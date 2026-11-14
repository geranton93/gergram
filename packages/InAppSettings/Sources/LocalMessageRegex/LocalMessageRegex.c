#include "LocalMessageRegex.h"

#include <stdatomic.h>
#include <stdlib.h>
#include <time.h>
#include <unicode/uregex.h>

struct LocalMessageRegexBudget {
    atomic_bool cancelled;
    uint64_t deadline;
    uint32_t comparisons;
};

static uint64_t monotonicNanoseconds(void) {
    struct timespec value;
    if (clock_gettime(CLOCK_MONOTONIC, &value) != 0) {
        return 0;
    }
    return (uint64_t)value.tv_sec * 1000000000 + (uint64_t)value.tv_nsec;
}

LocalMessageRegexHandle *localMessageRegexOpen(const uint16_t *pattern, int32_t length, bool caseInsensitive) {
    if (length <= 0) {
        return NULL;
    }
    UErrorCode status = U_ZERO_ERROR;
    uint32_t options = UREGEX_MULTILINE | (caseInsensitive ? UREGEX_CASE_INSENSITIVE : 0);
    URegularExpression *expression = uregex_open((const UChar *)pattern, length, options, NULL, &status);
    if (expression != NULL && U_SUCCESS(status)) {
        uregex_setTimeLimit(expression, 64, &status);
        uregex_setStackLimit(expression, 256 * 1024, &status);
    }
    if (expression == NULL || U_FAILURE(status)) {
        if (expression != NULL) {
            uregex_close(expression);
        }
        return NULL;
    }
    return (LocalMessageRegexHandle *)expression;
}

void localMessageRegexClose(LocalMessageRegexHandle *expression) {
    uregex_close((URegularExpression *)expression);
}

LocalMessageRegexBudget *localMessageRegexBudgetCreate(void) {
    LocalMessageRegexBudget *budget = calloc(1, sizeof(*budget));
    if (budget != NULL) {
        atomic_init(&budget->cancelled, false);
    }
    return budget;
}

void localMessageRegexBudgetDestroy(LocalMessageRegexBudget *budget) {
    free(budget);
}

void localMessageRegexBudgetStart(LocalMessageRegexBudget *budget, uint32_t milliseconds, uint32_t comparisons) {
    budget->deadline = monotonicNanoseconds() + (uint64_t)milliseconds * 1000000;
    budget->comparisons = comparisons;
}

void localMessageRegexBudgetCancel(LocalMessageRegexBudget *budget) {
    atomic_store_explicit(&budget->cancelled, true, memory_order_relaxed);
}

bool localMessageRegexBudgetIsCancelled(const LocalMessageRegexBudget *budget) {
    return atomic_load_explicit(&budget->cancelled, memory_order_relaxed);
}

bool localMessageRegexBudgetHasTime(const LocalMessageRegexBudget *budget) {
    return !localMessageRegexBudgetIsCancelled(budget) && monotonicNanoseconds() < budget->deadline;
}

bool localMessageRegexBudgetCanMatch(const LocalMessageRegexBudget *budget) {
    return budget->comparisons > 0 && localMessageRegexBudgetHasTime(budget);
}

static UBool checkMatch(const void *context, int32_t steps) {
    (void)steps;
    return (UBool)localMessageRegexBudgetHasTime(context);
}

static UBool checkFind(const void *context, int64_t matchIndex) {
    (void)matchIndex;
    return (UBool)localMessageRegexBudgetHasTime(context);
}

int32_t localMessageRegexFind(LocalMessageRegexHandle *expression, const uint16_t *text, int32_t length, LocalMessageRegexBudget *budget) {
    if (!localMessageRegexBudgetCanMatch(budget) || length <= 0) {
        return -1;
    }
    budget->comparisons--;
    URegularExpression *regex = (URegularExpression *)expression;
    UErrorCode status = U_ZERO_ERROR;
    uregex_setMatchCallback(regex, checkMatch, budget, &status);
    uregex_setFindProgressCallback(regex, checkFind, budget, &status);
    uregex_setText(regex, (const UChar *)text, length, &status);
    UBool result = uregex_find(regex, 0, &status);

    static const UChar emptyText[] = {0};
    UErrorCode resetStatus = U_ZERO_ERROR;
    uregex_setMatchCallback(regex, NULL, NULL, &resetStatus);
    uregex_setFindProgressCallback(regex, NULL, NULL, &resetStatus);
    uregex_setText(regex, emptyText, 0, &resetStatus);
    if (U_FAILURE(status) || U_FAILURE(resetStatus) || !localMessageRegexBudgetHasTime(budget)) {
        return -1;
    }
    return result ? 1 : 0;
}

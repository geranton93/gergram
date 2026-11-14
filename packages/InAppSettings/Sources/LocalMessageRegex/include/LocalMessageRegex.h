#ifndef LocalMessageRegex_h
#define LocalMessageRegex_h

#include <stdbool.h>
#include <stdint.h>

typedef struct LocalMessageRegexHandle LocalMessageRegexHandle;
typedef struct LocalMessageRegexBudget LocalMessageRegexBudget;

LocalMessageRegexHandle * _Nullable localMessageRegexOpen(const uint16_t * _Nonnull pattern, int32_t length, bool caseInsensitive);
void localMessageRegexClose(LocalMessageRegexHandle * _Nonnull expression);

LocalMessageRegexBudget * _Nullable localMessageRegexBudgetCreate(void);
void localMessageRegexBudgetDestroy(LocalMessageRegexBudget * _Nonnull budget);
void localMessageRegexBudgetStart(LocalMessageRegexBudget * _Nonnull budget, uint32_t milliseconds, uint32_t comparisons);
void localMessageRegexBudgetCancel(LocalMessageRegexBudget * _Nonnull budget);
bool localMessageRegexBudgetIsCancelled(const LocalMessageRegexBudget * _Nonnull budget);
bool localMessageRegexBudgetHasTime(const LocalMessageRegexBudget * _Nonnull budget);
bool localMessageRegexBudgetCanMatch(const LocalMessageRegexBudget * _Nonnull budget);

int32_t localMessageRegexFind(LocalMessageRegexHandle * _Nonnull expression, const uint16_t * _Nonnull text, int32_t length, LocalMessageRegexBudget * _Nonnull budget);

#endif

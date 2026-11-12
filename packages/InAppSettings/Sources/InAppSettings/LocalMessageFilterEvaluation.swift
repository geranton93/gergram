import LocalMessageRegex

private final class LocalMessageFilterPattern {
    let expression: OpaquePointer
    let reversed: Bool

    init?(_ rule: LocalMessageFilterRule) {
        let maximumLength = LocalMessageFilterEvaluation.maximumPatternLength
        let units = Array(rule.pattern.utf16.prefix(maximumLength + 1))
        guard !units.isEmpty, units.count <= maximumLength,
              let expression = units.withUnsafeBufferPointer({ buffer -> OpaquePointer? in
                  guard let address = buffer.baseAddress else { return nil }
                  return localMessageRegexOpen(address, Int32(buffer.count), rule.isCaseInsensitive)
              }) else { return nil }
        self.expression = expression
        self.reversed = rule.isReversed
    }

    deinit {
        localMessageRegexClose(expression)
    }
}

public final class LocalMessageFilterEvaluation {
    public static let maximumPatternLength = 256
    public static let maximumInputLength = 8192

    private let budget: OpaquePointer
    private let milliseconds: UInt32
    private let comparisons: UInt32
    private var patterns: [LocalMessageFilterPattern] = []

    public convenience init?() {
        self.init(milliseconds: 35, comparisons: 4096)
    }

    init?(milliseconds: UInt32, comparisons: UInt32) {
        guard let budget = localMessageRegexBudgetCreate() else { return nil }
        self.budget = budget
        self.milliseconds = milliseconds
        self.comparisons = comparisons
    }

    deinit {
        localMessageRegexBudgetDestroy(budget)
    }

    public static func isValid(_ rule: LocalMessageFilterRule) -> Bool {
        LocalMessageFilterPattern(rule) != nil
    }

    public var canEvaluate: Bool {
        !patterns.isEmpty && localMessageRegexBudgetCanMatch(budget)
    }

    public var isCancelled: Bool {
        localMessageRegexBudgetIsCancelled(budget)
    }

    public func cancel() {
        localMessageRegexBudgetCancel(budget)
    }

    public func prepare(_ rules: [LocalMessageFilterRule]) {
        localMessageRegexBudgetStart(budget, milliseconds, comparisons)
        patterns.removeAll(keepingCapacity: true)
        for rule in rules.prefix(LocalMessageFilterPreferences.maximumRules) where rule.isEnabled {
            guard localMessageRegexBudgetHasTime(budget) else { break }
            if let pattern = LocalMessageFilterPattern(rule) {
                patterns.append(pattern)
            }
        }
    }

    public func shouldHide(_ input: String) -> Bool {
        guard canEvaluate else { return false }
        let text = Array(input.utf16.prefix(Self.maximumInputLength + 1))
        guard !text.isEmpty, text.count <= Self.maximumInputLength else { return false }
        return text.withUnsafeBufferPointer { buffer in
            guard let address = buffer.baseAddress else { return false }
            for pattern in patterns {
                guard localMessageRegexBudgetCanMatch(budget) else { return false }
                let result = localMessageRegexFind(pattern.expression, address, Int32(buffer.count), budget)
                if result >= 0, (result == 1) != pattern.reversed {
                    return true
                }
            }
            return false
        }
    }
}

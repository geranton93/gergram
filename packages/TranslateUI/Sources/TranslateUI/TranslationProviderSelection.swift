enum TranslationProvider: Hashable {
    case telegram
    case google
}

struct TranslationProviderSelection: Equatable {
    private(set) var provider: TranslationProvider = .telegram
    private(set) var isGoogleAvailable = false

    mutating func setGoogleAvailability(_ available: Bool) {
        isGoogleAvailable = available
        if !available {
            provider = .telegram
        }
    }

    @discardableResult
    mutating func select(_ provider: TranslationProvider, confirmedGoogleConsent: Bool = false) -> Bool {
        guard self.provider != provider else { return false }
        if provider == .google, !isGoogleAvailable || !confirmedGoogleConsent {
            return false
        }
        self.provider = provider
        return true
    }
}

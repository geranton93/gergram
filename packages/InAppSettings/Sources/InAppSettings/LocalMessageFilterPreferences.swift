import Postbox
import SwiftSignalKit

public func localMessageFilterPreferences(_ postbox: Postbox) -> Signal<LocalMessageFilterPreferences, NoError> {
    let key = ApplicationSpecificPreferencesKeys.localMessageFilters
    return postbox.preferencesView(keys: [key]) |> map { view in
        return view.values[key]?.get(LocalMessageFilterPreferences.self) ?? LocalMessageFilterPreferences()
    } |> distinctUntilChanged
}

public func updateLocalMessageFilterPreferences<Result>(_ postbox: Postbox, _ update: @escaping (inout LocalMessageFilterPreferences) -> Result) -> Signal<Result, NoError> {
    return postbox.transaction { transaction in
        updateLocalMessageFilterPreferences(transaction, update)
    }
}

public func updateLocalMessageFilterPreferences<Result>(_ transaction: Transaction, _ update: (inout LocalMessageFilterPreferences) -> Result) -> Result {
    let key = ApplicationSpecificPreferencesKeys.localMessageFilters
    let previous = transaction.getPreferencesEntry(key: key)?.get(LocalMessageFilterPreferences.self) ?? LocalMessageFilterPreferences()
    var updated = previous
    let result = update(&updated)
    if updated != previous {
        transaction.updatePreferencesEntry(key: key) { _ in PreferencesEntry(updated) }
    }
    return result
}

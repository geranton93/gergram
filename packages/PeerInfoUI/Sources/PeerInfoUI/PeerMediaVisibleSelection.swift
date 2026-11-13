func peerMediaVisibleSelection<Mode: Equatable>(selected: Mode?, initial: Mode?, visible: [Mode], preferredOrder: [Mode], isAllowed: (Mode) -> Bool) -> Mode? {
    guard let selected else {
        return initial.flatMap { isAllowed($0) ? $0 : nil } ?? visible.first
    }
    if visible.contains(selected) {
        return selected
    }
    if let index = preferredOrder.firstIndex(of: selected),
       let earlier = preferredOrder[...index].reversed().first(where: visible.contains) {
        return earlier
    }
    return visible.last ?? (isAllowed(selected) ? selected : nil)
}

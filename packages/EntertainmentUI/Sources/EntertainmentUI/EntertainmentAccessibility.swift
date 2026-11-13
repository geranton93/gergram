import Cocoa
import TGUIKit

struct EntertainmentAccessibilityAction {
    let name: String
    let perform: () -> Bool
}

struct EntertainmentAccessibilityCell {
    let id: AnyHashable
    let label: String
    let frame: NSRect
    let isSelected: Bool
    let alternateAction: EntertainmentAccessibilityAction?
    let press: () -> Void

    init(id: AnyHashable, label: String, frame: NSRect, isSelected: Bool = false, alternateAction: EntertainmentAccessibilityAction? = nil, press: @escaping () -> Void) {
        self.id = id
        self.label = label
        self.frame = frame
        self.isSelected = isSelected
        self.alternateAction = alternateAction
        self.press = press
    }
}

final class EntertainmentAccessibilityCellElement: NSAccessibilityElement {
    weak var view: NSView?
    var frameInView: NSRect = .zero
    var press: (() -> Void)?
    var selected: Bool = false

    override func isAccessibilityElement() -> Bool {
        return true
    }

    override func accessibilityFrame() -> NSRect {
        guard let view = view else {
            return .zero
        }
        return NSAccessibility.screenRect(fromView: view, rect: frameInView)
    }

    override func isAccessibilitySelected() -> Bool {
        return selected
    }

    override func accessibilityPerformPress() -> Bool {
        guard let press = press else {
            return false
        }
        press()
        return true
    }
}

final class EntertainmentAccessibilityCells {
    private var elements: [AnyHashable: EntertainmentAccessibilityCellElement] = [:]

    func elements(for cells: [EntertainmentAccessibilityCell], in view: NSView) -> [Any] {
        var result: [Any] = []
        var alive: [AnyHashable: EntertainmentAccessibilityCellElement] = [:]
        for cell in cells {
            let element = elements[cell.id] ?? EntertainmentAccessibilityCellElement()
            element.view = view
            element.setAccessibilityParent(view)
            element.setAccessibilityRole(.button)
            element.setAccessibilityLabel(cell.label)
            element.frameInView = cell.frame
            element.selected = cell.isSelected
            element.press = cell.press
            element.setAccessibilityCustomActions(cell.alternateAction.map { [NSAccessibilityCustomAction(name: $0.name, handler: $0.perform)] })
            alive[cell.id] = element
            result.append(element)
        }
        for (id, element) in elements where alive[id] == nil {
            element.press = nil
            element.setAccessibilityCustomActions(nil)
        }
        elements = alive
        return result
    }
}

final class EntertainmentGridControl: Control {
    var accessibilityCells: (() -> [EntertainmentAccessibilityCell])?
    private let cellElements = EntertainmentAccessibilityCells()

    override func isAccessibilityElement() -> Bool {
        return false
    }

    override func accessibilityChildren() -> [Any]? {
        var children = super.accessibilityChildren() ?? []
        guard TGUIKitAccessibility.isEnabled, let cells = accessibilityCells?() else {
            return children
        }
        children.append(contentsOf: cellElements.elements(for: cells, in: self))
        return children
    }
}

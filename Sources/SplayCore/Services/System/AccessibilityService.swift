// macOS-only: AX trust prompt; no equivalent on iOS.
// See docs/plans/splay-ios-utility-layer.md (slice 1).
#if os(macOS)
import ApplicationServices
import Foundation

public protocol AccessibilityServiceProtocol: Sendable {
    func getSelectedTextWithSource(maxCharacters: Int?) throws -> (String, AccessibilitySelectionSource)
    func getSelectedText(maxCharacters: Int?) throws -> String
}

public extension AccessibilityServiceProtocol {
    func getSelectedTextWithSource() throws -> (String, AccessibilitySelectionSource) {
        try getSelectedTextWithSource(maxCharacters: nil)
    }

    func getSelectedText() throws -> String {
        try getSelectedText(maxCharacters: nil)
    }
}

/// Whether the focused element will take a paste. fn dictation asks this before
/// synthesising ⌘V: a paste into nothing is silently lost, so a non-editable
/// focus keeps the text on the clipboard instead. `role` is for the log, so a
/// wrong "not editable" call can be traced to the app/element that caused it.
public struct AccessibilityPasteTarget: Sendable, Equatable {
    public enum Verdict: String, Sendable {
        case editable
        case notEditable = "not_editable"
        /// Accessibility isn't granted, so the focus can't be read.
        case unknown
    }

    public let verdict: Verdict
    public let role: String?

    public init(verdict: Verdict, role: String?) {
        self.verdict = verdict
        self.role = role
    }
}

public enum AccessibilitySelectionSource: String, Sendable, Equatable {
    case selectedTextAttribute
    case parameterizedString
    case valueSubstring
}

public enum AccessibilityServiceError: Error, LocalizedError, Equatable {
    case notAuthorized
    case noFocusedElement
    case noSelectedText
    case textTooLong(max: Int, actual: Int)
    case unsupportedElement

    public var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Accessibility permission is required to read selected text."
        case .noFocusedElement:
            return "No focused text field was found."
        case .noSelectedText:
            return "Select text first."
        case .textTooLong(let max, let actual):
            return "Selection is too long (\(actual) chars). Maximum is \(max)."
        case .unsupportedElement:
            return "The focused element does not expose selected text."
        }
    }
}

protocol AccessibilityBackend: Sendable {
    func isTrusted() -> Bool
    func focusedElement() -> AXUIElement?
    func selectedText(of element: AXUIElement) -> String?
    func selectedRange(of element: AXUIElement) -> CFRange?
    func fullValue(of element: AXUIElement) -> String?
    func string(for range: CFRange, of element: AXUIElement) -> String?
    func role(of element: AXUIElement) -> String?
    func isEditable(_ element: AXUIElement) -> Bool
    func isSelectedRangeSettable(of element: AXUIElement) -> Bool
}

struct SystemAccessibilityBackend: AccessibilityBackend {
    func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    func focusedElement() -> AXUIElement? {
        let systemElement = AXUIElementCreateSystemWide()
        guard let value = copyAttributeValue(
            element: systemElement,
            attribute: kAXFocusedUIElementAttribute as CFString
        ) else {
            return nil
        }

        guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeDowncast(value as AnyObject, to: AXUIElement.self)
    }

    func selectedText(of element: AXUIElement) -> String? {
        guard let value = copyAttributeValue(
            element: element,
            attribute: kAXSelectedTextAttribute as CFString
        ) else {
            return nil
        }
        return value as? String
    }

    func selectedRange(of element: AXUIElement) -> CFRange? {
        guard let value = copyAttributeValue(
            element: element,
            attribute: kAXSelectedTextRangeAttribute as CFString
        ) else {
            return nil
        }

        guard CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = unsafeDowncast(value as AnyObject, to: AXValue.self)
        guard AXValueGetType(axValue) == .cfRange else {
            return nil
        }

        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else {
            return nil
        }
        return range
    }

    func fullValue(of element: AXUIElement) -> String? {
        guard let value = copyAttributeValue(
            element: element,
            attribute: kAXValueAttribute as CFString
        ) else {
            return nil
        }
        return value as? String
    }

    func string(for range: CFRange, of element: AXUIElement) -> String? {
        var mutableRange = range
        guard let rangeValue = AXValueCreate(.cfRange, &mutableRange) else {
            return nil
        }

        var raw: CFTypeRef?
        let status = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            rangeValue,
            &raw
        )
        guard status == .success, let raw else {
            return nil
        }
        return raw as? String
    }

    func role(of element: AXUIElement) -> String? {
        copyAttributeValue(element: element, attribute: kAXRoleAttribute as CFString) as? String
    }

    /// WebKit/Chromium mark contenteditable regions with `AXEditable`.
    func isEditable(_ element: AXUIElement) -> Bool {
        (copyAttributeValue(element: element, attribute: "AXEditable" as CFString) as? Bool) ?? false
    }

    func isSelectedRangeSettable(of element: AXUIElement) -> Bool {
        var settable: DarwinBoolean = false
        let status = AXUIElementIsAttributeSettable(
            element, kAXSelectedTextRangeAttribute as CFString, &settable
        )
        return status == .success && settable.boolValue
    }

    private func copyAttributeValue(element: AXUIElement, attribute: CFString) -> CFTypeRef? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard status == .success else {
            return nil
        }
        return value
    }
}

public final class AccessibilityService: AccessibilityServiceProtocol, @unchecked Sendable {
    private let backend: any AccessibilityBackend
    private let defaultMaxCharacters: Int

    public init(defaultMaxCharacters: Int = 16_000) {
        self.defaultMaxCharacters = defaultMaxCharacters
        self.backend = SystemAccessibilityBackend()
    }

    init(
        defaultMaxCharacters: Int = 16_000,
        backend: any AccessibilityBackend
    ) {
        self.defaultMaxCharacters = defaultMaxCharacters
        self.backend = backend
    }

    private static let textRoles: Set<String> = [
        kAXTextFieldRole as String, kAXTextAreaRole as String,
        kAXComboBoxRole as String, "AXSearchField",
    ]

    public func focusedPasteTarget() -> AccessibilityPasteTarget {
        guard backend.isTrusted() else { return AccessibilityPasteTarget(verdict: .unknown, role: nil) }
        guard let element = backend.focusedElement() else {
            return AccessibilityPasteTarget(verdict: .notEditable, role: nil)
        }
        let role = backend.role(of: element)
        let editable = role.map(Self.textRoles.contains) == true
            || backend.isEditable(element)
            || backend.isSelectedRangeSettable(of: element)
        return AccessibilityPasteTarget(verdict: editable ? .editable : .notEditable, role: role)
    }

    public func getSelectedText(maxCharacters: Int?) throws -> String {
        try getSelectedTextWithSource(maxCharacters: maxCharacters).0
    }

    public func getSelectedTextWithSource(maxCharacters: Int?) throws -> (String, AccessibilitySelectionSource) {
        let max = maxCharacters ?? defaultMaxCharacters
        guard backend.isTrusted() else {
            throw AccessibilityServiceError.notAuthorized
        }
        guard let element = backend.focusedElement() else {
            throw AccessibilityServiceError.noFocusedElement
        }

        if let direct = normalized(backend.selectedText(of: element)), !direct.isEmpty {
            return (try validatedLength(direct, max: max), .selectedTextAttribute)
        }

        guard let range = backend.selectedRange(of: element) else {
            throw AccessibilityServiceError.unsupportedElement
        }
        guard range.length > 0 else {
            throw AccessibilityServiceError.noSelectedText
        }

        if let parameterized = normalized(backend.string(for: range, of: element)), !parameterized.isEmpty {
            return (try validatedLength(parameterized, max: max), .parameterizedString)
        }

        guard let value = backend.fullValue(of: element) else {
            throw AccessibilityServiceError.unsupportedElement
        }

        let ns = value as NSString
        let nsRange = NSRange(location: range.location, length: range.length)
        guard nsRange.location >= 0,
              nsRange.length >= 0,
              nsRange.location + nsRange.length <= ns.length else {
            throw AccessibilityServiceError.unsupportedElement
        }

        guard let extracted = normalized(ns.substring(with: nsRange)), !extracted.isEmpty else {
            throw AccessibilityServiceError.noSelectedText
        }
        return (try validatedLength(extracted, max: max), .valueSubstring)
    }

    private func normalized(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func validatedLength(_ text: String, max: Int) throws -> String {
        if text.count > max {
            throw AccessibilityServiceError.textTooLong(max: max, actual: text.count)
        }
        return text
    }
}
#endif

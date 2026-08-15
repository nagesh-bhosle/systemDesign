//
//  FocusedFieldInspector.swift
//  VoiceDictation
//
//  Best-effort AX inspection of the focused UI element.
//

import ApplicationServices

enum FocusedFieldInspector {
    /// Returns true when the focused element appears to be a secure/password field.
    static func isFocusedFieldSecure() -> Bool {
        guard AXIsProcessTrusted() else { return false }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedObject: CFTypeRef?
        let focusStatus = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedObject
        )
        guard focusStatus == .success, let focusedObject else { return false }

        // AXUIElement is a typealias for CFTypeRef; the force cast is safe and
        // the compiler requires it for toll-free-bridged Core Foundation types.
        let element = focusedObject as! AXUIElement
        var roleObject: CFTypeRef?
        let roleStatus = AXUIElementCopyAttributeValue(
            element,
            kAXRoleAttribute as CFString,
            &roleObject
        )
        guard roleStatus == .success, let role = roleObject as? String else { return false }

        if role == "AXSecureTextField" { return true }
        if role.localizedCaseInsensitiveContains("Secure") { return true }
        return false
    }
}

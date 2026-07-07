import Carbon.HIToolbox
import Foundation
import LeafiyUICore

final class HotKeyCenter {
    var onActivate: (() -> Void)?
    var onRegisterFailed: ((String, OSStatus) -> Void)?

    private var eventHandler: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerUPP: EventHandlerUPP?

    func register(shortcut: String) {
        unregister()

        guard let parsed = Self.parseShortcut(shortcut) else {
            NSLog("Fifi hotkey shortcut is unsupported: %@", shortcut)
            return
        }

        handlerUPP = { _, event, userData in
            guard let event, let userData else { return noErr }

            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr else { return status }
            guard hotKeyID.signature == HotKeyCenter.fourCharacterCode("FIFI"), hotKeyID.id == 1 else { return noErr }

            let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
            NSLog("Fifi[hotkey] fired")
            // Synchronous on purpose: the Carbon handler runs on the main thread
            // during event dispatch, and macOS 14+ only honors NSApp.activate
            // while the triggering user-input event context is still current.
            // An async hop loses that context and activation gets denied.
            center.onActivate?()
            return noErr
        }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            handlerUPP,
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandler
        )
        guard handlerStatus == noErr else {
            NSLog("Fifi failed to install hotkey handler: %d", handlerStatus)
            handlerUPP = nil
            return
        }

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.fourCharacterCode("FIFI"), id: 1)
        let registerStatus = RegisterEventHotKey(
            parsed.keyCode,
            parsed.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if registerStatus == noErr, let ref {
            hotKeyRef = ref
            NSLog("Fifi[hotkey] registered %@", shortcut)
        } else {
            NSLog("Fifi[hotkey] register FAILED %@ status=%d (another app may already own this shortcut)", shortcut, registerStatus)
            onRegisterFailed?(shortcut, registerStatus)
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        handlerUPP = nil
    }

    static func isShortcutSupported(_ shortcut: String) -> Bool {
        parseShortcut(shortcut) != nil
    }

    private static func fourCharacterCode(_ string: String) -> OSType {
        string.utf8.reduce(0) { ($0 << 8) + OSType($1) }
    }

    private static func parseShortcut(_ shortcut: String) -> (keyCode: UInt32, modifiers: UInt32)? {
        guard let spec = KeyboardShortcutSpec(parsing: shortcut),
              let keyCode = keyCode(for: spec.key) else {
            return nil
        }

        var modifiers: UInt32 = 0
        for modifier in [spec.first, spec.second] {
            modifiers |= carbonFlags(for: modifier)
        }
        return (UInt32(keyCode), modifiers)
    }

    private static func carbonFlags(for modifier: KeyboardShortcutSpec.Modifier) -> UInt32 {
        switch modifier {
        case .command:
            return UInt32(cmdKey)
        case .shift:
            return UInt32(shiftKey)
        case .option:
            return UInt32(optionKey)
        case .control:
            return UInt32(controlKey)
        }
    }

    private static func keyCode(for key: String) -> Int? {
        let keys: [String: Int] = [
            "A": kVK_ANSI_A, "B": kVK_ANSI_B, "C": kVK_ANSI_C, "D": kVK_ANSI_D,
            "E": kVK_ANSI_E, "F": kVK_ANSI_F, "G": kVK_ANSI_G, "H": kVK_ANSI_H,
            "I": kVK_ANSI_I, "J": kVK_ANSI_J, "K": kVK_ANSI_K, "L": kVK_ANSI_L,
            "M": kVK_ANSI_M, "N": kVK_ANSI_N, "O": kVK_ANSI_O, "P": kVK_ANSI_P,
            "Q": kVK_ANSI_Q, "R": kVK_ANSI_R, "S": kVK_ANSI_S, "T": kVK_ANSI_T,
            "U": kVK_ANSI_U, "V": kVK_ANSI_V, "W": kVK_ANSI_W, "X": kVK_ANSI_X,
            "Y": kVK_ANSI_Y, "Z": kVK_ANSI_Z,
            "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
            "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7,
            "8": kVK_ANSI_8, "9": kVK_ANSI_9
        ]
        return keys[key]
    }

    deinit {
        unregister()
    }
}

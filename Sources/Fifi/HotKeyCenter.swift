import Carbon.HIToolbox
import Foundation

final class HotKeyCenter {
    var onActivate: (() -> Void)?

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
        } else {
            NSLog("Fifi failed to register hotkey %@: %d", shortcut, registerStatus)
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
        let tokens = shortcut
            .replacingOccurrences(of: "⌘", with: "command+")
            .replacingOccurrences(of: "⇧", with: "shift+")
            .replacingOccurrences(of: "⌥", with: "option+")
            .replacingOccurrences(of: "⌃", with: "control+")
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        guard tokens.count >= 2, let keyToken = tokens.last, let keyCode = keyCode(for: keyToken) else { return nil }

        var modifiers: UInt32 = 0
        for token in tokens.dropLast() {
            switch token {
            case "cmd", "command":
                modifiers |= UInt32(cmdKey)
            case "shift":
                modifiers |= UInt32(shiftKey)
            case "option", "alt":
                modifiers |= UInt32(optionKey)
            case "ctrl", "control":
                modifiers |= UInt32(controlKey)
            default:
                return nil
            }
        }

        guard modifiers != 0 else { return nil }
        return (UInt32(keyCode), modifiers)
    }

    private static func keyCode(for token: String) -> Int? {
        let keys: [String: Int] = [
            "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D,
            "e": kVK_ANSI_E, "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H,
            "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
            "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P,
            "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
            "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
            "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
            "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
            "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7,
            "8": kVK_ANSI_8, "9": kVK_ANSI_9,
            "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4,
            "f5": kVK_F5, "f6": kVK_F6, "f7": kVK_F7, "f8": kVK_F8,
            "f9": kVK_F9, "f10": kVK_F10, "f11": kVK_F11, "f12": kVK_F12,
            "space": kVK_Space,
            "tab": kVK_Tab,
            "return": kVK_Return, "enter": kVK_Return,
            "escape": kVK_Escape, "esc": kVK_Escape,
            "delete": kVK_Delete, "del": kVK_Delete,
            "left": kVK_LeftArrow,
            "right": kVK_RightArrow,
            "up": kVK_UpArrow,
            "down": kVK_DownArrow,
            "comma": kVK_ANSI_Comma,
            "period": kVK_ANSI_Period, "dot": kVK_ANSI_Period,
            "slash": kVK_ANSI_Slash,
            "semicolon": kVK_ANSI_Semicolon,
            "quote": kVK_ANSI_Quote, "apostrophe": kVK_ANSI_Quote,
            "backslash": kVK_ANSI_Backslash,
            "minus": kVK_ANSI_Minus, "hyphen": kVK_ANSI_Minus,
            "equal": kVK_ANSI_Equal, "equals": kVK_ANSI_Equal,
            "leftbracket": kVK_ANSI_LeftBracket,
            "rightbracket": kVK_ANSI_RightBracket,
            "grave": kVK_ANSI_Grave, "backtick": kVK_ANSI_Grave
        ]
        return keys[token]
    }

    deinit {
        unregister()
    }
}

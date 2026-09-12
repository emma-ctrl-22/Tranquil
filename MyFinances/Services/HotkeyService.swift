import AppKit
import Carbon.HIToolbox

/// The ⌥⌘E global hotkey.
///
/// Uses Carbon's `RegisterEventHotKey`, which works system-wide **without** Accessibility
/// permission — unlike an event tap. Nothing is observed or recorded; the OS simply calls
/// back when this one combination is pressed.
final class HotkeyService {
    static let shared = HotkeyService()

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var onPress: (() -> Void)?

    private init() {}

    var isRegistered: Bool { hotKeyRef != nil }

    /// Registers ⌥⌘E. Returns false if something else already owns the combination —
    /// the app carries on without it rather than failing to launch.
    @discardableResult
    func register(onPress: @escaping () -> Void) -> Bool {
        unregister()
        self.onPress = onPress

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, event, userData in
            guard let userData else { return noErr }
            var pressedID = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &pressedID
            )
            guard status == noErr, pressedID.id == HotkeyService.signatureID else { return noErr }
            let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { service.onPress?() }
            return noErr
        }

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(
            GetApplicationEventTarget(), callback, 1, &eventType, selfPointer, &handlerRef
        )
        guard installed == noErr else { return false }

        let hotKeyID = EventHotKeyID(signature: HotkeyService.signature, id: HotkeyService.signatureID)
        let registered = RegisterEventHotKey(
            UInt32(kVK_ANSI_E),
            UInt32(optionKey | cmdKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard registered == noErr else {
            unregister()
            return false
        }
        return true
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
    }

    /// 'TRNQ'
    private static let signature: OSType = 0x54524E51
    private static let signatureID: UInt32 = 1
}

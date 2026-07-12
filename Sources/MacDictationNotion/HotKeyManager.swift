import AppKit
import Carbon.HIToolbox

final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    var onTrigger: (() -> Void)?

    func register(keyCode: UInt32 = UInt32(kVK_ANSI_D),
                  modifiers: UInt32 = UInt32(cmdKey | shiftKey)) {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref); hotKeyRef = nil }

        if eventHandlerRef == nil {
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                          eventKind: UInt32(kEventHotKeyPressed))
            let selfPtr = Unmanaged.passUnretained(self).toOpaque()
            InstallEventHandler(
                GetApplicationEventTarget(),
                { (_, _, userData) -> OSStatus in
                    guard let userData = userData else { return OSStatus(eventNotHandledErr) }
                    Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue().onTrigger?()
                    return noErr
                },
                1, &eventType, selfPtr, &eventHandlerRef
            )
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x4D444E54), id: 1)
        RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let ref = hotKeyRef      { UnregisterEventHotKey(ref); hotKeyRef = nil }
        if let ref = eventHandlerRef { RemoveEventHandler(ref); eventHandlerRef = nil }
    }
}

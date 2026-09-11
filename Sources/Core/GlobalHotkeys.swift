import Carbon.HIToolbox
import Foundation

/// 自定全局快捷键（Carbon RegisterEventHotKey，无需任何权限）：
///   ⌥⌘↑ / ⌥⌘↓ 调亮度。（预设故意不做快捷键，避免和系统/其它 App 抢键。）
final class GlobalHotkeys {
    static let shared = GlobalHotkeys()

    var onBrightnessUp: (() -> Void)?
    var onBrightnessDown: (() -> Void)?

    private var handlerRef: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var isRunning = false

    private static let signature: OSType = 0x44_50_4C_54 // 'DPLT'

    private init() {}

    func start() {
        guard !isRunning else { return }
        isRunning = true

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                guard let event else { return OSStatus(eventNotHandledErr) }
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
                let slot = Int(hotKeyID.id)
                DispatchQueue.main.async {
                    switch slot {
                    case 0: GlobalHotkeys.shared.onBrightnessUp?()
                    case 1: GlobalHotkeys.shared.onBrightnessDown?()
                    default: break
                    }
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &handlerRef
        )

        let modifiers = UInt32(cmdKey | optionKey)
        register(keyCode: UInt32(kVK_UpArrow), modifiers: modifiers, id: 0)
        register(keyCode: UInt32(kVK_DownArrow), modifiers: modifiers, id: 1)
    }

    func stop() {
        for ref in hotKeyRefs { UnregisterEventHotKey(ref) }
        hotKeyRefs.removeAll()
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
        isRunning = false
    }

    private func register(keyCode: UInt32, modifiers: UInt32, id: UInt32) {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref { hotKeyRefs.append(ref) }
    }
}

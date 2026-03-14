import Carbon
import Foundation

@MainActor
final class HotKeyManager {
    private var quitHotKeyRef: EventHotKeyRef?
    private var minimizeHotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let quitHotKeyID = EventHotKeyID(signature: OSType(0x6A715154), id: 1)
    private let minimizeHotKeyID = EventHotKeyID(signature: OSType(0x6A715154), id: 2)
    private let quitHandler: () -> Void
    private let minimizeHandler: () -> Void
    private let supportsMinimizeHotKey: Bool
    private var quitEnabled = false
    private var minimizeEnabled = false

    init(
        supportsMinimizeHotKey: Bool,
        quitHandler: @escaping () -> Void,
        minimizeHandler: @escaping () -> Void
    ) {
        self.supportsMinimizeHotKey = supportsMinimizeHotKey
        self.quitHandler = quitHandler
        self.minimizeHandler = minimizeHandler
        installHandler()
    }

    func updateRegistration(quitEnabled: Bool, minimizeEnabled: Bool) {
        self.quitEnabled = quitEnabled
        self.minimizeEnabled = minimizeEnabled && supportsMinimizeHotKey
        register()
        unregisterDisabledHotKeys()
    }

    private func installHandler() {
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, userData in
                guard let userData, let eventRef else { return noErr }

                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                if hotKeyID.signature == manager.quitHotKeyID.signature && hotKeyID.id == manager.quitHotKeyID.id {
                    manager.quitHandler()
                } else if hotKeyID.signature == manager.minimizeHotKeyID.signature && hotKeyID.id == manager.minimizeHotKeyID.id {
                    manager.minimizeHandler()
                }

                return noErr
            },
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    private func register() {
        if quitEnabled, quitHotKeyRef == nil {
            RegisterEventHotKey(
                UInt32(kVK_ANSI_Q),
                UInt32(controlKey | optionKey),
                quitHotKeyID,
                GetApplicationEventTarget(),
                0,
                &quitHotKeyRef
            )
        }

        if minimizeEnabled, minimizeHotKeyRef == nil {
            RegisterEventHotKey(
                UInt32(kVK_DownArrow),
                UInt32(controlKey | optionKey),
                minimizeHotKeyID,
                GetApplicationEventTarget(),
                0,
                &minimizeHotKeyRef
            )
        }
    }

    private func unregisterDisabledHotKeys() {
        if !quitEnabled, let quitHotKeyRef {
            UnregisterEventHotKey(quitHotKeyRef)
            self.quitHotKeyRef = nil
        }

        if !minimizeEnabled, let minimizeHotKeyRef {
            UnregisterEventHotKey(minimizeHotKeyRef)
            self.minimizeHotKeyRef = nil
        }
    }
}

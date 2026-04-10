import AppKit
import Carbon
import Foundation

enum ShortcutCommand: CaseIterable {
    case toggleListening
    case toggleOverlay
    case toggleDisplayMode
    case fontUp
    case fontDown

    var keyEquivalent: String {
        switch self {
        case .toggleListening: return "l"
        case .toggleOverlay: return "o"
        case .toggleDisplayMode: return "d"
        case .fontUp: return "="
        case .fontDown: return "-"
        }
    }

    var displayShortcut: String {
        switch self {
        case .toggleListening: return "\u{2325}\u{2318}L"
        case .toggleOverlay: return "\u{2325}\u{2318}O"
        case .toggleDisplayMode: return "\u{2325}\u{2318}D"
        case .fontUp: return "\u{2325}\u{2318}="
        case .fontDown: return "\u{2325}\u{2318}-"
        }
    }

    var menuTitle: String {
        switch self {
        case .toggleListening: return "Start / Stop Listening"
        case .toggleOverlay: return "Toggle Overlay"
        case .toggleDisplayMode: return "Toggle Display Mode"
        case .fontUp: return "Increase Font Size"
        case .fontDown: return "Decrease Font Size"
        }
    }

    fileprivate var hotKeyID: UInt32 {
        switch self {
        case .toggleListening: return 1
        case .toggleOverlay: return 2
        case .toggleDisplayMode: return 3
        case .fontUp: return 4
        case .fontDown: return 5
        }
    }

    fileprivate var keyCode: UInt32 {
        switch self {
        case .toggleListening: return UInt32(kVK_ANSI_L)
        case .toggleOverlay: return UInt32(kVK_ANSI_O)
        case .toggleDisplayMode: return UInt32(kVK_ANSI_D)
        case .fontUp: return UInt32(kVK_ANSI_Equal)
        case .fontDown: return UInt32(kVK_ANSI_Minus)
        }
    }

    fileprivate var carbonModifiers: UInt32 {
        UInt32(optionKey | cmdKey)
    }
}

final class GlobalHotkeyManager {
    private static let signature: OSType = 0x4E_54_48_4B // "NTHK"

    private var hotKeyRefs: [ShortcutCommand: EventHotKeyRef] = [:]
    private var eventHandlerRef: EventHandlerRef?
    private let onCommand: (ShortcutCommand) -> Void

    private(set) var failedRegistrations: [ShortcutCommand] = []

    init(onCommand: @escaping (ShortcutCommand) -> Void) {
        self.onCommand = onCommand
    }

    deinit {
        unregisterAll()
    }

    func registerAll() {
        unregisterAll()
        installHandlerIfNeeded()

        var failed: [ShortcutCommand] = []
        for command in ShortcutCommand.allCases {
            var hotKeyRef: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: Self.signature, id: command.hotKeyID)
            let status = RegisterEventHotKey(
                command.keyCode,
                command.carbonModifiers,
                hotKeyID,
                GetEventDispatcherTarget(),
                0,
                &hotKeyRef
            )

            if status == noErr, let hotKeyRef {
                hotKeyRefs[command] = hotKeyRef
            } else {
                failed.append(command)
            }
        }

        failedRegistrations = failed
    }

    func unregisterAll() {
        for (_, hotKeyRef) in hotKeyRefs {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRefs.removeAll()

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }

        failedRegistrations = []
    }

    private func installHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, eventRef, userData in
                guard let userData, let eventRef else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                return manager.handleHotKeyPressed(eventRef)
            },
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandlerRef
        )

        if status != noErr {
            eventHandlerRef = nil
        }
    }

    private func handleHotKeyPressed(_ eventRef: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            eventRef,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr else { return status }
        guard hotKeyID.signature == Self.signature else { return OSStatus(eventNotHandledErr) }
        guard let command = ShortcutCommand.allCases.first(where: { $0.hotKeyID == hotKeyID.id }) else {
            return OSStatus(eventNotHandledErr)
        }

        DispatchQueue.main.async { [onCommand] in
            onCommand(command)
        }
        return noErr
    }
}

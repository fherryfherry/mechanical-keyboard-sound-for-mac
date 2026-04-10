//
//  KeyboardMonitor.swift
//  Mechanical Sound For Mac
//
//  Created by Codex.
//

import AppKit
import ApplicationServices
import Combine
import IOKit.hidsystem
import QuartzCore
import ServiceManagement
import SwiftUI

@MainActor
final class KeyboardMonitor: ObservableObject {
    enum GlobalCaptureStatus: Equatable {
        case inactive
        case active
        case failed

        var title: String {
            switch self {
            case .inactive:
                return "Global Capture: Off"
            case .active:
                return "Global Capture: Active"
            case .failed:
                return "Global Capture: Failed"
            }
        }

        var icon: String {
            switch self {
            case .inactive:
                return "minus.circle"
            case .active:
                return "checkmark.circle"
            case .failed:
                return "xmark.circle"
            }
        }
    }

    static let shared = KeyboardMonitor()

    private enum DefaultsKey {
        static let isEnabled = "keyboardMonitor.isEnabled"
        static let volume = "keyboardMonitor.volume"
        static let selectedSoundProfile = "keyboardMonitor.selectedSoundProfile"
        static let launchAtLogin = "keyboardMonitor.launchAtLogin"
        static let hasConfiguredLaunchAtLogin = "keyboardMonitor.hasConfiguredLaunchAtLogin"
        static let showKeyOverlay = "keyboardMonitor.showKeyOverlay"
        static let showComboPhrases = "keyboardMonitor.showComboPhrases"
        static let pointerSoundEnabled = "keyboardMonitor.pointerSoundEnabled"
    }

    private static let comboPhrases = [
        "Menyala abangku...",
        "Jari lu lagi possessed.",
        "Keyboard auto minta ampun.",
        "Ngetiknya lagi barbar.",
        "Kombo jalan terus bosku.",
        "Santai bang, tombolnya panas.",
        "RPM jari overlimit.",
        "Itu ngetik apa summon petir?",
        "Shift kiri ikut deg-degan.",
        "Tombol enter minta cuti.",
        "Spasi pun kena mental.",
        "Mesin ketik mode ultra.",
        "Ketikannya lagi savage.",
        "Ini mah combo tanpa jeda.",
        "Bara api dari fingertip.",
        "Keyboard jadi wajan panas.",
        "Tuts-nya auto kebakar.",
        "Layar ikut ngos-ngosan.",
        "Gokil, ritmenya dapet banget.",
        "Kayak speedrun nugas.",
        "Ketik terus jangan kasih kendor.",
        "Abang ini CPU jari.",
        "Combo-nya bikin merinding.",
        "Tuts kiri kanan kena rush.",
        "Bunyinya udah kayak turnamen.",
        "Ngoding sambil nyerang boss.",
        "Itu keyboard apa turbo jet?",
        "Jarinya lagi top form.",
        "Stack combo makin tebal.",
        "Api unggun lokal naik kelas.",
        "Tombol-tombol pada surrender.",
        "Input rate lagi horor.",
        "Ini baru namanya tempo.",
        "Ngetik sambil drifting.",
        "Akselerasi jari tidak wajar.",
        "Keyboard-nya kena critical hit.",
        "Panasnya sampai taskbar.",
        "Serangan beruntun tak terelakkan.",
        "Bara combo terus nyala.",
        "Bang, itu tangan atau makro?",
        "Tuts-nya lagi dihajar elegan.",
        "Ngetik cepat level legenda.",
        "Suhu meja ikut naik.",
        "Jarinya lagi mode ranked.",
        "Gila, ini kombo tak putus.",
        "Typing aura lagi full.",
        "Fire rate aman terkendali.",
        "Serem, ritmenya rapet.",
        "Keyboard bunyi sambil ketar-ketir.",
        "Kombo lucu tapi mengerikan."
    ]

    @Published var isEnabled = true {
        didSet {
            guard oldValue != isEnabled else { return }
            UserDefaults.standard.set(isEnabled, forKey: DefaultsKey.isEnabled)
            configureMonitoring()
        }
    }

    @Published var volume: Double = 0.85 {
        didSet {
            UserDefaults.standard.set(volume, forKey: DefaultsKey.volume)
            soundEngine.volume = Float(volume)
        }
    }

    @Published var selectedSoundProfile: KeyboardSoundEngine.SoundProfile = .cream {
        didSet {
            UserDefaults.standard.set(selectedSoundProfile.rawValue, forKey: DefaultsKey.selectedSoundProfile)
            soundEngine.selectedProfile = selectedSoundProfile
        }
    }

    @Published var launchAtLogin = false {
        didSet {
            guard oldValue != launchAtLogin else { return }
            UserDefaults.standard.set(launchAtLogin, forKey: DefaultsKey.launchAtLogin)
            UserDefaults.standard.set(true, forKey: DefaultsKey.hasConfiguredLaunchAtLogin)
            updateLaunchAtLoginRegistration()
        }
    }

    @Published var showKeyOverlay = true {
        didSet {
            guard oldValue != showKeyOverlay else { return }
            UserDefaults.standard.set(showKeyOverlay, forKey: DefaultsKey.showKeyOverlay)
            if !showKeyOverlay {
                KeyPressOverlayController.shared.hideImmediately()
            }
        }
    }

    @Published var showComboPhrases = true {
        didSet {
            guard oldValue != showComboPhrases else { return }
            UserDefaults.standard.set(showComboPhrases, forKey: DefaultsKey.showComboPhrases)
            if showComboPhrases {
                lastComboAnnouncementTimestamp = nil
                lastComboPhrase = nil
            }
        }
    }

    @Published var pointerSoundEnabled = true {
        didSet {
            guard oldValue != pointerSoundEnabled else { return }
            UserDefaults.standard.set(pointerSoundEnabled, forKey: DefaultsKey.pointerSoundEnabled)
        }
    }

    @Published private(set) var keystrokeCount = 0
    @Published private(set) var latestLatencyMilliseconds: Double = 0
    @Published private(set) var averageLatencyMilliseconds: Double = 0
    @Published private(set) var permissionStatus: PermissionStatus = .unknown
    @Published private(set) var isGlobalCaptureActive = false
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var inputMonitoringGranted = false
    @Published private(set) var globalCaptureStatus: GlobalCaptureStatus = .inactive

    var hasPermission: Bool {
        permissionStatus != .needsPermission
    }

    var bundlePath: String {
        Bundle.main.bundleURL.path
    }

    var isInstalledInApplications: Bool {
        let bundlePath = Bundle.main.bundleURL.standardizedFileURL.path
        let applicationRoots = [
            FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first,
            FileManager.default.urls(for: .applicationDirectory, in: .userDomainMask).first
        ].compactMap { $0?.standardizedFileURL.path }

        return applicationRoots.contains { bundlePath.hasPrefix($0 + "/") || bundlePath == $0 }
    }

    var installationHint: String? {
        guard !isInstalledInApplications else { return nil }
        return "Jalankan app dari folder Applications agar Input Monitoring lebih konsisten terdaftar di macOS."
    }

    var latestLatencyText: String {
        formattedLatency(latestLatencyMilliseconds)
    }

    var averageLatencyText: String {
        formattedLatency(averageLatencyMilliseconds)
    }

    private let soundEngine = KeyboardSoundEngine()
    private var localKeyDownMonitor: Any?
    private var localKeyUpMonitor: Any?
    private var localFlagsChangedMonitor: Any?
    private var localPointerDownMonitor: Any?
    private var localPointerUpMonitor: Any?
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private var permissionPollTimer: Timer?
    private var lastOverlayTimestamp: CFTimeInterval?
    private var rapidTypingStreak = 0
    private var lastComboAnnouncementTimestamp: CFTimeInterval?
    private var lastComboPhrase: String?

    private init() {
        restoreSettings()
        soundEngine.volume = Float(volume)
        soundEngine.selectedProfile = selectedSoundProfile
        soundEngine.onLatencyMeasured = { [weak self] latencyMilliseconds in
            Task { @MainActor in
                self?.recordLatency(latencyMilliseconds)
            }
        }
        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshPermissionStatus()
            }
        }
        updateLaunchAtLoginRegistration()
        refreshPermissionStatus()
        configureMonitoring()
    }

    func refreshPermissionStatus() {
        let previousAccessibility = accessibilityGranted
        let previousInputMonitoring = inputMonitoringGranted
        let previousPermissionStatus = permissionStatus

        accessibilityGranted = AXIsProcessTrusted()
        inputMonitoringGranted = hidListenEventAccessGranted()

        if accessibilityGranted && inputMonitoringGranted {
            permissionStatus = .granted
        } else {
            permissionStatus = .needsPermission
        }

        guard previousAccessibility != accessibilityGranted ||
            previousInputMonitoring != inputMonitoringGranted ||
            previousPermissionStatus != permissionStatus
        else {
            return
        }

        configureMonitoring()
    }

    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refreshPermissionStatus()
    }

    func requestInputMonitoringPermission() {
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        refreshPermissionStatus()
    }

    func requestPermission() {
        requestAccessibilityPermission()
        requestInputMonitoringPermission()
    }

    func startProfilePreview(_ profile: KeyboardSoundEngine.SoundProfile) {
        soundEngine.startPreview(for: profile)
    }

    func scheduleProfilePreview(_ profile: KeyboardSoundEngine.SoundProfile, delay: TimeInterval = 1.0) {
        soundEngine.schedulePreview(for: profile, delay: delay)
    }

    func stopProfilePreview() {
        soundEngine.stopPreview()
    }

    private func configureMonitoring() {
        stopMonitoring()
        guard isEnabled else { return }

        if permissionStatus == .granted {
            startGlobalEventTap()
            if isGlobalCaptureActive {
                return
            }
        }

        localKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
            return event
        }

        localKeyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            self?.handleKeyUpEvent(event)
            return event
        }

        localFlagsChangedMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChangedEvent(event)
            return event
        }

        localPointerDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            self?.handlePointerDownEvent(event)
            return event
        }

        localPointerUpMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp, .rightMouseUp, .otherMouseUp]) { [weak self] event in
            self?.handlePointerUpEvent(event)
            return event
        }

        // Without permission, only in-app typing can be monitored.
    }

    private func stopMonitoring() {
        isGlobalCaptureActive = false
        globalCaptureStatus = .inactive

        if let localKeyDownMonitor {
            NSEvent.removeMonitor(localKeyDownMonitor)
            self.localKeyDownMonitor = nil
        }

        if let localKeyUpMonitor {
            NSEvent.removeMonitor(localKeyUpMonitor)
            self.localKeyUpMonitor = nil
        }

        if let localFlagsChangedMonitor {
            NSEvent.removeMonitor(localFlagsChangedMonitor)
            self.localFlagsChangedMonitor = nil
        }

        if let localPointerDownMonitor {
            NSEvent.removeMonitor(localPointerDownMonitor)
            self.localPointerDownMonitor = nil
        }

        if let localPointerUpMonitor {
            NSEvent.removeMonitor(localPointerUpMonitor)
            self.localPointerUpMonitor = nil
        }

        if let eventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
            self.eventTapSource = nil
        }

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            self.eventTap = nil
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        guard isEnabled else { return }
        guard !event.isARepeat else { return }

        keystrokeCount += 1
        showKeyPressOverlay(for: event.keyCode)
        soundEngine.playClick(for: event.keyCode, eventTimestamp: CACurrentMediaTime())
    }

    private func handleKeyUpEvent(_ event: NSEvent) {
        guard isEnabled else { return }
        guard !event.isARepeat else { return }

        soundEngine.playRelease(for: event.keyCode)
    }

    private func handleFlagsChangedEvent(_ event: NSEvent) {
        guard isEnabled else { return }
        guard let isPressed = isModifierPressed(for: event.keyCode, flags: event.modifierFlags) else { return }

        if isPressed {
            keystrokeCount += 1
            showKeyPressOverlay(for: event.keyCode)
            soundEngine.playClick(for: event.keyCode, eventTimestamp: CACurrentMediaTime())
        } else {
            soundEngine.playRelease(for: event.keyCode)
        }
    }

    private func handlePointerDownEvent(_ event: NSEvent) {
        guard isEnabled, pointerSoundEnabled else { return }
        soundEngine.playPointerClick(eventTimestamp: CACurrentMediaTime())
    }

    private func handlePointerUpEvent(_ event: NSEvent) {
        guard isEnabled, pointerSoundEnabled else { return }
        soundEngine.playPointerRelease()
    }

    private func recordLatency(_ latencyMilliseconds: Double) {
        latestLatencyMilliseconds = latencyMilliseconds

        if keystrokeCount == 0 {
            averageLatencyMilliseconds = latencyMilliseconds
            return
        }

        let previousSamples = Double(max(keystrokeCount - 1, 0))
        averageLatencyMilliseconds =
            ((averageLatencyMilliseconds * previousSamples) + latencyMilliseconds) / Double(keystrokeCount)
    }

    private func formattedLatency(_ value: Double) -> String {
        String(format: "%.2f ms", value)
    }

    private func restoreSettings() {
        let defaults = UserDefaults.standard

        if defaults.object(forKey: DefaultsKey.isEnabled) != nil {
            isEnabled = defaults.bool(forKey: DefaultsKey.isEnabled)
        }

        if defaults.object(forKey: DefaultsKey.volume) != nil {
            volume = defaults.double(forKey: DefaultsKey.volume)
        }

        if
            let rawValue = defaults.string(forKey: DefaultsKey.selectedSoundProfile),
            let profile = KeyboardSoundEngine.SoundProfile(rawValue: rawValue)
        {
            selectedSoundProfile = profile
        }

        if defaults.bool(forKey: DefaultsKey.hasConfiguredLaunchAtLogin) {
            launchAtLogin = defaults.bool(forKey: DefaultsKey.launchAtLogin)
        } else {
            launchAtLogin = true
        }

        if defaults.object(forKey: DefaultsKey.showKeyOverlay) != nil {
            showKeyOverlay = defaults.bool(forKey: DefaultsKey.showKeyOverlay)
        }

        if defaults.object(forKey: DefaultsKey.showComboPhrases) != nil {
            showComboPhrases = defaults.bool(forKey: DefaultsKey.showComboPhrases)
        }

        if defaults.object(forKey: DefaultsKey.pointerSoundEnabled) != nil {
            pointerSoundEnabled = defaults.bool(forKey: DefaultsKey.pointerSoundEnabled)
        }
    }

    private func updateLaunchAtLoginRegistration() {
        let service = SMAppService.mainApp

        do {
            if launchAtLogin {
                if service.status != .enabled {
                    try service.register()
                }
            } else if service.status == .enabled {
                try service.unregister()
            }
        } catch {
            NSLog("Failed to update launch at login: \(error.localizedDescription)")
        }
    }

    private func hidListenEventAccessGranted() -> Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    private func startGlobalEventTap() {
        let events =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.rightMouseUp.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.otherMouseUp.rawValue)
        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(events),
            callback: { _, type, event, refcon in
                guard let refcon else {
                    return Unmanaged.passUnretained(event)
                }

                let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(refcon).takeUnretainedValue()
                return monitor.handleGlobalEventTap(type: type, event: event)
            },
            userInfo: refcon
        ) else {
            permissionStatus = .globalCaptureUnavailable
            globalCaptureStatus = .failed
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        eventTapSource = source
        isGlobalCaptureActive = true
        globalCaptureStatus = .active
    }

    private func handleGlobalEventTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard isEnabled else {
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            if pointerSoundEnabled {
                soundEngine.playPointerClick(eventTimestamp: CACurrentMediaTime())
            }
            return Unmanaged.passUnretained(event)
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            if pointerSoundEnabled {
                soundEngine.playPointerRelease()
            }
            return Unmanaged.passUnretained(event)
        default:
            break
        }

        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        if isRepeat {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        switch type {
        case .keyDown:
            keystrokeCount += 1
            showKeyPressOverlay(for: keyCode)
            soundEngine.playClick(for: keyCode, eventTimestamp: CACurrentMediaTime())
        case .keyUp:
            soundEngine.playRelease(for: keyCode)
        case .flagsChanged:
            guard let isPressed = isModifierPressed(for: keyCode, flags: event.flags) else { break }

            if isPressed {
                keystrokeCount += 1
                showKeyPressOverlay(for: keyCode)
                soundEngine.playClick(for: keyCode, eventTimestamp: CACurrentMediaTime())
            } else {
                soundEngine.playRelease(for: keyCode)
            }
        default:
            break
        }

        return Unmanaged.passUnretained(event)
    }

    private func showKeyPressOverlay(for keyCode: UInt16) {
        guard showKeyOverlay else { return }
        guard let label = keyDisplayName(for: keyCode) else { return }
        let now = CACurrentMediaTime()
        let heat = overlayHeat(for: now)
        let comboMessage = comboMessage(for: now, heat: heat)
        lastOverlayTimestamp = now
        KeyPressOverlayController.shared.show(keyLabel: label, heat: heat, comboMessage: comboMessage)
    }

    private func overlayHeat(for timestamp: CFTimeInterval) -> Double {
        guard let lastOverlayTimestamp else { return 0.25 }

        let delta = max(0, timestamp - lastOverlayTimestamp)
        let normalized = 1 - ((delta - 0.05) / 0.45)
        return min(max(normalized, 0), 1)
    }

    private func comboMessage(for timestamp: CFTimeInterval, heat: Double) -> String? {
        guard showComboPhrases else { return nil }

        guard let lastOverlayTimestamp else {
            rapidTypingStreak = 1
            lastComboAnnouncementTimestamp = nil
            lastComboPhrase = nil
            return nil
        }

        let delta = max(0, timestamp - lastOverlayTimestamp)

        if delta <= 0.42 {
            rapidTypingStreak += 1
        } else {
            rapidTypingStreak = 1
            lastComboAnnouncementTimestamp = nil
            lastComboPhrase = nil
            return nil
        }

        guard heat >= 0.48, rapidTypingStreak >= 4 else {
            return nil
        }

        if let previousAnnouncementTimestamp = lastComboAnnouncementTimestamp {
            guard (timestamp - previousAnnouncementTimestamp) >= 1.5 else { return nil }
        }

        lastComboAnnouncementTimestamp = timestamp
        return nextComboPhrase()
    }

    private func nextComboPhrase() -> String {
        let phrases = Self.comboPhrases
        guard phrases.count > 1 else { return phrases.first ?? "Menyala abangku..." }

        let nextPhrase = phrases
            .filter { $0 != lastComboPhrase }
            .randomElement() ?? phrases[0]

        lastComboPhrase = nextPhrase
        return nextPhrase
    }

    private func keyDisplayName(for keyCode: UInt16) -> String? {
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 10: return "§"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "O"
        case 32: return "U"
        case 33: return "["
        case 34: return "I"
        case 35: return "P"
        case 36, 76: return "↩"
        case 37: return "L"
        case 38: return "J"
        case 39: return "'"
        case 40: return "K"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "N"
        case 46: return "M"
        case 47: return "."
        case 48: return "⇥"
        case 49: return "␣"
        case 50: return "`"
        case 51: return "⌫"
        case 53: return "⎋"
        case 55, 54: return "⌘"
        case 56, 60: return "⇧"
        case 57: return "⇪"
        case 58, 61: return "⌥"
        case 59, 62: return "⌃"
        case 63: return "fn"
        case 64: return "F17"
        case 65: return "Numpad ."
        case 67: return "Numpad *"
        case 69: return "Numpad +"
        case 71: return "⌧"
        case 72: return "􀊩"
        case 73: return "􀊧"
        case 74: return "􀊣"
        case 75: return "Numpad /"
        case 78: return "Numpad -"
        case 79: return "F18"
        case 80: return "F19"
        case 81: return "Numpad ="
        case 82: return "Numpad 0"
        case 83: return "Numpad 1"
        case 84: return "Numpad 2"
        case 85: return "Numpad 3"
        case 86: return "Numpad 4"
        case 87: return "Numpad 5"
        case 88: return "Numpad 6"
        case 89: return "Numpad 7"
        case 91: return "Numpad 8"
        case 92: return "Numpad 9"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 99: return "F3"
        case 100: return "F8"
        case 101: return "F9"
        case 103: return "F11"
        case 105: return "F13"
        case 106: return "F16"
        case 107: return "F14"
        case 109: return "F10"
        case 111: return "F12"
        case 113: return "F15"
        case 114: return "Help"
        case 115: return "↖"
        case 116: return "⇞"
        case 117: return "⌦"
        case 118: return "F4"
        case 119: return "↘"
        case 120: return "F2"
        case 121: return "⇟"
        case 122: return "F1"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: return nil
        }
    }

    private func isModifierPressed(for keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool? {
        switch keyCode {
        case 55, 54:
            return flags.contains(.command)
        case 56, 60:
            return flags.contains(.shift)
        case 58, 61:
            return flags.contains(.option)
        case 59, 62:
            return flags.contains(.control)
        case 57:
            return flags.contains(.capsLock)
        case 63:
            return flags.contains(.function)
        default:
            return nil
        }
    }

    private func isModifierPressed(for keyCode: UInt16, flags: CGEventFlags) -> Bool? {
        switch keyCode {
        case 55, 54:
            return flags.contains(.maskCommand)
        case 56, 60:
            return flags.contains(.maskShift)
        case 58, 61:
            return flags.contains(.maskAlternate)
        case 59, 62:
            return flags.contains(.maskControl)
        case 57:
            return flags.contains(.maskAlphaShift)
        case 63:
            return flags.contains(.maskSecondaryFn)
        default:
            return nil
        }
    }
}

extension KeyboardMonitor {
    enum PermissionStatus: Equatable {
        case unknown
        case granted
        case needsPermission
        case globalCaptureUnavailable

        var title: String {
            switch self {
            case .unknown:
                return "Memeriksa izin keyboard"
            case .granted:
                return "Izin keyboard aktif"
            case .needsPermission:
                return "Izin keyboard dibutuhkan"
            case .globalCaptureUnavailable:
                return "Global capture gagal aktif"
            }
        }

        var message: String {
            switch self {
            case .unknown:
                return "App sedang mengecek apakah bisa membaca input keyboard."
            case .granted:
                return "Suara bisa diputar saat Anda mengetik di aplikasi ini dan aplikasi lain."
            case .needsPermission:
                return "Berikan izin Accessibility dan Input Monitoring agar app bisa mendeteksi keyboard secara global di seluruh macOS."
            case .globalCaptureUnavailable:
                return "Izin terlihat aktif, tetapi event tap global belum berhasil dibuat. Coba buka ulang aplikasi setelah mengaktifkan Input Monitoring."
            }
        }

        var icon: String {
            switch self {
            case .unknown:
                return "questionmark.circle"
            case .granted:
                return "checkmark.shield"
            case .needsPermission:
                return "keyboard.badge.ellipsis"
            case .globalCaptureUnavailable:
                return "exclamationmark.triangle"
            }
        }
    }
}

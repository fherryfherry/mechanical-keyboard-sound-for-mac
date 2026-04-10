//
//  KeyboardSoundEngine.swift
//  Mechanical Sound For Mac
//
//  Created by Codex.
//

import AVFoundation
import Foundation
import QuartzCore

final class KeyboardSoundEngine {
    private struct PlayerLayer {
        let primary: AVAudioPlayer
        let boost: AVAudioPlayer
    }

    enum SoundProfile: String, CaseIterable, Identifiable {
        case alpaca
        case blackink
        case bluealps
        case boxnavy
        case buckling
        case cream
        case holypanda
        case mxblack
        case mxblue
        case mxbrown
        case redink
        case topre
        case turquoise

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .alpaca: return "Alpaca"
            case .blackink: return "Black Ink"
            case .bluealps: return "Blue Alps"
            case .boxnavy: return "Box Navy"
            case .buckling: return "Buckling Spring"
            case .cream: return "Cream"
            case .holypanda: return "Holy Panda"
            case .mxblack: return "MX Black"
            case .mxblue: return "MX Blue"
            case .mxbrown: return "MX Brown"
            case .redink: return "Red Ink"
            case .topre: return "Topre"
            case .turquoise: return "Turquoise"
            }
        }
    }

    enum KeyPhase {
        case press
        case release
    }

    var onLatencyMeasured: ((Double) -> Void)?
    var volume: Float = 0.85 {
        didSet {
            queue.async { [weak self] in
                guard let self else { return }
                self.pressPlayers.values.forEach { self.applyVolume(to: $0) }
                self.releasePlayers.values.forEach { self.applyVolume(to: $0) }
                self.previewPressPlayers.values.forEach { self.applyVolume(to: $0) }
                self.previewReleasePlayers.values.forEach { self.applyVolume(to: $0) }
            }
        }
    }

    var selectedProfile: SoundProfile = .cream {
        didSet {
            queue.async { [weak self] in
                self?.preparePlayers()
            }
        }
    }

    private let queue = DispatchQueue(label: "KeyboardSoundEngine.queue", qos: .userInitiated)
    private var pressPlayers: [String: PlayerLayer] = [:]
    private var releasePlayers: [String: PlayerLayer] = [:]
    private var previewPressPlayers: [String: PlayerLayer] = [:]
    private var previewReleasePlayers: [String: PlayerLayer] = [:]
    private var genericPressRotation = 0
    private var previewGenericPressRotation = 0
    private var previewProfile: SoundProfile?
    private var pendingPreviewWorkItem: DispatchWorkItem?
    private var previewWorkItem: DispatchWorkItem?
    private var previewToken = UUID()

    init() {
        queue.async { [weak self] in
            self?.preparePlayers()
        }
    }

    func playClick(for keyCode: UInt16, eventTimestamp: CFTimeInterval) {
        queue.async { [weak self] in
            self?.playSample(for: keyCode, phase: .press, eventTimestamp: eventTimestamp)
        }
    }

    func playRelease(for keyCode: UInt16) {
        queue.async { [weak self] in
            self?.playSample(for: keyCode, phase: .release, eventTimestamp: nil)
        }
    }

    func playPointerClick(eventTimestamp: CFTimeInterval) {
        queue.async { [weak self] in
            self?.playSample(for: 36, phase: .press, eventTimestamp: eventTimestamp)
        }
    }

    func playPointerRelease() {
        queue.async { [weak self] in
            self?.playSample(for: 36, phase: .release, eventTimestamp: nil)
        }
    }

    func startPreview(for profile: SoundProfile) {
        queue.async { [weak self] in
            self?.startPreviewLoop(for: profile)
        }
    }

    func schedulePreview(for profile: SoundProfile, delay: TimeInterval) {
        queue.async { [weak self] in
            guard let self else { return }

            self.pendingPreviewWorkItem?.cancel()

            let workItem = DispatchWorkItem { [weak self] in
                self?.startPreviewLoop(for: profile)
            }

            self.pendingPreviewWorkItem = workItem
            self.queue.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }

    func stopPreview() {
        queue.async { [weak self] in
            self?.stopPreviewLocked()
        }
    }

    private func preparePlayers() {
        pressPlayers = loadPlayers(for: selectedProfile, in: "press")
        releasePlayers = loadPlayers(for: selectedProfile, in: "release")
    }

    private func loadPlayers(for profile: SoundProfile, in folder: String) -> [String: PlayerLayer] {
        let fileNames = folder == "press"
            ? ["BACKSPACE", "ENTER", "SPACE", "GENERIC_R0", "GENERIC_R1", "GENERIC_R2", "GENERIC_R3", "GENERIC_R4"]
            : ["BACKSPACE", "ENTER", "SPACE", "GENERIC"]

        var players: [String: PlayerLayer] = [:]
        
        if let bundlePath = Bundle.main.resourcePath {
            let audioPath = URL(fileURLWithPath: bundlePath).appendingPathComponent("audio/\(profile.rawValue)/\(folder)")
            
            for fileName in fileNames {
                let fileURL = audioPath.appendingPathComponent(fileName).appendingPathExtension("mp3")
                
                guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }
                
                if
                    let primaryPlayer = try? AVAudioPlayer(contentsOf: fileURL),
                    let boostPlayer = try? AVAudioPlayer(contentsOf: fileURL)
                {
                    let layer = PlayerLayer(primary: primaryPlayer, boost: boostPlayer)
                    applyVolume(to: layer)
                    layer.primary.prepareToPlay()
                    layer.boost.prepareToPlay()
                    players[fileName] = layer
                }
            }
        }

        return players
    }

    private func playSample(for keyCode: UInt16, phase: KeyPhase, eventTimestamp: CFTimeInterval?) {
        let sampleName = sampleName(for: keyCode, phase: phase)
        let players = phase == .press ? pressPlayers : releasePlayers

        guard let playerLayer = players[sampleName] ?? players[fallbackSampleName(for: phase)] else { return }

        applyVolume(to: playerLayer)
        playerLayer.primary.currentTime = 0
        playerLayer.primary.play()

        if playerLayer.boost.volume > 0 {
            playerLayer.boost.currentTime = 0
            playerLayer.boost.play()
        }

        if let eventTimestamp {
            let latencyMilliseconds = max(0, (CACurrentMediaTime() - eventTimestamp) * 1_000)
            onLatencyMeasured?(latencyMilliseconds)
        }
    }

    private func sampleName(for keyCode: UInt16, phase: KeyPhase) -> String {
        switch phase {
        case .press:
            if keyCode == 51 { return "BACKSPACE" }
            if keyCode == 36 || keyCode == 76 { return "ENTER" }
            if keyCode == 49 { return "SPACE" }

            let genericNames = ["GENERIC_R0", "GENERIC_R1", "GENERIC_R2", "GENERIC_R3", "GENERIC_R4"]
            let selectedName = genericNames[genericPressRotation % genericNames.count]
            genericPressRotation += 1
            return selectedName

        case .release:
            if keyCode == 51 { return "BACKSPACE" }
            if keyCode == 36 || keyCode == 76 { return "ENTER" }
            if keyCode == 49 { return "SPACE" }
            return "GENERIC"
        }
    }

    private func fallbackSampleName(for phase: KeyPhase) -> String {
        phase == .press ? "GENERIC_R0" : "GENERIC"
    }

    private func startPreviewLoop(for profile: SoundProfile) {
        guard previewProfile != profile else { return }

        stopPreviewLocked()
        pendingPreviewWorkItem = nil

        previewPressPlayers = loadPlayers(for: profile, in: "press")
        previewReleasePlayers = loadPlayers(for: profile, in: "release")
        previewGenericPressRotation = 0
        previewProfile = profile
        previewToken = UUID()

        schedulePreviewPress(for: previewToken)
    }

    private func stopPreviewLocked() {
        pendingPreviewWorkItem?.cancel()
        pendingPreviewWorkItem = nil
        previewWorkItem?.cancel()
        previewWorkItem = nil
        previewToken = UUID()
        previewProfile = nil

        stop(players: previewPressPlayers)
        stop(players: previewReleasePlayers)

        previewPressPlayers = [:]
        previewReleasePlayers = [:]
    }

    private func schedulePreviewPress(for token: UUID) {
        guard previewProfile != nil, token == previewToken else { return }

        playPreviewSample(named: previewGenericSampleName(), phase: .press)

        let workItem = DispatchWorkItem { [weak self] in
            self?.schedulePreviewRelease(for: token)
        }

        previewWorkItem = workItem
        queue.asyncAfter(deadline: .now() + 0.07, execute: workItem)
    }

    private func schedulePreviewRelease(for token: UUID) {
        guard previewProfile != nil, token == previewToken else { return }

        playPreviewSample(named: "GENERIC", phase: .release)

        let workItem = DispatchWorkItem { [weak self] in
            self?.schedulePreviewPress(for: token)
        }

        previewWorkItem = workItem
        queue.asyncAfter(deadline: .now() + 0.18, execute: workItem)
    }

    private func playPreviewSample(named sampleName: String, phase: KeyPhase) {
        let players = phase == .press ? previewPressPlayers : previewReleasePlayers
        guard let playerLayer = players[sampleName] ?? players[fallbackSampleName(for: phase)] else { return }

        applyVolume(to: playerLayer)
        playerLayer.primary.currentTime = 0
        playerLayer.primary.play()

        if playerLayer.boost.volume > 0 {
            playerLayer.boost.currentTime = 0
            playerLayer.boost.play()
        }
    }

    private func previewGenericSampleName() -> String {
        let genericNames = ["GENERIC_R0", "GENERIC_R1", "GENERIC_R2", "GENERIC_R3", "GENERIC_R4"]
        let selectedName = genericNames[previewGenericPressRotation % genericNames.count]
        previewGenericPressRotation += 1
        return selectedName
    }

    private func stop(players: [String: PlayerLayer]) {
        for layer in players.values {
            layer.primary.stop()
            layer.boost.stop()
        }
    }

    private func applyVolume(to layer: PlayerLayer) {
        let clampedVolume = min(max(volume, 0), 2)
        layer.primary.volume = min(clampedVolume, 1)
        layer.boost.volume = max(0, clampedVolume - 1)
    }
}

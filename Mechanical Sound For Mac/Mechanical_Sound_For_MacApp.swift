import AppKit
import SwiftUI

@main
struct Mechanical_Sound_For_MacApp: App {
    @StateObject private var keyboardMonitor = KeyboardMonitor.shared

    var body: some Scene {
        MenuBarExtra("Mechanical Sound", systemImage: "keyboard") {
            TrayMenuContent(keyboardMonitor: keyboardMonitor)
        }

        Window("Request Permission", id: PermissionGuideView.windowID) {
            PermissionGuideView(keyboardMonitor: keyboardMonitor)
                .frame(width: 460)
                .background(PermissionWindowConfigurator())
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 460, height: 640)
    }
}

private struct TrayMenuContent: View {
    @ObservedObject var keyboardMonitor: KeyboardMonitor
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if shouldShowDiagnostics {
            Button(keyboardMonitor.permissionStatus == .granted ? "Permission Help" : "Request Permission") {
                openWindow(id: PermissionGuideView.windowID)
            }
            Divider()
        }

        Toggle("Aktifkan suara", isOn: $keyboardMonitor.isEnabled)
        Toggle("Launch at Login", isOn: $keyboardMonitor.launchAtLogin)
        Toggle("Key Press HUD", isOn: $keyboardMonitor.showKeyOverlay)
        Toggle("Combo Frasa", isOn: $keyboardMonitor.showComboPhrases)
        Toggle("Mouse / Touchpad Sound", isOn: $keyboardMonitor.pointerSoundEnabled)

        Menu("Volume \(Int(keyboardMonitor.volume * 100))%") {
            volumeButton(title: "25%", value: 0.25)
            volumeButton(title: "50%", value: 0.5)
            volumeButton(title: "75%", value: 0.75)
            volumeButton(title: "85%", value: 0.85)
            volumeButton(title: "100%", value: 1.0)
            volumeButton(title: "125%", value: 1.25)
            volumeButton(title: "150%", value: 1.5)
            volumeButton(title: "200%", value: 2.0)
        }

        Menu("Profile \(keyboardMonitor.selectedSoundProfile.displayName)") {
            ForEach(KeyboardSoundEngine.SoundProfile.allCases) { profile in
                ProfileMenuItem(keyboardMonitor: keyboardMonitor, profile: profile)
            }
        }

        Divider()

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
    }

    private var shouldShowDiagnostics: Bool {
        keyboardMonitor.permissionStatus != .granted || keyboardMonitor.installationHint != nil
    }

    private func volumeButton(title: String, value: Double) -> some View {
        Button {
            keyboardMonitor.volume = value
        } label: {
            if abs(keyboardMonitor.volume - value) < 0.01 {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }
}

private struct ProfileMenuItem: View {
    @ObservedObject var keyboardMonitor: KeyboardMonitor
    let profile: KeyboardSoundEngine.SoundProfile

    var body: some View {
        Button {
            keyboardMonitor.stopProfilePreview()
            keyboardMonitor.selectedSoundProfile = profile
        } label: {
            if keyboardMonitor.selectedSoundProfile == profile {
                Label(profile.displayName, systemImage: "checkmark")
            } else {
                Text(profile.displayName)
            }
        }
        .onHover { isHovering in
            guard isHovering else {
                keyboardMonitor.stopProfilePreview()
                return
            }
            keyboardMonitor.scheduleProfilePreview(profile)
        }
    }
}

private struct PermissionGuideView: View {
    static let windowID = "permission-guide"

    @ObservedObject var keyboardMonitor: KeyboardMonitor
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerCard
                statusSummary

                permissionStep(
                    number: 1,
                    title: "Accessibility",
                    description: "Klik tombol di bawah untuk meminta permission Accessibility, lalu aktifkan toggle app ini di halaman yang terbuka.",
                    isGranted: keyboardMonitor.accessibilityGranted,
                    primaryTitle: "Request Accessibility",
                    primaryAction: {
                        keyboardMonitor.requestAccessibilityPermission()
                    },
                    secondaryTitle: nil,
                    secondaryAction: nil
                )

                inputMonitoringStep

                footerSection
            }
            .padding(22)
        }
        .scrollIndicators(.hidden)
        .background(
            LinearGradient(
                colors: [
                    Color(NSColor.windowBackgroundColor),
                    Color(NSColor.controlBackgroundColor)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let heroImage = NSImage(named: "PermissionHeader") {
                Image(nsImage: heroImage)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 132)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color(NSColor.separatorColor).opacity(0.35))
                    }
            }

            Text("Request Permission")
                .font(.title2.bold())

            Text("Ikuti dua langkah berikut agar suara keyboard bisa aktif secara global di semua aplikasi.")
                .foregroundStyle(.secondary)
        }
    }

    private var statusSummary: some View {
        HStack(spacing: 12) {
            summaryChip(title: "Accessibility", isOn: keyboardMonitor.accessibilityGranted)
            summaryChip(title: "Input Monitoring", isOn: keyboardMonitor.inputMonitoringGranted)
            summaryChip(title: "Capture", isOn: keyboardMonitor.isGlobalCaptureActive)
        }
    }

    private var footerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let installationHint = keyboardMonitor.installationHint {
                Divider()
                Text(installationHint)
                    .font(.callout)
                Text(keyboardMonitor.bundlePath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Button("Recheck Status") {
                    keyboardMonitor.refreshPermissionStatus()
                }

                Spacer()

                if keyboardMonitor.accessibilityGranted && keyboardMonitor.inputMonitoringGranted {
                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }

                Label(
                    keyboardMonitor.globalCaptureStatus.title,
                    systemImage: keyboardMonitor.globalCaptureStatus.icon
                )
                .foregroundStyle(keyboardMonitor.isGlobalCaptureActive ? .green : .secondary)
            }

            Text("developed by CakFer. v1.0.0")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var inputMonitoringStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Step 2")
                    .font(.headline)
                Spacer()
                Text(keyboardMonitor.inputMonitoringGranted ? "Completed" : "Pending")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(keyboardMonitor.inputMonitoringGranted ? Color.green.opacity(0.14) : Color.gray.opacity(0.12))
                    .foregroundStyle(keyboardMonitor.inputMonitoringGranted ? .green : .secondary)
                    .clipShape(Capsule())
            }

            Text("Input Monitoring")
                .font(.title3.weight(.semibold))

            Text("Ikuti panduan berikut untuk menambahkan app ini ke Input Monitoring, lalu pilih Quit & Reopen saat macOS memintanya.")
                .foregroundStyle(.secondary)

            Button("Request Input Monitoring") {
                keyboardMonitor.requestInputMonitoringPermission()
                openPrivacyPane(anchor: "Privacy_ListenEvent")
            }
            .buttonStyle(.borderedProminent)

            inputMonitoringInstruction(
                imageName: "InputMonitoringStep1",
                title: "1. Klik tombol +",
                description: "Di halaman Input Monitoring, tekan tombol + untuk menambahkan aplikasi."
            )

            inputMonitoringInstruction(
                imageName: "InputMonitoringStep2",
                title: "2. Pilih Mechanical Sound For Mac",
                description: "Di Finder dialog, pilih aplikasi Mechanical Sound For Mac yang terpasang."
            )

            inputMonitoringInstruction(
                imageName: "InputMonitoringStep3",
                title: "3. Pilih Quit & Reopen",
                description: "Saat modal macOS muncul, pilih Quit & Reopen agar permission aktif."
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.92))
                .strokeBorder(Color(NSColor.separatorColor).opacity(0.45))
        )
    }

    @ViewBuilder
    private func permissionStep(
        number: Int,
        title: String,
        description: String,
        isGranted: Bool,
        primaryTitle: String,
        primaryAction: @escaping () -> Void,
        secondaryTitle: String?,
        secondaryAction: (() -> Void)?
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Step \(number)")
                    .font(.headline)
                Spacer()
                Text(isGranted ? "Completed" : "Pending")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(isGranted ? Color.green.opacity(0.14) : Color.gray.opacity(0.12))
                    .foregroundStyle(isGranted ? .green : .secondary)
                    .clipShape(Capsule())
            }

            Text(title)
                .font(.title3.weight(.semibold))

            Text(description)
                .foregroundStyle(.secondary)

            HStack {
                Button(primaryTitle, action: primaryAction)
                    .buttonStyle(.borderedProminent)

                if let secondaryTitle, let secondaryAction {
                    Button(secondaryTitle, action: secondaryAction)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.92))
                .strokeBorder(Color(NSColor.separatorColor).opacity(0.45))
        )
    }

    private func summaryChip(title: String, isOn: Bool) -> some View {
        Label(title, systemImage: isOn ? "checkmark.circle.fill" : "circle")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isOn ? Color.green.opacity(0.14) : Color.gray.opacity(0.12))
            .foregroundStyle(isOn ? .green : .secondary)
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func inputMonitoringInstruction(
        imageName: String,
        title: String,
        description: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let image = NSImage(named: imageName) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color(NSColor.separatorColor).opacity(0.35))
                    }
            }

            Text(title)
                .font(.subheadline.weight(.semibold))

            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func openPrivacyPane(anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}

private struct PermissionWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()

        DispatchQueue.main.async {
            guard let window = view.window else { return }

            window.collectionBehavior.remove(.fullScreenPrimary)
            window.collectionBehavior.remove(.managed)
            window.styleMask.remove(.resizable)
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        }

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }

            window.collectionBehavior.remove(.fullScreenPrimary)
            window.collectionBehavior.remove(.managed)
            window.styleMask.remove(.resizable)
            window.standardWindowButton(.zoomButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        }
    }
}

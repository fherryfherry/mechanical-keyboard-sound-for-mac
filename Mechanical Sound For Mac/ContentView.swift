//
//  ContentView.swift
//  Mechanical Sound For Mac
//
//  Created by Ferry on 09/04/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var keyboardMonitor = KeyboardMonitor.shared
    @State private var typingText = ""
    @FocusState private var isTypingAreaFocused: Bool
    private let primaryTextColor = Color(red: 0.16, green: 0.12, blue: 0.08)
    private let secondaryTextColor = Color(red: 0.30, green: 0.24, blue: 0.18)
    private let cardBackgroundColor = Color.white.opacity(0.9)

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            statusCard
            controlCard
            typingCard
            infoCard
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 420)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.94, blue: 0.89),
                    Color(red: 0.87, green: 0.83, blue: 0.76)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .foregroundStyle(primaryTextColor)
        .onAppear {
            isTypingAreaFocused = true
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mechanical Keyboard Sound")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(primaryTextColor)

            Text("Tambahkan efek suara klik saat mengetik di Mac, mirip mechanical keyboard.")
                .foregroundStyle(secondaryTextColor)
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(keyboardMonitor.permissionStatus.title, systemImage: keyboardMonitor.permissionStatus.icon)
                .font(.headline)
                .foregroundStyle(primaryTextColor)

            Text(keyboardMonitor.permissionStatus.message)
                .foregroundStyle(secondaryTextColor)

            HStack(spacing: 12) {
                Button("Cek Ulang Izin") {
                    keyboardMonitor.refreshPermissionStatus()
                }

                if !keyboardMonitor.hasPermission {
                    Button("Minta Izin Keyboard") {
                        keyboardMonitor.requestPermission()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackgroundColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var controlCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Aktifkan suara keyboard", isOn: $keyboardMonitor.isEnabled)
                .toggleStyle(.switch)
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Volume")
                    Spacer()
                    Text("\(Int(keyboardMonitor.volume * 100))%")
                        .foregroundStyle(secondaryTextColor)
                }

                Slider(value: $keyboardMonitor.volume, in: 0.05...2.0)
                    .disabled(!keyboardMonitor.isEnabled)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Profil switch")
                    Spacer()
                    Text(keyboardMonitor.selectedSoundProfile.displayName)
                        .foregroundStyle(secondaryTextColor)
                }

                Picker("Profil switch", selection: $keyboardMonitor.selectedSoundProfile) {
                    ForEach(KeyboardSoundEngine.SoundProfile.allCases) { profile in
                        Text(profile.displayName).tag(profile)
                    }
                }
                .labelsHidden()
                .disabled(!keyboardMonitor.isEnabled)
            }

            HStack {
                Text("Tombol terdeteksi")
                Spacer()
                Text("\(keyboardMonitor.keystrokeCount)")
                    .monospacedDigit()
                    .font(.title3.weight(.semibold))
            }
            .padding(.top, 4)

            HStack {
                Text("Latency terakhir")
                Spacer()
                Text(keyboardMonitor.latestLatencyText)
                    .monospacedDigit()
                    .foregroundStyle(secondaryTextColor)
            }

            HStack {
                Text("Rata-rata latency")
                Spacer()
                Text(keyboardMonitor.averageLatencyText)
                    .monospacedDigit()
                    .foregroundStyle(secondaryTextColor)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackgroundColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Catatan")
                .font(.headline)
                .foregroundStyle(primaryTextColor)

            Text("Untuk mendengar suara saat mengetik di semua aplikasi, macOS biasanya meminta izin Accessibility atau Input Monitoring. Setelah izin diberikan, buka ulang aplikasi jika macOS memintanya.")
                .foregroundStyle(secondaryTextColor)

            Text("Suara dibuat secara sintetis di dalam app, jadi tidak perlu file audio tambahan.")
                .foregroundStyle(secondaryTextColor)

            Text("Sekarang app memakai sample audio keyboard asli dari folder audio profile yang Anda pindahkan ke dalam app.")
                .foregroundStyle(secondaryTextColor)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackgroundColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var typingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Area Coba Mengetik")
                        .font(.headline)
                        .foregroundStyle(primaryTextColor)

                    Text("Ketik di sini untuk mengetes suara tanpa pindah ke aplikasi lain.")
                        .foregroundStyle(secondaryTextColor)
                }

                Spacer()

                Button("Fokus ke Area Ketik") {
                    isTypingAreaFocused = true
                }
            }

            TextEditor(text: $typingText)
                .focused($isTypingAreaFocused)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(primaryTextColor)
                .scrollContentBackground(.hidden)
                .padding(12)
                .frame(minHeight: 120)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.98))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.black.opacity(0.12), lineWidth: 1)
                )
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackgroundColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

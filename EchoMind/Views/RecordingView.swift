//
//  RecordingView.swift
//  EchoMind
//
//  Created by Oleksandr Stepanov on 26.02.26.
//


import SwiftUI
import Foundation

// MARK: - View

struct RecordingView: View {
    @Environment(\.dismiss) private var dismiss

    let onFinished: (URL) -> Void
    @StateObject private var vm = AudioRecorderViewModel()

    init(onFinished: @escaping (URL) -> Void = { _ in }) {
        self.onFinished = onFinished
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 8)

            // Title
            Text(vm.isRecording ? "Recording" : "Ready")
                .font(.title2.weight(.semibold))

            // Timer
            Text(vm.formattedDuration)
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .accessibilityLabel("Recording duration")

            // Waveform (simple live level visual)
            WaveformView(levels: vm.waveformLevels)
                .frame(height: 90)
                .padding(.horizontal, 18)

            // Status
            Text(vm.statusText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()

            // Actions
            HStack(spacing: 14) {
                Button(role: .destructive) {
                    HapticsService.notify(.warning)
                    vm.cancelRecording()
                    dismiss()
                } label: {
                    Label("Cancel", systemImage: "xmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    if vm.isRecording {
                        vm.finishRecording()
                        HapticsService.notify(.success)
                        if let url = vm.recordedURL {
                            onFinished(url)
                        }
                        dismiss()
                    } else {
                        HapticsService.impact(.medium)
                        vm.startRecording()
                    }
                } label: {
                    Label(vm.isRecording ? "Finish" : "Start", systemImage: vm.isRecording ? "checkmark" : "mic.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.primaryActionDisabled)
            }
            .padding(.horizontal)
            .padding(.bottom, 10)

            if let url = vm.recordedURL, !vm.isRecording {
                ShareLink(item: url) {
                    Label("Export recording", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal)
            }
        }
        .padding(.top)
        .onAppear { vm.onAppear() }
        .onDisappear { vm.onDisappear() }
        .onChange(of: vm.showMicAlert) { _, isShown in
            if isShown {
                HapticsService.notify(.error)
            }
        }
        .alert("Microphone Access Needed", isPresented: $vm.showMicAlert) {
            Button("OK") { }
        } message: {
            Text("Please enable microphone access in Settings to record audio.")
        }
    }
}

#Preview {
    RecordingView(onFinished: { _ in })
}


// MARK: - Waveform View

struct WaveformView: View {
    let levels: [CGFloat]

    var body: some View {
        GeometryReader { geo in
            let count = max(levels.count, 1)
            let spacing: CGFloat = 3
            let barWidth = max(2, (geo.size.width - CGFloat(count - 1) * spacing) / CGFloat(count))

            HStack(alignment: .center, spacing: spacing) {
                ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                    Capsule(style: .continuous)
                        .frame(width: barWidth, height: max(4, geo.size.height * level))
                        .opacity(0.9)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .accessibilityHidden(true)
    }
}

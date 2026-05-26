import SwiftUI

struct VoiceInteractionView: View {
    @State private var isActive = false
    var activeThread: Thread?

    var body: some View {
        if isActive {
            ActiveVoiceInteractionView(activeThread: activeThread, onDismiss: { isActive = false })
        } else {
            Button(action: { isActive = true }) {
                HStack {
                    Image(systemName: "mic.fill")
                    Text("Hlasový Asistent")
                }
                .font(.subheadline)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.1))
                .foregroundColor(.blue)
                .cornerRadius(16)
            }
            .padding(.bottom, 8)
        }
    }
}

struct ActiveVoiceInteractionView: View {
    @StateObject private var viewModel = VoiceInteractionService()
    var activeThread: Thread?
    var onDismiss: () -> Void

    var body: some View {
        VStack {
            HStack {
                Spacer()
                Button(action: {
                    viewModel.stopEverything()
                    onDismiss()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                        .padding(8)
                }
            }

            if viewModel.isDownloadingModel {
                ProgressView("Stahování hlasového modelu...")
                    .padding()
            } else {
                if viewModel.isListening || viewModel.isSpeaking || !viewModel.currentText.isEmpty {
                    Text(viewModel.currentText.isEmpty ? "Připraven" : viewModel.currentText)
                        .font(.subheadline)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding()

                    VoicePulseView(isListening: viewModel.isListening, level: viewModel.audioLevel)
                        .frame(height: 50)
                        .padding()
                }

                Button(action: {
                    viewModel.activeThread = activeThread
                    viewModel.toggleInteraction()
                }) {
                    Image(systemName: viewModel.isListening ? "stop.circle.fill" : "mic.circle.fill")
                        .resizable()
                        .frame(width: 44, height: 44)
                        .foregroundColor(viewModel.isListening ? .red : .blue)
                }
                .padding(.vertical, 8)
            }
        }
        .background(Color.aicovenGlass)
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

struct VoicePulseView: View {
    var isListening: Bool
    var level: Float

    // Deterministic multipliers to avoid jitter
    private let multipliers: [CGFloat] = [0.8, 1.2, 1.0, 1.3, 0.9]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<5) { index in
                RoundedRectangle(cornerRadius: 10)
                    .fill(isListening ? Color.red : Color.gray.opacity(0.3))
                    .frame(width: 8, height: calculateHeight(for: index))
                    .animation(.spring(response: 0.2, dampingFraction: 0.6), value: level)
            }
        }
    }

    private func calculateHeight(for index: Int) -> CGFloat {
        if !isListening { return 20 }
        let baseHeight: CGFloat = 20
        let dynamicHeight = CGFloat(level) * 1000 // Scale factor
        let multiplier = multipliers[index % multipliers.count]
        return max(baseHeight, min(50, dynamicHeight * multiplier))
    }
}

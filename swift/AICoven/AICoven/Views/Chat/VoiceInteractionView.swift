import SwiftUI

struct VoiceInteractionView: View {
    @StateObject private var viewModel = VoiceInteractionService()
    var activeThread: Thread?

    var body: some View {
        VStack {
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

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<5) { index in
                RoundedRectangle(cornerRadius: 10)
                    .fill(isListening ? Color.red : Color.gray.opacity(0.3))
                    .frame(width: 8, height: calculateHeight(for: index))
                    .animation(.spring(), value: level)
            }
        }
    }

    private func calculateHeight(for index: Int) -> CGFloat {
        if !isListening { return 20 }
        let baseHeight: CGFloat = 20
        let dynamicHeight = CGFloat(level) * 1000 // Scale factor
        return max(baseHeight, min(50, dynamicHeight * CGFloat.random(in: 0.5...1.5))) // Add some random variance for visuals
    }
}

import SwiftUI

struct CreateTaskOverlay: View {
    let message: String
    var isProcessing = true

    var body: some View {
        VStack(spacing: 8) {
            if isProcessing {
                ProgressView()
                    .controlSize(.regular)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.title2)
            }
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 8)
    }
}

import SwiftUI

/// Displays a circular progress indicator during 3D model reconstruction.
struct ReconstructionProgressView: View {
    let progress: Double
    var statusText: String = "Reconstructing 3D model..."

    var body: some View {
        VStack(spacing: 32) {
            // Circular progress ring
            ZStack {
                // Background ring
                Circle()
                    .stroke(lineWidth: 8)
                    .opacity(0.15)
                    .foregroundStyle(.white)

                // Progress ring
                Circle()
                    .trim(from: 0.0, to: CGFloat(min(progress, 1.0)))
                    .stroke(style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .foregroundStyle(.tint)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: progress)

                // Percentage text
                VStack(spacing: 4) {
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: Int(progress * 100))

                    Image(systemName: "cube.transparent.fill")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(width: 160, height: 160)

            // Status text
            VStack(spacing: 8) {
                Text(statusText)
                    .font(.headline)
                    .foregroundStyle(.white)

                Text("Please keep the app open")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding()
    }
}

#Preview("25%") {
    ZStack {
        Color.black.ignoresSafeArea()
        ReconstructionProgressView(progress: 0.25)
    }
}

#Preview("75%") {
    ZStack {
        Color.black.ignoresSafeArea()
        ReconstructionProgressView(progress: 0.75)
    }
}

#Preview("Complete") {
    ZStack {
        Color.black.ignoresSafeArea()
        ReconstructionProgressView(progress: 1.0, statusText: "Generating preview...")
    }
}

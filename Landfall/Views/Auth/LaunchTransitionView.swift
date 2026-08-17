import SwiftUI

/// The short beat between launch and knowing whether a session was restored.
///
/// It exists so the app never flashes the sign-in screen at a player who is
/// already signed in. The motion is deliberately slow and quiet — a compass
/// ring settling, not a spinner demanding attention — because on a warm launch
/// it is on screen for only a few frames.
struct LaunchTransitionView: View {
    @State private var sweeping = false
    @State private var breathing = false

    private var ink: Color { Color(uiColor: VoyageSceneKit.sand) }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(uiColor: VoyageSceneKit.seaBase),
                    Color(uiColor: VoyageSceneKit.nightBG)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ZStack {
                Circle()
                    .stroke(ink.opacity(0.16), lineWidth: 1)
                    .frame(width: 74, height: 74)

                // The sweeping arc reads as a bearing being taken.
                Circle()
                    .trim(from: 0, to: 0.22)
                    .stroke(
                        ink.opacity(0.85),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .frame(width: 74, height: 74)
                    .rotationEffect(.degrees(sweeping ? 360 : 0))

                Circle()
                    .fill(ink.opacity(0.9))
                    .frame(width: 5, height: 5)
                    .scaleEffect(breathing ? 1.5 : 1)
                    .opacity(breathing ? 0.55 : 1)
            }
            .accessibilityElement()
            .accessibilityLabel(Text("Setting course"))
        }
        .onAppear {
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                sweeping = true
            }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
    }
}

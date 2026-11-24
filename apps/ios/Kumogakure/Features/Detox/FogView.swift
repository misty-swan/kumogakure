import SwiftUI

/// Pure visual attenuation parameters derived from `progress` (`design-system.md` §4.2).
struct FogVisualMetrics: Equatable, Sendable {
    let progress: Double

    init(progress: Double) {
        self.progress = min(1.0, max(0.0, progress))
    }

    var backgroundBlurRadius: Double {
        Self.interpolate(progress: progress, start: 16.0, mid: 6.0, end: 0.0)
    }

    var backgroundBrightness: Double {
        Self.interpolate(progress: progress, start: -0.25, mid: -0.10, end: 0.0)
    }

    var farFogOpacity: Double {
        Self.interpolate(progress: progress, start: 0.72, mid: 0.35, end: 0.0)
    }

    var nearFogOpacity: Double {
        Self.interpolate(progress: progress, start: 0.85, mid: 0.40, end: 0.0)
    }

    var scrimTopOpacity: Double {
        Self.interpolate(progress: progress, start: 0.62, mid: 0.42, end: 0.28)
    }

    var scrimBottomOpacity: Double {
        Self.interpolate(progress: progress, start: 0.72, mid: 0.50, end: 0.34)
    }

    private static func interpolate(
        progress: Double,
        start: Double,
        mid: Double,
        end: Double
    ) -> Double {
        if progress <= 0.5 {
            let t = progress / 0.5
            return start + (mid - start) * t
        }
        let t = (progress - 0.5) / 0.5
        return mid + (end - mid) * t
    }
}

/// Three-layer clearing-fog landscape renderer capped at 30fps and Reduce Motion compliant.
struct FogView: View {
    let theme: ThemeID
    let progress: Double
    var isPaused: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var metrics: FogVisualMetrics {
        FogVisualMetrics(progress: progress)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Layer 1: Landscape photograph clearing via blur and brightness attenuation.
                Image(theme.assetName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .blur(radius: metrics.backgroundBlurRadius)
                    .brightness(metrics.backgroundBrightness)
                    .animation(.easeInOut(duration: 0.6), value: metrics.progress)

                // Layer 2: Multi-layer mist plumes (disabled horizontal drift when Reduce Motion is ON).
                TimelineView(
                    .animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion || isPaused)
                ) { timeline in
                    let elapsed = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                    Canvas { context, size in
                        drawFogLayer(
                            in: &context,
                            size: size,
                            opacity: metrics.farFogOpacity,
                            drift: reduceMotion ? 0 : sin(elapsed * 0.09) * size.width * 0.10,
                            verticalBias: 0.38,
                            plumeCount: 5,
                            radiusMultiplier: 0.58
                        )

                        drawFogLayer(
                            in: &context,
                            size: size,
                            opacity: metrics.nearFogOpacity,
                            drift: reduceMotion ? 0 : -cos(elapsed * 0.07) * size.width * 0.14,
                            verticalBias: 0.62,
                            plumeCount: 6,
                            radiusMultiplier: 0.68
                        )
                    }
                    .allowsHitTesting(false)
                }

                // Layer 3: Top & bottom contrast scrim preserving text legibility.
                LinearGradient(
                    stops: [
                        .init(color: KumogakureColors.sumiBg.opacity(metrics.scrimTopOpacity), location: 0.0),
                        .init(color: KumogakureColors.sumiBg.opacity(0.18), location: 0.48),
                        .init(color: KumogakureColors.sumiBg.opacity(metrics.scrimBottomOpacity), location: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func drawFogLayer(
        in context: inout GraphicsContext,
        size: CGSize,
        opacity: Double,
        drift: Double,
        verticalBias: Double,
        plumeCount: Int,
        radiusMultiplier: Double
    ) {
        guard opacity > 0.005 else { return }

        let baseColor = KumogakureColors.fogOverlayTint
        let baseRadius = max(size.width, size.height) * radiusMultiplier

        for index in 0..<plumeCount {
            let ratio = Double(index) / Double(max(1, plumeCount - 1))
            let centerX = size.width * (0.1 + 0.8 * ratio) + drift * (index.isMultiple(of: 2) ? 1.0 : -0.7)
            let verticalJitter = sin(Double(index) * 1.9 + verticalBias * 3.0) * size.height * 0.14
            let centerY = size.height * verticalBias + verticalJitter
            let center = CGPoint(x: centerX, y: centerY)
            let radius = baseRadius * (0.75 + 0.25 * cos(Double(index) * 1.3))

            let gradient = Gradient(stops: [
                .init(color: baseColor.opacity(opacity * 0.65), location: 0.0),
                .init(color: baseColor.opacity(opacity * 0.28), location: 0.5),
                .init(color: baseColor.opacity(0.0), location: 1.0),
            ])
            context.fill(
                Path(ellipseIn: CGRect(
                    x: center.x - radius,
                    y: center.y - radius * 0.72,
                    width: radius * 2,
                    height: radius * 1.44
                )),
                with: .radialGradient(
                    gradient,
                    center: center,
                    startRadius: 0,
                    endRadius: radius
                )
            )
        }
    }
}

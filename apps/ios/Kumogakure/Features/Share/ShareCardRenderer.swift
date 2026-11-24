import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Share modes available on S-02 (`absence-card-spec.md` §3.2).
enum ShareOutputFormat: String, CaseIterable, Identifiable, Sendable {
    case urlWithMessage
    case squareImage
    case storyImage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .urlWithMessage: return "URL＋一言"
        case .squareImage: return "画像（1:1）"
        case .storyImage: return "ストーリー（9:16）"
        }
    }

    var cardFormat: ShareCardFormat {
        switch self {
        case .urlWithMessage, .squareImage: return .square
        case .storyImage: return .story
        }
    }

    var includesImage: Bool {
        self != .urlWithMessage
    }
}

/// Canonical share text templates defined in `docs/02-design/absence-card-spec.md` §3.2.
enum ShareMessageBuilder {
    static func urlShareText(
        plannedEndsAt: Date,
        timeZone: TimeZone = .current,
        message: String?,
        shareURL: String
    ) -> String {
        let clock = DurationFormatter.clockTimeString(plannedEndsAt, timeZone: timeZone)
        let header = "ただいま雲隠れ中です（\(clock) 帰還予定）。"
        let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let firstLine = trimmed.isEmpty ? header : "\(header)\(trimmed)"
        return "\(firstLine)\n\(shareURL)\n#雲隠れ"
    }

    static func imageShareText(
        plannedEndsAt: Date,
        timeZone: TimeZone = .current,
        message: String?
    ) -> String {
        let clock = DurationFormatter.clockTimeString(plannedEndsAt, timeZone: timeZone)
        let header = "ただいま雲隠れ中です（\(clock) 帰還予定）。"
        let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let firstLine = trimmed.isEmpty ? header : "\(header)\(trimmed)"
        return "\(firstLine)\n#雲隠れ #デジタルデトックス"
    }

    static func completionShareText(actualDurationSeconds: Int) -> String {
        let duration = DurationFormatter.japaneseDuration(seconds: actualDurationSeconds)
        return "\(duration)の雲隠れから帰還しました。静かな時間でした。\n#雲隠れ"
    }
}

/// Renders metadata-free `1080x1080` or `1080x1920` PNG cards on `@MainActor`.
enum ShareCardRenderer {
    @MainActor
    static func renderPNGData(payload: AbsenceCardPayload, format: ShareCardFormat) -> Data? {
        let snapshotView = AbsenceCardSnapshotView(payload: payload, format: format)
        let renderer = ImageRenderer(content: snapshotView)
        renderer.scale = 1.0
        renderer.proposedSize = ProposedViewSize(format.pixelSize)
        #if canImport(UIKit)
        return renderer.uiImage?.pngData()
        #else
        return nil
        #endif
    }

    #if canImport(UIKit)
    @MainActor
    static func renderImage(payload: AbsenceCardPayload, format: ShareCardFormat) -> UIImage? {
        guard let pngData = renderPNGData(payload: payload, format: format) else {
            return nil
        }
        // Re-wrap encoded PNG bytes so no camera/EXIF metadata accompanies the shared UIImage.
        return UIImage(data: pngData, scale: 1.0)
    }
    #endif
}

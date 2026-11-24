# Kumogakure iOS App (`apps/ios`)

iOS 17.0+ / Swift 5.10+ / SwiftUI / SwiftData ネイティブアプリ（`SWIFT_STRICT_CONCURRENCY = complete`）。

## ディレクトリ構成（Week 3 時点）

- `Kumogakure.xcodeproj` / `project.yml` — Xcode 15.3+ プロジェクト定義（`Kumogakure` アプリ + `KumogakureTests` ユニットテスト）
- `Kumogakure/App/` — `AppConfig.swift`, `KumogakureApp.swift`, `RootView.swift`
- `Kumogakure/Core/Domain/` — `Catalog.swift`, `MorningTargetCalculator.swift`, `DurationFormatter.swift`
- `Kumogakure/Core/Storage/` — `KeychainHelper.swift`, `DetoxSessionRecord.swift`, `UserPreferencesStore.swift`
- `Kumogakure/Core/Timer/` — `ClockProviding.swift`, `DetoxTimerEngine.swift`, `AppLifecycleMonitor.swift`, `DetoxSessionStore.swift`
- `Kumogakure/Core/Audio/` — `AmbientAudioManager.swift`（`SoundID.none` 時の `AVAudioSession` 非起動厳守）
- `Kumogakure/Core/Notification/` — `NotificationScheduler.swift`
- `Kumogakure/DesignSystem/` — `KumogakureColors.swift`, `KumogakureTypography.swift`, `KumogakureComponents.swift`
- `Kumogakure/Features/`
  - `Home/` — S-01 ホーム画面（`HomeView.swift`, `CustomDurationPickerSheet.swift`）
  - `Detox/` — S-03 雲隠れ中画面・霧アニメーション（`DetoxSessionView.swift`, `FogView.swift`）
  - `Result/` — S-04 帰還完了画面（`ReturnCompleteView.swift`）、S-05 途中帰還/離脱画面（`EarlyReturnView.swift`）
  - `Placeholders/` — Week 4 接続までの橋渡しシート（`Week4BridgeSheets.swift`）
- `Kumogakure/Resources/`
  - `Info.plist`（`UIBackgroundModes: ["audio"]`, `ITSAppUsesNonExemptEncryption: false`, `CFBundleDisplayName: 雲隠れ`）
  - `Assets.xcassets/` — `Landscapes/`（4 種 `1290x2796` JPEG）, `AccentColor`, `LaunchBackground`, `AppIcon`
  - `Sounds/` — `rain.m4a`, `night_wind.m4a`, `bonfire.m4a`（AAC-LC 44.1kHz Stereo 128kbps `-19 LUFS`）
  - `ASSETS_CREDITS.md` — 画像・音声アセットの生成記録およびライセンス台帳
- `KumogakureTests/` — Protocol DI による XCTest ユニットテスト 6 スイート＋テストダブル一式

## Mac / Xcode でのビルド・テスト手順

```bash
cd apps/ios
open Kumogakure.xcodeproj

# CLI でのユニットテスト実行例（利用可能な iPhone シミュレータに合わせて destination を指定）
xcodebuild test \
  -project Kumogakure.xcodeproj \
  -scheme Kumogakure \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

## CI（GitHub Actions）

- [../../.github/workflows/ios-ci.yml](../../.github/workflows/ios-ci.yml) が `apps/ios/**` 変更時の PR / `main` push / 手動実行で `macos-15` ランナー上に最新の利用可能 iPhone シミュレータを起動し、`xcodebuild test` を自動実行します。

詳細仕様は [../../docs/03-architecture/ios-app-spec.md](../../docs/03-architecture/ios-app-spec.md) および [../../docs/02-design/design-system.md](../../docs/02-design/design-system.md) を参照してください。

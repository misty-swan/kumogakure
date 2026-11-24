# Kumogakure iOS App (`apps/ios`)

iOS 17.0+ / Swift 5.10+ / SwiftUI / SwiftData ネイティブアプリ（`SWIFT_STRICT_CONCURRENCY = complete`）。

## ディレクトリ構成（Week 4 時点）

- `Kumogakure.xcodeproj` / `project.yml` — Xcode 15.3+ プロジェクト定義（`Kumogakure` アプリ + `KumogakureTests` ユニットテスト、`Kumogakure.storekit` ローカル課金設定連動）
- `Kumogakure/App/` — `AppConfig.swift`, `KumogakureApp.swift`, `RootView.swift`
- `Kumogakure/Core/Domain/` — `Catalog.swift`, `MorningTargetCalculator.swift`, `DurationFormatter.swift`
- `Kumogakure/Core/Network/` — `KumogakureAPIClient.swift`（`POST /sessions`, `POST /finish`, `GET /stats/active`、5 秒タイムアウト）
- `Kumogakure/Core/Storage/` — `KeychainHelper.swift`, `DetoxSessionRecord.swift`, `OfflineFinishQueue.swift`, `UserPreferencesStore.swift`
- `Kumogakure/Core/Timer/` — `ClockProviding.swift`, `DetoxTimerEngine.swift`, `AppLifecycleMonitor.swift`, `DetoxSessionStore.swift`
- `Kumogakure/Core/Audio/` — `AmbientAudioManager.swift`（`SoundID.none` 時の `AVAudioSession` 非起動厳守）
- `Kumogakure/Core/Notification/` — `NotificationScheduler.swift`
- `Kumogakure/Core/Billing/` — `SubscriptionManager.swift`（StoreKit 2 ローカル `.storekit` 検証・`hermit_pro` 資格管理）
- `Kumogakure/DesignSystem/` — `KumogakureColors.swift`, `KumogakureTypography.swift`, `KumogakureComponents.swift`, `AbsenceCardSnapshotView.swift`
- `Kumogakure/Features/`
  - `Home/` — S-01 ホーム画面（`HomeView.swift`, `CustomDurationPickerSheet.swift`）
  - `Share/` — S-02 不在証明作成・SNS 画像カード生成＆OS シェアシート（`AbsenceShareView.swift`, `ShareCardRenderer.swift`, `ActivityViewControllerWrapper.swift`）
  - `Detox/` — S-03 雲隠れ中画面・霧アニメーション（`DetoxSessionView.swift`, `FogView.swift`）
  - `Result/` — S-04 帰還完了画面（`ReturnCompleteView.swift`）、S-05 途中帰還/離脱画面（`EarlyReturnView.swift`）
  - `History/` — S-06 雲隠れ帳・7 日制限・Swift Charts 統計（`HistoryView.swift`, `HistoryAnalytics.swift`）
  - `Paywall/` — S-07 隠者プラン Paywall・3.1.2 準拠（`PaywallView.swift`）
  - `Settings/` — S-08 設定画面・法務/Google フォームブラウザ（`SettingsView.swift`, `SafariWebView.swift`）
- `Kumogakure/Resources/`
  - `Info.plist`（`UIBackgroundModes: ["audio"]`, `ITSAppUsesNonExemptEncryption: false`, `CFBundleDisplayName: 雲隠れ`）
  - `Kumogakure.storekit` — Xcode StoreKit Configuration v3（年額 ¥2,400・7 日間無料トライアル / 月額 ¥300）
  - `Assets.xcassets/` — `Landscapes/`（4 種 `1290x2796` JPEG）, `AccentColor`, `LaunchBackground`, `AppIcon`
  - `Sounds/` — `rain.m4a`, `night_wind.m4a`, `bonfire.m4a`（AAC-LC 44.1kHz Stereo 128kbps `-19 LUFS`）
  - `ASSETS_CREDITS.md` — 画像・音声アセットの生成記録およびライセンス台帳
- `KumogakureTests/` — Protocol DI・`URLProtocol` スタブ・`SKTestSession` による XCTest ユニットテスト 10 スイート＋テストダブル一式

## Mac / Xcode でのビルド・テスト手順

```bash
cd apps/ios
open Kumogakure.xcodeproj

# CLI でのユニットテスト実行例（利用可能な iPhone シミュレータに合わせて destination を指定）
xcodebuild test \
  -project Kumogakure.xcodeproj \
  -scheme Kumogakure \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

## CI（GitHub Actions）

- [../../.github/workflows/ios-ci.yml](../../.github/workflows/ios-ci.yml) が `apps/ios/**` 変更時の PR / `main` push / 手動実行で `macos-15` ランナー上に最新の利用可能 iPhone シミュレータを起動し、`xcodebuild test` を自動実行します。

詳細仕様は [../../docs/03-architecture/ios-app-spec.md](../../docs/03-architecture/ios-app-spec.md) および [../../docs/02-design/design-system.md](../../docs/02-design/design-system.md) を参照してください。

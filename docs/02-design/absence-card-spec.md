# 不在証明 Web・OGP 画像・SNS カード仕様書

『雲隠れ』のバイラルループの中核となる「不在証明 Web ページ（`/s/{id}`）」「動的 OGP 画像（`/ogp/{id}.png`）」「iOS 端末内生成 SNS カード」のレイアウトおよび生成ルールを定義します。

---

## 1. 不在証明 Web ページ（`GET /s/{id}`）

### 1.1 HTML ヘッド・OGP メタタグ仕様
X（旧 Twitter）、LINE、Facebook、Slack、Discord 等のクローラーが正しくカードを展開できるよう、以下のメタタグをサーバーサイド HTML（Askama テンプレート）に必ず出力します。

```html
<!DOCTYPE html>
<html lang="ja">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="robots" content="noindex, nofollow">
  <title>{display_name_or_default}はただいま雲隠れ中です | 雲隠れ</title>
  <meta name="description" content="{planned_return_text}。{message}">

  <!-- Open Graph -->
  <meta property="og:type" content="website">
  <meta property="og:site_name" content="雲隠れ - Kumogakure">
  <meta property="og:title" content="{og_title}">
  <meta property="og:description" content="{og_description}">
  <meta property="og:url" content="https://kumogakure.app/s/{id}">
  <meta property="og:image" content="https://kumogakure.app/ogp/{id}.png">
  <meta property="og:image:width" content="1200">
  <meta property="og:image:height" content="630">
  <meta property="og:image:type" content="image/png">

  <!-- Twitter / X Card -->
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="{og_title}">
  <meta name="twitter:description" content="{og_description}">
  <meta name="twitter:image" content="https://kumogakure.app/ogp/{id}.png">
</head>
```

> **URL 設計の注意**: `og:image` はセッション ID ごとに一意な `/ogp/{id}.png` であり、クエリパラメータを含めないことで Cloudflare CDN のキャッシュヒット率を最大化します。

### 1.2 Web ページ上の表示構成（状態別）
1. **ヘッダー**: 小さな和紋ロゴ「雲隠れ」。
2. **ステータスカード**:
   - `active`（現在進行中）: ステータスバッジ「雲隠れ中」＋ 帰還予定時刻（`timezone` でフォーマット、例: `21:30 頃帰還予定 (JST)`）＋ 表示名（未設定時は「旅人」ではなく省略し「ただいま、雲隠れしています」）＋ 一言メッセージ ＋ 帰還までのおおよその残り目安。
   - `completed`（帰還済み）: ステータスバッジ「帰還済み」＋「{帰還時刻} に雲隠れから帰還しました」。
   - `canceled`（途中帰還）: ステータスバッジ「ひと足早く帰還」＋「予定より少し早く雲の中から戻りました」。
   - `410 Gone`（発行 24 時間経過）: 「この不在証明は役目を終えて霧に溶けました」。
3. **アプリ誘導フッター CTA**:
   - コピー: 「罪悪感なく、少しだけ世間から離れませんか？」
   - App Store バッジ / ダウンロードリンク（`?utm_source=absence_card&utm_medium=web`）。
4. **安全・法務リンク**:
   - プライバシーポリシー、利用規約、および **「不適切な内容を報告する」** リンク（Google フォームへ遷移し、`?entry.<field_id>={session_id}` 等で対象セッション ID を自動事前入力して個人連絡先を非公開のまま UGC 対策・App Store 審査対応を実現）。

---

## 2. 動的 OGP 画像（`GET /ogp/{id}.png`）詳細仕様

Rust バックエンドで Askama（XML エスケープ有効）による SVG 生成 → `resvg` によるラスタライズで **1200 x 630 px PNG** を生成します。

### 2.1 デザインテーマ（`card_style`）別カラー定義

| `card_style` | プラン | 背景色 | 外枠・罫線色 | 主テキスト色 | 副テキスト色 | 落款・印色 |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `washi_classic` | 無料 / Pro | `#F4F0E6`（和紙） | `#D6CFC2` | `#1E2022`（墨） | `#5A5E63` | `#B84A39`（朱印） |
| `sumi_night` | Pro 限定 | `#12151B`（深墨） | `#2F3745` | `#EAE6DF`（生成り） | `#9CA3AE` | `#C79A63`（金茶） |
| `indigo_mist` | Pro 限定 | `#132230`（藍鼠） | `#324A5F` | `#ECE9E2` | `#A2B3C2` | `#C79A63`（金茶） |

### 2.2 レイアウト座標設計（1200 x 630 px）

```text
+-------------------------------------------------------------------+ (0,0)
|  +-------------------------------------------------------------+  |
|  | [左上: 和風雲紋章 SVG]            [右上: 落款印 "隠" 48x48]  |  |
|  |                                                             |  |
|  |          ただいま、雲隠れ中                                 |  |
|  |                                                             |  |
|  |          帰還予定： 21:30 頃 (JST)                           |  |
|  |                                                             |  |
|  |          「読書してきます。通知オフ中です」                  |  |
|  |          ── 霧崎 ──                                        |  |
|  |                                                             |  |
|  |  [テーマタグ: 霧の山並み]      [右下透かし: 雲隠れ - Kumogakure]|  |
|  +-------------------------------------------------------------+  |
+-------------------------------------------------------------------+ (1200,630)
```

- **外周マージン**: `36px`（二重細枠 `1.5px` + 内側 `6px` に `0.75px` 罫線）。SNS の丸角クロップ（X や LINE）で文字が切れないよう、テキスト安全領域は内枠からさらに `48px` 内側（`x: 96..1104`, `y: 84..546`）に収める。
- **フォントファミリー**: `font-family="Shippori Mincho, Noto Serif JP, serif"`（`Shippori Mincho` を優先し、未収録漢字を `Noto Serif JP` でフォールバック）。
- **タイトル**: `ただいま、雲隠れ中`（font-size: `44px`）。
- **帰還予定時刻**: `帰還予定：{HH:mm} 頃`（font-size: `34px`, タイムゾーン表記付き。`Asia/Tokyo` なら `(JST)`、それ以外は IANA 短縮またはオフセット）。
- **一言メッセージ**:
  - 最大 40 文字。**1 行 20 文字を目安に最大 2 行に自動折り返し**（絵文字やサロゲートペア、結合文字で壊れないよう Rust `unicode-segmentation` で書記素単位分割）。
  - 2 行を超える場合（半角/全角混在での幅超過含む）は 38 文字以降を `…` で省略する。
- **表示名（`display_name`）**:
  - 存在する場合のみ `── {display_name} ──` を表示（最大 20 文字）。`NULL` または空文字の場合は行自体を詰めて非表示にする。
- **透かし（バイラル要素）**:
  - `hide_watermark == 0`（無料プラン、または Pro で表示 ON の場合）: 右下安全領域に `雲隠れ - Kumogakure`（font-size: `20px`, 透明度 `0.65`）を描画。
  - `hide_watermark == 1`（Pro 限定オプション）: 透かし文字を完全に非描画。

---

## 3. iOS 端末内生成 SNS 画像カード仕様

SNS（特に画像添付が主流の X や、URL リンクが標準アカウントでは貼れない場合がある Instagram ストーリー）向けに、iOS アプリ内で `SwiftUI ImageRenderer` を使って高解像度 PNG を生成します。

### 3.1 サイズ規格

| フォーマット | ピクセルサイズ（`@1x` レンダリング `scale: 1.0`） | 主なシェア先 | レイアウト特徴 |
| :--- | :--- | :--- | :--- |
| **正方形カード** | `1080 x 1080 px` | X（Twitter）・LINE 画像送信 | 中央に不在証明文面、背景に薄霧＋風景アイコン |
| **ストーリー縦長カード** | `1080 x 1920 px`（9:16） | Instagram ストーリー | 上下に十分な余白（IG の上部アイコン・下部スワイプ UI 避けに上下 `260px` のセーフゾーン確保） |

### 3.2 レンダリング・共有制約
- `ImageRenderer` はメインスレッド（`@MainActor`）で実行し、生成される `UIImage` のメタデータ（EXIF 等）を含まないクリーンな PNG/JPEG として `UIActivityViewController` へ渡す。
- Web URL と画像を同時にシェアする場合、LINE 等の一部アプリで URL プレビューと画像が競合することがあるため、S-02 画面で「URL＋一言でシェア」か「画像カードでシェア」かを明確に切り替えられる UI を提供する。
- シェア時デフォルト文言テンプレート:
  - URL シェア時: `ただいま雲隠れ中です（{HH:mm} 帰還予定）。{一言}\n{url}\n#雲隠れ`
  - 画像のみシェア時: `ただいま雲隠れ中です（{HH:mm} 帰還予定）。{一言}\n#雲隠れ #デジタルデトックス`
  - 帰還完了シェア時: `{時間}の雲隠れから帰還しました。静かな時間でした。\n#雲隠れ`

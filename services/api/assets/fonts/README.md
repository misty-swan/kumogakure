# OGP レンダリング用和文フォント（SIL OFL 1.1）

動的 OGP PNG（`1200 x 630 px`、`resvg` / `fontdb`）レンダリング用としてコンテナに同梱する日本語明朝体フォントとライセンスファイルです（正本: [../../../../docs/01-product/open-questions.md](../../../../docs/01-product/open-questions.md) OQ-10、[../../../../docs/03-architecture/backend-spec.md](../../../../docs/03-architecture/backend-spec.md)）。

## 同梱ファイル一覧

| ファイル名 | 役割 | ライセンス | サイズ (bytes) | SHA-256 | 出典 URL |
| :--- | :--- | :--- | ---: | :--- | :--- |
| `ShipporiMincho-Regular.ttf` | メイン明朝体（`"Shippori Mincho"`） | SIL OFL 1.1（`OFL-ShipporiMincho.txt`） | 8,677,284 | `769b5269f0f9bc6534b352c0e6bd856a566e03ff788f107191c2d835863570b2` | https://raw.githubusercontent.com/google/fonts/main/ofl/shipporimincho/ShipporiMincho-Regular.ttf |
| `NotoSerifJP-Regular.otf` | フォールバック明朝体（`"Noto Serif JP"`） | SIL OFL 1.1（`OFL-NotoSerifJP.txt`） | 6,210,492 | `2c9a12dbd4f2408c4610c7ee84a108b62d7236c3775baed618c64d9cb44b2f04` | https://raw.githubusercontent.com/notofonts/noto-cjk/main/Serif/SubsetOTF/JP/NotoSerifJP-Regular.otf |
| `OFL-ShipporiMincho.txt` | Shippori Mincho ライセンス全文 | SIL OFL 1.1 | 4,399 | `41fba056279be5f45ff9a99e44b7b53897b42732f5806d8e666e0ab49ac6bd38` | https://raw.githubusercontent.com/google/fonts/main/ofl/shipporimincho/OFL.txt |
| `OFL-NotoSerifJP.txt` | Noto Serif JP ライセンス全文 | SIL OFL 1.1 | 4,301 | `6a73f9541c2de74158c0e7cf6b0a58ef774f5a780bf191f2d7ec9cc53efe2bf2` | https://raw.githubusercontent.com/notofonts/noto-cjk/main/Serif/LICENSE |

## 選定・互換性注記

- Google Fonts リポジトリ上の `NotoSerifJP[wght].ttf` は可変フォント（13.5MB）であり、`resvg` / `usvg` が静的ウェイトとして描画できない場合があるため、公式 `notofonts/noto-cjk` リポジトリの静的 Regular サブセット（`SubsetOTF/JP/NotoSerifJP-Regular.otf`、約 6.2MB）を採用しています。
- SVG テンプレート上では `font-family="Shippori Mincho, Noto Serif JP, serif"` を指定し、`fontdb` 起動時プリロード時に `set_serif_family("Shippori Mincho")` を設定します。

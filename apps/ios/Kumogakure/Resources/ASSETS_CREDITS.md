# 素材アセット生成・調達・権利記録台帳（W1-2 / W1-3）

本ファイルは『雲隠れ（Kumogakure）』iOS アプリ同梱の風景画像（4 種）および環境音（3 種）について、作成履歴・技術規格・出典・ライセンス証跡を記録する管理台帳です（正本: [../../../../docs/02-design/design-system.md](../../../../docs/02-design/design-system.md) §6、[../../../../docs/01-product/open-questions.md](../../../../docs/01-product/open-questions.md) OQ-11）。

---

## 1. 風景画像アセット（W1-2：`1290 x 2796 px` / `<= 600 KB`）

### 共通制作・最適化記録
- **生成日**: `2026-11-20`
- **生成ツール**: Google DeepMind 画像生成サブエージェント（`image-generator`、9:16 縦長生成、`768 x 1376` 原画出力）
- **後処理**: Python 3 + Pillow `12.1.1` により `ImageOps.exif_transpose` 適用・EXIF/メタデータ除去・sRGB `RGB` 変換・`ImageOps.fit(..., (1290, 2796), LANCZOS)` で `1290 x 2796 px` へリサイズ・トリミングし、Progressive JPEG (`quality=88, optimize=True, subsampling="4:2:0"`) で 600 KB 以下へ最適化。
- **権利・利用条件確認**: 開発環境内蔵の `image-generator` により独自プロンプトで新規生成したオリジナル素材であり、既存著作物・人物・ロゴ・ウォーターマーク・文字要素を含まないことを目視確認済み。

### 個別ファイル仕様とプロンプト記録

| `theme_id` | 日本語名 | プラン | 配置パス | 解像度 | サイズ (bytes) | SHA-256 |
| :--- | :--- | :--- | :--- | :--- | ---: | :--- |
| `misty_mountain` | 霧の山並み | 無料 | `Assets.xcassets/Landscapes/misty_mountain.imageset/misty_mountain.jpg` | `1290 x 2796` | 278,859 (272.3 KiB) | `54fe6974ecd4766b20a74431f89fba7d9cb17aa1b806b81023530fadae1444c0` |
| `rainy_bamboo` | 雨の竹林 | 無料 | `Assets.xcassets/Landscapes/rainy_bamboo.imageset/rainy_bamboo.jpg` | `1290 x 2796` | 504,263 (492.4 KiB) | `d60bc93f3aff8a12e6fca4b57233f0e2ca375224e1ebdc65914f6f5b4fd8fd9f` |
| `moonlit_lake` | 月夜の湖畔 | Pro（隠者） | `Assets.xcassets/Landscapes/moonlit_lake.imageset/moonlit_lake.jpg` | `1290 x 2796` | 228,625 (223.3 KiB) | `cca46134bf80df669cb9d8f1a9cd2652a3cf79bcdb071bea791ecc40e819207f` |
| `dawn_shrine` | 夜明けの社 | Pro（隠者） | `Assets.xcassets/Landscapes/dawn_shrine.imageset/dawn_shrine.jpg` | `1290 x 2796` | 277,824 (271.3 KiB) | `48f9fe8e942462003297574eba9a15eee23981f3f7d4a4ac104d7ff5f6db73ad` |

<details>
<summary>使用プロンプト要約（全 4 テーマ共通トーン：静謐・和モダン・上下スクリム余白）</summary>

1. **`misty_mountain`**: 9:16 vertical sumi-e ink-wash mood meets misty fine-art Japanese landscape photography; charcoal slate and soft silver-gray fog (`#0F1216` to `#D8DEE6`), layered mountain ridges and pine silhouettes in center, calm uncluttered dark sky in upper 25% and misty shadow in lower 20%, no text/logos/watermarks/people/borders.
2. **`rainy_bamboo`**: 9:16 twilight rainy Japanese bamboo grove path; muted deep moss-green and charcoal bamboo stalks fading into cool silver mist and gentle rain with damp stone path, uncluttered dark foliage/haze in upper 25% and lower 20%, no text/logos/watermarks/people/borders.
3. **`moonlit_lake`**: 9:16 nocturnal Japanese mountain lake reflecting a mist-veiled full moon; deep sumi-indigo night sky (`#0F1216` to `#1B2A38`), distant mountain silhouettes, subtle moonlight shimmer on still water, uncluttered dark sky above and still water below, no text/logos/watermarks/people/boats/borders.
4. **`dawn_shrine`**: 9:16 pre-dawn Japanese mountain shrine with weathered wooden torii gate and cedar trees in drifting valley mist; deep twilight-indigo upper sky and dark stone steps below transitioning to muted shinonome amber-gold (`#C79A63`) near the horizon, no text/logos/watermarks/people/borders.

</details>

---

## 2. 環境音 BGM アセット（W1-3：AAC-LC / 44.1kHz / Stereo / 128kbps / 60s シームレスループ / -19 LUFS）

### 共通加工・品質基準
- **加工日**: `2026-11-20`
- **処理パイプライン（`ffmpeg`）**:
  1. ソースを 44.1kHz ステレオ PCM に展開し、`highpass=f=30` で DC オフセット除去＋各トラック用トーンシェイピング適用。
  2. 必要長まで等パワー `acrossfade`（`qsin` カーブ）で継ぎ目なく延長し、モノラル原音は位相干渉を起こさない時間オフセット（+11.3s / +21.7s）の微小ステレオ空気感レイヤーを加味。
  3. 先頭 4 秒と末尾 4 秒を等パワー（`qsin`）クロスフェード合成して厳密に **`60.000 秒`** のシームレスループを構築。
  4. 2-pass 線形 EBU R128 ラウドネス正規化（目標 `-19.0 LUFS`, True Peak `-1.5 dBTP`）を実施。
  5. `aac -profile:a aac_low -ar 44100 -ac 2 -b:a 128k -movflags +faststart` で `.m4a` エンコードし、60 秒ループ境界（52s〜68s）を接続試聴してクリックノイズ・途切れがないことを確認済み。

### 出典・ライセンス・実測値一覧

| `sound_id` | 日本語名 | プラン | 配置パス | 実測尺 / ビットレート | 統合ラウドネス | サイズ (bytes) | SHA-256 |
| :--- | :--- | :--- | :--- | :--- | :--- | ---: | :--- |
| `rain` | 雨音 | 無料 | `Sounds/rain.m4a` | `60.000s` / `129.6 kbps` | `-19.11 LUFS` | 971,876 (949.1 KiB) | `1dc0cce99456e04d9786de4544b155e43b4b37c402060c98e2667878cc7152a2` |
| `night_wind` | 夜風 | 無料 | `Sounds/night_wind.m4a` | `60.000s` / `129.6 kbps` | `-19.01 LUFS` | 971,883 (949.1 KiB) | `b7d10db4f6d59d5e9836aeecbfe01f85a077d84c5fe8f1a836e0fda7ea43a821` |
| `bonfire` | 焚き火 | Pro（隠者） | `Sounds/bonfire.m4a` | `60.000s` / `129.6 kbps` | `-19.19 LUFS` | 971,926 (949.1 KiB) | `a080e5283beaedda53195c905010eee67f830f0b92e09cc5743a4e3726bb5a74` |

#### 出典・ライセンス詳細
1. **`rain.m4a`**
   - **原題 / 作者**: `Rain` by `ezwa`（PDsounds.org 由来の Wikimedia Commons アーカイブ）
   - **出典ページ**: https://commons.wikimedia.org/wiki/File:Rain_%281%29.ogg
   - **原ファイル URL**: https://upload.wikimedia.org/wikipedia/commons/0/0e/Rain_%281%29.ogg
   - **ライセンス**: **Public Domain**（Wikimedia Commons `PD-author` / PDsounds.org パブリックドメイン素材、帰属表示不要・商用利用可）
   - **適用フィルタ**: `highpass=f=80,lowpass=f=6500`（高域ヒスノイズの抑制）
2. **`night_wind.m4a`**
   - **原題 / 作者**: `wind1`（`five 1 minute long synthesized wind sounds` より）by `Luke.RUSTLTD`
   - **出典ページ**: https://opengameart.org/content/wind1
   - **原ファイル URL**: https://opengameart.org/sites/default/files/wind1.wav
   - **ライセンス**: **CC0 1.0 Universal (Public Domain Dedication)**（https://creativecommons.org/publicdomain/zero/1.0/ 、帰属表示不要・商用利用可）
   - **適用フィルタ**: `highpass=f=70,lowpass=f=3500`（夜間木立風の柔らかなトーン調整）
3. **`bonfire.m4a`**
   - **原題 / 作者**: `Dry grass burning in open fireplace` by `ezwa`（PDsounds.org 由来の Wikimedia Commons アーカイブ）
   - **出典ページ**: https://commons.wikimedia.org/wiki/File:Dry_grass_burning_in_open_fireplace.ogg
   - **原ファイル URL**: https://upload.wikimedia.org/wikipedia/commons/d/d8/Dry_grass_burning_in_open_fireplace.ogg
   - **ライセンス**: **Public Domain**（Wikimedia Commons `PD-author` / PDsounds.org パブリックドメイン素材、帰属表示不要・商用利用可）
   - **適用フィルタ**: `highpass=f=70,lowpass=f=8500`（耳障りな高域ピークを抑えた穏やかな薪爆ぜトーン）

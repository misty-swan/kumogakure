-- 雲隠れ（Kumogakure）初期スキーマ定義
-- 正本: docs/03-architecture/database-design.md

CREATE TABLE IF NOT EXISTS _schema_migrations (
    version TEXT PRIMARY KEY,
    applied_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS sessions (
    id TEXT PRIMARY KEY,                              -- 10文字URL安全nanoid (例: "k9x2m7p4q8", 約60bitエントロピー)
    user_uuid TEXT NOT NULL,                          -- 端末生成の匿名UUID v4
    owner_token_hash TEXT NOT NULL,                   -- セッション操作用トークン(32byte hex)のSHA-256 hex
    display_name TEXT,                                -- 任意の表示名 (最大20文字, NULL可)
    message TEXT,                                     -- 一言メッセージ (最大40文字, NULL可)
    theme_id TEXT NOT NULL,                           -- 'misty_mountain' | 'rainy_bamboo' | 'moonlit_lake' | 'dawn_shrine'
    card_style TEXT NOT NULL DEFAULT 'washi_classic', -- 'washi_classic' | 'sumi_night' | 'indigo_mist'
    hide_watermark INTEGER NOT NULL DEFAULT 0,        -- 0: 透かし表示, 1: 非表示 (Proサーバー検証済)
    is_public INTEGER NOT NULL DEFAULT 0,             -- 0: 非公開(同時人数集計のみ), 1: 不在証明URL公開
    timezone TEXT NOT NULL DEFAULT 'Asia/Tokyo',      -- IANAタイムゾーン文字列
    status TEXT NOT NULL,                             -- 'active' | 'completed' | 'canceled'
    started_at INTEGER NOT NULL,                      -- UNIX秒(UTC)
    ends_at INTEGER NOT NULL,                         -- 帰還予定UNIX秒(UTC)
    finished_at INTEGER,                              -- 実際の終了UNIX秒(UTC)
    expires_at INTEGER NOT NULL                       -- 自動失効UNIX秒(UTC; started_at + 86400)
);

CREATE INDEX IF NOT EXISTS idx_sessions_active ON sessions (status, ends_at);
CREATE INDEX IF NOT EXISTS idx_sessions_user_active ON sessions (user_uuid, status);
CREATE INDEX IF NOT EXISTS idx_sessions_expires_at ON sessions (expires_at);

INSERT OR IGNORE INTO _schema_migrations (version, applied_at)
VALUES ('0001_init', unixepoch());

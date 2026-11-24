use unicode_segmentation::UnicodeSegmentation;

use crate::error::AppError;

pub const MAX_DISPLAY_NAME_GRAPHEMES: usize = 20;
pub const MAX_MESSAGE_GRAPHEMES: usize = 40;
const OGP_LINE_MAX_WIDTH: usize = 38;

/// Built-in moderation blocklist covering severe slurs, spam/phishing cues, and explicit UGC abuse.
const BUILTIN_NG_WORDS: &[&str] = &[
    // Japanese severe harassment / slurs / illegal / explicit spam
    "死ね",
    "しね",
    "殺す",
    "ころす",
    "自殺",
    "リスカ",
    "売春",
    "援助交際",
    "援交",
    "パパ活",
    "詐欺",
    "闇バイト",
    "裏垢",
    "エロ動画",
    "アダルト",
    "キチガイ",
    "基地外",
    "障害者",
    "ガイジ",
    "池沼",
    "カス",
    "ゴミ人間",
    // English severe slurs / abuse / spam
    "kill yourself",
    "kys",
    "nigger",
    "faggot",
    "retard",
    "porn",
    "casino",
    "crypto giveaway",
    "airdrop",
];

#[derive(Debug, Clone)]
pub struct Sanitizer {
    ng_words_lower: Vec<String>,
}

impl Sanitizer {
    pub fn new(extra_ng_words: &[String]) -> Self {
        let mut ng_words_lower: Vec<String> = BUILTIN_NG_WORDS
            .iter()
            .map(|w| w.to_ascii_lowercase())
            .collect();

        for word in extra_ng_words {
            let trimmed = word.trim();
            if !trimmed.is_empty() {
                ng_words_lower.push(trimmed.to_lowercase());
            }
        }

        Self { ng_words_lower }
    }

    /// Normalize, validate control characters, enforce grapheme length, and check URL/NG-word policy.
    pub fn sanitize_text(
        &self,
        input: Option<&str>,
        max_graphemes: usize,
        field: &'static str,
    ) -> Result<Option<String>, AppError> {
        let Some(raw) = input else {
            return Ok(None);
        };

        if contains_forbidden_control_char(raw) {
            return Err(AppError::validation(
                field,
                "使用できない制御文字が含まれています。",
            ));
        }

        let normalized = normalize_whitespace(raw);
        if normalized.is_empty() {
            return Ok(None);
        }

        let grapheme_count = normalized.graphemes(true).count();
        if grapheme_count > max_graphemes {
            return Err(AppError::validation(
                field,
                format!("最大 {max_graphemes} 文字以内で入力してください。"),
            ));
        }

        if contains_url_or_spam_scheme(&normalized) {
            return Err(AppError::ContentPolicyViolation {
                field,
                message: "URL や外部リンクを含む文言は登録できません。".to_string(),
            });
        }

        let lower = normalized.to_lowercase();
        if self.ng_words_lower.iter().any(|ng| lower.contains(ng)) {
            return Err(AppError::ContentPolicyViolation {
                field,
                message: "利用規約に反する不適切な表現が含まれています。".to_string(),
            });
        }

        Ok(Some(normalized))
    }
}

fn contains_forbidden_control_char(s: &str) -> bool {
    s.chars().any(|c| {
        if matches!(c, '\r' | '\n' | '\t') {
            return false;
        }
        // Keep ZWJ / variation selectors intact so emoji sequences (e.g. 👨‍👩‍👧) work cleanly.
        if matches!(c, '\u{200D}' | '\u{FE0E}' | '\u{FE0F}') {
            return false;
        }
        if c.is_control() {
            return true;
        }
        // Reject bidirectional control overrides/isolates (Trojan Source / spoofing).
        matches!(
            c,
            '\u{061C}' | '\u{200E}' | '\u{200F}' | '\u{202A}'..='\u{202E}' | '\u{2066}'..='\u{2069}'
        )
    })
}

fn normalize_whitespace(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut chars = s.chars().peekable();
    while let Some(c) = chars.next() {
        match c {
            '\r' => {
                if chars.peek() == Some(&'\n') {
                    chars.next();
                }
                out.push(' ');
            }
            '\n' | '\t' => out.push(' '),
            other => out.push(other),
        }
    }
    out.trim().to_string()
}

fn contains_url_or_spam_scheme(s: &str) -> bool {
    let mut folded = String::with_capacity(s.len());
    for c in s.chars() {
        if matches!(c, '\u{200B}' | '\u{FEFF}' | '\u{200C}' | '\u{00AD}') {
            continue;
        }
        let mapped = match c {
            'Ａ'..='Ｚ' => char::from_u32(c as u32 - 'Ａ' as u32 + 'A' as u32).unwrap_or(c),
            'ａ'..='ｚ' => char::from_u32(c as u32 - 'ａ' as u32 + 'a' as u32).unwrap_or(c),
            '０'..='９' => char::from_u32(c as u32 - '０' as u32 + '0' as u32).unwrap_or(c),
            '：' => ':',
            '／' => '/',
            '．' => '.',
            other => other,
        };
        folded.push(mapped);
    }

    let lower = folded.to_ascii_lowercase();
    [
        "http://",
        "https://",
        "ftp://",
        "javascript:",
        "data:",
        "www.",
    ]
    .iter()
    .any(|needle| lower.contains(needle))
}

fn grapheme_width(g: &str) -> usize {
    if g.is_ascii() {
        1
    } else {
        2
    }
}

/// Wrap `"「{message}」"` into at most two SVG `<text>` lines using grapheme boundaries.
/// If the message overflows two lines, truncate safely and append `"…」"`.
pub fn wrap_ogp_message(message: &str) -> (String, Option<String>) {
    let quoted = format!("「{message}」");
    let graphemes: Vec<&str> = quoted.graphemes(true).collect();

    let mut line1 = String::new();
    let mut line1_width = 0usize;
    let mut idx = 0usize;

    while idx < graphemes.len() {
        let g = graphemes[idx];
        let w = grapheme_width(g);
        if line1_width + w > OGP_LINE_MAX_WIDTH && !line1.is_empty() {
            break;
        }
        line1.push_str(g);
        line1_width += w;
        idx += 1;
    }

    if idx >= graphemes.len() {
        return (line1, None);
    }

    let remaining = &graphemes[idx..];
    let remaining_width: usize = remaining.iter().map(|g| grapheme_width(g)).sum();

    if remaining_width <= OGP_LINE_MAX_WIDTH {
        let line2: String = remaining.concat();
        return (line1, Some(line2));
    }

    // Reserve 4 width units for `"…」"` (2 + 2) so the truncated line stays within safe bounds.
    let budget = OGP_LINE_MAX_WIDTH.saturating_sub(4);
    let mut line2 = String::new();
    let mut line2_width = 0usize;
    for &g in remaining {
        let w = grapheme_width(g);
        if line2_width + w > budget {
            break;
        }
        line2.push_str(g);
        line2_width += w;
    }
    line2.push_str("…」");

    (line1, Some(line2))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sanitizer() -> Sanitizer {
        Sanitizer::new(&["カスタム禁止語".to_string()])
    }

    #[test]
    fn accepts_valid_japanese_and_emoji_clusters_at_exact_boundaries() {
        let s = sanitizer();

        // 20 family-emoji grapheme clusters should pass display_name (<= 20)
        let twenty_families = "👨‍👩‍👧".repeat(20);
        assert_eq!(twenty_families.graphemes(true).count(), 20);
        let res = s
            .sanitize_text(
                Some(&twenty_families),
                MAX_DISPLAY_NAME_GRAPHEMES,
                "display_name",
            )
            .expect("20 emoji grapheme clusters must be accepted");
        assert_eq!(res.as_deref(), Some(twenty_families.as_str()));

        // 21 clusters must fail with 422
        let twenty_one = "👨‍👩‍👧".repeat(21);
        let err = s
            .sanitize_text(
                Some(&twenty_one),
                MAX_DISPLAY_NAME_GRAPHEMES,
                "display_name",
            )
            .unwrap_err();
        assert!(matches!(
            err,
            AppError::Validation {
                field: Some("display_name"),
                ..
            }
        ));

        // 40 Japanese characters must pass message (<= 40)
        let forty_jp = "あ".repeat(40);
        assert!(s
            .sanitize_text(Some(&forty_jp), MAX_MESSAGE_GRAPHEMES, "message")
            .unwrap()
            .is_some());

        let forty_one_jp = "あ".repeat(41);
        assert!(matches!(
            s.sanitize_text(Some(&forty_one_jp), MAX_MESSAGE_GRAPHEMES, "message"),
            Err(AppError::Validation {
                field: Some("message"),
                ..
            })
        ));
    }

    #[test]
    fn normalizes_whitespace_and_rejects_control_and_bidi_chars() {
        let s = sanitizer();
        assert_eq!(
            s.sanitize_text(Some("   "), MAX_DISPLAY_NAME_GRAPHEMES, "display_name")
                .unwrap(),
            None
        );

        let normalized = s
            .sanitize_text(
                Some("  読書\r\nしてきます\t "),
                MAX_MESSAGE_GRAPHEMES,
                "message",
            )
            .unwrap();
        assert_eq!(normalized.as_deref(), Some("読書 してきます"));

        let nul_err = s
            .sanitize_text(Some("abc\0def"), MAX_DISPLAY_NAME_GRAPHEMES, "display_name")
            .unwrap_err();
        assert!(matches!(nul_err, AppError::Validation { .. }));

        let bidi_err = s
            .sanitize_text(Some("hello\u{202E}world"), MAX_MESSAGE_GRAPHEMES, "message")
            .unwrap_err();
        assert!(matches!(bidi_err, AppError::Validation { .. }));
    }

    #[test]
    fn blocks_urls_and_ng_words_with_content_policy_violation() {
        let s = sanitizer();

        for bad_url in [
            "見てね https://evil.example/phish",
            "HTTP://spam.example",
            "ｈｔｔｐｓ：／／ｓｐａｍ．ｊｐ",
            "www.example.com",
            "javascript:alert(1)",
        ] {
            let err = s
                .sanitize_text(Some(bad_url), MAX_MESSAGE_GRAPHEMES, "message")
                .unwrap_err();
            assert!(
                matches!(
                    err,
                    AppError::ContentPolicyViolation {
                        field: "message",
                        ..
                    }
                ),
                "expected URL rejection for {bad_url}"
            );
        }

        for bad_word in ["お前死ねよ", "これはカスタム禁止語です"] {
            let err = s
                .sanitize_text(Some(bad_word), MAX_MESSAGE_GRAPHEMES, "message")
                .unwrap_err();
            assert!(matches!(
                err,
                AppError::ContentPolicyViolation {
                    field: "message",
                    ..
                }
            ));
        }
    }

    #[test]
    fn xss_payload_is_preserved_as_plain_text_for_template_auto_escaping() {
        let s = sanitizer();
        let out = s
            .sanitize_text(
                Some("<script>alert(1)</script>"),
                MAX_MESSAGE_GRAPHEMES,
                "message",
            )
            .unwrap();
        assert_eq!(out.as_deref(), Some("<script>alert(1)</script>"));
    }

    #[test]
    fn wrap_ogp_message_handles_short_two_line_and_emoji_overflow() {
        let (l1, l2) = wrap_ogp_message("読書してきます");
        assert_eq!(l1, "「読書してきます」");
        assert_eq!(l2, None);

        let long_jp = "静かな森の中で深呼吸しながら長編小説をじっくり読んで過ごします";
        let (l1, l2) = wrap_ogp_message(long_jp);
        assert!(!l1.is_empty());
        assert!(l2.is_some());

        let max_forty = "あ".repeat(40);
        let (l1, l2) = wrap_ogp_message(&max_forty);
        assert_eq!(l1.graphemes(true).count(), 19);
        let l2 = l2.expect("40 chars should wrap to line 2");
        assert!(l2.ends_with("…」"));

        // Ensure emoji clusters are never split mid-grapheme (both fitting 2 lines and overflowing)
        let emoji_fit = "👨‍👩‍👧".repeat(30);
        let (ef1, ef2) = wrap_ogp_message(&emoji_fit);
        assert!(ef1.starts_with('「'));
        assert!(ef2.unwrap().ends_with('」'));

        let emoji_overflow = "👨‍👩‍👧".repeat(40);
        let (e1, e2) = wrap_ogp_message(&emoji_overflow);
        assert!(e1.starts_with('「'));
        assert!(e2.unwrap().ends_with("…」"));
    }
}

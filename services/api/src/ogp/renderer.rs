use std::sync::Arc;

use askama::Template;
use resvg::{tiny_skia, usvg};
use tokio::sync::Semaphore;

use crate::domain::sanitize::wrap_ogp_message;
use crate::domain::session::{format_return_time_label, SessionRecord};

pub const OGP_WIDTH: u32 = 1200;
pub const OGP_HEIGHT: u32 = 630;

#[derive(Debug, thiserror::Error)]
pub enum OgpError {
    #[error("failed to render OGP SVG template: {0}")]
    Template(#[from] askama::Error),
    #[error("failed to parse OGP SVG tree: {0}")]
    SvgParse(#[from] usvg::Error),
    #[error("failed to allocate PNG pixmap")]
    PixmapAlloc,
    #[error("failed to encode PNG: {0}")]
    PngEncode(String),
    #[error("OGP semaphore closed")]
    SemaphoreClosed,
    #[error("OGP blocking task failed: {0}")]
    Join(#[from] tokio::task::JoinError),
}

#[derive(Template)]
#[template(path = "ogp_card.svg", escape = "xml")]
struct OgpCardTemplate {
    bg_color: &'static str,
    border_color: &'static str,
    primary_color: &'static str,
    secondary_color: &'static str,
    seal_color: &'static str,
    tag_bg_color: &'static str,
    return_time_label: String,
    message_line1: Option<String>,
    message_line2: Option<String>,
    msg_line1_y: u32,
    msg_line2_y: u32,
    display_name: Option<String>,
    display_name_y: u32,
    theme_label: &'static str,
    hide_watermark: bool,
}

/// Render the XML-escaped OGP SVG markup for a session.
pub fn render_svg(session: &SessionRecord) -> Result<String, OgpError> {
    let palette = session.card_style.palette();
    let tz = session.parsed_timezone();
    let return_time_label = format_return_time_label(session.ends_at, tz);

    let (message_line1, message_line2) = match session.message.as_deref() {
        Some(msg) => {
            let (l1, l2) = wrap_ogp_message(msg);
            (Some(l1), l2)
        }
        None => (None, None),
    };

    let msg_line1_y = 352;
    let msg_line2_y = 392;
    let display_name_y = match (&message_line1, &message_line2) {
        (Some(_), Some(_)) => 448,
        (Some(_), None) => 410,
        (None, _) => 364,
    };

    let tmpl = OgpCardTemplate {
        bg_color: palette.bg,
        border_color: palette.border,
        primary_color: palette.primary,
        secondary_color: palette.secondary,
        seal_color: palette.seal,
        tag_bg_color: palette.tag_bg,
        return_time_label,
        message_line1,
        message_line2,
        msg_line1_y,
        msg_line2_y,
        display_name: session.display_name.clone(),
        display_name_y,
        theme_label: session.theme_id.label_ja(),
        hide_watermark: session.hide_watermark,
    };

    Ok(tmpl.render()?)
}

/// Rasterize the session's OGP SVG into a `1200 x 630` PNG on Tokio's blocking pool,
/// bounded by `semaphore` to guard Cloud Run memory limits.
pub async fn render_ogp_png(
    session: &SessionRecord,
    fonts: Arc<fontdb::Database>,
    semaphore: Arc<Semaphore>,
) -> Result<Vec<u8>, OgpError> {
    let svg = render_svg(session)?;
    let _permit = semaphore
        .acquire_owned()
        .await
        .map_err(|_| OgpError::SemaphoreClosed)?;

    tokio::task::spawn_blocking(move || rasterize_svg_to_png(&svg, fonts)).await?
}

fn rasterize_svg_to_png(svg: &str, fonts: Arc<fontdb::Database>) -> Result<Vec<u8>, OgpError> {
    let options = usvg::Options {
        fontdb: fonts,
        font_family: "Shippori Mincho".to_string(),
        ..Default::default()
    };

    let tree = usvg::Tree::from_str(svg, &options)?;
    let mut pixmap = tiny_skia::Pixmap::new(OGP_WIDTH, OGP_HEIGHT).ok_or(OgpError::PixmapAlloc)?;
    resvg::render(
        &tree,
        tiny_skia::Transform::identity(),
        &mut pixmap.as_mut(),
    );
    pixmap
        .encode_png()
        .map_err(|err| OgpError::PngEncode(err.to_string()))
}

#[cfg(test)]
mod tests {
    use std::path::Path;

    use super::*;
    use crate::domain::catalog::{CardStyle, ThemeId};
    use crate::domain::session::SessionStatus;
    use crate::state::load_fonts;

    fn sample_session(
        display_name: Option<&str>,
        message: Option<&str>,
        hide_watermark: bool,
    ) -> SessionRecord {
        SessionRecord {
            id: "k9x2m7p4q8".to_string(),
            user_uuid: "550e8400-e29b-41d4-a716-446655440000".to_string(),
            owner_token_hash: "00".repeat(32),
            display_name: display_name.map(ToString::to_string),
            message: message.map(ToString::to_string),
            theme_id: ThemeId::MistyMountain,
            card_style: CardStyle::WashiClassic,
            hide_watermark,
            is_public: true,
            timezone: "Asia/Tokyo".to_string(),
            status: SessionStatus::Active,
            started_at: 1_768_473_000,
            ends_at: 1_768_480_200,
            finished_at: None,
            expires_at: 1_768_559_400,
        }
    }

    #[test]
    fn svg_escapes_xml_injection_and_respects_watermark_flag() {
        let session = sample_session(
            Some("<霧崎 & \"影\">"),
            Some("<script>alert(1)</script> & 読書"),
            false,
        );
        let svg = render_svg(&session).unwrap();
        assert!(!svg.contains("<script>"));
        assert!(svg.contains("&lt;script&gt;alert(1)&lt;/script&gt;"));
        assert!(svg.contains("&lt;霧崎 &amp;"));
        assert!(svg.contains("雲隠れ - Kumogakure"));

        let no_wm = sample_session(None, Some("読書してきます"), true);
        let svg_no_wm = render_svg(&no_wm).unwrap();
        assert!(!svg_no_wm.contains("雲隠れ - Kumogakure"));
        assert!(!svg_no_wm.contains("──"));
    }

    #[tokio::test]
    async fn rasterizes_1200x630_png_with_bundled_fonts_and_rare_kanji() {
        let fonts = Arc::new(load_fonts(Path::new("assets/fonts")).unwrap());
        let sem = Arc::new(Semaphore::new(4));
        let mut session =
            sample_session(Some("鷗外"), Some("鬱蒼たる竹林で薔薇と読書します"), false);
        session.card_style = CardStyle::SumiNight;
        session.theme_id = ThemeId::DawnShrine;

        let bytes = render_ogp_png(&session, fonts, sem).await.unwrap();
        assert!(bytes.starts_with(b"\x89PNG\r\n\x1a\n"));

        let decoder = png::Decoder::new(bytes.as_slice());
        let mut reader = decoder.read_info().unwrap();
        let info = reader.info();
        assert_eq!(info.width, 1200);
        assert_eq!(info.height, 630);

        let mut buf = vec![0; reader.output_buffer_size()];
        reader.next_frame(&mut buf).unwrap();
        // Verify non-uniform image content (text/border actually rendered over #12151B background)
        let first_pixel = &buf[0..4];
        assert!(buf.chunks_exact(4).any(|px| px != first_pixel));
    }
}

use std::fmt;

/// Landscape theme identifier (`AGENTS.md` §3).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ThemeId {
    MistyMountain,
    RainyBamboo,
    MoonlitLake,
    DawnShrine,
}

impl ThemeId {
    pub fn parse(raw: &str) -> Option<Self> {
        match raw {
            "misty_mountain" => Some(Self::MistyMountain),
            "rainy_bamboo" => Some(Self::RainyBamboo),
            "moonlit_lake" => Some(Self::MoonlitLake),
            "dawn_shrine" => Some(Self::DawnShrine),
            _ => None,
        }
    }

    pub const fn as_str(self) -> &'static str {
        match self {
            Self::MistyMountain => "misty_mountain",
            Self::RainyBamboo => "rainy_bamboo",
            Self::MoonlitLake => "moonlit_lake",
            Self::DawnShrine => "dawn_shrine",
        }
    }

    pub const fn label_ja(self) -> &'static str {
        match self {
            Self::MistyMountain => "霧の山並み",
            Self::RainyBamboo => "雨の竹林",
            Self::MoonlitLake => "月夜の湖畔",
            Self::DawnShrine => "夜明けの社",
        }
    }

    pub const fn is_pro(self) -> bool {
        matches!(self, Self::MoonlitLake | Self::DawnShrine)
    }
}

impl fmt::Display for ThemeId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

/// Absence card visual design identifier (`absence-card-spec.md` §2.1).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum CardStyle {
    #[default]
    WashiClassic,
    SumiNight,
    IndigoMist,
}

/// Color palette for OGP SVG & HTML card rendering.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct CardPalette {
    pub bg: &'static str,
    pub border: &'static str,
    pub primary: &'static str,
    pub secondary: &'static str,
    pub seal: &'static str,
    pub tag_bg: &'static str,
}

impl CardStyle {
    pub fn parse(raw: &str) -> Option<Self> {
        match raw {
            "washi_classic" => Some(Self::WashiClassic),
            "sumi_night" => Some(Self::SumiNight),
            "indigo_mist" => Some(Self::IndigoMist),
            _ => None,
        }
    }

    pub const fn as_str(self) -> &'static str {
        match self {
            Self::WashiClassic => "washi_classic",
            Self::SumiNight => "sumi_night",
            Self::IndigoMist => "indigo_mist",
        }
    }

    pub const fn is_pro(self) -> bool {
        matches!(self, Self::SumiNight | Self::IndigoMist)
    }

    pub const fn palette(self) -> CardPalette {
        match self {
            Self::WashiClassic => CardPalette {
                bg: "#F4F0E6",
                border: "#D6CFC2",
                primary: "#1E2022",
                secondary: "#5A5E63",
                seal: "#B84A39",
                tag_bg: "#E9E3D5",
            },
            Self::SumiNight => CardPalette {
                bg: "#12151B",
                border: "#2F3745",
                primary: "#EAE6DF",
                secondary: "#9CA3AE",
                seal: "#C79A63",
                tag_bg: "#1B2029",
            },
            Self::IndigoMist => CardPalette {
                bg: "#132230",
                border: "#324A5F",
                primary: "#ECE9E2",
                secondary: "#A2B3C2",
                seal: "#C79A63",
                tag_bg: "#1B3043",
            },
        }
    }
}

impl fmt::Display for CardStyle {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

/// Preset messages permitted on the free ("旅人") plan (`monetization.md` §2).
pub const PRESET_MESSAGES: [&str; 5] = [
    "少しの間、ひと休みします",
    "読書してきます",
    "おやすみなさい。朝まで雲隠れします",
    "集中して作業してきます",
    "少し散歩・入浴してきます",
];

/// Return `true` when the trimmed message matches one of the server-defined presets.
pub fn is_preset_message(message: &str) -> bool {
    PRESET_MESSAGES.contains(&message)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn theme_and_card_style_catalog_match_spec() {
        assert_eq!(
            ThemeId::parse("misty_mountain"),
            Some(ThemeId::MistyMountain)
        );
        assert_eq!(ThemeId::parse("rainy_bamboo"), Some(ThemeId::RainyBamboo));
        assert_eq!(ThemeId::parse("moonlit_lake"), Some(ThemeId::MoonlitLake));
        assert_eq!(ThemeId::parse("dawn_shrine"), Some(ThemeId::DawnShrine));
        assert_eq!(ThemeId::parse("unknown"), None);

        assert!(!ThemeId::MistyMountain.is_pro());
        assert!(!ThemeId::RainyBamboo.is_pro());
        assert!(ThemeId::MoonlitLake.is_pro());
        assert!(ThemeId::DawnShrine.is_pro());

        assert!(!CardStyle::WashiClassic.is_pro());
        assert!(CardStyle::SumiNight.is_pro());
        assert!(CardStyle::IndigoMist.is_pro());
        assert_eq!(CardStyle::WashiClassic.palette().bg, "#F4F0E6");
        assert_eq!(CardStyle::SumiNight.palette().seal, "#C79A63");
        assert_eq!(CardStyle::IndigoMist.palette().primary, "#ECE9E2");
    }

    #[test]
    fn preset_messages_cover_five_free_options() {
        assert_eq!(PRESET_MESSAGES.len(), 5);
        assert!(is_preset_message("読書してきます"));
        assert!(!is_preset_message("勝手なカスタム文言"));
    }
}

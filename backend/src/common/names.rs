//! Name helpers shared by features.

use unicode_normalization::UnicodeNormalization;

/// Reduces a display name to ASCII letters, digits and single spaces, which is
/// what `users_display_name_chars` allows. Accents are stripped ("Dewi Sartika
/// Putri" from "Déwi Sartîka Pütri") and symbols are dropped. Letters outside
/// Latin script are dropped too. Returns `None` when nothing is left, so the
/// caller can store NULL and let the DB fill in `user <n>`.
pub fn sanitize_display_name(raw: &str) -> Option<String> {
    let cleaned: String = raw
        .nfd()
        .map(|c| if c.is_whitespace() { ' ' } else { c })
        .filter(|c| c.is_ascii_alphanumeric() || *c == ' ')
        .collect();
    let collapsed = cleaned.split_whitespace().collect::<Vec<_>>().join(" ");
    (!collapsed.is_empty()).then_some(collapsed)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn plain_name_is_unchanged() {
        assert_eq!(
            sanitize_display_name("Siti Rahayu").as_deref(),
            Some("Siti Rahayu")
        );
    }

    #[test]
    fn accents_are_stripped() {
        assert_eq!(
            sanitize_display_name("Déwi Sartîka Pütri").as_deref(),
            Some("Dewi Sartika Putri")
        );
    }

    #[test]
    fn symbols_are_dropped_and_spaces_collapsed() {
        assert_eq!(
            sanitize_display_name("  Warung   *Bu* Ani!! 99 ").as_deref(),
            Some("Warung Bu Ani 99")
        );
        assert_eq!(
            sanitize_display_name("O'Brien-Smith").as_deref(),
            Some("OBrienSmith")
        );
    }

    #[test]
    fn blank_or_symbol_only_is_none() {
        assert_eq!(sanitize_display_name(""), None);
        assert_eq!(sanitize_display_name("   \t\n"), None);
        assert_eq!(sanitize_display_name("!!! ???"), None);
        assert_eq!(sanitize_display_name("名前"), None);
    }
}

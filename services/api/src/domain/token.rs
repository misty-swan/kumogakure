use nanoid::nanoid;
use rand::rngs::OsRng;
use rand::RngCore;
use sha2::{Digest, Sha256};
use subtle::ConstantTimeEq;

/// Length of public session IDs (`ADR-003`).
pub const SESSION_ID_LEN: usize = 10;

/// URL-safe 64-character alphabet `[A-Za-z0-9_-]` (~60 bits of entropy for 10 chars).
pub const SESSION_ID_ALPHABET: [char; 64] = [
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S',
    'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l',
    'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '0', '1', '2', '3', '4',
    '5', '6', '7', '8', '9', '_', '-',
];

/// Generate a 10-character URL-safe session ID.
pub fn generate_session_id() -> String {
    nanoid!(SESSION_ID_LEN, &SESSION_ID_ALPHABET)
}

/// Validate that a candidate session ID matches `[A-Za-z0-9_-]{10}`.
pub fn is_valid_session_id(id: &str) -> bool {
    id.len() == SESSION_ID_LEN
        && id
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
}

/// Generate a 32-byte cryptographically random `owner_token` (64-char hex) and its SHA-256 hex digest.
pub fn generate_owner_token() -> (String, String) {
    let mut bytes = [0u8; 32];
    OsRng.fill_bytes(&mut bytes);
    let raw_token = hex::encode(bytes);
    let token_hash = hash_owner_token(&raw_token);
    (raw_token, token_hash)
}

/// Compute lowercase SHA-256 hex digest of an `owner_token`.
pub fn hash_owner_token(token: &str) -> String {
    let digest = Sha256::digest(token.as_bytes());
    hex::encode(digest)
}

/// Verify an `owner_token` against a stored SHA-256 hex hash in constant time.
pub fn verify_owner_token(token: &str, expected_hash: &str) -> bool {
    let Ok(expected_bytes) = hex::decode(expected_hash) else {
        return false;
    };
    if expected_bytes.len() != 32 {
        return false;
    }

    let computed = Sha256::digest(token.as_bytes());
    bool::from(computed.as_slice().ct_eq(expected_bytes.as_slice()))
}

/// Compare two arbitrary secrets in constant time by hashing both inputs first.
pub fn verify_secret_constant_time(provided: &str, expected: &str) -> bool {
    if expected.is_empty() || provided.is_empty() {
        return false;
    }

    let provided_digest = Sha256::digest(provided.as_bytes());
    let expected_digest = Sha256::digest(expected.as_bytes());
    bool::from(provided_digest.as_slice().ct_eq(expected_digest.as_slice()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn session_id_has_expected_length_and_alphabet() {
        for _ in 0..50 {
            let id = generate_session_id();
            assert_eq!(id.len(), SESSION_ID_LEN);
            assert!(is_valid_session_id(&id));
        }

        assert!(is_valid_session_id("k9x2m7p4q8"));
        assert!(is_valid_session_id("A_z-012345"));
        assert!(!is_valid_session_id("short"));
        assert!(!is_valid_session_id("too_long_session_id"));
        assert!(!is_valid_session_id("bad~char12"));
        assert!(!is_valid_session_id("bad/char12"));
    }

    #[test]
    fn owner_token_hash_and_constant_time_verification() {
        let (token, hash) = generate_owner_token();
        assert_eq!(token.len(), 64);
        assert_eq!(hash.len(), 64);
        assert_ne!(token, hash);
        assert!(verify_owner_token(&token, &hash));

        let mut tampered = token.clone();
        let replacement = if tampered.starts_with('a') { 'b' } else { 'a' };
        tampered.replace_range(0..1, &replacement.to_string());
        assert!(!verify_owner_token(&tampered, &hash));
        assert!(!verify_owner_token("", &hash));
        assert!(!verify_owner_token(&token, "not-valid-hex"));
        assert!(!verify_owner_token(&token, "abcd"));
    }

    #[test]
    fn secret_constant_time_comparison() {
        assert!(verify_secret_constant_time("super-secret", "super-secret"));
        assert!(!verify_secret_constant_time("super-secrex", "super-secret"));
        assert!(!verify_secret_constant_time("short", "super-secret"));
        assert!(!verify_secret_constant_time("", "super-secret"));
        assert!(!verify_secret_constant_time("super-secret", ""));
    }
}

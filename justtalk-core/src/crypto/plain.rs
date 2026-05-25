//! No-op encryptor for v0.1 — passes data through unmodified.

use super::traits::MessageEncryptor;
use crate::Result;

/// Identity (pass-through) encryptor used during initial development.
///
/// Payload bytes are returned as-is; no cryptographic protection is applied.
#[derive(Debug, Clone, Default)]
pub struct PlainEncryptor;

impl MessageEncryptor for PlainEncryptor {
    fn encrypt(&self, plaintext: &[u8]) -> Result<Vec<u8>> {
        Ok(plaintext.to_vec())
    }

    fn decrypt(&self, ciphertext: &[u8]) -> Result<Vec<u8>> {
        Ok(ciphertext.to_vec())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn roundtrip_preserves_data() {
        let enc = PlainEncryptor;
        let data = b"hello justtalk";
        let cipher = enc.encrypt(data).unwrap();
        let plain = enc.decrypt(&cipher).unwrap();
        assert_eq!(plain, data);
    }

    #[test]
    fn encrypt_is_identity() {
        let enc = PlainEncryptor;
        let data = vec![1, 2, 3, 4, 5];
        assert_eq!(enc.encrypt(&data).unwrap(), data);
    }

    #[test]
    fn empty_payload() {
        let enc = PlainEncryptor;
        assert_eq!(enc.encrypt(b"").unwrap(), b"");
        assert_eq!(enc.decrypt(b"").unwrap(), b"");
    }
}

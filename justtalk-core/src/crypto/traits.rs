//! Core encryption trait that all encryptors must implement.

use crate::Result;

/// Abstraction over message-level encryption.
///
/// Implementations range from no-op (plain) to full E2EE (Signal Protocol).
pub trait MessageEncryptor: Send + Sync + std::fmt::Debug {
    /// Encrypt `plaintext` bytes, returning ciphertext.
    fn encrypt(&self, plaintext: &[u8]) -> Result<Vec<u8>>;

    /// Decrypt `ciphertext` bytes, returning plaintext.
    fn decrypt(&self, ciphertext: &[u8]) -> Result<Vec<u8>>;
}

//! Encryption layer — trait definition and implementations.
//!
//! v0.1 ships with `PlainEncryptor` (no-op); future versions will add
//! Signal Protocol / XChaCha20-Poly1305 implementations.

pub mod traits;
pub mod plain;

pub use plain::PlainEncryptor;
pub use traits::MessageEncryptor;

//! Ed25519 keypair for peer identity and message signing.

use ed25519_dalek::{Signer, SigningKey, Verifier, VerifyingKey};
use rand::rngs::OsRng;
use rand::RngCore;

use crate::{Error, Result};

/// An Ed25519 keypair used to identify a peer and sign messages.
#[derive(Debug, Clone)]
pub struct KeyPair {
    signing_key: SigningKey,
}

impl KeyPair {
    /// Generate a fresh random keypair.
    pub fn generate() -> Self {
        let mut secret = [0u8; 32];
        OsRng.fill_bytes(&mut secret);
        let signing_key = SigningKey::from_bytes(&secret);
        Self { signing_key }
    }

    /// Derive the peer ID (hex-encoded public key).
    pub fn peer_id(&self) -> String {
        hex::encode(self.signing_key.verifying_key().as_bytes())
    }

    /// Return the verifying (public) key bytes.
    pub fn public_key_bytes(&self) -> [u8; 32] {
        *self.signing_key.verifying_key().as_bytes()
    }

    /// Sign a message, returning the signature bytes.
    pub fn sign(&self, message: &[u8]) -> Vec<u8> {
        self.signing_key.sign(message).to_bytes().to_vec()
    }

    /// Verify a signature against a public key and message.
    pub fn verify(public_key: &[u8; 32], message: &[u8], signature: &[u8]) -> Result<()> {
        let verifying_key = VerifyingKey::from_bytes(public_key)
            .map_err(|e| Error::Identity(format!("invalid public key: {e}")))?;
        let sig = ed25519_dalek::Signature::from_slice(signature)
            .map_err(|e| Error::Identity(format!("invalid signature: {e}")))?;
        verifying_key
            .verify(message, &sig)
            .map_err(|e| Error::Identity(format!("signature verification failed: {e}")))
    }

    /// Reconstruct a keypair from raw secret key bytes.
    pub fn from_secret_key_bytes(bytes: &[u8; 32]) -> Result<Self> {
        let signing_key = SigningKey::from_bytes(bytes);
        Ok(Self { signing_key })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn generate_produces_valid_keypair() {
        let kp = KeyPair::generate();
        assert!(!kp.peer_id().is_empty());
        assert_eq!(kp.peer_id().len(), 64); // hex-encoded 32 bytes
    }

    #[test]
    fn sign_and_verify_roundtrip() {
        let kp = KeyPair::generate();
        let message = b"hello justchat";
        let signature = kp.sign(message);
        assert!(KeyPair::verify(&kp.public_key_bytes(), message, &signature).is_ok());
    }

    #[test]
    fn verify_rejects_wrong_message() {
        let kp = KeyPair::generate();
        let message = b"hello";
        let signature = kp.sign(message);
        assert!(KeyPair::verify(&kp.public_key_bytes(), b"tampered", &signature).is_err());
    }

    #[test]
    fn verify_rejects_wrong_key() {
        let kp1 = KeyPair::generate();
        let kp2 = KeyPair::generate();
        let signature = kp1.sign(b"test");
        assert!(KeyPair::verify(&kp2.public_key_bytes(), b"test", &signature).is_err());
    }

    #[test]
    fn from_secret_key_bytes_roundtrip() {
        let kp1 = KeyPair::generate();
        let secret = kp1.signing_key.to_bytes();
        let kp2 = KeyPair::from_secret_key_bytes(&secret).unwrap();
        assert_eq!(kp1.peer_id(), kp2.peer_id());
    }
}

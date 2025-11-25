"""
Lightweight helpers for encrypting/decrypting image payloads.

Images are encrypted on the client with AES-GCM using a shared secret.
The server derives a 256-bit key from the secret via SHA-256 and expects
the payload to be base64-encoded bytes of: nonce (12b) + ciphertext + tag.
"""

from __future__ import annotations

import base64
from hashlib import sha256
from typing import Optional

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

from app.core import settings

DEFAULT_ALGORITHM = "aes_gcm"


def _derive_key(secret: str) -> bytes:
    """Derive a 256-bit key from a human-readable secret."""
    if not secret:
        raise ValueError("Image encryption secret is not configured")
    return sha256(secret.encode("utf-8")).digest()


def decrypt_image_payload(encrypted_payload_b64: str, algorithm: Optional[str] = None) -> str:
    """
    Decrypt a base64-encoded encrypted image payload and return the original base64 image string.

    Args:
        encrypted_payload_b64: Base64 string of nonce+ciphertext+tag produced by AES-GCM.
        algorithm: Optional algorithm hint (currently only 'aes_gcm' is supported).

    Returns:
        Decrypted image payload as a UTF-8 string (base64 image data).

    Raises:
        ValueError: If decryption fails or unsupported algorithm is requested.
    """
    algo = (algorithm or DEFAULT_ALGORITHM).lower()
    if algo != DEFAULT_ALGORITHM:
        raise ValueError(f"Unsupported encryption algorithm: {algorithm}")

    try:
        payload_bytes = base64.b64decode(encrypted_payload_b64)
    except Exception as exc:
        raise ValueError(f"Invalid base64 for encrypted payload: {exc}")

    if len(payload_bytes) < 12 + 16:
        raise ValueError("Encrypted payload too short to contain nonce and tag")

    nonce = payload_bytes[:12]
    ciphertext = payload_bytes[12:]
    key = _derive_key(settings.IMAGE_ENCRYPTION_KEY)

    try:
        aesgcm = AESGCM(key)
        plaintext = aesgcm.decrypt(nonce, ciphertext, None)
    except Exception as exc:
        raise ValueError(f"Failed to decrypt payload: {exc}")

    try:
        return plaintext.decode("utf-8")
    except Exception as exc:
        raise ValueError(f"Decrypted payload is not valid UTF-8: {exc}")

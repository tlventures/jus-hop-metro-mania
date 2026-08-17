import base64
import hashlib
import time
import re
import httpx
from typing import Dict, Tuple, Optional
from nacl.signing import SigningKey, VerifyKey
from nacl.exceptions import BadSignatureError
from cryptography.hazmat.primitives.asymmetric import x25519
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.backends import default_backend

from app.core.config import settings
from app.core.logging import logger

HEADER_REGEX = re.compile(r'([a-zA-Z0-9_-]+)="([^"]+)"')


def compute_blake512_digest(body: bytes) -> str:
    """
    Computes BLAKE-512 (BLAKE2b with 64-byte / 512-bit output) hash digest of the request payload.
    Format: "BLAKE-512=" + base64(digest)
    """
    hasher = hashlib.blake2b(digest_size=64)
    hasher.update(body)
    raw_digest = hasher.digest()
    b64_digest = base64.b64encode(raw_digest).decode("utf-8")
    return f"BLAKE-512={b64_digest}"


def _decode_onboarding_key(key_b64: str) -> bytes:
    raw = base64.b64decode(key_b64)
    if len(raw) >= 32:
        return raw[-32:]
    raise ValueError(f"Invalid ONDC key byte length: {len(raw)}")


def decrypt_subscribe_challenge(challenge_string: str) -> str:
    """
    Decrypt ONDC Registry /on_subscribe challenge_string.

    ONDC onboarding derives an X25519 shared key from the participant encryption
    private key and ONDC registry public key, then decrypts the base64 challenge
    using AES-256-ECB. The decrypted answer is returned to the registry.
    """
    if not settings.ENCRYPTION_PRIVATE_KEY_B64:
        if settings.APP_ENV == "production" and not settings.DEBUG:
            raise ValueError("ENCRYPTION_PRIVATE_KEY_B64 is required")
        return challenge_string

    private_key = x25519.X25519PrivateKey.from_private_bytes(
        _decode_onboarding_key(settings.ENCRYPTION_PRIVATE_KEY_B64)
    )
    public_key = x25519.X25519PublicKey.from_public_bytes(
        _decode_onboarding_key(settings.ONDC_PUBLIC_KEY_B64)
    )
    shared_key = private_key.exchange(public_key)
    encrypted = base64.b64decode(challenge_string)
    decryptor = Cipher(
        algorithms.AES(shared_key),
        modes.ECB(),
        backend=default_backend(),
    ).decryptor()
    padded = decryptor.update(encrypted) + decryptor.finalize()
    pad_len = padded[-1]
    if 0 < pad_len <= 16:
        padded = padded[:-pad_len]
    return padded.decode("utf-8")


def generate_keypair() -> Tuple[str, str]:
    """
    Generates a fresh Ed25519 keypair encoded as Base64 strings.
    Returns (private_key_b64, public_key_b64).
    """
    signing_key = SigningKey.generate()
    priv_b64 = base64.b64encode(signing_key.encode()).decode("utf-8")
    pub_b64 = base64.b64encode(signing_key.verify_key.encode()).decode("utf-8")
    return priv_b64, pub_b64


def get_signing_key(priv_key_b64: Optional[str] = None) -> SigningKey:
    """
    Loads PyNaCl SigningKey from Base64 string or environment settings.
    """
    key_str = priv_key_b64 or settings.SIGNING_PRIVATE_KEY_B64
    try:
        raw_bytes = base64.b64decode(key_str)
        # If seed is 32 bytes
        if len(raw_bytes) == 32:
            return SigningKey(raw_bytes)
        # If extended 64 bytes
        elif len(raw_bytes) >= 32:
            return SigningKey(raw_bytes[:32])
        else:
            raise ValueError(f"Invalid private key byte length: {len(raw_bytes)}")
    except Exception as e:
        logger.warning(f"Falling back to fresh test keypair due to key decode error: {e}")
        return SigningKey.generate()


def create_beckn_auth_header(
    body: bytes,
    subscriber_id: Optional[str] = None,
    unique_key_id: Optional[str] = None,
    priv_key_b64: Optional[str] = None,
    ttl_seconds: int = 300
) -> str:
    """
    Generates ONDC protocol HTTP Authorization header according to Beckn v2.0.0 specs.
    1. Computes BLAKE-512 digest.
    2. Constructs signing string: (created)\n(expires)\ndigest.
    3. Signs string using Ed25519 private key.
    4. Formats Authorization header string.
    """
    sub_id = subscriber_id or settings.BAP_ID
    key_id = unique_key_id or settings.SUBSCRIBER_UNIQUE_KEY_ID

    created = int(time.time())
    expires = created + ttl_seconds
    digest_val = compute_blake512_digest(body)

    signing_string = f"(created): {created}\n(expires): {expires}\ndigest: {digest_val}"

    signing_key = get_signing_key(priv_key_b64)
    signed_data = signing_key.sign(signing_string.encode("utf-8"))
    signature_b64 = base64.b64encode(signed_data.signature).decode("utf-8")

    key_id_str = f"{sub_id}|{key_id}|ed25519"

    auth_header = (
        f'Signature keyId="{key_id_str}",'
        f'algorithm="ed25519",'
        f'created="{created}",'
        f'expires="{expires}",'
        f'headers="(created) (expires) digest",'
        f'signature="{signature_b64}"'
    )
    return auth_header


def create_beckn_headers(
    body: bytes,
    subscriber_id: Optional[str] = None,
    unique_key_id: Optional[str] = None,
) -> Dict[str, str]:
    digest = compute_blake512_digest(body)
    return {
        "Content-Type": "application/json",
        "Digest": digest,
        "Authorization": create_beckn_auth_header(
            body=body,
            subscriber_id=subscriber_id,
            unique_key_id=unique_key_id,
        ),
    }


def parse_authorization_header(auth_header: str) -> Dict[str, str]:
    """
    Parses key-value pairs from an HTTP Authorization header string.
    Example header: Signature keyId="...",algorithm="ed25519",created="123",expires="456",headers="...",signature="..."
    """
    if not auth_header or not auth_header.startswith("Signature "):
        raise ValueError("Invalid Authorization header format. Must start with 'Signature '")

    content = auth_header[len("Signature "):]
    matches = HEADER_REGEX.findall(content)
    params = {k: v for k, v in matches}

    required = ["keyId", "algorithm", "created", "expires", "signature"]
    for req in required:
        if req not in params:
            raise ValueError(f"Missing required parameter '{req}' in Authorization header")

    return params


def verify_ed25519_signature(
    public_key_b64: str,
    signature_b64: str,
    signing_string: str
) -> bool:
    """
    Verifies an Ed25519 signature against a signing string using PyNaCl.
    """
    try:
        pub_bytes = base64.b64decode(public_key_b64)
        if len(pub_bytes) > 32:
            pub_bytes = pub_bytes[:32]
        verify_key = VerifyKey(pub_bytes)
        sig_bytes = base64.b64decode(signature_b64)
        verify_key.verify(signing_string.encode("utf-8"), sig_bytes)
        return True
    except BadSignatureError:
        return False
    except Exception as e:
        logger.error(f"Error during Ed25519 signature verification: {e}")
        return False


async def fetch_public_key_from_ondc_registry(
    subscriber_id: str,
    unique_key_id: str,
    redis_client=None
) -> Optional[str]:
    """
    Fetches the public key for a given subscriber_id and key_id from ONDC Registry via POST /lookup,
    and caches it in Redis with a 12-hour TTL.
    """
    cache_key = f"ondc:pubkey:{subscriber_id}:{unique_key_id}"
    if redis_client:
        try:
            cached_key = await redis_client.get(cache_key)
            if cached_key:
                return cached_key.decode("utf-8") if isinstance(cached_key, bytes) else cached_key
        except Exception as e:
            logger.warning(f"Redis public key cache read error: {e}")

    # Fallback lookup to ONDC Registry
    lookup_payload = {
        "subscriber_id": subscriber_id,
        "ukId": unique_key_id,
        "domain": "ONDC:TRV11",
        "type": "BPP"
    }

    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            resp = await client.post(
                f"{settings.ONDC_REGISTRY_URL}/lookup",
                json=lookup_payload
            )
            if resp.status_code == 200:
                data = resp.json()
                if isinstance(data, list) and len(data) > 0:
                    pub_key = data[0].get("signing_public_key")
                    if pub_key and redis_client:
                        try:
                            await redis_client.setex(
                                cache_key,
                                settings.REDIS_KEY_TTL_SECONDS,
                                pub_key
                            )
                        except Exception as ce:
                            logger.warning(f"Failed to cache public key in Redis: {ce}")
                    return pub_key
    except Exception as e:
        logger.error(f"ONDC Registry lookup failed for {subscriber_id}: {e}")

    # Fallback to test/mock public key if registry lookup fails in dev mode
    if settings.DEBUG or settings.APP_ENV != "production":
        logger.info(f"Using dev fallback public key for {subscriber_id}")
        return settings.SIGNING_PUBLIC_KEY_B64

    return None

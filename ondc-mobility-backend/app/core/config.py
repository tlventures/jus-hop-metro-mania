import os
from pydantic_settings import BaseSettings
from pydantic import Field


class Settings(BaseSettings):
    APP_NAME: str = "ONDC TRV11 BNP Core"
    APP_ENV: str = "development"
    DEBUG: bool = True
    LOG_LEVEL: str = "INFO"
    ALLOWED_ORIGINS: str = ""

    # API Server Config
    HOST: str = "0.0.0.0"
    PORT: int = 8000
    WORKERS: int = 4

    # PostgreSQL / SQLite Database
    DATABASE_URL: str = Field(
        default="sqlite+aiosqlite:///./ondc_dev.db",
        description="Async SQLAlchemy database connection URI"
    )
    DB_POOL_SIZE: int = 20
    DB_MAX_OVERFLOW: int = 10

    # Redis Config
    REDIS_URL: str = Field(
        default="redis://localhost:6379/0",
        description="Redis cluster or single node connection URL"
    )
    REDIS_KEY_TTL_SECONDS: int = 43200  # 12 hours for cached public keys

    # Beckn ONDC Protocol Config
    ONDC_DOMAIN: str = "ONDC:TRV11"
    ONDC_COUNTRY: str = "IND"
    ONDC_CITY_CODE: str = "std:040"
    ONDC_CORE_VERSION: str = "2.0.0"
    ONDC_ENVIRONMENT: str = "preprod"
    BAP_ID: str = Field(default="ondc.metrosafar.in", description="Registered ONDC BAP Subscriber ID")
    BAP_URI: str = Field(default="https://ondc.metrosafar.in/ondc", description="BAP Callback Base URI")
    ONDC_REGISTRY_URL: str = Field(default="https://preprod.registry.ondc.org", description="ONDC Registry URL for public key lookup")
    ONDC_GATEWAY_URL: str = Field(default="https://preprod.gateway.ondc.org/search", description="ONDC Gateway search URL")
    SUBSCRIBER_UNIQUE_KEY_ID: str = Field(default="key-ed25519-1", description="Unique key ID registered in ONDC registry")
    ONDC_SITE_VERIFICATION_CONTENT: str = Field(default="", description="Exact generated ondc-site-verification.html content")
    ALLOW_WORKBENCH_MISSING_DIGEST: bool = Field(
        default=True,
        description="Allow ONDC Workbench callbacks that sign the body but omit the Digest header",
    )
    NETWORK_OBSERVABILITY_TOKEN: str = Field(default="", description="ONDC Network Observability token")
    NETWORK_OBSERVABILITY_URL: str = Field(
        default="https://analytics-api.aws.ondc.org/v1/api/push-txn-logs",
        description="ONDC Network Observability transaction log submission endpoint",
    )

    # Cryptographic Keys (Ed25519) - Base64 encoded private/public keys
    # Default is a test keypair; production key MUST be injected via ENV variables
    SIGNING_PRIVATE_KEY_B64: str = Field(
        default="MC4CAQAwBQYDK2VwBCIEIK+8l/28xZf67m5W/aQ5Y8bM/v3n5oZ2v/v3n5oZ2v/v",
        description="Base64 encoded Ed25519 private key (seed or PKCS8/raw)"
    )
    SIGNING_PUBLIC_KEY_B64: str = Field(
        default="MCowBQYDK2VwAyEAX5+5oZ2v/v3n5oZ2v/v3n5oZ2v/v3n5oZ2v/v3n5oZ2=",
        description="Base64 encoded Ed25519 public key"
    )
    ENCRYPTION_PRIVATE_KEY_B64: str = Field(
        default="",
        description="Base64 encoded X25519 encryption private key from ONDC onboarding"
    )
    ENCRYPTION_PUBLIC_KEY_B64: str = Field(
        default="",
        description="Base64 encoded X25519 encryption public key from ONDC onboarding"
    )
    ONDC_PUBLIC_KEY_B64: str = Field(
        default="MCowBQYDK2VuAyEARa/WcMCzNQp4DWjvTI4DK7vHL6EdaHqN4GjFIu9wxxM=",
        description="ONDC registry public encryption key; default is pre-prod"
    )

    # Circuit Breaker Config
    CB_FAIL_MAX: int = 5
    CB_RESET_TIMEOUT: int = 30  # seconds

    # Idempotency & Queue Settings
    IDEMPOTENCY_TTL_SECONDS: int = 300  # 5 minutes
    WEBHOOK_TIMEOUT_MS: int = 1000  # ONDC max ACK SLA

    # Razorpay (test mode by default; inject live keys in prod via env)
    RAZORPAY_KEY_ID: str = Field(
        default="rzp_test_1DP5mmOlF5G5ag",
        description="Razorpay Key ID; default is Razorpay's public test key.",
    )
    RAZORPAY_KEY_SECRET: str = Field(
        default="thisisatestsecret_replaceviaenv",
        description="Razorpay Key Secret; MUST be set via env in any non-local run.",
    )
    RAZORPAY_API_BASE: str = "https://api.razorpay.com/v1"
    RAZORPAY_WEBHOOK_SECRET: str = Field(default="", description="Optional webhook shared secret.")

    # QR ticket signing (uses the same Ed25519 key configured for ONDC)
    QR_TOKEN_TTL_HOURS: int = 4
    QR_TOKEN_ISSUER: str = "metrosafar"

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"
        case_sensitive = True


settings = Settings()

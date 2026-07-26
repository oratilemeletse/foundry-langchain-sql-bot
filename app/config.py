"""
Application configuration — reads from environment variables.
In Azure, these are injected by the Container Instance from Key Vault via Managed Identity.
Locally, load from a .env file.
"""

from functools import lru_cache

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    # Azure OpenAI
    azure_openai_endpoint: str = ""
    azure_openai_api_key: str = ""
    azure_openai_deployment_name: str = "gpt-4o"
    azure_openai_api_version: str = "2024-02-01"

    # Database
    # Set DB_MODE=sqlite for local dev; DB_MODE=azure for Azure SQL
    db_mode: str = "sqlite"

    # SQLite (local dev)
    sqlite_db_path: str = "adventureworks.db"

    # Azure SQL (production)
    sql_server_fqdn: str = ""
    sql_database_name: str = ""
    sql_admin_username: str = ""
    sql_admin_password: str = ""

    # Azure Key Vault (production — container reads secrets at runtime)
    key_vault_uri: str = ""

    # App
    log_level: str = "INFO"
    app_port: int = 8000

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"
        case_sensitive = False


@lru_cache
def get_settings() -> Settings:
    return Settings()

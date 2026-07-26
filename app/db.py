"""
Database connection layer.

Local dev  → SQLite (adventureworks.db)
Production → Azure SQL (pyodbc / SQLAlchemy)

The connection string is assembled from env vars, which in Azure come from Key Vault
via Managed Identity — never hardcoded.
"""

from __future__ import annotations

import logging

from sqlalchemy import create_engine, text
from sqlalchemy.engine import Engine

from app.config import get_settings

logger = logging.getLogger(__name__)


def _build_engine() -> Engine:
    settings = get_settings()

    if settings.db_mode == "sqlite":
        db_path = settings.sqlite_db_path
        logger.info("Using SQLite database: %s", db_path)
        return create_engine(f"sqlite:///{db_path}", connect_args={"check_same_thread": False})

    # Azure SQL via ODBC
    server = settings.sql_server_fqdn
    database = settings.sql_database_name
    username = settings.sql_admin_username
    password = settings.sql_admin_password

    connection_string = (
        f"mssql+pyodbc://{username}:{password}@{server}/{database}"
        "?driver=ODBC+Driver+18+for+SQL+Server&Encrypt=yes&TrustServerCertificate=no"
    )
    logger.info("Using Azure SQL: %s / %s", server, database)
    return create_engine(connection_string, pool_pre_ping=True)


_engine: Engine | None = None


def get_engine() -> Engine:
    global _engine
    if _engine is None:
        _engine = _build_engine()
    return _engine


def get_connection_string() -> str:
    """Return the raw connection string for LangChain's SQLDatabase."""
    settings = get_settings()

    if settings.db_mode == "sqlite":
        return f"sqlite:///{settings.sqlite_db_path}"

    server = settings.sql_server_fqdn
    database = settings.sql_database_name
    username = settings.sql_admin_username
    password = settings.sql_admin_password

    return (
        f"mssql+pyodbc://{username}:{password}@{server}/{database}"
        "?driver=ODBC+Driver+18+for+SQL+Server&Encrypt=yes&TrustServerCertificate=no"
    )


def run_query(sql: str) -> list[dict]:
    """Execute a SQL query and return rows as list of dicts."""
    engine = get_engine()
    with engine.connect() as conn:
        result = conn.execute(text(sql))
        columns = list(result.keys())
        rows = [dict(zip(columns, row)) for row in result.fetchall()]
    return rows


def get_schema_summary() -> str:
    """Return a compact schema string: table(col1, col2, ...) per line."""
    get_engine()  # ensure engine is initialised
    settings = get_settings()

    if settings.db_mode == "sqlite":
        schema_sql = """
            SELECT m.name AS table_name, p.name AS column_name
            FROM sqlite_master m
            JOIN pragma_table_info(m.name) p
            WHERE m.type = 'table'
            ORDER BY m.name, p.cid
        """
    else:
        schema_sql = """
            SELECT TABLE_NAME as table_name, COLUMN_NAME as column_name
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = 'dbo'
            ORDER BY TABLE_NAME, ORDINAL_POSITION
        """

    rows = run_query(schema_sql)

    tables: dict[str, list[str]] = {}
    for row in rows:
        t = row["table_name"]
        tables.setdefault(t, []).append(row["column_name"])

    return "\n".join(f"{t}({', '.join(cols)})" for t, cols in tables.items())


def list_tables() -> list[str]:
    """Return all table names in the database."""
    get_engine()  # ensure engine is initialised
    settings = get_settings()

    if settings.db_mode == "sqlite":
        rows = run_query("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
        return [r["name"] for r in rows]

    rows = run_query(
        "SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE='BASE TABLE' ORDER BY TABLE_NAME"
    )
    return [r["TABLE_NAME"] for r in rows]

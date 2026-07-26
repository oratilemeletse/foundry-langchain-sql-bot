"""
Tests for the database layer using an in-memory SQLite database.
"""

import pytest
import sqlalchemy as sa

import app.db as db_module
from app.db import get_schema_summary, list_tables, run_query


@pytest.fixture(autouse=True)
def in_memory_db(monkeypatch, tmp_path):
    """Use a fresh SQLite file for each test with a sample schema."""
    db_path = str(tmp_path / "test.db")
    monkeypatch.setenv("DB_MODE", "sqlite")
    monkeypatch.setenv("SQLITE_DB_PATH", db_path)

    from app.config import get_settings
    get_settings.cache_clear()
    db_module._engine = None

    # Seed with a tiny schema
    engine = db_module.get_engine()
    with engine.begin() as conn:
        conn.execute(sa.text(
            "CREATE TABLE Product (ProductID INTEGER PRIMARY KEY, Name TEXT, Price REAL)"
        ))
        conn.execute(sa.text(
            "INSERT INTO Product VALUES (1, 'Widget', 9.99), (2, 'Gadget', 19.99)"
        ))

    yield

    db_module._engine = None
    get_settings.cache_clear()


def test_list_tables():
    tables = list_tables()
    assert "Product" in tables


def test_run_query_returns_rows():
    rows = run_query("SELECT * FROM Product ORDER BY ProductID")
    assert len(rows) == 2
    assert rows[0]["Name"] == "Widget"
    assert rows[1]["Price"] == 19.99


def test_get_schema_summary():
    schema = get_schema_summary()
    assert "Product" in schema
    assert "ProductID" in schema
    assert "Name" in schema

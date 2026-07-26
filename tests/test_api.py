"""
Integration tests for the FastAPI app using TestClient + SQLite.
No Azure credentials needed — DB_MODE=sqlite is used automatically.
Azure OpenAI calls are mocked.
"""

from unittest.mock import patch

import pytest
from fastapi.testclient import TestClient


@pytest.fixture(autouse=True)
def use_sqlite_env(monkeypatch, tmp_path):
    """Force SQLite mode for all tests."""
    monkeypatch.setenv("DB_MODE", "sqlite")
    monkeypatch.setenv("SQLITE_DB_PATH", str(tmp_path / "test.db"))
    monkeypatch.setenv("AZURE_OPENAI_ENDPOINT", "https://fake.openai.azure.com/")
    monkeypatch.setenv("AZURE_OPENAI_API_KEY", "fake-key")

    # Reset settings cache
    from app.config import get_settings
    get_settings.cache_clear()

    # Reset DB engine
    import app.db as db_module
    db_module._engine = None

    yield

    get_settings.cache_clear()
    db_module._engine = None


@pytest.fixture
def client():
    from app.main import app
    return TestClient(app)


def test_health(client):
    response = client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "ok"
    assert "metrics" in data


def test_metrics_empty(client):
    response = client.get("/metrics")
    assert response.status_code == 200
    assert "No requests recorded yet" in response.text


def test_metrics_after_request(client):
    """Metrics endpoint should reflect data after a (mocked) request."""
    from app.metrics import metrics_store
    metrics_store.record_request("agent", 1.0, 100, True)

    response = client.get("/metrics")
    assert 'chatbot_requests_total{mode="agent"} 1' in response.text


@patch("app.main.run_agent")
def test_chat_agent_mode(mock_agent, client):
    from app.agent_mode import AgentResult
    mock_agent.return_value = AgentResult(
        answer="The answer is 42.",
        tokens_used=150,
        steps=[{"tool": "run_query", "tool_input": "SELECT 42", "observation": "42"}],
    )

    response = client.post("/chat", json={"question": "What is 42?", "mode": "agent"})
    assert response.status_code == 200
    data = response.json()
    assert data["answer"] == "The answer is 42."
    assert data["mode"] == "agent"
    assert data["tokens_used"] == 150
    assert data["agent_steps"] is not None


@patch("app.main.run_function_call")
def test_chat_function_call_mode(mock_fc, client):
    from app.function_call_mode import FunctionCallResult
    mock_fc.return_value = FunctionCallResult(
        answer="There are 5 products.",
        sql_query="SELECT COUNT(*) FROM Product",
        tokens_used=80,
        raw_rows=[{"COUNT(*)": 5}],
    )

    response = client.post(
        "/chat", json={"question": "How many products?", "mode": "function_call"}
    )
    assert response.status_code == 200
    data = response.json()
    assert data["answer"] == "There are 5 products."
    assert data["sql_query"] == "SELECT COUNT(*) FROM Product"
    assert data["mode"] == "function_call"


@patch("app.main.run_agent")
def test_chat_error_returns_500(mock_agent, client):
    mock_agent.side_effect = RuntimeError("LLM unavailable")

    response = client.post("/chat", json={"question": "broken", "mode": "agent"})
    assert response.status_code == 500
    assert "LLM unavailable" in response.json()["detail"]

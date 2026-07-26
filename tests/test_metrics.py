"""
Unit tests for the metrics store.
No Azure credentials needed — fully offline.
"""

import pytest

from app.metrics import MetricsStore


def test_initial_state():
    store = MetricsStore()
    assert store.summary() == {}
    assert "No requests recorded yet" in store.to_prometheus_text()


def test_record_success():
    store = MetricsStore()
    store.record_request("agent", latency_seconds=1.5, tokens=100, success=True)

    summary = store.summary()
    assert "agent" in summary
    assert summary["agent"]["request_count"] == 1
    assert summary["agent"]["error_count"] == 0
    assert summary["agent"]["error_rate"] == 0.0
    assert summary["agent"]["total_tokens"] == 100
    assert summary["agent"]["avg_latency_seconds"] == 1.5


def test_record_error():
    store = MetricsStore()
    store.record_request("function_call", latency_seconds=0.5, tokens=50, success=False)

    summary = store.summary()
    assert summary["function_call"]["error_count"] == 1
    assert summary["function_call"]["error_rate"] == 1.0


def test_multiple_modes():
    store = MetricsStore()
    store.record_request("agent", 2.0, 200, True)
    store.record_request("agent", 4.0, 400, True)
    store.record_request("function_call", 0.5, 80, True)

    summary = store.summary()
    assert summary["agent"]["request_count"] == 2
    assert summary["agent"]["avg_latency_seconds"] == 3.0
    assert summary["function_call"]["request_count"] == 1


def test_prometheus_text_format():
    store = MetricsStore()
    store.record_request("agent", 1.0, 100, True)
    text = store.to_prometheus_text()

    assert 'chatbot_requests_total{mode="agent"} 1' in text
    assert 'chatbot_errors_total{mode="agent"} 0' in text
    assert 'chatbot_tokens_total{mode="agent"} 100' in text


def test_measure_context_manager_success():
    store = MetricsStore()
    tokens_ref = [0]

    with store.measure("agent", tokens_ref):
        tokens_ref[0] = 42

    assert store.summary()["agent"]["request_count"] == 1
    assert store.summary()["agent"]["error_count"] == 0
    assert store.summary()["agent"]["total_tokens"] == 42


def test_measure_context_manager_failure():
    store = MetricsStore()
    tokens_ref = [0]

    with pytest.raises(ValueError), store.measure("agent", tokens_ref):
        raise ValueError("boom")

    assert store.summary()["agent"]["error_count"] == 1

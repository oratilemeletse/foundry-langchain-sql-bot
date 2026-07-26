"""
Prometheus-style metrics for the chatbot API.

Tracked per mode (agent / function_call):
  - request count
  - error count
  - total latency (seconds)
  - total tokens used (prompt + completion)

Exposed at GET /metrics as plain text in Prometheus exposition format.
"""

from __future__ import annotations

import time
from collections import defaultdict
from collections.abc import Generator
from contextlib import contextmanager
from dataclasses import dataclass


@dataclass
class ModeMetrics:
    request_count: int = 0
    error_count: int = 0
    total_latency_seconds: float = 0.0
    total_tokens: int = 0


class MetricsStore:
    def __init__(self) -> None:
        self._data: dict[str, ModeMetrics] = defaultdict(ModeMetrics)

    def record_request(
        self,
        mode: str,
        latency_seconds: float,
        tokens: int,
        success: bool,
    ) -> None:
        m = self._data[mode]
        m.request_count += 1
        m.total_latency_seconds += latency_seconds
        m.total_tokens += tokens
        if not success:
            m.error_count += 1

    @contextmanager
    def measure(self, mode: str, tokens_ref: list[int]) -> Generator[None, None, None]:
        """
        Context manager that records latency and success automatically.

        Usage:
            tokens = [0]
            with metrics.measure("agent", tokens):
                result = do_work()
                tokens[0] = result.token_count
        """
        start = time.perf_counter()
        success = True
        try:
            yield
        except Exception:
            success = False
            raise
        finally:
            elapsed = time.perf_counter() - start
            self.record_request(mode, elapsed, tokens_ref[0], success)

    def to_prometheus_text(self) -> str:
        lines: list[str] = []

        for mode, m in self._data.items():
            avg_latency = (
                m.total_latency_seconds / m.request_count if m.request_count > 0 else 0.0
            )
            lines += [
                '# HELP chatbot_requests_total Total requests per mode',
                '# TYPE chatbot_requests_total counter',
                f'chatbot_requests_total{{mode="{mode}"}} {m.request_count}',
                '',
                '# HELP chatbot_errors_total Total errors per mode',
                '# TYPE chatbot_errors_total counter',
                f'chatbot_errors_total{{mode="{mode}"}} {m.error_count}',
                '',
                '# HELP chatbot_latency_seconds_avg Average latency per mode (seconds)',
                '# TYPE chatbot_latency_seconds_avg gauge',
                f'chatbot_latency_seconds_avg{{mode="{mode}"}} {avg_latency:.4f}',
                '',
                '# HELP chatbot_tokens_total Total tokens used per mode',
                '# TYPE chatbot_tokens_total counter',
                f'chatbot_tokens_total{{mode="{mode}"}} {m.total_tokens}',
                '',
            ]

        if not lines:
            lines = ["# No requests recorded yet\n"]

        return "\n".join(lines)

    def summary(self) -> dict:
        """Return metrics as a dict (used in /health extended response)."""
        return {
            mode: {
                "request_count": m.request_count,
                "error_count": m.error_count,
                "error_rate": round(m.error_count / m.request_count, 4) if m.request_count else 0,
                "avg_latency_seconds": round(
                    m.total_latency_seconds / m.request_count, 4
                ) if m.request_count else 0,
                "total_tokens": m.total_tokens,
            }
            for mode, m in self._data.items()
        }


# Singleton — shared across the app lifetime
metrics_store = MetricsStore()

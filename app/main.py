"""
FastAPI application entry point.

Endpoints:
  POST /chat    — NL-to-SQL query (mode: "agent" | "function_call")
  GET  /health  — liveness check + per-mode metrics summary
  GET  /metrics — Prometheus-format metrics
"""

from __future__ import annotations

import logging
import time
from typing import Literal

import uvicorn
from fastapi import FastAPI, HTTPException
from fastapi.responses import PlainTextResponse
from pydantic import BaseModel

from app.agent_mode import run_agent
from app.config import get_settings
from app.function_call_mode import run_function_call
from app.metrics import metrics_store

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
settings = get_settings()
logging.basicConfig(
    level=settings.log_level.upper(),
    format='{"time": "%(asctime)s", "level": "%(levelname)s", "logger": "%(name)s", "message": "%(message)s"}',
)
logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# App
# ---------------------------------------------------------------------------
app = FastAPI(
    title="AdventureWorks SQL Chatbot",
    description="NL-to-SQL chatbot with two modes: LangChain ReAct Agent and Function Calling",
    version="1.0.0",
)


# ---------------------------------------------------------------------------
# Request / Response models
# ---------------------------------------------------------------------------
class ChatRequest(BaseModel):
    question: str
    mode: Literal["agent", "function_call"] = "agent"


class ChatResponse(BaseModel):
    answer: str
    mode: str
    latency_seconds: float
    tokens_used: int
    # Mode-specific extras
    sql_query: str | None = None
    agent_steps: list[dict] | None = None


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------
@app.post("/chat", response_model=ChatResponse)
async def chat(request: ChatRequest) -> ChatResponse:
    """
    Ask a natural language question about the AdventureWorks database.

    - mode=agent        → LangChain ReAct agent (multi-step, self-correcting)
    - mode=function_call → Single-shot function calling (fast, deterministic)
    """
    start = time.perf_counter()
    tokens_ref = [0]

    try:
        if request.mode == "agent":
            result = run_agent(request.question)
            tokens_ref[0] = result.tokens_used
            elapsed = time.perf_counter() - start
            metrics_store.record_request("agent", elapsed, result.tokens_used, success=True)

            logger.info(
                '{"event": "chat", "mode": "agent", "latency": %.3f, "tokens": %d, "steps": %d}',
                elapsed,
                result.tokens_used,
                len(result.steps),
            )

            return ChatResponse(
                answer=result.answer,
                mode="agent",
                latency_seconds=round(elapsed, 3),
                tokens_used=result.tokens_used,
                agent_steps=result.steps,
            )

        elif request.mode == "function_call":
            result = run_function_call(request.question)
            tokens_ref[0] = result.tokens_used
            elapsed = time.perf_counter() - start
            metrics_store.record_request("function_call", elapsed, result.tokens_used, success=True)

            logger.info(
                '{"event": "chat", "mode": "function_call", "latency": %.3f, "tokens": %d}',
                elapsed,
                result.tokens_used,
            )

            return ChatResponse(
                answer=result.answer,
                mode="function_call",
                latency_seconds=round(elapsed, 3),
                tokens_used=result.tokens_used,
                sql_query=result.sql_query,
            )

    except Exception as exc:
        elapsed = time.perf_counter() - start
        metrics_store.record_request(request.mode, elapsed, 0, success=False)
        logger.error(
            '{"event": "chat_error", "mode": "%s", "error": "%s"}',
            request.mode,
            str(exc),
        )
        raise HTTPException(status_code=500, detail=str(exc)) from exc

    raise HTTPException(status_code=400, detail=f"Unknown mode: {request.mode}")


@app.get("/health")
async def health() -> dict:
    """Liveness check. Returns status and per-mode metrics summary."""
    return {
        "status": "ok",
        "metrics": metrics_store.summary(),
    }


@app.get("/metrics", response_class=PlainTextResponse)
async def metrics() -> str:
    """Prometheus-format metrics. Scrape this with Prometheus or Azure Monitor."""
    return metrics_store.to_prometheus_text()


# ---------------------------------------------------------------------------
# Entry point (local dev)
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    uvicorn.run("app.main:app", host="0.0.0.0", port=settings.app_port, reload=True)

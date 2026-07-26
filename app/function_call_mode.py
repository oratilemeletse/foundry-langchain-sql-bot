"""
Mode B — Direct Function Calling (single-shot NL-to-SQL).

Flow:
  1. Build a system prompt that contains the full DB schema.
  2. Register run_sql as a tool (OpenAI function-calling format).
  3. Send user question to Azure OpenAI.
  4. LLM returns a tool_call JSON with the SQL query.
  5. Execute the SQL, get rows back.
  6. Send rows back to LLM for a natural-language summary.

Faster and cheaper than the ReAct agent, but no self-correction loop.
"""

from __future__ import annotations

import json
import logging
from dataclasses import dataclass

from openai import AzureOpenAI

from app.config import get_settings
from app.db import get_schema_summary, run_query

logger = logging.getLogger(__name__)

# Tool definition registered with the LLM
_RUN_SQL_TOOL = {
    "type": "function",
    "function": {
        "name": "run_sql",
        "description": (
            "Execute a read-only SQL SELECT query against the AdventureWorks database "
            "and return the results as JSON. Only use SELECT — never INSERT/UPDATE/DELETE."
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": "A valid SQL SELECT statement.",
                }
            },
            "required": ["query"],
        },
    },
}


@dataclass
class FunctionCallResult:
    answer: str
    sql_query: str
    tokens_used: int
    raw_rows: list[dict]


def _get_client() -> AzureOpenAI:
    settings = get_settings()
    return AzureOpenAI(
        azure_endpoint=settings.azure_openai_endpoint,
        api_key=settings.azure_openai_api_key,
        api_version=settings.azure_openai_api_version,
    )


def run_function_call(question: str) -> FunctionCallResult:
    """
    Single-shot NL-to-SQL using OpenAI function calling.
    Returns the answer and execution metadata.
    """
    settings = get_settings()
    client = _get_client()
    schema = get_schema_summary()

    system_prompt = (
        "You are an expert SQL assistant for the AdventureWorks database.\n"
        "Use the run_sql tool to answer the user's question by querying the database.\n"
        "Only run SELECT queries — never modify data.\n\n"
        "Database schema (table_name(col1, col2, ...)):\n"
        f"{schema}"
    )

    messages = [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": question},
    ]

    logger.info("[function_call] question=%r", question)

    # Step 1: Ask LLM to generate SQL via tool call
    response1 = client.chat.completions.create(
        model=settings.azure_openai_deployment_name,
        messages=messages,
        tools=[_RUN_SQL_TOOL],
        tool_choice={"type": "function", "function": {"name": "run_sql"}},
    )

    choice = response1.choices[0]
    tool_call = choice.message.tool_calls[0]
    args = json.loads(tool_call.function.arguments)
    sql_query = args["query"]

    logger.info("[function_call] generated_sql=%r", sql_query)

    # Step 2: Execute the SQL
    rows = run_query(sql_query)
    rows_json = json.dumps(rows, default=str)

    # Step 3: Send results back to LLM for a natural-language summary
    messages.append(choice.message)
    messages.append(
        {
            "role": "tool",
            "tool_call_id": tool_call.id,
            "content": rows_json,
        }
    )

    response2 = client.chat.completions.create(
        model=settings.azure_openai_deployment_name,
        messages=messages,
    )

    answer = response2.choices[0].message.content or ""

    # Sum tokens across both calls
    tokens_used = (
        (response1.usage.total_tokens if response1.usage else 0)
        + (response2.usage.total_tokens if response2.usage else 0)
    )

    logger.info("[function_call] tokens_used=%d", tokens_used)

    return FunctionCallResult(
        answer=answer,
        sql_query=sql_query,
        tokens_used=tokens_used,
        raw_rows=rows,
    )

"""
Mode A — LangChain ReAct SQL Agent.

Uses LangChain's create_sql_agent which runs a Reason+Act loop:
  Thought → Action (tool call) → Observation → ... → Final Answer

Tools available to the agent:
  - list_tables_tool   : list all tables
  - get_schema_tool    : get column info for one or more tables
  - query_sql_tool     : run a SELECT query
  - query_checker_tool : ask the LLM to double-check a query before running it

The agent can self-correct: if a query fails, it rewrites it and retries.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass

from langchain_community.agent_toolkits import SQLDatabaseToolkit, create_sql_agent
from langchain_community.utilities import SQLDatabase
from langchain_openai import AzureChatOpenAI

from app.config import get_settings
from app.db import get_connection_string

logger = logging.getLogger(__name__)


@dataclass
class AgentResult:
    answer: str
    tokens_used: int
    steps: list[dict]


def _get_llm() -> AzureChatOpenAI:
    settings = get_settings()
    return AzureChatOpenAI(
        azure_endpoint=settings.azure_openai_endpoint,
        azure_deployment=settings.azure_openai_deployment_name,
        api_version=settings.azure_openai_api_version,
        api_key=settings.azure_openai_api_key,
        temperature=0,
    )


def run_agent(question: str) -> AgentResult:
    """
    Run the LangChain ReAct SQL agent against the question.
    Returns the final answer and metadata.
    """
    conn_str = get_connection_string()

    db = SQLDatabase.from_uri(conn_str)
    llm = _get_llm()
    toolkit = SQLDatabaseToolkit(db=db, llm=llm)

    agent = create_sql_agent(
        llm=llm,
        toolkit=toolkit,
        verbose=False,
        agent_executor_kwargs={"return_intermediate_steps": True},
        max_iterations=10,
    )

    logger.info("[agent] question=%r", question)

    response = agent.invoke({"input": question})

    answer = response.get("output", "")
    intermediate_steps = response.get("intermediate_steps", [])

    # Extract step info for logging / tracing
    steps = []
    for action, observation in intermediate_steps:
        steps.append(
            {
                "tool": action.tool,
                "tool_input": action.tool_input,
                "observation": str(observation)[:500],
            }
        )

    # LangChain doesn't surface token counts easily without callbacks;
    # we use a rough estimate: 4 chars ≈ 1 token
    raw_text = question + answer + str(intermediate_steps)
    estimated_tokens = len(raw_text) // 4

    logger.info("[agent] steps=%d estimated_tokens=%d", len(steps), estimated_tokens)

    return AgentResult(answer=answer, tokens_used=estimated_tokens, steps=steps)

# LLM Integration Patterns for Production

Comprehensive patterns and best practices for integrating Large Language Models into production systems, covering API design, RAG, evaluation, guardrails, caching, routing, and agent architectures.

---

## Table of Contents

1. [API Client Design](#api-client-design)
2. [Token Counting and Cost Estimation](#token-counting-and-cost-estimation)
3. [Structured Output](#structured-output)
4. [Prompt Management](#prompt-management)
5. [RAG Implementation](#rag-implementation)
6. [Evaluation Framework](#evaluation-framework)
7. [Guardrails and Content Filtering](#guardrails-and-content-filtering)
8. [Caching Strategies](#caching-strategies)
9. [Multi-Model Routing](#multi-model-routing)
10. [Agent and Tool-Use Patterns](#agent-and-tool-use-patterns)

---

## API Client Design

### Resilient Client with Retry, Fallback, and Streaming

```python
import asyncio
import time
import hashlib
from dataclasses import dataclass, field
from enum import Enum
from typing import AsyncIterator

import httpx
from tenacity import (
    retry,
    stop_after_attempt,
    wait_exponential_jitter,
    retry_if_exception_type,
)


class LLMProvider(Enum):
    OPENAI = "openai"
    ANTHROPIC = "anthropic"
    GOOGLE = "google"


@dataclass
class LLMResponse:
    content: str
    model: str
    provider: LLMProvider
    input_tokens: int
    output_tokens: int
    latency_ms: float
    cached: bool = False
    finish_reason: str = ""


@dataclass
class LLMClientConfig:
    primary_provider: LLMProvider = LLMProvider.ANTHROPIC
    fallback_providers: list[LLMProvider] = field(default_factory=lambda: [LLMProvider.OPENAI])
    max_retries: int = 3
    timeout_seconds: float = 60.0
    retry_min_wait: float = 1.0
    retry_max_wait: float = 30.0


class RateLimitError(Exception):
    """Raised when API returns 429 Too Many Requests."""
    def __init__(self, retry_after: float = 0):
        self.retry_after = retry_after


class LLMClient:
    """Production LLM client with retry, fallback, streaming, and observability."""

    def __init__(self, config: LLMClientConfig):
        self.config = config
        self.providers = self._init_providers()
        self._request_count = 0
        self._error_count = 0

    def _init_providers(self) -> dict[LLMProvider, httpx.AsyncClient]:
        base_urls = {
            LLMProvider.OPENAI: "https://api.openai.com/v1",
            LLMProvider.ANTHROPIC: "https://api.anthropic.com/v1",
            LLMProvider.GOOGLE: "https://generativelanguage.googleapis.com/v1",
        }
        return {
            provider: httpx.AsyncClient(
                base_url=base_urls[provider],
                timeout=httpx.Timeout(self.config.timeout_seconds),
                limits=httpx.Limits(max_connections=50, max_keepalive_connections=10),
            )
            for provider in [self.config.primary_provider] + self.config.fallback_providers
        }

    @retry(
        retry=retry_if_exception_type((httpx.TransportError, RateLimitError)),
        stop=stop_after_attempt(3),
        wait=wait_exponential_jitter(initial=1, max=30, jitter=5),
        before_sleep=lambda retry_state: logger.warning(
            f"Retrying LLM request (attempt {retry_state.attempt_number}): "
            f"{retry_state.outcome.exception()}"
        ),
    )
    async def complete(
        self,
        messages: list[dict],
        model: str,
        temperature: float = 0.0,
        max_tokens: int = 4096,
        **kwargs,
    ) -> LLMResponse:
        """Send a completion request with automatic retry."""

        start_time = time.monotonic()
        self._request_count += 1

        provider = self.config.primary_provider
        try:
            response = await self._send_request(
                provider, messages, model, temperature, max_tokens, **kwargs
            )
        except (httpx.TransportError, RateLimitError):
            raise  # Let tenacity handle retries
        except Exception as e:
            self._error_count += 1
            # Try fallback providers
            for fallback in self.config.fallback_providers:
                try:
                    logger.warning(f"Primary failed, trying fallback: {fallback.value}")
                    response = await self._send_request(
                        fallback, messages, model, temperature, max_tokens, **kwargs
                    )
                    break
                except Exception:
                    continue
            else:
                raise e

        latency_ms = (time.monotonic() - start_time) * 1000
        response.latency_ms = latency_ms

        # Emit metrics
        metrics.histogram("llm.latency_ms", latency_ms, tags=[f"model:{model}"])
        metrics.increment("llm.tokens.input", response.input_tokens)
        metrics.increment("llm.tokens.output", response.output_tokens)

        return response

    async def stream(
        self,
        messages: list[dict],
        model: str,
        temperature: float = 0.0,
        max_tokens: int = 4096,
        **kwargs,
    ) -> AsyncIterator[str]:
        """Stream completion tokens as they are generated."""

        provider = self.config.primary_provider
        client = self.providers[provider]

        async with client.stream(
            "POST",
            "/chat/completions",
            json={
                "model": model,
                "messages": messages,
                "temperature": temperature,
                "max_tokens": max_tokens,
                "stream": True,
                **kwargs,
            },
        ) as response:
            async for line in response.aiter_lines():
                if line.startswith("data: "):
                    data = line[6:]
                    if data == "[DONE]":
                        break
                    chunk = json.loads(data)
                    delta = chunk["choices"][0].get("delta", {})
                    if content := delta.get("content"):
                        yield content

    async def complete_with_fallback(
        self,
        messages: list[dict],
        model_chain: list[tuple[LLMProvider, str]],
        **kwargs,
    ) -> LLMResponse:
        """
        Try models in order, falling back to the next on failure.

        model_chain: [(provider, model_name), ...]
        Example: [
            (LLMProvider.ANTHROPIC, "claude-sonnet-4-20250514"),
            (LLMProvider.OPENAI, "gpt-4o"),
            (LLMProvider.OPENAI, "gpt-4o-mini"),  # cheapest fallback
        ]
        """
        last_error = None
        for provider, model in model_chain:
            try:
                return await self._send_request(provider, messages, model, **kwargs)
            except Exception as e:
                logger.warning(f"Model {model} failed: {e}, trying next...")
                last_error = e
                continue

        raise last_error
```

### Circuit Breaker Pattern

```python
import time
from enum import Enum


class CircuitState(Enum):
    CLOSED = "closed"        # Normal operation
    OPEN = "open"            # Failing, reject requests immediately
    HALF_OPEN = "half_open"  # Testing if service recovered


class CircuitBreaker:
    """
    Circuit breaker for LLM API calls.
    Opens after consecutive failures, periodically tests recovery.
    """

    def __init__(
        self,
        failure_threshold: int = 5,
        recovery_timeout: float = 60.0,
        half_open_max_calls: int = 3,
    ):
        self.failure_threshold = failure_threshold
        self.recovery_timeout = recovery_timeout
        self.half_open_max_calls = half_open_max_calls
        self.state = CircuitState.CLOSED
        self.failure_count = 0
        self.last_failure_time = 0
        self.half_open_calls = 0

    def can_execute(self) -> bool:
        if self.state == CircuitState.CLOSED:
            return True
        elif self.state == CircuitState.OPEN:
            if time.monotonic() - self.last_failure_time >= self.recovery_timeout:
                self.state = CircuitState.HALF_OPEN
                self.half_open_calls = 0
                return True
            return False
        elif self.state == CircuitState.HALF_OPEN:
            return self.half_open_calls < self.half_open_max_calls
        return False

    def record_success(self):
        if self.state == CircuitState.HALF_OPEN:
            self.half_open_calls += 1
            if self.half_open_calls >= self.half_open_max_calls:
                self.state = CircuitState.CLOSED
                self.failure_count = 0
        elif self.state == CircuitState.CLOSED:
            self.failure_count = 0

    def record_failure(self):
        self.failure_count += 1
        self.last_failure_time = time.monotonic()
        if self.failure_count >= self.failure_threshold:
            self.state = CircuitState.OPEN
        if self.state == CircuitState.HALF_OPEN:
            self.state = CircuitState.OPEN
```

---

## Token Counting and Cost Estimation

### Token Counting

```python
import tiktoken

class TokenCounter:
    """Count tokens for cost estimation and context window management."""

    # Encoding mappings (as of 2025)
    MODEL_ENCODINGS = {
        "gpt-4o": "o200k_base",
        "gpt-4o-mini": "o200k_base",
        "gpt-4-turbo": "cl100k_base",
        "gpt-3.5-turbo": "cl100k_base",
    }

    def __init__(self, model: str = "gpt-4o"):
        encoding_name = self.MODEL_ENCODINGS.get(model, "cl100k_base")
        self.encoding = tiktoken.get_encoding(encoding_name)
        self.model = model

    def count_tokens(self, text: str) -> int:
        """Count tokens in a text string."""
        return len(self.encoding.encode(text))

    def count_messages(self, messages: list[dict]) -> int:
        """
        Count tokens in a chat messages array.
        Accounts for message formatting overhead.
        """
        tokens = 0
        for message in messages:
            tokens += 4  # <|im_start|>{role}\n ... <|im_end|>\n
            for key, value in message.items():
                if isinstance(value, str):
                    tokens += self.count_tokens(value)
                elif isinstance(value, list):
                    # Handle content arrays (for multimodal)
                    for item in value:
                        if item.get("type") == "text":
                            tokens += self.count_tokens(item["text"])
                        elif item.get("type") == "image_url":
                            tokens += self._estimate_image_tokens(item)
        tokens += 2  # assistant reply priming
        return tokens

    def _estimate_image_tokens(self, image_item: dict) -> int:
        """Estimate tokens for image inputs (varies by resolution)."""
        detail = image_item.get("image_url", {}).get("detail", "auto")
        if detail == "low":
            return 85
        elif detail == "high":
            return 765  # Base, actual varies with dimensions
        return 765  # Conservative estimate for "auto"

    def truncate_to_fit(
        self,
        text: str,
        max_tokens: int,
        truncation_marker: str = "\n...[truncated]...",
    ) -> str:
        """Truncate text to fit within a token budget."""
        tokens = self.encoding.encode(text)
        if len(tokens) <= max_tokens:
            return text
        marker_tokens = self.encoding.encode(truncation_marker)
        truncated_tokens = tokens[:max_tokens - len(marker_tokens)]
        return self.encoding.decode(truncated_tokens) + truncation_marker
```

### Cost Estimation

```python
@dataclass
class ModelPricing:
    input_per_million: float    # USD per 1M input tokens
    output_per_million: float   # USD per 1M output tokens
    cached_input_per_million: float = 0.0

# Pricing as of early 2025 (update as needed)
PRICING = {
    "claude-sonnet-4-20250514": ModelPricing(3.00, 15.00, 1.50),
    "claude-haiku-3-5": ModelPricing(0.80, 4.00, 0.40),
    "gpt-4o": ModelPricing(2.50, 10.00, 1.25),
    "gpt-4o-mini": ModelPricing(0.15, 0.60, 0.075),
    "gemini-1.5-pro": ModelPricing(1.25, 5.00, 0.3125),
    "gemini-1.5-flash": ModelPricing(0.075, 0.30, 0.01875),
}


class CostEstimator:
    """Estimate and track LLM API costs."""

    def __init__(self):
        self.total_cost = 0.0
        self.cost_by_model: dict[str, float] = {}

    def estimate_cost(
        self,
        model: str,
        input_tokens: int,
        output_tokens: int,
        cached_input_tokens: int = 0,
    ) -> float:
        """Estimate cost for a single request."""
        pricing = PRICING.get(model)
        if not pricing:
            logger.warning(f"No pricing data for model {model}")
            return 0.0

        cost = (
            (input_tokens - cached_input_tokens) * pricing.input_per_million / 1_000_000
            + cached_input_tokens * pricing.cached_input_per_million / 1_000_000
            + output_tokens * pricing.output_per_million / 1_000_000
        )

        self.total_cost += cost
        self.cost_by_model[model] = self.cost_by_model.get(model, 0) + cost
        return cost

    def estimate_monthly_cost(
        self,
        model: str,
        avg_input_tokens: int,
        avg_output_tokens: int,
        requests_per_day: int,
    ) -> dict:
        """Project monthly costs for capacity planning."""
        daily_cost = self.estimate_cost(model, avg_input_tokens, avg_output_tokens) * requests_per_day
        return {
            "model": model,
            "daily_requests": requests_per_day,
            "daily_cost_usd": round(daily_cost, 2),
            "monthly_cost_usd": round(daily_cost * 30, 2),
            "annual_cost_usd": round(daily_cost * 365, 2),
            "cost_per_request_usd": round(daily_cost / requests_per_day, 6),
        }
```

---

## Structured Output

### JSON Mode with Pydantic Validation

```python
from pydantic import BaseModel, Field, validator
import json


class ExtractedEntity(BaseModel):
    name: str = Field(description="Entity name")
    entity_type: str = Field(description="Type: person, organization, location, or date")
    confidence: float = Field(ge=0.0, le=1.0, description="Confidence score 0-1")


class ExtractionResult(BaseModel):
    entities: list[ExtractedEntity]
    summary: str = Field(max_length=500)
    language: str = Field(description="ISO 639-1 language code")


async def extract_structured(
    client: LLMClient,
    text: str,
    schema: type[BaseModel],
    model: str = "gpt-4o",
) -> BaseModel:
    """Extract structured data from text using JSON mode."""

    messages = [
        {
            "role": "system",
            "content": (
                "You are a precise data extraction assistant. "
                "Always respond with valid JSON matching the provided schema. "
                "Never include explanatory text outside the JSON object."
            ),
        },
        {
            "role": "user",
            "content": f"Extract information from the following text according to this schema:\n\n"
                       f"Schema:\n```json\n{json.dumps(schema.model_json_schema(), indent=2)}\n```\n\n"
                       f"Text:\n{text}",
        },
    ]

    response = await client.complete(
        messages=messages,
        model=model,
        temperature=0.0,
        response_format={"type": "json_object"},
    )

    # Parse and validate with Pydantic
    try:
        data = json.loads(response.content)
        return schema.model_validate(data)
    except (json.JSONDecodeError, ValidationError) as e:
        # Retry with error feedback
        messages.append({"role": "assistant", "content": response.content})
        messages.append({
            "role": "user",
            "content": f"Your response had validation errors: {e}\nPlease fix and respond with valid JSON.",
        })
        retry_response = await client.complete(
            messages=messages, model=model, temperature=0.0,
            response_format={"type": "json_object"},
        )
        data = json.loads(retry_response.content)
        return schema.model_validate(data)
```

### Function Calling (Tool Use)

```python
# Define tools for the LLM
TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "search_database",
            "description": "Search the product database by query string and optional filters.",
            "parameters": {
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "Natural language search query",
                    },
                    "category": {
                        "type": "string",
                        "enum": ["electronics", "clothing", "books", "home"],
                        "description": "Product category filter",
                    },
                    "max_price": {
                        "type": "number",
                        "description": "Maximum price in USD",
                    },
                    "in_stock": {
                        "type": "boolean",
                        "description": "Filter to only in-stock items",
                    },
                },
                "required": ["query"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_order_status",
            "description": "Look up the current status of a customer order.",
            "parameters": {
                "type": "object",
                "properties": {
                    "order_id": {
                        "type": "string",
                        "description": "The order ID (format: ORD-XXXXX)",
                    },
                },
                "required": ["order_id"],
            },
        },
    },
]


async def handle_tool_calls(
    client: LLMClient,
    messages: list[dict],
    model: str,
    tool_handlers: dict[str, callable],
    max_iterations: int = 10,
) -> LLMResponse:
    """
    Agentic loop: let the LLM call tools iteratively until it produces a final response.
    """
    for iteration in range(max_iterations):
        response = await client.complete(
            messages=messages,
            model=model,
            tools=TOOLS,
            tool_choice="auto",
        )

        # If no tool calls, return the final text response
        if not response.tool_calls:
            return response

        # Process each tool call
        messages.append({"role": "assistant", "content": response.content, "tool_calls": response.tool_calls})

        for tool_call in response.tool_calls:
            fn_name = tool_call["function"]["name"]
            fn_args = json.loads(tool_call["function"]["arguments"])

            handler = tool_handlers.get(fn_name)
            if not handler:
                result = json.dumps({"error": f"Unknown function: {fn_name}"})
            else:
                try:
                    result = json.dumps(await handler(**fn_args))
                except Exception as e:
                    result = json.dumps({"error": str(e)})

            messages.append({
                "role": "tool",
                "tool_call_id": tool_call["id"],
                "content": result,
            })

    raise MaxIterationsError(f"Tool calling exceeded {max_iterations} iterations")
```

---

## Prompt Management

### Prompt Registry with Versioning

```python
from datetime import datetime
from enum import Enum


class PromptStatus(Enum):
    DRAFT = "draft"
    ACTIVE = "active"
    DEPRECATED = "deprecated"
    ARCHIVED = "archived"


@dataclass
class PromptVersion:
    version: str                 # Semantic version: "1.2.0"
    template: str                # The prompt template with {variable} placeholders
    model: str                   # Target model
    temperature: float
    max_tokens: int
    status: PromptStatus
    created_at: datetime
    created_by: str
    changelog: str               # What changed in this version
    test_results: dict = None    # Evaluation results for this version
    metadata: dict = None        # Arbitrary metadata


class PromptRegistry:
    """
    Centralized prompt management with versioning, A/B testing, and rollback.
    Backed by a database or file system.
    """

    def __init__(self, storage_backend):
        self.storage = storage_backend

    def register_prompt(
        self,
        name: str,
        version: PromptVersion,
    ) -> str:
        """Register a new prompt version."""
        # Validate template variables
        required_vars = self._extract_variables(version.template)

        self.storage.save(name, version)
        logger.info(f"Registered prompt '{name}' version {version.version}")
        return f"{name}:{version.version}"

    def get_prompt(
        self,
        name: str,
        version: str = None,
    ) -> PromptVersion:
        """
        Get a prompt by name. If no version specified, returns the active version.
        """
        if version:
            return self.storage.get(name, version)
        return self.storage.get_active(name)

    def render(
        self,
        name: str,
        variables: dict,
        version: str = None,
    ) -> str:
        """Render a prompt template with variables."""
        prompt = self.get_prompt(name, version)
        try:
            return prompt.template.format(**variables)
        except KeyError as e:
            raise PromptRenderError(f"Missing variable {e} for prompt '{name}'")

    def promote(self, name: str, version: str) -> None:
        """Promote a version to active, demoting the current active version."""
        current_active = self.storage.get_active(name)
        if current_active:
            current_active.status = PromptStatus.DEPRECATED
            self.storage.save(name, current_active)

        new_active = self.storage.get(name, version)
        new_active.status = PromptStatus.ACTIVE
        self.storage.save(name, new_active)

    def rollback(self, name: str) -> None:
        """Rollback to the previous active version."""
        versions = self.storage.list_versions(name)
        deprecated = [v for v in versions if v.status == PromptStatus.DEPRECATED]
        if not deprecated:
            raise RollbackError(f"No deprecated version to rollback to for '{name}'")

        # Re-activate the most recently deprecated version
        previous = sorted(deprecated, key=lambda v: v.created_at, reverse=True)[0]
        self.promote(name, previous.version)


# Example prompt template
SUMMARIZATION_PROMPT = PromptVersion(
    version="2.1.0",
    template="""You are a helpful assistant that creates concise summaries.

Summarize the following {content_type} in {language}.

Requirements:
- Maximum {max_sentences} sentences
- Preserve key facts and figures
- Use {tone} tone
- Include a one-line TLDR at the top

Content:
{content}""",
    model="claude-sonnet-4-20250514",
    temperature=0.3,
    max_tokens=1024,
    status=PromptStatus.ACTIVE,
    created_at=datetime(2025, 10, 1),
    created_by="ml-team",
    changelog="Added TLDR requirement, improved factual preservation",
)
```

### Prompt A/B Testing

```python
class PromptABTest:
    """A/B test between prompt versions."""

    def __init__(
        self,
        prompt_name: str,
        control_version: str,
        treatment_version: str,
        traffic_split: float = 0.5,
        evaluation_metric: str = "quality_score",
    ):
        self.prompt_name = prompt_name
        self.control_version = control_version
        self.treatment_version = treatment_version
        self.traffic_split = traffic_split
        self.evaluation_metric = evaluation_metric

    def get_variant(self, request_id: str) -> str:
        """Deterministic variant assignment."""
        hash_val = int(hashlib.md5(
            f"{self.prompt_name}:{request_id}".encode()
        ).hexdigest(), 16)
        if (hash_val % 10000) / 10000 < self.traffic_split:
            return self.treatment_version
        return self.control_version

    async def run_with_logging(
        self,
        request_id: str,
        registry: PromptRegistry,
        variables: dict,
        client: LLMClient,
    ) -> tuple[LLMResponse, str]:
        """Run the appropriate variant and log for analysis."""
        variant = self.get_variant(request_id)
        prompt = registry.get_prompt(self.prompt_name, variant)
        rendered = registry.render(self.prompt_name, variables, variant)

        response = await client.complete(
            messages=[{"role": "user", "content": rendered}],
            model=prompt.model,
            temperature=prompt.temperature,
            max_tokens=prompt.max_tokens,
        )

        # Log for analysis
        experiment_log.record({
            "request_id": request_id,
            "prompt_name": self.prompt_name,
            "variant": variant,
            "input_tokens": response.input_tokens,
            "output_tokens": response.output_tokens,
            "latency_ms": response.latency_ms,
        })

        return response, variant
```

---

## RAG Implementation

### Chunking Strategies

```python
from dataclasses import dataclass


@dataclass
class Chunk:
    text: str
    metadata: dict
    chunk_id: str
    token_count: int


class ChunkingStrategy:
    """Various text chunking strategies for RAG pipelines."""

    @staticmethod
    def fixed_size(
        text: str,
        chunk_size: int = 512,
        chunk_overlap: int = 64,
        tokenizer=None,
    ) -> list[Chunk]:
        """
        Fixed-size chunking with overlap.
        Simple, predictable, works well as a baseline.
        """
        if tokenizer is None:
            tokenizer = tiktoken.get_encoding("cl100k_base")

        tokens = tokenizer.encode(text)
        chunks = []
        start = 0

        while start < len(tokens):
            end = min(start + chunk_size, len(tokens))
            chunk_tokens = tokens[start:end]
            chunk_text = tokenizer.decode(chunk_tokens)

            chunks.append(Chunk(
                text=chunk_text,
                metadata={"start_token": start, "end_token": end},
                chunk_id=hashlib.sha256(chunk_text.encode()).hexdigest()[:12],
                token_count=len(chunk_tokens),
            ))

            start += chunk_size - chunk_overlap

        return chunks

    @staticmethod
    def semantic(
        text: str,
        embedding_model,
        similarity_threshold: float = 0.75,
        min_chunk_size: int = 100,
        max_chunk_size: int = 1000,
    ) -> list[Chunk]:
        """
        Semantic chunking: split at points where topic changes.
        Groups consecutive sentences by embedding similarity.
        """
        sentences = text.split(". ")
        if len(sentences) <= 1:
            return [Chunk(text=text, metadata={}, chunk_id="0", token_count=len(text.split()))]

        # Embed each sentence
        embeddings = embedding_model.encode(sentences)

        # Find similarity between consecutive sentences
        chunks = []
        current_chunk_sentences = [sentences[0]]

        for i in range(1, len(sentences)):
            similarity = cosine_similarity(
                embeddings[i-1].reshape(1, -1),
                embeddings[i].reshape(1, -1)
            )[0][0]

            current_text = ". ".join(current_chunk_sentences)

            if similarity < similarity_threshold and len(current_text) >= min_chunk_size:
                chunks.append(Chunk(
                    text=current_text,
                    metadata={"similarity_break": float(similarity)},
                    chunk_id=hashlib.sha256(current_text.encode()).hexdigest()[:12],
                    token_count=len(current_text.split()),
                ))
                current_chunk_sentences = [sentences[i]]
            else:
                current_chunk_sentences.append(sentences[i])

                if len(current_text) >= max_chunk_size:
                    chunks.append(Chunk(
                        text=current_text,
                        metadata={"forced_split": True},
                        chunk_id=hashlib.sha256(current_text.encode()).hexdigest()[:12],
                        token_count=len(current_text.split()),
                    ))
                    current_chunk_sentences = [sentences[i]]

        if current_chunk_sentences:
            remaining = ". ".join(current_chunk_sentences)
            chunks.append(Chunk(
                text=remaining,
                metadata={},
                chunk_id=hashlib.sha256(remaining.encode()).hexdigest()[:12],
                token_count=len(remaining.split()),
            ))

        return chunks

    @staticmethod
    def recursive_document(
        text: str,
        chunk_size: int = 512,
        chunk_overlap: int = 64,
        separators: list[str] = None,
    ) -> list[Chunk]:
        """
        Recursive splitting: try to split on natural boundaries first
        (sections, paragraphs, sentences), falling back to smaller units.
        """
        if separators is None:
            separators = ["\n\n\n", "\n\n", "\n", ". ", " ", ""]

        if len(text) <= chunk_size:
            return [Chunk(
                text=text, metadata={},
                chunk_id=hashlib.sha256(text.encode()).hexdigest()[:12],
                token_count=len(text.split()),
            )]

        for sep in separators:
            if sep and sep in text:
                parts = text.split(sep)
                chunks = []
                current = ""

                for part in parts:
                    if len(current) + len(sep) + len(part) <= chunk_size:
                        current = current + sep + part if current else part
                    else:
                        if current:
                            chunks.append(Chunk(
                                text=current, metadata={"separator": repr(sep)},
                                chunk_id=hashlib.sha256(current.encode()).hexdigest()[:12],
                                token_count=len(current.split()),
                            ))
                        current = part

                if current:
                    chunks.append(Chunk(
                        text=current, metadata={"separator": repr(sep)},
                        chunk_id=hashlib.sha256(current.encode()).hexdigest()[:12],
                        token_count=len(current.split()),
                    ))

                if all(len(c.text) <= chunk_size for c in chunks):
                    return chunks

        return ChunkingStrategy.fixed_size(text, chunk_size, chunk_overlap)
```

### Embedding Model Comparison

| Model | Dimensions | Max Tokens | MTEB Score | Speed | Cost |
|-------|-----------|------------|------------|-------|------|
| **text-embedding-3-large** (OpenAI) | 3072 (configurable) | 8191 | ~65 | Fast | $0.13/M tokens |
| **text-embedding-3-small** (OpenAI) | 1536 (configurable) | 8191 | ~62 | Very fast | $0.02/M tokens |
| **voyage-3** (Voyage AI) | 1024 | 32000 | ~67 | Fast | $0.06/M tokens |
| **embed-v4.0** (Cohere) | 1024 | 512 | ~64 | Fast | $0.10/M tokens |
| **all-MiniLM-L6-v2** (open source) | 384 | 256 | ~56 | Very fast | Free (self-hosted) |
| **bge-large-en-v1.5** (open source) | 1024 | 512 | ~64 | Medium | Free (self-hosted) |
| **e5-mistral-7b** (open source) | 4096 | 32768 | ~66 | Slow | Free (self-hosted) |

### Vector Database Selection

| Database | Type | Strengths | Best For |
|----------|------|-----------|----------|
| **Pinecone** | Managed cloud | Fully managed, easy to use, fast | Quick start, serverless workloads |
| **Weaviate** | Self-hosted/cloud | Hybrid search built-in, GraphQL API | Hybrid search, multimodal |
| **Qdrant** | Self-hosted/cloud | High performance, rich filtering | Production workloads needing complex filters |
| **Milvus/Zilliz** | Self-hosted/cloud | Horizontal scaling, GPU support | Large-scale (100M+ vectors) |
| **ChromaDB** | Embedded | Simple API, easy setup | Prototyping, small datasets |
| **pgvector** | PostgreSQL extension | Use existing Postgres, ACID | Teams already on Postgres, moderate scale |

### Hybrid Search with BM25

Combine dense vector search (semantic) with sparse BM25 search (lexical) for best retrieval quality.

```python
import numpy as np
from rank_bm25 import BM25Okapi


class HybridRetriever:
    """
    Hybrid search combining dense (vector) and sparse (BM25) retrieval
    with Reciprocal Rank Fusion (RRF) for score combination.
    """

    def __init__(
        self,
        vector_store,
        embedding_model,
        bm25_weight: float = 0.3,
        vector_weight: float = 0.7,
        rrf_k: int = 60,
    ):
        self.vector_store = vector_store
        self.embedding_model = embedding_model
        self.bm25_weight = bm25_weight
        self.vector_weight = vector_weight
        self.rrf_k = rrf_k
        self.bm25_index = None
        self.documents = []

    def index_documents(self, documents: list[dict]):
        """Index documents in both vector store and BM25."""
        self.documents = documents

        embeddings = self.embedding_model.encode([d["text"] for d in documents])
        self.vector_store.upsert(
            ids=[d["id"] for d in documents],
            embeddings=embeddings,
            metadata=[d.get("metadata", {}) for d in documents],
        )

        tokenized = [d["text"].lower().split() for d in documents]
        self.bm25_index = BM25Okapi(tokenized)

    def search(
        self,
        query: str,
        top_k: int = 10,
        filter_metadata: dict = None,
    ) -> list[dict]:
        """Hybrid search with Reciprocal Rank Fusion."""

        # Dense retrieval (semantic)
        query_embedding = self.embedding_model.encode([query])[0]
        vector_results = self.vector_store.search(
            query_embedding, top_k=top_k * 3, filter=filter_metadata,
        )

        # Sparse retrieval (BM25)
        tokenized_query = query.lower().split()
        bm25_scores = self.bm25_index.get_scores(tokenized_query)
        bm25_top_indices = np.argsort(bm25_scores)[::-1][:top_k * 3]
        bm25_results = [
            {"id": self.documents[i]["id"], "score": bm25_scores[i]}
            for i in bm25_top_indices if bm25_scores[i] > 0
        ]

        # Reciprocal Rank Fusion
        rrf_scores = {}
        for rank, result in enumerate(vector_results):
            doc_id = result["id"]
            rrf_scores[doc_id] = rrf_scores.get(doc_id, 0) + (
                self.vector_weight / (self.rrf_k + rank + 1)
            )
        for rank, result in enumerate(bm25_results):
            doc_id = result["id"]
            rrf_scores[doc_id] = rrf_scores.get(doc_id, 0) + (
                self.bm25_weight / (self.rrf_k + rank + 1)
            )

        sorted_ids = sorted(rrf_scores.items(), key=lambda x: x[1], reverse=True)
        top_ids = [doc_id for doc_id, score in sorted_ids[:top_k]]

        results = []
        doc_map = {d["id"]: d for d in self.documents}
        for doc_id in top_ids:
            doc = doc_map.get(doc_id)
            if doc:
                results.append({**doc, "rrf_score": rrf_scores[doc_id]})

        return results
```

### Full RAG Pipeline

```python
class RAGPipeline:
    """End-to-end RAG pipeline: query -> retrieve -> rerank -> generate."""

    def __init__(
        self,
        retriever: HybridRetriever,
        llm_client: LLMClient,
        reranker=None,
        model: str = "claude-sonnet-4-20250514",
        max_context_tokens: int = 8000,
    ):
        self.retriever = retriever
        self.llm_client = llm_client
        self.reranker = reranker
        self.model = model
        self.max_context_tokens = max_context_tokens
        self.token_counter = TokenCounter()

    async def query(
        self,
        question: str,
        top_k: int = 5,
        filter_metadata: dict = None,
    ) -> dict:
        """Full RAG query: retrieve, rerank, generate answer with citations."""

        # Step 1: Retrieve
        candidates = self.retriever.search(question, top_k=top_k * 3, filter_metadata=filter_metadata)

        # Step 2: Rerank (optional but recommended)
        if self.reranker:
            candidates = self.reranker.rerank(question, candidates, top_k=top_k)
        else:
            candidates = candidates[:top_k]

        # Step 3: Build context with token budget
        context_chunks = []
        token_budget = self.max_context_tokens
        for doc in candidates:
            chunk_tokens = self.token_counter.count_tokens(doc["text"])
            if chunk_tokens <= token_budget:
                context_chunks.append(doc)
                token_budget -= chunk_tokens
            else:
                break

        # Step 4: Generate answer
        context_text = "\n\n---\n\n".join(
            f"[Source {i+1}: {doc.get('metadata', {}).get('title', 'Unknown')}]\n{doc['text']}"
            for i, doc in enumerate(context_chunks)
        )

        messages = [
            {
                "role": "system",
                "content": (
                    "You are a helpful assistant that answers questions based on provided context. "
                    "Always cite your sources using [Source N] notation. "
                    "If the context doesn't contain enough information to answer, say so clearly. "
                    "Never make up information not present in the context."
                ),
            },
            {
                "role": "user",
                "content": f"Context:\n{context_text}\n\nQuestion: {question}",
            },
        ]

        response = await self.llm_client.complete(
            messages=messages, model=self.model, temperature=0.1,
        )

        return {
            "answer": response.content,
            "sources": [
                {"title": doc.get("metadata", {}).get("title"), "id": doc["id"]}
                for doc in context_chunks
            ],
            "model": self.model,
            "input_tokens": response.input_tokens,
            "output_tokens": response.output_tokens,
        }
```

---

## Evaluation Framework

### Automated Evaluation

```python
from enum import Enum


class EvalMetric(Enum):
    RELEVANCE = "relevance"
    FAITHFULNESS = "faithfulness"
    COMPLETENESS = "completeness"
    COHERENCE = "coherence"
    HARMLESSNESS = "harmlessness"


class LLMJudge:
    """Use an LLM to evaluate another LLM's output (LLM-as-a-judge)."""

    EVAL_PROMPTS = {
        EvalMetric.FAITHFULNESS: """You are evaluating whether an AI assistant's answer is faithful to the provided context.

Context:
{context}

Question: {question}

Answer: {answer}

Evaluate faithfulness on a scale of 1-5:
1: The answer contains fabricated information not in the context
2: The answer mostly guesses with minor context support
3: The answer is partially supported by context
4: The answer is mostly supported by context with minor inferences
5: The answer is fully supported by the provided context

Respond with ONLY a JSON object:
{{"score": <1-5>, "reasoning": "<brief explanation>"}}""",

        EvalMetric.RELEVANCE: """You are evaluating whether an AI assistant's answer is relevant to the user's question.

Question: {question}

Answer: {answer}

Evaluate relevance on a scale of 1-5:
1: Completely irrelevant, does not address the question
2: Tangentially related but misses the core question
3: Partially addresses the question
4: Mostly addresses the question with minor gaps
5: Directly and fully addresses the question

Respond with ONLY a JSON object:
{{"score": <1-5>, "reasoning": "<brief explanation>"}}""",
    }

    def __init__(self, client: LLMClient, judge_model: str = "claude-sonnet-4-20250514"):
        self.client = client
        self.judge_model = judge_model

    async def evaluate(
        self,
        metric: EvalMetric,
        question: str,
        answer: str,
        context: str = "",
    ) -> dict:
        """Evaluate a single response on a specific metric."""
        prompt = self.EVAL_PROMPTS[metric].format(
            question=question, answer=answer, context=context,
        )

        response = await self.client.complete(
            messages=[{"role": "user", "content": prompt}],
            model=self.judge_model,
            temperature=0.0,
            response_format={"type": "json_object"},
        )

        result = json.loads(response.content)
        return {
            "metric": metric.value,
            "score": result["score"],
            "reasoning": result["reasoning"],
            "judge_model": self.judge_model,
        }

    async def evaluate_batch(
        self,
        test_cases: list[dict],
        metrics: list[EvalMetric],
    ) -> pd.DataFrame:
        """Evaluate a batch of test cases across multiple metrics."""
        results = []

        for case in test_cases:
            for metric in metrics:
                result = await self.evaluate(
                    metric=metric,
                    question=case["question"],
                    answer=case["answer"],
                    context=case.get("context", ""),
                )
                results.append({"test_case_id": case["id"], **result})

        df = pd.DataFrame(results)
        summary = df.groupby("metric")["score"].agg(["mean", "std", "min", "max"])
        logger.info(f"Evaluation summary:\n{summary}")

        return df
```

### Human Feedback Loop

```python
@dataclass
class HumanFeedback:
    request_id: str
    question: str
    answer: str
    rating: int              # 1-5
    feedback_text: str       # Free-form feedback
    feedback_category: str   # "incorrect", "incomplete", "great", "harmful", etc.
    annotator_id: str
    timestamp: datetime


class FeedbackCollector:
    """Collect and analyze human feedback for continuous improvement."""

    def __init__(self, storage_backend):
        self.storage = storage_backend

    def record_feedback(self, feedback: HumanFeedback):
        """Record a piece of human feedback."""
        self.storage.save(feedback)

        # Trigger alerts for critical feedback
        if feedback.rating <= 2 or feedback.feedback_category == "harmful":
            alert_ml_team(feedback)

    def get_improvement_candidates(
        self,
        min_samples: int = 10,
        max_rating: float = 3.0,
    ) -> list[dict]:
        """Identify prompt/model configurations that need improvement."""
        feedback_data = self.storage.get_recent(days=30)
        df = pd.DataFrame([vars(f) for f in feedback_data])

        low_rated = df[df["rating"] <= max_rating]

        return low_rated.groupby("feedback_category").agg(
            count=("rating", "count"),
            avg_rating=("rating", "mean"),
            example_questions=("question", lambda x: list(x.head(3))),
        ).sort_values("count", ascending=False).to_dict("records")
```

---

## Guardrails and Content Filtering

### Multi-Layer Guardrail System

```python
from dataclasses import dataclass
from enum import Enum


class GuardrailAction(Enum):
    ALLOW = "allow"
    BLOCK = "block"
    MODIFY = "modify"
    FLAG = "flag"       # Allow but log for review


@dataclass
class GuardrailResult:
    action: GuardrailAction
    reason: str
    modified_content: str = None
    confidence: float = 1.0


class GuardrailPipeline:
    """
    Multi-layer guardrail system for input and output filtering.

    Pipeline order:
    1. Input validation (format, length)
    2. PII detection and redaction
    3. Prompt injection detection
    4. Topic/content policy check
    5. [LLM generates response]
    6. Output content policy check
    7. Output factuality check (for RAG)
    8. PII leak detection in output
    """

    def __init__(self):
        self.input_guards: list[callable] = []
        self.output_guards: list[callable] = []

    def add_input_guard(self, guard: callable):
        self.input_guards.append(guard)

    def add_output_guard(self, guard: callable):
        self.output_guards.append(guard)

    async def check_input(self, user_input: str) -> GuardrailResult:
        """Run all input guardrails. First blocking result stops the pipeline."""
        for guard in self.input_guards:
            result = await guard(user_input)
            if result.action == GuardrailAction.BLOCK:
                return result
            if result.action == GuardrailAction.MODIFY:
                user_input = result.modified_content
        return GuardrailResult(action=GuardrailAction.ALLOW, reason="All input guards passed")

    async def check_output(self, output: str, context: dict = None) -> GuardrailResult:
        """Run all output guardrails."""
        for guard in self.output_guards:
            result = await guard(output, context)
            if result.action == GuardrailAction.BLOCK:
                return result
            if result.action == GuardrailAction.MODIFY:
                output = result.modified_content
        return GuardrailResult(action=GuardrailAction.ALLOW, reason="All output guards passed")


# Example guardrails

async def pii_detection_guard(text: str) -> GuardrailResult:
    """Detect and redact PII from input/output."""
    import re

    pii_patterns = {
        "email": r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b",
        "phone": r"\b\d{3}[-.]?\d{3}[-.]?\d{4}\b",
        "ssn": r"\b\d{3}-\d{2}-\d{4}\b",
        "credit_card": r"\b\d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4}\b",
    }

    detected = {}
    redacted_text = text
    for pii_type, pattern in pii_patterns.items():
        matches = re.findall(pattern, text)
        if matches:
            detected[pii_type] = len(matches)
            redacted_text = re.sub(pattern, f"[REDACTED_{pii_type.upper()}]", redacted_text)

    if detected:
        return GuardrailResult(
            action=GuardrailAction.MODIFY,
            reason=f"PII detected and redacted: {detected}",
            modified_content=redacted_text,
        )

    return GuardrailResult(action=GuardrailAction.ALLOW, reason="No PII detected")


async def prompt_injection_guard(text: str) -> GuardrailResult:
    """Detect prompt injection attempts."""
    injection_indicators = [
        "ignore previous instructions",
        "ignore all previous",
        "disregard your instructions",
        "you are now",
        "new instructions:",
        "system prompt:",
        "override:",
        "jailbreak",
        "DAN mode",
        "developer mode",
    ]

    text_lower = text.lower()
    for indicator in injection_indicators:
        if indicator in text_lower:
            return GuardrailResult(
                action=GuardrailAction.BLOCK,
                reason=f"Potential prompt injection detected: '{indicator}'",
                confidence=0.8,
            )

    return GuardrailResult(action=GuardrailAction.ALLOW, reason="No injection detected")


async def topic_policy_guard(text: str) -> GuardrailResult:
    """Check if the request falls within allowed topics for this application."""
    blocked_topics = ["medical_advice", "legal_advice", "financial_advice"]

    # In production, use a fine-tuned classifier here
    # topic = await classify_topic(text)
    # if topic in blocked_topics:
    #     return GuardrailResult(
    #         action=GuardrailAction.BLOCK,
    #         reason=f"Topic '{topic}' is outside this application's scope"
    #     )

    return GuardrailResult(action=GuardrailAction.ALLOW, reason="Topic within policy")
```

---

## Caching Strategies

### Semantic Cache

```python
import hashlib
import time
from dataclasses import dataclass


@dataclass
class CacheEntry:
    key: str
    response: LLMResponse
    embedding: list[float]
    created_at: float
    ttl_seconds: float
    hit_count: int = 0


class LLMCache:
    """
    Multi-tier caching for LLM responses.

    Tier 1: Exact match cache (fast, deterministic)
    Tier 2: Semantic similarity cache (handles paraphrases)
    """

    def __init__(
        self,
        embedding_model,
        vector_store,
        redis_client=None,
        exact_ttl: int = 3600,
        semantic_ttl: int = 86400,
        similarity_threshold: float = 0.95,
    ):
        self.embedding_model = embedding_model
        self.vector_store = vector_store
        self.redis = redis_client
        self.exact_ttl = exact_ttl
        self.semantic_ttl = semantic_ttl
        self.similarity_threshold = similarity_threshold

    def _compute_exact_key(self, messages: list[dict], model: str, temperature: float) -> str:
        """Compute deterministic cache key for exact match."""
        content = json.dumps({
            "messages": messages, "model": model, "temperature": temperature,
        }, sort_keys=True)
        return f"llm:exact:{hashlib.sha256(content.encode()).hexdigest()}"

    async def get(
        self,
        messages: list[dict],
        model: str,
        temperature: float,
    ) -> LLMResponse | None:
        """Try to get a cached response. Tries exact match first, then semantic."""

        # Tier 1: Exact match
        exact_key = self._compute_exact_key(messages, model, temperature)
        if self.redis:
            cached = await self.redis.get(exact_key)
            if cached:
                metrics.increment("llm.cache.hit", tags=["tier:exact"])
                response = LLMResponse(**json.loads(cached))
                response.cached = True
                return response

        # Tier 2: Semantic similarity (only for temperature=0 deterministic queries)
        if temperature == 0:
            query_text = messages[-1]["content"] if messages else ""
            query_embedding = self.embedding_model.encode([query_text])[0]

            results = self.vector_store.search(
                query_embedding, top_k=1, filter={"model": model}
            )

            if results and results[0]["score"] >= self.similarity_threshold:
                metrics.increment("llm.cache.hit", tags=["tier:semantic"])
                entry = json.loads(results[0]["metadata"]["response"])
                response = LLMResponse(**entry)
                response.cached = True
                return response

        metrics.increment("llm.cache.miss")
        return None

    async def set(
        self,
        messages: list[dict],
        model: str,
        temperature: float,
        response: LLMResponse,
    ):
        """Cache a response in both tiers."""

        exact_key = self._compute_exact_key(messages, model, temperature)

        # Tier 1: Exact match in Redis
        if self.redis:
            await self.redis.setex(exact_key, self.exact_ttl, json.dumps(vars(response)))

        # Tier 2: Semantic cache in vector store
        if temperature == 0:
            query_text = messages[-1]["content"] if messages else ""
            query_embedding = self.embedding_model.encode([query_text])[0]

            self.vector_store.upsert(
                ids=[exact_key],
                embeddings=[query_embedding],
                metadata=[{
                    "model": model,
                    "response": json.dumps(vars(response)),
                    "created_at": time.time(),
                }],
            )
```

### Cache Invalidation Strategies

| Strategy | When to Use | Implementation |
|----------|------------|----------------|
| **TTL-based** | General purpose, data has known freshness window | Set expiry on cache entries |
| **Version-based** | After prompt or model changes | Include prompt version in cache key |
| **Content-based** | When underlying data changes | Invalidate when source documents update |
| **Manual** | After deployment or config changes | Flush cache via admin endpoint |

---

## Multi-Model Routing

### Intelligent Router

```python
class ModelRouter:
    """
    Route requests to the optimal model based on complexity, cost, and latency requirements.
    """

    def __init__(self, client: LLMClient, classifier_model: str = "gpt-4o-mini"):
        self.client = client
        self.classifier_model = classifier_model

        self.model_tiers = {
            "simple": {
                "model": "claude-haiku-3-5",
                "provider": LLMProvider.ANTHROPIC,
                "max_tokens": 1024,
                "cost_per_1k_tokens": 0.001,
            },
            "standard": {
                "model": "claude-sonnet-4-20250514",
                "provider": LLMProvider.ANTHROPIC,
                "max_tokens": 4096,
                "cost_per_1k_tokens": 0.009,
            },
            "complex": {
                "model": "claude-opus-4-20250514",
                "provider": LLMProvider.ANTHROPIC,
                "max_tokens": 4096,
                "cost_per_1k_tokens": 0.045,
            },
        }

    async def classify_complexity(self, messages: list[dict]) -> str:
        """Classify request complexity to determine routing tier."""
        user_message = messages[-1]["content"] if messages else ""

        # Rule-based fast path
        if len(user_message) < 50 and not any(kw in user_message.lower() for kw in [
            "analyze", "compare", "explain", "reason", "debate", "complex"
        ]):
            return "simple"

        # LLM-based classification for ambiguous cases
        classification_prompt = f"""Classify this user request by complexity.

Request: {user_message[:500]}

Categories:
- "simple": Factual lookups, simple Q&A, formatting, translation
- "standard": Summarization, moderate analysis, code generation, multi-step tasks
- "complex": Deep reasoning, complex analysis, creative writing, nuanced judgment

Respond with ONLY the category name (simple, standard, or complex)."""

        response = await self.client.complete(
            messages=[{"role": "user", "content": classification_prompt}],
            model=self.classifier_model,
            temperature=0.0,
            max_tokens=10,
        )

        tier = response.content.strip().lower()
        return tier if tier in self.model_tiers else "standard"

    async def route(self, messages: list[dict], **kwargs) -> LLMResponse:
        """Route to optimal model and execute."""
        tier = await self.classify_complexity(messages)
        config = self.model_tiers[tier]

        logger.info(f"Routing to tier '{tier}': {config['model']}")
        metrics.increment("llm.routing", tags=[f"tier:{tier}"])

        return await self.client.complete(
            messages=messages,
            model=config["model"],
            max_tokens=config["max_tokens"],
            **kwargs,
        )
```

### Routing Decision Matrix

| Request Type | Latency Budget | Cost Sensitivity | Recommended Tier |
|-------------|---------------|-----------------|-----------------|
| Autocomplete, simple chat | <500ms | High | Haiku / GPT-4o-mini / Flash |
| Summarization, moderate analysis | <5s | Medium | Sonnet / GPT-4o |
| Complex reasoning, code review | <30s | Low | Opus / o1 / Gemini Pro |
| Batch processing (offline) | Minutes | Very high | Cheapest that meets quality bar |

---

## Agent and Tool-Use Patterns

### ReAct Agent Pattern

```python
class ReActAgent:
    """
    ReAct (Reasoning + Acting) agent that interleaves
    thinking and tool use to solve multi-step problems.
    """

    def __init__(
        self,
        client: LLMClient,
        tools: dict[str, callable],
        model: str = "claude-sonnet-4-20250514",
        max_steps: int = 15,
        max_tokens: int = 4096,
    ):
        self.client = client
        self.tools = tools
        self.model = model
        self.max_steps = max_steps
        self.max_tokens = max_tokens

    def _build_system_prompt(self) -> str:
        tool_descriptions = "\n".join(
            f"- {name}: {fn.__doc__}" for name, fn in self.tools.items()
        )
        return f"""You are a helpful assistant that can use tools to answer questions.

Available tools:
{tool_descriptions}

For each step, use this format:
Thought: [your reasoning about what to do next]
Action: [tool_name]
Action Input: [JSON input for the tool]

When you have enough information to answer, use:
Thought: [your final reasoning]
Final Answer: [your complete answer]

Always think step by step. Use tools when you need information you don't have."""

    async def run(self, query: str) -> dict:
        """Execute the agent loop."""
        messages = [
            {"role": "system", "content": self._build_system_prompt()},
            {"role": "user", "content": query},
        ]

        steps = []

        for step_num in range(self.max_steps):
            response = await self.client.complete(
                messages=messages,
                model=self.model,
                max_tokens=self.max_tokens,
                temperature=0.1,
            )

            content = response.content

            if "Final Answer:" in content:
                final_answer = content.split("Final Answer:")[-1].strip()
                steps.append({"type": "final_answer", "content": final_answer})
                return {
                    "answer": final_answer,
                    "steps": steps,
                    "total_steps": step_num + 1,
                }

            action_match = self._parse_action(content)
            if not action_match:
                messages.append({"role": "assistant", "content": content})
                messages.append({
                    "role": "user",
                    "content": "Please use the correct format: Action: [tool_name] followed by Action Input: [input]",
                })
                continue

            tool_name, tool_input = action_match
            steps.append({
                "type": "action",
                "thought": content.split("Action:")[0].replace("Thought:", "").strip(),
                "tool": tool_name,
                "input": tool_input,
            })

            if tool_name not in self.tools:
                observation = f"Error: Unknown tool '{tool_name}'. Available: {list(self.tools.keys())}"
            else:
                try:
                    observation = await self.tools[tool_name](**json.loads(tool_input))
                    observation = str(observation)
                except Exception as e:
                    observation = f"Error executing {tool_name}: {str(e)}"

            steps.append({"type": "observation", "content": observation})

            messages.append({"role": "assistant", "content": content})
            messages.append({"role": "user", "content": f"Observation: {observation}"})

        return {
            "answer": "Agent reached maximum steps without a final answer.",
            "steps": steps,
            "total_steps": self.max_steps,
        }

    def _parse_action(self, text: str) -> tuple[str, str] | None:
        """Parse action name and input from LLM response."""
        if "Action:" not in text or "Action Input:" not in text:
            return None

        action_line = text.split("Action:")[1].split("\n")[0].strip()
        input_line = text.split("Action Input:")[1].strip()

        if input_line.startswith("{"):
            brace_count = 0
            end_idx = 0
            for i, char in enumerate(input_line):
                if char == "{":
                    brace_count += 1
                elif char == "}":
                    brace_count -= 1
                    if brace_count == 0:
                        end_idx = i + 1
                        break
            input_line = input_line[:end_idx]

        return action_line, input_line
```

### Planning Agent (Plan-and-Execute)

```python
class PlanAndExecuteAgent:
    """
    Two-phase agent:
    1. Planner creates a step-by-step plan
    2. Executor carries out each step, potentially re-planning if needed
    """

    def __init__(
        self,
        client: LLMClient,
        tools: dict[str, callable],
        planner_model: str = "claude-sonnet-4-20250514",
        executor_model: str = "claude-sonnet-4-20250514",
    ):
        self.client = client
        self.tools = tools
        self.planner_model = planner_model
        self.executor_model = executor_model

    async def plan(self, query: str, context: str = "") -> list[str]:
        """Generate a step-by-step plan."""
        plan_prompt = f"""Create a step-by-step plan to answer the following query.
Each step should be a concrete, actionable task.
Number each step.
Keep the plan concise (3-7 steps).

Available tools: {list(self.tools.keys())}

{f"Previous context: {context}" if context else ""}

Query: {query}

Plan:"""

        response = await self.client.complete(
            messages=[{"role": "user", "content": plan_prompt}],
            model=self.planner_model,
            temperature=0.2,
        )

        steps = []
        for line in response.content.strip().split("\n"):
            line = line.strip()
            if line and line[0].isdigit():
                step = line.lstrip("0123456789.): ").strip()
                if step:
                    steps.append(step)

        return steps

    async def execute(self, query: str) -> dict:
        """Plan and execute to answer the query."""
        plan = await self.plan(query)
        results = []
        context = ""

        for i, step in enumerate(plan):
            logger.info(f"Executing step {i+1}/{len(plan)}: {step}")

            step_result = await self._execute_step(step, context, query)
            results.append({"step": step, "result": step_result})
            context += f"\nStep {i+1} ({step}): {step_result}\n"

        synthesis_prompt = f"""Based on the following research, provide a comprehensive answer.

Original question: {query}

Research results:
{context}

Provide a clear, well-structured answer:"""

        final = await self.client.complete(
            messages=[{"role": "user", "content": synthesis_prompt}],
            model=self.planner_model,
            temperature=0.3,
        )

        return {
            "answer": final.content,
            "plan": plan,
            "step_results": results,
        }
```

### Tool Design Best Practices

| Principle | Guideline | Example |
|-----------|-----------|---------|
| **Single responsibility** | Each tool does one thing well | `search_products` not `search_and_filter_and_sort_products` |
| **Clear descriptions** | Docstrings the LLM can understand | "Search products by name. Returns top 10 results with price and availability." |
| **Typed parameters** | Use JSON Schema with descriptions | `{"query": {"type": "string", "description": "Product search query"}}` |
| **Graceful errors** | Return error messages, don't throw | `{"error": "Product not found", "suggestion": "Try a broader search"}` |
| **Bounded output** | Limit response size | Truncate to 1000 chars, summarize large results |
| **Idempotent reads** | GET-like tools should be safe to retry | Search, lookup, and read operations |
| **Confirmation for writes** | Destructive actions need confirmation | "Are you sure you want to delete order #1234?" |

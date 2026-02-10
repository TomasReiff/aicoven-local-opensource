# Local Context Sandwich, Encrypted Storage, and Model Routing

## Product Overview

This document describes how the AICoven local client will:

- Store all chats, context memory, settings, and agent runs locally on-device using SQLite via GRDB.
- Encrypt provider API keys, chats, and memories with user-provided keys, so no plaintext sensitive data is persisted.
- Support a layered "context sandwich" prompt, hybrid memory retrieval, and multi-provider model routing for both cloud and local models.
- Enable autonomous agents with a user-defined maximum number of steps, fully on-device.

There is no mandatory backend: users bring their own LLM provider API keys or local models, and the app orchestrates everything locally on iOS and macOS.

## Architecture Overview

### Persistence Layer (SQLite + GRDB)

- Single SQLite database opened via GRDB (DatabaseQueue/DatabasePool), stored under Application Support.
- Tables:
  - `threads`: per-conversation metadata and encrypted summaries.
  - `messages`: chat turns with encrypted content.
  - `memory_chunks`: long-term context snippets with embeddings, scopes, and tags.
  - `user_settings`: encrypted JSON of app and routing preferences.
  - `provider_accounts`: BYOK provider configs and key references.
  - `agent_runs`: metadata for autonomous agent runs (profile, max steps, status).
  - `agent_steps`: per-step internal reasoning and tool results, all encrypted.
- GRDB record types map to rows; repository classes provide typed access and apply encryption at the edge.

### Encryption & Key Management

- Users choose a passphrase; the app never stores it directly.
- From the passphrase and a random salt, the app derives a wrapping key `K_wrap` via a strong KDF.
- The app generates a random data encryption key `K_data` used to encrypt all sensitive payloads (chats, memories, settings, provider configs).
- `K_data` is stored only in encrypted form (`Encrypt(K_data, K_wrap)`) plus salt, in Keychain or a small metadata table.
- On unlock, the user re-enters the passphrase; the app derives `K_wrap`, decrypts `K_data`, and keeps it in memory for the session.
- All ciphertext fields are protected with authenticated encryption (AES-GCM or similar) via the `DataEncryptionService` abstraction.
- Provider API keys are either stored directly in Keychain with logical identifiers in the DB, or encrypted with `K_data` in `provider_accounts`.

### Memory model and flows

- Long-term context is stored in the `memory_chunks` table, mapped to `MemoryChunkRecord` / `LocalMemoryChunk` and accessed via `MemoryRepository`.
- Each row contains encrypted text, an optional embedding vector, a scope string (for example `user`, `coven`, or `thread:<thread_id>`), tags, and basic provenance metadata.
- `MemoryService` provides the high-level API used by views, chat, and agents:
  - `searchMemory(...)` uses `EmbeddingService.searchRelevantMemories` for hybrid vector/lexical search when a query is provided, and falls back to the most recent chunks per scope otherwise.
  - `createMemory(...)`, `updateMemory(...)`, and `deleteMemory(...)` manage encrypted chunks and always recompute embeddings when text changes.
- Suggested memory writes from chat/agents are stored in the `memory_proposals` table via `MemoryProposalRecord` / `MemoryProposalRepository`.
  - `listProposals(...)` powers the **Memory Proposals** UI for reviewing pending writes.
  - When a proposal is approved via `reviewProposal(...)`, the content is indexed into `memory_chunks` using `EmbeddingService.indexMemory`, so "Approve" behaves as "save this as memory" in the local-only client.

### LLM Integration

- A unified `LLMClient` protocol abstracts over:
  - Cloud providers (OpenAI, Anthropic, etc.) using user-supplied keys.
  - Local models on macOS (e.g., localhost runtime or Core ML wrappers).
- `LLMClient` supports both chat completions and embeddings.
- Concrete clients fetch provider configs and secrets from the local stores and Keychain.

### Model Routing

- A `ModelRouter` component selects the best model per task based on:
  - Task type (chat, summarize, embed, judge, agent_step, etc.).
  - User settings (preferred providers, cost sensitivity, local-only mode).
  - Capabilities (context length, tools support, quality tier).
- The router returns a `(providerID, modelID)` pair used to pick the right `LLMClient` implementation and model name.
- Optionally, routing itself can be delegated to a small model (local or cheap remote) in future iterations.

### Context Sandwich Builder

- A `ContextBuilder` assembles the full prompt for each turn:
  1. System contract (role, rules, capabilities).
  2. Runtime facts (absolute time, timezone, etc.).
  3. Policies (safety, PII, memory write policy).
  4. Retrieved context memory (top-k memory chunks via hybrid search with scope and PII filters).
  5. Thread summary.
  6. Recent turns (last N messages).
  7. Current user message.
  8. Response checklist (instructions for reasoning, actions, and output).
- Truncation logic ensures the composed prompt fits within the target models context window while preserving critical layers.

### Autonomous Agents

- `AgentProfile` describes each autonomous agent type (tools allowed, memory scopes, routing hints, safety constraints).
- For each autonomous run, an `AgentRun` row stores which profile is used, its `max_steps`, and status.
- The `AgentRunner`:
  - Executes a loop of up to `max_steps` iterations.
  - At each step, builds a step-specific context sandwich with prior agent steps, remaining step budget, and policies.
  - Calls an appropriate model (via `ModelRouter` and `LLMClient`).
  - Interprets tool calls and actions from the model output, executes allowed tools, and stores results in `agent_steps`.
  - Stops early when the model signals completion or a safety rule triggers.
- The user always sets `max_steps` and can stop a run at any time.

Concretely, the current implementation:

- Persists runs and steps via `AgentRunRepository` and encrypted `agent_runs` / `agent_steps` tables (`AgentRunRecord` / `AgentStepRecord`).
- Initializes `AgentRunner.shared` from a `ToolEnvironment` built from the current `LLMConfiguration`, so it only sees providers for which the user has configured API keys.
- Uses a simple JSON tool-calling protocol shared with the streaming chat path: when a model wants to call a tool it must return a single JSON object (no extra text) of the form `{ "tool": "web_search" | "current_time", "input": "...", "reason": "..." }`.
- Maps these tool calls onto `ToolService.webSearch` and `ToolService.currentTime`, appending short summaries and context blocks back into the agent's context sandwich for subsequent steps.

## Implementation Phases

1. **Foundations (DB, encryption, secrets)**
   - Add GRDB, create `DatabaseManager`, and define the core schema.
   - Implement `EncryptionService` and key hierarchy using a user passphrase, `K_wrap`, and `K_data`.
   - Integrate with Keychain for storing encryption metadata and provider secrets.

2. **Stores and retrieval**
   - Implement GRDB-backed `ThreadStore`, `SettingsStore`, `MemoryStore`, and `ProviderAccountStore` using repositories.
   - Add basic embedding storage and in-memory cosine similarity search for memory retrieval.

3. **LLM clients and context sandwich**
   - Define `LLMClient` and implement at least one cloud provider client and a stub/local client.
   - Implement embedding workflows for memory writes and queries.
   - Implement `ContextBuilder` for the 8-layer context sandwich and hook it into the chat flow.

4. **Model routing**
   - Define `ModelDescriptor` and `RoutingContext` and implement a heuristic `ModelRouter` that respects user preferences, capabilities, and local-only mode.
   - Route all LLM calls (chat and embeddings) through the router.

5. **Autonomous agents**
   - Define `AgentProfile`, and implement `AgentRun`/`AgentStep` storage.
   - Implement `AgentRunner` with a hard cap on steps and full integration with context sandwich and routing.
   - Add UI affordances for configuring and observing runs.

## Tools layer and web search

On top of the LLM and routing layer, the client exposes a small set of **provider-agnostic tools** used by both agents and the interactive chat UI:

- `ToolEnvironment` inspects the configured model catalog and derives per-provider capabilities (default chat model, vision model, whether a files API is supported, etc.).
- `ToolService` is an `actor` that owns a `ToolEnvironment` instance and provides:
  - Timezone-aware `currentTime()` used by the context sandwich.
  - `webSearch(query:maxResults:)` implemented via DuckDuckGo's public JSON API (no extra keys).
  - `analyzeAttachment(...)` and `analyzeFile(...)` that use the best available chat/vision model to summarize or answer questions about images and files.
  - `generateImage(prompt:)` and `generateFile(...)` which create local image/file artifacts and return URLs that can be attached to messages.

The tools layer is intentionally thin: it never talks to a custom backend and only uses the provider keys the user has configured in the app.

## Current implementation status

The `dev` branch of this repo implements most of the architecture described above:

- GRDB-backed persistence for threads, messages, memories, settings, provider accounts, and agent runs/steps.
- A `DataEncryptionService` and key hierarchy (user passphrase  `K_wrap`  `K_data`) integrated into the repositories.
- `LLMClient` implementations for multiple providers plus a `HeuristicModelRouter` that selects models per task.
- A `ContextBuilder` that composes the layered context sandwich, including runtime time info from `ToolService.currentTime`.
- A local `ChatService` that:
  - Builds context via `ContextBuilder`.
  - Routes to an appropriate provider/model via `ModelRouter`.
  - Streams answers into the SwiftUI chat UI (currently using non-streaming SDK calls under the hood).
- An `AgentRunner` capable of bounded multi-step runs, storing `AgentRun` and `AgentStep` rows.
- A tools layer (`ToolEnvironment` + `ToolService`) wired into both the context sandwich and the enhanced message composer (web search, attachment analysis, local file/image generation).

Some areas remain intentionally flexible or partially implemented so contributors can help shape them:

- Additional providers and local model runtimes.
- Richer tools (e.g. structured browsing, repository-aware tools).
- More sophisticated memory retrieval and summarization.
- UI affordances for inspecting agent runs, tool usage, and memory writes.

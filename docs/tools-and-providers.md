# Providers, API Keys, and Tools

This document explains how the AICoven local client uses your provider keys, how to configure them, and what built-in tools are available in the app.

The client is **local-first** and has no required custom backend. All state (threads, messages, memories, settings, agent runs) is stored on-device. The only outbound network calls are:

- HTTPS requests directly to LLM / embedding providers you configure (e.g. OpenAI, Anthropic, Gemini).
- HTTPS requests to DuckDuckGo's JSON API for web search (no API key required).

## Supported provider types

The `LLMClient` layer is designed to work with multiple providers. The exact list will evolve, but the core categories are:

- **OpenAI-compatible APIs** – chat completions and embeddings.
- **Anthropic** – Claude models via the Messages API.
- **Google / Gemini** – Gemini models via the Generative Language API.
- **Local / custom runtimes** – future integrations for localhost or on-device models.

`ModelRouter` selects a `(providerID, modelID)` pair for each task (chat, summarization, embeddings, etc.) based on the set of providers that have keys configured on your device.

## Where keys are stored

Provider keys are never sent to any AICoven backend; they stay on your device:

- The app uses a `SecretsStore` abstraction backed by the system Keychain to store API credentials securely.
- References to provider accounts and preferences are stored in the encrypted SQLite database.
- When an LLM call is made, the appropriate client pulls the key from `SecretsStore` and adds it to the HTTPS request.

For more on encryption and local storage, see `docs/local-context-architecture.md`.

## Configuring provider keys in the app

> UI labels and exact flows may change slightly over time, but this is the intended user experience.

1. **Open the app** (iOS or macOS) and navigate to the **Settings / Provider Keys** screen.
2. For each provider you want to use (e.g. OpenAI, Anthropic, Gemini):
   - Paste your API key into the corresponding field.
   - Optionally choose a default model if the UI exposes model selection.
3. Save your changes.

Once a key is configured and validated, the `LLMConfiguration` environment and `ModelRouter` will include that provider in routing decisions. If no keys are configured, the app will surface a clear error message when you try to chat.

## How routing works

When you send a message or an agent step runs, the app:

1. Builds a **context sandwich** via `ContextBuilder` (system contract, time, policies, memories, history, current message).
2. Constructs a `RoutingContext` (task type, quality vs. cost preferences, long-context requirements, etc.).
3. Asks `ModelRouter` to choose the best available `ModelDescriptor` for that context, limited to providers with valid keys.
4. Invokes the chosen `LLMClient` with your message(s) and the selected `modelID`.

If no matching provider/model is available (e.g. no keys set, or only incompatible models), the router returns `nil` and the caller shows a human-readable error instead of failing silently.

## Tools overview

On top of raw LLM calls, the app exposes a set of **provider-agnostic tools** implemented by `ToolService`. These tools are designed to:

- Work with whichever providers you have keys for.
- Avoid any additional developer or user keys.
- Produce artifacts (files/images) that the UI can display and the user can download or reuse.

### Time

- `currentTime(timezone:)` returns both UTC and local ISO8601 timestamps plus the timezone identifier.
- `ContextBuilder` injects this into the system messages so the model can reason about "now" without device APIs.

### Web search

- Implemented as `webSearch(query:maxResults:)` on `ToolService`.
- Uses DuckDuckGo's JSON API (`https://api.duckduckgo.com/?q=...&format=json&no_html=1&skip_disambig=1`).
- Does **not** require any key; it is purely HTTP to a public endpoint.
- Returns a small list of `(title, url, snippet)` results.
- Results can be surfaced to the model as extra system context or appended into the user message by the enhanced composer.

### Attachment and file analysis

- `analyzeAttachment(_ attachment:hints:)` branches based on the attachment's MIME type:
  - For images (`image/*`), loads bytes from disk and calls a vision-capable model (if any) via `LLMClient`.
  - For text-like files, reads UTF‑8 content and sends it to the best available chat model.
  - If only a filename is available, synthesizes a description and asks the model for high-level guidance.
- `analyzeFile(text:hints:)` lets callers pass arbitrary text blobs for summarization or Q&A.

These are used in two main places:

- **Interactive chat** – the enhanced message composer can run "Summarize attachments" to generate summaries before you send.
- **Agents** – autonomous runs can call into the same APIs when they need to understand files or images.

### Image generation

- `generateImage(prompt:)` is a simple, provider-backed image helper.
- Today it delegates to an OpenAI chat model when available with a constrained system prompt that returns a data URL.
- The app decodes the data URL locally and writes a PNG under the app's caches directory.
- Returns a small `GeneratedImage` struct with an `id` and a local file `url`.
- The UI attaches these as `FileAttachmentDetail` objects so they behave like regular attachments.

In the future this may be upgraded to use first-class image generation endpoints for multiple providers, but the public API of `ToolService` is intended to remain stable.

### File generation

- `generateFile(name:mimeType:contents:)` writes a file to disk (typically under a `GeneratedFiles` directory) and returns a `GeneratedFile` with `id`, `url`, and MIME type.
- Used for things like saving summaries, reports, or other text artifacts produced during a chat or agent run.
- Files are exposed to the UI as attachments so users can open or export them via the host OS.

## Tools in the chat UI

The enhanced message composer in the personal chat view wires several of these tools directly into the user experience:

- **Web search** – Takes the current draft message as a query and appends a `[Web search results]` section with top results.
- **Summarize attachments** – Runs `analyzeAttachment` for each attached file/image and appends an `[Attachment analysis]` section.
- **Generate image from message** – Calls `generateImage` and attaches the resulting PNG.
- **Generate file from message** – Calls `generateFile` to save the draft text as a `.txt` file and attaches it.

When you hit send:

- Only your **human-authored question** is persisted as the user message in the thread.
- Tool-produced sections (e.g. `[Web search results]`, `[Attachment analysis]`) are treated as **extra system context** in the context sandwich rather than as literal user text.

This keeps the conversation history readable while still giving the model access to richer, tool-generated information.

## Tools in autonomous agents

The same `ToolService` instance is available to the autonomous `AgentRunner`.

- Agents can call web search, attachment analysis, and file/image generation helpers as part of their planning/execution loop.
- Each use of a tool is recorded in the `agent_steps` table along with any intermediate reasoning the model exposes.
- The step limit (`max_steps`) is enforced regardless of tool usage, so tools cannot cause unbounded execution.

Agents and the streaming chat path share a simple JSON protocol for tool calls. When a model wants to call a tool, it must respond with a single JSON object (no extra text) of the form:

```json
{"tool": "web_search" | "current_time", "input": "...", "reason": "..."}
```

`AgentRunner` parses this via an internal `AgentToolCall` helper, executes the mapped `ToolService` method, and feeds a summarized context block back into the context sandwich. The chat streaming path uses a similar `ChatToolInvocation` helper and enforces a configurable `chat_max_tool_steps` budget to avoid unbounded tool loops.

Agent UI and tooling are still evolving, but the intent is to expose:

- A run history showing which tools were invoked and why.
- Links to any generated files/images.
- A clear way to stop or limit tool usage.

## Privacy considerations

- Provider keys never leave the device except in HTTPS requests directly to the chosen provider.
- Tool calls that talk to the network (currently only web search and provider APIs) are explicit and auditable.
- All long-term state (including agent runs and tool outputs that are persisted) is stored in the encrypted SQLite database.

If you intend to extend the tools layer (for example, to add Git or local shell access), please follow the same design constraints:

- Prefer local operations over new remote services.
- Make any outbound network requests explicit and minimal.
- Ensure new tools integrate cleanly with the context sandwich and do not leak sensitive data by default.

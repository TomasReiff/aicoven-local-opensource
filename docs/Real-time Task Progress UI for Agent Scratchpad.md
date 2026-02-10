# Real-time Task Progress UI for Agent Scratchpad
## Problem Statement
Currently, the agent outputs `<scratchpad>` blocks containing task lists that:
1. Show up twice in the final message (once unchecked, once checked)
2. Are not streamed in real-time to show progress
3. Clutter the final response message
## Proposed Solution
Stream scratchpad task updates as separate events, display them in a collapsible "Tasks" UI component (similar to existing Reasoning/Tool Calls), and strip scratchpad blocks from the final message content.
## Architecture Overview
```text
Backend (streaming)          Frontend (Swift)
─────────────────────       ─────────────────────
1. Parse <scratchpad>   →   2. Handle scratchpad_update event
   during streaming
                            3. Update @State streamingTasks
4. Emit scratchpad_update
   event with tasks     →   5. Render TasksProgressView
                            
6. Strip scratchpad from    7. Strip scratchpad from
   stored message              displayed message
```
## Implementation Steps
### Step 1: Backend - Parse and emit scratchpad events
File: `apps/api/services/chat_service_pg.py`
* Add `_parse_scratchpad_tasks()` method to extract tasks from `<scratchpad>` blocks
* In `_run_autonomous_loop()`, detect scratchpad content during streaming
* Emit new event type `scratchpad_update` with structured task data:
```json
{
  "type": "scratchpad_update",
  "tasks": [
    {"id": "1", "title": "Fetch license text", "completed": false},
    {"id": "2", "title": "Check repo branch", "completed": true}
  ]
}
```
* Add `_strip_scratchpad_blocks()` method to clean final message content
### Step 2: Backend - Strip scratchpad from stored messages
File: `apps/api/services/chat_service_pg.py`
* Before storing assistant message in `_insert_message()` call, strip `<scratchpad>...</scratchpad>` blocks
* Keep task metadata in message metadata for audit trail
### Step 3: Swift - Define scratchpad event model
File: `apps/swift/AICoven/AICoven/Services/ChatService.swift`
* Add `scratchpad_update` case to `ChatStreamEvent` decoder
* Create `AgentTask` struct: `{id: String, title: String, completed: Bool}`
### Step 4: Swift - Handle scratchpad events in stream handler
File: `apps/swift/AICoven/AICoven/Services/ChatService.swift`
* Add `onScratchpadUpdate: @escaping ([AgentTask]) -> Void` callback to `streamMessage()`
* Parse and forward scratchpad events to callback
### Step 5: Swift - Add streaming tasks state to WorkspaceView
File: `apps/swift/AICoven/AICoven/Views/Main/WorkspaceView.swift`
* Add `@State private var streamingTasks: [AgentTask] = []`
* Pass `onScratchpadUpdate` callback to `streamMessage()` that updates `streamingTasks`
* Clear tasks on stream completion
### Step 6: Swift - Create TasksProgressView component
File: `apps/swift/AICoven/AICoven/Views/Chat/TasksProgressView.swift` (new)
* Create collapsible DisclosureGroup similar to AgentFeaturesView
* Show task list with checkmarks: `[x]` completed, `[ ]` pending
* Header shows progress: "Tasks (2/3)"
### Step 7: Swift - Integrate TasksProgressView into chat UI
File: `apps/swift/AICoven/AICoven/Views/Main/WorkspaceView.swift`
* Display `TasksProgressView` in the thinking indicator area when `isSending && !streamingTasks.isEmpty`
* Animate task completion state changes
### Step 8: Swift - Strip scratchpad from message display
File: `apps/swift/AICoven/AICoven/Adapters/MessageAdapter.swift`
* Update `sanitizeContent()` to remove `<scratchpad>...</scratchpad>` blocks
* Ensure final displayed message is clean
## Data Model
```swift
struct AgentTask: Identifiable, Codable {
    let id: String
    let title: String
    var completed: Bool
}
```
## Event Schema
```json
{
  "type": "scratchpad_update",
  "tasks": [
    {"id": "task-1", "title": "Fetch PolyForm License 1.0.0 text", "completed": false},
    {"id": "task-2", "title": "Determine default branch (dev)", "completed": true},
    {"id": "task-3", "title": "Create LICENSE file", "completed": false}
  ]
}
```
## Testing
* Verify scratchpad events stream correctly during tool-using tasks
* Verify tasks update in real-time as agent marks them complete
* Verify final message content has no scratchpad blocks
* Verify task progress persists in message metadata for audit

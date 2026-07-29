# AG-UI Event Contract

Athlon Agent chat timeline consumes AG-UI-compatible JSON objects via `handleEvent(event)` / `replayEvents(events[])`.

Each event is a flat JSON object with a required `type` string (SCREAMING_SNAKE_CASE). Payload fields use **camelCase**.

## Core stream events (from `AgentStreamEvent`)

| `type` | Source case | Payload |
|---|---|---|
| `RUN_STARTED` | `runStarted` | `threadId`, `runId` |
| `RUN_FINISHED` | `runFinished` | `threadId`, `runId` |
| `TEXT_MESSAGE_START` | `textMessageStart` | `messageId`, `role` |
| `TEXT_MESSAGE_CONTENT` | `textMessageContent` | `messageId`, `delta` |
| `TEXT_MESSAGE_END` | `textMessageEnd` | `messageId` |
| `REASONING_MESSAGE_START` | `reasoningMessageStart` | `messageId`, `role` |
| `REASONING_MESSAGE_CONTENT` | `reasoningMessageContent` | `messageId`, `delta` |
| `REASONING_MESSAGE_END` | `reasoningMessageEnd` | `messageId` |
| `TOOL_CALL_START` | `toolCallStart` | `toolCallId`, `toolCallName` |
| `TOOL_CALL_ARGS` | `toolCallArgs` | `toolCallId`, `delta` |
| `TOOL_CALL_END` | `toolCallEnd` | `toolCallId`, `status` |
| `TOOL_CALL_RESULT` | `toolCallResult` | `toolCallId`, `content`, `messageId`, `status` (+ optional `header`/`summary`/`markdown`/`html`) |
| `TOOL_CALL_OUTPUT` | `toolCallOutput` | `toolCallId`, `delta` |

Runtime-only cases that may not emit AG-UI JSON directly:

- `chatMessageAppended`
- `clearEmptyAssistantPlaceholder`
- `usageRecorded`
- `contextHygieneApplied`

## UI / host helpers (`ChatEventSerializer`)

| `type` | Purpose | Payload |
|---|---|---|
| `USER_MESSAGE` | Persist/display user bubble | `messageId`, `content`, optional `images[]` |
| `TOOL_APPROVAL_REQUEST` | Ask user to approve a tool | `toolCallId`, `toolName`, `arguments` |
| `TOOL_APPROVAL_RESOLVED` | Approval decision applied | `toolCallId`, `approved` |
| `RESET_TIMELINE` | Clear timeline before replay | _(empty)_ |
| `STATIC_ASSISTANT_HTML` | Replay/history assistant HTML | `messageId`, `markdown`, `html`, `createIfMissing`, optional `streaming` |
| `TURN_ACTIVITY` | Turn activity summary card | activity counters + `items[]` |
| `FILES_CHANGED` | Diff/files changed card | `upsert`, `files[]` |

## WKWebView command envelopes

Host → page commands (not AG-UI events) use:

```json
{ "command": "replay" | "reset" | "prepend" | "historyAvailability", "events": [ ... ], "hasOlderMessages": true }
```

## Theme bridge

```js
applyThemeUpdate(highlightHref, tokensB64, syntaxB64)
```

- `highlightHref`: `github-dark.min.css` or `github.min.css`
- `tokensB64`: base64 UTF-8 of `:root { --chat-bg: ... }` CSS
- `syntaxB64`: optional light-theme hljs overrides

## Fixture

See `Resources/Chat/chat-fixture-events.json` for a minimal replay sequence:
user message → assistant text → `file_list` tool call → assistant wrap-up.

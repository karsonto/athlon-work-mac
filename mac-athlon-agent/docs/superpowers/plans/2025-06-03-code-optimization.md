# AthlonAgent Code Optimization Plan

> **For agentic workers:** Execute tasks sequentially. Each step is a self-contained change with a commit.

**Goal:** Eliminate redundant I/O, fix memory leaks, add compiler optimizations, and clean up stale files in the AthlonAgent project.

**Architecture:** The changes are independent and ordered by risk — safe cleanup first, then correctness fixes, then performance optimizations.

**Tech Stack:** Swift 6, macOS 14+, SwiftUI

---

### Task 1: Remove stale .bak files

**Files:**
- Delete: `mac-athlon-agent/*.bak` (1 file)
- Delete: `mac-athlon-agent/AthlonAgent/**/*.bak` (23 files)

- [ ] **Step 1: List all .bak files and remove them**

```bash
cd F:\mac-athlon-work
for /r mac-athlon-agent %i in (*.bak) do del "%i"
```

- [ ] **Step 2: Verify no .bak files remain**

```bash
dir /s /b mac-athlon-agent\*.bak 2>nul || echo "No .bak files found"
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "chore: remove stale .bak backup files (24 files)"
```

---

### Task 2: Fix SessionWriteLock memory leak — clean up locks on session deletion

**Files:**
- Modify: `mac-athlon-agent/AthlonAgent/Infrastructure/FileStorageService.swift`

**Problem:** `SessionWriteLock` stores an `NSLock` per session in a static dictionary that only grows. When a session is deleted, its lock is never removed.

- [ ] **Step 1: Add `removeLock(for:)` method to `SessionWriteLock`**

In `mac-athlon-agent/AthlonAgent/Infrastructure/FileStorageService.swift`, add:

```swift
static func removeLock(for sessionId: String) {
    registryLock.lock()
    locks.removeValue(forKey: sessionId)
    registryLock.unlock()
}
```

After the existing `lock(for:)` method (line 28).

- [ ] **Step 2: Call `removeLock` in `deleteSession`**

In `FileStorageService.deleteSession` (line ~144-150), add after `removeIndexEntry`:

```swift
SessionWriteLock.removeLock(for: sessionId)
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "fix: clean up SessionWriteLock entries on session deletion"
```

---

### Task 3: Fix persistMessage double-write — remove redundant saveSession calls

**Files:**
- Modify: `mac-athlon-agent/AthlonAgent/Core/AgentRuntime.swift`

**Problem:** `persistMessage()` calls both `appendConversationMessage` (append to jsonl) and `saveSession` (full rewrite of session.json + conversation.jsonl + conversation.md). This means every new message triggers a full rewrite. Additionally, line 170 calls `saveSession` again right after `persistMessage`.

**Fix:** Change `persistMessage` to only append the message. Add a single `saveSession` at the end of `sendAsync` to persist the final state once.

- [ ] **Step 1: Modify `persistMessage` — remove `saveSession`**

Change lines 455-458 from:
```swift
private func persistMessage(session: AgentSession, message: ChatMessage) async {
    try? await storage.appendConversationMessage(sessionId: session.id, message: message)
    try? await storage.saveSession(session)
}
```
to:
```swift
private func persistMessage(session: AgentSession, message: ChatMessage) async {
    try? await storage.appendConversationMessage(sessionId: session.id, message: message)
}
```

- [ ] **Step 2: Remove redundant `saveSession` at line 170**

Remove the line `try? await storage.saveSession(workingSession)` at line 170.

- [ ] **Step 3: Add final `saveSession` at end of `sendAsync`**

After line 199 (closing brace of `while true` loop), before the closing brace of `sendAsync` at line 200, add:

```swift
        try? await storage.saveSession(workingSession)
```

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "perf: eliminate redundant saveSession calls in persistMessage"
```

---

### Task 4: Add compiler optimization flags

**Files:**
- Modify: `mac-athlon-agent/Package.swift`

- [ ] **Step 1: Add optimization flags to Package.swift**

Change line 24-26 from:
```swift
swiftSettings: [
    .swiftLanguageMode(.v5)
]
```
to:
```swift
swiftSettings: [
    .swiftLanguageMode(.v5),
    .unsafeFlags(["-O"])
]
```

- [ ] **Step 2: Commit**

```bash
git add -A
git commit -m "perf: add -O compiler optimization for release builds"
```

---

### Task 5: Tag and push

- [ ] **Step 1: Create tag**

```bash
git tag v1.0.13
```

- [ ] **Step 2: Push all commits and tag**

```bash
git push origin master --tags
```

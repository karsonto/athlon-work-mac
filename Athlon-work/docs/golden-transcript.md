# Golden Transcript 对比

用于将 macOS Athlon Agent 与 Windows 版本在**同一会话目录契约**下对齐。

## 目录布局

顶层会话：

```
~/.athlon-agent/sessions/{sessionId}/
  session.json
  conversation.jsonl
  tool-calls/
  summaries/
  …
```

子 Agent：

```
~/.athlon-agent/sessions/{parentId}/subagents/default/{subId}/
  session.json
  conversation.jsonl
```

## 如何对比

1. 在 Windows 与 macOS 上分别跑同一脚本化对话（相同 model、相同 workspace、关闭 compaction / memory 干扰）。
2. 复制两边的 `conversation.jsonl`。
3. 按行解析 JSON；关注稳定字段：
   - `role`（User / Assistant / Tool）
   - `content`
   - `toolCalls[].name` + `arguments`（忽略 UUID `id`）
   - `toolCallId`（可用 name+序号对齐）
4. 忽略易变字段：绝对路径前缀、时间戳、`id`、token usage。
5. 工具结果允许空白/换行差异；语义一致即可。

## 建议工具

```bash
# 提取 role + 截断 content，便于 diff
jq -c '{role, content: (.content|tostring|.[0:120]), tools: [.toolCalls[]?.name]}' conversation.jsonl
```

将两边输出做 `diff -u`。若工具调用序列与最终 assistant 结论一致，即视为 golden 通过。

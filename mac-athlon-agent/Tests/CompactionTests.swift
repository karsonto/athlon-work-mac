import XCTest
@testable import AthlonAgent

final class CompactionTests: XCTestCase {
    func testContextCompactionSettings_UsesAgentScopeDefaults() {
        let settings = ContextCompactionSettings()
        XCTAssertEqual(settings.triggerMessages, 50)
        XCTAssertEqual(settings.triggerTokens, 80_000)
        XCTAssertEqual(settings.keepMessages, 20)
        XCTAssertEqual(settings.truncateArgs.maxArgLength, 2_000)
        XCTAssertEqual(settings.toolResultEviction.maxResultChars, 80_000)
        XCTAssertEqual(settings.compactTriggerRatio, 0.7)
    }

    func testResolveCompactTriggerTokens_UsesMaxOfFixedAndWindowRatio() {
        var settings = ContextCompactionSettings()
        settings.triggerTokens = 80_000
        settings.contextWindowTokens = 200_000
        settings.compactTriggerRatio = 0.7
        XCTAssertEqual(ConversationCutoffPlanner.resolveCompactTriggerTokens(settings), 140_000)
    }

    func testShouldCompact_TriggersAtWindowRatioThreshold() {
        var settings = ContextCompactionSettings()
        settings.triggerMessages = 0
        settings.triggerTokens = 0
        settings.contextWindowTokens = 100_000
        settings.compactTriggerRatio = 0.7
        let messages = [
            ChatMessage(role: .user, content: String(repeating: "x", count: 280_000))
        ]
        let estimated = ContextTokenEstimator.estimate(messages)
        XCTAssertTrue(ConversationCutoffPlanner.shouldCompact(messages, estimatedTokens: estimated, settings: settings, force: false))
    }

    func testCompactionPlanContextBuilder_IncludesIncompleteSubtasks() {
        let plan = AgentPlan(
            id: "p1",
            name: "Feature",
            description: "Build feature",
            expectedOutcome: "Tests pass",
            subtasks: [
                PlanSubtask(id: "done", index: 0, name: "completed-step", description: "d", expectedOutcome: "o", status: .done),
                PlanSubtask(id: "wip", index: 1, name: "wip", description: "work in progress", expectedOutcome: "api exists", status: .inProgress),
                PlanSubtask(id: "later", index: 2, name: "later", description: "later", expectedOutcome: "later out", status: .pending)
            ],
            createdAt: Date()
        )

        let appendix = CompactionPlanContextBuilder.buildSummaryPromptAppendix(plan)
        XCTAssertNotNil(appendix)
        let incompleteIndex = appendix!.range(of: "## Incomplete subtasks")!
        let incompleteSection = String(appendix![incompleteIndex.lowerBound...])
        XCTAssertTrue(incompleteSection.contains("wip"))
        XCTAssertTrue(incompleteSection.contains("later"))
        XCTAssertTrue(incompleteSection.contains("IN PROGRESS"))
        XCTAssertFalse(incompleteSection.contains("completed-step"))

        let enriched = CompactionPlanContextBuilder.enrichSummaryText("summary body", plan: plan)
        XCTAssertTrue(enriched.contains("summary body"))
        XCTAssertTrue(enriched.contains("Active plan snapshot"))
    }

    func testContextTokenEstimator_UsesCharsPerTokenHeuristic() {
        let message = ChatMessage(role: .user, content: String(repeating: "x", count: 250))
        let textTokens = Int(ceil(250.0 / 2.5))
        XCTAssertGreaterThanOrEqual(ContextTokenEstimator.estimateMessage(message), textTokens)
        XCTAssertEqual(
            ContextTokenEstimator.estimateMessage(message),
            ContextTokenEstimator.estimate([message])
        )
    }

    func testContextTokenEstimator_ExcludesReasoningByDefault() {
        let message = ChatMessage(
            role: .assistant,
            content: "answer",
            reasoningContent: String(repeating: "r", count: 500)
        )
        let withoutReasoning = ContextTokenEstimator.estimateMessage(message)
        let withReasoning = ContextTokenEstimator.estimateMessage(message, includeReasoningInModelContext: true)
        XCTAssertGreaterThan(withReasoning, withoutReasoning)
    }

    func testConversationCutoffPlanner_LongAgentLoop_CompactsWithoutSecondUserMessage() {
        var messages: [ChatMessage] = [
            ChatMessage(role: .user, content: "do the task")
        ]

        for i in 0..<4 {
            messages.append(ChatMessage(
                role: .assistant,
                content: "step-\(i)",
                toolCalls: [AgentToolCall(
                    id: "c\(i)",
                    name: "file_read",
                    arguments: "{}",
                    argumentsStreaming: "",
                    status: .none
                )]
            ))
            messages.append(ChatMessage(role: .tool, content: "output-\(i)", toolCallId: "c\(i)"))
        }

        let settings = ContextCompactionSettings(triggerMessages: 5, keepMessages: 2)
        let estimated = ContextTokenEstimator.estimate(messages)
        XCTAssertTrue(ConversationCutoffPlanner.shouldCompact(messages, estimatedTokens: estimated, settings: settings, force: false))

        let cutoff = ConversationCutoffPlanner.determineCutoffIndex(messages, estimatedTokens: estimated, settings: settings)
        XCTAssertGreaterThan(cutoff, 0)
        XCTAssertEqual(messages.count - cutoff, 2)
    }

    func testConversationCutoffPlanner_KeepTailByMessages() {
        let messages = [
            ChatMessage(role: .user, content: "first"),
            ChatMessage(role: .assistant, content: "reply-1"),
            ChatMessage(role: .user, content: "latest question"),
            ChatMessage(
                role: .assistant,
                content: "thinking",
                toolCalls: [AgentToolCall(id: "c1", name: "file_read", arguments: "{}", argumentsStreaming: "", status: .none)]
            ),
            ChatMessage(role: .tool, content: "tool output", toolCallId: "c1")
        ]

        let cutoff = ConversationCutoffPlanner.determineCutoffIndex(
            messages,
            estimatedTokens: ContextTokenEstimator.estimate(messages),
            settings: ContextCompactionSettings(keepMessages: 2)
        )

        let tail = messages[cutoff...].map(\.content)
        XCTAssertTrue(tail.contains("tool output"))
        XCTAssertFalse(tail.contains("first"))
        XCTAssertFalse(tail.contains("reply-1"))
    }

    func testConversationCutoffPlanner_FindSafeCutoff_DoesNotSplitToolPair() {
        let assistant = ChatMessage(
            role: .assistant,
            content: "",
            toolCalls: [AgentToolCall(id: "call-1", name: "file_read", arguments: "{}", argumentsStreaming: "", status: .none)]
        )
        let tool = ChatMessage(role: .tool, content: "ToolCallId: call-1\noutput", toolCallId: "call-1")
        let messages = [assistant, tool]

        let cutoff = ConversationCutoffPlanner.findSafeCutoffPoint(messages, cutoffIndex: 1)
        XCTAssertEqual(cutoff, 0)
    }

    func testSummaryMessageBuilder_FiltersOldSummaryMessages() {
        let summary = SummaryMessageBuilder.createSummaryPlaceholder(summaryText: "old summary", transcriptPath: nil)
        let user = ChatMessage(role: .user, content: "hello")
        let filtered = SummaryMessageBuilder.filterSummaryMessages([summary, user])
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered[0].content, "hello")
    }

    func testSummaryMessageBuilder_WithTranscript_UsesAgentScopeFormat() {
        let summary = SummaryMessageBuilder.createSummaryPlaceholder(summaryText: "facts", transcriptPath: "/tmp/transcript.jsonl")
        XCTAssertTrue(summary.content.contains("conversation that has been summarized"))
        XCTAssertTrue(summary.content.contains("/tmp/transcript.jsonl"))
        XCTAssertTrue(summary.content.contains("<summary>"))
        XCTAssertTrue(SummaryMessageBuilder.isSummaryMessage(summary))
    }

    func testCompactionMessageContent_IsSummaryPlaceholder_DetectsMarker() {
        let content = "\(ConversationCompactionDefaults.summaryMessageMarker)\nsummary"
        XCTAssertTrue(CompactionMessageContent.isSummaryPlaceholder(content))
    }

    func testConversationCompact_PreservesFullSummaryPreview() {
        let longSummary = String(repeating: "x", count: 400)
        let content = CompactionMessageContent.createConversationCompact(
            tokensBefore: 100,
            tokensAfter: 80,
            originalMessageCount: 5,
            transcriptPath: "t.jsonl",
            summaryPreview: longSummary
        )
        XCTAssertTrue(content.contains(longSummary))
        XCTAssertFalse(content.contains("..."))
    }

    func testTruncateArgsService_TruncatesOldToolArguments() {
        let longArgs = String(repeating: "a", count: 5_000)
        var assistant = ChatMessage(role: .assistant, content: "")
        assistant.toolCalls = [
            AgentToolCall(id: "t1", name: "file_read", arguments: longArgs, argumentsStreaming: "", status: .none)
        ]

        var messages: [ChatMessage] = []
        for index in 0..<8 {
            messages.append(ChatMessage(role: .user, content: "user-\(index)"))
            if index == 2 {
                messages.append(assistant)
                messages.append(ChatMessage(role: .tool, content: "out", toolCallId: "t1"))
            } else {
                messages.append(ChatMessage(role: .assistant, content: "reply-\(index)"))
            }
        }
        messages.append(ChatMessage(role: .user, content: "latest"))
        messages.append(ChatMessage(role: .assistant, content: "tail"))

        var settings = ContextCompactionSettings()
        settings.triggerMessages = 6
        settings.keepMessages = 2
        settings.truncateArgs = TruncateArgsSettings(
            enabled: true,
            triggerMessages: 6,
            keepMessages: 2,
            maxArgLength: 100,
            truncationText: "...(truncated)"
        )

        let session = AgentSession(
            id: "s1",
            title: "t",
            messages: messages,
            createdAt: Date(),
            updatedAt: Date(),
            isActive: true,
            isRunning: false,
            queuedTurnCount: 0
        )

        let updated = TruncateArgsService().applyIfNeeded(session: session, settings: settings)
        let firstAssistant = updated.messages.first { $0.role == MessageRole.assistant && $0.toolCalls != nil }
        let truncatedArgs = firstAssistant?.toolCalls?.first?.arguments ?? ""
        XCTAssertTrue(truncatedArgs.contains("...(truncated)"))
        XCTAssertLessThan(truncatedArgs.count, longArgs.count)
    }
}

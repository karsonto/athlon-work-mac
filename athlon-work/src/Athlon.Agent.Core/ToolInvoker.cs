using System.Diagnostics;
using Athlon.Agent.Core.Compaction;

namespace Athlon.Agent.Core;

public sealed class ToolInvoker(
    IToolRouter toolRouter,
    IFileStorageService storage,
    IToolResultEvictor toolResultEvictor,
    IAppLogger logger) : IToolInvoker
{
    private readonly IAppLogger _logger = logger.ForContext("ToolInvoker");

    public async Task<AgentSession> InvokeToolAndPersistAsync(
        AgentSession session,
        string? parentMessageId,
        AgentToolCall toolCall,
        AgentTurnCallbacks? callbacks,
        CancellationToken cancellationToken)
    {
        var sw = Stopwatch.StartNew();
        ToolResult result;
        try
        {
            result = await toolRouter.InvokeAsync(
                    new ToolInvocation(toolCall.Name, toolCall.Arguments), cancellationToken)
                .ConfigureAwait(false);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception ex)
        {
            _logger.Error(ex, "Tool {ToolName} threw; returning failure to the model", toolCall.Name);
            result = ToolResult.Failure("Tool invocation failed", ex.Message, sw.Elapsed);
        }

        sw.Stop();

        await storage.AppendToolCallLogAsync(
            session.Id,
            new SessionToolCallLogEntry(
                DateTimeOffset.UtcNow,
                toolCall.Id,
                toolCall.Name,
                toolCall.Arguments,
                result.Succeeded,
                result.Summary,
                result.Content,
                result.Error,
                sw.ElapsedMilliseconds),
            cancellationToken);

        var content = FormatToolResult(toolCall, result);
        content = await toolResultEvictor.EvictIfNeededAsync(
            session.Id,
            toolCall,
            result,
            content,
            cancellationToken);

        var toolMessage = ChatMessage.Create(MessageRole.Tool, content, parentMessageId);
        session = session.WithMessage(toolMessage);
        await NotifyMessageAsync(callbacks, toolMessage);
        return session;
    }

    public static string FormatToolResult(AgentToolCall call, ToolResult result)
    {
        var status = result.Succeeded ? "succeeded" : "failed";
        return string.Join(Environment.NewLine, new[]
        {
            $"ToolCallId: {call.Id}",
            $"Tool `{call.Name}` {status}.",
            "",
            $"Arguments: {FormatArguments(call.Arguments)}",
            $"Summary: {result.Summary}",
            "",
            result.Content ?? result.Error ?? string.Empty
        });
    }

    private static string FormatArguments(IReadOnlyDictionary<string, string> arguments)
    {
        return arguments.Count == 0
            ? "(none)"
            : string.Join(Environment.NewLine, arguments.Select(argument => $"{argument.Key}={argument.Value}"));
    }

    public static string? ExtractToolCallId(string? content)
    {
        if (string.IsNullOrWhiteSpace(content))
        {
            return null;
        }

        const string prefix = "ToolCallId:";
        ReadOnlySpan<char> span = content.AsSpan();
        while (span.Length > 0)
        {
            var lineEnd = span.IndexOfAny('\r', '\n');
            ReadOnlySpan<char> line;
            if (lineEnd < 0)
            {
                line = span;
                span = ReadOnlySpan<char>.Empty;
            }
            else
            {
                line = span[..lineEnd];
                span = span[(lineEnd + 1)..];
                if (span.Length > 0 && span[0] == '\n')
                {
                    span = span[1..];
                }
            }

            if (line.StartsWith(prefix.AsSpan(), StringComparison.OrdinalIgnoreCase))
            {
                var value = line[prefix.Length..].Trim().ToString();
                return string.IsNullOrWhiteSpace(value) ? null : value;
            }
        }

        return null;
    }

    private static async Task NotifyMessageAsync(AgentTurnCallbacks? callbacks, ChatMessage message)
    {
        if (callbacks?.OnMessage is not null)
        {
            await callbacks.OnMessage(message);
        }
    }
}

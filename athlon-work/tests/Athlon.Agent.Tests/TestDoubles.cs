using Athlon.Agent.Core;

namespace Athlon.Agent.Tests;

internal sealed class NoOpActiveAgentSessionContext : IActiveAgentSessionContext
{
    private static readonly AsyncLocal<string?> AmbientSessionId = new();

    public string? SessionId => AmbientSessionId.Value;

    public void SetSession(string? sessionId) => AmbientSessionId.Value = sessionId;

    public IDisposable Enter(string sessionId)
    {
        var previous = AmbientSessionId.Value;
        AmbientSessionId.Value = sessionId;
        return new SessionScope(previous);
    }

    private sealed class SessionScope(string? previous) : IDisposable
    {
        public void Dispose() => AmbientSessionId.Value = previous;
    }
}

internal sealed class NoOpToolInvoker : IToolInvoker
{
    private readonly IToolRouter? _toolRouter;

    public NoOpToolInvoker(IToolRouter? toolRouter = null)
    {
        _toolRouter = toolRouter;
    }

    public async Task<AgentSession> InvokeToolAndPersistAsync(
        AgentSession session,
        string? parentMessageId,
        AgentToolCall toolCall,
        AgentTurnCallbacks? callbacks,
        CancellationToken cancellationToken)
    {
        ToolResult result;
        try
        {
            result = await Task.Run(
                    () => _toolRouter?.InvokeAsync(new ToolInvocation(toolCall.Name, toolCall.Arguments), cancellationToken)
                          ?? Task.FromResult(ToolResult.Success("ok", "noop")),
                    cancellationToken)
                .ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            result = ToolResult.Failure("Tool invocation failed", ex.Message);
        }

        var content = ToolInvoker.FormatToolResult(toolCall, result);
        var toolMessage = ChatMessage.Create(MessageRole.Tool, content, parentMessageId);
        session = session.WithMessage(toolMessage);

        if (callbacks?.OnMessage is not null)
        {
            await callbacks.OnMessage(toolMessage);
        }

        return session;
    }
}

internal sealed class NoOpSessionPersistenceManager : ISessionPersistenceManager
{
    private readonly IFileStorageService? _storage;

    public NoOpSessionPersistenceManager(IFileStorageService? storage = null)
    {
        _storage = storage;
    }

    public async Task PersistMessageAsync(AgentSession session, ChatMessage message, CancellationToken cancellationToken, bool saveFull = false)
    {
        if (_storage is not null)
        {
            await _storage.AppendConversationMessageAsync(session.Id, message, cancellationToken);
            if (saveFull)
            {
                await _storage.SaveSessionAsync(session, cancellationToken);
            }
        }
    }

    public async Task SaveSessionAsync(AgentSession session, CancellationToken cancellationToken)
    {
        if (_storage is not null)
        {
            await _storage.SaveSessionAsync(session, cancellationToken);
        }
    }
}

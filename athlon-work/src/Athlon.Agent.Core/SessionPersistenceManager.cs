namespace Athlon.Agent.Core;

public sealed class SessionPersistenceManager(
    IFileStorageService storage,
    IAppLogger logger) : ISessionPersistenceManager
{
    private readonly IAppLogger _logger = logger.ForContext("SessionPersistenceManager");

    public async Task PersistMessageAsync(AgentSession session, ChatMessage message, CancellationToken cancellationToken, bool saveFull = false)
    {
        await storage.AppendConversationMessageAsync(session.Id, message, cancellationToken);
        if (saveFull)
        {
            await storage.SaveSessionAsync(session, cancellationToken);
        }
    }

    public async Task SaveSessionAsync(AgentSession session, CancellationToken cancellationToken)
    {
        await storage.SaveSessionAsync(session, cancellationToken);
    }
}

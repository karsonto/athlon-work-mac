namespace Athlon.Agent.Core;

public interface ISessionPersistenceManager
{
    Task PersistMessageAsync(AgentSession session, ChatMessage message, CancellationToken cancellationToken, bool saveFull = false);
    Task SaveSessionAsync(AgentSession session, CancellationToken cancellationToken);
}

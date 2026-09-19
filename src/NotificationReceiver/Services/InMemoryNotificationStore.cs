using System.Collections.Concurrent;

namespace Mango.NotificationReceiver.Services;

/// <summary>
/// Thread-safe in-memory implementation of <see cref="INotificationStore"/>.
/// Uses a <see cref="ConcurrentDictionary"/> keyed by notification ID for O(1) lookups.
/// Replace with EF Core + SQLite/SQL Server when persistence across restarts is needed.
/// </summary>
public sealed class InMemoryNotificationStore : INotificationStore
{
    // ConcurrentDictionary is safe for multiple concurrent consumer threads
    private readonly ConcurrentDictionary<Guid, ReceivedNotification> _store = new();

    public Task AddAsync(ReceivedNotification notification, CancellationToken cancellationToken = default)
    {
        _store.TryAdd(notification.Id, notification);
        return Task.CompletedTask;
    }

    public Task<IReadOnlyList<ReceivedNotification>> GetAllAsync(CancellationToken cancellationToken = default)
    {
        // Return newest first
        IReadOnlyList<ReceivedNotification> result = _store.Values
            .OrderByDescending(n => n.ReceivedAt)
            .ToList();

        return Task.FromResult(result);
    }

    public Task<ReceivedNotification?> GetByIdAsync(Guid id, CancellationToken cancellationToken = default)
    {
        _store.TryGetValue(id, out var notification);
        return Task.FromResult(notification);
    }
}

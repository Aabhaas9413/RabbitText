namespace Mango.NotificationReceiver.Services;

/// <summary>
/// Represents a notification received from the RabbitMQ queue.
/// </summary>
public sealed record ReceivedNotification
{
    public Guid Id { get; init; }
    public required string Title { get; init; }
    public required string Message { get; init; }
    public string Category { get; init; } = "General";
    public string? RecipientId { get; init; }
    public DateTimeOffset ReceivedAt { get; init; } = DateTimeOffset.UtcNow;
    public DateTimeOffset OriginallyCreatedAt { get; init; }
}

/// <summary>
/// Contract for the notification store on the read (Query) side.
/// Backed by an in-memory implementation; swap for EF Core / Cosmos DB by changing registration only.
/// </summary>
public interface INotificationStore
{
    /// <summary>Persists a notification received from RabbitMQ.</summary>
    Task AddAsync(ReceivedNotification notification, CancellationToken cancellationToken = default);

    /// <summary>Returns all stored notifications, newest first.</summary>
    Task<IReadOnlyList<ReceivedNotification>> GetAllAsync(CancellationToken cancellationToken = default);

    /// <summary>Returns a single notification by ID, or null if not found.</summary>
    Task<ReceivedNotification?> GetByIdAsync(Guid id, CancellationToken cancellationToken = default);
}

namespace Mango.Shared.Events;

/// <summary>
/// Integration event published to RabbitMQ when a notification is created on the Sender side.
/// This is the message contract shared between the NotificationSender and NotificationReceiver services.
/// </summary>
public sealed record NotificationCreatedEvent
{
    /// <summary>Unique identifier for this notification.</summary>
    public Guid Id { get; init; } = Guid.NewGuid();

    /// <summary>The notification title / subject line.</summary>
    public required string Title { get; init; }

    /// <summary>Full message body of the notification.</summary>
    public required string Message { get; init; }

    /// <summary>Logical category or channel (e.g. "Order", "System", "Promo").</summary>
    public string Category { get; init; } = "General";

    /// <summary>Optional recipient identifier (user ID, email, etc.).</summary>
    public string? RecipientId { get; init; }

    /// <summary>UTC timestamp when the event was created.</summary>
    public DateTimeOffset CreatedAt { get; init; } = DateTimeOffset.UtcNow;
}

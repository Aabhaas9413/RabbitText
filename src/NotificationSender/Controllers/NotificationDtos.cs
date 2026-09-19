namespace Mango.NotificationSender.Controllers;

/// <summary>
/// Request DTO for the POST /api/notifications endpoint.
/// Separate from the command to allow API versioning without touching CQRS internals.
/// </summary>
public sealed record SendNotificationRequest
{
    /// <example>Order Shipped</example>
    public required string Title { get; init; }

    /// <example>Your order #12345 has been dispatched and will arrive tomorrow.</example>
    public required string Message { get; init; }

    /// <example>Order</example>
    public string Category { get; init; } = "General";

    /// <example>user-abc-123</example>
    public string? RecipientId { get; init; }
}

/// <summary>Response DTO returned after a notification is successfully queued.</summary>
public sealed record SendNotificationResponse(
    Guid   NotificationId,
    string Status,
    DateTimeOffset QueuedAt);

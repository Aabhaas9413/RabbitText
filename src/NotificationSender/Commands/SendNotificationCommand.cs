using Mango.Shared.Abstractions;

namespace Mango.NotificationSender.Commands;

/// <summary>
/// CQRS Command: instructs the system to create and send a new notification.
/// Returns the generated notification ID upon success.
/// </summary>
public sealed record SendNotificationCommand : ICommand<Guid>
{
    /// <summary>Short title or subject of the notification.</summary>
    public required string Title { get; init; }

    /// <summary>Full message body.</summary>
    public required string Message { get; init; }

    /// <summary>Logical category (e.g. "Order", "System"). Defaults to "General".</summary>
    public string Category { get; init; } = "General";

    /// <summary>Optional recipient identifier.</summary>
    public string? RecipientId { get; init; }
}

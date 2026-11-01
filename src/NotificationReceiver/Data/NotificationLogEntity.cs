using System.ComponentModel.DataAnnotations;

namespace Alpha.NotificationReceiver.Data;

/// <summary>
/// Persistent EF Core entity tracking notification events by Correlation ID in SQLite.
/// A single row tracks the lifecycle (Sent -> Received) for each notification.
/// </summary>
public class NotificationLogEntity
{
    /// <summary>
    /// Unique correlation ID linking the sent notification event to its received record.
    /// Acts as Primary Key in SQLite.
    /// </summary>
    [Key]
    public Guid CorrelationId { get; set; }

    /// <summary>Notification title / subject line.</summary>
    [Required]
    [MaxLength(200)]
    public string Title { get; set; } = string.Empty;

    /// <summary>Notification message body.</summary>
    [Required]
    public string Message { get; set; } = string.Empty;

    /// <summary>Logical category or channel.</summary>
    [MaxLength(100)]
    public string Category { get; set; } = "General";

    /// <summary>Optional recipient user ID or email.</summary>
    [MaxLength(100)]
    public string? RecipientId { get; set; }

    /// <summary>Lifecycle tracking status (e.g. "Sent", "Received").</summary>
    [Required]
    [MaxLength(50)]
    public string Status { get; set; } = "Received";

    /// <summary>Timestamp when notification was originally sent/created.</summary>
    public DateTimeOffset SentAt { get; set; }

    /// <summary>Timestamp when notification was consumed and saved by Receiver.</summary>
    public DateTimeOffset? ReceivedAt { get; set; }
}

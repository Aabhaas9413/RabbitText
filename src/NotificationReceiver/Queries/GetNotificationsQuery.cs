using Mango.Shared.Abstractions;
using Mango.NotificationReceiver.Services;

namespace Mango.NotificationReceiver.Queries;

/// <summary>
/// CQRS Query: returns all notifications that have been received.
/// </summary>
public sealed record GetAllNotificationsQuery : IQuery<IReadOnlyList<ReceivedNotification>>;

/// <summary>
/// CQRS Query: returns a single notification by ID.
/// Returns null if the notification is not found.
/// </summary>
public sealed record GetNotificationByIdQuery(Guid Id)
    : IQuery<ReceivedNotification?>;

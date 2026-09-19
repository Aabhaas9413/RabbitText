using MediatR;
using Mango.NotificationReceiver.Services;

namespace Mango.NotificationReceiver.Queries;

/// <summary>
/// Handles <see cref="GetAllNotificationsQuery"/> — delegates to the notification store.
/// </summary>
public sealed class GetAllNotificationsQueryHandler
    : IRequestHandler<GetAllNotificationsQuery, IReadOnlyList<ReceivedNotification>>
{
    private readonly INotificationStore _store;

    public GetAllNotificationsQueryHandler(INotificationStore store) => _store = store;

    public Task<IReadOnlyList<ReceivedNotification>> Handle(
        GetAllNotificationsQuery request,
        CancellationToken cancellationToken)
        => _store.GetAllAsync(cancellationToken);
}

/// <summary>
/// Handles <see cref="GetNotificationByIdQuery"/> — performs an ID lookup in the store.
/// </summary>
public sealed class GetNotificationByIdQueryHandler
    : IRequestHandler<GetNotificationByIdQuery, ReceivedNotification?>
{
    private readonly INotificationStore _store;

    public GetNotificationByIdQueryHandler(INotificationStore store) => _store = store;

    public Task<ReceivedNotification?> Handle(
        GetNotificationByIdQuery request,
        CancellationToken cancellationToken)
        => _store.GetByIdAsync(request.Id, cancellationToken);
}

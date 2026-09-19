using MassTransit;
using Mango.NotificationReceiver.Services;
using Mango.Shared.Events;

namespace Mango.NotificationReceiver.Consumers;

/// <summary>
/// MassTransit consumer for <see cref="NotificationCreatedEvent"/>.
/// Receives the integration event from RabbitMQ and persists it to the notification store.
/// MassTransit automatically handles acknowledgement, retries, and dead-lettering.
/// </summary>
public sealed class NotificationCreatedConsumer : IConsumer<NotificationCreatedEvent>
{
    private readonly INotificationStore _store;
    private readonly ILogger<NotificationCreatedConsumer> _logger;

    public NotificationCreatedConsumer(
        INotificationStore store,
        ILogger<NotificationCreatedConsumer> logger)
    {
        _store  = store;
        _logger = logger;
    }

    public async Task Consume(ConsumeContext<NotificationCreatedEvent> context)
    {
        var @event = context.Message;

        _logger.LogInformation(
            "[Receiver] Consumed NotificationCreatedEvent. Id={Id}, Title={Title}, Category={Category}",
            @event.Id,
            @event.Title,
            @event.Category);

        var notification = new ReceivedNotification
        {
            Id                   = @event.Id,
            Title                = @event.Title,
            Message              = @event.Message,
            Category             = @event.Category,
            RecipientId          = @event.RecipientId,
            OriginallyCreatedAt  = @event.CreatedAt,
            ReceivedAt           = DateTimeOffset.UtcNow
        };

        await _store.AddAsync(notification, context.CancellationToken);

        _logger.LogInformation("[Receiver] Notification stored. Id={Id}", @event.Id);
    }
}

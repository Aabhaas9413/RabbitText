using MediatR;
using Alpha.NotificationSender.Messaging;
using Alpha.Shared.Events;

namespace Alpha.NotificationSender.Commands;

/// <summary>
/// CQRS Command Handler: processes <see cref="SendNotificationCommand"/>.
/// Constructs the integration event and publishes it via <see cref="INotificationEventPublisher"/>
/// (which routes to either RabbitMQ or Kafka based on the <c>Messaging:Provider</c> feature flag).
/// </summary>
public sealed class SendNotificationCommandHandler
    : IRequestHandler<SendNotificationCommand, Guid>
{
    private readonly INotificationEventPublisher _eventPublisher;
    private readonly ILogger<SendNotificationCommandHandler> _logger;

    public SendNotificationCommandHandler(
        INotificationEventPublisher eventPublisher,
        ILogger<SendNotificationCommandHandler> logger)
    {
        _eventPublisher = eventPublisher;
        _logger         = logger;
    }

    public async Task<Guid> Handle(
        SendNotificationCommand request,
        CancellationToken cancellationToken)
    {
        var notificationId = Guid.NewGuid();

        var integrationEvent = new NotificationCreatedEvent
        {
            Id            = notificationId,
            CorrelationId = notificationId,
            Title         = request.Title,
            Message       = request.Message,
            Category      = request.Category,
            RecipientId   = request.RecipientId,
            CreatedAt     = DateTimeOffset.UtcNow
        };

        await _eventPublisher.PublishAsync(integrationEvent, cancellationToken);

        _logger.LogInformation(
            "[Sender] Published NotificationCreatedEvent via {Provider}. Id={NotificationId}, Title={Title}",
            _eventPublisher.ProviderName,
            notificationId,
            request.Title);

        return notificationId;
    }
}

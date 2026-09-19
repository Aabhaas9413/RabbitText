using MassTransit;
using MediatR;
using Mango.Shared.Events;

namespace Mango.NotificationSender.Commands;

/// <summary>
/// CQRS Command Handler: processes <see cref="SendNotificationCommand"/>.
/// Constructs the integration event and publishes it to RabbitMQ via MassTransit.
/// </summary>
public sealed class SendNotificationCommandHandler
    : IRequestHandler<SendNotificationCommand, Guid>
{
    private readonly IPublishEndpoint _publishEndpoint;
    private readonly ILogger<SendNotificationCommandHandler> _logger;

    public SendNotificationCommandHandler(
        IPublishEndpoint publishEndpoint,
        ILogger<SendNotificationCommandHandler> logger)
    {
        _publishEndpoint = publishEndpoint;
        _logger = logger;
    }

    public async Task<Guid> Handle(
        SendNotificationCommand request,
        CancellationToken cancellationToken)
    {
        var notificationId = Guid.NewGuid();

        var integrationEvent = new NotificationCreatedEvent
        {
            Id          = notificationId,
            Title       = request.Title,
            Message     = request.Message,
            Category    = request.Category,
            RecipientId = request.RecipientId,
            CreatedAt   = DateTimeOffset.UtcNow
        };

        // Publish the integration event to RabbitMQ.
        // MassTransit handles exchange/queue routing automatically.
        await _publishEndpoint.Publish(integrationEvent, cancellationToken);

        _logger.LogInformation(
            "[Sender] Published NotificationCreatedEvent. Id={NotificationId}, Title={Title}",
            notificationId,
            request.Title);

        return notificationId;
    }
}

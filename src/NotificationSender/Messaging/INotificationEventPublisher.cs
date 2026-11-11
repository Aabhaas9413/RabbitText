using Alpha.Shared.Events;
using MassTransit;

namespace Alpha.NotificationSender.Messaging;

/// <summary>
/// Broker-agnostic abstraction for publishing <see cref="NotificationCreatedEvent"/>.
/// The active implementation (RabbitMQ vs. Kafka) is selected at startup via the
/// <c>Messaging:Provider</c> feature flag.
/// </summary>
public interface INotificationEventPublisher
{
    /// <summary>Name of the active messaging provider ("RabbitMQ" or "Kafka").</summary>
    string ProviderName { get; }

    /// <summary>Publishes the notification event to the configured message broker.</summary>
    Task PublishAsync(NotificationCreatedEvent @event, CancellationToken cancellationToken = default);
}

/// <summary>
/// Publishes notification events to a RabbitMQ exchange via MassTransit's <see cref="IPublishEndpoint"/>.
/// </summary>
public sealed class RabbitMqNotificationEventPublisher : INotificationEventPublisher
{
    private readonly IPublishEndpoint _publishEndpoint;

    public RabbitMqNotificationEventPublisher(IPublishEndpoint publishEndpoint)
    {
        _publishEndpoint = publishEndpoint;
    }

    public string ProviderName => "RabbitMQ";

    public Task PublishAsync(NotificationCreatedEvent @event, CancellationToken cancellationToken = default)
        => _publishEndpoint.Publish(@event, cancellationToken);
}

/// <summary>
/// Produces notification events to a Kafka topic via MassTransit's <see cref="ITopicProducer{T}"/>.
/// </summary>
public sealed class KafkaNotificationEventPublisher : INotificationEventPublisher
{
    private readonly ITopicProducer<NotificationCreatedEvent> _topicProducer;

    public KafkaNotificationEventPublisher(ITopicProducer<NotificationCreatedEvent> topicProducer)
    {
        _topicProducer = topicProducer;
    }

    public string ProviderName => "Kafka";

    public Task PublishAsync(NotificationCreatedEvent @event, CancellationToken cancellationToken = default)
        => _topicProducer.Produce(@event, cancellationToken);
}


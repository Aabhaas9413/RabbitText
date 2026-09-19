using MediatR;
using Microsoft.AspNetCore.Mvc;
using Mango.NotificationSender.Commands;

namespace Mango.NotificationSender.Controllers;

/// <summary>
/// Handles incoming HTTP requests for the Notification Sender (Command Side).
/// Dispatches commands via MediatR; has no direct knowledge of RabbitMQ or persistence.
/// </summary>
[ApiController]
[Route("api/[controller]")]
[Produces("application/json")]
public sealed class NotificationsController : ControllerBase
{
    private readonly IMediator _mediator;
    private readonly ILogger<NotificationsController> _logger;

    public NotificationsController(IMediator mediator, ILogger<NotificationsController> logger)
    {
        _mediator = mediator;
        _logger   = logger;
    }

    /// <summary>
    /// Queue a new notification for delivery.
    /// The notification is published to RabbitMQ asynchronously; consumers process it independently.
    /// </summary>
    /// <param name="request">Notification payload.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>The queued notification ID and current status.</returns>
    /// <response code="202">Notification accepted and queued successfully.</response>
    /// <response code="400">Validation error — required fields missing.</response>
    [HttpPost]
    [ProducesResponseType(typeof(SendNotificationResponse), StatusCodes.Status202Accepted)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> SendNotification(
        [FromBody] SendNotificationRequest request,
        CancellationToken cancellationToken)
    {
        _logger.LogInformation("[Sender] Received POST /api/notifications. Title={Title}", request.Title);

        var command = new SendNotificationCommand
        {
            Title       = request.Title,
            Message     = request.Message,
            Category    = request.Category,
            RecipientId = request.RecipientId
        };

        var notificationId = await _mediator.Send(command, cancellationToken);

        var response = new SendNotificationResponse(
            NotificationId: notificationId,
            Status:         "Queued",
            QueuedAt:       DateTimeOffset.UtcNow);

        return Accepted(response);
    }
}

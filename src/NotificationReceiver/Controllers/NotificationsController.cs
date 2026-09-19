using MediatR;
using Microsoft.AspNetCore.Mvc;
using Mango.NotificationReceiver.Queries;
using Mango.NotificationReceiver.Services;

namespace Mango.NotificationReceiver.Controllers;

/// <summary>
/// Read-only API for querying received notifications (Query Side of CQRS).
/// This controller has zero knowledge of RabbitMQ or how notifications arrive.
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
    /// Retrieves all received notifications, newest first.
    /// </summary>
    /// <response code="200">List of received notifications.</response>
    [HttpGet]
    [ProducesResponseType(typeof(IReadOnlyList<ReceivedNotification>), StatusCodes.Status200OK)]
    public async Task<IActionResult> GetAll(CancellationToken cancellationToken)
    {
        _logger.LogInformation("[Receiver] GET /api/notifications");
        var notifications = await _mediator.Send(new GetAllNotificationsQuery(), cancellationToken);
        return Ok(notifications);
    }

    /// <summary>
    /// Retrieves a single notification by its unique ID.
    /// </summary>
    /// <param name="id">The notification GUID.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <response code="200">The notification was found.</response>
    /// <response code="404">No notification exists with the given ID.</response>
    [HttpGet("{id:guid}")]
    [ProducesResponseType(typeof(ReceivedNotification), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetById(Guid id, CancellationToken cancellationToken)
    {
        _logger.LogInformation("[Receiver] GET /api/notifications/{Id}", id);
        var notification = await _mediator.Send(new GetNotificationByIdQuery(id), cancellationToken);

        return notification is null
            ? NotFound(new { Message = $"Notification {id} not found." })
            : Ok(notification);
    }
}

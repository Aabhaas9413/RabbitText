using Mango.NotificationReceiver.Data;
using Microsoft.EntityFrameworkCore;

namespace Mango.NotificationReceiver.Services;

/// <summary>
/// EF Core + SQLite implementation of <see cref="INotificationStore"/>.
/// Tracks notification events by CorrelationId in a single row per event.
/// </summary>
public sealed class SqliteNotificationStore : INotificationStore
{
    private readonly NotificationDbContext _dbContext;
    private readonly ILogger<SqliteNotificationStore> _logger;

    public SqliteNotificationStore(
        NotificationDbContext dbContext,
        ILogger<SqliteNotificationStore> logger)
    {
        _dbContext = dbContext;
        _logger    = logger;
    }

    /// <summary>
    /// Upserts a single row keyed by CorrelationId to log sent and received lifecycle state.
    /// </summary>
    public async Task AddAsync(ReceivedNotification notification, CancellationToken cancellationToken = default)
    {
        var correlationId = notification.CorrelationId != Guid.Empty
            ? notification.CorrelationId
            : notification.Id;

        var existingEntity = await _dbContext.NotificationLogs
            .FirstOrDefaultAsync(e => e.CorrelationId == correlationId, cancellationToken);

        if (existingEntity != null)
        {
            // Single row update: Update status and ReceivedAt timestamp
            existingEntity.Status     = notification.Status;
            existingEntity.ReceivedAt = notification.ReceivedAt;
            _dbContext.NotificationLogs.Update(existingEntity);

            _logger.LogInformation(
                "[SqliteStore] Updated existing log row. CorrelationId={CorrelationId}, Status={Status}",
                correlationId,
                existingEntity.Status);
        }
        else
        {
            // Insert single row tracking sent & received event
            var newEntity = new NotificationLogEntity
            {
                CorrelationId = correlationId,
                Title         = notification.Title,
                Message       = notification.Message,
                Category      = notification.Category,
                RecipientId   = notification.RecipientId,
                Status        = notification.Status,
                SentAt        = notification.OriginallyCreatedAt,
                ReceivedAt    = notification.ReceivedAt
            };

            await _dbContext.NotificationLogs.AddAsync(newEntity, cancellationToken);

            _logger.LogInformation(
                "[SqliteStore] Inserted new log row. CorrelationId={CorrelationId}, Status={Status}",
                correlationId,
                newEntity.Status);
        }

        await _dbContext.SaveChangesAsync(cancellationToken);
    }

    public async Task<IReadOnlyList<ReceivedNotification>> GetAllAsync(CancellationToken cancellationToken = default)
    {
        var entities = await _dbContext.NotificationLogs
            .AsNoTracking()
            .ToListAsync(cancellationToken);

        return entities
            .OrderByDescending(e => e.ReceivedAt ?? e.SentAt)
            .Select(MapToDto)
            .ToList();
    }

    public async Task<ReceivedNotification?> GetByIdAsync(Guid id, CancellationToken cancellationToken = default)
    {
        var entity = await _dbContext.NotificationLogs
            .AsNoTracking()
            .FirstOrDefaultAsync(e => e.CorrelationId == id, cancellationToken);

        return entity != null ? MapToDto(entity) : null;
    }

    private static ReceivedNotification MapToDto(NotificationLogEntity entity) => new()
    {
        Id                  = entity.CorrelationId,
        CorrelationId       = entity.CorrelationId,
        Title               = entity.Title,
        Message             = entity.Message,
        Category            = entity.Category,
        RecipientId         = entity.RecipientId,
        Status              = entity.Status,
        OriginallyCreatedAt = entity.SentAt,
        ReceivedAt          = entity.ReceivedAt ?? entity.SentAt
    };
}

using Microsoft.EntityFrameworkCore;

namespace Alpha.NotificationReceiver.Data;

/// <summary>
/// EF Core DbContext for NotificationReceiver backed by SQLite.
/// </summary>
public class NotificationDbContext : DbContext
{
    public NotificationDbContext(DbContextOptions<NotificationDbContext> options)
        : base(options)
    {
    }

    /// <summary>
    /// Event tracking log table.
    /// </summary>
    public DbSet<NotificationLogEntity> NotificationLogs => Set<NotificationLogEntity>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        modelBuilder.Entity<NotificationLogEntity>(entity =>
        {
            entity.HasKey(e => e.CorrelationId);
            entity.HasIndex(e => e.Category);
            entity.HasIndex(e => e.Status);
            entity.HasIndex(e => e.SentAt);
        });
    }
}

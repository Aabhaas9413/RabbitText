using MassTransit;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.EntityFrameworkCore;
using Alpha.NotificationReceiver.Consumers;
using Alpha.NotificationReceiver.Data;
using Alpha.NotificationReceiver.Queries;
using Alpha.NotificationReceiver.Services;

var builder = WebApplication.CreateBuilder(args);

// ─── Controllers & API Explorer ────────────────────────────────────────────
builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(options =>
{
    options.SwaggerDoc("v1", new()
    {
        Title       = "Alpha – Notification Receiver API",
        Version     = "v1",
        Description = "CQRS Query-side microservice. Consumes notification events from RabbitMQ and exposes them via a read API."
    });
    var xmlFile = $"{System.Reflection.Assembly.GetExecutingAssembly().GetName().Name}.xml";
    var xmlPath = Path.Combine(AppContext.BaseDirectory, xmlFile);
    if (File.Exists(xmlPath)) options.IncludeXmlComments(xmlPath);
});

// ─── CQRS — MediatR ───────────────────────────────────────────────────────
builder.Services.AddMediatR(cfg =>
    cfg.RegisterServicesFromAssemblyContaining<GetAllNotificationsQuery>());

// ─── Database & Persistence — EF Core + SQLite ─────────────────────────────
var connectionString = builder.Configuration.GetConnectionString("DefaultConnection") ?? "Data Source=data/notifications.db";

// Ensure target directory exists for SQLite database file
var sqliteDataSource = new Microsoft.Data.Sqlite.SqliteConnectionStringBuilder(connectionString).DataSource;
var sqliteDir = Path.GetDirectoryName(sqliteDataSource);
if (!string.IsNullOrEmpty(sqliteDir) && !Directory.Exists(sqliteDir))
{
    Directory.CreateDirectory(sqliteDir);
}

builder.Services.AddDbContext<NotificationDbContext>(options =>
    options.UseSqlite(connectionString));

builder.Services.AddScoped<INotificationStore, SqliteNotificationStore>();

// ─── MassTransit + RabbitMQ ───────────────────────────────────────────────
builder.Services.AddMassTransit(x =>
{
    // Register our consumer — MassTransit will auto-create the queue
    x.AddConsumer<NotificationCreatedConsumer>();

    x.UsingRabbitMq((ctx, cfg) =>
    {
        var rabbitHost = builder.Configuration.GetValue<string>("RabbitMQ:Host") ?? "localhost";
        var rabbitUser = builder.Configuration.GetValue<string>("RabbitMQ:Username") ?? "guest";
        var rabbitPass = builder.Configuration.GetValue<string>("RabbitMQ:Password") ?? "guest";

        cfg.Host(rabbitHost, "/", h =>
        {
            h.Username(rabbitUser);
            h.Password(rabbitPass);
        });

        // Auto-configure all registered consumer endpoints
        cfg.ConfigureEndpoints(ctx);
        cfg.AutoStart = true;
    });
});

// ─── Health Checks ────────────────────────────────────────────────────────
builder.Services.AddHealthChecks();

var app = builder.Build();

// ─── Middleware Pipeline ───────────────────────────────────────────────────
// Swagger is on for local dev / Docker, and can be enabled per Azure environment
// via the Swagger__Enabled setting (true in dev, false in prod).
var swaggerEnabled = app.Environment.IsDevelopment()
    || app.Environment.IsEnvironment("Docker")
    || app.Configuration.GetValue<bool>("Swagger:Enabled");

if (swaggerEnabled)
{
    app.UseSwagger();
    app.UseSwaggerUI(c =>
    {
        c.SwaggerEndpoint("/swagger/v1/swagger.json", "Notification Receiver v1");
        c.RoutePrefix = "swagger";
    });
}

if (app.Environment.IsDevelopment())
{
    app.UseHttpsRedirection();
}
app.UseAuthorization();
app.MapControllers();
app.MapHealthChecks("/health");
// Liveness: process is up (no dependency checks, so a RabbitMQ blip doesn't trigger restarts)
app.MapHealthChecks("/health/live", new HealthCheckOptions { Predicate = _ => false });
// Readiness: includes the MassTransit bus health check registered automatically
app.MapHealthChecks("/health/ready");

// ─── Auto-Create Database Schema ──────────────────────────────────────────
using (var scope = app.Services.CreateScope())
{
    var dbContext = scope.ServiceProvider.GetRequiredService<NotificationDbContext>();
    await dbContext.Database.EnsureCreatedAsync();
}

app.Run();

using MassTransit;
using Alpha.NotificationSender.Commands;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;

var builder = WebApplication.CreateBuilder(args);

// ─── Controllers & API Explorer ────────────────────────────────────────────
builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(options =>
{
    options.SwaggerDoc("v1", new()
    {
        Title       = "Alpha – Notification Sender API",
        Version     = "v1",
        Description = "CQRS Command-side microservice. Accepts notification commands and publishes integration events to RabbitMQ."
    });
    // Include XML doc comments
    var xmlFile = $"{System.Reflection.Assembly.GetExecutingAssembly().GetName().Name}.xml";
    var xmlPath = Path.Combine(AppContext.BaseDirectory, xmlFile);
    if (File.Exists(xmlPath)) options.IncludeXmlComments(xmlPath);
});

// ─── MediatR ──────────────────────────────────────────────────────────────
// Registers all IRequestHandler<,> implementations in this assembly
builder.Services.AddMediatR(cfg =>
    cfg.RegisterServicesFromAssemblyContaining<SendNotificationCommand>());

// ─── MassTransit + RabbitMQ ───────────────────────────────────────────────
builder.Services.AddMassTransit(x =>
{
    // No consumers on the sender side — it only publishes
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

        // Let MassTransit auto-configure topology (exchanges/queues) on startup
        cfg.ConfigureEndpoints(ctx);

        // Sender has no consumers; AutoStart=true forces MassTransit to connect to
        // RabbitMQ on startup so the /health/ready check reports Healthy once connected.
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
        c.SwaggerEndpoint("/swagger/v1/swagger.json", "Notification Sender v1");
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

app.Run();

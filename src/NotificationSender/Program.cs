using MassTransit;
using Mango.NotificationSender.Commands;

var builder = WebApplication.CreateBuilder(args);

// ─── Controllers & API Explorer ────────────────────────────────────────────
builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(options =>
{
    options.SwaggerDoc("v1", new()
    {
        Title       = "Mango – Notification Sender API",
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
    });
});

// ─── Health Checks ────────────────────────────────────────────────────────
builder.Services.AddHealthChecks();

var app = builder.Build();

// ─── Middleware Pipeline ───────────────────────────────────────────────────
if (app.Environment.IsDevelopment() || app.Environment.IsEnvironment("Docker"))
{
    app.UseSwagger();
    app.UseSwaggerUI(c =>
    {
        c.SwaggerEndpoint("/swagger/v1/swagger.json", "Notification Sender v1");
        c.RoutePrefix = "swagger";
    });
}

app.UseHttpsRedirection();
app.UseAuthorization();
app.MapControllers();
app.MapHealthChecks("/health");

app.Run();

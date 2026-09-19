using MassTransit;
using Mango.NotificationReceiver.Consumers;
using Mango.NotificationReceiver.Queries;
using Mango.NotificationReceiver.Services;

var builder = WebApplication.CreateBuilder(args);

// ─── Controllers & API Explorer ────────────────────────────────────────────
builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(options =>
{
    options.SwaggerDoc("v1", new()
    {
        Title       = "Mango – Notification Receiver API",
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

// ─── Notification Store (in-memory, Singleton so state persists per process) ─
builder.Services.AddSingleton<INotificationStore, InMemoryNotificationStore>();

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
        c.SwaggerEndpoint("/swagger/v1/swagger.json", "Notification Receiver v1");
        c.RoutePrefix = "swagger";
    });
}

app.UseHttpsRedirection();
app.UseAuthorization();
app.MapControllers();
app.MapHealthChecks("/health");

app.Run();

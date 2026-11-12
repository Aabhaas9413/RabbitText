# ⚡ Alpha — CQRS Notification Platform (RabbitMQ & Kafka)

A production-grade **CQRS microservices** architecture built on **.NET 9**, **MediatR**, **MassTransit**, **RabbitMQ**, and **Apache Kafka**. Two independent microservices communicate asynchronously through a pluggable message broker (**RabbitMQ** or **Kafka**, selectable via a feature flag in Bicep, Azure DevOps Pipelines, or environment variables), fully containerised with Docker Compose and deployed to **Azure Container Apps**.

---

## 📐 Architecture Overview

```
┌────────────────────────────────────────────────────────────────┐
│                        Client / API Consumer                    │
└───────────────────────────┬────────────────────────────────────┘
                            │ POST /api/notifications
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│          NotificationSender  (Command Side — Port 5001)          │
│                                                                   │
│  HTTP → Controller → MediatR → SendNotificationCommandHandler    │
│                                       │                          │
│                                       ▼                          │
│                     INotificationEventPublisher                  │
│             (selected via Messaging__Provider feature flag)      │
└────────────────────┬────────────────────────────────┬────────────┘
                     │ RabbitMQ                       │ Kafka
                     ▼                                ▼
       ┌──────────────────────────┐     ┌──────────────────────────┐
       │     RabbitMQ Broker      │     │   Apache Kafka (KRaft)   │
       │  Exchange: Notification- │     │  Topic: notification-    │
       │  CreatedEvent (AMQP)     │     │  created (Port 9092)     │
       └─────────────┬────────────┘     └─────────────┬────────────┘
                     └──────────────┬─────────────────┘
                                    │ MassTransit Consume
                                    ▼
┌─────────────────────────────────────────────────────────────────┐
│         NotificationReceiver  (Query Side — Port 5002)           │
│                                                                   │
│  NotificationCreatedConsumer → INotificationStore (EF + SQLite)   │
│                                                                   │
│  GET /api/notifications → MediatR → GetAllNotificationsHandler   │
└──────────────────────────────────────────────────────────────────┘
```

### CQRS Split

| Concept | NotificationSender | NotificationReceiver |
|---|---|---|
| **Pattern** | Command side | Query side |
| **Accepts** | `POST /api/notifications` | `GET /api/notifications` |
| **MediatR** | `ICommand<Guid>` | `IQuery<IReadOnlyList<...>>` |
| **Broker role** | Publisher (`INotificationEventPublisher`) | Consumer (`NotificationCreatedConsumer`) |
| **Supported Brokers** | **RabbitMQ** (`IPublishEndpoint`) or **Kafka** (`ITopicProducer<T>`) | **RabbitMQ** queue or **Kafka** topic (`MassTransit.Kafka`) |
| **State** | Stateless | EF Core + SQLite persistent log |

---

## 🛠️ Prerequisites

| Tool | Minimum version | Install |
|---|---|---|
| [.NET SDK](https://dotnet.microsoft.com/download) | 9.0 | `winget install Microsoft.DotNet.SDK.9` |
| [Docker Desktop](https://www.docker.com/products/docker-desktop/) | 4.x | [Download](https://www.docker.com/products/docker-desktop/) |
| [Git](https://git-scm.com/) | 2.x | `winget install Git.Git` |

> **Note**: Docker Desktop includes Docker Compose v2. Both RabbitMQ and Apache Kafka (KRaft) run inside Docker.

---

## 🐳 Option A — Local Docker Setup (Recommended)

Everything — RabbitMQ, Kafka (KRaft), and both microservices — is configured in [`docker-compose.yml`](docker-compose.yml).

### 1. Clone the repository

```bash
git clone <your-repo-url>
cd testDotNet
```

### 2. Start the full stack (RabbitMQ or Kafka)

**Mode 1 — RabbitMQ (default):**
```powershell
docker-compose up --build
```

**Mode 2 — Apache Kafka (via feature flag):**
```powershell
$env:MESSAGING_PROVIDER="Kafka"; docker-compose up --build
```

### 3. Verify everything is running

```bash
docker-compose ps
```

```
NAME                          STATUS      PORTS
alpha-rabbitmq                healthy     0.0.0.0:5672->5672, 0.0.0.0:15672->15672
alpha-kafka                   running     0.0.0.0:9092->9092
alpha-notification-sender     healthy     0.0.0.0:5001->8080
alpha-notification-receiver   healthy     0.0.0.0:5002->8080
```

### 4. Access the services

| Service | URL | Description |
|---|---|---|
| NotificationSender API | http://localhost:5001/swagger | Swagger UI (Command side — shows active broker) |
| NotificationReceiver API | http://localhost:5002/swagger | Swagger UI (Query side — shows active broker) |
| **RabbitMQ Management UI** | **http://localhost:15672** | Queues, exchanges, message rates (`guest` / `guest`) |
| Sender readiness check | http://localhost:5001/health/ready | Returns `Healthy` |
| Receiver readiness check | http://localhost:5002/health/ready | Returns `Healthy` |

### 5. Send your first notification

Using **curl**:
```bash
curl -X POST http://localhost:5001/api/notifications \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Hello from CQRS!",
    "message": "This notification travelled through the configured broker.",
    "category": "Demo",
    "recipientId": "user-001"
  }'
```

Expected response (`202 Accepted`):
```json
{
  "notificationId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
  "status": "Queued",
  "queuedAt": "2026-09-14T22:00:00Z"
}
```

### 6. Read the notification back

```bash
curl http://localhost:5002/api/notifications
```

You'll see the notification the Receiver consumed from RabbitMQ or Kafka:
```json
[
  {
    "id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
    "correlationId": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
    "title": "Hello from CQRS!",
    "message": "This notification travelled through the configured broker.",
    "category": "Demo",
    "recipientId": "user-001",
    "status": "Received",
    "receivedAt": "2026-09-14T22:00:01Z",
    "originallyCreatedAt": "2026-09-14T22:00:00Z"
  }
]
```

### 7. Inspect the SQLite Database

To view the raw persistent SQLite database rows stored inside Docker:

**Option A — Via VS Code (Live Sync)**:
1. Install the **[SQLite Viewer](https://marketplace.visualstudio.com/items?itemName=qwtel.sqlite-viewer)** extension in VS Code.
2. Click `data/receiver/notifications.db` directly in your VS Code file explorer.
3. Click the **Refresh** button inside SQLite Viewer to see new rows appear as events are sent!

**Option B — Via REST API / Browser**:
Open [http://localhost:5002/api/notifications](http://localhost:5002/api/notifications) or [http://localhost:5002/swagger](http://localhost:5002/swagger) to see all database records formatted as JSON.

### 8. Stop the stack

```bash
docker-compose down          # Stop containers, preserve volumes & SQLite database
docker-compose down -v       # Stop containers AND delete RabbitMQ/SQLite volumes
```

---

## 💻 Option B — Run Brokers via Docker, Run .NET Services Locally

Useful when you want Docker for RabbitMQ/Kafka but prefer to debug the .NET microservices in Visual Studio or via `dotnet run`.

```bash
# Start RabbitMQ (or Kafka) in Docker
docker-compose up rabbitmq kafka
```

Then in two terminals:
```bash
# Terminal 1 — Notification Sender
cd src/NotificationSender
dotnet run

# Terminal 2 — Notification Receiver
cd src/NotificationReceiver
dotnet run
```

To switch local `dotnet run` to **Kafka**, set `"Provider": "Kafka"` under `"Messaging"` in `appsettings.json` (or set `$env:Messaging__Provider="Kafka"`).

---

## 🚀 Kubernetes Deployment

### Deploy

```bash
# 1. Create the namespace and Receiver deployment
kubectl apply -f k8s/receiver-deployment.yaml

# 2. Deploy RabbitMQ
kubectl apply -f k8s/rabbitmq-deployment.yaml

# 3. Wait for RabbitMQ to be ready
kubectl rollout status statefulset/rabbitmq -n alpha

# 4. Deploy microservices
kubectl apply -f k8s/sender-deployment.yaml
kubectl apply -f k8s/receiver-deployment.yaml

# 5. Verify
kubectl get pods -n alpha
kubectl get services -n alpha
```

---

## ☁️ Azure Deployment (Bicep + Azure DevOps + Broker Feature Flag)

Deploy to Azure across **dev** and **prod** environments using Azure Pipelines and Bicep, with a per-environment **feature flag** (`messagingProvider`: `RabbitMQ` or `Kafka`).

For the comprehensive step-by-step setup guide, resource inventory, and minimal-cost breakdown, see [`docs/AZURE_DEPLOYMENT.md`](docs/AZURE_DEPLOYMENT.md).

### Switching Between RabbitMQ and Kafka in Azure

1. **In Azure DevOps UI (Per-Run Dropdown)**:
   - Go to **Pipelines → select your pipeline → Run pipeline**.
   - Choose **`RabbitMQ`** or **`Kafka`** from the **Dev Messaging Provider (Feature Flag)** and **Prod Messaging Provider (Feature Flag)** dropdowns.
   - Bicep provisions **only** the selected broker (`alpha-rabbitmq-{env}` or `alpha-kafka-{env}`), injects `Messaging__Provider` into both microservices, and automatically deletes the unselected broker container app so you never pay for both.
2. **In Bicep Directly**:
   ```bash
   az deployment group create \
     --resource-group alpha-rg-dev \
     --template-file infra/bicep/main.bicep \
     --parameters environmentName=dev messagingProvider=Kafka ...
   ```

### Quick Automated Azure DevOps Setup

Run [`scripts/setup-azure-devops.ps1`](scripts/setup-azure-devops.ps1) to register Azure resource providers, push to Azure Repos, and create the `alpha-dev` & `alpha-prod` variable groups, environments, and pipeline automatically:

```powershell
az login
.\scripts\setup-azure-devops.ps1 `
  -OrganizationUrl "https://dev.azure.com/<your-org>" `
  -ProjectName "<your-project>" `
  -RepoName "<your-repo>" `
  -SubscriptionId "<your-azure-subscription-id>"
```

Then in Azure DevOps:
1. **Project Settings → Service Connections**: Create an Azure Resource Manager (Workload Identity Federation) connection named `alpha-azure` at **Subscription** scope.
2. **Pipelines → Environments → `alpha-prod`**: Add an **Approval check** for manual production gating, then run the pipeline (`azure-pipelines.yml`).

---

## 📁 Project Structure

```
testDotNet/
├── azure-pipelines.yml               # Multi-stage CI/CD pipeline (with RabbitMQ/Kafka feature flag)
├── pipelines/
│   └── templates/
│       └── deploy-environment.yml    # Reusable deploy + E2E smoke test template
├── scripts/
│   └── setup-azure-devops.ps1        # One-shot Azure & Azure DevOps setup script
├── docs/
│   └── AZURE_DEPLOYMENT.md           # Detailed Azure & Azure DevOps setup guide
├── src/
│   ├── Shared/Alpha.Shared/          # Shared contracts (events, CQRS abstractions)
│   │   ├── Abstractions/             # ICommand<T>, IQuery<T>
│   │   └── Events/                   # NotificationCreatedEvent
│   ├── NotificationSender/           # Command-side microservice (Port 5001)
│   │   ├── Commands/                 # SendNotificationCommand + Handler
│   │   ├── Messaging/                # INotificationEventPublisher (RabbitMQ & Kafka impls)
│   │   └── Controllers/              # POST /api/notifications
│   └── NotificationReceiver/         # Query-side microservice (Port 5002)
│       ├── Consumers/                # MassTransit consumer (works with RabbitMQ & Kafka)
│       ├── Data/                     # EF Core DbContext & NotificationLogEntity
│       ├── Queries/                  # GetNotificationsQuery + Handlers
│       ├── Services/                 # INotificationStore + SQLite impl (SqliteNotificationStore)
│       └── Controllers/              # GET /api/notifications
├── k8s/                              # Kubernetes manifests
├── infra/
│   └── bicep/                        # Azure infrastructure as code
│       ├── shared.bicep              # Shared ACR registry
│       ├── main.bicep                # Per-environment stack (dev/prod + messagingProvider flag)
│       └── modules/
│           ├── containerRegistry.bicep
│           ├── network.bicep         # VNet required for internal TCP ingress (5672 / 9092)
│           └── containerApps.bicep   # ACA environment, RabbitMQ/Kafka broker & apps
├── docker-compose.yml                # Full stack orchestration (RabbitMQ + Kafka)
└── docker-compose.override.yml       # Local dev overrides
```

---

## 🔧 Configuration

All configuration is driven by environment variables, which override `appsettings.json`:

| Variable | Default | Description |
|---|---|---|
| `Messaging__Provider` | `RabbitMQ` | **Feature flag**: `RabbitMQ` or `Kafka` |
| `RabbitMQ__Host` | `localhost` | RabbitMQ hostname (used when `Messaging__Provider=RabbitMQ`) |
| `RabbitMQ__Username` | `guest` | RabbitMQ username |
| `RabbitMQ__Password` | `guest` | RabbitMQ password |
| `Kafka__BootstrapServers` | `localhost:9092` | Kafka bootstrap servers (used when `Messaging__Provider=Kafka`) |
| `Kafka__Topic` | `notification-created` | Kafka topic name for notification events |
| `Kafka__GroupId` | `alpha-notification-receiver` | Kafka consumer group ID on the Receiver |
| `Swagger__Enabled` | `false` (`true` in dev) | Enables Swagger UI in non-Development environments |
| `ASPNETCORE_ENVIRONMENT` | `Development` | Runtime environment (`Development`, `Docker`, `Production`) |
| `ASPNETCORE_HTTP_PORTS` | `8080` | HTTP port inside the container |

> ℹ️ Docker and Azure Container Apps use `__` (double underscore) to separate nested config sections, which ASP.NET Core automatically maps to `:` in the config hierarchy.

---

## 🧩 Key Technologies

| Technology | Role |
|---|---|
| **ASP.NET Core 9** | Web API framework for both microservices |
| **EF Core 9 + SQLite** | Persistent event logger with Correlation ID tracking |
| **MediatR 12** | In-process CQRS command/query dispatch |
| **MassTransit 8 + Kafka Rider** | Unified messaging abstraction over RabbitMQ and Apache Kafka |
| **RabbitMQ 3.13** | AMQP message broker option (`Messaging__Provider=RabbitMQ`) |
| **Apache Kafka 3.8 (KRaft)** | Event streaming broker option (`Messaging__Provider=Kafka`, ZooKeeper-less) |
| **Docker Compose** | Local multi-service orchestration |
| **Bicep** | Azure infrastructure as code with conditional broker deployment |
| **Azure Container Apps** | Serverless container hosting target |
| **Azure DevOps** | Multi-stage CI/CD pipeline (`dev` + `prod`) |

---

## 🔮 Next Steps

- [x] **Add EF Core + SQLite** to `NotificationReceiver` for persistent storage with Correlation ID tracking
- [x] **Wire up Azure DevOps** multi-stage CI/CD pipeline (`dev` + `prod`) and Bicep IaC
- [x] **Add generic RabbitMQ / Kafka feature flag** across microservices, Bicep, and Azure Pipelines
- [ ] **Add unit tests** for command/query handlers with xUnit + Moq
- [ ] **Add integration tests** using MassTransit's `InMemoryTestHarness`
- [ ] **Add more notification types** (Email, SMS, Push) as additional events
- [ ] **Replace SQLite store** with Azure SQL / PostgreSQL to scale Receiver to multiple replicas

# 🐇 Mango — CQRS Notification Platform

A production-grade **CQRS microservices** architecture built on **.NET 9**, **MediatR**, **MassTransit**, and **RabbitMQ**. Two independent microservices communicate asynchronously through RabbitMQ, fully containerised with Docker Compose and ready for Kubernetes and Azure Container Apps.

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
│                                       │ IPublishEndpoint.Publish │
└───────────────────────────────────────┼──────────────────────────┘
                                        │
                                        ▼
                          ┌─────────────────────────┐
                          │      RabbitMQ Broker      │
                          │  Exchange: notification-  │
                          │  created-event            │
                          └────────────┬──────────────┘
                                       │ AMQP consume
                                       ▼
┌─────────────────────────────────────────────────────────────────┐
│         NotificationReceiver  (Query Side — Port 5002)           │
│                                                                   │
│  MassTransit Consumer → INotificationStore (in-memory)           │
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
| **RabbitMQ role** | Publisher | Consumer |
| **State** | Stateless | In-memory store |

---

## 🛠️ Prerequisites

| Tool | Minimum version | Install |
|---|---|---|
| [.NET SDK](https://dotnet.microsoft.com/download) | 9.0 | `winget install Microsoft.DotNet.SDK.9` |
| [Docker Desktop](https://www.docker.com/products/docker-desktop/) | 4.x | [Download](https://www.docker.com/products/docker-desktop/) |
| [Git](https://git-scm.com/) | 2.x | `winget install Git.Git` |

> **Note**: Docker Desktop includes Docker Compose v2. You do **not** need to install RabbitMQ separately — it runs inside Docker.

---

## 🐇 Option A — Local Docker Setup (Recommended)

This is the easiest way to run the full stack. Everything — RabbitMQ, both microservices — starts with one command.

### 1. Clone the repository

```bash
git clone <your-repo-url>
cd testDotNet
```

### 2. Start the full stack

```bash
docker-compose up --build
```

This will:
- Pull the `rabbitmq:3.13-management` image
- Build both microservice images
- Start RabbitMQ (with health checks) then the two services

**First run takes ~2–3 minutes** while Docker pulls base images and compiles .NET projects.

### 3. Verify everything is running

```bash
docker-compose ps
```

You should see all three containers as `healthy`:

```
NAME                        STATUS      PORTS
mango-rabbitmq              healthy     0.0.0.0:5672->5672, 0.0.0.0:15672->15672
mango-notification-sender   healthy     0.0.0.0:5001->8080
mango-notification-receiver healthy     0.0.0.0:5002->8080
```

### 4. Access the services

| Service | URL | Description |
|---|---|---|
| NotificationSender API | http://localhost:5001/swagger | Swagger UI (Command side) |
| NotificationReceiver API | http://localhost:5002/swagger | Swagger UI (Query side) |
| **RabbitMQ Management UI** | **http://localhost:15672** | Queues, exchanges, message rates |
| Sender health check | http://localhost:5001/health | Returns `Healthy` |
| Receiver health check | http://localhost:5002/health | Returns `Healthy` |

> **RabbitMQ credentials**: `guest` / `guest`

### 5. Send your first notification

Using **curl**:
```bash
curl -X POST http://localhost:5001/api/notifications \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Hello from CQRS!",
    "message": "This notification travelled through RabbitMQ.",
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

You'll see the notification the Receiver consumed from RabbitMQ:
```json
[
  {
    "id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
    "title": "Hello from CQRS!",
    "message": "This notification travelled through RabbitMQ.",
    "category": "Demo",
    "recipientId": "user-001",
    "receivedAt": "2026-09-14T22:00:01Z",
    "originallyCreatedAt": "2026-09-14T22:00:00Z"
  }
]
```

### 7. Stop the stack

```bash
docker-compose down          # Stop containers, preserve volumes
docker-compose down -v       # Stop containers AND delete RabbitMQ data
```

---

## 🐇 Option B — Install RabbitMQ Directly (Windows)

If you prefer to run RabbitMQ natively (without Docker) and run the .NET services from Visual Studio or the CLI:

### Step 1: Install Erlang (RabbitMQ dependency)

1. Download **Erlang/OTP 26** from https://www.erlang.org/downloads
2. Run the installer as Administrator
3. Verify: `erl -eval 'erlang:display(erlang:system_info(otp_release)), halt().' -noshell`

### Step 2: Install RabbitMQ

1. Download the **RabbitMQ Windows installer** from https://www.rabbitmq.com/install-windows.html
2. Run the installer (it installs as a Windows Service automatically)
3. Verify the service is running:
   ```powershell
   Get-Service -Name RabbitMQ
   ```

### Step 3: Enable the Management Plugin

Open a command prompt **as Administrator**:
```cmd
"C:\Program Files\RabbitMQ Server\rabbitmq_server-3.13.x\sbin\rabbitmq-plugins.bat" enable rabbitmq_management
```

Then restart the service:
```powershell
Restart-Service RabbitMQ
```

Access the management UI at: **http://localhost:15672** (guest / guest)

### Step 4: Run the microservices locally

```bash
# Terminal 1 — Notification Sender
cd src/NotificationSender
dotnet run

# Terminal 2 — Notification Receiver
cd src/NotificationReceiver
dotnet run
```

Both services default to `localhost` for RabbitMQ (configured in `appsettings.Development.json`).

---

## 🐇 Option C — RabbitMQ via Docker only (services run locally)

Useful when you want Docker for RabbitMQ but prefer to debug .NET services in Visual Studio.

```bash
# Start only RabbitMQ
docker-compose up rabbitmq
```

Then run the two services from Visual Studio or the CLI as in Option B Step 4.

---

## 🚀 Kubernetes Deployment

### Prerequisites
- [kubectl](https://kubernetes.io/docs/tasks/tools/) configured for your cluster
- [Docker Desktop Kubernetes](https://docs.docker.com/desktop/kubernetes/) or a cloud cluster (AKS, EKS, GKE)

### Deploy

```bash
# 1. Create the namespace first
kubectl apply -f k8s/receiver-deployment.yaml  # Contains the Namespace definition

# 2. Deploy RabbitMQ
kubectl apply -f k8s/rabbitmq-deployment.yaml

# 3. Wait for RabbitMQ to be ready
kubectl rollout status statefulset/rabbitmq -n mango

# 4. Deploy microservices
kubectl apply -f k8s/sender-deployment.yaml
kubectl apply -f k8s/receiver-deployment.yaml

# 5. Verify
kubectl get pods -n mango
kubectl get services -n mango
```

### Port-forward for local testing

```bash
# Sender
kubectl port-forward service/notification-sender 5001:80 -n mango

# Receiver
kubectl port-forward service/notification-receiver 5002:80 -n mango

# RabbitMQ Management UI
kubectl port-forward service/rabbitmq 15672:15672 -n mango
```

---

## ☁️ Azure Deployment (Bicep)

### Prerequisites
- Azure CLI: `winget install Microsoft.AzureCLI`
- Logged in: `az login`
- Resource group created: `az group create --name mango-rg-dev --location uksouth`

### Deploy infrastructure

```bash
cd infra/bicep

az deployment group create \
  --resource-group mango-rg-dev \
  --template-file main.bicep \
  --parameters environment=dev imageTag=latest
```

### Azure DevOps Pipeline

1. Import `infra/azure-pipelines.yml` into your Azure DevOps project
2. Set up **Service Connections** in Project Settings:
   - `mango-acr-connection` — Docker Registry connection to your ACR
   - `mango-azure-subscription` — Azure Resource Manager connection
3. Update `acrLoginServer` and `resourceGroup` variables in the pipeline file
4. Create **Environments** named `mango-dev` and `mango-prod` with approval gates for production

---

## 📁 Project Structure

```
testDotNet/
├── src/
│   ├── Shared/Mango.Shared/          # Shared contracts (events, CQRS abstractions)
│   │   ├── Abstractions/             # ICommand<T>, IQuery<T>
│   │   └── Events/                   # NotificationCreatedEvent
│   ├── NotificationSender/           # Command-side microservice (Port 5001)
│   │   ├── Commands/                 # SendNotificationCommand + Handler
│   │   └── Controllers/              # POST /api/notifications
│   └── NotificationReceiver/         # Query-side microservice (Port 5002)
│       ├── Consumers/                # MassTransit RabbitMQ consumer
│       ├── Queries/                  # GetNotificationsQuery + Handlers
│       ├── Services/                 # INotificationStore + in-memory impl
│       └── Controllers/              # GET /api/notifications
├── k8s/                              # Kubernetes manifests
├── infra/
│   ├── azure-pipelines.yml           # Azure DevOps CI/CD pipeline
│   └── bicep/                        # Azure infrastructure as code
│       ├── main.bicep
│       └── modules/
│           ├── containerRegistry.bicep
│           └── containerApps.bicep
├── docker-compose.yml                # Full stack orchestration
└── docker-compose.override.yml       # Local dev overrides
```

---

## 🔧 Configuration

All configuration is driven by environment variables, which override `appsettings.json`:

| Variable | Default | Description |
|---|---|---|
| `RabbitMQ__Host` | `localhost` | RabbitMQ hostname |
| `RabbitMQ__Username` | `guest` | RabbitMQ username |
| `RabbitMQ__Password` | `guest` | RabbitMQ password |
| `ASPNETCORE_ENVIRONMENT` | `Development` | Controls Swagger visibility |
| `ASPNETCORE_HTTP_PORTS` | `8080` | HTTP port inside the container |

> ℹ️ Docker uses `__` (double underscore) to separate nested config sections, which ASP.NET Core automatically maps to `:` in the config hierarchy.

---

## 🧩 Key Technologies

| Technology | Role |
|---|---|
| **ASP.NET Core 9** | Web API framework for both microservices |
| **MediatR 12** | In-process CQRS command/query dispatch |
| **MassTransit 8** | RabbitMQ abstraction — consumers, publishers, retries |
| **RabbitMQ 3.13** | Message broker for inter-service communication |
| **Docker Compose** | Local multi-service orchestration |
| **Kubernetes** | Production container orchestration |
| **Bicep** | Azure infrastructure as code |
| **Azure Container Apps** | Serverless container hosting target |
| **Azure DevOps** | CI/CD pipeline |

---

## 🔮 Next Steps

- [ ] **Add EF Core + SQLite** to `NotificationReceiver` for persistent storage
- [ ] **Add unit tests** for command/query handlers with xUnit + Moq
- [ ] **Add integration tests** using MassTransit's `InMemoryTestHarness`
- [ ] **Wire up Azure DevOps** service connections and run the pipeline
- [ ] **Add more notification types** (Email, SMS, Push) as additional events
- [ ] **Add a Saga** for multi-step notification workflows (e.g. send → track → confirm)
- [ ] **Replace in-memory store** with SQL Server and scale Receiver to multiple replicas

# ──────────────────────────────────────────────────────────────────────────────
# Stage 1: Build
# ──────────────────────────────────────────────────────────────────────────────
FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src

# Copy project files first to leverage Docker layer caching for NuGet restore
COPY ["src/Shared/Mango.Shared/Mango.Shared.csproj",                         "src/Shared/Mango.Shared/"]
COPY ["src/NotificationSender/Mango.NotificationSender.csproj",               "src/NotificationSender/"]

RUN dotnet restore "src/NotificationSender/Mango.NotificationSender.csproj"

# Copy full source
COPY . .

WORKDIR "/src/src/NotificationSender"
RUN dotnet build "Mango.NotificationSender.csproj" -c Release -o /app/build

# ──────────────────────────────────────────────────────────────────────────────
# Stage 2: Publish
# ──────────────────────────────────────────────────────────────────────────────
FROM build AS publish
RUN dotnet publish "Mango.NotificationSender.csproj" -c Release -o /app/publish \
    /p:UseAppHost=false \
    /p:GenerateDocumentationFile=true

# ──────────────────────────────────────────────────────────────────────────────
# Stage 3: Runtime
# ──────────────────────────────────────────────────────────────────────────────
FROM mcr.microsoft.com/dotnet/aspnet:9.0 AS final
WORKDIR /app

# Create a non-root user for security
RUN addgroup --system appgroup && adduser --system --ingroup appgroup appuser
USER appuser

EXPOSE 8080
EXPOSE 8081

COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "Mango.NotificationSender.dll"]

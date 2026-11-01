# ──────────────────────────────────────────────────────────────────────────────
# Stage 1: Build
# ──────────────────────────────────────────────────────────────────────────────
FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src

COPY ["src/Shared/Alpha.Shared/Alpha.Shared.csproj",                         "src/Shared/Alpha.Shared/"]
COPY ["src/NotificationReceiver/Alpha.NotificationReceiver.csproj",           "src/NotificationReceiver/"]

RUN dotnet restore "src/NotificationReceiver/Alpha.NotificationReceiver.csproj"

COPY . .

WORKDIR "/src/src/NotificationReceiver"
RUN dotnet build "Alpha.NotificationReceiver.csproj" -c Release -o /app/build

# ──────────────────────────────────────────────────────────────────────────────
# Stage 2: Publish
# ──────────────────────────────────────────────────────────────────────────────
FROM build AS publish
RUN dotnet publish "Alpha.NotificationReceiver.csproj" -c Release -o /app/publish \
    /p:UseAppHost=false \
    /p:GenerateDocumentationFile=true

# ──────────────────────────────────────────────────────────────────────────────
# Stage 3: Runtime
# ──────────────────────────────────────────────────────────────────────────────
FROM mcr.microsoft.com/dotnet/aspnet:9.0 AS final
WORKDIR /app

RUN mkdir -p /app/data && addgroup --system appgroup && adduser --system --ingroup appgroup appuser && chown -R appuser:appgroup /app/data
USER appuser

EXPOSE 8080
EXPOSE 8081

COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "Alpha.NotificationReceiver.dll"]

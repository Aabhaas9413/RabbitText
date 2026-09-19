# ──────────────────────────────────────────────────────────────────────────────
# Stage 1: Build
# ──────────────────────────────────────────────────────────────────────────────
FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src

COPY ["src/Shared/Mango.Shared/Mango.Shared.csproj",                         "src/Shared/Mango.Shared/"]
COPY ["src/NotificationReceiver/Mango.NotificationReceiver.csproj",           "src/NotificationReceiver/"]

RUN dotnet restore "src/NotificationReceiver/Mango.NotificationReceiver.csproj"

COPY . .

WORKDIR "/src/src/NotificationReceiver"
RUN dotnet build "Mango.NotificationReceiver.csproj" -c Release -o /app/build

# ──────────────────────────────────────────────────────────────────────────────
# Stage 2: Publish
# ──────────────────────────────────────────────────────────────────────────────
FROM build AS publish
RUN dotnet publish "Mango.NotificationReceiver.csproj" -c Release -o /app/publish \
    /p:UseAppHost=false \
    /p:GenerateDocumentationFile=true

# ──────────────────────────────────────────────────────────────────────────────
# Stage 3: Runtime
# ──────────────────────────────────────────────────────────────────────────────
FROM mcr.microsoft.com/dotnet/aspnet:9.0 AS final
WORKDIR /app

RUN addgroup --system appgroup && adduser --system --ingroup appgroup appuser
USER appuser

EXPOSE 8080
EXPOSE 8081

COPY --from=publish /app/publish .
ENTRYPOINT ["dotnet", "Mango.NotificationReceiver.dll"]

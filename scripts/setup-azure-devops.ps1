<#
.SYNOPSIS
    One-shot automation script to configure Azure and Azure DevOps for Mango (dev + prod).

.DESCRIPTION
    Automates all one-time setup steps described in docs/AZURE_DEPLOYMENT.md:
      1. Registers required Azure Resource Providers on your subscription
      2. Adds the Azure Repos Git remote ('azure') and pushes the 'main' branch
      3. Creates/updates 'mango-dev' and 'mango-prod' Variable Groups with secret RABBITMQ_PASSWORD
      4. Creates 'mango-dev' and 'mango-prod' Environments in Azure DevOps
      5. Creates the 'Mango-CI-CD' pipeline from /azure-pipelines.yml

.EXAMPLE
    .\scripts\setup-azure-devops.ps1 `
        -OrganizationUrl "https://dev.azure.com/my-org" `
        -ProjectName "my-project" `
        -RepoName "my-repo" `
        -SubscriptionId "<azure-subscription-guid>"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Azure DevOps Organization URL, e.g. https://dev.azure.com/your-org")]
    [string]$OrganizationUrl,

    [Parameter(Mandatory = $true, HelpMessage = "Azure DevOps Project name")]
    [string]$ProjectName,

    [Parameter(Mandatory = $false, HelpMessage = "Azure Repos Git repository name (defaults to ProjectName)")]
    [string]$RepoName = $ProjectName,

    [Parameter(Mandatory = $true, HelpMessage = "Azure Subscription ID (GUID)")]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false, HelpMessage = "Pipeline name to create in Azure DevOps")]
    [string]$PipelineName = "Mango-CI-CD"
)

$ErrorActionPreference = "Stop"

function New-RandomPassword {
    param([int]$Length = 24)
    $chars = (48..57) + (65..90) + (97..122)
    -join (1..$Length | ForEach-Object { [char]($chars | Get-Random) })
}

Write-Host "`n=== 1. Azure CLI Login & Resource Providers ===" -ForegroundColor Cyan
az account set --subscription $SubscriptionId
$providers = @(
    "Microsoft.App",
    "Microsoft.ContainerRegistry",
    "Microsoft.OperationalInsights",
    "Microsoft.Network"
)
foreach ($rp in $providers) {
    Write-Host "Registering provider $rp..."
    az provider register --namespace $rp --output none
}

Write-Host "`n=== 2. Installing/Configuring Azure DevOps CLI Extension ===" -ForegroundColor Cyan
az extension add --name azure-devops --upgrade --yes 2>$null
az devops configure --defaults organization=$OrganizationUrl project="$ProjectName"

Write-Host "`n=== 3. Pushing Repository to Azure Repos ===" -ForegroundColor Cyan
$encodedProject = [uri]::EscapeDataString($ProjectName)
$encodedRepo    = [uri]::EscapeDataString($RepoName)
$orgTrimmed     = $OrganizationUrl.TrimEnd('/')
$azureRepoUrl   = "$orgTrimmed/$encodedProject/_git/$encodedRepo"

$existingRemotes = git remote
if ($existingRemotes -contains "azure") {
    git remote set-url azure $azureRepoUrl
} else {
    git remote add azure $azureRepoUrl
}
Write-Host "Pushing 'main' to $azureRepoUrl ..."
git push -u azure main

Write-Host "`n=== 4. Creating Variable Groups (mango-dev & mango-prod) ===" -ForegroundColor Cyan
foreach ($envName in @("dev", "prod")) {
    $vgName = "mango-$envName"
    $existingVgId = az pipelines variable-group list --group-name $vgName --query "[0].id" -o tsv
    $password = New-RandomPassword -Length 24

    if ([string]::IsNullOrWhiteSpace($existingVgId)) {
        Write-Host "Creating variable group '$vgName' with secret RABBITMQ_PASSWORD..."
        # Create group with a placeholder then convert to secret variable
        $vgId = az pipelines variable-group create `
            --name $vgName `
            --description "Secrets for Mango $envName environment" `
            --authorize true `
            --variables INIT_PLACEHOLDER=true `
            --query id -o tsv

        az pipelines variable-group variable create `
            --group-id $vgId `
            --name RABBITMQ_PASSWORD `
            --secret true `
            --value $password | Out-Null

        az pipelines variable-group variable delete `
            --group-id $vgId `
            --name INIT_PLACEHOLDER `
            --yes | Out-Null
    } else {
        Write-Host "Variable group '$vgName' already exists (ID: $existingVgId) — skipping."
    }
}

Write-Host "`n=== 5. Creating Azure DevOps Environments (mango-dev & mango-prod) ===" -ForegroundColor Cyan
# 499b84ac-1321-427f-aa17-267ca6975798 is the standard Azure DevOps Entra resource ID
$adoResource = "499b84ac-1321-427f-aa17-267ca6975798"
$existingEnvs = az rest `
    --method get `
    --uri "$orgTrimmed/$encodedProject/_apis/distributedtask/environments?api-version=7.1-preview.1" `
    --resource $adoResource `
    --query "value[].name" -o tsv

foreach ($adoEnv in @("mango-dev", "mango-prod")) {
    if ($existingEnvs -contains $adoEnv) {
        Write-Host "Environment '$adoEnv' already exists — skipping."
    } else {
        Write-Host "Creating environment '$adoEnv'..."
        $body = @{ name = $adoEnv; description = "Mango $adoEnv environment" } | ConvertTo-Json -Compress
        az rest `
            --method post `
            --uri "$orgTrimmed/$encodedProject/_apis/distributedtask/environments?api-version=7.1-preview.1" `
            --resource $adoResource `
            --headers "Content-Type=application/json" `
            --body $body | Out-Null
    }
}

Write-Host "`n=== 6. Creating Azure Pipeline '$PipelineName' ===" -ForegroundColor Cyan
$existingPipelineId = az pipelines list --name $PipelineName --query "[0].id" -o tsv
if ([string]::IsNullOrWhiteSpace($existingPipelineId)) {
    az pipelines create `
        --name $PipelineName `
        --description "Mango CQRS CI/CD (Build -> Dev -> Prod)" `
        --repository $RepoName `
        --repository-type tfsgit `
        --branch main `
        --yaml-path /azure-pipelines.yml `
        --skip-first-run | Out-Null
    Write-Host "Pipeline '$PipelineName' created." -ForegroundColor Green
} else {
    Write-Host "Pipeline '$PipelineName' already exists (ID: $existingPipelineId)."
}

Write-Host "`n=== Setup Complete! ===" -ForegroundColor Green
Write-Host "Remaining 2 manual checks in Azure DevOps UI (takes ~60 seconds):" -ForegroundColor Yellow
Write-Host "  1. Project Settings -> Service connections -> New service connection -> Azure Resource Manager"
Write-Host "     -> Workload identity federation (automatic) -> Scope: Subscription -> Name: 'mango-azure'"
Write-Host "     -> Check 'Grant access permission to all pipelines'."
Write-Host "  2. Pipelines -> Environments -> 'mango-prod' -> Approvals and checks -> + -> Approvals"
Write-Host "     -> Add yourself as approver, then run the '$PipelineName' pipeline!"


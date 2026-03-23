<#
.SYNOPSIS
    List Azure OpenAI models and their Responses API support.

.DESCRIPTION
    Queries the Azure Cognitive Services Management API (ARM) to get model capabilities
    per region, then displays a compatibility matrix.

.PARAMETER Subscription
    Azure subscription ID. Can also set AZURE_SUBSCRIPTION_ID env var.

.PARAMETER Location
    Azure region. Defaults to eastus2.

.PARAMETER Tenant
    Tenant ID for cross-tenant auth.

.PARAMETER All
    Show all OpenAI models (default: only Responses-capable).

.PARAMETER Filter
    Comma-separated model name prefixes to include.

.PARAMETER AsJson
    Output as JSON.

.EXAMPLE
    .\Get-ModelCompatibility.ps1 -Subscription SUB_ID -Location eastus2
    .\Get-ModelCompatibility.ps1 -Subscription SUB_ID -Location eastus2 -Filter gpt-4o,gpt-5
    .\Get-ModelCompatibility.ps1 -Subscription SUB_ID -Location eastus2 -All
#>
[CmdletBinding()]
param(
    [string]$Subscription = $env:AZURE_SUBSCRIPTION_ID,
    [string]$Location = ($env:AZURE_LOCATION ?? "eastus2"),
    [string]$Tenant = $env:AZURE_TENANT_ID,
    [switch]$All,
    [string]$Filter,
    [switch]$AsJson
)

$ErrorActionPreference = "Stop"

if (-not $Subscription) {
    Write-Error "Subscription required. Use -Subscription or set AZURE_SUBSCRIPTION_ID."
    exit 1
}

# Get access token
$tokenArgs = @("account", "get-access-token", "--resource", "https://management.azure.com/", "--query", "accessToken", "-o", "tsv")
if ($Tenant) { $tokenArgs += @("--tenant", $Tenant) }
$token = & az @tokenArgs 2>$null
if (-not $token) {
    Write-Error "Failed to get Azure access token. Run 'az login' first."
    exit 1
}

# Query ARM for models
$apiVersion = "2024-10-01"
$uri = "https://management.azure.com/subscriptions/$Subscription/providers/Microsoft.CognitiveServices/locations/$Location/models?api-version=$apiVersion"
$headers = @{
    "Authorization" = "Bearer $token"
    "Content-Type"  = "application/json"
}

try {
    $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
}
catch {
    Write-Error "Failed to query ARM: $_"
    exit 1
}

# Parse models
$models = @()
$seen = @{}

foreach ($m in $response.value) {
    if ($m.model.format -ne "OpenAI") { continue }

    $key = "$($m.model.name)|$($m.model.version)"
    if ($seen.ContainsKey($key)) { continue }
    $seen[$key] = $true

    $caps = @{}
    foreach ($c in $m.model.capabilities.PSObject.Properties) {
        $caps[$c.Name] = $c.Value
    }

    $models += [PSCustomObject]@{
        Name              = $m.model.name
        Version           = $m.model.version
        Responses         = ($caps["responses"] -eq "true")
        ChatCompletion    = ($caps["chatCompletion"] -eq "true")
        JsonSchemaResponse = ($caps["jsonSchemaResponse"] -eq "true") -or ($caps["jsonObjectResponse"] -eq "true")
        AgentsV2          = ($caps["agentsV2"] -eq "true")
        FineTune          = ($caps["fineTune"] -eq "true")
    }
}

$models = $models | Sort-Object Name, Version

# Apply filter
if ($Filter) {
    $prefixes = $Filter.Split(",") | ForEach-Object { $_.Trim().ToLower() }
    $models = $models | Where-Object {
        $name = $_.Name.ToLower()
        $prefixes | Where-Object { $name.StartsWith($_) }
    }
}

# Filter to Responses-capable unless -All
if (-not $All) {
    $models = $models | Where-Object { $_.Responses }
}

if ($models.Count -eq 0) {
    Write-Host "No models found matching criteria."
    exit 0
}

if ($AsJson) {
    @{
        location = $Location
        models = $models
    } | ConvertTo-Json -Depth 3
}
else {
    Write-Host ""
    Write-Host "  Azure OpenAI Model Compatibility - $Location" -ForegroundColor Cyan
    Write-Host "  $('=' * 90)" -ForegroundColor DarkGray
    Write-Host ""

    $header = "  {0,-30} {1,-12} {2,9} {3,5} {4,12} {5,7} {6,10}" -f "Model", "Version", "Responses", "Chat", "JSON Schema", "Agents", "Fine-tune"
    Write-Host $header -ForegroundColor White
    Write-Host "  $('-' * 30) $('-' * 12) $('-' * 9) $('-' * 5) $('-' * 12) $('-' * 7) $('-' * 10)" -ForegroundColor DarkGray

    foreach ($m in $models) {
        $flag = { param($v) if ($v) { "Y" } else { "-" } }
        $row = "  {0,-30} {1,-12} {2,9} {3,5} {4,12} {5,7} {6,10}" -f `
            $m.Name, $m.Version, `
            (& $flag $m.Responses), (& $flag $m.ChatCompletion), `
            (& $flag $m.JsonSchemaResponse), (& $flag $m.AgentsV2), (& $flag $m.FineTune)
        Write-Host $row
    }

    $responsesCount = ($models | Where-Object { $_.Responses }).Count
    Write-Host ""
    Write-Host "  $responsesCount/$($models.Count) model versions support the Responses API in $Location" -ForegroundColor Gray
    Write-Host ""
}

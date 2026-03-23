<#
.SYNOPSIS
    CLI entry point for Azure OpenAI → Responses API migration toolkit (C# / .NET).

.DESCRIPTION
    Dispatches to scan, org-scan, test, plan, models, and bulk subcommands.

.EXAMPLE
    .\migrate.ps1 scan C:\myapp
    .\migrate.ps1 scan C:\myapp -SmokeTest
    .\migrate.ps1 org-scan -Org myorg
    .\migrate.ps1 test
    .\migrate.ps1 plan
    .\migrate.ps1 models -Subscription SUB_ID -Location eastus2
    .\migrate.ps1 bulk prepare -Org myorg
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory)]
    [ValidateSet("scan", "org-scan", "test", "plan", "models", "bulk")]
    [string]$Command,

    [Parameter(Position = 1, ValueFromRemainingArguments)]
    [string[]]$Arguments
)

$ErrorActionPreference = "Stop"

$Root = $PSScriptRoot
$Scripts = Join-Path $Root ".github" "skills" "azure-openai-to-responses-csharp" "scripts"
$Tools = Join-Path $Root "tools"

function Invoke-Scan {
    param([string[]]$Args)

    $scanScript = Join-Path $Scripts "Detect-LegacyOpenAI.ps1"
    if (-not (Test-Path $scanScript)) {
        Write-Error "Scanner not found at $scanScript"
        return 1
    }

    $dirs = $Args | Where-Object { -not $_.StartsWith("-") }
    $smokeTest = $Args -contains "-SmokeTest"

    if (-not $dirs) { $dirs = @(".") }

    $exitCode = 0
    foreach ($dir in $dirs) {
        & $scanScript -Path $dir
        if ($LASTEXITCODE -ne 0) { $exitCode = 1 }
    }

    if ($smokeTest) {
        Write-Host ""
        Write-Host "--- Smoke-testing Azure OpenAI Responses API deployment ---" -ForegroundColor Cyan
        Write-Host ""
        $smokeResult = Invoke-SmokeTest
        if ($smokeResult -ne 0) { $exitCode = 1 }
    }

    return $exitCode
}

function Invoke-SmokeTest {
    $endpoint = $env:AZURE_OPENAI_ENDPOINT
    $deployment = $env:AZURE_OPENAI_DEPLOYMENT
    $apiKey = $env:AZURE_OPENAI_API_KEY

    if (-not $endpoint) {
        Write-Error "AZURE_OPENAI_ENDPOINT not set"
        return 1
    }
    if (-not $deployment) {
        Write-Error "AZURE_OPENAI_DEPLOYMENT not set"
        return 1
    }
    if (-not $apiKey) {
        Write-Warning "AZURE_OPENAI_API_KEY not set — smoke test requires API key for quick test"
        return 1
    }

    $baseUrl = "$($endpoint.TrimEnd('/'))/openai/v1/responses"
    $headers = @{
        "api-key"      = $apiKey
        "Content-Type" = "application/json"
    }
    $body = @{
        model            = $deployment
        input            = "Say hello in one word."
        max_output_tokens = 50
        store            = $false
    } | ConvertTo-Json

    try {
        $response = Invoke-RestMethod -Uri $baseUrl -Method Post -Headers $headers -Body $body
        Write-Host "[PASS] Deployment '$deployment' supports Responses API" -ForegroundColor Green
        Write-Host "   Model output: $($response.output_text)" -ForegroundColor Gray
        Write-Host "   Status: $($response.status)" -ForegroundColor Gray
        return 0
    }
    catch {
        Write-Host "[FAIL] Deployment '$deployment' does NOT support Responses API" -ForegroundColor Red
        Write-Host "   Error: $_" -ForegroundColor Red
        return 1
    }
}

function Invoke-OrgScan {
    param([string[]]$Args)

    $script = Join-Path $Tools "Find-LegacyOpenAIRepos.ps1"
    if (-not (Test-Path $script)) {
        Write-Error "Script not found at $script"
        return 1
    }

    & $script @Args
    return $LASTEXITCODE
}

function Invoke-Test {
    $testProject = Join-Path $Tools "Test-Migration" "Test-Migration.csproj"
    if (-not (Test-Path $testProject)) {
        Write-Error "Test project not found at $testProject"
        return 1
    }

    dotnet test $testProject --verbosity normal
    return $LASTEXITCODE
}

function Show-Plan {
    $plan = @"

╔══════════════════════════════════════════════════════════════════════╗
║       Azure OpenAI SDK (C#) → Responses API Migration Plan         ║
╠══════════════════════════════════════════════════════════════════════╣
║                                                                      ║
║  APPROACH A: Single-repo migration                                   ║
║  ─────────────────────────────────                                   ║
║  1. Scan:    .\migrate.ps1 scan C:\path\to\your-app                  ║
║  2. Migrate: @azure-openai-to-responses-csharp migrate C:\path\...   ║
║     Or follow .github\skills\...\SKILL.md                            ║
║  3. Verify:  .\migrate.ps1 scan C:\path\to\your-app                  ║
║              cd C:\path\to\your-app; dotnet test                     ║
║                                                                      ║
║  APPROACH B: Bulk migration across repos                             ║
║  ───────────────────────────────────────                             ║
║  1. Discover: .\migrate.ps1 org-scan -Org YOUR_ORG                   ║
║  2. Scan:     .\migrate.ps1 scan C:\path\to\each-repo                ║
║  3. Migrate:  Use Approach A per repo, then send PRs                 ║
║  4. Track:    Re-run org-scan to see remaining repos                 ║
║                                                                      ║
║  APPROACH C: Skill-only (no agent)                                   ║
║  ─────────────────────────────────                                   ║
║  Feed .github\skills\azure-openai-to-responses-csharp\SKILL.md to   ║
║  any LLM (Copilot, Claude, ChatGPT) as context, then ask it to      ║
║  migrate your code.                                                  ║
║                                                                      ║
╚══════════════════════════════════════════════════════════════════════╝

"@
    Write-Host $plan
    return 0
}

function Invoke-Models {
    param([string[]]$Args)

    $script = Join-Path $Tools "Get-ModelCompatibility.ps1"
    if (-not (Test-Path $script)) {
        Write-Error "Script not found at $script"
        return 1
    }

    & $script @Args
    return $LASTEXITCODE
}

function Invoke-Bulk {
    param([string[]]$Args)

    $script = Join-Path $Tools "Invoke-BulkMigration.ps1"
    if (-not (Test-Path $script)) {
        Write-Error "Script not found at $script"
        return 1
    }

    & $script @Args
    return $LASTEXITCODE
}

# Dispatch
$exitCode = switch ($Command) {
    "scan"     { Invoke-Scan -Args $Arguments }
    "org-scan" { Invoke-OrgScan -Args $Arguments }
    "test"     { Invoke-Test }
    "plan"     { Show-Plan }
    "models"   { Invoke-Models -Args $Arguments }
    "bulk"     { Invoke-Bulk -Args $Arguments }
}

exit $exitCode

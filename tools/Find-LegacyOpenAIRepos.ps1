<#
.SYNOPSIS
    Find repos in a GitHub org using legacy Azure OpenAI Chat Completions patterns in C#.

.DESCRIPTION
    Searches for AzureOpenAIClient, CompleteChatAsync, ChatCompletion, and other legacy
    patterns using the gh CLI code search API.

.PARAMETER Org
    GitHub organization name.

.PARAMETER Language
    Filter by language. Defaults to csharp.

.PARAMETER AsJson
    Output results as JSON.

.EXAMPLE
    .\Find-LegacyOpenAIRepos.ps1 -Org myorg
    .\Find-LegacyOpenAIRepos.ps1 -Org myorg -Language csharp -AsJson
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Org,

    [string]$Language = "csharp",

    [switch]$AsJson
)

$ErrorActionPreference = "Stop"

$SearchPatterns = @(
    @{ Pattern = "CompleteChatAsync"; Label = "Chat Completions API call" }
    @{ Pattern = "AzureOpenAIClient"; Label = "AzureOpenAIClient constructor" }
    @{ Pattern = "GetChatClient"; Label = "GetChatClient call" }
    @{ Pattern = "Azure.AI.OpenAI"; Label = "Azure.AI.OpenAI package reference" }
    @{ Pattern = "ChatCompletion"; Label = "ChatCompletion type" }
    @{ Pattern = "CompleteChatStreamingAsync"; Label = "Streaming Chat Completions" }
)

$RateLimitPause = 7  # seconds between searches

# Verify gh CLI is authenticated
try {
    $username = gh api /user --jq ".login" 2>$null
    if (-not $username) { throw "Not authenticated" }
    Write-Host "Authenticated as: $username" -ForegroundColor Gray
}
catch {
    Write-Error "gh CLI not authenticated. Run 'gh auth login' first."
    exit 1
}

Write-Host "Searching org: $Org" -ForegroundColor Gray
if ($Language) { Write-Host "Language filter: $Language" -ForegroundColor Gray }
Write-Host ""

$repoMatches = @{}

foreach ($item in $SearchPatterns) {
    Write-Host "Searching: '$($item.Pattern)' ($($item.Label))..." -ForegroundColor Gray

    $cmd = @("search", "code", "--owner", $Org, $item.Pattern, "--json", "repository,path", "--limit", "100")
    if ($Language) { $cmd += @("--language", $Language) }

    $result = & gh @cmd 2>$null
    if ($LASTEXITCODE -eq 0 -and $result) {
        $matches = $result | ConvertFrom-Json
        foreach ($match in $matches) {
            $repoName = $match.repository.fullName
            if (-not $repoMatches.ContainsKey($repoName)) {
                $repoMatches[$repoName] = @{}
            }
            if (-not $repoMatches[$repoName].ContainsKey($item.Label)) {
                $repoMatches[$repoName][$item.Label] = @()
            }
            $repoMatches[$repoName][$item.Label] += $match.path
        }
        $uniqueRepos = ($matches | ForEach-Object { $_.repository.fullName } | Sort-Object -Unique).Count
        Write-Host "  Found $($matches.Count) matches across $uniqueRepos repos" -ForegroundColor DarkGray
    }

    Start-Sleep -Seconds $RateLimitPause
}

Write-Host ""

if ($repoMatches.Count -eq 0) {
    Write-Host "No legacy Azure OpenAI patterns found in '$Org'." -ForegroundColor Green
    exit 0
}

$totalMatches = ($repoMatches.Values | ForEach-Object { $_.Values } | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum

if ($AsJson) {
    $output = @{
        org             = $Org
        language_filter = $Language
        total_repos     = $repoMatches.Count
        total_matches   = $totalMatches
        repos           = @()
    }
    foreach ($repo in ($repoMatches.Keys | Sort-Object)) {
        $patterns = $repoMatches[$repo]
        $files = ($patterns.Values | ForEach-Object { $_ } | Sort-Object -Unique)
        $output.repos += @{
            repo            = $repo
            patterns_found  = @($patterns.Keys)
            files           = $files
        }
    }
    $output | ConvertTo-Json -Depth 5
}
else {
    Write-Host "Found $totalMatches matches across $($repoMatches.Count) repos in '$Org':" -ForegroundColor Yellow
    Write-Host ""

    foreach ($repo in ($repoMatches.Keys | Sort-Object)) {
        $patterns = $repoMatches[$repo]
        $files = ($patterns.Values | ForEach-Object { $_ } | Sort-Object -Unique)

        Write-Host "  $repo" -ForegroundColor White
        Write-Host "    Patterns: $($patterns.Keys -join ', ')" -ForegroundColor DarkGray
        Write-Host "    Files ($($files.Count)):" -ForegroundColor DarkGray
        $displayFiles = $files | Select-Object -First 10
        foreach ($f in $displayFiles) {
            Write-Host "      - $f" -ForegroundColor DarkGray
        }
        if ($files.Count -gt 10) {
            Write-Host "      ... and $($files.Count - 10) more" -ForegroundColor DarkGray
        }
        Write-Host ""
    }
}

<#
.SYNOPSIS
    Scans a .NET project directory for legacy Azure OpenAI Chat Completions patterns.

.DESCRIPTION
    Finds C# files using AzureOpenAIClient, ChatClient, CompleteChatAsync, and other
    legacy patterns that need migration to the Responses API.

.PARAMETER Path
    The directory to scan. Defaults to current directory.

.PARAMETER ExcludeDirs
    Directories to exclude from scanning. Defaults to bin, obj, .git, node_modules.

.EXAMPLE
    .\Detect-LegacyOpenAI.ps1 -Path C:\myapp
    .\Detect-LegacyOpenAI.ps1 -Path . -ExcludeDirs bin,obj,TestResults
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Path = ".",

    [string[]]$ExcludeDirs = @("bin", "obj", ".git", "node_modules", ".vs", "TestResults", "packages")
)

$ErrorActionPreference = "Stop"

# Resolve the path
$ScanRoot = (Resolve-Path $Path).Path

# Define patterns to search for, grouped by category
$PatternGroups = [ordered]@{
    "NuGet Packages" = @(
        @{ Pattern = 'Azure\.AI\.OpenAI'; Label = 'Azure.AI.OpenAI package reference'; Extensions = @('.csproj', '.props', '.targets') }
        @{ Pattern = 'Include="Azure\.AI\.OpenAI"'; Label = 'Azure.AI.OpenAI PackageReference'; Extensions = @('.csproj', '.props', '.targets') }
    )
    "Using Directives" = @(
        @{ Pattern = 'using\s+Azure\.AI\.OpenAI'; Label = 'using Azure.AI.OpenAI namespace'; Extensions = @('.cs') }
        @{ Pattern = 'using\s+OpenAI\.Chat\b'; Label = 'using OpenAI.Chat namespace'; Extensions = @('.cs') }
    )
    "Client Constructors" = @(
        @{ Pattern = 'new\s+AzureOpenAIClient\s*\('; Label = 'AzureOpenAIClient constructor'; Extensions = @('.cs') }
        @{ Pattern = '\.GetChatClient\s*\('; Label = 'GetChatClient() call'; Extensions = @('.cs') }
        @{ Pattern = 'AzureKeyCredential'; Label = 'AzureKeyCredential (Azure.AI.OpenAI auth)'; Extensions = @('.cs') }
    )
    "API Calls" = @(
        @{ Pattern = '\.CompleteChatAsync\s*\('; Label = 'CompleteChatAsync call'; Extensions = @('.cs') }
        @{ Pattern = '\.CompleteChat\s*\('; Label = 'CompleteChat call (sync)'; Extensions = @('.cs') }
        @{ Pattern = '\.CompleteChatStreamingAsync\s*\('; Label = 'CompleteChatStreamingAsync call'; Extensions = @('.cs') }
        @{ Pattern = '\.CompleteChatStreaming\s*\('; Label = 'CompleteChatStreaming call (sync)'; Extensions = @('.cs') }
    )
    "Response Shapes" = @(
        @{ Pattern = '\.Content\[0\]\.Text'; Label = 'Legacy response shape: .Content[0].Text'; Extensions = @('.cs') }
        @{ Pattern = 'ChatCompletion\b'; Label = 'ChatCompletion type reference'; Extensions = @('.cs') }
        @{ Pattern = 'StreamingChatCompletionUpdate'; Label = 'StreamingChatCompletionUpdate type'; Extensions = @('.cs') }
        @{ Pattern = '\.ContentUpdate\b'; Label = 'Legacy streaming .ContentUpdate'; Extensions = @('.cs') }
        @{ Pattern = 'ChatFinishReason'; Label = 'ChatFinishReason enum'; Extensions = @('.cs') }
        @{ Pattern = 'ChatMessageRole'; Label = 'ChatMessageRole enum'; Extensions = @('.cs') }
    )
    "Message Types" = @(
        @{ Pattern = 'SystemChatMessage'; Label = 'SystemChatMessage type'; Extensions = @('.cs') }
        @{ Pattern = 'UserChatMessage'; Label = 'UserChatMessage type'; Extensions = @('.cs') }
        @{ Pattern = 'AssistantChatMessage'; Label = 'AssistantChatMessage type'; Extensions = @('.cs') }
        @{ Pattern = 'ToolChatMessage'; Label = 'ToolChatMessage type'; Extensions = @('.cs') }
        @{ Pattern = 'ChatMessage\b'; Label = 'ChatMessage base type'; Extensions = @('.cs') }
    )
    "Chat Options" = @(
        @{ Pattern = 'ChatCompletionOptions'; Label = 'ChatCompletionOptions class'; Extensions = @('.cs') }
        @{ Pattern = 'ChatTool\b'; Label = 'ChatTool type (function calling)'; Extensions = @('.cs') }
        @{ Pattern = 'ChatResponseFormat'; Label = 'ChatResponseFormat class'; Extensions = @('.cs') }
        @{ Pattern = '\.Seed\s*='; Label = 'Seed property (not supported in Responses API)'; Extensions = @('.cs') }
    )
    "Parameters" = @(
        @{ Pattern = 'api[_-]?version'; Label = 'api_version / ApiVersion reference'; Extensions = @('.cs', '.json', '.bicep', '.yaml', '.yml', '.env', '.config') }
        @{ Pattern = 'AZURE_OPENAI_API_VERSION'; Label = 'AZURE_OPENAI_API_VERSION env var'; Extensions = @('.cs', '.json', '.bicep', '.yaml', '.yml', '.env', '.config', '.ps1', '.sh') }
    )
    "Test Infrastructure" = @(
        @{ Pattern = 'Mock<ChatClient>'; Label = 'Mocked ChatClient'; Extensions = @('.cs') }
        @{ Pattern = 'ChatClient\b'; Label = 'ChatClient type reference'; Extensions = @('.cs') }
    )
}

# Collect all files to scan
$allFiles = Get-ChildItem -Path $ScanRoot -Recurse -File | Where-Object {
    $file = $_
    $relPath = $file.FullName.Substring($ScanRoot.Length).TrimStart('\', '/')
    $parts = $relPath -split '[\\/]'
    -not ($parts | Where-Object { $_ -in $ExcludeDirs })
}

$totalHits = 0
$fileHits = @{}
$categoryHits = [ordered]@{}

foreach ($groupName in $PatternGroups.Keys) {
    $patterns = $PatternGroups[$groupName]
    $categoryHits[$groupName] = @()

    foreach ($patternInfo in $patterns) {
        $matchingFiles = $allFiles | Where-Object {
            $_.Extension -in $patternInfo.Extensions
        }

        foreach ($file in $matchingFiles) {
            $lineNum = 0
            foreach ($line in (Get-Content $file.FullName -ErrorAction SilentlyContinue)) {
                $lineNum++
                if ($line -match $patternInfo.Pattern) {
                    $relPath = $file.FullName.Substring($ScanRoot.Length).TrimStart('\', '/')
                    $hit = [PSCustomObject]@{
                        Category = $groupName
                        Label    = $patternInfo.Label
                        File     = $relPath
                        Line     = $lineNum
                        Content  = $line.Trim()
                    }
                    $categoryHits[$groupName] += $hit
                    $totalHits++

                    if (-not $fileHits.ContainsKey($relPath)) {
                        $fileHits[$relPath] = 0
                    }
                    $fileHits[$relPath]++
                }
            }
        }
    }
}

# Output report
Write-Host ""
Write-Host "  Azure OpenAI SDK (C#) Legacy Pattern Scanner" -ForegroundColor Cyan
Write-Host "  =============================================" -ForegroundColor Cyan
Write-Host "  Scanned: $ScanRoot" -ForegroundColor Gray
Write-Host ""

if ($totalHits -eq 0) {
    Write-Host "  [CLEAN] No legacy Chat Completions patterns found." -ForegroundColor Green
    Write-Host ""
    exit 0
}

Write-Host "  Found $totalHits legacy pattern(s) across $($fileHits.Count) file(s):" -ForegroundColor Yellow
Write-Host ""

foreach ($groupName in $categoryHits.Keys) {
    $hits = $categoryHits[$groupName]
    if ($hits.Count -eq 0) { continue }

    Write-Host "  $groupName ($($hits.Count) hit(s))" -ForegroundColor Magenta
    Write-Host "  $('-' * ($groupName.Length + 10))" -ForegroundColor DarkGray

    foreach ($hit in $hits) {
        Write-Host "    $($hit.File):$($hit.Line)" -ForegroundColor White -NoNewline
        Write-Host "  $($hit.Label)" -ForegroundColor DarkYellow
        $preview = $hit.Content
        if ($preview.Length -gt 100) { $preview = $preview.Substring(0, 97) + "..." }
        Write-Host "      $preview" -ForegroundColor DarkGray
    }
    Write-Host ""
}

# Summary
Write-Host "  Summary by file:" -ForegroundColor Cyan
Write-Host "  -----------------" -ForegroundColor DarkGray
foreach ($file in ($fileHits.GetEnumerator() | Sort-Object -Property Value -Descending)) {
    Write-Host "    $($file.Value) hit(s)  $($file.Key)" -ForegroundColor White
}
Write-Host ""
Write-Host "  Total: $totalHits pattern(s) in $($fileHits.Count) file(s) need migration." -ForegroundColor Yellow
Write-Host ""

exit 1

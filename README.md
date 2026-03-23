# Azure OpenAI To Responses (C# / .NET)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![.NET 10](https://img.shields.io/badge/.NET-10-512BD4)](https://dotnet.microsoft.com/)
[![OpenAI SDK](https://img.shields.io/badge/OpenAI%20SDK-%E2%89%A5%202.9.1-412991)](https://www.nuget.org/packages/OpenAI)

Migrate your **.NET apps** from the **Azure OpenAI SDK (`Azure.AI.OpenAI`) with Chat Completions API** to the **OpenAI SDK (`OpenAI`) with Responses API**.

> **GPT-5 and newer models require the Responses API.** Migrating now future-proofs your apps and unlocks deep tool integration, structured output, and a stable `/openai/v1/` endpoint with no `api_version` management.

> **⚠️ Before you start:** Check that your deployed model supports the Responses API — run `.\migrate.ps1 models -Subscription YOUR_SUB_ID -Location YOUR_REGION` or see the [model compatibility](#model-compatibility) section. Older models like `gpt-4o` support Responses but **not all features** (see [known limitations](#known-limitations-with-older-models)).

> **📝 Note:** The Responses API is currently in preview. All C# files that use it must include `#pragma warning disable OPENAI001` at the top to suppress the preview warning.

### Quick links

- **New to migration?** Start with [Choose your approach](#choose-your-approach) below
- **Hands-on with Copilot?** Use the [VS Code agent](#a-single-repo-migration) to migrate interactively
- **Prefer manual?** Follow [SKILL.md](.github/skills/azure-openai-to-responses-csharp/SKILL.md) step by step with the [cheat sheet](.github/skills/azure-openai-to-responses-csharp/references/cheat-sheet.md)
- **Migrating tests?** See the [test migration guide](.github/skills/azure-openai-to-responses-csharp/references/test-migration.md)
- **ASP.NET Core app?** See [cheat sheet § ASP.NET Core](.github/skills/azure-openai-to-responses-csharp/references/cheat-sheet.md#10-aspnet-core-integration) for minimal API and DI patterns
- **Hit an error?** Check [troubleshooting](.github/skills/azure-openai-to-responses-csharp/references/troubleshooting.md)

### What changes?

| Before (Azure OpenAI SDK + Chat Completions) | After (OpenAI SDK + Responses API) |
|---|---|
| `new AzureOpenAIClient(endpoint, credential)` | `new ResponsesClient(credential, options)` with `Endpoint = new Uri($"{endpoint}/openai/v1/")` |
| `client.GetChatClient("deployment")` | Direct `ResponsesClient` — no intermediate client |
| `chatClient.CompleteChatAsync(messages)` | `responsesClient.CreateResponseAsync("model", input, options)` |
| `response.Value.Content[0].Text` | `response.GetOutputText()` |
| `Azure.AI.OpenAI` + `OpenAI` packages | `OpenAI` package only (>= 2.9.1) |
| `api-version` managed by SDK | Not needed — `/openai/v1/` is stable |

### NuGet packages

| Before | After |
|---|---|
| `Azure.AI.OpenAI` (>= 2.0) | `OpenAI` (>= 2.9.1) |
| `Azure.Identity` (for EntraID) | `Azure.Identity` (still needed for EntraID) |
| `OpenAI` (transitive via Azure.AI.OpenAI) | `OpenAI` (direct reference) |

### Quick example: basic completion

```csharp
#pragma warning disable OPENAI001

// BEFORE — Chat Completions
var client = new AzureOpenAIClient(new Uri(endpoint), new DefaultAzureCredential());
var chatClient = client.GetChatClient("gpt-5-mini");
ChatCompletion response = await chatClient.CompleteChatAsync(
    new ChatMessage[] { new UserChatMessage("Hello!") });
Console.WriteLine(response.Content[0].Text);

// AFTER — Responses API
var policy = new BearerTokenPolicy(
    new DefaultAzureCredential(), "https://cognitiveservices.azure.com/.default");
var options = new OpenAIClientOptions { Endpoint = new Uri($"{endpoint.TrimEnd('/')}/openai/v1/") };
var responsesClient = new ResponsesClient(policy, options);
var response = await responsesClient.CreateResponseAsync("gpt-5-mini", "Hello!");
Console.WriteLine(response.GetOutputText());
```

### Quick example: streaming

```csharp
#pragma warning disable OPENAI001

var messages = new[] { ResponseItem.CreateUserMessageItem("Count from 1 to 10.") };
var opts = new CreateResponseOptions("gpt-5-mini", messages);

await foreach (var update in responsesClient.CreateResponseStreamingAsync(opts))
{
    if (update is ResponseContentPartDeltaUpdate delta)
        Console.Write(delta.Delta);
}
Console.WriteLine();
```

---

## Choose your approach

| Approach | Best for | Time |
|---|---|---|
| **[A. Single-repo migration](#a-single-repo-migration)** | One app, hands-on walkthrough | ~30 min per app |
| **[B. Bulk migration across repos](#b-bulk-migration-across-repos)** | Org-wide rollout, multiple repos | Hours (scripted) |
| **[C. Skill-only (no agent)](#c-skill-only-no-agent)** | Any LLM, manual, or custom workflow | Varies |

### Setup (all approaches)

```powershell
git clone https://github.com/Azure-Samples/azure-openai-to-responses-csharp.git
cd azure-openai-to-responses-csharp
```

No additional install needed — all tools are PowerShell scripts. Requires PowerShell 7+ and .NET 10 SDK.

---

## A. Single-repo migration

Migrate one app end-to-end — the same workflow used to migrate the included [demo app](demo/).

### Step 1 — Scan for legacy patterns

```powershell
.\migrate.ps1 scan C:\path\to\your-app
```

The scanner finds every call site that needs to change, grouped by category: client constructors, API calls, response shapes, parameters, config, and test infrastructure.

### Step 2 — Let the agent migrate it

Open your app in VS Code as a **multi-root workspace** with both this repo and your app:

1. Open your app folder in VS Code (`File > Open Folder`)
2. Add this repo: `File > Add Folder to Workspace...` → select the cloned `azure-openai-to-responses-csharp` folder
3. VS Code switches to an "Untitled (Workspace)" with both folders in the sidebar

> **Why multi-root?** VS Code scopes Copilot's file access to workspace folders. Without this, the agent will prompt for permission every time it tries to read or edit files in your app. Adding both folders to the same workspace avoids those prompts.
>
> **Tip:** Save it for reuse with `File > Save Workspace As...` (creates a `.code-workspace` file you can double-click next time).

In Copilot Chat:

```
@azure-openai-to-responses-csharp migrate the app at C:\path\to\your-app
```

The agent will:

1. **Scan** your code and show what needs to change
2. **Plan** the edit order — NuGet packages first, then constructors, API calls, response shapes, tests, cleanup
3. **Migrate** each file with precise, reviewable edits
4. **Verify** by re-running the scanner (zero hits) and your tests (`dotnet test`)
5. **Report** a summary of everything changed and any manual follow-ups

> **Prefer hands-on?** Skip the agent and follow [SKILL.md](.github/skills/azure-openai-to-responses-csharp/SKILL.md) step by step. The [cheat sheet](.github/skills/azure-openai-to-responses-csharp/references/cheat-sheet.md) has copy-paste code for every pattern.

### Step 3 — Verify

```powershell
# Scanner should report zero hits
.\migrate.ps1 scan C:\path\to\your-app

# Run your project's own tests
cd C:\path\to\your-app
dotnet test
```

Verification will vary by project — run whatever unit/integration tests the project already has. If the app has a UI or API endpoint, do a quick manual test too (start the server, send a request, confirm streaming works).

> **Migrating tests?** Your existing mocks and assertions will need updating too. See the [test migration guide](.github/skills/azure-openai-to-responses-csharp/references/test-migration.md) for `ChatCompletion` → `ResponseResult` mock patterns, interface abstractions, and `WebApplicationFactory` integration tests.

### Demo: what a migrated app looks like

The [`demo/azure-openai-keyless-csharp/`](demo/azure-openai-keyless-csharp/) directory is a fully migrated [Azure Samples keyless deployment app](https://github.com/Azure-Samples/azure-openai-keyless-csharp) — a real .NET console app using EntraID authentication.

| File | What changed |
|---|---|
| `Program.cs` | `AzureOpenAIClient` / `ChatClient` → `ResponsesClient` with `BearerTokenPolicy`; `CompleteChat` → `CreateResponseAsync`; `completion.Content[0].Text` → `response.GetOutputText()` |
| `*.csproj` | `Azure.AI.OpenAI` removed; `OpenAI` >= 2.9.1 added directly |
| `infra/main.bicep` | Removed `openAiApiVersion` parameter and `OPENAI_API_VERSION` output |
| `.env.sample` | Removed `OPENAI_API_VERSION` |

**Result:** `dotnet run` works end-to-end, scanner reports zero legacy hits. See the [sample PR description](demo/azure-openai-keyless-csharp/PR.md) for what a migration PR would look like.

---

## B. Bulk migration across repos

Roll out the migration across your entire GitHub org with a single workflow that discovers, clones, tracks, and sends PRs.

Requires the [gh CLI](https://cli.github.com/), authenticated (`gh auth login`).

### Step 1 — Prepare (discover + clone + scan)

```powershell
.\migrate.ps1 bulk prepare -Org YOUR_ORG
.\migrate.ps1 bulk prepare -Org YOUR_ORG -Language csharp -WorkDir .\migrations
```

This automatically:
- Searches your org for repos with legacy Chat Completions patterns in C#
- Clones each repo into the work directory
- Creates a `azure-openai-to-responses-api` branch in each
- Runs the scanner and produces a consolidated report

### Step 2 — Migrate each repo

For each repo in the work directory, pick your method:

- **Agent:** Open the repo in VS Code → `@azure-openai-to-responses-csharp migrate this app`
- **Skill:** Feed [SKILL.md](.github/skills/azure-openai-to-responses-csharp/SKILL.md) to your LLM
- **Manual:** Follow the skill step-by-step with the [cheat sheet](.github/skills/azure-openai-to-responses-csharp/references/cheat-sheet.md)

### Step 3 — Review status

```powershell
.\migrate.ps1 bulk status -WorkDir .\migrations
```

### Step 4 — Send PRs

```powershell
# Send PRs for all repos that are ready (interactive prompt)
.\migrate.ps1 bulk send-prs -WorkDir .\migrations

# Send PRs for specific repos only
.\migrate.ps1 bulk send-prs -WorkDir .\migrations -Repos repo1,repo2

# Skip confirmation
.\migrate.ps1 bulk send-prs -WorkDir .\migrations -Yes
```

---

## C. Skill-only (no agent)

The migration knowledge lives in a self-contained [SKILL.md](.github/skills/azure-openai-to-responses-csharp/SKILL.md) that any LLM can follow — no VS Code agent required.

### With VS Code Copilot Chat

Add to your `.github/copilot-instructions.md`:

```markdown
When asked to migrate from Chat Completions to Responses API in C#, follow:
.github/skills/azure-openai-to-responses-csharp/SKILL.md
```

Then ask: *"Migrate this file from Chat Completions to Responses API."*

### With Claude, ChatGPT, or any LLM

Paste the skill file as context:

```powershell
Get-Content .github\skills\azure-openai-to-responses-csharp\SKILL.md
```

The skill includes:
- Step-by-step migration instructions with parameter mapping tables
- Client constructor patterns (sync, async, EntraID, API key)
- Acceptance criteria checklist (code, tests, behavioral gates)
- Links to [cheat-sheet.md](.github/skills/azure-openai-to-responses-csharp/references/cheat-sheet.md) (all code snippets), [test-migration.md](.github/skills/azure-openai-to-responses-csharp/references/test-migration.md) (mock/assertion updates), and [troubleshooting.md](.github/skills/azure-openai-to-responses-csharp/references/troubleshooting.md) (common errors + gotchas)

### Scanner standalone

The scanner works independently — no agent or LLM needed:

```powershell
.\migrate.ps1 scan C:\path\to\your-app

# Or call the script directly
.\.github\skills\azure-openai-to-responses-csharp\scripts\Detect-LegacyOpenAI.ps1 -Path C:\path\to\your-app
```

---

## Model compatibility

### Responses API support matrix (eastus2, March 2026)

| Model | Version | Responses | Chat | JSON Schema | Agents | Fine-tune |
|---|---|:---:|:---:|:---:|:---:|:---:|
| gpt-4 | 0613 | Y | Y | - | Y | - |
| gpt-4o | 2024-08-06 | Y | Y | Y | Y | Y |
| gpt-4o-mini | 2024-07-18 | Y | Y | Y | Y | Y |
| gpt-4.1 | 2025-04-14 | Y | Y | - | Y | Y |
| gpt-4.1-mini | 2025-04-14 | Y | Y | - | Y | Y |
| o1 | 2024-12-17 | Y | Y | - | Y | - |
| o3-mini | 2025-01-31 | Y | Y | - | Y | - |
| o4-mini | 2025-04-16 | Y | Y | - | Y | Y |
| gpt-5 | 2025-08-07 | Y | Y | - | Y | - |
| gpt-5-mini | 2025-08-07 | Y | Y | - | Y | - |

> **Y** = supported, **-** = not declared. Availability varies by region — run `.\migrate.ps1 models` for your region's live data.

### Check your region

```powershell
.\migrate.ps1 models -Subscription YOUR_SUB_ID -Location eastus2
.\migrate.ps1 models -Subscription YOUR_SUB_ID -Location eastus2 -Filter gpt-4o,gpt-5
.\migrate.ps1 models -Subscription YOUR_SUB_ID -Location eastus2 -All   # includes non-Responses models
```

### Known limitations with older models

> **⚠️ WARNING:** Older models (e.g., `gpt-4o`, `gpt-4`) support the Responses API but **do not support all features fully**. The migration still works for basic text, chat, streaming, and tools — but test thoroughly.

| Limitation | Details |
|---|---|
| `reasoning` parameter | Not supported on `gpt-4o-mini`, `gpt-4o`, and many non-reasoning models. |
| `Seed` property | Not supported in Responses API at all — remove from all requests. |
| Structured output | Older models may not enforce `strict: true` JSON schemas reliably. |
| Tool orchestration | GPT-5+ orchestrates tool calls as part of internal reasoning. Older models on Responses still work but lack deep integration. |
| Temperature constraints | When migrating to `gpt-5` or o-series, temperature must be omitted or set to `1`. |
| `MaxOutputTokenCount` | Minimum is **16** on Azure OpenAI. Values below 16 return a 400 error. |
| **O-series models** | `o1`, `o3-mini`, `o3`, `o4-mini` have specific constraints: `temperature` must be `1`, `top_p` not supported, `MaxCompletionTokenCount` must be migrated to `MaxOutputTokenCount` (set to 4096+). |

**Recommendation:** If staying on an older model (gpt-4o, gpt-4), the migration to Responses API works for core functionality. For full benefit (especially tool orchestration and reasoning), upgrade to gpt-5.1 or gpt-5.2.

---

## References

- [Azure OpenAI Starter Kit](https://aka.ms/openai/start) — quickstart examples, model compatibility, and Responses API guidance
- [Azure OpenAI Responses API docs](https://learn.microsoft.com/en-us/azure/ai-foundry/openai/how-to/responses)
- [OpenAI Responses API reference](https://platform.openai.com/docs/api-reference/responses)
- [OpenAI .NET SDK](https://github.com/openai/openai-dotnet) — the official OpenAI SDK for .NET

<details>
<summary>CLI reference</summary>

| Command | Description |
|---|---|
| `.\migrate.ps1 scan <dirs>` | Scan directories for legacy patterns. Exit 0 = clean, exit 1 = migration needed. |
| `.\migrate.ps1 org-scan -Org <name>` | Search a GitHub org for repos using legacy patterns (via `gh` CLI). |
| `.\migrate.ps1 org-scan -Org <name> -AsJson` | Same, but JSON output for scripting. |
| `.\migrate.ps1 bulk prepare -Org <name>` | Clone flagged repos, create branches, scan, produce report. |
| `.\migrate.ps1 bulk status -WorkDir <dir>` | Show migration status + files changed per repo. |
| `.\migrate.ps1 bulk send-prs -WorkDir <dir>` | Create PRs for migrated repos. |
| `.\migrate.ps1 models -Subscription <id> -Location <region>` | List Azure OpenAI models and Responses API support. |
| `.\migrate.ps1 test` | Run the live Responses API .NET test suite. |
| `.\migrate.ps1 plan` | Print the recommended migration workflow. |

</details>

<details>
<summary>Repository structure</summary>

```
azure-openai-to-responses-csharp/
├── migrate.ps1                                     # CLI entry point (PowerShell)
├── README.md
├── .gitignore
├── LICENSE
├── .github/
│   ├── agents/
│   │   └── azure-openai-to-responses-csharp.agent.md  # Copilot agent (orchestrator)
│   └── skills/
│       └── azure-openai-to-responses-csharp/
│           ├── SKILL.md                            # Core migration knowledge
│           ├── references/
│           │   ├── cheat-sheet.md                  # All C# code snippets & patterns
│           │   ├── test-migration.md               # Mock & assertion updates
│           │   └── troubleshooting.md              # Errors, risk table, gotchas
│           └── scripts/
│               └── Detect-LegacyOpenAI.ps1         # Pattern scanner
├── tools/
│   ├── Invoke-BulkMigration.ps1                    # Bulk workflow: clone, track, send PRs
│   ├── Find-LegacyOpenAIRepos.ps1                  # GitHub org search (uses gh CLI)
│   ├── Get-ModelCompatibility.ps1                  # Model compatibility matrix from ARM
│   └── Test-Migration/                             # .NET test project
│       ├── Test-Migration.csproj
│       └── ResponsesApiTests.cs                    # Live API test harness
└── demo/
    └── azure-openai-keyless-csharp/                # Fully migrated Azure Samples app
        ├── README.md                               # What changed
        ├── Program.cs                              # Migrated program
        ├── azure-openai-keyless-csharp.csproj      # Updated NuGet refs
        ├── PR.md                                   # Sample PR description
        ├── .env.sample
        └── infra/
            ├── main.bicep                          # Updated Bicep (no api_version)
            └── abbreviations.json                  # Azure resource name abbreviations
```

</details>

<details>
<summary>Environment variables</summary>

| Variable | Used by | Description |
|---|---|---|
| `AZURE_OPENAI_ENDPOINT` | test | Azure OpenAI resource URL |
| `AZURE_OPENAI_DEPLOYMENT` | test | Deployment name (e.g., `gpt-5-mini`) |
| `AZURE_OPENAI_API_KEY` | test | API key (omit if using EntraID) |
| `AZURE_TENANT_ID` | EntraID auth | Tenant ID |
| `AZURE_CLIENT_ID` | Managed identity | User-assigned managed identity client ID |

</details>

---

## Contributing

This project welcomes contributions and suggestions. See [CONTRIBUTING.md](CONTRIBUTING.md) for details.

- [Report a bug](https://github.com/Azure-Samples/azure-openai-to-responses-csharp/issues/new)
- [Security issues](SECURITY.md)
- [Code of conduct](CODE_OF_CONDUCT.md)

## License

MIT — see [LICENSE](LICENSE)

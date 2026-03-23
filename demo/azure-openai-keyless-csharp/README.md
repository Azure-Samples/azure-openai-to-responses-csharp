# Demo: Migrated Azure OpenAI Keyless C# App (Responses API)

This is [Azure-Samples/azure-openai-keyless-csharp](https://github.com/Azure-Samples/azure-openai-keyless-csharp) **after migration** from Azure OpenAI SDK Chat Completions to the OpenAI SDK Responses API. It shows what a real migrated .NET app looks like.

## What changed

| File | Migration change |
|---|---|
| `Program.cs` | `AzureOpenAIClient` / `ChatClient` → `ResponsesClient` with `BearerTokenPolicy`; `CompleteChat` → `CreateResponseAsync`; `completion.Content[0].Text` → `response.GetOutputText()` |
| `azure-openai-keyless-csharp.csproj` | `Azure.AI.OpenAI` removed, `OpenAI` >= 2.9.1 added |
| `infra/main.bicep` | Removed `openAiApiVersion` parameter and `OPENAI_API_VERSION` output — not needed with `/openai/v1/` endpoint |
| `.env.sample` | Removed `OPENAI_API_VERSION` |

## Key patterns demonstrated

- **Keyless (EntraID) auth** — `DefaultAzureCredential` wrapped in `BearerTokenPolicy`, passed to `ResponsesClient` via `OpenAIClientOptions`
- **No `api_version` management** — the `/openai/v1/` endpoint is stable
- **`#pragma warning disable OPENAI001`** — required for the experimental Responses API

## Key file to study

- **`Program.cs`** — The migrated main program. Shows `BearerTokenPolicy` setup with `DefaultAzureCredential`, `ResponsesClient` construction with `OpenAIClientOptions`, and `CreateResponseAsync` with `ResponseItem` conversation format.

## Running the sample

```bash
cd demo/azure-openai-keyless-csharp

# Set user secrets (same endpoint, same deployment — only the SDK changes)
dotnet user-secrets set "AZURE_OPENAI_ENDPOINT" "<your-endpoint>"
dotnet user-secrets set "AZURE_OPENAI_API_DEPLOYMENT_NAME" "<your-deployment>"

dotnet run
```

## Verifying the migration

```powershell
# Scanner should report zero hits on the migrated app
..\..\migrate.ps1 scan .\

# Run the app
dotnet run
```

## Original repo

See the [original Azure Samples repo](https://github.com/Azure-Samples/azure-openai-keyless-csharp) for deployment instructions, Codespaces setup, and full infrastructure.

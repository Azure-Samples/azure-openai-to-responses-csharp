# Migrate Azure OpenAI SDK (C#) to OpenAI Responses API

> **Purpose:** Step-by-step migration guide for .NET apps using `Azure.AI.OpenAI` with Chat Completions
> to `OpenAI` SDK with Responses API. Designed to be followed by an LLM agent or a human developer.

## Prerequisites

- .NET 10+ SDK installed
- The target app uses `Azure.AI.OpenAI` package (v2.0+) with `ChatClient` / `CompleteChatAsync`
- An Azure OpenAI deployment that supports the Responses API (run scanner to check)

## Migration steps

### Step 1 — Scan for legacy patterns

Run the scanner against the target directory:

```powershell
.\.github\skills\azure-openai-to-responses-csharp\scripts\Detect-LegacyOpenAI.ps1 -Path <target>
```

The scanner reports every file and line that needs to change. Review the output before proceeding.

### Step 2 — Update NuGet packages

In every `.csproj` file that references `Azure.AI.OpenAI`:

1. **Remove** the `Azure.AI.OpenAI` package reference
2. **Add** (or update) the `OpenAI` package to version `>= 2.9.1`
3. **Keep** `Azure.Identity` if the app uses EntraID / `DefaultAzureCredential`

```xml
<!-- BEFORE -->
<PackageReference Include="Azure.AI.OpenAI" Version="2.1.0" />
<PackageReference Include="Azure.Identity" Version="1.13.2" />

<!-- AFTER -->
<PackageReference Include="OpenAI" Version="2.9.1" />
<PackageReference Include="Azure.Identity" Version="1.13.2" />
```

### Step 3 — Update using directives

Replace old namespaces with new ones:

| Remove | Add |
|---|---|
| `using Azure.AI.OpenAI;` | `using OpenAI;` |
| `using OpenAI.Chat;` | `using OpenAI.Responses;` |
| | `using System.ClientModel;` (for `ApiKeyCredential`) |
| | `using System.ClientModel.Primitives;` (for `BearerTokenPolicy` with EntraID) |

Add the pragma warning suppression at the top of each file using Responses API:
```csharp
#pragma warning disable OPENAI001
```

### Step 4 — Migrate client constructors

#### API Key authentication

```csharp
// BEFORE
var client = new AzureOpenAIClient(
    new Uri(endpoint),
    new AzureKeyCredential(apiKey));
var chatClient = client.GetChatClient(deploymentName);

// AFTER
var credential = new ApiKeyCredential(apiKey);
var clientOptions = new OpenAIClientOptions
{
    Endpoint = new Uri($"{endpoint.TrimEnd('/')}/openai/v1/")
};
var responsesClient = new ResponsesClient(credential, clientOptions);
```

#### EntraID / DefaultAzureCredential

```csharp
// BEFORE
var client = new AzureOpenAIClient(
    new Uri(endpoint),
    new DefaultAzureCredential());
var chatClient = client.GetChatClient(deploymentName);

// AFTER
var policy = new BearerTokenPolicy(
    new DefaultAzureCredential(),
    "https://cognitiveservices.azure.com/.default");
var clientOptions = new OpenAIClientOptions
{
    Endpoint = new Uri($"{endpoint.TrimEnd('/')}/openai/v1/")
};
var responsesClient = new ResponsesClient(policy, clientOptions);
```

### Step 5 — Migrate API calls

#### Parameter mapping

| Chat Completions (old) | Responses API (new) | Notes |
|---|---|---|
| `messages` (list of `ChatMessage`) | `input` (string or list of `ResponseItem`) | Use `ResponseItem.CreateUserMessageItem()` etc. |
| `model` (via `GetChatClient(name)`) | `model` (string parameter on `CreateResponseAsync`) | Pass model name directly |
| `MaxOutputTokenCount` / `MaxTokens` | `MaxOutputTokenCount` (on `CreateResponseOptions`) | Same name, different class |
| `Temperature` | `Temperature` (on `CreateResponseOptions`) | Only if model supports it |
| `TopP` | `TopP` (on `CreateResponseOptions`) | Not supported on o-series |
| `Seed` | ❌ **Remove** | Not supported in Responses API |
| `ResponseFormat` (JSON) | `CreateResponseOptions` with structured output | See cheat sheet |
| `StopSequences` | `StopSequences` (on `CreateResponseOptions`) | Same concept |
| `FrequencyPenalty` | `FrequencyPenalty` (on `CreateResponseOptions`) | Same concept |
| `PresencePenalty` | `PresencePenalty` (on `CreateResponseOptions`) | Same concept |

#### Basic completion

```csharp
// BEFORE
ChatCompletion response = await chatClient.CompleteChatAsync(
    new ChatMessage[]
    {
        new SystemChatMessage("You are a helpful assistant."),
        new UserChatMessage("Hello!")
    });
Console.WriteLine(response.Content[0].Text);

// AFTER
var messages = new List<ResponseItem>
{
    ResponseItem.CreateSystemMessageItem("You are a helpful assistant."),
    ResponseItem.CreateUserMessageItem("Hello!")
};
var options = new CreateResponseOptions("gpt-5-mini", messages)
{
    MaxOutputTokenCount = 1000
};
ResponseResult response = await responsesClient.CreateResponseAsync(options);
Console.WriteLine(response.GetOutputText());
```

#### Simple text input

```csharp
// AFTER — simple text (no conversation)
ResponseResult response = await responsesClient.CreateResponseAsync(
    "gpt-5-mini", "Explain quantum computing in simple terms", null);
Console.WriteLine(response.GetOutputText());
```

### Step 6 — Migrate response shapes

| Before | After |
|---|---|
| `response.Content[0].Text` | `response.GetOutputText()` |
| `response.Usage.InputTokenCount` | `response.Usage.InputTokenCount` |
| `response.Usage.OutputTokenCount` | `response.Usage.OutputTokenCount` |
| `response.Usage.TotalTokenCount` | `response.Usage.TotalTokenCount` |
| `response.FinishReason` | `response.Status` (`completed`, `failed`, etc.) |
| `response.Role` | N/A — output is always assistant |
| `response.Id` | `response.Id` |

### Step 7 — Migrate streaming

```csharp
// BEFORE
await foreach (StreamingChatCompletionUpdate update
    in chatClient.CompleteChatStreamingAsync(messages))
{
    foreach (ChatMessageContentPart part in update.ContentUpdate)
    {
        Console.Write(part.Text);
    }
}

// AFTER
var options = new CreateResponseOptions("gpt-5-mini", messages)
{
    MaxOutputTokenCount = 1000
};
await foreach (ResponseUpdate update
    in responsesClient.CreateResponseStreamingAsync(options))
{
    if (update is ResponseContentPartDeltaUpdate deltaUpdate)
    {
        Console.Write(deltaUpdate.Delta);
    }
}
```

### Step 8 — Migrate tests

See the [test-migration reference](references/test-migration.md) for detailed patterns.

Key changes:
- Replace `ChatCompletion` mocks with `ResponseResult` mocks
- Replace `ChatCompletionChunk` / streaming mocks with `ResponseUpdate` mocks
- Update assertions: `.Content[0].Text` → `.GetOutputText()`
- Update type checks: `ChatClient` → `ResponsesClient`

### Step 9 — Clean up configuration

1. **Remove** `AZURE_OPENAI_API_VERSION` from:
   - `appsettings.json` / `appsettings.Development.json`
   - Environment variables in Bicep/ARM templates
   - `.env` files / launchSettings.json
   - Docker/container configurations

2. **Keep** `AZURE_OPENAI_ENDPOINT` — still needed for the base URL.

3. **Keep** `AZURE_OPENAI_DEPLOYMENT` or pass the model name directly.

4. **Keep** `AZURE_CLIENT_ID` if using managed identity.

### Step 10 — Verify

1. Run the scanner — should report zero hits:
   ```powershell
   .\.github\skills\azure-openai-to-responses-csharp\scripts\Detect-LegacyOpenAI.ps1 -Path <target>
   ```

2. Build the project:
   ```powershell
   dotnet build
   ```

3. Run tests:
   ```powershell
   dotnet test
   ```

## Acceptance criteria

### Code
- [ ] No `Azure.AI.OpenAI` package references remain
- [ ] No `AzureOpenAIClient` or `GetChatClient` calls remain
- [ ] No `CompleteChatAsync` / `CompleteChatStreamingAsync` calls remain
- [ ] No `ChatCompletion` / `ChatMessage` / `SystemChatMessage` / `UserChatMessage` types remain
- [ ] No `response.Content[0].Text` or `choices[0]` patterns remain
- [ ] No `api_version` / `AZURE_OPENAI_API_VERSION` references remain
- [ ] All files using Responses API have `#pragma warning disable OPENAI001`
- [ ] Scanner reports zero legacy hits

### Tests
- [ ] All existing tests pass with the new SDK
- [ ] Mocks updated for `ResponseResult` / `ResponseUpdate`
- [ ] No references to `ChatCompletion` types in test files

### Behavioral
- [ ] App produces same user-visible output
- [ ] Streaming still works if it was streaming before
- [ ] Authentication method preserved (API key or EntraID)
- [ ] Error handling covers new exception types

## References

- [Cheat sheet](references/cheat-sheet.md) — All C# code patterns in one place
- [Test migration](references/test-migration.md) — Mock and assertion update guide
- [Troubleshooting](references/troubleshooting.md) — Common errors and fixes

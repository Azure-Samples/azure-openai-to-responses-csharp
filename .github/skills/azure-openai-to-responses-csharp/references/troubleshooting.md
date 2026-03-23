# Troubleshooting — C# / .NET Migration

> Common errors, risk table, and gotchas when migrating from Azure OpenAI SDK to OpenAI Responses API.

## Common errors

### `OPENAI001: ResponsesClient is experimental`

**Symptom:** Build warning CS0618 or error about experimental API.

**Fix:** Add at the top of each file using the Responses API:
```csharp
#pragma warning disable OPENAI001
```

Or in your `.csproj`:
```xml
<PropertyGroup>
    <NoWarn>$(NoWarn);OPENAI001</NoWarn>
</PropertyGroup>
```

---

### `404 Not Found` when calling CreateResponseAsync

**Symptom:** `ClientResultException` with 404 status.

**Cause:** The base URL is wrong — missing `/openai/v1/` suffix.

**Fix:** Ensure your endpoint URL ends with `/openai/v1/`:
```csharp
Endpoint = new Uri($"{endpoint.TrimEnd('/')}/openai/v1/")
```

---

### `401 Unauthorized` with EntraID

**Symptom:** `ClientResultException` with 401 status when using `BearerTokenPolicy`.

**Causes:**
1. The `DefaultAzureCredential` can't find a valid credential (not logged in to `az login`, `azd auth login`, etc.)
2. The user/service principal lacks the `Cognitive Services User` role on the Azure OpenAI resource
3. Wrong scope string

**Fix:**
```csharp
// Ensure correct scope
var policy = new BearerTokenPolicy(
    new DefaultAzureCredential(),
    "https://cognitiveservices.azure.com/.default");  // Must be exactly this
```

Check role assignment:
```powershell
az role assignment create `
    --assignee YOUR_PRINCIPAL_ID `
    --role "Cognitive Services User" `
    --scope /subscriptions/SUB_ID/resourceGroups/RG/providers/Microsoft.CognitiveServices/accounts/ACCOUNT
```

---

### `400 Bad Request: max_output_tokens must be >= 16`

**Symptom:** 400 error when `MaxOutputTokenCount` is too low.

**Fix:** Set `MaxOutputTokenCount` to at least 16. For reasoning models, use 1000+:
```csharp
var options = new CreateResponseOptions("gpt-5-mini", items)
{
    MaxOutputTokenCount = 1000  // Not 50 or 100 — reasoning needs more
};
```

---

### `400 Bad Request: temperature must be 1` (o-series)

**Symptom:** 400 error when using o1, o3-mini, o3, or o4-mini with Temperature set to non-1.

**Fix:** Remove `Temperature` setting for o-series models, or set it to exactly `1f`:
```csharp
var options = new CreateResponseOptions("o4-mini", items)
{
    MaxOutputTokenCount = 4096
    // Do NOT set Temperature
};
```

---

### `400 Bad Request: Unsupported parameter 'seed'`

**Symptom:** 400 error mentioning unsupported `seed` parameter.

**Fix:** Remove `Seed` from the options. The Responses API does not support `Seed`:
```csharp
// ❌ Remove this
// options.Seed = 42;
```

---

### `NullReferenceException` on `response.GetOutputText()`

**Symptom:** Null reference when accessing the output text.

**Cause:** The response may have failed or been filtered.

**Fix:** Check `response.Status` before accessing output:
```csharp
var response = await responsesClient.CreateResponseAsync(options);
if (response.Status == ResponseResultStatus.Completed)
{
    Console.WriteLine(response.GetOutputText());
}
else
{
    Console.Error.WriteLine($"Response failed with status: {response.Status}");
}
```

---

### Missing `System.ClientModel` namespace

**Symptom:** `ApiKeyCredential` or `ClientResultException` not found.

**Fix:** The `System.ClientModel` package is a transitive dependency of `OpenAI`. If it's not resolved, add it explicitly:
```xml
<PackageReference Include="System.ClientModel" Version="1.*" />
```

And add the using:
```csharp
using System.ClientModel;
```

---

### `BearerTokenPolicy` not found

**Symptom:** Cannot resolve `BearerTokenPolicy` type.

**Fix:** Add the correct using:
```csharp
using System.ClientModel.Primitives;
```

This is in the `System.ClientModel` package, which is a transitive dependency of `OpenAI`.

---

## Risk table

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Model doesn't support Responses API | Low | High | Run `.\migrate.ps1 models` to check before migrating |
| Streaming event shape breaks frontend | Medium | Medium | Only affects apps where frontend parses raw OpenAI events |
| `Seed` removal changes output determinism | Low | Low | `Seed` was never fully deterministic anyway |
| Token count differences | Low | Low | Reasoning tokens may differ; monitor costs |
| `api_version` removal breaks other services | Low | Medium | Only remove from OpenAI-specific config, not other Azure services |
| Test mocks break | High | Medium | Budget time for test rewrites; use interfaces |
| Content filter behavior changes | Low | Medium | Test with production-like prompts |

## Gotchas

1. **`#pragma warning disable OPENAI001` is required.** The Responses API is marked experimental in the .NET SDK. Every file using `ResponsesClient`, `ResponseResult`, etc. needs this pragma.

2. **Don't mix `Azure.AI.OpenAI` and direct `OpenAI` Responses API in the same file.** Complete the migration per-file. The namespaces conflict.

3. **The `/openai/v1/` path is critical.** If you forget the trailing slash or use the wrong path, you'll get 404 errors.

4. **`ResponseResult` vs `ClientResult<ResponseResult>`.** Depending on the SDK version, `CreateResponseAsync` may return `ClientResult<ResponseResult>`. Access with `.Value` if needed.

5. **Streaming uses different types.** `StreamingChatCompletionUpdate` → `ResponseUpdate`. The delta is in `ResponseContentPartDeltaUpdate.Delta`, not `ContentUpdate[i].Text`.

6. **`AssistantChatMessage(ChatCompletion)` constructor is gone.** In multi-turn conversations, use `ResponseItem.CreateAssistantMessageItem(response.GetOutputText())` instead.

7. **O-series models don't support system messages.** Move system instructions into the first user message.

8. **`MaxOutputTokenCount` means something different for reasoning models.** Reasoning tokens are internal and counted separately. Set this higher (1000+) to leave room for both reasoning and output.

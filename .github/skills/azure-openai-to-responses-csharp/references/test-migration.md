# Test Migration Guide — C# / .NET

> How to update unit tests, integration tests, mocks, and assertions when migrating
> from `Azure.AI.OpenAI` Chat Completions to `OpenAI` Responses API.

## Overview

| Before (Chat Completions) | After (Responses API) |
|---|---|
| `ChatCompletion` | `ResponseResult` |
| `StreamingChatCompletionUpdate` | `ResponseUpdate` / `ResponseContentPartDeltaUpdate` |
| `ChatMessage` / `SystemChatMessage` / `UserChatMessage` | `ResponseItem` |
| `ChatClient` | `ResponsesClient` |
| `AzureOpenAIClient` | N/A — use `ResponsesClient` directly |
| `response.Content[0].Text` | `response.GetOutputText()` |
| `response.FinishReason == ChatFinishReason.Stop` | `response.Status == ResponseResultStatus.Completed` |

---

## Mocking the ResponsesClient

### Using Moq

```csharp
// ❌ BEFORE — Mocking ChatClient
var mockChatClient = new Mock<ChatClient>();
// ChatClient.CompleteChatAsync is complex to mock due to sealed types

// ✅ AFTER — Approach: Abstract behind an interface
public interface IChatService
{
    Task<string> GetResponseAsync(string userMessage);
    IAsyncEnumerable<string> GetStreamingResponseAsync(string userMessage);
}

// Production implementation
public class ResponsesApiChatService : IChatService
{
    private readonly ResponsesClient _client;
    private readonly string _model;

    public ResponsesApiChatService(ResponsesClient client, string model)
    {
        _client = client;
        _model = model;
    }

    public async Task<string> GetResponseAsync(string userMessage)
    {
        var response = await _client.CreateResponseAsync(_model, userMessage, null);
        return response.GetOutputText();
    }

    public async IAsyncEnumerable<string> GetStreamingResponseAsync(string userMessage)
    {
        var items = new List<ResponseItem>
        {
            ResponseItem.CreateUserMessageItem(userMessage)
        };
        var options = new CreateResponseOptions(_model, items) { MaxOutputTokenCount = 1000 };
        await foreach (var update in _client.CreateResponseStreamingAsync(options))
        {
            if (update is ResponseContentPartDeltaUpdate delta)
            {
                yield return delta.Delta;
            }
        }
    }
}

// Test mock
var mockService = new Mock<IChatService>();
mockService
    .Setup(s => s.GetResponseAsync(It.IsAny<string>()))
    .ReturnsAsync("Paris");
```

### Integration test with WebApplicationFactory

```csharp
// ❌ BEFORE
public class ChatEndpointTests : IClassFixture<WebApplicationFactory<Program>>
{
    [Fact]
    public async Task Chat_ReturnsResponse()
    {
        // Setup with mocked ChatClient
        var client = _factory.CreateClient();
        var response = await client.PostAsJsonAsync("/chat", new
        {
            messages = new[] { new { role = "user", content = "Hello" } }
        });
        response.EnsureSuccessStatusCode();
        var body = await response.Content.ReadFromJsonAsync<ChatResponse>();
        Assert.NotNull(body?.Content);
    }
}

// ✅ AFTER
public class ChatEndpointTests : IClassFixture<WebApplicationFactory<Program>>
{
    [Fact]
    public async Task Chat_ReturnsResponse()
    {
        // Setup with mocked IChatService
        var client = _factory.WithWebHostBuilder(builder =>
        {
            builder.ConfigureServices(services =>
            {
                services.AddSingleton<IChatService>(new MockChatService("Hello back!"));
            });
        }).CreateClient();

        var response = await client.PostAsJsonAsync("/chat", new
        {
            messages = new[] { new { role = "user", content = "Hello" } }
        });
        response.EnsureSuccessStatusCode();
        var body = await response.Content.ReadFromJsonAsync<ChatResponse>();
        Assert.Equal("Hello back!", body?.Content);
    }
}
```

---

## Assertion updates

### Response content

```csharp
// ❌ BEFORE
Assert.Equal("expected", response.Content[0].Text);
Assert.Equal(ChatFinishReason.Stop, response.FinishReason);
Assert.Equal(ChatMessageRole.Assistant, response.Role);

// ✅ AFTER
Assert.Equal("expected", response.GetOutputText());
Assert.Equal(ResponseResultStatus.Completed, response.Status);
// Role is implicitly assistant — no assertion needed
```

### Token usage

```csharp
// ❌ BEFORE
Assert.True(response.Usage.InputTokenCount > 0);
Assert.True(response.Usage.OutputTokenCount > 0);

// ✅ AFTER
Assert.True(response.Usage.InputTokenCount > 0);
Assert.True(response.Usage.OutputTokenCount > 0);
// NEW: reasoning tokens available
Assert.True(response.Usage.OutputTokenDetails.ReasoningTokenCount >= 0);
```

### Type checks

```csharp
// ❌ BEFORE
Assert.IsType<ChatClient>(services.GetRequiredService<ChatClient>());

// ✅ AFTER
Assert.IsType<ResponsesClient>(services.GetRequiredService<ResponsesClient>());
```

---

## Streaming test patterns

```csharp
// ❌ BEFORE — Testing streaming
[Fact]
public async Task Stream_ProducesContent()
{
    var chunks = new List<string>();
    await foreach (var update in chatClient.CompleteChatStreamingAsync(messages))
    {
        foreach (var part in update.ContentUpdate)
        {
            chunks.Add(part.Text);
        }
    }
    Assert.NotEmpty(chunks);
    Assert.Contains(chunks, c => !string.IsNullOrEmpty(c));
}

// ✅ AFTER
[Fact]
public async Task Stream_ProducesContent()
{
    var options = new CreateResponseOptions("gpt-5-mini", items)
    {
        MaxOutputTokenCount = 200
    };
    var chunks = new List<string>();
    await foreach (var update in responsesClient.CreateResponseStreamingAsync(options))
    {
        if (update is ResponseContentPartDeltaUpdate delta)
        {
            chunks.Add(delta.Delta);
        }
    }
    Assert.NotEmpty(chunks);
    Assert.Contains(chunks, c => !string.IsNullOrEmpty(c));
}
```

---

## xUnit / NUnit / MSTest compatibility

The migration patterns work with all .NET test frameworks. The key changes are the same:

1. Replace `ChatCompletion` references with `ResponseResult`
2. Replace `ChatClient` references with `ResponsesClient`
3. Update response access from `.Content[0].Text` to `.GetOutputText()`
4. Update streaming from `StreamingChatCompletionUpdate` to `ResponseUpdate`
5. Consider abstracting behind interfaces for better testability

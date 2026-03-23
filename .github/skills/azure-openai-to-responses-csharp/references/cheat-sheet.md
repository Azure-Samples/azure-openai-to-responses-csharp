# C# Migration Cheat Sheet — Chat Completions → Responses API

> Copy-paste C# code for every migration pattern. Each section shows **Before** and **After**.

## Table of Contents

1. [Client Constructors](#1-client-constructors)
2. [Basic Completion](#2-basic-completion)
3. [Conversation Format](#3-conversation-format)
4. [Streaming](#4-streaming)
5. [Structured Output (JSON)](#5-structured-output-json)
6. [Tool / Function Calling](#6-tool--function-calling)
7. [Multi-Turn Conversation](#7-multi-turn-conversation)
8. [EntraID Authentication](#8-entraid-authentication)
9. [Error Handling](#9-error-handling)
10. [ASP.NET Core Integration](#10-aspnet-core-integration)
11. [Dependency Injection](#11-dependency-injection)
12. [Configuration / appsettings.json](#12-configuration--appsettingsjson)
13. [O-Series Reasoning Models](#13-o-series-reasoning-models)

---

## 1. Client Constructors

### API Key

```csharp
// ❌ BEFORE
using Azure;
using Azure.AI.OpenAI;
using OpenAI.Chat;

var client = new AzureOpenAIClient(
    new Uri(endpoint),
    new AzureKeyCredential(apiKey));
var chatClient = client.GetChatClient(deploymentName);

// ✅ AFTER
using System.ClientModel;
using OpenAI;
using OpenAI.Responses;

#pragma warning disable OPENAI001

var credential = new ApiKeyCredential(apiKey);
var clientOptions = new OpenAIClientOptions
{
    Endpoint = new Uri($"{endpoint.TrimEnd('/')}/openai/v1/")
};
var responsesClient = new ResponsesClient(credential, clientOptions);
```

### DefaultAzureCredential (EntraID)

```csharp
// ❌ BEFORE
using Azure.Identity;
using Azure.AI.OpenAI;
using OpenAI.Chat;

var client = new AzureOpenAIClient(
    new Uri(endpoint),
    new DefaultAzureCredential());
var chatClient = client.GetChatClient(deploymentName);

// ✅ AFTER
using System.ClientModel.Primitives;
using Azure.Identity;
using OpenAI;
using OpenAI.Responses;

#pragma warning disable OPENAI001

var policy = new BearerTokenPolicy(
    new DefaultAzureCredential(),
    "https://cognitiveservices.azure.com/.default");
var clientOptions = new OpenAIClientOptions
{
    Endpoint = new Uri($"{endpoint.TrimEnd('/')}/openai/v1/")
};
var responsesClient = new ResponsesClient(policy, clientOptions);
```

---

## 2. Basic Completion

```csharp
// ❌ BEFORE
ChatCompletion response = await chatClient.CompleteChatAsync(
    new ChatMessage[]
    {
        new UserChatMessage("What is the capital of France?")
    });
string answer = response.Content[0].Text;

// ✅ AFTER
ResponseResult response = await responsesClient.CreateResponseAsync(
    "gpt-5-mini", "What is the capital of France?", null);
string answer = response.GetOutputText();
```

---

## 3. Conversation Format

```csharp
// ❌ BEFORE
var messages = new List<ChatMessage>
{
    new SystemChatMessage("You are a helpful assistant."),
    new UserChatMessage("Tell me about Azure.")
};
ChatCompletion response = await chatClient.CompleteChatAsync(messages);
Console.WriteLine(response.Content[0].Text);

// ✅ AFTER
var messages = new List<ResponseItem>
{
    ResponseItem.CreateSystemMessageItem("You are a helpful assistant."),
    ResponseItem.CreateUserMessageItem("Tell me about Azure.")
};
var options = new CreateResponseOptions("gpt-5-mini", messages)
{
    MaxOutputTokenCount = 1000
};
ResponseResult response = await responsesClient.CreateResponseAsync(options);
Console.WriteLine(response.GetOutputText());
```

---

## 4. Streaming

```csharp
// ❌ BEFORE
await foreach (StreamingChatCompletionUpdate update
    in chatClient.CompleteChatStreamingAsync(messages))
{
    foreach (ChatMessageContentPart part in update.ContentUpdate)
    {
        Console.Write(part.Text);
    }
}

// ✅ AFTER
var options = new CreateResponseOptions("gpt-5-mini", responseItems)
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
Console.WriteLine();
```

---

## 5. Structured Output (JSON)

```csharp
// ❌ BEFORE
var options = new ChatCompletionOptions
{
    ResponseFormat = ChatResponseFormat.CreateJsonSchemaFormat(
        "CapitalAnswer",
        BinaryData.FromString("""
        {
            "type": "object",
            "properties": {
                "country": { "type": "string" },
                "capital": { "type": "string" }
            },
            "required": ["country", "capital"],
            "additionalProperties": false
        }
        """),
        jsonSchemaIsStrict: true)
};
ChatCompletion response = await chatClient.CompleteChatAsync(messages, options);
string json = response.Content[0].Text;

// ✅ AFTER
var options = new CreateResponseOptions("gpt-5-mini", responseItems)
{
    MaxOutputTokenCount = 500
};
options.OutputFormat = ResponseOutputFormat.CreateJsonSchemaFormat(
    "CapitalAnswer",
    BinaryData.FromString("""
    {
        "type": "object",
        "properties": {
            "country": { "type": "string" },
            "capital": { "type": "string" }
        },
        "required": ["country", "capital"],
        "additionalProperties": false
    }
    """),
    jsonSchemaIsStrict: true);
ResponseResult response = await responsesClient.CreateResponseAsync(options);
string json = response.GetOutputText();
```

---

## 6. Tool / Function Calling

```csharp
// ❌ BEFORE
var tools = new List<ChatTool>
{
    ChatTool.CreateFunctionTool(
        "get_weather",
        "Gets the current weather for a city",
        BinaryData.FromString("""
        {
            "type": "object",
            "properties": {
                "city": { "type": "string" }
            },
            "required": ["city"]
        }
        """))
};
var options = new ChatCompletionOptions();
foreach (var tool in tools) options.Tools.Add(tool);
ChatCompletion response = await chatClient.CompleteChatAsync(messages, options);

if (response.FinishReason == ChatFinishReason.ToolCalls)
{
    foreach (var toolCall in response.ToolCalls)
    {
        // Handle tool call
        Console.WriteLine($"Tool: {toolCall.FunctionName}, Args: {toolCall.FunctionArguments}");
    }
}

// ✅ AFTER
var options = new CreateResponseOptions("gpt-5-mini", responseItems)
{
    MaxOutputTokenCount = 1000
};
options.Tools.Add(ResponseTool.CreateFunctionTool(
    "get_weather",
    "Gets the current weather for a city",
    BinaryData.FromString("""
    {
        "type": "object",
        "properties": {
            "city": { "type": "string" }
        },
        "required": ["city"]
    }
    """)));
ResponseResult response = await responsesClient.CreateResponseAsync(options);
// Check output items for function calls
foreach (var item in response.OutputItems)
{
    if (item is FunctionCallItem functionCall)
    {
        Console.WriteLine($"Tool: {functionCall.Name}, Args: {functionCall.Arguments}");
    }
}
```

---

## 7. Multi-Turn Conversation

```csharp
// ❌ BEFORE
var messages = new List<ChatMessage>
{
    new SystemChatMessage("You are a math tutor. Be concise."),
    new UserChatMessage("What is 2+2?")
};
ChatCompletion resp1 = await chatClient.CompleteChatAsync(messages);
messages.Add(new AssistantChatMessage(resp1));
messages.Add(new UserChatMessage("Now multiply that by 3."));
ChatCompletion resp2 = await chatClient.CompleteChatAsync(messages);

// ✅ AFTER
var messages = new List<ResponseItem>
{
    ResponseItem.CreateSystemMessageItem("You are a math tutor. Be concise."),
    ResponseItem.CreateUserMessageItem("What is 2+2?")
};
var opts1 = new CreateResponseOptions("gpt-5-mini", messages) { MaxOutputTokenCount = 100 };
ResponseResult resp1 = await responsesClient.CreateResponseAsync(opts1);
string answer1 = resp1.GetOutputText();

messages.Add(ResponseItem.CreateAssistantMessageItem(answer1));
messages.Add(ResponseItem.CreateUserMessageItem("Now multiply that by 3."));

var opts2 = new CreateResponseOptions("gpt-5-mini", messages) { MaxOutputTokenCount = 100 };
ResponseResult resp2 = await responsesClient.CreateResponseAsync(opts2);
Console.WriteLine(resp2.GetOutputText());
```

---

## 8. EntraID Authentication

### Managed Identity (Azure Container Apps, App Service, etc.)

```csharp
// ✅ AFTER — Managed Identity
using System.ClientModel.Primitives;
using Azure.Identity;
using OpenAI;
using OpenAI.Responses;

#pragma warning disable OPENAI001

var clientId = Environment.GetEnvironmentVariable("AZURE_CLIENT_ID");
var credential = clientId != null
    ? new ManagedIdentityCredential(clientId)
    : new DefaultAzureCredential();

var policy = new BearerTokenPolicy(
    credential,
    "https://cognitiveservices.azure.com/.default");
var clientOptions = new OpenAIClientOptions
{
    Endpoint = new Uri($"{endpoint.TrimEnd('/')}/openai/v1/")
};
var responsesClient = new ResponsesClient(policy, clientOptions);
```

### ChainedTokenCredential (local dev + production)

```csharp
// ✅ AFTER — Chained credential
using Azure.Identity;
using System.ClientModel.Primitives;
using OpenAI;
using OpenAI.Responses;

#pragma warning disable OPENAI001

var credential = new ChainedTokenCredential(
    new ManagedIdentityCredential(Environment.GetEnvironmentVariable("AZURE_CLIENT_ID")),
    new AzureDeveloperCliCredential());

var policy = new BearerTokenPolicy(
    credential,
    "https://cognitiveservices.azure.com/.default");
var clientOptions = new OpenAIClientOptions
{
    Endpoint = new Uri($"{endpoint.TrimEnd('/')}/openai/v1/")
};
var responsesClient = new ResponsesClient(policy, clientOptions);
```

---

## 9. Error Handling

```csharp
// ❌ BEFORE
try
{
    ChatCompletion response = await chatClient.CompleteChatAsync(messages);
}
catch (ClientResultException ex) when (ex.Status == 429)
{
    // Rate limited
}
catch (ClientResultException ex) when (ex.Status == 400)
{
    // Bad request (e.g., content filter)
}

// ✅ AFTER
try
{
    ResponseResult response = await responsesClient.CreateResponseAsync(options);
    if (response.Status != ResponseResultStatus.Completed)
    {
        Console.Error.WriteLine($"Response status: {response.Status}");
    }
}
catch (ClientResultException ex) when (ex.Status == 429)
{
    // Rate limited — same pattern
}
catch (ClientResultException ex) when (ex.Status == 400)
{
    // Bad request — same pattern
}
```

---

## 10. ASP.NET Core Integration

### Minimal API endpoint

```csharp
// ❌ BEFORE
app.MapPost("/chat", async (ChatRequest request, ChatClient chatClient) =>
{
    var messages = request.Messages.Select<MessageDto, ChatMessage>(m => m.Role switch
    {
        "system" => new SystemChatMessage(m.Content),
        "user" => new UserChatMessage(m.Content),
        "assistant" => new AssistantChatMessage(m.Content),
        _ => new UserChatMessage(m.Content)
    }).ToList();

    var response = await chatClient.CompleteChatAsync(messages);
    return Results.Ok(new { content = response.Content[0].Text });
});

// ✅ AFTER
app.MapPost("/chat", async (ChatRequest request, ResponsesClient responsesClient) =>
{
    var items = request.Messages.Select<MessageDto, ResponseItem>(m => m.Role switch
    {
        "system" => ResponseItem.CreateSystemMessageItem(m.Content),
        "user" => ResponseItem.CreateUserMessageItem(m.Content),
        "assistant" => ResponseItem.CreateAssistantMessageItem(m.Content),
        _ => ResponseItem.CreateUserMessageItem(m.Content)
    }).ToList();

    var options = new CreateResponseOptions("gpt-5-mini", items)
    {
        MaxOutputTokenCount = 1000
    };
    var response = await responsesClient.CreateResponseAsync(options);
    return Results.Ok(new { content = response.GetOutputText() });
});
```

### Streaming SSE endpoint

```csharp
// ✅ AFTER — Streaming in ASP.NET Core
app.MapPost("/chat/stream", async (ChatRequest request, ResponsesClient responsesClient, HttpResponse httpResponse) =>
{
    httpResponse.ContentType = "text/event-stream";

    var items = request.Messages.Select<MessageDto, ResponseItem>(m => m.Role switch
    {
        "system" => ResponseItem.CreateSystemMessageItem(m.Content),
        "user" => ResponseItem.CreateUserMessageItem(m.Content),
        "assistant" => ResponseItem.CreateAssistantMessageItem(m.Content),
        _ => ResponseItem.CreateUserMessageItem(m.Content)
    }).ToList();

    var options = new CreateResponseOptions("gpt-5-mini", items)
    {
        MaxOutputTokenCount = 1000
    };

    await foreach (var update in responsesClient.CreateResponseStreamingAsync(options))
    {
        if (update is ResponseContentPartDeltaUpdate deltaUpdate)
        {
            var json = System.Text.Json.JsonSerializer.Serialize(
                new { delta = new { content = deltaUpdate.Delta } });
            await httpResponse.WriteAsync($"data: {json}\n\n");
            await httpResponse.Body.FlushAsync();
        }
    }
    await httpResponse.WriteAsync("data: [DONE]\n\n");
});
```

---

## 11. Dependency Injection

```csharp
// ❌ BEFORE — in Program.cs / Startup.cs
builder.Services.AddSingleton(sp =>
{
    var endpoint = builder.Configuration["AzureOpenAI:Endpoint"]!;
    var client = new AzureOpenAIClient(
        new Uri(endpoint),
        new DefaultAzureCredential());
    return client.GetChatClient(builder.Configuration["AzureOpenAI:Deployment"]!);
});

// ✅ AFTER
builder.Services.AddSingleton(sp =>
{
    var endpoint = builder.Configuration["AzureOpenAI:Endpoint"]!;
    var policy = new BearerTokenPolicy(
        new DefaultAzureCredential(),
        "https://cognitiveservices.azure.com/.default");
    var clientOptions = new OpenAIClientOptions
    {
        Endpoint = new Uri($"{endpoint.TrimEnd('/')}/openai/v1/")
    };
    return new ResponsesClient(policy, clientOptions);
});
```

---

## 12. Configuration / appsettings.json

```jsonc
// ❌ BEFORE
{
  "AzureOpenAI": {
    "Endpoint": "https://myresource.openai.azure.com/",
    "Deployment": "gpt-4o",
    "ApiVersion": "2024-12-01-preview"  // REMOVE THIS
  }
}

// ✅ AFTER
{
  "AzureOpenAI": {
    "Endpoint": "https://myresource.openai.azure.com/",
    "Model": "gpt-5-mini"
    // No ApiVersion needed — /openai/v1/ is stable
  }
}
```

---

## 13. O-Series Reasoning Models (o1, o3-mini, o3, o4-mini)

O-series models have specific constraints:

```csharp
// ✅ AFTER — O-series model
var messages = new List<ResponseItem>
{
    ResponseItem.CreateUserMessageItem("Solve this step by step: What is 15% of 280?")
    // NOTE: System messages are NOT supported on o-series — use user messages instead
};
var options = new CreateResponseOptions("o4-mini", messages)
{
    MaxOutputTokenCount = 4096,  // Must be 4096+ for o-series
    // Do NOT set Temperature (must be 1, which is default)
    // Do NOT set TopP (not supported)
};
// For reasoning effort control:
// options.Reasoning = new ResponseReasoningOptions { Effort = "medium" };
ResponseResult response = await responsesClient.CreateResponseAsync(options);
Console.WriteLine(response.GetOutputText());
Console.WriteLine($"Reasoning tokens: {response.Usage.OutputTokenDetails.ReasoningTokenCount}");
```

**O-series constraints summary:**
- `Temperature` must be omitted or `1`
- `TopP` not supported
- `MaxOutputTokenCount` must be `4096` or higher
- System messages not supported (use user messages instead)
- `Seed` not supported

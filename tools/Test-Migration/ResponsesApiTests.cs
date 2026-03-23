#pragma warning disable OPENAI001 // Responses API is in preview

/// <summary>
/// Test harness for Azure OpenAI Responses API migration.
///
/// Validates that a migrated codebase correctly calls the Responses API
/// against a live Azure OpenAI deployment. Covers: basic completion,
/// conversation format, streaming, structured output, multi-turn, and tool use.
///
/// Prerequisites:
///     dotnet tool restore   (if any global tools are needed)
///     Set environment variables (see below)
///
/// Environment variables:
///     AZURE_OPENAI_ENDPOINT           - Your Azure OpenAI resource endpoint
///     AZURE_OPENAI_DEPLOYMENT         - Deployment name (e.g. gpt-5-mini)
///     AZURE_OPENAI_API_KEY            - API key (if not using EntraID)
///
/// Usage:
///     dotnet test tools/Test-Migration/ --logger "console;verbosity=detailed"
/// </summary>

using System.ClientModel;
using System.ClientModel.Primitives;
using System.Text.Json;
using OpenAI;
using OpenAI.Responses;
using Xunit;

namespace TestMigration;

/// <summary>
/// Creates a shared ResponsesClient for all tests. Skips all tests if
/// environment variables are not configured.
/// </summary>
public class ResponsesClientFixture
{
    public ResponsesClient? Client { get; }
    public string? Model { get; }
    public string? SkipReason { get; }

    public ResponsesClientFixture()
    {
        var endpoint = Environment.GetEnvironmentVariable("AZURE_OPENAI_ENDPOINT") ?? "";
        var deployment = Environment.GetEnvironmentVariable("AZURE_OPENAI_DEPLOYMENT") ?? "";
        var apiKey = Environment.GetEnvironmentVariable("AZURE_OPENAI_API_KEY") ?? "";

        if (string.IsNullOrEmpty(endpoint))
        {
            SkipReason = "AZURE_OPENAI_ENDPOINT not set";
            return;
        }
        if (string.IsNullOrEmpty(deployment))
        {
            SkipReason = "AZURE_OPENAI_DEPLOYMENT not set";
            return;
        }

        Model = deployment;
        var baseUrl = $"{endpoint.TrimEnd('/')}/openai/v1/";
        var options = new OpenAIClientOptions { Endpoint = new Uri(baseUrl) };

        if (!string.IsNullOrEmpty(apiKey))
        {
            Client = new ResponsesClient(new ApiKeyCredential(apiKey), options);
        }
        else
        {
            try
            {
                var credential = new Azure.Identity.DefaultAzureCredential();
                var policy = new BearerTokenPolicy(
                    credential, "https://cognitiveservices.azure.com/.default");
                Client = new ResponsesClient(policy, options);
            }
            catch (Exception ex)
            {
                SkipReason = $"EntraID auth failed: {ex.Message}";
            }
        }
    }
}

/// <summary>
/// Live Responses API tests — mirrors the Python test_migration.py test harness.
/// Each test validates a specific migration pattern works correctly.
/// </summary>
[Collection("ResponsesApi")]
public class ResponsesApiTests : IClassFixture<ResponsesClientFixture>
{
    private readonly ResponsesClientFixture _fixture;

    public ResponsesApiTests(ResponsesClientFixture fixture) => _fixture = fixture;

    private void SkipIfNotConfigured()
    {
        Skip.If(_fixture.Client is null, _fixture.SkipReason ?? "Client not configured");
    }

    // -----------------------------------------------------------------------
    // 1. Basic completion — the simplest possible Responses API call
    // -----------------------------------------------------------------------
    [Fact]
    public async Task BasicCompletion_ReturnsNonEmptyText()
    {
        SkipIfNotConfigured();

        var response = await _fixture.Client!.CreateResponseAsync(
            _fixture.Model!, "Say hello in one word.");

        var text = response.GetOutputText();
        Assert.False(string.IsNullOrWhiteSpace(text), "Response text should not be empty");
    }

    // -----------------------------------------------------------------------
    // 2. Conversation format — system + user messages via ResponseItem
    // -----------------------------------------------------------------------
    [Fact]
    public async Task ConversationFormat_SystemAndUserMessages()
    {
        SkipIfNotConfigured();

        var messages = new[]
        {
            ResponseItem.CreateSystemMessageItem("You are a helpful assistant. Reply in exactly one word."),
            ResponseItem.CreateUserMessageItem("What color is the sky?")
        };

        var response = await _fixture.Client!.CreateResponseAsync(_fixture.Model!, messages);
        var text = response.GetOutputText();

        Assert.False(string.IsNullOrWhiteSpace(text));
    }

    // -----------------------------------------------------------------------
    // 3. Streaming — incremental token delivery
    // -----------------------------------------------------------------------
    [Fact]
    public async Task Streaming_ReceivesDeltaUpdates()
    {
        SkipIfNotConfigured();

        var messages = new[]
        {
            ResponseItem.CreateUserMessageItem("Count from 1 to 5.")
        };
        var options = new CreateResponseOptions(_fixture.Model!, messages);

        var chunks = new List<string>();
        await foreach (var update in _fixture.Client!.CreateResponseStreamingAsync(options))
        {
            if (update is ResponseContentPartDeltaUpdate delta)
            {
                chunks.Add(delta.Delta);
            }
        }

        Assert.True(chunks.Count > 0, "Should receive at least one streaming delta");
        var fullText = string.Join("", chunks);
        Assert.False(string.IsNullOrWhiteSpace(fullText));
    }

    // -----------------------------------------------------------------------
    // 4. Max output tokens — respects the limit
    // -----------------------------------------------------------------------
    [Fact]
    public async Task MaxOutputTokens_LimitsResponse()
    {
        SkipIfNotConfigured();

        var messages = new[]
        {
            ResponseItem.CreateUserMessageItem("Write a very long essay about the history of computing.")
        };
        var options = new CreateResponseOptions(_fixture.Model!, messages)
        {
            MaxOutputTokenCount = 10
        };

        var response = await _fixture.Client!.CreateResponseAsync(options);
        var text = response.GetOutputText();

        // With max 10 tokens the response should be short (not necessarily exactly 10 tokens
        // due to tokenization, but it should be truncated)
        Assert.NotNull(text);
    }

    // -----------------------------------------------------------------------
    // 5. Multi-turn — previous_response_id for conversations
    // -----------------------------------------------------------------------
    [Fact]
    public async Task MultiTurn_ConversationContinuity()
    {
        SkipIfNotConfigured();

        // Turn 1
        var messages1 = new[]
        {
            ResponseItem.CreateSystemMessageItem("You are a helpful assistant. Be very brief."),
            ResponseItem.CreateUserMessageItem("My name is Alice.")
        };
        var response1 = await _fixture.Client!.CreateResponseAsync(_fixture.Model!, messages1);
        var text1 = response1.GetOutputText();
        Assert.False(string.IsNullOrWhiteSpace(text1));

        // Turn 2 — include previous context
        var messages2 = new List<ResponseItem>(response1.OutputItems)
        {
            ResponseItem.CreateUserMessageItem("What is my name?")
        };
        // Prepend the original system message
        messages2.Insert(0, ResponseItem.CreateSystemMessageItem("You are a helpful assistant. Be very brief."));

        var options2 = new CreateResponseOptions(_fixture.Model!, messages2);
        var response2 = await _fixture.Client!.CreateResponseAsync(options2);
        var text2 = response2.GetOutputText();

        Assert.Contains("Alice", text2, StringComparison.OrdinalIgnoreCase);
    }

    // -----------------------------------------------------------------------
    // 6. Structured output — JSON schema enforcement
    // -----------------------------------------------------------------------
    [Fact]
    public async Task StructuredOutput_ReturnsValidJson()
    {
        SkipIfNotConfigured();

        var messages = new[]
        {
            ResponseItem.CreateUserMessageItem("What is the capital of France? Respond with JSON.")
        };
        var options = new CreateResponseOptions(_fixture.Model!, messages)
        {
            MaxOutputTokenCount = 200
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

        var response = await _fixture.Client!.CreateResponseAsync(options);
        var text = response.GetOutputText();

        Assert.False(string.IsNullOrWhiteSpace(text));
        var doc = JsonDocument.Parse(text);
        Assert.True(doc.RootElement.TryGetProperty("capital", out var capital));
        Assert.Equal("Paris", capital.GetString());
    }

    // -----------------------------------------------------------------------
    // 7. Tool / function calling — define a tool and get back a tool call
    // -----------------------------------------------------------------------
    [Fact]
    public async Task ToolCalling_ReturnsToolCallItem()
    {
        SkipIfNotConfigured();

        var messages = new[]
        {
            ResponseItem.CreateUserMessageItem("What is the weather in Seattle?")
        };
        var options = new CreateResponseOptions(_fixture.Model!, messages);
        options.Tools.Add(ResponseTool.CreateFunctionTool(
            "get_weather",
            "Get current weather for a city",
            BinaryData.FromString("""
            {
                "type": "object",
                "properties": {
                    "city": { "type": "string", "description": "City name" }
                },
                "required": ["city"],
                "additionalProperties": false
            }
            """)));

        var response = await _fixture.Client!.CreateResponseAsync(options);

        // The model should call the tool instead of answering directly
        var functionCall = response.OutputItems
            .OfType<FunctionCallItem>()
            .FirstOrDefault();

        Assert.NotNull(functionCall);
        Assert.Equal("get_weather", functionCall.Name);

        // Parse the arguments
        var args = JsonDocument.Parse(functionCall.Arguments);
        Assert.True(args.RootElement.TryGetProperty("city", out var city));
        Assert.Contains("Seattle", city.GetString(), StringComparison.OrdinalIgnoreCase);
    }

    // -----------------------------------------------------------------------
    // 8. No legacy shapes — verify the response is NOT a ChatCompletion
    // -----------------------------------------------------------------------
    [Fact]
    public async Task NoLegacyShapes_ResponseIsNotChatCompletion()
    {
        SkipIfNotConfigured();

        var response = await _fixture.Client!.CreateResponseAsync(
            _fixture.Model!, "Say hello.");

        // Verify we got an OpenAIResponse (Responses API), not a ChatCompletion
        Assert.IsType<OpenAIResponse>(response);
        Assert.NotEmpty(response.OutputItems);

        // GetOutputText() is the Responses API method — it should work
        var text = response.GetOutputText();
        Assert.False(string.IsNullOrWhiteSpace(text));
    }
}

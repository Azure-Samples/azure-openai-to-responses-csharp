#pragma warning disable OPENAI001 // Responses API is in preview

using Azure.Identity;
using Microsoft.Extensions.Configuration;
using OpenAI;
using OpenAI.Responses;
using System.ClientModel;
using System.ClientModel.Primitives;

IConfigurationRoot config = new ConfigurationBuilder()
    .AddUserSecrets<Program>()
    .Build();

var endpoint = config["AZURE_OPENAI_ENDPOINT"];
var model = config["AZURE_OPENAI_API_DEPLOYMENT_NAME"];

if (string.IsNullOrEmpty(endpoint) || string.IsNullOrEmpty(model))
{
    throw new Exception("Azure OpenAI connection information was not set. See README for details.");
}

// Set the environment variable to use dev tool credentials only.
// See http://aka.ms/azsdk/net/identity/credential-chains#exclude-a-credential-type-category.
Environment.SetEnvironmentVariable(DefaultAzureCredential.DefaultEnvironmentVariableName, "dev");

// Build a BearerTokenPolicy for keyless (Entra ID) authentication.
// This replaces the AzureOpenAIClient + DefaultAzureCredential pattern.
var policy = new BearerTokenPolicy(
    new DefaultAzureCredential(DefaultAzureCredential.DefaultEnvironmentVariableName),
    "https://cognitiveservices.azure.com/.default");

// Configure the client to use the Azure OpenAI /openai/v1/ endpoint.
// No api_version needed — the /openai/v1/ route is stable.
var clientOptions = new OpenAIClientOptions
{
    Endpoint = new Uri($"{endpoint.TrimEnd('/')}/openai/v1/")
};
var responsesClient = new ResponsesClient(policy, clientOptions);

// Create a response using the Responses API.
// ResponseItem factory methods replace SystemChatMessage / UserChatMessage.
var messages = new[]
{
    ResponseItem.CreateSystemMessageItem("You are a helpful assistant that makes lots of cat references and uses emojis."),
    ResponseItem.CreateUserMessageItem("Write a haiku about a hungry cat who wants tuna"),
};

OpenAIResponse response = await responsesClient.CreateResponseAsync(model, messages);

Console.WriteLine("Response:");
Console.WriteLine(response.GetOutputText());

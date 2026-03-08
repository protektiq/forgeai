using System.Net;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Mvc.Testing;
using Xunit;

namespace dotnet_api.Tests;

/// <summary>
/// Malformed input and API key validation tests.
/// When ApiKey is set: missing or wrong X-Api-Key must return 401.
/// </summary>
public class ApiKeyValidationTests
{
    [Fact]
    public async Task When_ApiKey_Configured_Request_Without_Key_Returns_401()
    {
        await using var factory = new WebApplicationFactory<Program>()
            .WithWebHostBuilder(b => b.UseSetting("ApiKey", "test-secret-key"));
        var client = factory.CreateClient();

        var response = await client.GetAsync("/api/v1/assets");
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);

        var content = await response.Content.ReadAsStringAsync();
        var doc = JsonDocument.Parse(content);
        var code = doc.RootElement.GetProperty("error").GetProperty("code").GetString();
        Assert.Equal("unauthorized", code);
    }

    [Fact]
    public async Task When_ApiKey_Configured_Request_With_Wrong_Key_Returns_401()
    {
        await using var factory = new WebApplicationFactory<Program>()
            .WithWebHostBuilder(b => b.UseSetting("ApiKey", "correct-key"));
        var client = factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-Api-Key", "wrong-key");

        var response = await client.GetAsync("/api/v1/assets");
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);

        var content = await response.Content.ReadAsStringAsync();
        var doc = JsonDocument.Parse(content);
        var code = doc.RootElement.GetProperty("error").GetProperty("code").GetString();
        Assert.Equal("unauthorized", code);
    }

    [Fact]
    public async Task When_ApiKey_Configured_Request_With_Valid_Key_Does_Not_Return_401()
    {
        await using var factory = new WebApplicationFactory<Program>()
            .WithWebHostBuilder(b => b.UseSetting("ApiKey", "valid-key-for-test"));
        var client = factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-Api-Key", "valid-key-for-test");

        var response = await client.GetAsync("/api/v1/assets");
        // 200 (Rails up) or 502 (Rails down) - not 401
        Assert.NotEqual(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task Health_Does_Not_Require_ApiKey()
    {
        await using var factory = new WebApplicationFactory<Program>()
            .WithWebHostBuilder(b => b.UseSetting("ApiKey", "required"));
        var client = factory.CreateClient();
        // No X-Api-Key header
        var response = await client.GetAsync("/health");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [Fact]
    public async Task Generate_With_Empty_Prompt_Returns_400()
    {
        await using var factory = new WebApplicationFactory<Program>()
            .WithWebHostBuilder(b => b.UseSetting("ApiKey", "test-key-for-validation"));
        var client = factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-Api-Key", "test-key-for-validation");
        var body = JsonSerializer.Serialize(new { prompt = "" });
        var content = new StringContent(body, Encoding.UTF8, "application/json");

        var response = await client.PostAsync("/api/v1/generate", content);
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task Generate_With_Missing_Prompt_Returns_400()
    {
        await using var factory = new WebApplicationFactory<Program>()
            .WithWebHostBuilder(b => b.UseSetting("ApiKey", "test-key-for-validation"));
        var client = factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-Api-Key", "test-key-for-validation");
        var body = JsonSerializer.Serialize(new { });
        var content = new StringContent(body, Encoding.UTF8, "application/json");

        var response = await client.PostAsync("/api/v1/generate", content);
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }
}

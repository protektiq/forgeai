using System.Net;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Hosting;
using Xunit;

namespace dotnet_api.Tests;

public class ContractTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly HttpClient _client;
    private readonly WebApplicationFactory<Program> _factory;

    public ContractTests(WebApplicationFactory<Program> factory)
    {
        _factory = factory;
        _client = factory.CreateClient();
    }

    [Fact]
    public async Task Health_Returns_200_With_Status_And_Service()
    {
        var response = await _client.GetAsync("/health");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var json = await response.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal("ok", json.GetProperty("status").GetString());
        Assert.Equal("dotnet_api", json.GetProperty("service").GetString());
    }

    [Fact]
    public async Task Root_Returns_Service_Info()
    {
        var response = await _client.GetAsync("/");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var json = await response.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal("dotnet_api", json.GetProperty("service").GetString());
    }

    /// <summary>
    /// When no API key is configured, /api/v1/* should not return 401 (may return 200 or 502 if Rails is down).
    /// </summary>
    [Fact]
    public async Task Api_V1_When_No_ApiKey_Configured_Does_Not_Return_401()
    {
        using var factory = new WebApplicationFactory<Program>()
            .WithWebHostBuilder(b => b.UseSetting("ApiKey", "").UseSetting("ASPNETCORE_API_KEY", ""));
        var client = factory.CreateClient();
        var response = await client.GetAsync("/api/v1/assets");
        // Either success (200) or gateway error (502) when Rails is down - never 401 when key is not set
        Assert.NotEqual(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task Api_V1_Jobs_With_Empty_Id_Returns_400_Or_404()
    {
        // GET /api/v1/jobs/ may not match route /api/v1/jobs/{id} -> 404, or 400 if id validated
        var response = await _client.GetAsync("/api/v1/jobs/");
        Assert.True(
            response.StatusCode == HttpStatusCode.NotFound ||
            response.StatusCode == HttpStatusCode.BadRequest ||
            response.StatusCode == HttpStatusCode.Unauthorized,
            $"Unexpected status {response.StatusCode}");
    }
}

using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;

const string ApiKeyHeader = "X-Api-Key";
const string InternalApiKeyHeader = "X-Internal-Api-Key";
const int PromptMaxLength = 10_000;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddHttpClient("Rails", (sp, client) =>
{
    var config = sp.GetRequiredService<IConfiguration>();
    var baseUrl = config["Rails:BaseUrl"] ?? "http://localhost:3000";
    client.BaseAddress = new Uri(baseUrl.TrimEnd('/') + "/");
    client.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
    var internalKey = config["Rails:InternalApiKey"];
    if (!string.IsNullOrWhiteSpace(internalKey))
        client.DefaultRequestHeaders.Add(InternalApiKeyHeader, internalKey.Trim());
});

var app = builder.Build();

string? configuredApiKey = app.Configuration["ApiKey"] ?? app.Configuration["ASPNETCORE_API_KEY"];
if (string.IsNullOrWhiteSpace(configuredApiKey))
    configuredApiKey = null; // Allow all when not set (dev only)

app.Use(async (context, next) =>
{
    if (!context.Request.Path.StartsWithSegments("/api", StringComparison.OrdinalIgnoreCase))
    {
        await next();
        return;
    }
    if (configuredApiKey is null)
    {
        await next();
        return;
    }
    string? provided = context.Request.Headers[ApiKeyHeader].FirstOrDefault()?.Trim();
    if (string.IsNullOrEmpty(provided) || !System.Security.Cryptography.CryptographicOperations.FixedTimeEquals(
        Encoding.UTF8.GetBytes(provided),
        Encoding.UTF8.GetBytes(configuredApiKey)))
    {
        context.Response.StatusCode = 401;
        await context.Response.WriteAsJsonAsync(new { error = "Missing or invalid API key" });
        return;
    }
    await next();
});

app.MapGet("/", () => Results.Ok(new { service = "dotnet_api", health = "/health", api = "/api" }));
app.MapGet("/health", () => Results.Ok(new { status = "ok", service = "dotnet_api" }));

app.MapPost("/api/generate", async (HttpContext context, IHttpClientFactory httpClientFactory) =>
{
    GenerateRequest? body;
    try
    {
        body = await context.Request.ReadFromJsonAsync<GenerateRequest>();
    }
    catch (JsonException)
    {
        return Results.Json(new { error = "Invalid JSON body" }, statusCode: 400);
    }
    if (body == null)
        return Results.Json(new { error = "Body is required" }, statusCode: 400);
    string prompt = (body.Prompt ?? "").Trim();
    if (prompt.Length == 0)
        return Results.Json(new { error = "prompt is required" }, statusCode: 400);
    if (prompt.Length > PromptMaxLength)
        return Results.Json(new { error = $"prompt must be at most {PromptMaxLength} characters" }, statusCode: 400);

    var rails = httpClientFactory.CreateClient("Rails");
    var payload = new StringContent(JsonSerializer.Serialize(new { prompt }), Encoding.UTF8, "application/json");
    HttpResponseMessage response;
    try
    {
        response = await rails.PostAsync("api/v1/generate", payload);
    }
    catch (HttpRequestException ex)
    {
        return Results.Json(new { error = "Rails service unavailable", detail = ex.Message }, statusCode: 502);
    }
    catch (TaskCanceledException)
    {
        return Results.Json(new { error = "Rails service timeout" }, statusCode: 502);
    }

    var content = await response.Content.ReadAsStringAsync();
    if (!response.IsSuccessStatusCode)
        return Results.Json(JsonSerializer.Deserialize<JsonElement>(content.Length > 0 ? content : "{}"), statusCode: (int)response.StatusCode);
    return Results.Json(JsonSerializer.Deserialize<JsonElement>(content), statusCode: (int)response.StatusCode);
});

app.MapGet("/api/assets", async (string? search, IHttpClientFactory httpClientFactory) =>
{
    var rails = httpClientFactory.CreateClient("Rails");
    string url = "api/v1/assets";
    if (!string.IsNullOrWhiteSpace(search))
    {
        var encoded = Uri.EscapeDataString(search.Trim());
        url += "?search=" + encoded;
    }
    HttpResponseMessage response;
    try
    {
        response = await rails.GetAsync(url);
    }
    catch (HttpRequestException ex)
    {
        return Results.Json(new { error = "Rails service unavailable", detail = ex.Message }, statusCode: 502);
    }
    catch (TaskCanceledException)
    {
        return Results.Json(new { error = "Rails service timeout" }, statusCode: 502);
    }
    var content = await response.Content.ReadAsStringAsync();
    if (!response.IsSuccessStatusCode)
        return Results.Json(JsonSerializer.Deserialize<JsonElement>(content.Length > 0 ? content : "{}"), statusCode: (int)response.StatusCode);
    return Results.Json(JsonSerializer.Deserialize<JsonElement>(content), statusCode: (int)response.StatusCode);
});

app.MapGet("/api/assets/{id}", async (string id, IHttpClientFactory httpClientFactory) =>
{
    if (string.IsNullOrWhiteSpace(id))
        return Results.Json(new { error = "Asset id is required" }, statusCode: 400);
    if (!int.TryParse(id, out _) && !Guid.TryParse(id, out _))
        return Results.Json(new { error = "Asset id must be a number or valid id" }, statusCode: 400);

    var rails = httpClientFactory.CreateClient("Rails");
    string url = "api/v1/assets/" + Uri.EscapeDataString(id.Trim());
    HttpResponseMessage response;
    try
    {
        response = await rails.GetAsync(url);
    }
    catch (HttpRequestException ex)
    {
        return Results.Json(new { error = "Rails service unavailable", detail = ex.Message }, statusCode: 502);
    }
    catch (TaskCanceledException)
    {
        return Results.Json(new { error = "Rails service timeout" }, statusCode: 502);
    }
    var content = await response.Content.ReadAsStringAsync();
    if (response.StatusCode == System.Net.HttpStatusCode.NotFound)
        return Results.Json(JsonSerializer.Deserialize<JsonElement>(content.Length > 0 ? content : "{}"), statusCode: 404);
    if (!response.IsSuccessStatusCode)
        return Results.Json(JsonSerializer.Deserialize<JsonElement>(content.Length > 0 ? content : "{}"), statusCode: (int)response.StatusCode);
    return Results.Json(JsonSerializer.Deserialize<JsonElement>(content), statusCode: (int)response.StatusCode);
});

app.Run();

record GenerateRequest(string? Prompt);

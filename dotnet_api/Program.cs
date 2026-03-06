using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

const string ApiKeyHeader = "X-Api-Key";
const string InternalApiKeyHeader = "X-Internal-Api-Key";
const string CorrelationIdHeader = "X-Correlation-Id";
const string RequestIdHeader = "X-Request-Id";
const int PromptMaxLength = 10_000;

// Standard error response shape (see docs/contracts/error-response.md)
record ErrorPart(
    [property: JsonPropertyName("code")] string Code,
    [property: JsonPropertyName("message")] string Message,
    [property: JsonPropertyName("correlation_id")] string CorrelationId);
record ApiErrorResponse([property: JsonPropertyName("error")] ErrorPart Error);

static IResult ApiErrorResult(string code, string message, string correlationId, int statusCode) =>
    Results.Json(new ApiErrorResponse(new ErrorPart(code, message, correlationId)), statusCode: statusCode);

static string GetCorrelationId(HttpContext context) =>
    context.Request.Headers[CorrelationIdHeader].FirstOrDefault()
    ?? context.Request.Headers[RequestIdHeader].FirstOrDefault()
    ?? Guid.NewGuid().ToString();

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
        var correlationId = context.Request.Headers[CorrelationIdHeader].FirstOrDefault()
            ?? context.Request.Headers[RequestIdHeader].FirstOrDefault()
            ?? Guid.NewGuid().ToString();
        context.Response.StatusCode = 401;
        await context.Response.WriteAsJsonAsync(new ApiErrorResponse(new ErrorPart("unauthorized", "Missing or invalid API key", correlationId)));
        return;
    }
    await next();
});

app.MapGet("/", () => Results.Ok(new { service = "dotnet_api", health = "/health", api = "/api" }));
app.MapGet("/health", () => Results.Ok(new { status = "ok", service = "dotnet_api" }));

app.MapPost("/api/generate", async (HttpContext context, IHttpClientFactory httpClientFactory) =>
{
    var correlationId = GetCorrelationId(context);
    var logger = context.RequestServices.GetRequiredService<ILogger<Program>>();
    logger.LogInformation("dotnet_api request correlation_id={CorrelationId} path={Path}", correlationId, context.Request.Path);

    GenerateRequest? body;
    try
    {
        body = await context.Request.ReadFromJsonAsync<GenerateRequest>();
    }
    catch (JsonException)
    {
        return ApiErrorResult("invalid_request", "Invalid JSON body", correlationId, 400);
    }
    if (body == null)
        return ApiErrorResult("invalid_request", "Body is required", correlationId, 400);
    string prompt = (body.Prompt ?? "").Trim();
    if (prompt.Length == 0)
        return ApiErrorResult("invalid_request", "prompt is required", correlationId, 400);
    if (prompt.Length > PromptMaxLength)
        return ApiErrorResult("invalid_request", $"prompt must be at most {PromptMaxLength} characters", correlationId, 400);

    var rails = httpClientFactory.CreateClient("Rails");
    var payload = new StringContent(JsonSerializer.Serialize(new { prompt }), Encoding.UTF8, "application/json");
    var request = new HttpRequestMessage(HttpMethod.Post, "api/v1/generate") { Content = payload };
    request.Headers.TryAddWithoutValidation(CorrelationIdHeader, correlationId);
    HttpResponseMessage response;
    try
    {
        response = await rails.SendAsync(request);
    }
    catch (HttpRequestException ex)
    {
        return ApiErrorResult("bad_gateway", "Rails service unavailable: " + ex.Message, correlationId, 502);
    }
    catch (TaskCanceledException)
    {
        return ApiErrorResult("bad_gateway", "Rails service timeout", correlationId, 502);
    }

    var content = await response.Content.ReadAsStringAsync();
    if (!response.IsSuccessStatusCode)
        return Results.Json(JsonSerializer.Deserialize<JsonElement>(content.Length > 0 ? content : "{}"), statusCode: (int)response.StatusCode);
    return Results.Json(JsonSerializer.Deserialize<JsonElement>(content), statusCode: (int)response.StatusCode);
});

app.MapGet("/api/assets", async (HttpContext context, string? search, IHttpClientFactory httpClientFactory) =>
{
    var correlationId = GetCorrelationId(context);
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
        return ApiErrorResult("bad_gateway", "Rails service unavailable: " + ex.Message, correlationId, 502);
    }
    catch (TaskCanceledException)
    {
        return ApiErrorResult("bad_gateway", "Rails service timeout", correlationId, 502);
    }
    var content = await response.Content.ReadAsStringAsync();
    if (!response.IsSuccessStatusCode)
        return Results.Json(JsonSerializer.Deserialize<JsonElement>(content.Length > 0 ? content : "{}"), statusCode: (int)response.StatusCode);
    return Results.Json(JsonSerializer.Deserialize<JsonElement>(content), statusCode: (int)response.StatusCode);
});

app.MapGet("/api/assets/{id}", async (HttpContext context, string id, IHttpClientFactory httpClientFactory) =>
{
    var correlationId = GetCorrelationId(context);
    if (string.IsNullOrWhiteSpace(id))
        return ApiErrorResult("invalid_request", "Asset id is required", correlationId, 400);
    if (!int.TryParse(id, out _) && !Guid.TryParse(id, out _))
        return ApiErrorResult("invalid_request", "Asset id must be a number or valid id", correlationId, 400);

    var rails = httpClientFactory.CreateClient("Rails");
    string url = "api/v1/assets/" + Uri.EscapeDataString(id.Trim());
    HttpResponseMessage response;
    try
    {
        response = await rails.GetAsync(url);
    }
    catch (HttpRequestException ex)
    {
        return ApiErrorResult("bad_gateway", "Rails service unavailable: " + ex.Message, correlationId, 502);
    }
    catch (TaskCanceledException)
    {
        return ApiErrorResult("bad_gateway", "Rails service timeout", correlationId, 502);
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

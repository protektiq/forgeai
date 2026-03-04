# .NET API

Minimal ASP.NET Core "hello world" API. GET `/` returns `Hello, world`.

## Prerequisites

- **.NET SDK** 8.0 (or 6.0/7.0; adjust `<TargetFramework>` in `.csproj` if needed)

Install from https://dotnet.microsoft.com/download

## Build

```bash
dotnet restore
dotnet build
```

## Run

```bash
dotnet run
```

Server listens on **http://localhost:5000** (see `Properties/launchSettings.json`). Open in a browser or:

```bash
curl http://localhost:5000
```

## Expected output

- Browser or `curl`: response body `Hello, world`
- Terminal: ASP.NET Core startup log with the listening URL

## Port

Default is 5000. To change it, edit `Properties/launchSettings.json` and set `applicationUrl` to e.g. `http://localhost:5001`, or configure URLs in code or appsettings.

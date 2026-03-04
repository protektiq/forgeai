# Architecture

This repository contains five independent services, each in its own language and folder. They are built and run separately; there is no shared runtime or single entrypoint.

## Services

| Service       | Folder        | Purpose (placeholder)     | Stack         |
|---------------|---------------|---------------------------|---------------|
| Rails app     | `rails_app/`  | Web application           | Ruby on Rails |
| Python gen    | `python_gen/` | Generation / scripting    | Python        |
| C++ media     | `cpp_media/`  | Media processing          | C++           |
| Rust index    | `rust_index/` | Indexing / search         | Rust          |
| .NET API      | `dotnet_api/` | API service               | .NET          |

Each service is self-contained: it has its own dependencies, build steps, and run instructions. They do not depend on each other for the initial "hello world" setup.

## Local orchestration

- **Simplest (MVP):** Run each service in its own terminal from the corresponding folder. No order is required; start any subset you need.
- **Later (optional):** Docker Compose may be added for single-command startup; it is not required for the current phase.

## Data flow

See [data-flow.md](data-flow.md) for a minimal data flow diagram. Update it as you add real APIs and data flows between services.

# forgeai

Multi-language repo: each service is built and run independently. This document gives prerequisites and how to run everything locally. For architecture and operations, see [docs/architecture.md](docs/architecture.md) and [docs/runbook.md](docs/runbook.md).

## Prerequisites

Install the following per service you want to run:

| Service       | Prerequisites                          | Notes                    |
|---------------|----------------------------------------|--------------------------|
| Rails app     | Ruby 3.x, Bundler                      | `gem install bundler`    |
| Python gen    | Python 3.x                             | Use a venv recommended   |
| C++ media     | g++ (C++17), make (optional)           | Any C++17 compiler       |
| Rust index    | Rust (rustc, cargo)                    | Install via [rustup](https://rustup.rs/) |
| .NET API      | .NET SDK 8.0                           | [Download](https://dotnet.microsoft.com/download) |

You do not need all of them to run a single service; install only what you need for the folders you use.

## How to run everything locally

**Orchestration:** The simplest approach is to run each service in its own terminal (one terminal per folder). No startup order is required. Docker Compose is optional later and not required for this MVP.

### Rails app (`rails_app/`)

```bash
cd rails_app
bundle install
bundle exec rails s
```

- **URL:** http://localhost:3000  
- **Details:** [rails_app/README.md](rails_app/README.md)

### Python gen (`python_gen/`)

```bash
cd python_gen
python3 -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
python main.py
```

- **URL:** http://localhost:5000  
- **Details:** [python_gen/README.md](python_gen/README.md)

### C++ media (`cpp_media/`)

```bash
cd cpp_media
make
./hello
```

- **Details:** [cpp_media/README.md](cpp_media/README.md) (one-shot binary, no server)

### Rust index (`rust_index/`)

```bash
cd rust_index
cargo build
cargo run
```

- **Details:** [rust_index/README.md](rust_index/README.md) (one-shot binary, no server)

### .NET API (`dotnet_api/`)

```bash
cd dotnet_api
dotnet restore
dotnet build
dotnet run
```

- **URL:** http://localhost:5000  
- **Details:** [dotnet_api/README.md](dotnet_api/README.md)

## Docs

- **[docs/architecture.md](docs/architecture.md)** — Service overview and local orchestration.
- **[docs/runbook.md](docs/runbook.md)** — Build/run commands and troubleshooting.
- **[docs/data-flow.md](docs/data-flow.md)** — Data flow diagram (updated as the system evolves).

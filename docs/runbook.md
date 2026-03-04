# Runbook

How to build and run each service locally. For prerequisites and high-level "how to run everything," see the [top-level README](../README.md).

## Orchestration

Run each service in its own terminal from the corresponding folder. No startup order is required; services are independent. To run everything locally, open five terminals and run one service per terminal.

## Per-service commands

### Rails app (`rails_app/`)

```bash
cd rails_app
bundle install
bundle exec rails s
```

- **Port:** 3000  
- **Logs:** stdout; also `rails_app/log/development.log` if present  
- **Common issues:** Port 3000 in use → change with `-p 3001` or stop the other process.

### Python gen (`python_gen/`)

```bash
cd python_gen
python3 -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
python main.py
```

- **Port:** 5000  
- **Logs:** stdout  
- **Common issues:** Port 5000 in use → edit `main.py` to use another port; missing venv → ensure you activate before `pip install`.

### C++ media (`cpp_media/`)

```bash
cd cpp_media
make
./hello
```

- **Logs:** stdout (no server; one-shot binary)  
- **Common issues:** No `make` → use `g++ -o hello main.cpp` then `./hello`; see `cpp_media/README.md`.

### Rust index (`rust_index/`)

```bash
cd rust_index
cargo build
cargo run
```

- **Logs:** stdout (one-shot binary)  
- **Common issues:** First run may download toolchain; see `rust_index/README.md`.

### .NET API (`dotnet_api/`)

```bash
cd dotnet_api
dotnet restore
dotnet build
dotnet run
```

- **Port:** 5000 (HTTP), 5001 (HTTPS) — check app output  
- **Logs:** stdout  
- **Common issues:** Port in use → configure in `Properties/launchSettings.json` or app configuration; see `dotnet_api/README.md`.

## Troubleshooting

- **Port already in use:** Change the port in the app config or stop the process using the port (`lsof -i :PORT` on Unix).
- **Build failures:** Ensure prerequisites are installed (Ruby, Python, g++, Rust, .NET SDK) and you are in the correct folder; see each project's README.

For architecture overview and data flow, see [architecture.md](architecture.md) and [data-flow.md](data-flow.md).

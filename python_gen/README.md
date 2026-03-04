# Python gen

Minimal Python Flask "hello world" service. Root route returns `Hello, world`.

## Prerequisites

- **Python** 3.x
- Recommended: create a virtual environment before installing dependencies

## Build

```bash
python3 -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
```

## Run

```bash
python main.py
```

Or with Flask CLI (after activating venv):

```bash
flask --app main run --port 5000
```

Server listens on **http://localhost:5000**. Open in a browser or:

```bash
curl http://localhost:5000
```

## Expected output

- Browser or `curl`: response body `Hello, world`
- Terminal: Flask startup log and request logs

## Port

Default port is 5000. To change it, edit `main.py` and set `port=5001` (or another port) in `app.run(...)`.

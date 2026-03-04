# Rails app

Minimal Ruby on Rails "hello world" service. Root route returns `Hello, world`.

## Prerequisites

- **Ruby** 3.x
- **Bundler** (`gem install bundler`)

## Build

```bash
bundle install
```

## Run

```bash
bundle exec rails s
```

Server listens on **http://localhost:3000**. Open in a browser or:

```bash
curl http://localhost:3000
```

## Expected output

- Browser or `curl`: response body `Hello, world`
- Terminal: Rails server log (Puma starting, etc.)

## Port

Default port is 3000. To use another port:

```bash
bundle exec rails s -p 3001
```

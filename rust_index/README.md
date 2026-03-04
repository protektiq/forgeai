# Rust index

Minimal Rust "hello world" program. Prints `Hello, world` to stdout.

## Prerequisites

- **Rust** toolchain (rustc, cargo). Install from https://rustup.rs/

## Build

```bash
cargo build
```

## Run

```bash
cargo run
```

You can also run the binary directly after building:

```bash
cargo build --release
./target/release/rust_index
```

## Expected output

```
Hello, world
```

The program is a one-shot binary (no server). It prints the line and exits.

## First run

The first `cargo build` or `cargo run` may download and compile dependencies (there are none for this minimal app) and can take a bit longer. Subsequent builds are incremental.

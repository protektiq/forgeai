# C++ media

Minimal C++ "hello world" program. Prints `Hello, world` to stdout.

## Prerequisites

- **g++** (or another C++17-capable compiler)
- **make** (optional; you can compile manually if make is not installed)

## Build

With Makefile:

```bash
make
```

Without make:

```bash
g++ -std=c++17 -o hello main.cpp
```

## Run

```bash
./hello
```

## Expected output

```
Hello, world
```

The program is a one-shot binary (no server). It prints the line and exits.

## Clean

```bash
make clean
```

Or remove the binary: `rm -f hello`

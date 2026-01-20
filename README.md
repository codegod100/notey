# Notey

A minimal, snappy single-user document editor built with Elm and Roc.

## Features

- Clean, distraction-free writing interface
- Auto-saves to SQLite
- Word count
- Works offline

## Project Structure

- `frontend/` - Elm source code
- `backend/` - Roc source code
- `platform/` - Roc platform and host
- `static/` - Static assets (HTML, compiled JS)
- `scripts/` - Build and package scripts

## Development Setup

### Prerequisites

- Elm 0.19.1+
- Roc (nightly)
- Zig (for building platform/host if needed)

### 1. Build Frontend

```bash
cd frontend
elm make src/Main.elm --output=../static/elm.js
cd ..
```

### 2. Build Backend

```bash
cd backend
roc build main.roc
cd ..
```

To run in development mode:

```bash
cd backend
roc dev main.roc -- --port 8080
```

### 3. Run Production Binary

If you built the binary:

```bash
./backend/main --port 8080
```

Open http://localhost:8080

## Deployment

Use the package script to create a release archive. Ensure you have built the frontend and backend first.

```bash
./scripts/package.sh
```

## Docker

```bash
docker build -t notey .
docker run -p 8080:8080 notey
```
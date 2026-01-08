# Notey

A minimal, snappy single-user document editor built with Elm.

## Features

- Clean, distraction-free writing interface
- Auto-saves to localStorage (instant, no server)
- Word count
- Works offline

## Setup

```bash
# Install Elm if you haven't
npm install -g elm

# Compile
elm make src/Main.elm --output=elm.js --optimize

# Open index.html in your browser
```

## Development

```bash
# For development (with debug tools)
elm make src/Main.elm --output=elm.js

# Watch mode (requires elm-live)
npm install -g elm-live
elm-live src/Main.elm --open -- --output=elm.js
```

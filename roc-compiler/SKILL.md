---
name: roc-compiler
description: Use the Zig-based Roc interpreter instead of the Rust-based compiler.
---

# Roc Compiler Skill

Use `rocn` (symlinked to the latest development Zig-based Roc interpreter) when working with Roc projects.

## Build Commands

```bash
# First build the Zig host library
zig build x64musl

# Run a Roc app
rocn app/main.roc --no-cache
```

## Building Roc Interpreter

If needed, rebuild the Zig-based interpreter:

```bash
cd /home/nandi/code/roc && zig build roc
```

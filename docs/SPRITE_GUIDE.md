# Deploying Notey to Sprites.dev

This guide walks through deploying the Notey document editor to a Sprites.dev environment.

## Prerequisites

- Sprites CLI installed (see https://sprites.dev/)
- Sprites account and authentication configured

## Quick Start

### 1. Create a Sprite

```bash
sprite create notey
```

This creates a persistent Linux environment in 1-2 seconds.

### 2. Connect to the Sprite Console

```bash
sprite console notey
```

### 3. Install Dependencies and Build

Once inside the sprite:

```bash
# Install Roc compiler
curl -L https://github.com/roc-lang/roc/releases/latest/download/roc_nix-linux.gz | gunzip > /tmp/roc
chmod +x /tmp/roc
sudo mv /tmp/roc /usr/local/bin/roc

# Create project directory
mkdir -p /notey
cd /notey

# Set up directory structure
mkdir -p static
mkdir -p platform/targets
```

### 4. Upload Project Files

From your local machine, upload the necessary files to the sprite:

```bash
# Upload source files
sprite cp main.roc notey:/notey/
sprite cp Args.roc notey:/notey/
sprite cp Http.roc notey:/notey/

# Upload platform files
sprite cp -r platform notey:/notey/

# Upload static files
sprite cp -r static notey:/notey/
```

### 5. Build the Binary

From within the sprite console:

```bash
cd /notey

# Build for Linux x64 (native on sprites)
zig build native

# Compile the Roc application
# Note: This requires the roc-compiler to work correctly
# The binary will be created as 'main'
roc build main.roc
```

This creates the `main` binary.

**Note**: If you encounter build issues with the Roc compiler, you can:
1. Use the `roc-compiler` subcommand if available
2. Build the binary locally and upload it to the sprite
3. Use the pre-built `main` binary if it exists in your local project

### 6. Run the Server

```bash
./main --port 8080
```

The server will start and be accessible at:
- The sprite's public HTTPS URL (e.g., `https://notey-xyz.fly.dev`)
- Or via port forwarding: `sprite port-forward notey 8080:8080`

### 7. Create a Checkpoint

After the server is working, create a checkpoint to save the environment:

```bash
# From the sprite console
sprite checkpoint create setup-complete

# Or from your local machine
sprite exec notey "sprite checkpoint create setup-complete"
```

## Managing Your Sprite

### View Checkpoints

```bash
sprite checkpoint list notey
```

### Restore a Checkpoint

```bash
sprite checkpoint restore notey setup-complete
```

### Start/Stop the Server

The server can be started/stopped without destroying the sprite:

```bash
# In sprite console
cd /notey && ./main --port 8080 &

# Or use sprite exec
sprite exec notey "cd /notey && ./main --port 8080"
```

### Access Logs

```bash
sprite logs notey
```

## Data Persistence

Notey uses SQLite for storage. The database is stored at:
- `/.roc_storage/notes.db`

This location is persistent across sprite hibernation and wake cycles.

## Benefits of Using Sprites

1. **Persistent Environment**: Files and data remain between sessions
2. **Fast Wake-Up**: Resumes instantly from hibernation
3. **Cost-Effective**: Auto-hibernates after 30s of inactivity
4. **HTTPS URL**: Each sprite gets a public HTTPS URL
5. **Checkpoints**: Save and restore environment states
6. **No Dockerfiles**: Direct Linux environment

## Troubleshooting

### Build Fails

Ensure Zig and Roc are installed:
```bash
zig --version
roc --version
```

### Port Already in Use

Check what's using the port:
```bash
sudo lsof -i :8080
```

### Database Issues

Check the database location:
```bash
ls -la /.roc_storage/
```

## Example Usage

```bash
# Create and set up in one go
sprite create notey
sprite cp main.roc notey:/notey/
sprite cp -r platform notey:/notey/
sprite cp -r static notey:/notey/
sprite exec notey "cd /notey && zig build native"
sprite exec notey "cd /notey && roc build main.roc"
sprite exec notey "cd /notey && ./main --port 8080"

# Get the sprite's public URL
sprite info notey
```

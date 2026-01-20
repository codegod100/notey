#!/bin/bash
set -e

echo "=== Notey Sprite Setup ==="

# Install Roc compiler if not present
if ! command -v roc &> /dev/null; then
    echo "Installing Roc compiler..."
    curl -L https://github.com/roc-lang/roc/releases/latest/download/roc_nix-linux.gz | gunzip > /tmp/roc
    chmod +x /tmp/roc
    sudo mv /tmp/roc /usr/local/bin/roc
fi

# Copy project files to sprite
echo "Setting up Notey project..."
mkdir -p /notey
cd /notey

# Create directory structure
mkdir -p static
mkdir -p platform/targets

# Copy necessary files (these would be uploaded to the sprite)
# For now, we'll create a minimal setup that can be populated
cat > README.md << 'EOF'
# Notey - Document Editor on Sprite

A simple document editor built with Roc, running on Sprites.dev.

## Running the server

After the binary is built:
./main --port 8080

The server will be accessible at the sprite's HTTPS URL.
EOF

echo "✓ Sprite directory structure created"
echo ""
echo "Next steps:"
echo "1. Upload project files to the sprite"
echo "2. Build the Roc binary"
echo "3. Run the server"
echo "4. Create a checkpoint with: sprite checkpoint create setup-complete"

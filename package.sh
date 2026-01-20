#!/bin/bash
set -e

echo "=== Building Notey Release Package ==="

# Get version from git or use default
VERSION=$(git describe --tags --always 2>/dev/null || echo "dev")
BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
ARCH=$(uname -m)

echo "Version: $VERSION"
echo "Build Date: $BUILD_DATE"
echo "Architecture: $ARCH"

# Create staging directory
STAGING_DIR="notey-release-$VERSION"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

# Create directory structure
mkdir -p "$STAGING_DIR/static"

# Copy binary
echo "Copying binary..."
cp main "$STAGING_DIR/"
chmod +x "$STAGING_DIR/main"

# Copy static files
echo "Copying static files..."
cp static/index.html "$STAGING_DIR/static/"
cp static/elm.js "$STAGING_DIR/static/"

# Copy platform directory for runtime
mkdir -p "$STAGING_DIR/platform/targets"
cp -r platform/*.roc "$STAGING_DIR/platform/" 2>/dev/null || true
cp -r platform/targets/* "$STAGING_DIR/platform/targets/" 2>/dev/null || true

# Copy source files (optional, for reference)
cp main.roc "$STAGING_DIR/"
cp Args.roc "$STAGING_DIR/"
cp Http.roc "$STAGING_DIR/"

# Create .roc_storage directory structure
mkdir -p "$STAGING_DIR/.roc_storage"

# Create README
cat > "$STAGING_DIR/README.md" << EOF
# Notey - Document Editor

Version: $VERSION
Build Date: $BUILD_DATE

## Quick Start

1. Extract the archive:
   \`\`\`bash
   tar -xzf notey-$VERSION.tar.gz
   cd notey-$VERSION
   \`\`\`

2. Make the binary executable (if not already):
   \`\`\`bash
   chmod +x main
   \`\`\`

3. Run the server:
   \`\`\`bash
   ./main --port 8080
   \`\`\`

4. Access the application at http://localhost:8080

## Configuration

The server accepts the following options:
- \`--port <number>\`: Port to listen on (default: 8080)

## Data Storage

Notey uses SQLite for data persistence. The database is stored in:
- \`.roc_storage/notes.db\`

This directory is created automatically on first run.

## System Requirements

- Linux x86_64 or ARM64
- No external dependencies required (static binary)

## Running as a Service

### Using systemd

Create a service file \`/etc/systemd/system/notey.service\`:

\`\`\`ini
[Unit]
Description=Notey Document Editor
After=network.target

[Service]
Type=simple
User=notey
WorkingDirectory=/opt/notey
ExecStart=/opt/notey/main --port 8080
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
\`\`\`

Then enable and start:

\`\`\`bash
sudo systemctl daemon-reload
sudo systemctl enable notey
sudo systemctl start notey
\`\`\`

### Using Docker

A Dockerfile is included for containerized deployment:

\`\`\`bash
docker build -t notey .
docker run -d -p 8080:8080 -v notey-data:/.roc_storage notey
\`\`\`

## Troubleshooting

### Port already in use
Check what's using port 8080:
\`\`\`bash
sudo lsof -i :8080
\`\`\`

### Permission denied
Ensure the binary is executable:
\`\`\`bash
chmod +x main
\`\`\`

## Support

For issues or questions, please refer to the project repository.
EOF

# Create Dockerfile
cat > "$STAGING_DIR/Dockerfile" << EOF
FROM scratch

WORKDIR /

COPY main /main
COPY static /static
COPY .roc_storage /.roc_storage

EXPOSE 8080

CMD ["/main"]
EOF

# Create systemd service file (optional)
cat > "$STAGING_DIR/notey.service" << EOF
[Unit]
Description=Notey Document Editor
After=network.target

[Service]
Type=simple
User=notey
WorkingDirectory=/opt/notey
ExecStart=/opt/notey/main --port 8080
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Create install script
cat > "$STAGING_DIR/install.sh" << 'EOF'
#!/bin/bash
set -e

INSTALL_DIR="/opt/notey"
SERVICE_USER="notey"

echo "=== Installing Notey ==="

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root or use sudo"
    exit 1
fi

# Create user if it doesn't exist
if ! id "$SERVICE_USER" &>/dev/null; then
    echo "Creating service user: $SERVICE_USER"
    useradd -r -s /bin/false -d "$INSTALL_DIR" "$SERVICE_USER"
fi

# Create installation directory
echo "Installing to $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cp -r * "$INSTALL_DIR/"
chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR"

# Create data directory
mkdir -p "$INSTALL_DIR/.roc_storage"
chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR/.roc_storage"

# Ask about systemd service
read -p "Install as systemd service? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    cp "$INSTALL_DIR/notey.service" /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable notey
    echo "Service installed. Start with: sudo systemctl start notey"
fi

echo "=== Installation complete ==="
echo "Run manually: cd $INSTALL_DIR && sudo -u $SERVICE_USER ./main --port 8080"
echo "Or start service: sudo systemctl start notey"
EOF

chmod +x "$STAGING_DIR/install.sh"

# Create archive
ARCHIVE_NAME="notey-$VERSION-$ARCH.tar.gz"
echo "Creating archive: $ARCHIVE_NAME"
tar -czf "$ARCHIVE_NAME" "$STAGING_DIR"

# Generate checksums
echo "Generating checksums..."
sha256sum "$ARCHIVE_NAME" > "$ARCHIVE_NAME.sha256"
md5sum "$ARCHIVE_NAME" > "$ARCHIVE_NAME.md5"

echo ""
echo "=== Package created successfully ==="
echo "Archive: $ARCHIVE_NAME"
echo "SHA256: $(cat $ARCHIVE_NAME.sha256 | cut -d' ' -f1)"
echo ""
echo "To deploy to a server:"
echo "  scp $ARCHIVE_NAME user@server:/tmp/"
echo "  ssh user@server"
echo "  cd /tmp && tar -xzf $ARCHIVE_NAME && cd notey-release-$VERSION"
echo "  sudo ./install.sh"

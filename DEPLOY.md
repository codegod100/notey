# Notey Deployment Guide

This guide explains how to deploy the Notey document editor to a server using the pre-packaged release archive.

## Quick Deployment

### 1. Download the Archive

Copy the archive to your server:

```bash
scp notey-*.tar.gz user@your-server:/tmp/
```

### 2. Extract and Install

SSH into your server and run:

```bash
ssh user@your-server
cd /tmp
tar -xzf notey-*.tar.gz
cd notey-release-*
sudo ./install.sh
```

The install script will:
- Create a `notey` service user
- Install Notey to `/opt/notey`
- Optionally set up a systemd service

### 3. Start the Server

**Option A: Using systemd (recommended)**
```bash
sudo systemctl start notey
sudo systemctl status notey
```

**Option B: Manual**
```bash
cd /opt/notey
sudo -u notey ./main --port 8080
```

### 4. Access the Application

Open your browser and navigate to:
- `http://your-server:8080`

## Manual Installation

If you prefer manual installation without the install script:

```bash
# Extract archive
tar -xzf notey-*.tar.gz
cd notey-release-*

# Create directory
sudo mkdir -p /opt/notey

# Copy files
sudo cp -r * /opt/notey/

# Create service user
sudo useradd -r -s /bin/false -d /opt/notey notey

# Set permissions
sudo chown -R notey:notey /opt/notey

# Run the server
sudo -u notey /opt/notey/main --port 8080
```

## Running with Docker

If you prefer containerized deployment:

```bash
# Extract archive
tar -xzf notey-*.tar.gz
cd notey-release-*

# Build Docker image
docker build -t notey .

# Run container
docker run -d \
  --name notey \
  -p 8080:8080 \
  -v notey-data:/.roc_storage \
  notey
```

## Configuration

### Command Line Options

- `--port <number>`: Port to listen on (default: 8080)

Example:
```bash
./main --port 9000
```

### Systemd Service

The service file is located at `/etc/systemd/system/notey.service`.

To modify the port or other settings:
```bash
sudo systemctl edit notey
```

Or edit the service file directly:
```bash
sudo nano /etc/systemd/system/notey.service
# Modify ExecStart line
sudo systemctl daemon-reload
sudo systemctl restart notey
```

## Data Persistence

Notey uses SQLite for data storage. The database location:
- **Standalone**: `.roc_storage/notes.db` in the installation directory
- **Docker**: `/.roc_storage/notes.db` in the container volume

### Backup

```bash
# Standalone
tar -czf notey-backup-$(date +%Y%m%d).tar.gz /opt/notey/.roc_storage

# Docker
docker run --rm -v notey-data:/.roc_data -v $(pwd):/backup \
  alpine tar -czf /backup/notey-backup-$(date +%Y%m%d).tar.gz /.roc_data
```

### Restore

```bash
# Standalone
tar -xzf notey-backup-*.tar.gz -C /opt/
sudo chown -R notey:notey /opt/notey/.roc_storage
sudo systemctl restart notey

# Docker
docker run --rm -v notey-data:/.roc_data -v $(pwd):/backup \
  alpine tar -xzf /backup/notey-backup-*.tar.gz -C /
```

## Reverse Proxy Configuration

### Nginx

```nginx
server {
    listen 80;
    server_name notey.yourdomain.com;

    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### Apache

```apache
<VirtualHost *:80>
    ServerName notey.yourdomain.com

    ProxyPreserveHost On
    ProxyPass / http://localhost:8080/
    ProxyPassReverse / http://localhost:8080/
</VirtualHost>
```

## SSL/TLS Setup

### Using Certbot (Let's Encrypt)

```bash
sudo apt install certbot python3-certbot-nginx
sudo certbot --nginx -d notey.yourdomain.com
```

### Manual Certificate

```nginx
server {
    listen 443 ssl;
    server_name notey.yourdomain.com;

    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

## Monitoring

### Check Service Status

```bash
sudo systemctl status notey
```

### View Logs

```bash
# Systemd logs
sudo journalctl -u notey -f

# Or if running manually, check output
```

### Health Check

```bash
curl http://localhost:8080
```

## Troubleshooting

### Service Won't Start

```bash
# Check status
sudo systemctl status notey

# View logs
sudo journalctl -u notey -n 50

# Check if port is in use
sudo lsof -i :8080
```

### Permission Denied

```bash
# Fix permissions
sudo chown -R notey:notey /opt/notey
sudo chmod +x /opt/notey/main
```

### Database Issues

```bash
# Check database directory
ls -la /opt/notey/.roc_storage/

# Verify database integrity
sudo -u notey sqlite3 /opt/notey/.roc_storage/notes.db "PRAGMA integrity_check;"
```

### Port Already in Use

Change the port in the service file or when running manually:

```bash
/opt/notey/main --port 9000
```

## Updating

### Update Procedure

1. Stop the service:
   ```bash
   sudo systemctl stop notey
   ```

2. Backup current installation:
   ```bash
   sudo cp -r /opt/notey /opt/notey.backup
   ```

3. Extract new version:
   ```bash
   tar -xzf notey-new-version.tar.gz
   cd notey-release-new-version
   sudo cp -r * /opt/notey/
   ```

4. Restart the service:
   ```bash
   sudo systemctl start notey
   ```

5. Verify it's working:
   ```bash
   sudo systemctl status notey
   curl http://localhost:8080
   ```

## Uninstalling

```bash
# Stop and disable service
sudo systemctl stop notey
sudo systemctl disable notey

# Remove files
sudo rm -rf /opt/notey
sudo rm /etc/systemd/system/notey.service
sudo systemctl daemon-reload

# Remove service user
sudo userdel notey
```

## Requirements

- **OS**: Linux (x86_64 or ARM64)
- **Memory**: 64MB minimum
- **Disk**: 10MB for application + storage
- **No external dependencies** (static binary)

## Support

For issues or questions:
- Check logs: `sudo journalctl -u notey -f`
- Verify port availability: `sudo lsof -i :8080`
- Check file permissions: `ls -la /opt/notey`

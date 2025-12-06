#!/bin/bash

# ============================================================================
# easypb - Easy PocketBase Server Setup
# https://github.com/anvychow/easypb
# 
# One-command PocketBase server setup for Ubuntu 24.04
# ============================================================================

set -e

VERSION="1.0.0"
PB_VERSION="0.25.8"

echo ""
echo "  ╔═══════════════════════════════════════════╗"
echo "  ║           easypb v$VERSION                   ║"
echo "  ║   Easy PocketBase Server Setup            ║"
echo "  ╚═══════════════════════════════════════════╝"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Please run as root"
    exit 1
fi

# Check Ubuntu version
if ! grep -q "24.04" /etc/os-release; then
    echo "⚠️  Warning: This script is tested on Ubuntu 24.04"
    read -p "Continue anyway? (y/N): " CONTINUE
    if [ "$CONTINUE" != "y" ] && [ "$CONTINUE" != "Y" ]; then
        exit 1
    fi
fi

# Get server IP
SERVER_IP=$(curl -4 -s ifconfig.me)
echo "🌐 Server IP: $SERVER_IP"
echo ""

# Update system
echo "📦 Updating system..."
apt update && apt upgrade -y

# Install dependencies
echo "📦 Installing dependencies..."
apt install -y curl unzip fail2ban ufw

# Setup firewall
echo "🔒 Configuring firewall..."
ufw allow 22
ufw allow 80
ufw allow 443
ufw --force enable

# Start fail2ban
systemctl enable fail2ban
systemctl start fail2ban

# Install Node.js
echo "📦 Installing Node.js 20..."
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

# Install PM2
echo "📦 Installing PM2..."
npm install -g pm2

# Setup PM2 startup
pm2 startup systemd -u root --hp /root
pm2 save --force

# Install Caddy
echo "📦 Installing Caddy..."
apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
apt update
apt install -y caddy

# Clear default Caddyfile
echo "" > /etc/caddy/Caddyfile
systemctl restart caddy

# Download PocketBase
echo "📦 Downloading PocketBase v$PB_VERSION..."
mkdir -p /var/www/pocketbase/instances
cd /var/www/pocketbase
curl -L -o pocketbase.zip "https://github.com/pocketbase/pocketbase/releases/download/v${PB_VERSION}/pocketbase_${PB_VERSION}_linux_amd64.zip"
unzip pocketbase.zip
rm pocketbase.zip
chmod +x pocketbase

# Create pb-create script
echo "📝 Creating pb-create command..."
cat > /usr/local/bin/pb-create << 'CREATEEOF'
#!/bin/bash
set -e

if [ -z "$1" ]; then
    echo "Usage: pb-create <domain>"
    echo "Example: pb-create api.myapp.com"
    exit 1
fi

DOMAIN=$1
NAME=$(echo $DOMAIN | sed 's/\./-/g')
BASE_DIR="/var/www/pocketbase/instances"
PB_BINARY="/var/www/pocketbase/pocketbase"

# Check if instance already exists
if [ -d "$BASE_DIR/$NAME" ]; then
    echo "❌ Instance $NAME already exists"
    exit 1
fi

read -p "Superuser email: " EMAIL
PASSWORD=$(openssl rand -base64 12)

LAST_PORT=$(pm2 jlist 2>/dev/null | grep -o '127\.0\.0\.1:[0-9]*' | grep -o '[0-9]*$' | sort -n | tail -1)
if [ -z "$LAST_PORT" ]; then
    PORT=8090
else
    PORT=$((LAST_PORT + 1))
fi

echo ""
echo "Creating PocketBase instance..."
echo "  Domain: $DOMAIN"
echo "  Name: $NAME"
echo "  Port: $PORT"
echo ""

mkdir -p "$BASE_DIR/$NAME"
cp "$PB_BINARY" "$BASE_DIR/$NAME/"

pm2 start "$BASE_DIR/$NAME/pocketbase" --name "$NAME" -- serve --http=127.0.0.1:$PORT
pm2 save

sleep 2

"$BASE_DIR/$NAME/pocketbase" superuser upsert "$EMAIL" "$PASSWORD"

echo "
$DOMAIN {
    reverse_proxy localhost:$PORT
}" >> /etc/caddy/Caddyfile

systemctl restart caddy

SERVER_IP=$(curl -4 -s ifconfig.me)

echo ""
echo "✅ Done!"
echo ""
echo "════════════════════════════════════════════"
echo "  Domain:   https://$DOMAIN/_/"
echo "  Email:    $EMAIL"
echo "  Password: $PASSWORD"
echo "════════════════════════════════════════════"
echo ""
echo "⚠️  Save these credentials!"
echo ""
echo "📌 DNS: Add A record for $DOMAIN → $SERVER_IP"
CREATEEOF
chmod +x /usr/local/bin/pb-create

# Create pb-delete script
echo "📝 Creating pb-delete command..."
cat > /usr/local/bin/pb-delete << 'DELETEEOF'
#!/bin/bash
set -e

if [ -z "$1" ]; then
    echo "Usage: pb-delete <domain>"
    echo ""
    echo "Current instances:"
    pm2 list
    exit 1
fi

DOMAIN=$1
NAME=$(echo $DOMAIN | sed 's/\./-/g')
BASE_DIR="/var/www/pocketbase/instances"

if [ ! -d "$BASE_DIR/$NAME" ]; then
    echo "❌ Instance $NAME not found"
    exit 1
fi

echo "⚠️  This will delete: $NAME"
echo "   - Stop and remove from PM2"
echo "   - Delete files at $BASE_DIR/$NAME"
echo "   - Remove from Caddy config"
echo ""
read -p "Are you sure? (y/N): " CONFIRM

if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "Cancelled."
    exit 0
fi

pm2 stop "$NAME" 2>/dev/null || true
pm2 delete "$NAME" 2>/dev/null || true
pm2 save

rm -rf "$BASE_DIR/$NAME"

sed -i "/$DOMAIN {/,/}/d" /etc/caddy/Caddyfile

systemctl restart caddy

echo "✅ Deleted: $NAME"
DELETEEOF
chmod +x /usr/local/bin/pb-delete

# Create pb-update script
echo "📝 Creating pb-update command..."
cat > /usr/local/bin/pb-update << 'UPDATEEOF'
#!/bin/bash
set -e

if [ -z "$1" ]; then
    echo "Usage: pb-update <version>"
    echo "Example: pb-update 0.26.0"
    echo ""
    echo "Find latest version at:"
    echo "https://github.com/pocketbase/pocketbase/releases"
    exit 1
fi

VERSION=$1
BASE_DIR="/var/www/pocketbase"

echo "📦 Downloading PocketBase v$VERSION..."
cd $BASE_DIR
curl -L -o pocketbase.zip "https://github.com/pocketbase/pocketbase/releases/download/v${VERSION}/pocketbase_${VERSION}_linux_amd64.zip"
unzip -o pocketbase.zip
rm pocketbase.zip
chmod +x pocketbase

echo "🔄 Updating instances..."
for instance in $BASE_DIR/instances/*/; do
    if [ -d "$instance" ]; then
        NAME=$(basename "$instance")
        echo "  Updating $NAME..."
        cp $BASE_DIR/pocketbase "$instance/"
        pm2 restart "$NAME"
    fi
done

echo ""
echo "✅ All instances updated to v$VERSION"
UPDATEEOF
chmod +x /usr/local/bin/pb-update

# Create pb-list script
echo "📝 Creating pb-list command..."
cat > /usr/local/bin/pb-list << 'LISTEOF'
#!/bin/bash

echo ""
echo "PocketBase Instances:"
echo "════════════════════════════════════════════"
pm2 list
echo ""
echo "Instance directories:"
ls -la /var/www/pocketbase/instances/
LISTEOF
chmod +x /usr/local/bin/pb-list

# Create pb-logs script
echo "📝 Creating pb-logs command..."
cat > /usr/local/bin/pb-logs << 'LOGSEOF'
#!/bin/bash

if [ -z "$1" ]; then
    echo "Usage: pb-logs <domain>"
    echo "Example: pb-logs api.myapp.com"
    echo ""
    echo "Current instances:"
    pm2 list
    exit 1
fi

DOMAIN=$1
NAME=$(echo $DOMAIN | sed 's/\./-/g')

pm2 logs "$NAME"
LOGSEOF
chmod +x /usr/local/bin/pb-logs

echo ""
echo "  ╔═══════════════════════════════════════════╗"
echo "  ║         ✅ Setup Complete!                ║"
echo "  ╚═══════════════════════════════════════════╝"
echo ""
echo "  🌐 Server IP: $SERVER_IP"
echo ""
echo "  📚 Commands:"
echo "  ─────────────────────────────────────────────"
echo "  pb-create api.myapp.com  Create new instance"
echo "  pb-delete api.myapp.com  Delete instance"
echo "  pb-update 0.26.0         Update PocketBase"
echo "  pb-list                  List all instances"
echo "  pb-logs api.myapp.com    View instance logs"
echo ""
echo "  🚀 Get started:"
echo "  pb-create api.yourapp.com"
echo ""

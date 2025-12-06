# easypb

One-command PocketBase server setup for Ubuntu 24.04.

Deploy multiple PocketBase instances with automatic SSL, process management, and simple CLI tools.

## Quick Install

```bash
curl -sL https://raw.githubusercontent.com/anvychow/easypb/main/setup.sh | bash
```

## What it does

- ✅ Installs Node.js 20, PM2, Caddy
- ✅ Downloads latest PocketBase
- ✅ Configures UFW firewall
- ✅ Sets up Fail2ban for security
- ✅ Auto SSL via Caddy (Let's Encrypt)
- ✅ Creates CLI tools for easy management

## Requirements

- Fresh Ubuntu 24.04 server
- Root access
- Domain(s) pointed to your server IP

## Commands

After installation, you get these commands:

| Command | Description |
|---------|-------------|
| `pb-create api.myapp.com` | Create new PocketBase instance |
| `pb-delete api.myapp.com` | Delete an instance |
| `pb-update 0.26.0` | Update all instances to new version |
| `pb-list` | List all running instances |
| `pb-logs api.myapp.com` | View instance logs |

## Usage

### Create an instance

```bash
pb-create api.myapp.com
```

You'll be prompted for:
- Superuser email

A random password will be generated and displayed.

**Before running:** Add an A record for your domain pointing to your server IP.

### Access admin dashboard

```
https://api.myapp.com/_/
```

### Use in your app

```javascript
import PocketBase from 'pocketbase';

const pb = new PocketBase('https://api.myapp.com');
```

### Delete an instance

```bash
pb-delete api.myapp.com
```

### Update PocketBase

```bash
pb-update 0.26.0
```

This updates all instances to the specified version.

## File locations

| Path | Description |
|------|-------------|
| `/var/www/pocketbase/` | Main PocketBase directory |
| `/var/www/pocketbase/instances/` | All instance data |
| `/var/www/pocketbase/instances/<name>/pb_data/` | Instance database & uploads |
| `/etc/caddy/Caddyfile` | Caddy reverse proxy config |

## Backups

Each PocketBase instance has built-in backup features.

1. Go to `https://your-domain.com/_/`
2. Settings → Backups
3. Configure auto-backups or create manual backups
4. Optionally connect S3 for off-server storage

## Security

easypb automatically configures:

- **UFW Firewall** - Only ports 22, 80, 443 open
- **Fail2ban** - Blocks brute force SSH attempts
- **Auto SSL** - HTTPS via Let's Encrypt

## Recommended VPS Providers

- [Hetzner](https://hetzner.com) - Great EU servers
- [RackNerd](https://racknerd.com) - Budget friendly
- [DigitalOcean](https://digitalocean.com) - Easy to use
- [Vultr](https://vultr.com) - Global locations

Minimum specs: 1 CPU, 1GB RAM, 20GB SSD

## Contributing

PRs welcome! Please open an issue first to discuss changes.

## License

MIT License - see [LICENSE](LICENSE)

## Credits

- [PocketBase](https://pocketbase.io) - The amazing backend
- [Caddy](https://caddyserver.com) - Auto SSL reverse proxy
- [PM2](https://pm2.io) - Process manager

---

Made with ❤️ by [anvychow](https://github.com/anvychow)

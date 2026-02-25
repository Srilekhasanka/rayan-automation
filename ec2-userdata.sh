#!/bin/bash
set -euo pipefail

# ─── Log everything ──────────────────────────────────────────────────────────
exec > >(tee /var/log/user-data.log) 2>&1
echo ">>> User data script started at $(date)"

# ─── System updates & dependencies ───────────────────────────────────────────
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y
apt-get install -y \
  git curl wget unzip \
  build-essential \
  xvfb \
  libx11-xcb1 libxcomposite1 libxdamage1 libxrandr2 \
  libxtst6 libcups2 libdrm2 libgbm1 libasound2t64 \
  libatk1.0-0 libatk-bridge2.0-0 libpango-1.0-0 \
  libcairo2 libnss3 libnspr4 libdbus-1-3 \
  fonts-liberation xdg-utils

# ─── Install Node.js 20 ─────────────────────────────────────────────────────
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

# ─── Create app user ─────────────────────────────────────────────────────────
useradd -m -s /bin/bash appuser || true

# ─── Clone the repository ───────────────────────────────────────────────────
cd /home/appuser
sudo -u appuser git clone https://github.com/Srilekhasanka/rayan-automation.git app
cd /home/appuser/app

# ─── Create auth directory (session.json will be pushed separately) ──────────
sudo -u appuser mkdir -p /home/appuser/app/auth

# ─── Create .env file ───────────────────────────────────────────────────────
sudo -u appuser bash -c 'cat > /home/appuser/app/.env << EOF
PORTAL_USERNAME=ITTESTIN
PORTAL_PASSWORD=Rayna@2026
PASSPORT_IMAGE_PATH=data/passports/passport.jpg
EOF'

# ─── Install npm dependencies ───────────────────────────────────────────────
sudo -u appuser npm ci --prefix /home/appuser/app

# ─── Install Playwright Chromium + system deps ──────────────────────────────
sudo -u appuser npx --prefix /home/appuser/app playwright install chromium
npx --prefix /home/appuser/app playwright install-deps chromium

# ─── Xvfb service (virtual display for headed mode) ─────────────────────────
cat > /etc/systemd/system/xvfb.service << 'EOF'
[Unit]
Description=Xvfb Virtual Framebuffer
After=network.target

[Service]
ExecStart=/usr/bin/Xvfb :99 -screen 0 1920x1080x24
Restart=always
User=appuser

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable xvfb
systemctl start xvfb

# ─── Set DISPLAY for appuser ────────────────────────────────────────────────
echo 'export DISPLAY=:99' >> /home/appuser/.bashrc

# ─── Test runner script ─────────────────────────────────────────────────────
sudo -u appuser bash -c 'cat > /home/appuser/app/run-tests.sh << "SCRIPT"
#!/bin/bash
export DISPLAY=:99
cd /home/appuser/app
npm test
SCRIPT
chmod +x /home/appuser/app/run-tests.sh'

# ─── Signal completion ──────────────────────────────────────────────────────
echo ">>> Setup complete at $(date)"
echo "READY" > /home/appuser/setup-complete.flag

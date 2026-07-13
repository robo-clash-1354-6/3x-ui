#!/bin/bash
set -e

echo "🚀 Starting Sanaei Panel + nginx reverse proxy..."

export NGINX_PORT=3000
export PANEL_PORT=2053

# ===== تنظیم مسیر دیتابیس =====
export XUI_DB_PATH="/etc/x-ui/x-ui.db"
echo "📁 Database path: $XUI_DB_PATH"

# ===== بررسی وجود Volume =====
if [ -d "/etc/x-ui" ]; then
    echo "✅ Volume is mounted at /etc/x-ui"
    ls -la /etc/x-ui/
else
    echo "⚠️ Volume is NOT mounted at /etc/x-ui"
fi

# ===== راه‌اندازی Fail2ban =====
echo "🛡️ Starting Fail2ban service..."
mkdir -p /var/run/fail2ban

cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[xray]
enabled = true
port = http,https
filter = xray
logpath = /var/log/x-ui/access.log
maxretry = 3
bantime = 86400
findtime = 600
EOF

cat > /etc/fail2ban/filter.d/xray.conf << 'EOF'
[Definition]
failregex = ^.*\"GET /.* HTTP/1\.[01]\" 404 .*$
ignoreregex =
EOF

fail2ban-server -x start || echo "⚠️ Fail2ban already running"

cd /usr/local/x-ui

# ===== تنظیمات اولیه (فقط در صورت نبود دیتابیس) =====
if [ ! -f "/etc/x-ui/x-ui.db" ]; then
    echo "🔧 First run: Configuring Sanaei Panel on port $PANEL_PORT..."
    ./x-ui setting -port $PANEL_PORT -webBasePath /managepanel/ -username admin -password admin -listenIP 0.0.0.0
else
    echo "✅ Database already exists. Skipping initial configuration."
fi

echo "🔧 Enabling Xray access log..."
./x-ui xray setlog -access /var/log/x-ui/access.log -error /var/log/x-ui/error.log -level warning

echo "🔧 Starting Sanaei Panel..."
./x-ui &

echo "⏳ Waiting 15 seconds..."
sleep 15

echo "📡 Testing connection..."
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:$PANEL_PORT/managepanel/

echo "🔧 Building nginx.conf for port: $NGINX_PORT"

# ===== ایجاد nginx.conf با قابلیت اصلاح لینک =====
cat > /etc/nginx/nginx.conf << 'EOF'
worker_processes 1;
events { worker_connections 1024; }

http {
    include mime.types;

    # تابع برای اصلاح لینک‌های vless
    # تبدیل :8080 به :443 و اضافه کردن TLS
    server {
        listen 3000;

        location /managepanel/ {
            proxy_pass http://127.0.0.1:2053/managepanel/;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        # ===== مسیر ساب‌اسکریپشن با اصلاح لینک =====
        location /sub/ {
            # دریافت ساب از پنل
            proxy_pass http://127.0.0.1:2096/sub/;
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;

            # اصلاح لینک‌ها با sed
            # تبدیل :8080 به :443 و اضافه کردن TLS
            sub_filter_types text/plain;
            sub_filter 's-nl-faryad-production.up.railway.app:8080' 's-nl-faryad-production.up.railway.app:443';
            sub_filter 'security=none' 'security=tls&sni=s-nl-faryad-production.up.railway.app&fp=chrome&insecure=0&allowInsecure=0';
            sub_filter_once off;
        }

        # ===== مسیر اینباند VLESS/WebSocket =====
        location / {
            proxy_pass http://127.0.0.1:8080;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
    }
}
EOF

echo "✅ nginx.conf created successfully!"

echo "▶️ Testing nginx configuration..."
nginx -t

echo "▶️ Starting nginx..."
exec nginx -g "daemon off;"

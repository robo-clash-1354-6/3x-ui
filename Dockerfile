FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    bash \
    ca-certificates \
    sqlite3 \
    nginx \
    gettext-base \
    tzdata \
    fail2ban \
    iptables \
    && ln -sf /usr/share/zoneinfo/Asia/Tehran /etc/localtime \
    && rm -rf /var/lib/apt/lists/*

ENV ARCH=amd64
ENV XUI_VERSION=v3.5.0

RUN echo "Installing Sanaei Panel ${XUI_VERSION}..." && \
    curl -fLR --retry 5 --retry-delay 3 --connect-timeout 15 --max-time 300 -o /tmp/x-ui-linux-${ARCH}.tar.gz "https://github.com/MHSanaei/3x-ui/releases/download/${XUI_VERSION}/x-ui-linux-${ARCH}.tar.gz" && \
    tar -xzf /tmp/x-ui-linux-${ARCH}.tar.gz -C /usr/local/ && \
    rm /tmp/x-ui-linux-${ARCH}.tar.gz && \
    chmod +x /usr/local/x-ui/x-ui

RUN mkdir -p /etc/x-ui /var/log/x-ui /var/run/fail2ban

COPY nginx.conf.template /etc/nginx/nginx.conf.template
COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 3000

CMD ["/start.sh"]

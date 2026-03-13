# ============================================================
# HiClaw Cloud Element Web
# ============================================================
# Thin wrapper around official vectorim/element-web image.
# Adds an entrypoint that injects config.json from environment
# variables before starting nginx.
#
# Build:
#   docker build -f cloud-element/Dockerfile -t hiclaw/cloud-element:latest .
# ============================================================

ARG ELEMENT_BASE=registry.cn-hangzhou.aliyuncs.com/hiclaw-cloud/element-web:20260216

FROM ${ELEMENT_BASE}

# Switch to root to install entrypoint and make /app writable
USER root

COPY cloud-element/entrypoint.sh /hiclaw-entrypoint.sh
RUN chmod +x /hiclaw-entrypoint.sh && \
    chown nginx:nginx /app/config.json

# Switch back to nginx user
USER nginx

ENTRYPOINT ["/hiclaw-entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]

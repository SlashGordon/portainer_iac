FROM vaultwarden/server:latest

RUN apt-get update && apt-get upgrade -y \
    && rm -rf /var/lib/apt/lists/*

COPY docker-entrypoint.sh /entrypoint/docker-entrypoint.sh
RUN chmod +x /entrypoint/docker-entrypoint.sh

# Use non-root user (vaultwarden uses uid 1000)
USER 1000

ENTRYPOINT ["/entrypoint/docker-entrypoint.sh", "/start.sh"]

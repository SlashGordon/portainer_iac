FROM vaultwarden/server:latest

COPY docker-entrypoint.sh /entrypoint/docker-entrypoint.sh
RUN chmod +x /entrypoint/docker-entrypoint.sh

ENTRYPOINT ["/entrypoint/docker-entrypoint.sh", "/start.sh"]

FROM debian:bookworm-slim

ARG WEBHOOK_VERSION=2.8.3

RUN apt-get update \
	&& apt-get upgrade -y \
	&& apt-get install -y --no-install-recommends \
		ca-certificates curl tar tzdata python3 \
	&& rm -rf /var/lib/apt/lists/* \
	&& update-ca-certificates

# Create non-root user
RUN useradd -r -u 1000 -m appuser

# Install adnanh/webhook
RUN ARCH=$(uname -m) \
	&& case "$ARCH" in \
		x86_64) WEBHOOK_ARCH="amd64" ;; \
		aarch64) WEBHOOK_ARCH="arm64" ;; \
		armv7l) WEBHOOK_ARCH="armhf" ;; \
		*) echo "Unsupported architecture: $ARCH" && exit 1 ;; \
	esac \
	&& curl -fsSL "https://github.com/adnanh/webhook/releases/download/${WEBHOOK_VERSION}/webhook-linux-${WEBHOOK_ARCH}.tar.gz" \
		-o /tmp/webhook.tar.gz \
	&& tar -xzf /tmp/webhook.tar.gz -C /tmp \
	&& mv /tmp/webhook-linux-${WEBHOOK_ARCH}/webhook /usr/local/bin/webhook \
	&& chmod +x /usr/local/bin/webhook \
	&& rm -rf /tmp/webhook* \
	&& webhook --version

# Copy webhook configuration and scripts
COPY webhook/hooks.json /etc/webhook/hooks.json
COPY scripts/ /scripts/
RUN chmod +x /scripts/*

# Create directories for DynDNS state and set permissions
RUN mkdir -p /var/lib/dyndns /var/log \
	&& chown -R appuser:appuser /var/lib/dyndns /var/log /scripts

# Switch to non-root user
USER appuser

# Expose webhook port
EXPOSE 9000

# Entrypoint wrapper reads secrets into env vars, then starts webhook
ENTRYPOINT ["/scripts/resolve-secrets.sh"]
CMD ["webhook", "-hooks", "/etc/webhook/hooks.json", "-verbose"]

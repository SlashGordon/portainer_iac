FROM debian:bookworm-slim

ARG NAS_MANAGER_VERSION=v1.0.8
ARG WEBHOOK_VERSION=2.8.1

RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
		ca-certificates curl tar xz-utils tzdata sudo jq \
	&& rm -rf /var/lib/apt/lists/* \
	&& update-ca-certificates

# Quick install nas-manager via official script
RUN curl -fsSL "https://raw.githubusercontent.com/SlashGordon/nas-manager/main/install.sh" -o /tmp/nas-manager-install.sh \
	&& sh /tmp/nas-manager-install.sh "$NAS_MANAGER_VERSION" \
	&& rm -f /tmp/nas-manager-install.sh \
	&& nas-manager --version

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
RUN chmod +x /scripts/*.sh

# Create directories for DynDNS state
RUN mkdir -p /var/lib/dyndns /var/log

# Expose webhook port
EXPOSE 9000

# Start webhook server
ENTRYPOINT ["webhook", "-hooks", "/etc/webhook/hooks.json", "-verbose"]

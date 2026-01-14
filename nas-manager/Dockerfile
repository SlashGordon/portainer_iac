FROM debian:bookworm-slim

ARG NAS_MANAGER_VERSION=v1.0.7

RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
		ca-certificates curl tar xz-utils tzdata sudo \
	&& rm -rf /var/lib/apt/lists/* \
	&& update-ca-certificates

# Quick install nas-manager via official script
RUN curl -fsSL "https://raw.githubusercontent.com/SlashGordon/nas-manager/main/install.sh" -o /tmp/nas-manager-install.sh \
	&& sh /tmp/nas-manager-install.sh "$NAS_MANAGER_VERSION" \
	&& rm -f /tmp/nas-manager-install.sh \
	&& nas-manager --version

# Keep the container alive for Ofelia job-exec to run commands inside it
ENTRYPOINT ["/bin/sh", "-lc", "sleep infinity"]

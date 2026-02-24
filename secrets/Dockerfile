FROM alpine:3.23

# Install Python, SOPS, Age, shadow (for useradd/groupadd), and YAML parser for `unpack`
RUN apk add --no-cache python3 sops age shadow py3-yaml

# Arguments for host user permissions
ARG USER_ID=1000
ARG GROUP_ID=1000

# Create group/user to match host IDs.
# If USER_ID=0 (root), skip user creation (root already exists).
RUN set -eux; \
    if ! getent group "${GROUP_ID}" > /dev/null 2>&1; then \
        groupadd -g "${GROUP_ID}" sopsgroup; \
    fi; \
    if [ "${USER_ID}" != "0" ]; then \
        if ! getent passwd "${USER_ID}" > /dev/null 2>&1; then \
            useradd -l -u "${USER_ID}" -g "${GROUP_ID}" -m sopsuser; \
        fi; \
    fi

# Setup internal paths
WORKDIR /app
RUN mkdir -p /home/sopsuser/.config/sops/age && \
    chown -R ${USER_ID}:${GROUP_ID} /home/sopsuser /app

USER ${USER_ID}:${GROUP_ID}

# Copy script into image
COPY --chown=${USER_ID}:${GROUP_ID} sops_manager.py .
RUN chmod +x sops_manager.py

ENTRYPOINT ["python3", "/app/sops_manager.py"]
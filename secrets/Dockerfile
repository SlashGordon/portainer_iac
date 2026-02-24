FROM alpine:3.23

# Install Python, SOPS, Age, shadow (for useradd/groupadd), and YAML parser for `unpack`
RUN apk add --no-cache python3 sops age shadow py3-yaml

# Arguments for host user permissions
ARG USER_ID=1000
ARG GROUP_ID=1000

# Create group if it doesn't exist, then create user
RUN if ! getent group ${GROUP_ID} > /dev/null; then \
        groupadd -g ${GROUP_ID} sopsgroup; \
    fi && \
    useradd -l -u ${USER_ID} -g ${GROUP_ID} -m sopsuser

# Setup internal paths
WORKDIR /app
RUN mkdir -p /home/sopsuser/.config/sops/age && \
    chown -R sopsuser /home/sopsuser /app

USER sopsuser

# Copy script into image
COPY --chown=sopsuser sops_manager.py .
RUN chmod +x sops_manager.py

ENTRYPOINT ["python3", "/app/sops_manager.py"]
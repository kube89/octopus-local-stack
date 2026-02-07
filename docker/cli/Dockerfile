FROM alpine:3.19

ARG TARGETARCH

# Install dependencies
RUN apk add --no-cache \
    bash \
    curl \
    jq \
    docker-cli \
    docker-cli-compose \
    gum \
    python3 \
    && wget -qO /usr/local/bin/yq "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${TARGETARCH}" \
    && chmod +x /usr/local/bin/yq

# Set working directory
WORKDIR /workspace

# Default to bash
ENTRYPOINT ["/bin/bash"]

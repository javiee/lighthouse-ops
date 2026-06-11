FROM nousresearch/hermes-agent:v2026.5.29.2

RUN ARCH=$(dpkg --print-architecture 2>/dev/null || uname -m) && \
    case "$ARCH" in \
        amd64) ARCH="amd64" ;; \
        arm64) ARCH="arm64" ;; \
        aarch64) ARCH="arm64" ;; \
        *) echo "Unsupported architecture: $ARCH" && exit 1 ;; \
    esac && \
    curl -fsSL -o /tmp/gh.deb "https://github.com/cli/cli/releases/download/v2.71.0/gh_2.71.0_linux_${ARCH}.deb" && \
    apt-get update && \
    apt-get install -y /tmp/gh.deb && \
    rm /tmp/gh.deb && \
    gh --version

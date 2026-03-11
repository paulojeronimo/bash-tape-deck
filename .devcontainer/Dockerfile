FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG YQ_VERSION=v4.45.4

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    bat \
    ca-certificates \
    curl \
    figlet \
    git \
    ncurses-bin \
    shellcheck \
    toilet \
    tree \
    && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
      amd64) yq_arch='amd64' ;; \
      arm64) yq_arch='arm64' ;; \
      *) echo "Unsupported architecture: $arch" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${yq_arch}" -o /usr/local/bin/yq; \
    chmod +x /usr/local/bin/yq

CMD ["sleep", "infinity"]

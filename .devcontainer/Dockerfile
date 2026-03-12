FROM rust:1.85-bookworm AS agg-builder

ARG AGG_GIT_REF=main

RUN apt-get update && apt-get install -y --no-install-recommends \
    libfontconfig1-dev \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

RUN cargo install --root /usr/local --git https://github.com/asciinema/agg --branch "${AGG_GIT_REF}" agg

FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG YQ_VERSION=v4.45.4
ARG AGG_GIT_REF=main

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    asciinema \
    bat \
    ca-certificates \
    curl \
    ffmpeg \
    figlet \
    git \
    ncurses-bin \
    shellcheck \
    toilet \
    tmux \
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

COPY --from=agg-builder /usr/local/bin/agg /usr/local/bin/agg

CMD ["sleep", "infinity"]

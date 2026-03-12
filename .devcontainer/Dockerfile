FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG YQ_VERSION=v4.45.4
ARG AGG_GIT_REF=main

ENV CARGO_HOME=/usr/local/cargo
ENV PATH=${CARGO_HOME}/bin:${PATH}

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    asciinema \
    bat \
    build-essential \
    ca-certificates \
    cargo \
    curl \
    ffmpeg \
    figlet \
    git \
    libfontconfig1-dev \
    libssl-dev \
    ncurses-bin \
    pkg-config \
    rustc \
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

RUN cargo install --root /usr/local --git https://github.com/asciinema/agg --branch "${AGG_GIT_REF}" agg

CMD ["sleep", "infinity"]

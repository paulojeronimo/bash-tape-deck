FROM ubuntu:25.10 AS engine

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV TERM=xterm-256color

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    figlet \
    toilet \
    ncurses-bin \
    bat \
    && rm -rf /var/lib/apt/lists/*

ARG YQ_VERSION=v4.45.4
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
      amd64) yq_arch='amd64' ;; \
      arm64) yq_arch='arm64' ;; \
      *) echo "Unsupported architecture: $arch" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${yq_arch}" -o /usr/local/bin/yq; \
    chmod +x /usr/local/bin/yq

RUN useradd -m -s /bin/bash app

WORKDIR /opt/bash-tape-deck
COPY play.sh rewind.sh functions.sh /opt/bash-tape-deck/
COPY docker/bin/bash-tape-deck /usr/local/bin/bash-tape-deck

RUN chmod +x /usr/local/bin/bash-tape-deck /opt/bash-tape-deck/play.sh /opt/bash-tape-deck/rewind.sh && \
    chown -R app:app /opt/bash-tape-deck

USER app
WORKDIR /workspace

ENV PATH="/opt/bash-tape-deck:${PATH}"
ENV BASH_TAPE_ENGINE_DIR="/opt/bash-tape-deck"
ENV BASH_TAPE_IN_DOCKER="1"
ENV HOME="/home/app"

ENTRYPOINT ["bash-tape-deck"]

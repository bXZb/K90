#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# Runner 镜像自带的 apt 索引可能落后于镜像源（旧版本 deb 被上游撤下，
# 直接 install 会 404，见 run #29）。装之前先刷新索引。
apt-get update

apt-get install -y --no-install-recommends \
  git git-lfs curl wget unzip zip rsync patch \
  python3 python3-pip python3-setuptools \
  build-essential flex bison bc libssl-dev libelf-dev \
  libncurses-dev dwarves cpio \
  default-jre-headless \
  ca-certificates \
  pkg-config \
  openssl libxml2-utils file xxd \
  lz4 zstd xz-utils
apt-get install -y --no-install-recommends python-is-python3 || true

if ! command -v repo >/dev/null 2>&1; then
  curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo \
    -o /usr/local/bin/repo
  chmod a+x /usr/local/bin/repo
fi

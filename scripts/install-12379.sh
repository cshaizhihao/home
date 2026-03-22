#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/cshaizhihao/home.git"
BRANCH="dev"
APP_DIR="/opt/home-site"
CONTAINER_NAME="home-12379"
IMAGE_NAME="home-12379:latest"
HOST_PORT="12379"
CONTAINER_PORT="12445"

log() { echo -e "\033[1;34m[home-installer]\033[0m $*"; }
warn() { echo -e "\033[1;33m[warn]\033[0m $*"; }
err() { echo -e "\033[1;31m[error]\033[0m $*"; }

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    err "请使用 root 执行：sudo bash install-12379.sh"
    exit 1
  fi
}

install_docker_if_needed() {
  if command -v docker >/dev/null 2>&1; then
    log "Docker 已安装，跳过安装步骤"
    return
  fi

  log "检测到未安装 Docker，开始自动安装..."
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y
    apt-get install -y ca-certificates curl gnupg lsb-release
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/$(. /etc/os-release; echo "$ID")/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$(. /etc/os-release; echo "$ID") \
      $(. /etc/os-release; echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  elif command -v dnf >/dev/null 2>&1; then
    dnf -y install dnf-plugins-core
    dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
    dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  elif command -v yum >/dev/null 2>&1; then
    yum -y install yum-utils
    yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    yum -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  else
    err "未识别的系统包管理器，请手动安装 Docker 后重试。"
    exit 1
  fi

  systemctl enable --now docker
}

ensure_git() {
  if command -v git >/dev/null 2>&1; then
    return
  fi

  log "安装 git..."
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y && apt-get install -y git
  elif command -v dnf >/dev/null 2>&1; then
    dnf -y install git
  elif command -v yum >/dev/null 2>&1; then
    yum -y install git
  else
    err "无法自动安装 git，请先手动安装后重试。"
    exit 1
  fi
}

deploy() {
  mkdir -p "$(dirname "$APP_DIR")"

  if [[ -d "$APP_DIR/.git" ]]; then
    log "检测到已有项目目录，执行更新"
    git -C "$APP_DIR" fetch origin "$BRANCH"
    git -C "$APP_DIR" checkout "$BRANCH"
    git -C "$APP_DIR" reset --hard "origin/$BRANCH"
  else
    log "克隆仓库到 $APP_DIR"
    git clone --branch "$BRANCH" "$REPO_URL" "$APP_DIR"
  fi

  log "构建镜像 $IMAGE_NAME"
  docker build -t "$IMAGE_NAME" "$APP_DIR"

  if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    log "移除旧容器 $CONTAINER_NAME"
    docker rm -f "$CONTAINER_NAME" >/dev/null
  fi

  log "启动容器：${HOST_PORT}->${CONTAINER_PORT}"
  docker run -d \
    --name "$CONTAINER_NAME" \
    --restart unless-stopped \
    -p "${HOST_PORT}:${CONTAINER_PORT}" \
    "$IMAGE_NAME" >/dev/null

  log "部署完成 ✅"
  log "访问地址：http://<你的服务器IP>:${HOST_PORT}"
}

main() {
  require_root
  ensure_git
  install_docker_if_needed
  deploy
}

main "$@"

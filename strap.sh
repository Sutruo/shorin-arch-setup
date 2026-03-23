#!/usr/bin/env bash

# ==============================================================================
# 脚本功能说明 (Bootstrap Script for Shorin Arch Setup - Curl Edition)
# 1. 环境防御：严格检测操作系统(仅限Linux)与系统架构(仅限x86_64)。
# 2. 权限自适应：智能识别 root/普通用户，防止 Live CD 环境下缺少 sudo 导致崩溃。
# 3. 依赖准备：极简拉取 curl 和 tar，并提前安全同步并安装 git 供后续环境使用。
# 4. 流式处理：通过 curl 直接拉取 GitHub 的分支源码压缩包，并通过管道无缝解压。
# 5. 高可用拉取：加入 3 次防抖重试机制，应对极端的网络丢包。利用默认表格提供稳定速度显示。
# 6. 一键引导：拉取完成后，无缝切换目录并接管标准输入，提权执行核心安装脚本。
# ==============================================================================

# 启用严格模式：遇到错误、未定义变量或管道错误时立即退出
set -euo pipefail

# --- [颜色配置] ---
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- [环境检测与准备] ---

# 1. 检查是否为 Linux 内核
if [ "$(uname -s)" != "Linux" ]; then
    printf "%bError: This installer only supports Linux systems.%b\n" "$RED" "$NC"
    exit 1
fi

# 2. 检查架构是否匹配 (仅允许 x86_64)
ARCH=$(uname -m)
if [ "$ARCH" != "x86_64" ]; then
    printf "%bError: Unsupported architecture: %s%b\n" "$RED" "$ARCH" "$NC"
    printf "This installer is strictly designed for x86_64 (amd64) systems only.\n"
    exit 1
fi
ARCH_NAME="amd64"

# 3. 极简提权封装 (KISS 原则：是 root 直接跑，不是 root 才加 sudo)
run_as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        # 顺手检测一下有没有 sudo
        if ! command -v sudo >/dev/null 2>&1; then
            printf "%bError: 'sudo' command not found. Please run this script as root.%b\n" "$RED" "$NC"
            exit 1
        fi
        sudo "$@"
    fi
}

# --- [配置区域] ---
TARGET_BRANCH="${BRANCH:-main}"
# GitHub 提供了直接下载指定分支最新源码 tar.gz 压缩包的固定 API
TARBALL_URL="https://github.com/SHORiN-KiWATA/shorin-arch-setup/archive/refs/heads/${TARGET_BRANCH}.tar.gz"

# 强制将引导目录设定在内存盘 /tmp 下
TARGET_DIR="/tmp/shorin-arch-setup"

printf "%b>>> Preparing to install from branch: %s on %s%b\n" "$BLUE" "$TARGET_BRANCH" "$ARCH_NAME" "$NC"

# --- [执行流程] ---

# 1. 检查必要的依赖 (通常现代 Linux 都自带 curl 和 tar，git 为后续安装流程所需)
MISSING_PKGS=()
for cmd in curl tar git; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        MISSING_PKGS+=("$cmd")
    fi
done

if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
    printf "Missing dependencies: %s. Installing...\n" "${MISSING_PKGS[*]}"
    # 使用 -Sy 同步数据库防止 404，使用 --needed 避免重装已存在的包
    run_as_root pacman -Sy --noconfirm --needed "${MISSING_PKGS[@]}"
fi

# 2. 清理旧目录并重新创建
if [ -d "$TARGET_DIR" ]; then
    printf "Removing existing directory '%s'...\n" "$TARGET_DIR"
    run_as_root rm -rf "$TARGET_DIR"
fi
mkdir -p "$TARGET_DIR"

# 3. 流式下载与解压 (防抖重试机制)
printf "Downloading and extracting repository to %s...\n" "$TARGET_DIR"

for attempt in 1 2 3; do
    # 核心解压逻辑：
    # curl -fL: f=遇到HTTP错误直接失败 L=跟随重定向。保留默认进度表格以避免终端排版错乱。
    if curl -fL "$TARBALL_URL" | tar -xz -C "$TARGET_DIR" --strip-components=1; then
        run_as_root chmod 755 "$TARGET_DIR"
        printf "%b\nDownload and extraction successful.%b\n" "$GREEN" "$NC"
        break # 成功则跳出循环
    fi
    
    # 如果达到最后一次尝试依然失败，则彻底退出
    if [ "$attempt" -eq 3 ]; then
        printf "%bError: Failed to download branch '%s' after 3 attempts. Network issue suspected.%b\n" "$RED" "$TARGET_BRANCH" "$NC"
        exit 1
    fi
    
    printf "%bWarning: Download failed (attempt %d/3). Retrying in 3 seconds...%b\n" "$RED" "$attempt" "$NC"
    sleep 3
    
    # 重试前直接删掉整个目录再重建，避免 'rm -rf /*' 无法删除隐藏文件（.gitignore等）导致的残缺堆叠
    run_as_root rm -rf "$TARGET_DIR"
    mkdir -p "$TARGET_DIR"
done

# 4. 运行安装
cd "$TARGET_DIR"
printf "Starting installer...\n"
# 调用提权封装执行核心安装逻辑
run_as_root bash install.sh < /dev/tty

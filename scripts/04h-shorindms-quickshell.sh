#!/bin/bash

# ==============================================================================
# 04-dms-setup.sh - DMS Desktop (Refactored for AUR + shorindms CLI + Verify)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

if [[ -f "$SCRIPT_DIR/00-utils.sh" ]]; then
    source "$SCRIPT_DIR/00-utils.sh"
else
    echo "Error: 00-utils.sh not found in $SCRIPT_DIR."
    exit 1
fi

check_root
VERIFY_LIST="/tmp/shorin_install_verify.list"
rm -f "$VERIFY_LIST"

# --- Identify User & DM Check ---
log "Identifying target user..."
detect_target_user

if [[ -z "$TARGET_USER" || ! -d "$HOME_DIR" ]]; then
    error "Target user invalid or home directory does not exist."
    exit 1
fi

info_kv "Target User" "$TARGET_USER"
check_dm_conflict

# --- Temporary Sudo Privileges ---
log "Granting temporary sudo privileges..."
SUDO_TEMP_FILE="/etc/sudoers.d/99_shorin_installer_temp"
echo "$TARGET_USER ALL=(ALL) NOPASSWD: ALL" > "$SUDO_TEMP_FILE"
chmod 440 "$SUDO_TEMP_FILE"

cleanup_sudo() {
    if [[ -f "$SUDO_TEMP_FILE" ]]; then
        rm -f "$SUDO_TEMP_FILE"
        log "Security: Temporary sudo privileges revoked."
    fi
}
trap cleanup_sudo EXIT INT TERM

# ==============================================================================
# 核心安装逻辑：委托给 AUR 和 shorindms CLI
# ==============================================================================
AUR_HELPER="paru"
CORE_PKG="shorin-dms-niri-git"
section "Shorin DMS" "Installing Meta Environment"

# 1. 委托 AUR 助手安装大包
log "Installing $CORE_PKG environment via AUR..."
if ! as_user "$AUR_HELPER" -S --noconfirm --needed "$CORE_PKG"; then
    error "Failed to install $CORE_PKG"
    exit 1
fi

# --- 动态生成 VERIFY_LIST ---
log "Generating dynamic verification list from Pacman DB..."
echo "$CORE_PKG" >> "$VERIFY_LIST"
# 提取依赖并写入
pacman -Qi "$CORE_PKG" | grep "^Depends On" | cut -d':' -f2- | tr -s ' ' '\n' | sed -e 's/[<>=].*//g' -e '/^$/d' -e '/None/d' >> "$VERIFY_LIST"
log "Added $(wc -l < "$VERIFY_LIST") packages to $VERIFY_LIST."
# -----------------------------

# 2. 调用 shorindms 初始化环境
log "Initializing User Dotfiles and Environment..."
exe as_user shorindms init

# ==============================================================================
# 静态资源部署
# ==============================================================================
section "Shorin DMS" "Wallpapers & Tutorials"

log "Deploying wallpapers..."
WALLPAPER_SOURCE_DIR="$PARENT_DIR/resources/Wallpapers"
WALLPAPER_DIR="$HOME_DIR/Pictures/Wallpapers"
if [ -d "$WALLPAPER_SOURCE_DIR" ]; then
    as_user mkdir -p "$WALLPAPER_DIR"
    force_copy "$WALLPAPER_SOURCE_DIR/." "$WALLPAPER_DIR/"
    chown -R "$TARGET_USER:" "$WALLPAPER_DIR"
fi

log "Copying tutorial files..."
TUTORIAL_SRC="$PARENT_DIR/resources/必看-Shorin-DMS-Niri使用方法.txt"
TUTORIAL_DEST="$HOME_DIR/必看-Shorin-DMS-Niri使用方法.txt"
if [ -f "$TUTORIAL_SRC" ]; then
    as_user cp "$TUTORIAL_SRC" "$TUTORIAL_DEST"
fi

# ==============================================================================
# Finalization & Auto-Login
# ==============================================================================
section "Final" "Auto-Login & Cleanup"
rm -f "$SUDO_TEMP_FILE"

log "Cleaning up legacy TTY autologin configs..."
rm -f /etc/systemd/system/getty@tty1.service.d/autologin.conf 2>/dev/null

if [ "$SKIP_DM" = true ]; then
    log "Display Manager setup skipped (Conflict found or user opted out)."
    warn "You will need to start your session manually from the TTY."
else
    setup_ly
fi

success "Shorin DMS Niri Installation Complete!"
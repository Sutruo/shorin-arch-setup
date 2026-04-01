#!/bin/bash

# ==============================================================================
# 04-niri-setup.sh - Niri Desktop (Refactored for AUR + shorinniri CLI + Verify)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

source "$SCRIPT_DIR/00-utils.sh"
VERIFY_LIST="/tmp/shorin_install_verify.list"
rm -f "$VERIFY_LIST"
DEBUG=${DEBUG:-0}
CN_MIRROR=${CN_MIRROR:-0}
UNDO_SCRIPT="$SCRIPT_DIR/de-undochange.sh"

check_root

# --- [HELPER FUNCTIONS] ---

critical_failure_handler() {
    local failed_reason="$1"
    trap - ERR
    
    echo ""
    echo -e "\033[0;31m################################################################\033[0m"
    echo -e "\033[0;31m#                                                              #\033[0m"
    echo -e "\033[0;31m#   CRITICAL INSTALLATION FAILURE DETECTED                     #\033[0m"
    echo -e "\033[0;31m#                                                              #\033[0m"
    echo -e "\033[0;31m#   Reason: $failed_reason\033[0m"
    echo -e "\033[0;31m#                                                              #\033[0m"
    echo -e "\033[0;31m#   OPTIONS:                                                   #\033[0m"
    echo -e "\033[0;31m#   1. Restore snapshot (Undo changes & Exit)                  #\033[0m"
    echo -e "\033[0;31m#   2. Retry / Re-run script                                   #\033[0m"
    echo -e "\033[0;31m#   3. Abort (Exit immediately)                                #\033[0m"
    echo -e "\033[0;31m#                                                              #\033[0m"
    echo -e "\033[0;31m################################################################\033[0m"
    echo ""
    
    while true; do
        read -p "Select an option [1-3]: " -r choice
        case "$choice" in
            1)
                if [ -f "$UNDO_SCRIPT" ]; then
                    warn "Executing recovery script..."
                    bash "$UNDO_SCRIPT"
                    exit 1
                else
                    error "Recovery script missing! You are on your own."
                    exit 1
                fi
            ;;
            2)
                warn "Restarting installation script..."
                echo "-----------------------------------------------------"
                sleep 1
                exec "$0" "$@"
            ;;
            3)
                warn "User chose to abort."
                warn "Please fix the issue manually before re-running."
                error "Installation aborted."
                exit 1
            ;;
            *)
                echo "Invalid input. Please enter 1, 2, or 3."
            ;;
        esac
    done
}

section "Phase 4" "Niri Desktop Environment"

# ==============================================================================
# STEP 0: Safety Checkpoint & Pre-flight
# ==============================================================================
trap 'critical_failure_handler "Script Error at Line $LINENO"' ERR

detect_target_user
info_kv "Target" "$TARGET_USER"
check_dm_conflict

section "Pre-flight" "Temp sudo file"
SUDO_TEMP_FILE="/etc/sudoers.d/99_shorin_installer_temp"
echo "$TARGET_USER ALL=(ALL) NOPASSWD: ALL" >"$SUDO_TEMP_FILE"
chmod 440 "$SUDO_TEMP_FILE"
log "Temp sudo file created..."

# ==============================================================================
# STEP 1: Install Meta Package & Initialize Environment
# ==============================================================================
section "Step 1/3" "Install Environment & Dotfiles"

AUR_HELPER="paru"
CORE_PKG="shorin-niri-git"

# 1. 委托 AUR 助手安装大包
log "Installing $CORE_PKG and all its dependencies via AUR..."
if ! as_user "$AUR_HELPER" -S --noconfirm --needed "$CORE_PKG"; then
    critical_failure_handler "Failed to install '$CORE_PKG' from AUR."
fi

# --- 动态生成 VERIFY_LIST ---
log "Generating dynamic verification list from Pacman DB..."
echo "$CORE_PKG" >> "$VERIFY_LIST"
# 利用 pacman -Qi 提取该包的所有依赖，去除版本号限制(如 >=1.0)，并追加到列表
pacman -Qi "$CORE_PKG" | grep "^Depends On" | cut -d':' -f2- | tr -s ' ' '\n' | sed -e 's/[<>=].*//g' -e '/^$/d' -e '/None/d' >> "$VERIFY_LIST"
log "Added $(wc -l < "$VERIFY_LIST") packages to $VERIFY_LIST."
# -----------------------------

# 2. 调用 CLI 脚本完成用户环境和系统环境的初始化
log "Running shorinniri initialization..."
exe as_user shorinniri init

# ==============================================================================
# STEP 2: Deploy Static Resources (Wallpapers & Tutorials)
# ==============================================================================
section "Step 2/3" "Static Resources"

log "Deploying wallpapers..."
WALLPAPER_SOURCE_DIR="$PARENT_DIR/resources/Wallpapers"
WALLPAPER_DIR="$HOME_DIR/Pictures/Wallpapers"
if [ -d "$WALLPAPER_SOURCE_DIR" ]; then
    as_user mkdir -p "$WALLPAPER_DIR"
    force_copy "$WALLPAPER_SOURCE_DIR/." "$WALLPAPER_DIR/"
    chown -R "$TARGET_USER:" "$WALLPAPER_DIR"
else
    warn "Wallpaper source directory not found: $WALLPAPER_SOURCE_DIR"
fi

log "Copying tutorial file to home directory..."
TUTORIAL_SRC="$PARENT_DIR/resources/必看-shoirn-Niri使用方法.txt"
TUTORIAL_DEST="$HOME_DIR/必看-Shoirn-Niri使用方法.txt"
if [ -f "$TUTORIAL_SRC" ]; then
    as_user cp "$TUTORIAL_SRC" "$TUTORIAL_DEST"
fi

# ==============================================================================
# STEP 3: Display Manager & Cleanup
# ==============================================================================
section "Step 3/3" "Cleanup & Boot Configuration"

rm -f "$SUDO_TEMP_FILE"

log "Cleaning up legacy TTY autologin configs..."
rm -f /etc/systemd/system/getty@tty1.service.d/autologin.conf 2>/dev/null

if [ "$SKIP_DM" = true ]; then
    log "Display Manager setup skipped (Conflict found or user opted out)."
    warn "You will need to start your session manually from the TTY."
else
    setup_ly
fi

trap - ERR
success "Module 04 completed successfully. Shorin Niri is ready!"
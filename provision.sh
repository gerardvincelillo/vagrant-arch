#!/usr/bin/env bash
# =============================================================================
# provision.sh — ArchDev VM Bootstrap Script
#
# Runs as root via: config.vm.provision "shell", privileged: true
#
# Stages:
#   1. Keyring refresh + full system update
#   2. Package installation (xorg, openbox stack, dev tools)
#   3. Service configuration (NetworkManager, autologin)
#   4. Dotfile/config deployment from /tmp/arch-config
#   5. Auto-startx on tty1 (.bash_profile)
#
# Idempotency: stamp file at $STAMP prevents double-provisioning.
# Remove the stamp and run `vagrant provision` to re-run.
# =============================================================================

set -euo pipefail

# ── Constants ─────────────────────────────────────────────────────────────────
readonly STAMP="/var/lib/.archdev-provision.done"
readonly CONFIG_SRC="/tmp/arch-config"
readonly USER_HOME="/home/vagrant"
readonly VAGRANT_USER="vagrant"

# ── Helpers ───────────────────────────────────────────────────────────────────
log()  { echo "  [archdev] $*"; }
die()  { echo "  [archdev] ERROR: $*" >&2; exit 1; }
step() { echo; echo "══ $* ══"; }

# ── Idempotency Guard ─────────────────────────────────────────────────────────
if [[ -f "$STAMP" ]]; then
    log "Already provisioned. Remove $STAMP and re-run 'vagrant provision' to force."
    exit 0
fi

# ── 1. Pacman Keyring + System Update ────────────────────────────────────────
step "1/7  Keyring & system update"

log "Initializing pacman keyring (required on fresh boxes)..."
pacman-key --init
pacman-key --populate archlinux

log "Syncing package databases and updating keyring before full upgrade..."
pacman -Sy --noconfirm archlinux-keyring
pacman-key --populate archlinux

log "Full system upgrade..."
pacman -Su --noconfirm

# ── 2. Package Installation ───────────────────────────────────────────────────
step "2/7  Installing packages"

# Install all packages in a single transaction.
# --needed skips already-installed packages (safe to re-run if stamp removed).
pacman -S --noconfirm --needed \
    \
    `# ── X Server ──────────────────────────────────` \
    xorg-server \
    xorg-xinit \
    xorg-xrandr \
    xorg-xsetroot \
    \
    `# ── Window Manager Stack ──────────────────────` \
    openbox \
    tint2 \
    rofi \
    picom \
    feh \
    dunst \
    \
    `# ── Terminals ─────────────────────────────────` \
    alacritty \
    xterm \
    \
    `# ── Fonts ─────────────────────────────────────` \
    ttf-dejavu \
    ttf-liberation \
    noto-fonts \
    \
    `# ── Dev Tools ─────────────────────────────────` \
    base-devel \
    git \
    curl \
    wget \
    \
    `# ── System Utilities ──────────────────────────` \
    fastfetch \
    htop \
    tmux \
    xdg-user-dirs \
    networkmanager \
    \
    `# ── Wallpaper ─────────────────────────────────` \
    archlinux-wallpaper

log "Package installation complete."

# ── 3. Services ───────────────────────────────────────────────────────────────
step "3/7  Configuring services"

log "Enabling NetworkManager..."
systemctl enable NetworkManager
systemctl start NetworkManager || true

# ── 4. Autologin on tty1 ──────────────────────────────────────────────────────
step "4/7  Configuring tty1 autologin"

# Drop a systemd override that autologins the vagrant user on tty1.
# On next boot, getty reads this and skips the login prompt.
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << 'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin vagrant --noclear %I $TERM
Type=simple
EOF

systemctl daemon-reload
log "autologin.conf written for vagrant@tty1."

# ── 5. Deploy User Configs ────────────────────────────────────────────────────
step "5/7  Deploying dotfiles"

[[ -d "$CONFIG_SRC" ]] || die "Config source $CONFIG_SRC missing. File provisioner may have failed."

# .xinitrc — starts openbox-session when 'startx' is called
install -m 755 -o "$VAGRANT_USER" -g "$VAGRANT_USER" \
    "$CONFIG_SRC/xinitrc" "$USER_HOME/.xinitrc"

# Openbox
mkdir -p "$USER_HOME/.config/openbox"
install -m 644 -o "$VAGRANT_USER" -g "$VAGRANT_USER" \
    "$CONFIG_SRC/openbox/rc.xml"    "$USER_HOME/.config/openbox/rc.xml"
install -m 644 -o "$VAGRANT_USER" -g "$VAGRANT_USER" \
    "$CONFIG_SRC/openbox/menu.xml"  "$USER_HOME/.config/openbox/menu.xml"
install -m 755 -o "$VAGRANT_USER" -g "$VAGRANT_USER" \
    "$CONFIG_SRC/openbox/autostart" "$USER_HOME/.config/openbox/autostart"

# tint2
mkdir -p "$USER_HOME/.config/tint2"
install -m 644 -o "$VAGRANT_USER" -g "$VAGRANT_USER" \
    "$CONFIG_SRC/tint2/tint2rc" "$USER_HOME/.config/tint2/tint2rc"

# alacritty
mkdir -p "$USER_HOME/.config/alacritty"
install -m 644 -o "$VAGRANT_USER" -g "$VAGRANT_USER" \
    "$CONFIG_SRC/alacritty/alacritty.toml" \
    "$USER_HOME/.config/alacritty/alacritty.toml"

log "Configs deployed to $USER_HOME."

# ── 6. Auto-startx on tty1 ────────────────────────────────────────────────────
step "6/7  Configuring auto-startx"

# Create .bash_profile if it doesn't exist yet
touch "$USER_HOME/.bash_profile"
chown "$VAGRANT_USER:$VAGRANT_USER" "$USER_HOME/.bash_profile"

# Append only if not already present (idempotent)
if ! grep -q "exec startx" "$USER_HOME/.bash_profile" 2>/dev/null; then
    cat >> "$USER_HOME/.bash_profile" << 'EOF'

# ── Auto-start X on tty1 ──────────────────────────────────────────────────────
# When vagrant autologs into tty1, DISPLAY is unset → startx launches Openbox.
# Any other TTY or SSH session gets a normal shell.
if [[ -z "${DISPLAY:-}" ]] && [[ "$(tty)" == "/dev/tty1" ]]; then
    exec startx
fi
EOF
    log ".bash_profile updated with startx trigger."
fi

# ── 7. XDG User Directories ───────────────────────────────────────────────────
step "7/7  Creating XDG user directories"
su - "$VAGRANT_USER" -c "xdg-user-dirs-update" || true

# ── Done ──────────────────────────────────────────────────────────────────────
touch "$STAMP"

echo
echo "╔══════════════════════════════════════════════════════════╗"
echo "║                ArchDev provisioning complete!            ║"
echo "║                                                          ║"
echo "║  Run: vagrant reload                                     ║"
echo "║  → VM reboots → autologin → startx → Openbox desktop     ║"
echo "║                                                          ║"
echo "║  SSH:  vagrant ssh                                       ║"
echo "║  Halt: vagrant halt                                      ║"
echo "╚══════════════════════════════════════════════════════════╝"

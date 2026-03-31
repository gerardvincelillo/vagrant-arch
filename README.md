# ArchDev — Arch Linux Desktop VM

Fully automated Arch Linux VM with Openbox desktop, deployed via `vagrant up`.

---

## Quick Start

```bash
# Prerequisites (install once):
#   VirtualBox >= 6.1   https://www.virtualbox.org/
#   Vagrant    >= 2.3   https://www.vagrantup.com/

vagrant up          # downloads box, provisions (~10-20 min on first run)
vagrant reload      # reboot → triggers autologin → desktop starts
```

After `vagrant reload` the VirtualBox window opens with a full Openbox desktop.

---

## Directory Structure

```
.
├── Vagrantfile                   — VM definition (box, CPU, RAM, display)
├── provision.sh                  — Root-level provisioning (packages, config)
├── README.md                     — This file
└── config/                       — Dotfiles copied into the VM
    ├── xinitrc                   — X session entry point (called by startx)
    ├── openbox/
    │   ├── rc.xml                — Keybindings, theme, desktops, mouse rules
    │   ├── menu.xml              — Right-click desktop menu
    │   └── autostart             — Programs launched by openbox-session
    ├── tint2/
    │   └── tint2rc               — Bottom panel (tasks, clock, systray)
    └── alacritty/
        └── alacritty.toml        — Terminal colours, font, keybindings
```

---

## Base Box — `generic/arch`

| Property | Detail |
|---|---|
| Source | [Roboxes](https://roboxes.org/) — `generic/arch` |
| Base | Rolling Arch Linux |
| VBox Guest Additions | Pre-compiled and bundled |
| Updated | Several times per week |
| Default user | `vagrant` / `vagrant` |

**Why this box, not `archlinux/archlinux`?**  
The official `archlinux/archlinux` box does not ship with VirtualBox Guest
Additions. Without them the display, clipboard, and the file provisioner that
copies `config/` all fail. `generic/arch` includes matching GAs and is tested
against multiple VirtualBox versions.

**Limitation:** because Arch is rolling, a box downloaded today may be days
behind `pacman -Syu`. The provisioner always runs a full upgrade first, so the
final system is current regardless.

---

## Provisioning — Step by Step

`provision.sh` runs as root in a single pass and is guarded by a stamp file
(`/var/lib/.archdev-provision.done`) so it is safe to run `vagrant provision`
without repeating expensive steps.

| Step | What happens |
|---|---|
| 1 | `pacman-key --init && --populate` — refreshes the trust database |
| 2 | `pacman -Syu` — full system upgrade to latest packages |
| 3 | `pacman -S --needed` — installs the package set below |
| 4 | Enables `NetworkManager` via systemd |
| 5 | Writes `/etc/systemd/system/getty@tty1.service.d/autologin.conf` — autologins `vagrant` on tty1 |
| 6 | Deploys `config/` tree to `~/.xinitrc`, `~/.config/openbox/`, `~/.config/tint2/`, `~/.config/alacritty/` with correct ownership |
| 7 | Appends startx trigger to `~/.bash_profile` (tty1 check) |
| 8 | `xdg-user-dirs-update` — creates standard home directories |

### Installed Packages

| Category | Packages |
|---|---|
| X Server | `xorg-server` `xorg-xinit` `xorg-xrandr` `xorg-xsetroot` |
| Window Manager | `openbox` `tint2` `rofi` `picom` `feh` `dunst` |
| Terminals | `alacritty` `xterm` |
| Fonts | `ttf-dejavu` `ttf-liberation` `noto-fonts` |
| Dev Tools | `base-devel` `git` `curl` `wget` |
| Utilities | `fastfetch` `htop` `tmux` `xdg-user-dirs` `networkmanager` |

---

## Desktop Description

### Boot flow

```
systemd boot
  └─ getty@tty1 (autologin: vagrant)
       └─ bash reads ~/.bash_profile
            └─ tty == /dev/tty1 && DISPLAY unset → exec startx
                 └─ ~/.xinitrc
                      └─ exec openbox-session
                           ├─ reads rc.xml
                           └─ runs ~/.config/openbox/autostart
                                ├─ xsetroot -solid "#0f0f1a"
                                ├─ picom &
                                ├─ tint2 &
                                ├─ dunst &
                                └─ alacritty (welcome fastfetch) &
```

### Key Bindings

| Key | Action |
|---|---|
| `Super+Enter` | Open terminal (alacritty) |
| `Ctrl+Alt+T` | Open terminal (alacritty) |
| `Super+Space` | App launcher — rofi (GUI apps) |
| `Super+d` | Command runner — rofi (any binary) |
| `Alt+F4` | Close focused window |
| `Super+f` | Toggle fullscreen |
| `Super+↑` | Maximize window |
| `Super+↓` | Restore window |
| `Super+←` | Tile window to left half |
| `Super+→` | Tile window to right half |
| `Alt+Tab` | Cycle windows (forward) |
| `Alt+Shift+Tab` | Cycle windows (backward) |
| `Super+1/2/3` | Switch to desktop Dev / Web / Tools |
| `Super+Shift+1/2/3` | Move window to desktop 1/2/3 |
| `Super+r` | Reload Openbox config live |
| Right-click desktop | Root menu |
| Middle-click desktop | Window list |

---

## Debugging

### No display / black screen after `vagrant reload`

**Cause:** VirtualBox Guest Additions kernel module (`vboxguest`) failed to
load, or the display driver wasn't activated.

```bash
# Inside the VM via vagrant ssh:
lsmod | grep vbox              # should show vboxguest, vboxsf, vboxvideo
sudo modprobe vboxguest        # load manually if missing
sudo systemctl restart getty@tty1
```

If GAs are mismatched with your VirtualBox version:
```bash
vagrant plugin install vagrant-vbguest   # auto-manages GA versions
vagrant reload
```

### `startx` fails — "cannot open display"

```bash
# Check Xorg log:
cat /var/log/Xorg.0.log | grep -E "EE|WW"

# Common fixes:
sudo pacman -S xf86-video-vesa      # generic fallback video driver
sudo pacman -S xf86-video-vmware    # if using VMware backend
```

### Desktop starts but tint2 panel is missing

```bash
# Start manually in a terminal (shows error output):
tint2 &

# Validate config syntax:
tint2 -c ~/.config/tint2/tint2rc
```

### picom causes visual glitches or high CPU

Edit `~/.config/openbox/autostart` and remove or simplify the picom line:
```bash
# Minimal picom (shadows off, no opacity):
picom --backend xrender &
```
Or comment it out entirely — picom is purely cosmetic.

### rofi shows no apps

```bash
# Rebuild desktop database:
update-desktop-database ~/.local/share/applications
```

### pacman keyring errors during provisioning

```bash
# Inside VM:
sudo pacman-key --refresh-keys     # re-downloads keys (slow, ~5 min)
sudo pacman-key --populate archlinux
sudo pacman -Syu
```

### Re-run provisioning from scratch

```bash
# Remove the stamp file and re-provision:
vagrant ssh -c "sudo rm /var/lib/.archdev-provision.done"
vagrant provision
```

---

## Future Extensibility

This VM is a clean base. Extend `provision.sh` with additional package blocks:

### Security / Penetration Testing Lab

```bash
pacman -S --noconfirm --needed \
    nmap wireshark-qt metasploit zaproxy \
    john hashcat aircrack-ng \
    python-scapy tcpdump netcat
```

Add a dedicated desktop in `rc.xml`:
```xml
<name>Sec</name>
```

### AI / ML Environment

```bash
pacman -S --noconfirm --needed python python-pip cuda   # if GPU passthrough
pip install torch torchvision transformers jupyter
```

Or install via conda for isolated environments:
```bash
curl -sL https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh | bash
```

### Custom OS / Hardened Baseline

- Replace `generic/arch` with a custom Packer-built box
- Add SELinux / AppArmor profiles
- Layer a display manager (LightDM) over the `startx` method for multi-user support
- Add a custom Plymouth boot splash

---

## Helpful Commands

```bash
vagrant up            # create and provision VM
vagrant reload        # reboot (needed after provisioning to activate autologin)
vagrant halt          # graceful shutdown
vagrant suspend       # save VM state to disk
vagrant resume        # restore from suspend
vagrant ssh           # SSH into VM
vagrant provision     # re-run provisioning scripts
vagrant destroy       # delete VM and all disk state
vagrant box update    # pull latest generic/arch box version
```

---

## Credentials

| Field | Value |
|---|---|
| SSH user | `vagrant` |
| SSH password | `vagrant` |
| sudo | passwordless via `/etc/sudoers.d/vagrant` |

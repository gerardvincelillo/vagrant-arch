# -*- mode: ruby -*-
# vi: set ft=ruby :
# =============================================================================
# ArchDev — Arch Linux Desktop VM
#
# Base box : generic/arch  (Roboxes — rolling Arch, VirtualBox GAs bundled)
# Provider : VirtualBox
# Desktop  : Openbox + tint2 + rofi + alacritty
#
# Usage:
#   vagrant up           — provision and boot (first run ~10-15 min)
#   vagrant reload       — reboot to activate autologin + desktop
#   vagrant ssh          — CLI access
#   vagrant halt         — graceful shutdown
#   vagrant destroy      — delete VM
# =============================================================================

Vagrant.configure("2") do |config|

  # ── Base Box ───────────────────────────────────────────────────────────────
  # generic/arch (Roboxes):
  #   - Ships with VirtualBox Guest Additions pre-compiled
  #   - Rolling Arch base, updated multiple times per week
  #   - Reliable /vagrant mount and network support
  #   - Limitation: box version may lag a few days behind bleeding-edge Arch
  config.vm.box      = "generic/arch"
  config.vm.hostname = "archdev"

  # Disable default /vagrant synced folder (requires vboxsf kernel module;
  # skip it to avoid boot failures if GA version drifts)
  config.vm.synced_folder ".", "/vagrant", disabled: true

  # ── VirtualBox Provider ────────────────────────────────────────────────────
  config.vm.provider "virtualbox" do |vb|
    vb.name   = "ArchDev"
    vb.gui    = true   # open VirtualBox display window (required for desktop)
    vb.memory = 2048   # 2 GB — minimum comfortable for Openbox + dev tools
    vb.cpus   = 2

    # 128 MB VRAM; VMSVGA is the modern VBox controller (replaces VBoxVGA)
    # 3D acceleration OFF — picom uses xrender backend to avoid glx failures
    vb.customize ["modifyvm", :id, "--vram",               "128"]
    vb.customize ["modifyvm", :id, "--graphicscontroller", "vmsvga"]
    vb.customize ["modifyvm", :id, "--accelerate3d",       "off"]

    # Bidirectional clipboard via Guest Additions
    # (drag-and-drop disabled — causes VERR_TIMEOUT with VMSVGA on Linux)
    vb.customize ["modifyvm", :id, "--clipboard",          "bidirectional"]
    vb.customize ["modifyvm", :id, "--draganddrop",        "disabled"]

    # No audio device needed for a dev VM
    vb.customize ["modifyvm", :id, "--audio",              "none"]
  end

  # ── Provisioners (run in order) ────────────────────────────────────────────

  # 1. Upload config tree into the guest via SCP (no kernel modules required;
  #    works even if vboxsf is temporarily unavailable during first boot)
  config.vm.provision "file",
    source:      "config",
    destination: "/tmp/arch-config"

  # 2. System provisioning — runs as root
  config.vm.provision "shell",
    name:       "arch-desktop-setup",
    path:       "provision.sh",
    privileged: true

end

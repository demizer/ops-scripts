#!/bin/bash

# Package installer for motorhead
# Simple package installation - no error recovery

# Check if running on Arch Linux
if [[ ! -f /etc/arch-release ]]; then
    echo "This script must be run on Arch Linux"
    exit 1
fi

# Packages explicitly installed on motorhead host
PACKAGES=(
    7zip
    annotator
    archiso
    asciiquarium
    aspell-en
    atuin
    aurutils
    bats
    binutils
    binwalk
    bluez-utils
    bridge-utils
    btrfs-progs
    chromium
    claude-code
    codespell
    cpanminus
    cups
    cursor-bin
    datagrip
    datagrip-jre
    dconf-editor
    devtools
    docker
    docker-buildx
    docker-compose
    dosfstools
    dpkg
    dust-git
    e2fsprogs
    efibootmgr
    eog
    epiphany
    evince
    eza
    fatresize
    file-roller
    filezilla
    firefox
    flameshot
    fwupd
    fzf
    game-devices-udev
    gimp
    git
    gnome
    gnome-circle
    gnome-extra
    gdm
    go
    grilo-plugins
    gst-libav
    gst-plugins-ugly
    gvfs
    gvfs-afc
    gvfs-goa
    gvfs-google
    gvfs-gphoto2
    gvfs-mtp
    gvfs-nfs
    gvfs-smb
    handbrake
    hexedit
    htop
    inetutils
    insomnia
    jfrog-cli
    jq
    just
    kitty
    krita
    lazygit
    libfido2
    librecad
    libreoffice-fresh
    libva-utils
    libva-vdpau-driver-vp9-git
    libxcrypt-compat
    localsearch
    lshw
    lua-language-server
    luacheck
    lvm2
    m4
    make
    man-db
    memtest86+
    minicom
    mtr
    mutter
    mypaint
    mysql-clients80
    mysql-workbench
    nautilus
    net-tools
    networkmanager-openconnect
    networkmanager-openvpn
    nfs-utils
    ngrep
    nmap
    nomachine
    noto-fonts
    npm
    ntfs-3g
    ntp
    obs-studio
    obsidian
    openbsd-netcat
    openconnect
    openconnect-sso
    openshot
    openssh
    orca
    pacman-contrib
    pacnews-neovim
    pam-u2f
    pandoc-cli
    parted
    patch
    patchelf
    pkgconf
    pop-launcher-git
    postgresql
    postman-bin
    powerline-fonts
    prettier
    pv
    pycharm-professional
    pyright
    python
    python-jaraco.classes
    python-pip
    python-pipx
    qmk
    qt6-wayland
    quicklisp
    raylib
    reflector
    remmina
    ripgrep
    rsync
    rustrover
    rustup
    rygel
    samba
    sbcl
    scdoc
    sdl2_mixer
    sdl2_ttf
    shellcheck
    simple-scan
    slack-desktop
    solaar
    strace
    sushi
    switcheroo-control
    syslinux
    texinfo
    thermald
    tinysparql
    tk
    tmux
    tree
    ttf-dejavu
    ttf-font-awesome
    ttf-inconsolata
    ttf-liberation
    ttf-nerd-fonts-symbols
    unzip
    usbutils
    uv
    vault
    vifm
    vlc
    wget
    wireguard-tools
    wl-clipboard
    xf86-input-wacom
    yubikey-manager
)

echo "Installing ${#PACKAGES[@]} packages..."

# Update package database
pacman -Sy --noconfirm

# Install all packages at once - let pacman handle dependencies and conflicts
pacman -S --needed --noconfirm "${PACKAGES[@]}"

echo "Package installation completed"

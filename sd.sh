#!/bin/bash

# Vérification des privilèges root
if [ "$(id -u)" -ne 0 ]; then
    echo "Ce script doit être exécuté en tant que root."
    exit 1
fi

# Détection de l'utilisateur courant (hors root)
USER=$(logname)
USER_HOME=$(eval echo ~$USER)

echo "Mise à jour du système..."
pacman -Syu --noconfirm

echo "Installation des pilotes graphiques..."
pacman -S --noconfirm \
    mesa xf86-video-vesa \
    libva-mesa-driver mesa-vdpau

# Vérification si on est dans une VM
if hostnamectl | grep -q "VirtualBox"; then
    echo "Installation des pilotes pour VirtualBox..."
    pacman -S --noconfirm virtualbox-guest-utils
    systemctl enable vboxservice
elif lspci | grep -q "NVIDIA"; then
    echo "Installation des pilotes NVIDIA..."
    pacman -S --noconfirm nvidia nvidia-utils nvidia-settings
elif lspci | grep -q "Intel"; then
    echo "Installation des pilotes Intel..."
    pacman -S --noconfirm xf86-video-intel
elif lspci | grep -q "AMD"; then
    echo "Installation des pilotes AMD..."
    pacman -S --noconfirm xf86-video-amdgpu
fi

echo "Installation de Hyprland et des outils nécessaires..."
pacman -S --noconfirm \
    xorg-server xorg-xinit \
    hyprland waybar rofi kitty \
    firefox thunar pavucontrol \
    pipewire pipewire-pulse wireplumber \
    neovim git wget curl unzip

echo "Installation du gestionnaire de connexion SDDM..."
pacman -S --noconfirm sddm
systemctl enable sddm

echo "Ajout de la configuration de Hyprland..."
mkdir -p "$USER_HOME/.config/hypr"
echo "exec Hyprland" > "$USER_HOME/.xinitrc"
chown -R $USER:$USER "$USER_HOME/.config"

echo "Installation terminée ! Redémarrage dans 5 secondes..."
sleep 5
reboot

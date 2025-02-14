#!/bin/bash

# Variables
USERNAME="user"
PASSWORD="azerty123"
HOSTNAME="arch-machine"
ROOT_PASSWORD="azerty123"
LUKS_PASSWORD="azerty123"
SWAP_SIZE="2G"
ROOT_SIZE="20G"
HOME_SIZE="30G"
SHARED_SIZE="5G"
VIRTUALBOX_SIZE="10G"
SECURE_SIZE="10G"

# Partitionnement du disque
sgdisk -Z /dev/sda
sgdisk -n 1:0:+512M -t 1:EF00 /dev/sda
sgdisk -n 2:0:0 -t 2:8E00 /dev/sda

# Formatage de la partition EFI
mkfs.fat -F32 /dev/sda1

# Chiffrement du disque
echo -n "$LUKS_PASSWORD" | cryptsetup luksFormat --type luks2 /dev/sda2 -
echo -n "$LUKS_PASSWORD" | cryptsetup open /dev/sda2 cryptroot

# Création des volumes logiques
pvcreate /dev/mapper/cryptroot
vgcreate vg0 /dev/mapper/cryptroot
lvcreate -L $SWAP_SIZE -n swap vg0
lvcreate -L $ROOT_SIZE -n root vg0
lvcreate -L $HOME_SIZE -n home vg0
lvcreate -L $SHARED_SIZE -n shared vg0
lvcreate -L $VIRTUALBOX_SIZE -n virtualbox vg0
lvcreate -L $SECURE_SIZE -n secure vg0

# Formatage des volumes logiques
mkfs.ext4 /dev/vg0/root
mkfs.ext4 /dev/vg0/home
mkfs.ext4 /dev/vg0/shared
mkfs.ext4 /dev/vg0/virtualbox
mkfs.ext4 /dev/vg0/secure
mkswap /dev/vg0/swap
swapon /dev/vg0/swap

# Montage des systèmes de fichiers
mount /dev/vg0/root /mnt
mkdir /mnt/home
mkdir /mnt/shared
mkdir /mnt/virtualbox
mkdir /mnt/secure
mount /dev/vg0/home /mnt/home
mount /dev/vg0/shared /mnt/shared
mount /dev/vg0/virtualbox /mnt/virtualbox
mount /dev/vg0/secure /mnt/secure
mkdir /mnt/boot
mount /dev/sda1 /mnt/boot

# Installation des paquets de base
pacstrap /mnt base linux linux-firmware

# Génération du fichier fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Configuration du système
arch-chroot /mnt /bin/bash <<EOF
ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "$HOSTNAME" > /etc/hostname
echo "127.0.0.1 localhost" >> /etc/hosts
echo "::1 localhost" >> /etc/hosts
echo "127.0.1.1 $HOSTNAME.localdomain $HOSTNAME" >> /etc/hosts

# Configuration de mkinitcpio
sed -i 's/HOOKS=(base udev autodetect modconf block filesystems keyboard fsck)/HOOKS=(base udev autodetect modconf block encrypt lvm2 filesystems keyboard fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P

# Configuration de GRUB
pacman -S grub efibootmgr
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Configuration du mot de passe root
echo "root:$ROOT_PASSWORD" | chpasswd

# Création de l'utilisateur
useradd -m -G wheel -s /bin/bash $USERNAME
echo "$USERNAME:$PASSWORD" | chpasswd

# Installation de sudo
pacman -S sudo
sed -i 's/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers

# Installation des outils et environnements demandés
pacman -S virtualbox virtualbox-host-dkms gcc make base-devel git vim firefox

# Configuration de Hyprland
sudo -u $USERNAME git clone https://github.com/hyprwm/Hyprland.git /home/$USERNAME/Hyprland
sudo -u $USERNAME mkdir -p /home/$USERNAME/.config/hypr
sudo -u $USERNAME cp /home/$USERNAME/Hyprland/configs/example.conf /home/$USERNAME/.config/hypr/hyprland.conf

# Configuration des permissions pour le volume sécurisé
chown $USERNAME:$USERNAME /mnt/secure
chmod 700 /mnt/secure

# Configuration des permissions pour le dossier partagé
chown $USERNAME:$USERNAME /mnt/shared
chmod 770 /mnt/shared

EOF

# Démonter les systèmes de fichiers
umount -R /mnt
swapoff /dev/vg0/swap
cryptsetup close cryptroot

# Fin du script
echo "Installation terminée. Vous pouvez redémarrer votre machine."

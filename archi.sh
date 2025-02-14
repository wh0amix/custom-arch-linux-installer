#!/bin/bash

# Variables
DISK="/dev/sda"
HOSTNAME="archlinux"
USER1="collegue"
USER2="fils"
PASSWORD="azerty123"
LUKS_PART="/dev/sda3"
LUKS_MAPPER="cryptlvm"
VG_NAME="vg0"
LV_ROOT="lv_root"
LV_SHARED="lv_shared"
LV_VIRTUALBOX="lv_virtualbox"
LV_CRYPT="lv_crypt"
TIMEZONE="Europe/Paris"
LOCALE="fr_FR.UTF-8"

# Partitionnement
echo "Partitionnement du disque..."
parted -s $DISK mklabel gpt
parted -s $DISK mkpart primary fat32 1MiB 513MiB
parted -s $DISK set 1 esp on
parted -s $DISK mkpart primary ext4 513MiB 20GiB
parted -s $DISK mkpart primary 20GiB 30GiB
parted -s $DISK mkpart primary 30GiB 35GiB
parted -s $DISK mkpart primary 35GiB 100%

# Chiffrement LUKS
echo "Configuration de LUKS..."
cryptsetup luksFormat $LUKS_PART
cryptsetup open $LUKS_PART $LUKS_MAPPER

# LVM
echo "Configuration de LVM..."
pvcreate /dev/mapper/$LUKS_MAPPER
vgcreate $VG_NAME /dev/mapper/$LUKS_MAPPER
lvcreate -L 40G -n $LV_ROOT $VG_NAME
lvcreate -L 5G -n $LV_SHARED $VG_NAME
lvcreate -L 10G -n $LV_VIRTUALBOX $VG_NAME
lvcreate -L 10G -n $LV_CRYPT $VG_NAME

# Formatage
echo "Formatage des partitions..."
mkfs.fat -F32 /dev/sda1
mkfs.ext4 /dev/$VG_NAME/$LV_ROOT
mkfs.ext4 /dev/$VG_NAME/$LV_SHARED
mkfs.ext4 /dev/$VG_NAME/$LV_VIRTUALBOX
mkfs.ext4 /dev/$VG_NAME/$LV_CRYPT

# Montage
echo "Montage des partitions..."
mount /dev/$VG_NAME/$LV_ROOT /mnt
mkdir /mnt/boot
mount /dev/sda1 /mnt/boot
mkdir /mnt/shared
mount /dev/$VG_NAME/$LV_SHARED /mnt/shared
mkdir /mnt/virtualbox
mount /dev/$VG_NAME/$LV_VIRTUALBOX /mnt/virtualbox

# Installation des paquets de base
echo "Installation des paquets de base..."
pacstrap /mnt base linux linux-firmware vim networkmanager grub efibootmgr lvm2

# Génération de fstab
echo "Génération de fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# Configuration système
echo "Configuration du système..."
arch-chroot /mnt ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
arch-chroot /mnt hwclock --systohc
arch-chroot /mnt sed -i "s/#$LOCALE/$LOCALE/" /etc/locale.gen
arch-chroot /mnt locale-gen
arch-chroot /mnt echo "LANG=$LOCALE" > /etc/locale.conf
arch-chroot /mnt echo $HOSTNAME > /etc/hostname
arch-chroot /mnt echo "127.0.0.1 localhost" >> /etc/hosts
arch-chroot /mnt echo "::1       localhost" >> /etc/hosts
arch-chroot /mnt echo "127.0.1.1 $HOSTNAME.localdomain $HOSTNAME" >> /etc/hosts

# Bootloader
echo "Installation du bootloader..."
arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

# Utilisateurs
echo "Création des utilisateurs..."
arch-chroot /mnt useradd -m -G wheel -s /bin/bash $USER1
arch-chroot /mnt useradd -m -s /bin/bash $USER2
arch-chroot /mnt echo "$USER1:$PASSWORD" | chpasswd
arch-chroot /mnt echo "$USER2:$PASSWORD" | chpasswd

# Outils supplémentaires
echo "Installation des outils supplémentaires..."
arch-chroot /mnt pacman -S --noconfirm xorg-server xorg-xinit hyprland virtualbox firefox code

# Configuration de Hyprland
echo "Configuration de Hyprland..."
mkdir -p /mnt/home/$USER1/.config/hypr
echo "exec Hyprland" > /mnt/home/$USER1/.config/hypr/hyprland.conf

# Dossier partagé
echo "Configuration du dossier partagé..."
chown $USER1:$USER1 /mnt/shared
chmod 770 /mnt/shared

# Finalisation
echo "Finalisation..."
umount -R /mnt
echo "Installation terminée ! Redémarrage dans 5 secondes..."
sleep 5
reboot
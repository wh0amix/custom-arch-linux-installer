#!/bin/bash

# Variables
LUKS_PASS="azerty123"
LVM_VG="volgroup"
LVM_LV_SIZE="10G"
LVM_VBOX_SIZE="20G"
LVM_SHARED_SIZE="5G"
ROOT_MOUNT="/mnt"
EFI_PARTITION="/dev/sda1"
DISK="/dev/sda"
MOUNT_LVM="/mnt/lvm"
HYPRLAND_CONF="/mnt/home/coworker/.config/hyprland"

# Fonction pour créer et chiffrer le disque
encrypt_disk() {
    echo -n "$LUKS_PASS" | cryptsetup luksFormat $DISK
    echo -n "$LUKS_PASS" | cryptsetup open $DISK cryptdisk
}

# Fonction pour créer LVM
create_lvm() {
    pvcreate /dev/mapper/cryptdisk
    vgcreate $LVM_VG /dev/mapper/cryptdisk

    # Création des volumes logiques
    lvcreate -L $LVM_LV_SIZE -n root $LVM_VG
    lvcreate -L $LVM_VBOX_SIZE -n vbox $LVM_VG
    lvcreate -L $LVM_SHARED_SIZE -n shared $LVM_VG
}

# Fonction pour partitionner et formater
partition_and_format() {
    # Création des partitions EFI et LVM
    mkfs.fat -F32 $EFI_PARTITION
    mkfs.ext4 /dev/$LVM_VG/root
    mkfs.ext4 /dev/$LVM_VG/vbox
    mkfs.ext4 /dev/$LVM_VG/shared
}

# Montage des partitions
mount_partitions() {
    mount /dev/$LVM_VG/root $ROOT_MOUNT
    mkdir -p $ROOT_MOUNT/boot/efi
    mount $EFI_PARTITION $ROOT_MOUNT/boot/efi
}

# Installation de base
install_base() {
    pacstrap $ROOT_MOUNT base base-devel linux linux-firmware vim grub efibootmgr lvm2
}

# Configuration du système
configure_system() {
    genfstab -U $ROOT_MOUNT >> $ROOT_MOUNT/etc/fstab

    # Chroot dans l'environnement
    arch-chroot $ROOT_MOUNT /bin/bash <<EOF
    # Configuration du fuseau horaire
    ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
    hwclock --systohc

    # Configuration des locales
    echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
    locale-gen
    echo "LANG=en_US.UTF-8" > /etc/locale.conf

    # Configuration du hostname
    echo "coworker-pc" > /etc/hostname
    EOF
}

# Installation de GRUB et configuration du boot
install_grub() {
    arch-chroot $ROOT_MOUNT grub-install --target=x86_64-efi --efi-directory=$ROOT_MOUNT/boot/efi --bootloader-id=arch
    arch-chroot $ROOT_MOUNT grub-mkconfig -o /boot/grub/grub.cfg
}

# Installation de Hyprland, VirtualBox et autres logiciels
install_software() {
    arch-chroot $ROOT_MOUNT pacman -S --noconfirm hyprland virtualbox virtualbox-host-modules-arch firefox xterm
    arch-chroot $ROOT_MOUNT systemctl enable display-manager
}

# Configuration de l'utilisateur
configure_user() {
    arch-chroot $ROOT_MOUNT useradd -m coworker
    echo "coworker:$LUKS_PASS" | chpasswd
    arch-chroot $ROOT_MOUNT useradd -m son
    echo "son:$LUKS_PASS" | chpasswd

    # Créer les dossiers partagés
    mkdir -p $ROOT_MOUNT/home/coworker/shared
    mkdir -p $ROOT_MOUNT/home/son/shared
    chmod 777 $ROOT_MOUNT/home/coworker/shared
    chmod 777 $ROOT_MOUNT/home/son/shared
}

# Script principal
main() {
    # Initialisation
    encrypt_disk
    create_lvm
    partition_and_format
    mount_partitions
    install_base
    configure_system
    install_grub
    install_software
    configure_user

    echo "Installation terminée. Vous pouvez maintenant configurer et utiliser le système."
}

main

#!/bin/bash

LOGFILE="arch_install.log"
exec > >(tee -a "$LOGFILE") 2>&1  # Redirige la sortie vers le log

set -e  # Stoppe le script en cas d'erreur

# Vérification du mode root
if [[ $EUID -ne 0 ]]; then
    echo "Ce script doit être exécuté en tant que root."
    exit 1
fi

# Vérification de la connexion Internet
if ! ping -c 1 archlinux.org &> /dev/null; then
    echo "Pas d'accès à Internet. Veuillez vous connecter avant de continuer."
    exit 1
fi

# Demande du disque cible
DISK=$(lsblk -dpn -o NAME,SIZE | grep -E "/dev/sd|nvme|mmcblk" | dialog --stdout --menu "Sélectionnez le disque cible" 15 50 10 $(awk '{print $1, "(" $2 ")"}' ))
if [[ -z "$DISK" ]]; then
    echo "Aucun disque sélectionné, arrêt du script."
    exit 1
fi

# Demande du mot de passe pour LUKS
LUKS_PASS=$(dialog --stdout --insecure --passwordbox "Entrez un mot de passe pour le chiffrement LUKS" 10 50)
if [[ -z "$LUKS_PASS" ]]; then
    echo "Mot de passe LUKS non défini, arrêt du script."
    exit 1
fi

# Partitionnement et chiffrement du disque
echo "Partitionnement et formatage du disque..."
wipefs --all --force "$DISK"
parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart ESP fat32 1MiB 512MiB
parted -s "$DISK" set 1 esp on
parted -s "$DISK" mkpart primary 512MiB 100%

# Formatage et chiffrement
ESP_PART="${DISK}1"
ROOT_PART="${DISK}2"
echo -n "$LUKS_PASS" | cryptsetup luksFormat "$ROOT_PART"
echo -n "$LUKS_PASS" | cryptsetup open "$ROOT_PART" cryptroot
mkfs.fat -F32 "$ESP_PART"
mkfs.ext4 /dev/mapper/cryptroot

# Montage des partitions
mount /dev/mapper/cryptroot /mnt
mkdir -p /mnt/boot
mount "$ESP_PART" /mnt/boot

# Installation de base
echo "Installation de base d'Arch Linux..."
pacstrap /mnt base linux linux-firmware vim grub efibootmgr lvm2 dialog networkmanager

# Génération du fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Configuration système
arch-chroot /mnt /bin/bash <<EOF
echo "Configuration du système..."

# Localisation
echo "LANG=fr_FR.UTF-8" > /etc/locale.conf
sed -i 's/#fr_FR.UTF-8/fr_FR.UTF-8/' /etc/locale.gen
locale-gen
ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
hwclock --systohc

# Nom de l'hôte
echo "archlinux" > /etc/hostname
echo "127.0.1.1 archlinux" >> /etc/hosts

# Installation et configuration de GRUB
echo "Installation de GRUB..."
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
echo 'GRUB_CMDLINE_LINUX="cryptdevice=/dev/disk/by-uuid/$(blkid -s UUID -o value $ROOT_PART):cryptroot root=/dev/mapper/cryptroot"' >> /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg

# Activation des services
systemctl enable NetworkManager

# Création de l'utilisateur
useradd -m -G wheel -s /bin/bash user
echo "user:password" | chpasswd
sed -i 's/# %wheel ALL=(ALL) ALL/ %wheel ALL=(ALL) ALL/' /etc/sudoers
EOF

# Fin de l'installation
echo "Installation terminée ! Vous pouvez redémarrer."
dialog --msgbox "Installation terminée avec succès !\nVous pouvez redémarrer votre machine." 10 50

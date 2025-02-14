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

# Fonction pour l'affichage des erreurs
function check_error() {
  if [ $? -ne 0 ]; then
    echo "Erreur lors de l'exécution de la commande : $1"
    exit 1
  fi
}

# Partitionnement
echo "Partitionnement du disque..."
parted -s $DISK mklabel gpt
check_error "parted mklabel"
parted -s $DISK mkpart primary fat32 1MiB 513MiB
check_error "parted mkpart fat32"
parted -s $DISK set 1 esp on
check_error "parted set esp"
parted -s $DISK mkpart primary ext4 513MiB 20GiB
check_error "parted mkpart ext4"
parted -s $DISK mkpart primary 20GiB 30GiB
check_error "parted mkpart"
parted -s $DISK mkpart primary 30GiB 35GiB
check_error "parted mkpart"
parted -s $DISK mkpart primary 35GiB 100%
check_error "parted mkpart"

# Chiffrement LUKS
echo "Configuration de LUKS..."
cryptsetup luksFormat $LUKS_PART
check_error "cryptsetup luksFormat"
cryptsetup open $LUKS_PART $LUKS_MAPPER
check_error "cryptsetup open"

# LVM
echo "Configuration de LVM..."
pvcreate /dev/mapper/$LUKS_MAPPER
check_error "pvcreate"
vgcreate $VG_NAME /dev/mapper/$LUKS_MAPPER
check_error "vgcreate"
lvcreate -L 40G -n $LV_ROOT $VG_NAME
check_error "lvcreate root"
lvcreate -L 5G -n $LV_SHARED $VG_NAME
check_error "lvcreate shared"
lvcreate -L 10G -n $LV_VIRTUALBOX $VG_NAME
check_error "lvcreate virtualbox"
lvcreate -L 10G -n $LV_CRYPT $VG_NAME
check_error "lvcreate crypt"

# Formatage
echo "Formatage des partitions..."
mkfs.fat -F32 /dev/sda1
check_error "mkfs.fat"
mkfs.ext4 /dev/$VG_NAME/$LV_ROOT
check_error "mkfs.ext4 root"
mkfs.ext4 /dev/$VG_NAME/$LV_SHARED
check_error "mkfs.ext4 shared"
mkfs.ext4 /dev/$VG_NAME/$LV_VIRTUALBOX
check_error "mkfs.ext4 virtualbox"
mkfs.ext4 /dev/$VG_NAME/$LV_CRYPT
check_error "mkfs.ext4 crypt"

# Montage
echo "Montage des partitions..."
mount /dev/$VG_NAME/$LV_ROOT /mnt
check_error "mount root"
mkdir /mnt/boot
mkdir /mnt/boot/efi
mount /dev/sda1 /mnt/boot/efi
check_error "mount boot"
mkdir /mnt/shared
mount /dev/$VG_NAME/$LV_SHARED /mnt/shared
check_error "mount shared"
mkdir /mnt/virtualbox
mount /dev/$VG_NAME/$LV_VIRTUALBOX /mnt/virtualbox
check_error "mount virtualbox"

# Installation des paquets de base
echo "Installation des paquets de base..."
pacstrap /mnt base linux linux-firmware vim networkmanager grub efibootmgr lvm2
check_error "pacstrap"

# Génération de fstab
echo "Génération de fstab..."
genfstab -U /mnt >> /mnt/etc/fstab
check_error "genfstab"

# Configuration système
echo "Configuration du système..."
arch-chroot /mnt ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
check_error "ln -sf timezone"
arch-chroot /mnt hwclock --systohc
check_error "hwclock"
arch-chroot /mnt sed -i "s/#$LOCALE/$LOCALE/" /etc/locale.gen
check_error "sed locale"
arch-chroot /mnt locale-gen
check_error "locale-gen"
arch-chroot /mnt echo "LANG=$LOCALE" > /etc/locale.conf
check_error "echo LANG"
arch-chroot /mnt echo $HOSTNAME > /etc/hostname
check_error "echo hostname"
arch-chroot /mnt echo "127.0.0.1 localhost" >> /etc/hosts
check_error "echo localhost"
arch-chroot /mnt echo "::1       localhost" >> /etc/hosts
check_error "echo localhost ipv6"
arch-chroot /mnt echo "127.0.1.1 $HOSTNAME.localdomain $HOSTNAME" >> /etc/hosts
check_error "echo $HOSTNAME"

# Installation du bootloader
echo "Installation du bootloader..."
arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
check_error "grub-install"
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
check_error "grub-mkconfig"

# Utilisateurs
echo "Création des utilisateurs..."
arch-chroot /mnt useradd -m -G wheel -s /bin/bash $USER1
check_error "useradd collegue"
arch-chroot /mnt useradd -m -s /bin/bash $USER2
check_error "useradd fils"
arch-chroot /mnt echo "$USER1:$PASSWORD" | chpasswd
check_error "chpasswd collegue"
arch-chroot /mnt echo "$USER2:$PASSWORD" | chpasswd
check_error "chpasswd fils"

# Outils supplémentaires
echo "Installation des outils supplémentaires..."
arch-chroot /mnt pacman -S --noconfirm xorg-server xorg-xinit hyprland virtualbox firefox code
check_error "pacman -S tools"

# Configuration de Hyprland
echo "Configuration de Hyprland..."
mkdir -p /mnt/home/$USER1/.config/hypr
echo "exec Hyprland" > /mnt/home/$USER1/.config/hypr/hyprland.conf
check_error "config hyprland"

# Dossier partagé
echo "Configuration du dossier partagé..."
chown $USER1:$USER1 /mnt/shared
chmod 770 /mnt/shared
check_error "chown chmod shared"

# Finalisation
echo "Finalisation..."
umount -R /mnt
echo "Installation terminée ! Redémarrage dans 5 secondes..."
sleep 5
reboot

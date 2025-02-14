#!/bin/bash

set -e  # Arrêter le script en cas d'erreur

# Variables
DISK="/dev/sda"
CRYPT_NAME="cryptdisk"
VG_NAME="volgroup"
LV_ROOT="root"
LV_VBOX="vbox"
LV_SHARED="shared"
LV_ENCRYPTED="encrypted"
PASSWORD="azerty123"
HOSTNAME="coworker-pc"
USER1="coworker"
USER2="son"

echo "====> Configuration du disque et chiffrement avec LUKS..."
# Création des partitions
parted -s ${DISK} mklabel gpt
parted -s ${DISK} mkpart ESP fat32 1MiB 512MiB
parted -s ${DISK} set 1 esp on
parted -s ${DISK} mkpart primary 512MiB 100%

# Formater et configurer LUKS
mkfs.fat -F32 ${DISK}1
echo -n "${PASSWORD}" | cryptsetup luksFormat ${DISK}2 -
echo -n "${PASSWORD}" | cryptsetup open ${DISK}2 ${CRYPT_NAME} --key-file=-

# Configuration de LVM
pvcreate /dev/mapper/${CRYPT_NAME}
vgcreate ${VG_NAME} /dev/mapper/${CRYPT_NAME}
lvcreate -L 10G -n ${LV_ENCRYPTED} ${VG_NAME}
lvcreate -L 20G -n ${LV_VBOX} ${VG_NAME}
lvcreate -L 5G -n ${LV_SHARED} ${VG_NAME}
lvcreate -l 100%FREE -n ${LV_ROOT} ${VG_NAME}

# Formater les volumes logiques
mkfs.ext4 /dev/${VG_NAME}/${LV_ROOT}
mkfs.ext4 /dev/${VG_NAME}/${LV_VBOX}
mkfs.ext4 /dev/${VG_NAME}/${LV_SHARED}
mkfs.ext4 /dev/${VG_NAME}/${LV_ENCRYPTED}

# Montage des partitions
mount /dev/${VG_NAME}/${LV_ROOT} /mnt
mkdir -p /mnt/boot/efi /mnt/vbox /mnt/shared
mount ${DISK}1 /mnt/boot/efi
mount /dev/${VG_NAME}/${LV_VBOX} /mnt/vbox
mount /dev/${VG_NAME}/${LV_SHARED} /mnt/shared

echo "====> Installation des paquets de base..."
pacstrap /mnt base base-devel linux linux-firmware vim grub efibootmgr lvm2

echo "====> Configuration du système..."
genfstab -U /mnt >> /mnt/etc/fstab

arch-chroot /mnt /bin/bash <<EOF
# Configuration de base
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
hwclock --systohc
echo "${HOSTNAME}" > /etc/hostname

# Configuration de GRUB
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf block keymap encrypt lvm2 filesystems keyboard fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=arch
grub-mkconfig -o /boot/grub/grub.cfg

# Création des utilisateurs
useradd -m -G wheel ${USER1}
echo "${USER1}:${PASSWORD}" | chpasswd
useradd -m ${USER2}
echo "${USER2}:${PASSWORD}" | chpasswd
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

# Installation des logiciels
pacman -S --noconfirm hyprland gdm virtualbox virtualbox-host-modules-arch firefox xterm neofetch

# Activation des services
systemctl enable gdm.service
EOF

echo "====> Fin de l'installation, redémarrage..."
umount -R /mnt
reboot

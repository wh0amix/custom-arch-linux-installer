est-ce que ce script : #!/bin/bash

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

# Demande du disque cible
DISK=$(lsblk -dpn -o NAME,SIZE | grep -E "/dev/sd|nvme|mmcblk" | dialog --stdout --menu "Sélectionnez le disque cible" 15 50 10 $(awk '{print $1, "(" $2 ")"}' ))
if [[ -z "$DISK" ]]; then
    echo "Aucun disque sélectionné, arrêt du script."
    exit 1
fi

# Partitionnement du disque
sgdisk -Z "$DISK"
sgdisk -n 1:0:+512M -t 1:EF00 "$DISK"
sgdisk -n 2:0:0 -t 2:8E00 "$DISK"

# Formatage de la partition EFI
mkfs.fat -F32 "${DISK}1"

# Chiffrement du disque
echo -n "$LUKS_PASSWORD" | cryptsetup luksFormat --type luks2 "${DISK}2" -
echo -n "$LUKS_PASSWORD" | cryptsetup open "${DISK}2" cryptroot

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
mount "${DISK}1" /mnt/boot

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
echo 'GRUB_CMDLINE_LINUX="cryptdevice=/dev/disk/by-uuid/$(blkid -s UUID -o value ${DISK}2):cryptroot root=/dev/mapper/vg0-root"' >> /etc/default/grub
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

réponds à ca ? :Contexte
Un collègue à vous cherche à utiliser Arch Linux. Cependant, il ne veut pas faire l'installation car il n'y connait
rien. Il se tourne donc vers vous afin de l'installer pour lui. Problème : il rentre de vacances dans deux
semaines et son ordinateur est avec lui.
Vous vous savez pas disponible lors de son retour car vous êtes en vacances l'après-midi même de son
retour !
Par chance, vous lui avez demandé les spécificités de son ordinateur, ainsi que son futur usage...
Objectif
Réaliser un script d'installation qui vous permettra de discuter avec lui autour d'un café à son retour.
Votre collègue vous à dit les choses suivantes:
1. "Je serai le seul, avec mon fils, à utiliser la machine"
2. "Mon fils s'en servira uniquement pour suivre des tutos de code en C. Apparemment, son professeur
n'accepte pas qu'il utilise un IDE standard, t'y crois à ça ?!?"
3. "Le disque dur est vieux et pas bien grand, il fait, à tout casser, 80G"
4. "Niveau RAM, on est à l'aise avec un solide 8G"
5. "Il est certain que je fasse de la virtualisation avec un hyperviseur style VirtualBox, pour des tests"
6. "Il me faut impérativement un espace chiffré que je dois monter à la main, sait-on jamais ! [...] Un bon
10G minimum ferait pas de mal, je pense."
7. "Il y a un monde où j'aimerai tester Hyprland, ça a l'air chouette sur les forums de ricing ! Si tu pouvais
m'ajouter une configuration customisée ça sera génial !"
8. "Si tu as la capacité de m'ajouter un dossier partagé avec mon fils, ça serai top moumoute ! Pas
énorme hein, genre 5G, histoire de se partager des memes ! C'est notre truc à nous ça."
9. "Profites-en pour m'installer des outils que tu juges nécessaires, du simple navigateur internet aux
outils de gestion de l'ordi, n'hésites pas à m'en mettre ! Ça me permettra de mettre les mains dans le
cambouis, et avec tes recommandations, ça sera plus simple de te demander de l'aide !"
10. "Si tu as besoin de mots de passe, pour les comptes ou les trucs chiffrés, t'embêtes pas met
"azerty123", je modifierait ça plus tard."
11. "Mon ordinateur ? Il a l'UEFI d'activé évidemment !"
12. "Je garde rien sur le disque, c'est un single boot Arch qui m'intéresse !"
1/29/2025 partiel.md
/
Consignes
Vous l'avez compris, le but du partiel est d'automatiser une installation Arch avec les configurations
demandées. Ça signifie qu'il vous faut rédiger un script.
Voici les spécificités liés à la machine virtuelle à proprement parler :
80G de stockage
8G de RAM
4/8 de cpus
UEFI
N'oubliez pas le combo LUKS + LVM qu'on a vu ensemble Appliquez le pour le disque. Les particularités
de partitionnement sont donc les suivantes :
Le disque est chiffré avec LVM
Un volume logique dédié de 10Go doit être créé et configuré avec LUKS dessus, ainsi qu'un système
de fichier en plus sans point de montage puisque monté par l'utilisateur à la main
VirtualBox nécessite un espace de stockade dédié ⇒ volume logique (à vous de déterminer le point de
montage)
Pour le dossier partagé avec le fils ⇒ volume logique (à vous de déterminer le point de montage)
 
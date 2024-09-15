#!/bin/bash

# Проверяем, что скрипт запущен под root
if [ "$(id -u)" -ne "0" ]; then
  echo "Запустите скрипт с повышенными привилегиями..." 1>&2
  exit 1
fi

ping -c 2 www.archlinux.org

timedatectl set-ntp true
timedatectl set-timezone Europe/Moscow

# Размечаем диск =) Добавить возможность смены раздела на любой (или дать выбор)
echo "Произвожу разметку диска"
fdisk /dev/sda <<EOF
g
n
1

+512M
Y
n
2

+1G
Y
n
3


Y
t
1
1
t
2
19
t
2
20
w
EOF

# Форматирование разделов
echo "Подготовка размеченного пространства"
mkfs.fat -F32 /dev/sda1
mkswap /dev/sda2
swapon -v /dev/sda2
mkfs.ext4 /dev/sda3

# Монтирование ФС
echo "Монтирую разделы.."
mount /dev/sda3 /mnt
mkdir /mnt/boot
mount /dev/sda1 /mnt/boot

# Устанавливаю системные файлы
echo "Устанавливаю системные файлы.."
pacstrap /mnt base linux linux-firmware vim

echo "Генерация файловой системы"
genfstab -U /mnt >> /mnt/etc/fstab

# chroot
echo "Переходим в chroot"
arch-chroot /mnt /bin/base <<EOF

  #Установка часового пояса
  ln -sf /usr/share/zoneinfo/Region/City /etc/localtime
  hwclock --systohc
  echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
  echo "ru_RU.UTF-8 UTF-8" >> /etc/locale.gen
  locale-gen
  echo "LANG=en_US.UTF-8" > /etc/locale.conf
  # Установка hostname и настройка сети
  echo "archbox" > /etc/hostname
  echo "127.0.0.1	localhost
  ::1	localhost
  127.0.1.1	archbox.localdomain archbox" > /etc/hosts
  
  useradd -m  taminglinux
  passwd taminglinux
  
  usermod -aG wheel,audio,video,optical,storage taminglinux
  
  pacman -S --noconfirm grub efibootmgr dosfstools os-prober mtools dhcpcd
  # pacman -S --noconfirm iwd
  
  EDITOR=vim
  visudo
  
  grub-install --target=x86_64-efi --bootloader-id=Arch_UEFI --recheck
  grub-mkconfig -o /boot/grub/grub.cfg
  
EOF

echo "Установка завершена. Перезагрузите систему."

exit 0

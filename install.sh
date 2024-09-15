#!/bin/bash

# Проверяем, что скрипт запущен под root
if [ "$(id -u)" -ne "0" ]; then
  echo "Запустите скрипт с повышенными привилегиями..." 1>&2
  exit 1
fi

# Проверяем подключение к сети интернет
ping -c 1 www.archlinux.org
ping -c 1 www.google.com

# Настройка времени
echo "Настраиваем системное время..."
timedatectl set-ntp true
timedatectl set-timezone Europe/Moscow

# Выбор диска для установки системы
echo "Список доступных дисков:"
lsblk
read -p "Укажите диск для разметки (например, /dev/sda): " DISK

fdisk "$DISK" <<EOF
g
n
1



Y


w
EOF
# Erase Disk!!
dd if=/dev/random of="$DISK" bs=512 bc=100

# Разметка диска
echo "Произвожу разметку диска $DISK"
fdisk "$DISK" <<EOF
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
echo "Форматирую разделы..."
mkfs.fat -F32 "${DISK}1"
mkswap "${DISK}2"
swapon -v "${DISK}2"
mkfs.ext4 "${DISK}3"

# Монтирование ФС
echo "Монтирую разделы.."
mount "${DISK}3" /mnt
mkdir /mnt/boot
mount "${DISK}1" /mnt/boot

# Устанавливаю системные файлы
echo "Устанавливаю системные файлы.."
pacstrap /mnt base linux linux-firmware vim

echo "Генерация файловой системы"
genfstab -U /mnt >> /mnt/etc/fstab

# chroot
echo "Переходим в chroot"
arch-chroot /mnt /bin/bash <<EOF

  #Установка часового пояса
  sudo ln -sf /usr/share/zoneinfo/Region/City /etc/localtime
  sudo hwclock --systohc
  sudo echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
  sudo echo "ru_RU.UTF-8 UTF-8" >> /etc/locale.gen
  sudo locale-gen
  sudo echo "LANG=en_US.UTF-8" > /etc/locale.conf
  # Установка hostname и настройка сети
  sudo echo "archbox" > /etc/hostname
  sudo echo "127.0.0.1	localhost
  ::1	localhost
  127.0.1.1	archbox.localdomain archbox" > /etc/hosts
  
  sudo useradd -m  taminglinux
  sudo echo "Установите пароль для пользователя по умолчанию:"
  sudo passwd taminglinux
  
  sudo usermod -aG wheel,audio,video,optical,storage taminglinux
  
  sudo pacman -S --noconfirm sudo
  sudo echo "taminglinux ALL=(ALL) ALL" >> /etc/sudoers
  
  sudo pacman -S --noconfirm grub efibootmgr dosfstools os-prober mtools dhcpcd
   
  sudo echo "Перед повторным маунтом EFI, я выведу тебе стату по дискам"
  sudo  df -h
   
  sudo mkdir /boot/EFI
  sudo mount "${DISK}1" /boot/EFI

  sudo grub-install --target=x86_64-efi --bootloader-id=Arch_UEFI --recheck
  sudo grub-mkconfig -o /boot/grub/grub.cfg
  
  # Включаем сеть
  sudo systemctl enable dhcpcd
EOF

echo "Установка завершена. Перезагрузите систему."

exit 0

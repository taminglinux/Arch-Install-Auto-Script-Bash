#!/bin/bash

# Проверяем, что скрипт запущен под root
if [ "$(id -u)" -ne "0" ]; then
  echo "Запустите скрипт с повышенными привилегиями..." 1>&2
  exit 1
fi

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
n
3


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
pacstrap /mnt base linux linux-virmware vim

echo "Генерация файловой системы"
genfstab -U /mnt >> /mnt/etc/fstab

# chroot
echo "Переходим в chroot"
arch-chroot /mnt /bin/base <<EOF

  #Установка часового пояса
  ln -sf /usr/share/zoneinfo/Region/City /etc/localtime
  locale-gen
  echo "LANG=en_US.UTF-8" > /etc/locale.conf
  # Установка hostname и настройка сети
  echo "archbox" > /etc/hostname
  pacman -S --noconfirm grub
  grub-install --target=x86_64 /dev/sda
  grub-mkconfig -o /boot/grub/grub.cfg
EOF

echo "Установка завершена. Перезагрузите систему."

exit 0

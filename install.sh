#!/bin/bash

# 1Проверить, что скрипт запущен от рута
if [ "$(id -u)" -ne "0" ]; then
  echo "Скрипт нужно запустить от имени root" 1>&2
  exit 1
fi

# 2Установка базовых компонентов

echo "Устанавливаю базовые компоненты.."
pacman -Syu --noconfirm
pacman -S --noconfirm base base-devel linux linux-firmware vim

# Размечаем диск =) Добавить возможность смены раздела на любой (или дать выбор)
echo "Произвожу разметку диска"
fdisk /dev/sda <<EOF
o
n
p
1


+512M
t
ef
n
p
2


t
20
w
EOF

# Форматирование разделов
echo "Подготовка размеченного пространства"
mkfs.fat -F32 /dev/sda1
mkfs.ext4 /dev/sda2

# Монтирование ФС
echo "Монтирую разделы.."
mount /dev/sda2 /mnt
mkdir /mnt/boot
mount /dev/sda1 /mnt/boot

# Устанавливаю системные файлы
echo "Устанавливаю системные файлы.."
pacstrap /mnt base linux linux-virmware vim

echo "Генерация файловой системы"
genfstab -U /mnt >> /mnt/etc/fstab

# chroot


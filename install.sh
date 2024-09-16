#!/bin/bash

# Проверяем, что скрипт запущен под root
if [ "$(id -u)" -ne "0" ]; then
  echo "Запустите скрипт с правами root..." 1>&2
  exit 1
fi

# Настройка времени
echo "Настраиваем системное время..."
timedatectl set-ntp true
timedatectl set-timezone Europe/Moscow
echo "Настройка времени завершена..."

# Выбор диска для установки системы
echo "Список доступных дисков:"
lsblk
read -p "Укажите диск для разметки (например, /dev/sda): " DISK

# Очистка таблицы разделов
parted "$DISK" mklabel gpt
# Создание EFI раздела (512М, EFI)
parted "$DISK" mkpart primary fat32 1MiB 513MiB
parted "$DISK" set 1 boot on
# Создание SWAP-раздела (1G, SWAP)
parted "$DISK" mkpart primary linux-swap 513MiB 1537MiB
# Создание корневого раздела
parted "$DISK" mkpart primary ext4 1537MiB 100%

echo "Разметка устройства $DISK завершена..."

# Форматирование разделов
echo "Начинаю форматировать разделы..."
mkfs.fat -F32 "${DISK}1"
echo "Загрузочный раздел отформатирован..."
mkswap "${DISK}2"
swapon -v "${DISK}2"
echo "Swap-пространство активировано..."
mkfs.ext4 "${DISK}3"
echo "Корневой раздел отформатирован..."

# Монтирование ФС
echo "Монтирую корневой раздел.."
mount "${DISK}3" /mnt

# Устанавливаю системные файлы
echo "Устанавливаю системные файлы..."
pacstrap -K /mnt base linux linux-firmware vim
echo "Системные файлы установлены..."
echo "Записываю информацию о смонтированных устройствах..."
genfstab -U /mnt >> /mnt/etc/fstab

# Всё что выше - протестировано и должно работать. Далее отладка работы в chroot.

HOSTNAME=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 8)
read -p "Введите имя нового пользователя: " USERNAME

# chroot
echo "Переходим в chroot"
arch-chroot /mnt /bin/bash <<EOF

  echo "Настройка часового пояса..."
  ln -sf /usr/share/zoneinfo/Region/City /etc/localtime
  hwclock --systohc
  echo "Выполняем языковые настройки..."
  echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
  echo "ru_RU.UTF-8 UTF-8" >> /etc/locale.gen
  locale-gen
  echo "LANG=en_US.UTF-8" > /etc/locale.conf && export LANG=en_US.UTF-8
  echo "Настраиваем сеть..."
  echo "$HOSTNAME" > /etc/hostname

echo "127.0.0.1    localhost
::1    localhost
127.0.1.1    $HOSTNAME.localdomain $HOSTNAME" > /etc/hosts
  
  echo "Создание пользователя..."
  useradd -m  $USERNAME
  echo "Установите пароль пользователя $USERNAME"
  passwd $USERNAME
  usermod -aG wheel,audio,video,optical,storage $USERNAME
  
  pacman -S --noconfirm sudo
  echo "$USERNAME ALL=(ALL) ALL" >> /etc/sudoers
  
  pacman -S --noconfirm grub efibootmgr dosfstools os-prober mtools dhcpcd
  
  echo "Подготовка к установке загрузчика..."
  mkdir /boot/efi
  mount "${DISK}1" /boot/efi
  echo "Установка загрузчика..."
  grub-install --target=x86_64-efi --bootloader-id=Arch_UEFI --recheck
  grub-mkconfig -o /boot/grub/grub.cfg
  
  echo "Включаем сеть и устанавливаем графику..."
  systemctl enable dhcpcd
  pacman -S --noconfirm xorg-server xorg-apps
  
EOF

echo "Установка завершена. Перезагрузите систему."

exit 0

#!/bin/bash

# Проверяем, что скрипт запущен под root
if [ "$(id -u)" -ne "0" ]; then
  echo "Запустите скрипт с повышенными привилегиями..." 1>&2
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

echo "Выполняю удаление данных с диска..."
fdisk "$DISK" <<EOF
g
n
1



Y


w
EOF
echo "Информация с устройства $DISK удалена"
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

# Всё что выше - протестировано и должно работать. Далее отладка работы в chtoot.

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
  echo archbox > /etc/hostname
  cat <<EOF >> /etc/hosts
  127.0.0.1	localhost
  ::1	localhost
  127.0.1.1	archbox.localdomain archbox
  EOF
  
  echo "Создание пользователя..."
  useradd -m  taminglinux
  usermod -aG wheel,audio,video,optical,storage taminglinux
  
  pacman -S --noconfirm sudo
  echo "taminglinux ALL=(ALL) ALL" >> /etc/sudoers
  
  pacman -S --noconfirm grub efibootmgr dosfstools os-prober mtools dhcpcd
  
  echo "Подготовка к установке загрузчика..."
  mkdir /boot/efi
  mount "${DISK}1" /boot/efi
  echo "Установка загрузчика..."
  grub-install --target=x86_64-efi --bootloader-id=Arch_UEFI --recheck
  grub-mkconfig -o /boot/grub/grub.cfg
  
  echo "Включаем сеть и устанавливаем графику..."
  systemctl enable dhcpcd
  pacman -S xorg-server xorg-apps
  
EOF

echo "Установка завершена. Перезагрузите систему."

exit 0

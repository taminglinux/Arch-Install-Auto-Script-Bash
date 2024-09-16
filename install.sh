#!/bin/bash

# Проверяем, что скрипт запущен под root
if [ "$(id -u)" -ne "0" ]; then
  dialog --msgbox "Запустите скрипт с повышенными привилегиями..." 10 40
  exit 1
fi

pacman -Sy >/dev/null 2>&1
pacman -S --noconfirm dialog >/dev/null 2>&1

dialog --title "Установщик Arch Linux" --yesno "Этот скрипт упрощает установку Arch Linux.\n\nВы уверены, что хотите начать установку?" 10 60
response=$?
if [ $response -eq 1 ]; then
	dialog --msgbox "Установка была отменена." 5 40
	exit 1
fi

# Настройка времени
dialog --infobox "Настраиваем системное время..." 3 40
timedatectl set-ntp true
timedatectl set-timezone Europe/Moscow
sleep 2
dialog --pause "Настройка времени завершена..." 5 40 2

# Выбор диска для установки системы
DISKS=$(lsblk -d -p -n -o NAME,SIZE | grep -E "^/dev/[a-z]+")
DISK=$(dialog --menu "Укажите диск для разметки:" 15 60 5 $(echo "$DISKS" | awk '{print $1 " " $2}') 3>&1 1>&2 2>&3)

# Очистка таблицы разделов
dialog --yesno "Удалить все данные с $DISK?" 10 40
response=$?
if [ $response -eq 0 ]; then
	dialog --infobox "Выполняю удаление данных с диска $DISK..." 3 40
	parted --script "$DISK" mklabel gpt
else
	dialog --msgbox "Операция отменена..." 5 40
	exit 1
fi

# Разметка диска
dialog --infobox "Создаю разделы на $DISK..." 3 40
parted --script "$DISK" mkpart primary fat32 1MiB 513MiB
parted --script "$DISK" set 1 boot on
parted --script "$DISK" mkpart primary linux-swap 513MiB 1537MiB
parted --script "$DISK" mkpart primary ext4 1537MiB 100%
sleep 2
dialog --pause "Разметка устройства $DISK завершена..." 5 40 5

# Форматирование разделов
dialog --infobox "Форматирую разделы..." 3 40
mkfs.fat -F32 "${DISK}1"
mkswap "${DISK}2"
swapon "${DISK}2"
mkfs.ext4 "${DISK}3"
sleep 2
dialog --pause "Форматирование разделов завершено." 5 40 2

dialog --pause "Монтирую корневой раздел..." 5 40 2
mount "${DISK}3" /mnt

# Устанавливаю системные файлы
dialog --msgbox "Устанавливаю системные файлы..." 5 40
pacstrap -K /mnt base linux linux-firmware vim
genfstab -U /mnt >> /mnt/etc/fstab

HOSTNAME=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 8)
USERNAME=$(dialog --inputbox "Введите имя нового пользователя:" 10 60 3>&1 1>&2 2>&3 3>&-)

DESKTOP_ENV=$(dialog --menu "Выберите окружение рабочего стола:" 15 50 4 \
1 "LXDE" \
2 "LXQt" \
3 "GNOME" \
4 "KDE" 3>&1 1>&2 2>&3)

case $DESKTOP_ENV in
	1) DESKTOP="lxde" ;;
	2) DESKTOP="lxqt" ;;
	3) DESKTOP="gnome" ;;
	4) DESKTOP="plasma" ;;
	*) dialog --msgbox "Выбрано некорректное значение, установка отменена." 5 40 ; exit 1 ;;
esac

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
pacman -S --noconfirm $DESKTOP xorg-server xorg-apps
  
EOF

dialog --msgbox "Установка завершена. Перезагрузите систему." 5 40

exit

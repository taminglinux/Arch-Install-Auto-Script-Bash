#!/bin/bash

# Проверяем, что скрипт запущен под root
if [ "$(id -u)" -ne "0" ]; then
  dialog --msgbox "Запустите скрипт с повышенными привилегиями..." 10 40
  exit 1
fi

# Устанавливаем пакет dialog для отображения псевдографики
pacman -Sy &>/dev/null
pacman -S --noconfirm dialog &>/dev/null

# Подтверждение начала установки
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

# Выбор диска для установки системы
DISKS=$(lsblk -d -p -n -o NAME,SIZE | grep -E "^/dev/[a-z]+")
DISK=$(dialog --menu "Укажите диск для разметки:" 15 60 5 $(echo "$DISKS" | awk '{print $1 " " $2}') 3>&1 1>&2 2>&3)

# Очистка таблицы разделов
dialog --yesno "Удалить все данные с $DISK? Данные с диска будут удалены!" 10 60
response=$?
if [ $response -eq 0 ]; then
	dialog --infobox "Выполняю удаление данных с диска $DISK..." 3 40
	wipefs --all "$DISK"
	parted --script "$DISK" mklabel gpt &>/dev/null
else
	dialog --msgbox "Операция отменена..." 5 40
	exit 1
fi

# Разметка диска
dialog --infobox "Создаю разделы на $DISK..." 3 40
parted --script "$DISK" mkpart primary fat32 1MiB 513MiB &>/dev/null
parted --script "$DISK" set 1 boot on &>/dev/null
parted --script "$DISK" mkpart primary linux-swap 513MiB 1537MiB &>/dev/null
parted --script "$DISK" mkpart primary ext4 1537MiB 100% &>/dev/null
sleep 2
dialog --infobox "Разметка устройства $DISK завершена..." 3 40
sleep 2

# Форматирование разделов
dialog --infobox "Форматирую разделы..." 3 40
mkfs.fat -F32 "${DISK}1" &>/dev/null
mkswap "${DISK}2" &>/dev/null
swapon "${DISK}2" &>/dev/null
mkfs.ext4 "${DISK}3" &>/dev/null
sleep 5
dialog --infobox "Форматирование разделов завершено." 3 40
sleep 2

dialog --infobox "Монтирую корневой раздел..." 3 40
mount "${DISK}3" /mnt
sleep 5

# Устанавливаю системные файлы
dialog --infobox "Устанавливаю системные файлы..." 3 40
pacstrap -K /mnt base linux linux-firmware vim
genfstab -U /mnt >> /mnt/etc/fstab

HOSTNAME=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 8)
USERNAME=$(dialog --inputbox "Введите имя нового пользователя:" 10 60 3>&1 1>&2 2>&3 3>&-)
USER_PASS=$(dialog --insecure --passwordbox "Введите пароль для нового пользователя:" 10 60 3>&1 1>&2 2>&3)

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

dialog --infobox "Переходим в chroot" 3 40
arch-chroot /mnt /bin/bash <<EOF
echo "Настройка часового пояса..."
ln -sf /usr/share/zoneinfo/Region/City /etc/localtime
hwclock --systohc
echo "Выполняем языковые настройки..."
locale_file="/etc/locale.gen"
grep -Fxq "en_US.UTF-8 UTF-8" "$locale_file" || echo "en_US.UTF-8 UTF-8" >> "$locale_file"
grep -Fxq "ru_RU.UTF-8 UTF-8" "$locale_file" || echo "ru_RU.UTF-8 UTF-8" >> "$locale_file"
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "Настраиваем сеть..."
echo "$HOSTNAME" > /etc/hostname
echo "127.0.0.1    localhost
::1    localhost
127.0.1.1    $HOSTNAME.localdomain $HOSTNAME" > /etc/hosts
echo "Создание пользователя..."
useradd -m  $USERNAME
echo "$USERNAME:$USER_PASS" | chpasswd
usermod -aG wheel,audio,video,optical,storage $USERNAME
pacman -S --noconfirm sudo grub efibootmgr dosfstools os-prober mtools dhcpcd &>/dev/null
echo "$USERNAME ALL=(ALL) ALL" >> /etc/sudoers
echo "Установка загрузчика..."
mkdir /boot/efi
mount "${DISK}1" /boot/efi
grub-install --target=x86_64-efi --bootloader-id=Arch_UEFI --recheck
grub-mkconfig -o /boot/grub/grub.cfg
echo "Включаем сеть и устанавливаем графику..."
systemctl enable dhcpcd
pacman -S --noconfirm $DESKTOP xorg-server xorg-apps
EOF

dialog --msgbox "Установка завершена. Перезагрузите систему." 5 40

exit

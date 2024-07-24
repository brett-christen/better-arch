#!/bin/bash

echo "Select the disk:"
select disk in /dev/nvme*; do 
    if [ -n "$disk" ]; then
        break
    else
        echo "Invalid selection."
    fi
done

echo "You selected disk: $disk"


set dialog $(which dialog)
if [ -n "$dialog" ]; then
    break
else
    tempfile=$(mktemp)
    while true; do
        dialog --menu 'Please select a disk' 18 70 15 $(lsblk -dno NAME | grep '^sd') 2>"$tempfile" && break
    fi
done

disk="/dev/$(cat "$tempfile")"
rm "$tempfile"

echo "You selected disk: $disk"

cryptsetup open --type plain $disk container --key-file /dev/urandom
dd if=/dev/zero of=/dev/mapper/container status=progress bs=1M
cryptsetup close container

sgdisk --zap-all $disk
sgdisk --clear --new=1:0:+512MiB --typecode=1:ef00 --change-name=1:EFI --new=2:0:+32GiB --typecode=2:8200 --change-name=2:crypt_swap --new=3:0:0 --typecode=3:8300 --change-name=3:crypt_root $disk

cryptsetup luksFormat --type luks2 --align-payload=8192 -s 256 -c aes-xts-plain64 /dev/disk/by-partlabel/crypt_root
cryptsetup open --type plain --key-file /dev/urandom /dev/disk/by-partlabel/crypt_swap crypt_swap
cryptsetup open /dev/disk/by-partlabel/crypt_root crypt_root

mkswap -L crypt_swap /dev/mapper/crypt_swap
swapon -L crypt_swap

mkfs.fat -F 32 -n EFI /dev/disk/by-partlabel/EFI
mkfs.btrfs --label root /dev/mapper/crypt_root
mount -t btrfs LABEL=root /mnt
btrfs subvolume create /mnt/@root
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@var
btrfs subvolume create /mnt/@log
btrfs subvolume create /mnt/@pkg
btrfs subvolume create /mnt/@tmp
btrfs subvolume create /mnt/@snapshots

umount -R /mnt

mount -t btrfs -o defaults,x-mount.mkdir,space_cache=v2,compress=zstd,ssd,noatime,subvol=@root LABEL=rootfs /mnt
mount -t btrfs -o defaults,x-mount.mkdir,space_cache=v2,compress=zstd,ssd,nodev,nosuid,noatime,subvol=@home LABEL=home /mnt/home
mount -t btrfs -o defaults,x-mount.mkdir,space_cache=v2,compress=zstd,ssd,nodev,noatime,subvol=@var LABEL=var /mnt/var
mount -t btrfs -o defaults,x-mount.mkdir,space_cache=v2,compress=zstd,ssd,nodev,noatime,subvol=@log LABEL=log /mnt/var/log
mount -t btrfs -o defaults,x-mount.mkdir,space_cache=v2,compress=zstd,ssd,nodev,noatime,subvol=@pkg LABEL=pkg /mnt/var/cache/pacman/pkg
mount -t btrfs -o defaults,x-mount.mkdir,space_cache=v2,compress=zstd,ssd,nodev,nosuid,noatime,subvol=@tmp LABEL=tmp /mnt/tmp
mount -t btrfs -o defaults,x-mount.mkdir,space_cache=v2,compress=zstd,ssd,noatime,subvol=@snapshots LABEL=snapshots /mnt/.snapshots
#mount -t vfat  -o defaults,ssd,noatime,uid=0,gid=0,umask=0077,x-mount.mkdir /mnt/efi
# defaults,noatime,uid=0,gid=0,umask=0077,x-systemd.automount,x-systemd.idle-timeout=600 0 2
pacstrap /mnt base-selinux linux-zen linux-firmware
genfstab -L -p /mnt >> /mnt/etc/fstab
sed -i 's/LABEL=swap/\/dev\/mapper\/crypt_swap/g' /mnt/etc/fstab
echo 'swap /dev/disk/by-partlabel/crypt_swap /dev/urandom swap,offset=2048,cipher=aes-xts-plain64,size=256'



arch-chroot /mnt




#modprobe zram
#zramctl /dev/zram0 --algorithm zstd --size "$(($(grep MemTotal /proc/meminfo | tr -dc '0-9')/2))KiB"
#mkswap -U clear /dev/zram0
#swapon --priority 100 /dev/zram0
#sudo tee /etc/udev/rules.d/99-zram.rules <<'EOF'
#KERNEL=="zram0", ATTR{disksize}="512M", TAG+="systemd"
#EOF


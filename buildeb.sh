#!/bin/bash

# Install necessary applications
sudo apt-get update >/dev/null
sudo apt-get install -y \
    procps \
    sudo \
    apt-utils \
    debootstrap \
    squashfs-tools \
    xorriso \
    isolinux \
    syslinux-efi \
    grub-pc-bin \
    grub-efi-amd64-bin \
    grub-efi-ia32-bin \
    mtools \
    dosfstools >/dev/null &
spinner "Installing necessary dependencies"

# Function for spinning indicator
spinner()
{
    local pid=$!
    local delay=0.2
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf "\r [%c]  %s" "$spinstr" "$1"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
    done
    printf "\r [\xE2\x9C\x94]  %s\n" "$1"
}

# Create directory for storing files
mkdir -p "${HOME}/LIVE_BOOT" &
spinner "Creating working directory"

# Bootstrap and Configure Debian
sudo debootstrap \
    --arch=amd64 \
    --variant=minbase \
    stable \
    "${HOME}/LIVE_BOOT/chroot" \
    http://ftp.us.debian.org/debian/ >/dev/null &
spinner "Bootstraping and configuring Debian"

# Installing Linux kernel, live-boot, and systemd-sysv
{
    sudo chroot "${HOME}/LIVE_BOOT/chroot" << EOF >/dev/null 2>&1
apt-get update
apt-get install -y --no-install-recommends \
    linux-image-amd64 \
    live-boot \
    systemd-sysv
EOF
} &
spinner "Installing Linux kernel, live-boot, and systemd-sysv"

# Installing custom programs to image
{
    sudo chroot "${HOME}/LIVE_BOOT/chroot" << EOF >/dev/null 2>&1
apt-get update
apt-get install -y --no-install-recommends \
    wifite \
    vim
EOF
} &
spinner "Installing custom programs to image"

# Create directories
mkdir -p "${HOME}/LIVE_BOOT"/{staging/{EFI/BOOT,boot/grub/x86_64-efi,isolinux,live},tmp} &
spinner "Creating staging directories"

# Compress chroot environment into Squash filesystem
sudo mksquashfs \
    "${HOME}/LIVE_BOOT/chroot" \
    "${HOME}/LIVE_BOOT/staging/live/filesystem.squashfs" \
    -e boot >/dev/null &
spinner "Compressing chroot environment into Squash filesystem"

# Copy kernel and initramfs
{
    cp "${HOME}/LIVE_BOOT/chroot/boot"/vmlinuz-* \
        "${HOME}/LIVE_BOOT/staging/live/vmlinuz" && \
    cp "${HOME}/LIVE_BOOT/chroot/boot"/initrd.img-* \
        "${HOME}/LIVE_BOOT/staging/live/initrd"
} &
spinner "Copying kernel and initramfs"

# Prepare Boot Loader Menus
{
    cat <<'EOF' > "${HOME}/LIVE_BOOT/staging/isolinux/isolinux.cfg"
# ISOLINUX boot menu configuration file

UI vesamenu.c32

MENU TITLE Boot Menu
DEFAULT linux
TIMEOUT 600
MENU RESOLUTION 640 480
MENU COLOR border       30;44   #40ffffff #a0000000 std
MENU COLOR title        1;36;44 #9033ccff #a0000000 std
MENU COLOR sel          7;37;40 #e0ffffff #20ffffff all
MENU COLOR unsel        37;44   #50ffffff #a0000000 std
MENU COLOR help         37;40   #c0ffffff #a0000000 std
MENU COLOR timeout_msg  37;40   #80ffffff #00000000 std
MENU COLOR timeout      1;37;40 #c0ffffff #00000000 std
MENU COLOR msg07        37;40   #90ffffff #a0000000 std
MENU COLOR tabmsg       31;40   #30ffffff #00000000 std

LABEL linux
  MENU LABEL Debian Live [BIOS/ISOLINUX]
  MENU DEFAULT
  KERNEL /live/vmlinuz
  APPEND initrd=/live/initrd boot=live

LABEL linux
  MENU LABEL Debian Live [BIOS/ISOLINUX] (nomodeset)
  MENU DEFAULT
  KERNEL /live/vmlinuz
  APPEND initrd=/live/initrd boot=live nomodeset
EOF
} &
spinner "Preparing Boot Loader Menus"

# Prepare GRUB Boot Loader Configuration
{
    cat <<'EOF' > "${HOME}/LIVE_BOOT/staging/boot/grub/grub.cfg"
# GRUB boot menu configuration file

insmod part_gpt
insmod part_msdos
insmod fat
insmod iso9660

insmod all_video
insmod font

set default="0"
set timeout=30

menuentry "Debian Live [EFI/GRUB]" {
    search --no-floppy --set=root --label DEBLIVE
    linux ($root)/live/vmlinuz boot=live
    initrd ($root)/live/initrd
}

menuentry "Debian Live [EFI/GRUB] (nomodeset)" {
    search --no-floppy --set=root --label DEBLIVE
    linux ($root)/live/vmlinuz boot=live nomodeset
    initrd ($root)/live/initrd
}
EOF
} &
spinner "Preparing GRUB Boot Loader Configuration"

# Copy grub.cfg file to EFI BOOT directory
cp "${HOME}/LIVE_BOOT/staging/boot/grub/grub.cfg" "${HOME}/LIVE_BOOT/staging/EFI/BOOT/" &
spinner "Copying grub.cfg file to EFI BOOT directory"

# Create early configuration file embedded inside GRUB in EFI partition
{
    cat <<'EOF' > "${HOME}/LIVE_BOOT/tmp/grub-embed.cfg"
if ! [ -d "$cmdpath" ]; then
    if regexp --set=1:isodevice '^(\([^)]+\))\/?[Ee][Ff][Ii]\/[Bb][Oo][Oo][Tt]\/?$' "$cmdpath"; then
        cmdpath="${isodevice}/EFI/BOOT"
    fi
fi
configfile "${cmdpath}/grub.cfg"
EOF
} &
spinner "Creating early configuration file embedded inside GRUB in EFI partition"

# Copy BIOS/legacy boot required files
{
    cp /usr/lib/ISOLINUX/isolinux.bin "${HOME}/LIVE_BOOT/staging/isolinux/" && \
    cp /usr/lib/syslinux/modules/bios/* "${HOME}/LIVE_BOOT/staging/isolinux/" >/dev/null
} &
spinner "Copying BIOS/legacy boot required files"

# Copy EFI/modern boot required files
{
    cp -r /usr/lib/grub/x86_64-efi/* "${HOME}/LIVE_BOOT/staging/boot/grub/x86_64-efi/" >/dev/null
} &
spinner "Copying EFI/modern boot required files"

# Generate EFI bootable GRUB image
{
    grub-mkstandalone -O i386-efi \
        --modules="part_gpt part_msdos fat iso9660" \
        --locales="" \
        --themes="" \
        --fonts="" \
        --output="${HOME}/LIVE_BOOT/staging/EFI/BOOT/BOOTIA32.EFI" \
        "boot/grub/grub.cfg=${HOME}/LIVE_BOOT/tmp/grub-embed.cfg" >/dev/null

    grub-mkstandalone -O x86_64-efi \
        --modules="part_gpt part_msdos fat iso9660" \
        --locales="" \
        --themes="" \
        --fonts="" \
        --output="${HOME}/LIVE_BOOT/staging/EFI/BOOT/BOOTx64.EFI" \
        "boot/grub/grub.cfg=${HOME}/LIVE_BOOT/tmp/grub-embed.cfg" >/dev/null
} &
spinner "Generating EFI bootable GRUB image"

# Create FAT16 UEFI boot disk image
{
    (
        cd "${HOME}/LIVE_BOOT/staging" && \
        dd if=/dev/zero of=efiboot.img bs=1M count=20 && \
        mkfs.vfat efiboot.img && \
        mmd -i efiboot.img ::/EFI ::/EFI/BOOT && \
        mcopy -vi efiboot.img \
            "${HOME}/LIVE_BOOT/staging/EFI/BOOT/BOOTIA32.EFI" \
            "${HOME}/LIVE_BOOT/staging/EFI/BOOT/BOOTx64.EFI" \
            "${HOME}/LIVE_BOOT/staging/boot/grub/grub.cfg" \
            ::/EFI/BOOT/
    ) >/dev/null 2>&1

} &
spinner "Creating FAT16 UEFI boot disk image"

# Create Bootable ISO/CD
{
    (
        xorriso \
            -as mkisofs \
            -iso-level 3 \
            -o "${HOME}/LIVE_BOOT/debian-custom.iso" \
            -full-iso9660-filenames \
            -volid "DEBLIVE" \
            --mbr-force-bootable -partition_offset 16 \
            -joliet -joliet-long -rational-rock \
            -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
            -eltorito-boot \
                isolinux/isolinux.bin \
                -no-emul-boot \
                -boot-load-size 4 \
                -boot-info-table \
                --eltorito-catalog isolinux/isolinux.cat \
            -eltorito-alt-boot \
                -e --interval:appended_partition_2:all:: \
                -no-emul-boot \
                -isohybrid-gpt-basdat \
            -append_partition 2 C12A7328-F81F-11D2-BA4B-00A0C93EC93B ${HOME}/LIVE_BOOT/staging/efiboot.img \
            "${HOME}/LIVE_BOOT/staging" >/dev/null 2>&1
    )
} &
spinner "Creating Bootable ISO/CD"

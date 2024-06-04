#!/bin/bash

set -e
# Install necessary packages for the spinner function
apt-get install procps sudo >/dev/null

# Function for spinning indicator
spinner() {
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

# Variables for paths and URLs
LIVE_BOOT_DIR="$(pwd)/LIVE_BOOT"
DEBIAN_MIRROR="http://ftp.us.debian.org/debian/"

# Array of custom programs to be installed
CUSTOM_PROGRAMS=(
   pciutils
   aircrack-ng
   python3-pip
   python3
   git
   net-tools
   firmware-linux-nonfree
   firmware-iwlwifi
   wpasupplicant 
   wireless-tools
   wget
   tar
   dpkg
   i3
   picom
   i3blocks
   xorg
   xserver-xorg
   xserver-xorg-core
   xserver-xorg-input-all
   xserver-xorg-video-all
   lightdm
)

# Install necessary dependencies
sudo apt-get update >/dev/null
sudo apt-get install -y apt-utils debootstrap squashfs-tools xorriso \
   isolinux syslinux-efi grub-pc-bin grub-efi-amd64-bin grub-efi-ia32-bin \
   mtools dosfstools >/dev/null &
spinner "Installing necessary dependencies"

# Create directory for storing files
mkdir -p "${LIVE_BOOT_DIR}" &
spinner "Creating working directory"

# Bootstrap and Configure Debian
sudo debootstrap --arch=amd64 --variant=minbase stable \
   "${LIVE_BOOT_DIR}/chroot" "${DEBIAN_MIRROR}" >/dev/null &
spinner "Bootstrapping and configuring Debian"

# Add non-free and non-free-firmware repositories to Debian sources list
sudo chroot "${LIVE_BOOT_DIR}/chroot" /bin/bash -c "sed -i 's/main/main contrib non-free non-free-firmware/g' /etc/apt/sources.list"

# Install Linux kernel, live-boot, systemd-sysv, and custom programs using apt
sudo chroot "${LIVE_BOOT_DIR}/chroot" /bin/bash -c "apt-get update && apt-get --yes --quiet --no-install-recommends install linux-image-amd64 live-boot systemd-sysv ${CUSTOM_PROGRAMS[*]}" &
spinner "Installing Linux kernel, live-boot, systemd-sysv, and custom programs using apt"

# Add pip.conf configuration to the chroot environment
sudo chroot "${LIVE_BOOT_DIR}/chroot" /bin/bash -c "mkdir -p ~/.config/pip && echo -e '[global]\nbreak-system-packages = true' > ~/.config/pip/pip.conf"

# Install wifite2, knock, dirsearch, and dnsdumpster using git and pip
sudo chroot "${LIVE_BOOT_DIR}/chroot" /bin/bash -c "git clone https://github.com/derv82/wifite2.git /usr/local/bin/wifite2 >/dev/null 2>&1 && \
   cd /usr/local/bin/wifite2 && \
   ln -sf /usr/local/bin/wifite2/Wifite.py /usr/local/bin/wifite && \
   ln -sf /usr/local/bin/wifite2/Wifite.py /usr/local/bin/Wifite && \
   ln -sf /usr/bin/python3 /usr/bin/python && \
   git clone https://github.com/guelfoweb/knock.git /usr/local/bin/knock >/dev/null 2>&1 && \
   cd /usr/local/bin/knock && \
   pip install . --break-system-packages >/dev/null 2>&1 && \
   git clone https://github.com/maurosoria/dirsearch.git --depth 1 /usr/local/bin/dirsearch >/dev/null 2>&1 && \
   git clone https://github.com/zeropwn/dnsdmpstr /usr/local/bin/dnsdmpstr >/dev/null 2>&1 && \
   cd /usr/local/bin/dnsdmpstr && \
   pip3 install -r requirements.txt >/dev/null 2>&1 && \
   chmod +x ddump.py && \
   ln -sf /usr/local/bin/dnsdmpstr/ddump.py /usr/local/bin/ddump && \
   wget https://github.com/ffuf/ffuf/releases/download/v2.1.0/ffuf_2.1.0_linux_amd64.tar.gz -O /tmp/ffuf.tar.gz >/dev/null 2>&1 && \
   tar -xvf /tmp/ffuf.tar.gz -C /tmp ffuf >/dev/null 2>&1 && \
   mv /tmp/ffuf /usr/local/bin/ffuf && \
   rm /tmp/ffuf.tar.gz" &
spinner "Installing GIT programs"

# Copy caido-cli binary from host to chroot and create symlink
sudo cp caido-cli "${LIVE_BOOT_DIR}/chroot/usr/local/bin/caido-cli"
sudo chroot "${LIVE_BOOT_DIR}/chroot" /bin/bash -c "chmod +x /usr/local/bin/caido-cli && \
    ln -sf /usr/local/bin/caido-cli /usr/local/bin/caido" &
spinner "Installing caido-cli"

# Set hostname and root password
echo "mistos" | sudo tee "${LIVE_BOOT_DIR}/chroot/etc/hostname" >/dev/null &
spinner "Setting hostname to mistos"
echo 'root:live' | sudo chroot "${LIVE_BOOT_DIR}/chroot" chpasswd

# Copy custom i3 configuration files
sudo cp i3.conf "${LIVE_BOOT_DIR}/chroot/etc/i3/config"
sudo cp i3blocks.conf "${LIVE_BOOT_DIR}/chroot/etc/i3blocks.conf"

# Create directories
mkdir -p "${LIVE_BOOT_DIR}"/{staging/{EFI/BOOT,boot/grub/x86_64-efi,isolinux,live},tmp/grub-embed} &
spinner "Creating staging directories"

# Compress chroot environment into Squash filesystem
sudo mksquashfs "${LIVE_BOOT_DIR}/chroot" "${LIVE_BOOT_DIR}/staging/live/filesystem.squashfs" -e boot >/dev/null &
spinner "Compressing chroot environment into Squash filesystem"

# Copy kernel and initramfs
cp "${LIVE_BOOT_DIR}/chroot/boot"/vmlinuz-* "${LIVE_BOOT_DIR}/staging/live/vmlinuz" && \
cp "${LIVE_BOOT_DIR}/chroot/boot"/initrd.img-* "${LIVE_BOOT_DIR}/staging/live/initrd" &
spinner "Copying kernel and initramfs"

# Prepare ISOLINUX and GRUB boot loader configurations
cat > "${LIVE_BOOT_DIR}/staging/isolinux/isolinux.cfg" <<'EOF'
# ISOLINUX boot menu configuration file
UI vesamenu.c32

MENU TITLE Boot Menu
DEFAULT linux
TIMEOUT 1
MENU
EOF

cat > "${LIVE_BOOT_DIR}/staging/boot/grub/grub.cfg" <<'EOF'
# GRUB boot menu configuration file
insmod part_gpt
insmod part_msdos
insmod fat
insmod iso9660

insmod all_video
insmod font

set default="0"
set timeout=1

menuentry "Debian Live [EFI/GRUB]" {
   search --no-floppy --set=root --label DEBLIVE
   linux ($root)/live/vmlinuz boot=live quiet
   initrd ($root)/live/initrd
}
EOF

# Copy grub.cfg file to EFI BOOT directory
cp "${LIVE_BOOT_DIR}/staging/boot/grub/grub.cfg" "${LIVE_BOOT_DIR}/staging/EFI/BOOT/" &
spinner "Copying grub.cfg file to EFI BOOT directory"

# Create early configuration file embedded inside GRUB in EFI partition
cat > "${LIVE_BOOT_DIR}/tmp/grub-embed/grub-early.cfg" <<'EOF'
if ! [ -d "$cmdpath" ]; then
   if regexp --set=1:isodevice '^(\([^)]+\))\/?[Ee][Ff][Ii]\/[Bb][Oo][Oo][Tt]\/?$' "$cmdpath"; then
       cmdpath="${isodevice}/EFI/BOOT"
   fi
fi
configfile "${cmdpath}/grub.cfg"
EOF

# Copy BIOS/legacy and EFI/modern boot required files
cp /usr/lib/ISOLINUX/isolinux.bin "${LIVE_BOOT_DIR}/staging/isolinux/" && \
cp /usr/lib/syslinux/modules/bios/* "${LIVE_BOOT_DIR}/staging/isolinux/" >/dev/null &
spinner "Copying BIOS/legacy boot required files"

cp -r /usr/lib/grub/x86_64-efi/* "${LIVE_BOOT_DIR}/staging/boot/grub/x86_64-efi/" >/dev/null &
spinner "Copying EFI/modern boot required files"

# Generate EFI bootable GRUB image
grub-mkstandalone -O i386-efi --modules="part_gpt part_msdos fat iso9660" --locales="" --themes="" --fonts="" \
   --output="${LIVE_BOOT_DIR}/staging/EFI/BOOT/BOOTIA32.EFI" "boot/grub/grub.cfg=${LIVE_BOOT_DIR}/tmp/grub-embed/grub-early.cfg" >/dev/null &
spinner "Generating EFI bootable GRUB image (i386)"

grub-mkstandalone -O x86_64-efi --modules="part_gpt part_msdos fat iso9660" --locales="" --themes="" --fonts="" \
   --output="${LIVE_BOOT_DIR}/staging/EFI/BOOT/BOOTx64.EFI" "boot/grub/grub.cfg=${LIVE_BOOT_DIR}/tmp/grub-embed/grub-early.cfg" >/dev/null &
spinner "Generating EFI bootable GRUB image (x86_64)"

# Create FAT16 UEFI boot disk image
(
   cd "${LIVE_BOOT_DIR}/staging"
   dd if=/dev/zero of=efiboot.img bs=1M count=20
   mkfs.vfat efiboot.img
   mmd -i efiboot.img ::/EFI ::/EFI/BOOT
   mcopy -vi efiboot.img "${LIVE_BOOT_DIR}/staging/EFI/BOOT/BOOTIA32.EFI" "${LIVE_BOOT_DIR}/staging/EFI/BOOT/BOOTx64.EFI" "${LIVE_BOOT_DIR}/staging/boot/grub/grub.cfg" ::/EFI/BOOT/
) >/dev/null 2>&1 &
spinner "Creating FAT16 UEFI boot disk image"

# Create bootable ISO/CD
(
   xorriso -as mkisofs -iso-level 3 -o "mistos.iso" -full-iso9660-filenames \
       -volid "DEBLIVE" --mbr-force-bootable -partition_offset 16 \
       -joliet -joliet-long -rational-rock -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
       -eltorito-boot isolinux/isolinux.bin -no-emul-boot -boot-load-size 4 -boot-info-table \
       --eltorito-catalog isolinux/isolinux.cat \
       -eltorito-alt-boot -e --interval:appended_partition_2:all:: -no-emul-boot -isohybrid-gpt-basdat \
       -append_partition 2 C12A7328-F81F-11D2-BA4B-00A0C93EC93B "${LIVE_BOOT_DIR}/staging/efiboot.img" \
       "${LIVE_BOOT_DIR}/staging"
)
spinner "Creating bootable ISO/CD"

# Cleanup
rm -rf "${LIVE_BOOT_DIR}"

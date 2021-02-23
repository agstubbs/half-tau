# dropbear will complain if it isn't given an authorized_keys file
if [ -n "${PUBKEY_SSH_FIRST_USER}" ] ; then
    echo ${PUBKEY_SSH_FIRST_USER}|sudo tee /etc/dropbear-initramfs/authorized_keys
fi

sudo sed -i 's/^#DROPBEAR_OPTIONS=.*$/DROPBEAR_OPTIONS="-p 2222"/' /etc/dropbear-initramfs/config

#https://robpol86.com/raspberry_pi_luks.html
cat<<EOF| sudo tee /etc/kernel/postinst.d/initramfs-rebuild
#!/bin/sh -e

# Rebuild initramfs.gz after kernel upgrade to include new kernel's modules.
# https://github.com/Robpol86/robpol86.com/blob/master/docs/_static/initramfs-rebuild.sh
# Save as (chmod +x): /etc/kernel/postinst.d/initramfs-rebuild

# Remove splash from cmdline.
if grep -q '\bsplash\b' /boot/cmdline.txt; then
  sed -i 's/ \?splash \?/ /' /boot/cmdline.txt
fi

# Exit if not building kernel for this Raspberry Pi's hardware version.
version="\$1"
current_version="\$(uname -r)"
case "\${current_version}" in
  *-v8+)
    case "\${version}" in
      *-v8+) ;;
      *) exit 0
    esac
  ;;
  *+)
    case "\${version}" in
      *-v8+) exit 0 ;;
    esac
  ;;
esac

# Exit if rebuild cannot be performed or not needed.
[ -x /usr/sbin/mkinitramfs ] || exit 0
[ -f /boot/initramfs.gz ] || exit 0
lsinitramfs /boot/initramfs.gz |grep -q "/\$version$" && exit 0  # Already in initramfs.

# Rebuild.
mkinitramfs -o /boot/initramfs.gz "\$version"
EOF
sudo chmod +x /etc/kernel/postinst.d/initramfs-rebuild

cat<<EOF| sudo tee /etc/initramfs-tools/hooks/resize2fs
#!/bin/sh -e

# Copy resize2fs, fdisk, and other kernel modules into initramfs image.
# https://github.com/Robpol86/robpol86.com/blob/master/docs/_static/resize2fs.sh
# Save as (chmod +x): /etc/initramfs-tools/hooks/resize2fs

COMPATIBILITY=true  # Set to false to skip copying other kernel's modules.

PREREQ=""
prereqs () {
  echo "\${PREREQ}"
}
case "\${1}" in
  prereqs)
    prereqs
    exit 0
  ;;
esac

. /usr/share/initramfs-tools/hook-functions

copy_exec /sbin/resize2fs
copy_exec /sbin/fdisk
copy_exec /sbin/fsck.ext4
copy_exec /sbin/mkfs.ext4
copy_exec /sbin/parted

# Raspberry Pi 1 and 2+3 use different kernels. Include the other.
if "\${COMPATIBILITY}"; then
  case "\${version}" in
    *-v8+) other_version="\$(echo \${version} |sed 's/-v8+$/+/')" ;;
    *+) other_version="\$(echo \${version} |sed 's/+$/-v8+/')" ;;
    *)
      echo "Warning: kernel version doesn't end with +, ignoring."
      exit 0
  esac
  cp -r /lib/modules/\${other_version} \${DESTDIR}/lib/modules/
fi
EOF
sudo chmod +x /etc/initramfs-tools/hooks/resize2fs

sudo sed -i 's/^#CRYPTSETUP=.*$/CRYPTSETUP=y/' /etc/cryptsetup-initramfs/conf-hook


#https://raspberrypi.stackexchange.com/questions/112109/raspberry-pi-4-doesnt-show-a-wireless-interface-what-drivers-are-required


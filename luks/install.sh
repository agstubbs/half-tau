#!/bin/bash

if [ -f /etc/wpa_supplicant/wpa_supplicant.conf ] ; then
    if [ -z "${PBE_WPA_ESSID}" ] ; then
        PBE_WPA_ESSID=$(sudo cat /etc/wpa_supplicant/wpa_supplicant.conf | sed -ne 's+^[^#]*ssid=[ "]*\([^ "]*\)[ "]*$+\1+p')
    fi
    if [ -z "${PBE_WPA_PASSWORD}" ] ; then
        PBE_WPA_PASSWORD=$(sudo cat /etc/wpa_supplicant/wpa_supplicant.conf | sed -ne 's+^[^#]*psk=[ "]*\([^ "]*\)[ "]*$+\1+p')
    fi
    if [ -z "${WPA_COUNTRY}" ] ; then
        PBE_WPA_COUNTRY=$(sudo cat /etc/wpa_supplicant/wpa_supplicant.conf | sed -ne 's+^[^#]*country=[ "]*\([^ "]*\)[ "]*$+\1+p')
    fi
fi

if [ "${ENABLE_PBE_WIFI}" == "1" ] ; then
    cat <<EOF | sudo tee /etc/initramfs-tools/wpa_supplicant.conf
ctrl_interface=/tmp/wpa_supplicant
update_config=1
country=${PBE_WPA_COUNTRY}

network={
        ssid="${PBE_WPA_ESSID}"
        psk="${PBE_WPA_PASSWORD}"
        key_mgmt=WPA-PSK
}
EOF
    
    cat<<EOF|sudo tee /etc/initramfs-tools/hooks/enable-wireless
#!/bin/sh
set -e
PREREQ=""
prereqs()
{
    echo "\${PREREQ}"
}
case "\${1}" in
    prereqs)
        prereqs
        exit 0
        ;;
esac

. /usr/share/initramfs-tools/hook-functions

# CHANGE HERE for your correct modules.
manual_add_modules brcmfmac brcmutil brcmutil cfg80211 8021q garp stp llc
copy_exec /sbin/wpa_supplicant
copy_exec /sbin/wpa_cli
copy_exec /sbin/iwconfig
copy_exec /etc/initramfs-tools/wpa_supplicant.conf /etc/wpa_supplicant.conf
cp -a /lib/firmware/brcm/brcm*.txt \${DESTDIR}/usr/lib/firmware/brcm
cp -a /lib/firmware/brcm/brcm*.clm_blob \${DESTDIR}/usr/lib/firmware/brcm
EOF
    sudo chmod +x /etc/initramfs-tools/hooks/enable-wireless

    #http://www.marcfargas.com/posts/enable-wireless-debian-initramfs/
    cat<<EOF|sudo tee /etc/initramfs-tools/scripts/init-premount/a_enable_wireless
#!/bin/sh
PREREQ=""
prereqs()
{
    echo "\$PREREQ"
}

case \$1 in
prereqs)
    prereqs
    exit 0
    ;;
esac

. /scripts/functions

AUTH_LIMIT=30

alias WPACLI="/sbin/wpa_cli -p/tmp/wpa_supplicant -i\$DEVICE "

log_begin_msg "Starting WLAN connection"
/sbin/wpa_supplicant  -i\$DEVICE -c/etc/wpa_supplicant.conf -P/run/initram-wpa_supplicant.pid -B -f /tmp/wpa_supplicant.log

# Wait for AUTH_LIMIT seconds, then check the status
limit=\${AUTH_LIMIT}

echo -n "Waiting for connection (max \${AUTH_LIMIT} seconds)"
while [ \$limit -ge 0 -a `WPACLI status | grep wpa_state` != "wpa_state=COMPLETED" ]
do
    sleep 1
    echo -n "."
    limit=`expr \$limit - 1`
done
echo ""

if [ `WPACLI status | grep wpa_state` != "wpa_state=COMPLETED" ]; then
  ONLINE=0
  log_failure_msg "WLAN offline after timeout"
  panic
else
  ONLINE=1
  log_success_msg "WLAN online"
fi

configure_networking
EOF
    sudo chmod a+x /etc/initramfs-tools/scripts/init-premount/a_enable_wireless

    cat<<EOF|sudo tee /etc/initramfs-tools/scripts/local-bottom/kill_wireless
#!/bin/sh
PREREQ=""
prereqs()
{
    echo "\$PREREQ"
}

case \$1 in
prereqs)
    prereqs
    exit 0
    ;;
esac

echo "Killing wpa_supplicant so the system takes over later."
kill \$(cat /run/initram-wpa_supplicant.pid)
EOF
    sudo chmod a+x /etc/initramfs-tools/scripts/local-bottom/kill_wireless

    sudo sed -i -e 's/^DEVICE=.*$/DEVICE=wlan0/' /etc/initramfs-tools/initramfs.conf
else
    rm -f /etc/initramfs-tools/wpa_supplicant.conf
    rm -f /etc/initramfs-tools/hooks/enable-wireless
    rm -f /etc/initramfs-tools/scripts/init-premount/a_enable_wireless
    rm -f /etc/initramfs-tools/scripts/local-bottom/kill_wireless
    sudo sed -i -e 's/^DEVICE=.*$/DEVICE=/' /etc/initramfs-tools/initramfs.conf
fi

#https://hamy.io/post/0009/how-to-install-luks-encrypted-ubuntu-18.04.x-server-and-enable-remote-unlocking/#gsc.tab=0

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


#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Configure a mounted/extracted Debian rootfs, not the host or live board.
# See ../../ORANGECRAB_DEBIAN.md for password setup and image preparation.
set -eu
if [ "$#" -ne 1 ]; then
    echo "Usage: sh $0 ROOTFS_DIRECTORY" >&2
    exit 2
fi
root=$(realpath -e -- "$1")
if [ "$root" = / ] || [ ! -f "$root/etc/debian_version" ] ||
   [ ! -d "$root/usr/lib/systemd/system" ]; then
    echo "Expected a separate Debian root filesystem: $root" >&2
    exit 2
fi
mkdir -p "$root/etc/systemd/system.conf.d" \
    "$root/etc/systemd/system/sysinit.target.wants" \
    "$root/etc/systemd/system/multi-user.target.wants" \
    "$root/etc/systemd/system/serial-getty@ttyLXU0.service.d" \
    "$root/var/lib/dbus" "$root/boot"
cat > "$root/etc/systemd/system.conf.d/40-orangecrab-timeouts.conf" <<'EOF'
[Manager]
DefaultTimeoutStartSec=10min
DefaultDeviceTimeoutSec=10min
DefaultTimeoutStopSec=2min
EOF
cat > "$root/etc/systemd/system/serial-getty@ttyLXU0.service.d/40-orangecrab.conf" <<'EOF'
[Unit]
JobTimeoutSec=10min
[Service]
Type=simple
EOF
cat > "$root/etc/systemd/system/orangecrab-firstboot.service" <<'EOF'
[Unit]
Description=Set the OrangeCrab root password on first boot
DefaultDependencies=no
After=systemd-remount-fs.service
Before=systemd-user-sessions.service serial-getty@ttyLXU0.service
ConditionPathExists=!/etc/orangecrab-firstboot-complete

[Service]
Type=oneshot
ExecStart=/usr/bin/systemd-firstboot --prompt-root-password --force
ExecStartPost=/usr/bin/touch /etc/orangecrab-firstboot-complete
RemainAfterExit=yes
StandardInput=tty-force
StandardOutput=tty
StandardError=tty
TTYPath=/dev/ttyLXU0
TTYReset=yes
TTYVHangup=yes

[Install]
WantedBy=multi-user.target
EOF
cat > "$root/etc/systemd/system/orangecrab-console.service" <<'EOF'
[Unit]
Description=OrangeCrab local serial login
DefaultDependencies=no
After=systemd-remount-fs.service orangecrab-firstboot.service
Conflicts=shutdown.target
Before=shutdown.target

[Service]
Type=simple
ExecStart=/sbin/agetty --noreset --noclear -L ttyLXU0 115200 vt100
Restart=always
RestartSec=2

[Install]
WantedBy=sysinit.target
EOF
ln -sfn /dev/null "$root/etc/systemd/system/serial-getty@hvc0.service"
ln -sfn /dev/null "$root/etc/systemd/system/serial-getty@ttyLXU0.service"
ln -sfn /usr/lib/systemd/system/multi-user.target \
    "$root/etc/systemd/system/default.target"
ln -sfn ../orangecrab-console.service \
    "$root/etc/systemd/system/sysinit.target.wants/orangecrab-console.service"
ln -sfn ../orangecrab-firstboot.service \
    "$root/etc/systemd/system/multi-user.target.wants/orangecrab-firstboot.service"
cat > "$root/etc/fstab" <<'EOF'
/dev/mmcblk0p2 / ext4 defaults,errors=remount-ro 0 1
/dev/mmcblk0p1 /boot vfat defaults,nofail,x-systemd.device-timeout=10min 0 2
EOF
printf 'orangecrab\n' > "$root/etc/hostname"
cat > "$root/etc/hosts" <<'EOF'
127.0.0.1 localhost
127.0.1.1 orangecrab
::1 localhost ip6-localhost ip6-loopback
EOF
: > "$root/etc/machine-id"
ln -sfn /etc/machine-id "$root/var/lib/dbus/machine-id"
echo "Configured $root. Set its root password, then create"
echo "$root/etc/orangecrab-firstboot-complete before copying to SD."

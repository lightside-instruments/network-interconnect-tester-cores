# Reproducing the OrangeCrab Debian system

This guide reproduces the system verified on **2026-11-17**: OrangeCrab
r0.2-family / 85F, **128 MiB DDR3**, single-core VexiiRiscv RV64IMAFDC/Sv39
at 40 MHz, coherent native four-bit SD DMA, Debian 13 riscv64, and USB ACM
console. There are no network tester cores, Ethernet controller, or SSH
server in this configuration.

The tested Linux version is `6.1.0-rc2-orangecrab-uartfix2+`. Its UART timer
and USB transmit-backpressure fixes are required. The old release's
**512 MiB device tree is incorrect for this board** and must be replaced.

## 1. Establish paths and install host prerequisites

Use **Debian 13 (trixie), amd64**, with Bash. The tested host used Python
3.13, GCC 14.2, Java 21, OpenOCD 0.12.0, and GNU binutils 2.44. Install
the host tools and ordinary Python dependencies with APT. Run from the
root of this repository; keep these environment variables in subsequent
shells:

```bash
set -euo pipefail
export OC_REPO="$PWD"
test -f "$OC_REPO/systems/litex/boards/targets/gsd_orangecrab_debian.py"
export OC_SUPPORT="$OC_REPO/systems/litex/prog/orangecrab"
export OC_REPORT="$OC_REPO/codex/reports/orangecrab-debian/kernel-timer-fix"
export OC_BASE="$OC_REPO/releases/orangecrab-debian13-rv64-40mhz-2026-11-10"
export OC_WORK="$OC_REPO/build/orangecrab-reproduce"
export OC_SRC="$OC_WORK/src"
export OC_BUILD="$OC_WORK/soc"
mkdir -p "$OC_WORK/tools" "$OC_WORK/boot"
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

sudo apt update
sudo apt install build-essential git curl ca-certificates gnupg \
    python3-venv python3-dev python3-pip python3-setuptools python3-wheel \
    python3-serial python3-packaging python3-requests python3-colorama \
    meson ninja-build \
    gcc-riscv64-unknown-elf binutils-riscv64-unknown-elf \
    gcc-riscv64-linux-gnu binutils-riscv64-linux-gnu \
    device-tree-compiler flex bison bc libelf-dev libssl-dev \
    openjdk-21-jdk mmdebstrap qemu-user-static binfmt-support \
    dosfstools e2fsprogs fdisk util-linux openocd minicom \
    yosys nextpnr-ecp5 nextpnr-ecp5-chipdb fpga-trellis fpga-trellis-database
```

Enable the foreign-architecture executor for both rootfs preparation paths:

```bash
sudo update-binfmts --enable qemu-riscv64
sudo update-binfmts --display qemu-riscv64
```

The two cross compilers have different jobs: `riscv64-unknown-elf-` builds
LiteX BIOS/picolibc; `riscv64-linux-gnu-` builds Linux and OpenSBI. The
bare-metal linker failed OpenSBI's PIE check in the original attempt.

Debian's [`nextpnr-ecp5`](https://packages.debian.org/trixie/nextpnr-ecp5)
and [`fpga-trellis`](https://packages.debian.org/trixie/fpga-trellis)
packages provide the ECP5 place/router and bitstream tools, including
`ecppack`. The chip databases are installed explicitly above. Check that
the Debian executables are selected:

```bash
/usr/bin/yosys -V
/usr/bin/nextpnr-ecp5 --version
command -v ecppack
/usr/bin/meson --version
/usr/bin/ninja --version
```

Trixie's package versions available on the checked host were Yosys 0.52,
nextpnr 0.7, Trellis 1.4, Meson 1.7 and Ninja 1.12. The pinned picolibc
source requires Meson >= 0.53, so the Debian Meson is sufficient. The
recorded historical FPGA route used OSS CAD Suite 20260420 (Yosys
`0.64+68` / `413169663`, nextpnr `0.10-39-g33e1c903`). Those versions are
recorded for provenance, **not required downloads for this APT-first path**.
A new route made with Debian tools needs its own timing validation and is
not expected to have identical bytes. To use exact tested FPGA bytes,
select the archived image in step 3 instead.

### Install sbt through its upstream APT repository

The full `sbt` command is not supplied by the standard trixie repositories;
Debian's `libsbt-*` packages are not a replacement for the launcher. Use
[sbt's supported Debian repository](https://www.scala-sbt.org/1.x/docs/Installing-sbt-on-Linux.html),
with its signing key scoped to that repository:

```bash
curl -fL 'https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x2EE0EA64E40A89B84B2DF73499E82A75642AC823' \
    -o "$OC_WORK/tools/sbt-release.asc"
gpg --show-keys --with-colons "$OC_WORK/tools/sbt-release.asc" | \
    grep -F '2EE0EA64E40A89B84B2DF73499E82A75642AC823'
gpg --batch --yes --dearmor -o "$OC_WORK/tools/sbt-release.gpg" \
    "$OC_WORK/tools/sbt-release.asc"
sudo install -D -m 0644 "$OC_WORK/tools/sbt-release.gpg" /etc/apt/keyrings/sbt-release.gpg
printf '%s\n' 'deb [signed-by=/etc/apt/keyrings/sbt-release.gpg] https://repo.scala-sbt.org/scalasbt/debian all main' | \
    sudo tee /etc/apt/sources.list.d/sbt.list >/dev/null
sudo apt update
sudo apt install sbt=1.10.0
```

Version 1.10.0 is available in that upstream repository and matches the
pinned VexiiRiscv project's `project/build.properties`. This is the one
additional APT repository in the guide; no global `apt-key` trust or
unverified binary installer is used. sbt still downloads its Scala/Maven
build dependencies when the CPU generator first runs.

Allow several GiB of RAM, substantial source/build disk space, and network
access for Git, sbt/Maven, and Debian packages. The default Python setup
does not need PyPI packages.

## 2. Fetch pinned sources and create the LiteX environment

The source-build path does not require the old release archive. The optional
prebuilt-image paths below require its local files; if only the tarball is
present, extract it with GNU tar:

```bash
if [ ! -d "$OC_BASE" ] && [ -f "${OC_BASE}.tar.gz" ]; then
    tar --sparse -xzf "${OC_BASE}.tar.gz" -C "$OC_REPO/releases"
fi
```

The complete repository URLs/revisions are in
[`prog/orangecrab/sources.json`](prog/orangecrab/sources.json). Important pins:

| Component | Revision |
| --- | --- |
| LiteX | `4452113fa0ad43f4373258710c837ee408e5b0d0` |
| LiteX boards | `081a0ed5f63967abf3fc3f7b2afdd03f19ad0468` |
| VexiiRiscv | `dbcaa98fca102b9c691320a80f90429b4e2a5335` |
| Linux vendor tree | `247f34f7b80357943234f93f247a1ae6b6c3a740` |
| OpenSBI | `ed70256dd22c09962d146e433834239825ef0616` |

```bash
python3 "$OC_SUPPORT/fetch-sources.py" "$OC_SRC"
python3 -m venv --system-site-packages "$OC_WORK/venv"
source "$OC_WORK/venv/bin/activate"
while IFS= read -r component; do
    python -m pip install --no-deps --no-build-isolation -e "$component"
done < <(python "$OC_SUPPORT/fetch-sources.py" "$OC_SRC" --list-python)

git -C "$OC_SRC/litex" apply --check "$OC_SUPPORT/patches/litex-gcc14.patch"
git -C "$OC_SRC/litex" apply "$OC_SUPPORT/patches/litex-gcc14.patch"
```

The virtualenv can see the APT-installed Python dependencies. Pip is used
only to register the pinned LiteX/Migen/CPU sources that are not supplied
as the needed Debian packages. `--no-deps --no-build-isolation` prevents
those editable installs from replacing APT libraries or fetching a private
setuptools/Meson/Ninja stack from PyPI. Do not use `sudo pip` or
`--break-system-packages`.

The fetch helper uses fresh directories, verifies existing checkout
revisions, and fetches pinned submodules. It does not reset existing work.
The GCC 14 patch captures the tested local LiteX `common.mak` change; it is
separate from the Linux UART patch. A comment-only local boards change was
not required and is not included.

VexiiRiscv is placed under the Python CPU package's `verilog/ext/` directory,
where LiteX expects it. Use `--update-repo no` below so LiteX does not replace
that pinned checkout. First CPU generation still needs sbt dependencies.

## 3. Build gateware and its initialized BIOS

The current target selects `MT41K64M16`, the **128 MiB** DDR3 part, 85F FPGA,
40 MHz system clock, USB ACM, native SD, and coherent CPU DMA. The onboard
reference oscillator stays at 48 MHz. Do not increase the system clock to
48 MHz: previous routes missed that constraint.

```bash
cd "$OC_REPO/systems/litex"
python -m boards.targets.gsd_orangecrab_debian \
    --toolchain trellis --sys-clk-freq 40e6 --update-repo no \
    --output-dir "$OC_BUILD" --csr-csv "$OC_BUILD/csr.csv" \
    --build --no-compile-gateware
```

This builds software/BIOS and emits gateware/tool scripts without running
synthesis or placement/routing. Do **not** also pass `--no-compile-software`:
the ROM must contain a compiled BIOS. Generated output includes
`software/bios/bios.bin`, `csr.json`, `gateware/gsd_orangecrab.v`, the ROM
initialization file, `.ys`, `.lpf`, and `orangecrab-debian.dts`.

Run synthesis and the router explicitly to select the router/seed used in
the successful historical build:

```bash
cd "$OC_BUILD/gateware"
yosys -l synthesis.log -s gsd_orangecrab.ys
nextpnr-ecp5 --85k --package CSFBGA285 --speed 8 \
    --json gsd_orangecrab.json --lpf gsd_orangecrab.lpf \
    --textcfg gsd_orangecrab.config --router router2 --seed 1 \
    --report timing.json > timing.log 2>&1
python "$OC_SUPPORT/check-timing.py" timing.json
ecppack --svf gsd_orangecrab.svf gsd_orangecrab.config gsd_orangecrab.bit
export OC_GATEWARE="$OC_BUILD/gateware"
```

Only pack/program a route that passes **all** final clock constraints. The
JSON check excludes misleading intermediate placement estimates. If routing
fails, preserve its log and try a different seed, then check again.

**What has actually been validated:** the running board used the archived
40 MHz RV64 FPGA image, routed with router2/seed1, system fmax 44.59 MHz.
That image was generated before the RAM correction, so its BIOS displays
512 MiB and its controller exposes a wider address aperture. Linux safely
uses its lower 128 MiB with the corrected DTB. The *current 128 MiB target*
was updated and its CLI checked, but was **not rebuilt/routed/hardware-tested
in the final kernel-fix session**. A fresh build above needs its own timing
and hardware validation; the old route's numbers are not a result for it.

To reproduce the **exact tested FPGA binary**, instead select:

```bash
export OC_GATEWARE="$OC_BASE/fpga"
```

The historical source snapshot and synthesis/route reports are in
`codex/reports/orangecrab-debian/40mhz/`. Its target snapshot can reconstruct
the old controller configuration using the same build procedure, but its
512 MiB DTS must never be used on this 128 MiB board. Expect build timestamps
and regenerated placement to prevent byte-identical rebuilds.

### Optional external GPIO network tester

To include the configurable traffic generator, receive analyzer and fabric
8b/10b PCS, add these arguments to the elaboration command in section 3:

```bash
    --with-network-tester --network-tester-mode serial_external
```

Use a separate output directory, for example
`build/orangecrab-debian-network-tester`, and run the same synthesis, routing,
timing check and packing steps. The tester-only build passed all eight clock
constraints with nextpnr 0.10-39-g33e1c903 and `--router router2 --threads 2
--seed 2`, including 44.571 MHz against 40.003 MHz for the system clock.
The bitstream, SVF, BIOS, and CSR maps are in the
[build report](../../codex/reports/orangecrab-debian-network-tester/stable-csr-seed2/).
The board reached the Debian 13 serial login prompt from the existing SD
card. Its physical GPIO loopback passed from Debian with one frame and
with 1,000 frames in ten bursts, with zero CRC or preamble errors.

The established OrangeCrab connections are:

| Signal | FPGA pin |
| --- | --- |
| Serial TX+ | N17 |
| Serial TX− | M18 |
| Serial RX+ | B8 |
| Serial RX− | C8 |
| Generator cycle-start monitor | B10 |
| Generator GMII-enable monitor | B9 |

These are complementary **3.3 V CMOS** signals. At a 40 MHz system clock,
the serial bit clock is 10 MHz and GMII runs at 1 MHz. The fabric PCS uses
1000BASE-X encoding at this reduced rate; it does not provide a gigabit
electrical interface. TX can run without an incoming RX stream.

The Debian target keeps 0x800-byte CSR pages and reserves the original
peripheral banks. UART remains at `0xf0001000` with IRQ 1, and SD remains
at `0xf0003000` with IRQ 3. The corrected non-tester 128 MiB DTB has these
same addresses. The shared MAC adds its own device-tree node. Keep the
generated DTB, bitstream, initialized BIOS, `csr.csv` and `csr.json`
together. The patched kernel can be reused.

The generated CSR map is the authority for software access. For this target,
the generator starts at `0xf0004000` and the analyzer at `0xf0004038`.
Generator controls include
frame contents/length, interframe and interburst gaps, frames per burst and
total frame count. Multiword CSRs follow LiteX ordering as recorded in the
generated headers; the older AXI register layout is different.

The inherited real-time clock increments by 8 nominal nanoseconds per system
cycle. At 40 MHz its timestamps therefore advance at 0.32 times wall-clock
time; treat them as scaled timestamps until the clock increment is adapted.

#### Switch between `eth0` and the traffic tester

The external-serial build shares one fabric PCS between LiteEth and the
tester. Ingress goes to both LiteEth and the analyzer in either mode.
LiteEth supplies TX after reset and Debian exposes it as `eth0`.
Install the newly generated DTB to register the MAC. The patched
kernel configuration already includes the LiteEth driver. The GPIO link
requires a peer that uses the same 10 Mbit/s serial 8b/10b encoding.

The [previous shared MAC build](../../codex/reports/orangecrab-debian-network-tester/eth0-seed4/)
passed all eight clock constraints with router2, two threads, and seed 4.
The system clock reached 43.109 MHz against 40.003 MHz. On the board,
Linux registered `eth0` and Debian reached the serial login prompt after
installing the matching DTB and loading the FPGA over JTAG.
With a physical GPIO loopback, `eth0` received an exact Ethernet frame
before and after switching modes. In tester mode, the board received all
1,000 frames in ten bursts with zero CRC or preamble errors.

In a root shell, use the 32-bit `ethphy_select` CSR from the generated
`csr.csv`. The address is `0xf0005000` in this build. The commands below
use the BusyBox `devmem` applet.

```sh
ip link set eth0 up
busybox devmem 0xf0005000 32 1  # Generator TX
busybox devmem 0xf0005000 32    # Verify selector
```

Stop the generator and let any in-flight frames finish before returning to
adapter mode:

```sh
busybox devmem 0xf000400c 32 0  # Stop generator
busybox devmem 0xf0005000 32 0  # LiteEth TX
```

The mode request crosses into the GMII TX clock domain and takes effect
between frames. Keep `eth0` up to receive traffic during generator TX.
Any queued LiteEth transmit traffic waits until selector 0 is restored.

With the carrier-aware kernel and matching gateware/DTB, `eth0` reports
`LOWER_UP` when the receiver has both clock recovery lock and 8b/10b
synchronization. It checks the PCS status every 250 ms while the interface
is up. Either TX source can be selected while carrier stays up. The
existing kernel requires the carrier patch below to report these changes.

## 4. Build the patched RV64 Linux kernel

Use the supplied configuration, not a Debian stock kernel or the unpatched
vendor default. SD, ext4, LiteUART console, PLIC, and RV64/FPU support must be
built in because there is no initramfs.

```bash
cd "$OC_SRC/linux"
git apply --check "$OC_SUPPORT/patches/linux-liteuart.patch"
git apply "$OC_SUPPORT/patches/linux-liteuart.patch"
git apply --check "$OC_SUPPORT/patches/linux-liteeth-link-binding.patch"
git apply "$OC_SUPPORT/patches/linux-liteeth-link-binding.patch"
git apply --check "$OC_SUPPORT/patches/linux-liteeth-carrier.patch"
git apply "$OC_SUPPORT/patches/linux-liteeth-carrier.patch"
cp "$OC_SUPPORT/linux.config" .config
make ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu- olddefconfig
make -j"$(nproc)" ARCH=riscv CROSS_COMPILE=riscv64-linux-gnu- Image
cp arch/riscv/boot/Image "$OC_WORK/boot/Image"
```

`CONFIG_LOCALVERSION=-orangecrab-uartfix2` identifies the corrected kernel.
The patch initializes the UART timer once, cancels it synchronously on
shutdown, queues TX instead of spinning with interrupts disabled, and
bounds printk/early-console FIFO waits. `CONFIG_WERROR=n` permits the known
GCC 14 warnings in old BTRFS/socket code; it does not replace the UART fix.

A rebuild's version suffix/build timestamp/hash can differ. The **tested
prebuilt Image** in `$OC_REPORT/Image` predates PCS carrier reporting.
Its SHA-256 is:

```text
1532939d4e49ebd7ab5307c6ec72db998dce119045b6db258025341f1993f41c
```

For exact tested kernel bytes, copy that file instead of the new build:

```bash
cp "$OC_REPORT/Image" "$OC_WORK/boot/Image"
```

## 5. Build OpenSBI

```bash
cd "$OC_SRC/opensbi"
make -j"$(nproc)" PLATFORM=generic PLATFORM_RISCV_XLEN=64 \
    CROSS_COMPILE=riscv64-linux-gnu- \
    FW_TEXT_START=0x40f00000 FW_JUMP_ADDR=0x41000000 \
    FW_JUMP_FDT_ADDR=0x46000000
cp build/platform/generic/firmware/fw_jump.bin "$OC_WORK/boot/opensbi.bin"
riscv64-linux-gnu-readelf -h build/platform/generic/firmware/fw_jump.elf
riscv64-linux-gnu-nm -n build/platform/generic/firmware/fw_jump.elf | grep _fw_end
```

Require entry `0x40f00000` and firmware end below `0x40f80000`, the end of
the 512 KiB reservation. Use **fw_jump**, not fw_dynamic. The tested generic
firmware included LiteX serial/reset and ACLINT timer/IPI drivers.

For the exact tested firmware binary, use:

```bash
cp "$OC_BASE/boot/opensbi.bin" "$OC_WORK/boot/opensbi.bin"
```

## 6. Prepare the device tree and BIOS boot manifest

| Item | Physical address/range |
| --- | --- |
| Physical DDR3 | `0x40000000..0x47ffffff` (128 MiB) |
| OpenSBI reservation | `0x40f00000..0x40f7ffff` |
| Linux Image | `0x41000000` |
| DTB | `0x46000000` |
| Root filesystem | `/dev/mmcblk0p2` |

For a fresh corrected gateware build, compile **its generated DTS**:

```bash
cp "$OC_BUILD/orangecrab-debian.dts" "$OC_WORK/boot/orangecrab-debian.dts"
dtc -I dts -O dtb -o "$OC_WORK/boot/orangecrab-debian.dtb" \
    "$OC_WORK/boot/orangecrab-debian.dts"
```

Inspect the DTS before proceeding: the memory node must contain
`reg = <0x40000000 0x08000000>`, SD/CSR addresses must match the selected
SoC, and bootargs must select `root=/dev/mmcblk0p2` without `init=/bin/sh`.
Do not use a temporary recovery DTS containing the kernel-transport window.

For the **tested archived gateware**, use its corrected, tested DTB instead:

```bash
cp "$OC_REPORT/orangecrab-debian-128m.dts" "$OC_WORK/boot/orangecrab-debian.dts"
cp "$OC_REPORT/orangecrab-debian-128m.dtb" "$OC_WORK/boot/orangecrab-debian.dtb"
```

That DTB's SHA-256 is
`a1349785f31bd4f0669852df73a5c23315bb41629a041dd3c86a8dedb2efe98f`.
Install the boot manifest:

```bash
cp "$OC_SUPPORT/boot.json" "$OC_WORK/boot/boot.json"
cat "$OC_WORK/boot/boot.json"
(cd "$OC_WORK/boot" && sha256sum Image opensbi.bin orangecrab-debian.dtb boot.json > SHA256SUMS)
```

The manifest loads the three files, enters OpenSBI at `0x40f00000`, and
passes the DTB in **r2**, corresponding to RISC-V **a1**. r1/a0 is hart 0.
Do not put the DTB in r1. These are BIOS argument names, not a Linux command
line.

## 7. Prepare Debian and apply the final console/startup configuration

### 7a. Recommended for matching the tested package set: reuse the base image

The archived 14 GiB image contains the original Debian 13 riscv64 packages.
Make a **separate sparse copy**; the original bundle/image may be hardlinked,
so do not edit it in place or create another hardlink.

```bash
cp --reflink=auto --sparse=always "$OC_BASE/sd-card.img" "$OC_WORK/sd-card.img"
OC_LOOP=$(sudo losetup --find --show --partscan "$OC_WORK/sd-card.img")
export OC_LOOP
mkdir -p "$OC_WORK/mnt/root" "$OC_WORK/mnt/boot"
sudo mount "${OC_LOOP}p2" "$OC_WORK/mnt/root"
sudo mount "${OC_LOOP}p1" "$OC_WORK/mnt/boot"
export OC_ROOTFS="$OC_WORK/mnt/root"
```

Continue at **7c**, then copy the boot files and finish at **8b**. This path
retains the exact original package versions listed in
[`rootfs-packages.tsv`](prog/orangecrab/rootfs-packages.tsv), while applying
the later fixes that the old image/archive lacks.

### 7b. Alternatively build a fresh Debian root filesystem

Check that the RISC-V QEMU binfmt handler is enabled:

```bash
sudo update-binfmts --display qemu-riscv64
```

Then create a new directory rootfs:

```bash
export OC_ROOTFS="$OC_WORK/rootfs"
sudo mmdebstrap --architectures=riscv64 --variant=minbase \
    --include=systemd-sysv,udev,dbus,python3,iproute2,iputils-ping,ifupdown,procps,nano,less,ca-certificates,openssl \
    trixie "$OC_ROOTFS" \
    'deb https://deb.debian.org/debian trixie main' \
    'deb https://security.debian.org/debian-security trixie-security main'
```

This uses signed repositories and QEMU to run riscv64 package scripts.
The original build used mmdebstrap's unshare mode to produce a tarball;
sudo/directory mode here simplifies mounting/copying without changing the
guest architecture. Current repositories may yield newer package versions.
For exact original versions, use 7a; the package list alone is not a complete
signed snapshot/deb cache and cannot guarantee byte-identical new installs.

### 7c. Install the startup fixes and configure root authentication offline

```bash
sudo sh "$OC_SUPPORT/configure-rootfs.sh" "$OC_ROOTFS"
```

The helper reproduces the later card-only fixes: long device/service startup
timeouts, `/boot` mounted with `nofail`, multi-user default, unused hvc0
getty masked, and a dedicated `agetty` console on `ttyLXU0`. It masks the
standard ttyLXU0 getty so there is only one reader. It also installs the
original firstboot unit and resets machine-id for a fresh clone.

Set the password **before first boot** and mark firstboot complete. This
avoids the original firstboot/getty race and slow on-board password hashing.
The running laboratory system uses the user-requested `root` / `root`;
enter `root` below to match it, or choose another password for your copy.

```bash
sudo -v
read -r -s -p 'Password for guest root: ' OC_ROOT_PASSWORD
printf '\n'
printf 'root:%s\n' "$OC_ROOT_PASSWORD" | \
    sudo chroot "$OC_ROOTFS" /usr/sbin/chpasswd -c SHA512
unset OC_ROOT_PASSWORD
sudo chroot "$OC_ROOTFS" /usr/bin/chage -d 1 root
sudo touch "$OC_ROOTFS/etc/orangecrab-firstboot-complete"
sudo chroot "$OC_ROOTFS" /usr/bin/passwd -S root
```

The binfmt handler is required for these chroot commands. The final `P`
status indicates a set password. `chage -d 1` clears forced expiry without
using the board's unset clock; `-d 0` would force another password change.
The helper contains no fixed credential. `chpasswd` stores the operator-selected
password hash in the new rootfs's `/etc/shadow`, as on a normal Unix system.

## 8. Construct/finalize the SD image

### 8a. Only for the fresh rootfs from 7b: create the partitioned image

Skip this subsection if 7a already provided the mounted image.

```bash
truncate -s 14G "$OC_WORK/sd-card.img"
sfdisk "$OC_WORK/sd-card.img" <<'PARTITIONS'
label: dos
unit: sectors

start=2048, size=524288, type=c, bootable
start=526336, size=28833792, type=83
PARTITIONS
OC_LOOP=$(sudo losetup --find --show --partscan "$OC_WORK/sd-card.img")
export OC_LOOP
sudo mkfs.vfat -F 32 -n BOOT "${OC_LOOP}p1"
sudo mkfs.ext4 -F -L rootfs "${OC_LOOP}p2"
mkdir -p "$OC_WORK/mnt/root" "$OC_WORK/mnt/boot"
sudo mount "${OC_LOOP}p2" "$OC_WORK/mnt/root"
sudo mount "${OC_LOOP}p1" "$OC_WORK/mnt/boot"
sudo cp -a "$OC_ROOTFS/." "$OC_WORK/mnt/root/"
```

The image is 15032385536 bytes (14 GiB), with a 256 MiB FAT32 first partition
and an ext4 second partition. It fits the tested nominal 16 GB card. Root
ownership, permissions and symlinks are preserved by the privileged copy.

### 8b. Install the final boot files and cleanly detach the image

```bash
sudo cp "$OC_WORK/boot/Image" "$OC_WORK/boot/opensbi.bin" \
    "$OC_WORK/boot/orangecrab-debian.dtb" "$OC_WORK/boot/boot.json" \
    "$OC_WORK/boot/SHA256SUMS" "$OC_WORK/mnt/boot/"
(cd "$OC_WORK/mnt/boot" && sha256sum -c SHA256SUMS)
sync
sudo umount "$OC_WORK/mnt/boot"
sudo umount "$OC_WORK/mnt/root"
sudo fsck.vfat -n "${OC_LOOP}p1"
sudo e2fsck -fn "${OC_LOOP}p2"
sudo losetup -d "$OC_LOOP"
sha256sum "$OC_WORK/sd-card.img" > "$OC_WORK/sd-card.img.sha256"
```

Require both filesystem checks to pass before writing the card. On an error,
unmount/detach only the loop device shown by `losetup` for this image; do
not guess a `/dev/loopN` or run filesystem checks on mounted partitions.

## 9. Write and verify a physical card

**This step erases the selected whole device.** Insert the card in a host
reader, inspect model/serial/size, and set the device explicitly. `/dev/mmcblk0`
is only a historical example and must not be assumed on another host.

```bash
lsblk -o NAME,PATH,SIZE,MODEL,SERIAL,TYPE,MOUNTPOINTS
export OC_SD_DEVICE=/dev/disk/by-id/REPLACE_WITH_THE_WHOLE_CARD_DEVICE
readlink -f "$OC_SD_DEVICE"
test -b "$OC_SD_DEVICE"
test "$(lsblk -dn -o TYPE "$OC_SD_DEVICE")" = disk
lsblk -o NAME,SIZE,TYPE,MOUNTPOINTS "$OC_SD_DEVICE"
```

Unmount any mounted card partitions explicitly. Confirm the selected disk
has no mounted children and has room for the image:

```bash
if lsblk -nr -o MOUNTPOINT "$OC_SD_DEVICE" | grep -q '[^[:space:]]'; then
    echo 'Card or a child partition is still mounted'; false
fi
test "$(sudo blockdev --getsize64 "$OC_SD_DEVICE")" -ge \
    "$(stat -c %s "$OC_WORK/sd-card.img")"
read -r -p "Type the whole device path to erase: " OC_CONFIRM
test "$OC_CONFIRM" = "$OC_SD_DEVICE"
```

Only after those checks succeed:

```bash
sudo dd if="$OC_WORK/sd-card.img" of="$OC_SD_DEVICE" \
    bs=4M iflag=fullblock oflag=direct conv=fsync status=progress
sudo blockdev --flushbufs "$OC_SD_DEVICE"
OC_IMAGE_BYTES=$(stat -c %s "$OC_WORK/sd-card.img")
OC_EXPECTED_SHA=$(sha256sum "$OC_WORK/sd-card.img" | cut -d ' ' -f 1)
OC_READBACK_SHA=$(sudo dd if="$OC_SD_DEVICE" bs=4M \
    iflag=direct,count_bytes count="$OC_IMAGE_BYTES" status=progress | sha256sum | cut -d ' ' -f 1)
test "$OC_EXPECTED_SHA" = "$OC_READBACK_SHA"
printf 'Verified %s bytes: %s\n' "$OC_IMAGE_BYTES" "$OC_READBACK_SHA"
```

Read-back covers the entire image, including sparse-file holes as zeroes.
After verification, remove the unmounted card from the host and insert it
in the OrangeCrab's onboard microSD socket.

## 10. Grant console access and load the FPGA over JTAG

For serial access, instantiate the rule for your local login account:

```bash
sed "s/@USER@/$(id -un)/g" "$OC_SUPPORT/orangecrab-usb.rules.in" | \
    sudo tee /etc/udev/rules.d/99-orangecrab-local.rules >/dev/null
sudo udevadm control --reload-rules
```

The rule applies on the next USB enumeration. The running system was loaded
through an external **FT232H (0403:6014), channel 0**, using JTAG at 5 MHz.
Connect 3.3 V-compatible JTAG signals and a common ground:

| FT232H | Board JTAG signal |
| --- | --- |
| AD0 | TCK |
| AD1 | TDI |
| AD2 | TDO |
| AD3 | TMS |
| GND | GND |

Power the OrangeCrab through USB. Use board signal labels/schematic for the
actual pad/header locations. The matching OpenOCD layout is supplied in
[`ft232h.cfg`](prog/orangecrab/ft232h.cfg).

```bash
sudo openocd -f "$OC_SUPPORT/ft232h.cfg" \
    -c "init; svf {$OC_GATEWARE/gsd_orangecrab.svf} quiet; shutdown"
```

Require ECP5-85F JTAG ID **0x41113043** and a successful SVF exit with no
errors. This loads **SRAM**, matching the verified procedure; it does not
make a new persistent flash image. A cold power cycle restores whatever
was already in flash. Warm `reboot` retains the loaded FPGA configuration.
DFU/flash installation is a separate procedure and was not part of the
final kernel-fix validation.

## 11. Boot and confirm the reproduced system

Use the stable serial identity; ttyACM numbering can change after JTAG:

```bash
ls -l /dev/serial/by-id/usb-GsD_OrangeCrab_CDC-if00
minicom -D /dev/serial/by-id/usb-GsD_OrangeCrab_CDC-if00 -b 115200
```

Use **one** reader: close other minicom/litex_term/Python readers. If locked,
inspect `fuser -v DEVICE` and `/run/lock/LCK..ttyACM*`; remove a stale lock
only after confirming its recorded process is gone. Disable terminal
hardware/software flow control if the client enables either.

Expected boot sequence:

1. RV64 VexiiRiscv BIOS at 40 MHz; DDR leveling and the 2 MiB memtest pass.
2. BIOS reads `boot.json`, Image, DTB and OpenSBI from FAT.
3. OpenSBI enters Linux at `0x41000000` with FDT at `0x46000000`.
4. Linux exposes physical memory only through `0x47ffffff`, detects both SD
   partitions, mounts ext4 root, and starts Debian 13.
5. `orangecrab login:` appears on `ttyLXU0`. Log in using the password set
   offline. No password-change prompt should be forced.

The 40 MHz CPU takes minutes to start the full userspace. The longer systemd
timeouts are intentional. Once logged in:

```sh
id
uname -a
head -n 3 /proc/meminfo
systemctl is-system-running --wait
systemctl --failed --no-pager
dmesg | grep -E 'BUG:|Oops:|soft lockup|self-detected stall|Kernel panic'
```

The tested image reports kernel `6.1.0-rc2-orangecrab-uartfix2+`,
`MemTotal: 92440 kB`, systemd **running**, and **zero failed units**. The
usable memory total is lower than 128 MiB because of the first 16 MiB below
Linux's load address plus kernel reservations. The final grep should find
no fault markers. An older archived BIOS can still print 512 MiB; that
number is its configured aperture, not a capacity measurement.

Finish with `sync` before shutting down/rebooting. An unexpected root
password reset or startup failure is not a reason to write the card again:
first check the DTB, rootfs overlay, console ownership, and boot log.

## 12. Validation scope and retained evidence

The final SD system passed normal boot/root login, 1000 actual UART
last-close/reopen cycles in 18.89 s, and a deliberate **35-second closure of
the host serial descriptor** during TTY and printk output. All 45 CPU
heartbeats continued, maximum gap 1.705 s; printk completed; the kernel log
had no fault markers. systemd finished with zero failed units.

The reader-closure test observed 16379 of 16384 transmitted payload bytes;
it establishes CPU progress under backpressure, **not lossless USB data
across closing/reopening the host port**. Kernel console characters may be
dropped when no reader drains the FIFO; full printk records remain in the
kernel ring. Ordinary TTY data is queued rather than busy-waited under the
IRQ-disabled port lock.

Evidence and optional regression scripts are in
[`kernel-timer-fix`](../../codex/reports/orangecrab-debian/kernel-timer-fix/README.md).
The PID 1 lifecycle script is for a dedicated recovery boot, not a command
to run in an ordinary login shell. Its use is unnecessary for routine image
preparation. A full destructive 128 MiB RAM test and a newly routed current
128 MiB gateware image were not part of that final validation.

The old release archive/raw image has not been silently rewritten. This
guide's kernel, corrected DTB, and rootfs configuration must be applied to
it to reproduce the running system. Package timestamps, machine-id,
password salt, journals, tool versions, and new routes mean a fresh build
is not promised to have identical whole-disk or gateware hashes.

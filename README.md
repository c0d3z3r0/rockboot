# RockBoot

RockBoot is a kexec based bootloader for rk3188 boards intended to provide a simple way for replacing
kernels without having to flash them to nand or write them to sd cards by hand. It is used by
[rock-update](https://github.com/c0d3z3r0/rock-update) and has been tested for Radxa Rock Pro but should
work with any rk3188 based board as long as you have a working kernel config (see kernel build below).


# How does it work?

RockBoot exists of X parts:
- u-boot bootloader for rk3188 
- a mainline linux kernel with kexec support
- an initramfs image with busybox and kexec-tools

RK3188 starts u-boot from your sd card which just starts the kexec kernel that boots into the initramfs.
The init script reads your kernel, devicetree blob (dtb) and config.txt from the first (FAT32) partition
of your sd card and calls kexec to load them into RAM. Then it executes kexec again to directly boot into
the new kernel. That's it!


# Build RockBoot

Rockboot is a full open source bootloader (except the RockChip DDR binary blob for rk3188)  but you don't have to
build RockBoot by yourself. This git repository provides all binary files needed to get your rk3188
board up fast. Just skip the build part and continue at *Installation*.

## Build the Toolchain

For building rockboot you need an armv7 toolchain. You can compile one yourself
or use the linaro toolchain. Look at [https://releases.linaro.org/](https://releases.linaro.org/)
for `arm-linux-gnueabihf` or at [https://www.linaro.org/downloads/](https://www.linaro.org/downloads/)
for `Cortex A9 little-endian toolchain`.

~~~bash
wget https://releases.linaro.org/15.05/components/toolchain/binaries/arm-linux-gnueabihf/gcc-linaro-4.9-2015.05-x86_64_arm-linux-gnueabihf.tar.xz
tar -xaf gcc-linaro-4.9-2015.05-x86_64_arm-linux-gnueabihf.tar.xz

export PATH="`pwd`/gcc-linaro-4.9-2015.05-x86_64_arm-linux-gnueabihf/bin/:${PATH}"
export ARCH=arm
export CROSS_COMPILE=arm-linux-gnueabihf-
~~~

## Build the dependencies, busybox and kexec

### Dependencies: mkbootimg and rkcrc

~~~bash
git clone https://github.com/c0d3z3r0/rockchip-mkbootimg.git
cd rockchip-mkbootimg; make; cd ..

git clone https://github.com/naobsd/rkutils.git
cd rkutils; gcc rkcrc.c -o rkcrc; cd ..
~~~

### Busybox

~~~bash
wget http://busybox.net/downloads/busybox-1.23.2.tar.bz2
tar -xaf busybox-1.23.2.tar.bz2
cd busybox-1.23.2/

make defconfig
sed -i'' 's/.*CONFIG_STATIC.*/CONFIG_STATIC=y/' .config
sed -i'' 's/.*CONFIG_INSTALL_NO_USR.*/CONFIG_INSTALL_NO_USR=y/' .config
make

cd ..
~~~

### Kexec Tools

~~~bash
wget https://www.kernel.org/pub/linux/utils/kernel/kexec/kexec-tools-2.0.10.tar.xz
tar -xaf kexec-tools-2.0.10.tar.xz
cd kexec-tools-2.0.10/

LDFLAGS=-static ./configure --host=arm-linux-gnueabihf
make

cd ..
~~~

## Build the initramfs

~~~bash
mkdir -p initramfs/{bin,sbin,dev,mnt,proc,sys}
cd initramfs/
mknod dev/null c 1 3
mknod dev/console c 5 1
cp ../kexec-tools-2.0.10/build/sbin/* sbin/
cp ../busybox-1.23.2/busybox bin/
cp ../init.sh init
chmod +x init
find . | cpio -H newc -o > ../initramfs.cpio

cd ..
~~~

## Build the kexec kernel

We need to build a kernel with minimal support for your board. For Radxa Rock Pro you can just use the `kexec-linux.config`. Feel free to modify it to your needs with `make menuconfig` if you have another board.

~~~bash
git clone -b workbench/next https://github.com/c0d3z3r0/linux-rockchip.git
cd linux-rockchip/
make distclean
cp ../kexec-linux.config .config

make silentoldconfig
#make menuconfig  # only if needed
make -j5 zImage
make -j5 rk3188-radxarock.dtb
cat arch/arm/boot/{zImage,dts/rk3188-radxarock.dtb} >../radxa-kernel.img

cd ..
~~~

## Build the boot image

~~~bash
./rockchip-mkbootimg/mkbootimg --kernel radxa-kernel.img --ramdisk initramfs.cpio -o boot.img
~~~

## Build u-boot for rk3188

~~~bash
git clone https://github.com/c0d3z3r0/u-boot-rockchip.git
cd u-boot-rockchip/

make rk30xx
./pack-sd.sh

cd ..
~~~

### The rockchip / u-boot parameter file

This file contains the cmdline for the u-boot bootloader. *Do not* change it. You
can specify the cmdline for *your* kernel in `config.txt` later.

~~~bash
./rkutils/rkcrc -p parameter.txt build/parameter.img
~~~


## RockBoot Installation

### Create partition table and write rockboot to your sd card

We need to leave 65536 sectors (32MB) free for the bootloader. Next we create a
100MB boot partition for the config and the kernel.
<br>
After the boot partition you can create as many partitions as you like.

~~~bash
export DEV=/dev/sdX   # your sd card

sudo dd if=/dev/zero of=${DEV} bs=32M count=1

sudo fdisk ${DEV}  << EOF
o
n
p
1
65536
+100M
t
e
w
EOF
~~~

### Write the images onto sd card

Adapt the paths for the `.img` files.

~~~bash
sudo dd if=u-boot-sd.img of=${DEV} conv=sync seek=64 
sudo dd if=parameter.img of=${DEV} conv=sync seek=$((0x2000))
sudo dd if=boot.img of=${DEV} conv=sync seek=$((0x2000+0x2000))

sudo mkfs.msdos ${DEV}1
~~~

### RockBoot Configuration

The boot partition contains your kernel, the devicetree blob built with the kernel and a config file `config.txt`.
In the config file you need to specify which kernel you want to boot with which dtb and the cmdline.

So just copy your kernel and dtb (*not* kexec-kernel created above) to `/dev/sdX1` and create a `config.txt`.

Example (the default used by rock-update):

~~~
kernel=zImage
dtb=rk3188-radxarock.dtb
cmdline="console=tty0 console=ttyS2,115200 root=/dev/mmcblk0p2 rootfstype=ext4 rw clocksource=jiffies"
~~~

# License

Copyright (C) 2015 Michael Niewöhner

This is open source software, licensed under the MIT License. See the file LICENSE for details.

This license does not apply to the foreign software included in binaries of or used in this project
but does apply to rockboot itself containing the init script and the
surrounding work. For licenses of the software included in rockboot consult
the LICENSES directory.

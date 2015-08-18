#!/bin/busybox ash

/bin/busybox --install -s /bin
mount -t proc proc /proc
mount -t sysfs sysfs /sys
echo 0 > /proc/sys/kernel/printk
mdev -s

echo
echo \########################
echo \# Welcome to rockboot! \#
echo \########################
echo

mount /dev/mmcblk0p1 /mnt || (
  echo Error: Mounting boot partition failed!
  exec ash
)

if [ -f /mnt/config.txt ]; then
  while read -r var
  do
    eval $(echo export $var)
  done </mnt/config.txt
else
  echo Error: No config file found!
  exec ash
fi

read -t 2 -p "Press any key to open a shell."
if [ $? -eq 0 ]; then
  exec ash
else
  echo -e \\nBooting ...
  kexec -l --command-line="${cmdline}" --dtb=/mnt/${dtb} $([ "${initrd}" ] && echo --initrd=/mnt/${initrd}) /mnt/${kernel}
  kexec -e
fi

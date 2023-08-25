if [ "${var.crdb_resize_homelv}" = "yes" ] 
then 
  echo "Attempting to resize /dev/mapper/rootvg-homelv with any space available on the physical volume"
  echo "Resize the Linux LVM"
  growpart /dev/sda 2
  echo "Capture the free space on the device in GB.  The awk command is capturing only the integer portion of the output"
  ds=`pvs -o name,free --units g --noheadings | awk '{printf "%d\n", \$2}'`
  echo "Resizing the logical volume by \${ds}"
  lvresize -r -L +\${ds}G /dev/mapper/rootvg-homelv
fi


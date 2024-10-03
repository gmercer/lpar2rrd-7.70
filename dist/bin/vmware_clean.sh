#!/bin/ksh
#
# . /home/lpar2rrd/lpar2rrd/etc/lpar2rrd.cfg; sh ./bin/vmware_clean.sh
#
# removes from dir data/ totally all vmware related files and dirs
#
# Load LPAR2RRD configuration
if [ -f etc/lpar2rrd.cfg ]; then
  . etc/lpar2rrd.cfg
else
  if [ -f `dirname $0`/etc/lpar2rrd.cfg ]; then
    . `dirname $0`/etc/lpar2rrd.cfg
  else
    if [ -f `dirname $0`/../etc/lpar2rrd.cfg ]; then
      . `dirname $0`/../etc/lpar2rrd.cfg
    fi
  fi
fi

if [ `echo $INPUTDIR|egrep "bin$"|wc -l` -gt 0 ]; then
  INPUTDIR=`dirname $INPUTDIR`
fi

if [ ! -d "$INPUTDIR" ]; then
  echo "Does not exist \$INPUTDIR; have you loaded environment properly? . /home/lpar2rrd/lpar2rrd/etc/lpar2rrd.cfg"
  exit 1
fi

echo "This data (directories) contain VMware related data and will be deleted:"
last_path=""
for vmware_file in `ls $INPUTDIR/data/*/*/vmware.txt 2>/dev/null `
do
  vmware_dir1=`dirname $vmware_file`
  vmware_dir=`dirname $vmware_dir1`
  if [[ ! "$vmware_dir" == *. && ! "$vmware_dir" == *data && ! "$vmware_dir" == "$last_path" ]]; then
    echo "  $vmware_dir"| sed 's/bin\/\.\.\///'
    last_path="$vmware_dir"
  fi
done
if [ -d "$INPUTDIR/data/vmware_VMs" ]; then
  echo "  $INPUTDIR/data/vmware_VMs"| sed 's/bin\/\.\.\///'
fi



echo ""
echo "Do you want to continue with removing of them?"
echo "[Y/N]"
read yes

if [ ! "$yes" = "Y" -a ! "$yes" = "y" ]; then
  exit 0
fi


last_path=""
for vmware_file in `ls $INPUTDIR/data/*/*/vmware.txt 2>/dev/null `
do
  vmware_dir1=`dirname $vmware_file`
  vmware_dir=`dirname $vmware_dir1`
  if [[ ! "$vmware_dir" == *. && ! "$vmware_dir" == *data && ! "$vmware_dir" == "$last_path" ]] ; then
    echo "  removing:  $vmware_dir"| sed 's/bin\/\.\.\///'
    rm -rf "$vmware_dir"
    last_path="$vmware_dir"
  fi
done
if [ -d "$INPUTDIR/data/vmware_VMs" ]; then
  echo "  removing:  $INPUTDIR/data/vmware_VMs"| sed 's/bin\/\.\.\///'
  rm -rf "$INPUTDIR/data/vmware_VMs"
fi
rm -f $INPUTDIR/tmp/menu_vmware.txt
rm -f $INPUTDIR/tmp/menu.txt

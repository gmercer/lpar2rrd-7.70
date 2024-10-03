#!/bin/ksh

PATH=$PATH:/usr/bin:/bin:/usr/local/bin:/opt/freeware/bin
export PATH

LANG=C
export LANG

# No no, it affects date format coming from the HMC in some rare cases, no idea why ....
#if [ `locale 2>/dev/null| grep  LC_NUMERIC| egrep "^C$|US" | wc -l` -eq 0 ]; then
#  # locale LC_NUMERIC might cause a problem in decimal separator, setting to "C"
#  LC_NUMERIC=C
#  export LC_NUMERIC
#fi


# it is necessary as files need to be readable also for WEB server user
umask 022

# Load LPAR2RRD configuration
. `dirname $0`/etc/lpar2rrd.cfg

# switch off RRDcached as default (you migtt still allow it in etc/.magic)
LPAR2RRD_CACHE_NO=1
export LPAR2RRD_CACHE_NO

# Load "magic" setup
if [ -f `dirname $0`/etc/.magic ]; then
  . `dirname $0`/etc/.magic
  if [ ! "$VM_IMAGE"x = "x" ]; then
    if [ $VM_IMAGE -eq 1 ]; then
      echo "Image environment is set"
    fi
  fi
fi

if [ "$INPUTDIR" = "." ]; then
   INPUTDIR=`pwd`
   export INPUTDIR
fi

if [ -f $INPUTDIR/etc/version.txt ]; then
  # actually installed version include patch level (in $version is not patch level)
  version_patch=`cat $INPUTDIR/etc/version.txt|tail -1`
  export version_patch
fi

TMPDIR=$INPUTDIR/tmp
export TMPDIR

ERRLOG="$INPUTDIR/logs/error.log-vmware"
export ERRLOG

# ./load.sh html --> it runs only web creation code
HTML=0
if [ ! "$1"x = "x" -a "$1" = "html" ]; then
  HTML=1
  touch $TMPDIR/$version-vmware # force to run html part
fi

# ./load.sh custom --> it runs custom group refresh
CUSTOM_GRP=0
if [ ! "$1"x = "x" -a "$1" = "custom" ]; then
  exit # custom group is solved in main load.sh
  #CUSTOM_GRP=1
  #touch $TMPDIR/$version-vmware # force to run html part
  #rm $TMPDIR/custom-group-*  # delete all groups and let them recreate, it delete already unconfigured ones
fi

if [ $HTML -eq 0 ]; then # -a $CUSTOM_GRP -eq 0 -a -f "$TMPDIR_LPAR/$prg_name.pid" ]; then
  prg_name=`basename $0`
  if [ -f "$TMPDIR/$prg_name.pid" ]; then
    PID=`cat "$TMPDIR/$prg_name.pid"|sed 's/ //g'`
    if [ ! "$PID"x = "x" ]; then
      ps -ef|grep "$prg_name"|egrep -v "vi |vim "|awk '{print $2}'|egrep "^$PID$" >/dev/null
      if [ $? -eq 0 ]; then
        d=`date`
        echo "$d: There is already running another copy of $prg_name, exiting ..."
        echo "$d: There is already running another copy of $prg_name, exiting ..." >> $ERRLOG
        exit 1
      fi
    fi
  fi
fi

# ok, there is no other copy of $prg_name
echo "$$" > "$TMPDIR/$prg_name.pid"

cd $INPUTDIR

UPGRADE=0
if [ ! -f $TMPDIR/$version ]; then
  sleep 15 # must be different sleep than in load.sh as this do the same thing
  UPGRADE=1

  #  refresh WEB files immediately after the upgrade to do not have to wait for the end of upgrade
  echo "Copy GUI files : $WEBDIR"

  cp $INPUTDIR/html/*html $WEBDIR/
  cp $INPUTDIR/html/*ico $WEBDIR/
  cp $INPUTDIR/html/*png $WEBDIR/

  if [ ! -L "$WEBDIR/jquery" ]; then
    # skip that in case of internal development
    cd $INPUTDIR/html
    tar cf - jquery | (cd $WEBDIR ; tar xf - )
    cd - >/dev/null
  fi

  if [ ! -L "$WEBDIR/css" ]; then
    # skip that in case of internal development
    cd $INPUTDIR/html
    tar cf - css | (cd $WEBDIR ; tar xf - )
    cd - >/dev/null
  fi

fi
export UPGRADE  # for lpar2rrd.pl and trends especially

if [ -f $ERRLOG ]; then
  ERR_START=`wc -l $ERRLOG |awk '{print $1}'`
else
  ERR_START=0
fi

# Checks
if [ ! -f "$RRDTOOL" ]; then
  echo "Set correct path to RRDTOOL binary in lpar2rrd.cfg, it does not exist here: $RRDTOOL"
  echo "Set correct path to RRDTOOL binary in lpar2rrd.cfg, it does not exist here: $RRDTOOL" >> $ERRLOG
  exit 0
fi
ok=0
for i in `echo "$PERL5LIB"|sed 's/:/ /g'`
do
  if [ -f "$i/RRDp.pm" ]; then
    ok=1
  fi
done
if [ $ok -eq 0 ]; then
  echo "Set correct path to RRDp.pm Perl module in lpar2rrd.cfg"
  echo "it does not exist here : $PERL5LIB"
  echo ""
  echo "1. Assure it is installed rrdtool-perl module"
  echo "2. try to find it "
  echo "   find /usr -name RRDp.pm"
  echo "   find /opt -name RRDp.pm"
  echo "3. place path (directory) to etc/lpar2rrd.cfg, parametr PERL5LIB"

  echo "Set correct path to RRDp.pm Perl module in lpar2rrd.cfg" >> $ERRLOG
  echo "it does not exist here : $PERL5LIB" >> $ERRLOG
  echo "1. Assure it is installed rrdtool-perl module" >> $ERRLOG
  echo "2. try to find it " >> $ERRLOG
  echo "   find /usr -name RRDp.pm" >> $ERRLOG
  echo "   find /opt -name RRDp.pm" >> $ERRLOG
  echo "3. place path (directory) to etc/lpar2rrd.cfg, parametr PERL5LIB" >> $ERRLOG

  exit 1
fi
if [ ! -f "$PERL" ]; then
  echo "Set correct path to Perl binary in lpar2rrd.cfg, it does not exist here: $PERL"
  exit 0
fi
if [ x"$RRDHEIGHT" = "x" ]; then
  echo "RRDHEIGHT does not seem to be set up, correct it in lpar2rrd.cfg"
  exit 0
fi
if [ x"$RRDWIDTH" = "x" ]; then
  echo "RRDWIDTH does not seem to be set up, correct it in lpar2rrd.cfg"
  exit 0
fi
if [ x"$SAMPLE_RATE" = "x" ]; then
  echo "SAMPLE_RATE does not seem to be set up, correct it in lpar2rrd.cfg"
  exit 0
fi
if [ x"$DEBUG" = "x" ]; then
  echo "DEBUG does not seem to be set up, correct it in lpar2rrd.cfg"
  exit 0
fi
if [ ! -d "$WEBDIR" ]; then
  echo "Set correct path to WEBDIR in lpar2rrd.cfg, it does not exist here: $WEBDIR"
  exit 0
fi

#
# Load data from VMware
#

# you can set VCENTER_PARALLEL_RUN in etc/.magic to persist upgrades
# all data from all vCenters must be captured within an hour (real time data)
# paralelize it here (default 100 vcenters)
if [ "$VCENTER_PARALLEL_RUN"x = "x" ]; then
  VCENTER_PARALLEL_RUN=100 # when > 1 then vcenters are processed concurrently
fi

#POWER=0
#if [ ! "$1"x = "x" ]; then
#  if [ "$1" = "power" ]; then
#    POWER=1
#  fi
#fi

mv $INPUTDIR/logs/load_vmware.log $INPUTDIR/logs/load_vmware.prev 2>/dev/null
mv $INPUTDIR/logs/load_vmware_rrd.log $INPUTDIR/logs/load_vmware_rrd.prev 2>/dev/null

if [ ! "$VI_CREDSTORE"x = "x" ]; then  # -a $POWER -eq 0 ]; then
  # it must be separated from above
  if [ -f $VI_CREDSTORE ]; then
    if [ `wc -l $VI_CREDSTORE 2>/dev/null | awk '{print $1}'` -gt 0 ]; then
      if [ -f "$INPUTDIR/logs/counter-info.txt" ]; then
		if ! [ $HTML -eq 1 -o $CUSTOM_GRP -eq 1 ]; then # let run only web part or custom one
          `mv "$INPUTDIR/logs/counter-info.txt" "$INPUTDIR/logs/counter-info.back"`
		fi
      fi
      for HMC in `$PERL -MHostCfg -e 'print HostCfg::getHostConnections("VMware")'`
      do
        export HMC
        if [ $HTML -eq 1 -o $CUSTOM_GRP -eq 1 ]; then continue; fi # let run only web part or custom one
        if [ ! -f "$INPUTDIR/vmware-lib/VMware/VIMRuntime.pm" ]; then
          echo "VMware-vSphere-Perl-SDK is not installed, refer to VMware installation docu on: http://www.lpar2rrd.com/install.htm"
          echo "Exiting VMware load ..."
          break
        fi
        $BINDIR/vmware_run.sh &
      done
    else
      echo "VMware         : not identified, no credentials" >> $INPUTDIR/logs/load_vmware.log
      echo "VMware         : not identified, no credentials"
    fi
  else
    echo "VMware         : not identified, no credentials" >> $INPUTDIR/logs/load_vmware.log
    echo "VMware         : not identified, no credentials"
  fi
else
  echo "VMware         : not identified, no credentials" >> $INPUTDIR/logs/load_vmware.log
  echo "VMware         : not identified, no credentials"
fi

#
# wait until all HMC and vcenter jobs finish
#

echo "jobs -l vmware : " # just print jobs status
jobs -l
jobs -l >> $INPUTDIR/logs/load_vmware.log

for pid in `jobs -l |sed -e 's/+//g' -e 's/-//g'|awk '{print $2}'|egrep -iv "stop|daemon|rrdtool|vi |vim |load.sh"`
do
  if [ -f "$TMPDIR/lpar2rrd-daemon.pid" -a $pid -eq `cat $TMPDIR/lpar2rrd-daemon.pid` ]; then
    echo "Skipping daemon: $pid" >> $INPUTDIR/logs/load_vmware.log
    continue
  fi
  echo "Waiting for VMware: $pid" >> $INPUTDIR/logs/load_vmware.log
  wait $pid >> $INPUTDIR/logs/load_vmware.log
done

# run it only when vmware is presented
#if [ `wc -l $VI_CREDSTORE 2>/dev/null | awk '{print $1}'` -gt 4 ]; then
  $BINDIR/vmware_push_perf_data_to_rrd.sh 2>&1 | tee -a $INPUTDIR/logs/load_vmware.log &
#fi

#
# filter file data/vmware_VMs/vm_uuid_name.txt, where can be appended renamed VMs
#
if [ -f "$INPUTDIR/data/vmware_VMs/vm_uuid_name.txt" ]; then
  $PERL -w $BINDIR/reduce_vm_names.pl 2>>$ERRLOG | tee -a $INPUTDIR/logs/load_vmware.log
fi

#
#
# Install/Update web frontend
#

$BINDIR/install-html.sh vmware | tee -a $INPUTDIR/logs/load_vmware.log
ret=$?
if [ ! $ret -eq 0 ]; then
  echo "`date` : An error occured in install-html.sh, return code: $ret" >> $ERRLOG
fi


#
# Heatmap ( must be behind install-html.sh as it relys on actual menu.txt)
#
if [ $HTML -eq 0 -a $CUSTOM_GRP -eq 0 ]; then
  nohup $PERL -w $BINDIR/heatmap.pl vmware 2>>$ERRLOG | tee -a $INPUTDIR/logs/load_vmware.log &
fi

# XorMon load data to SQLite
if [ ! "$XORMON"x = "x" ]; then
  if [ "$XORMON" != "0" ]; then
    $PERL -w $BINDIR/vmware_menu2db.pl 2>>$ERRLOG 
  fi
fi

#
# Error handling
#

if [ -f $ERRLOG ]; then
  ERR_END=`wc -l $ERRLOG |awk '{print $1}'`
else
  ERR_END=0
fi
ERR_TOT=`expr $ERR_END - $ERR_START`
if [ $ERR_TOT -gt 0 ]; then
  echo "An error occured in lpar2rrd, check $ERRLOG and output of load.sh"
  echo ""
  echo "$ tail -$ERR_TOT $ERRLOG"
  echo ""
  tail -$ERR_TOT $ERRLOG
  #date >> $ERRLOG
fi

if [ -d "$INPUTDIR/logs" ]; then
  if [ -f "$INPUTDIR/load.out" ]; then
    cp -p "$INPUTDIR/load.out" "$INPUTDIR/logs"
    chmod 755 "$INPUTDIR/logs/load.out"
  fi
fi

edate=`date`
echo "date end all VM: $edate"
exit 0

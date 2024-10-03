#!/bin/ksh

PATH=$PATH:/usr/bin:/bin:/usr/local/bin:/opt/freeware/bin
export PATH

LANG=C
export LANG

# it is necessary as files need to be readable also for WEB server user
umask 022

# Load LPAR2RRD configuration
. `dirname $0`/etc/lpar2rrd.cfg

#Load HYPER-V configuration
# . `dirname $0`/etc/web_config/hyperv.cfg

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

ERRLOG=$INPUTDIR/logs/error.log-hyperv


if [ -f $INPUTDIR/etc/version.txt ]; then
  # actually installed version include patch level (in $version is not patch level)
  version_patch=`cat $INPUTDIR/etc/version.txt|tail -1`
  export version_patch
fi

#
# when WEBDIR_PUBLIC is defined then it creates a new (second) web root for public users (on demand extention for a customer)
# (without entitlement area in lpar graphs)
# run it from cron as follows
# 30 * * * * export WEBDIR_PUBLIC=/home/lpar2rrd/lpar2rrd/www_public; /home/lpar2rrd/lpar2rrd/load.sh > /home/lpar2rrd/lpar2rrd/load.out 2>&1 
# etc/.magic setup (to say the GUI where is the right menu.txt file)
# WWW_ATERNATE_URL="__part_of_web_path__"
# WWW_ATERNATE_TMP="tmp_public"
#

TMPDIR_LPAR=$INPUTDIR/tmp
if [ ! "$WEBDIR_PUBLIC"x = "x" ]; then
  WEBDIR=$WEBDIR_PUBLIC
  TMPDIR_LPAR=$WEBDIR-tmp # set up new separate $TMPDIR_LPAR
  echo "Creating public web without entitlements here: $WEBDIR_PUBLIC"
  if [ ! -d "$WEBDIR_PUBLIC" ]; then
    mkdir $WEBDIR_PUBLIC 
  fi
  if [ ! -d "$TMPDIR_LPAR" ]; then
    mkdir $TMPDIR_LPAR
  fi
fi
export WEBDIR TMPDIR_LPAR


prg_name=`basename $0`
if [ -f "$TMPDIR_LPAR/$prg_name.pid" ]; then
  PID=`cat "$TMPDIR_LPAR/$prg_name.pid"|sed 's/ //g'`
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
# ok, there is no other copy of $prg_name
echo "$$" > "$TMPDIR_LPAR/$prg_name.pid"


HOSTNAME=`uname -n`
export HOSTNAME

ID=`( lsattr -El sys0 -a systemid 2>/dev/null || hostid ) | sed 's/^.*,//' | awk '{print $1}'`
UN=`uname -a`
UNAME=`echo "$UN $ID"`
export UNAME

UPGRADE=0
if [ ! -f $TMPDIR_LPAR/$version ]; then
  if [ ! "$DEBUG"x = "x" ]; then 
    if [ $DEBUG -gt 0 ]; then 
      echo ""
      echo "Looks like there has been an upgrade to $version or new installation"
      echo ""
      sleep 2
    fi
  fi
  UPGRADE=1

  #  refresh WEB files immediately after the upgrade to do not have to wait for the end of upgrade
  echo "Copy GUI files : $WEBDIR"

  cp $INPUTDIR/html/*html $WEBDIR/
  cp $INPUTDIR/html/*ico $WEBDIR/
  cp $INPUTDIR/html/*png $WEBDIR/

  cd $INPUTDIR/html
  tar cf - jquery | (cd $WEBDIR ; tar xf - )
  cd - >/dev/null

  cd $INPUTDIR/html
  tar cf - css | (cd $WEBDIR ; tar xf - )
  cd - >/dev/null

fi
export UPGRADE  # for lpar2rrd.pl and trends especially


cd $INPUTDIR

# Check if it runs under the right user
install_user=`ls -lX $BINDIR/lpar2rrd.pl|awk '{print $3}'` # must be X to do not cut user name to 8 chars
running_user=`id |awk -F\( '{print $2}'|awk -F\) '{print $1}'`
if [ ! "$install_user" = "$running_user" ]; then
  echo "You probably trying to run it under wrong user" 
  echo "LPAR2RRD files are owned by : $install_user"
  echo "You are : $running_user"
  echo "LPAR2RRD should run only under user which owns installed package"
  echo "Do you want to really continue? [n]:"
  read answer
  if [ "$answer"x = "x" -o "$answer" = "n" -o "$answer" = "N" ]; then
    exit
  fi
fi

if [ -f $ERRLOG ]; then
  ERR_START=`wc -l $ERRLOG |awk '{print $1}'`
else
  ERR_START=0
fi 

# Checks
if [ ! -f "$RRDTOOL" ]; then
  echo "Set correct path to RRDTOOL binary in lpar2rrd.cfg, it does not exist here: $RRDTOOL"
  echo "Set correct path to RRDTOOL binary in lpar2rrd.cfg, it does not exist here: $RRDTOOL"  >> $ERRLOG
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
  exit 1
fi 
if [ x"$RRDHEIGHT" = "x" ]; then
  echo "RRDHEIGHT does not seem to be set up, correct it in lpar2rrd.cfg"
  exit 1
fi
if [ x"$RRDWIDTH" = "x" ]; then
  echo "RRDWIDTH does not seem to be set up, correct it in lpar2rrd.cfg"
  exit 1
fi
if [ x"$SAMPLE_RATE" = "x" ]; then
  echo "SAMPLE_RATE does not seem to be set up, correct it in lpar2rrd.cfg"
  exit 1
fi
if [ x"$HMC_USER" = "x" ]; then
  echo "HMC_USER does not seem to be set up, correct it in lpar2rrd.cfg"
  exit 1
fi
if [ x"$DEBUG" = "x" ]; then
  echo "DEBUG does not seem to be set up, correct it in lpar2rrd.cfg"
  exit 0
fi
if [ ! -d "$WEBDIR" ]; then
  echo "Set correct path to WEBDIR in lpar2rrd.cfg, it does not exist here: $WEBDIR"
  exit 0
fi 

# subroutines for time trap
  timeout=7200 # 2 hours
  cleanup()
  {
    trap - ALRM               #reset handler to default
    kill -ALRM $pid_wait_time 2>/dev/null #stop timer subshell if running
    kill $! 2>/dev/null    #kill last job
  }

  wait_time()
  {
    trap "cleanup" ALRM
    sleep $timeout& wait
    slp_pid=$!
    kill -ALRM $$
    kill $slp_pid # kill sleep running on the backend
  }

#
# Store data from HyperV to rrd files
#

# testing for hyperv
echo "hyperv start   : push data to rrd "`date`
if [ ! -d "$TMPDIR_LPAR/HYPERV" ]; then
  echo "No HYPERV perf data directory found, exiting"
  exit
fi

# start parsing windows perf files 
   echo "HYPDIR start   :  "`date`
   wait_time $timeout& pid_wait_time=$!         #start the timeout
   trap "cleanup" ALRM          # cleanup after timeout
   $PERL -w $BINDIR/hyp2rrd.pl 2>>$ERRLOG & wait $!           # start the job wait for it and save its return value
   status=$?
   echo "HyperV finish  : status $status "`date`
   kill -ALRM $pid_wait_time    # send ALRM signal to watchit
   wait $pid_wait_time          # wait for watchit to finish cleanup
 
# start JiDut jun Storage spaces
   echo "s2d start      :  "`date`
   wait_time $timeout& pid_wait_time=$!         #start the timeout
   trap "cleanup" ALRM          # cleanup after timeout
   $PERL -w $BINDIR/s2d.pl 2>>$ERRLOG & wait $!           # start the job wait for it and save its return value
   status=$?
   echo "s2d finish     : status $status "`date`
   kill -ALRM $pid_wait_time    # send ALRM signal to watchit
   wait $pid_wait_time          # wait for watchit to finish cleanup

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
echo "date end all   : $edate"
exit 0

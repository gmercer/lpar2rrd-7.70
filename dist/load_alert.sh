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

# SNMP TRAP workaround
SNMP_PERSISTENT_DIR=/var/tmp
export SNMP_PERSISTENT_DIR



# it is necessary as files need to be readable also for WEB server user
umask 022

# Load LPAR2RRD configuration
. `dirname $0`/etc/lpar2rrd.cfg

# Load "magic" setup
if [ -f `dirname $0`/etc/.magic ]; then
  . `dirname $0`/etc/.magic
fi

ALERT_TEST=0
if [ ! "$1"x = "x" -a "$1" = "test" ]; then
  ALERT_TEST=1
  echo "testing mode   : issue all alarms to test notification"
fi
export ALERT_TEST

if [ "$INPUTDIR" = "." ]; then
   INPUTDIR=`pwd`
   export INPUTDIR
fi
TMPDIR=$INPUTDIR/tmp

prg_name=`basename $0`
if [ -f "$TMPDIR/$prg_name.pid" ]; then
  PID=`cat "$TMPDIR/$prg_name.pid"`
  if [ ! "$PID"x = "x" ]; then
    ps -ef|grep "$prg_name"|grep "$PID" >/dev/null
    if [ $? -eq 0 ]; then
      echo "There is already running another copy of $prg_name, exiting ..."
      d=`date`
      ps=`ps -ef|grep "$prg_name"|grep "$PID" >/dev/null`
      echo "$d: There is already running another copy of $prg_name, exiting ... \"$ps\"" >> $ERRLOG-alrt
      exit 1
    fi
  fi
fi
# ok, there is no other copy of $0
echo "$$" > "$TMPDIR/$prg_name.pid"


UPGRADE=0
if [ ! -f $TMPDIR/$version ]; then
  if [ $DEBUG -eq 1 ]; then echo "Looks like there was an upgrade"; fi
  UPGRADE=1
fi
export UPGRADE  # for lpar2rrd.pl and trends especially


cd $INPUTDIR

if [ -f "etc/web_config/alerting.cfg" ]; then
  ALERCFG="etc/web_config/alerting.cfg"
else
  ALERCFG="etc/alert.cfg"
fi
export ALERCFG

if [ ! -f $ALERCFG ]; then
    if [ $DEBUG -eq 1 ]; then echo "There is no $ALERCFG cfg file"; fi
    exit 0
fi


# Check if it runs under the right user
if [ `uname -s` = "SunOS" ]; then
  # Solaris does not have -X
  install_user=`ls -l $BINDIR/lpar2rrd.pl|awk '{print $3}'`  # must be X to do not cut user name to 8 chars
else
  install_user=`ls -lX $BINDIR/lpar2rrd.pl|awk '{print $3}'`  # must be X to do not cut user name to 8 chars
fi
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

ERRLOG=$ERRLOG-alrt
if [ -f $ERRLOG ]; then
  ERR_START=`wc -l $ERRLOG |awk '{print $1}'`
else
  ERR_START=0
fi 

# Checks
if [ ! -f "$RRDTOOL" ]; then
  echo "Set correct path to RRDTOOL binary in lpar2rrd.cfg, it does not exist here: $RRDTOOL"
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
  echo "Set correct path to RRDp.pm Perl module in lpar2rrd.cfg, it does not exist here : $PERL5LIB"
  exit 0
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
if [ x"$HMC_USER" = "x" ] && [ "$REST_API" = 0 ]; then
  echo "HMC_USER does not seem to be set up, correct it in lpar2rrd.cfg"
  exit 0
fi
if [ x"$HMC_LIST" = "x" ] && [ "$REST_API" = 0 ]; then
  echo "HMC_LIST does not seem to be set up, correct it in lpar2rrd.cfg"
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
if [ x"$MANAGED_SYSTEMS_EXCLUDE" = "x" ]; then
  MANAGED_SYSTEMS_EXCLUDE=""
  export MANAGED_SYSTEMS_EXCLUDE
fi 


#
# Load data from HMC(s) (if configured through SSH only, if Rest API, then just alert) and create graphs
#

$PERL -w $BINDIR/alrt.pl $TEST_ALERT 2>>$ERRLOG


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
  date >> $ERRLOG
fi

if [ -d "$INPUTDIR/logs" ]; then
  if [ -f "$INPUTDIR/load_alert.out" ]; then
    cp -p "$INPUTDIR/load_alert.out" "$INPUTDIR/logs"
  fi
fi

exit 0

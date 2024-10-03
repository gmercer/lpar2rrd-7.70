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

if [ "$INPUTDIR" = "." ]; then
   INPUTDIR=`pwd`
   export INPUTDIR
fi
TMPDIR=$INPUTDIR/tmp


prg_name=`basename $0`
if [ -f "$TMPDIR/$prg_name.pid" ]; then
  PID=`cat "$TMPDIR/$prg_name.pid"|sed 's/ //g'`
  if [ ! "$PID"x = "x" ]; then
    ps -ef|grep "$prg_name"|egrep -v "vi |vim "|awk '{print $2}'|egrep "^$PID$" >/dev/null
    if [ $? -eq 0 ]; then
      echo "There is already running another copy of $prg_name, exiting ..."
      d=`date`
      echo "$d: There is already running another copy of $prg_name, exiting ..." >> $ERRLOG
      exit 1
    fi
  fi
fi
# ok, there is no other copy of $prg_name
echo "$$" > "$TMPDIR/$prg_name.pid"


cd $INPUTDIR
ERRLOG=$ERRLOG-hea

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
if [ x"$HMC_USER" = "x" ]; then
  echo "" > /dev/null
  #use from host config 23.11.18 insted of $hmc_user=ENV{HMC_USER} (HD)
  #echo "HMC_USER does not seem to be set up, correct it in lpar2rrd.cfg"
  #exit 0
fi

#if [ x"$HMC_LIST" = "x" ]; then
#  HMC_LIST=`$PERL $BINDIR/hmc_list.pl`
#  echo "load_hea.sh hmc_list: $HMC_LIST"
#  echo "HMC_LIST does not seem to be set up, correct it in lpar2rrd.cfg"
#  exit 0
#fi

#use HMC_LIST from GUI. Fix 21.11.19 HD
HMC_LIST=`$PERL $BINDIR/hmc_list.pl`

if [ x"$DEBUG" = "x" ]; then
  echo "DEBUG does not seem to be set up, correct it in lpar2rrd.cfg"
  exit 0
fi
if [ ! -d "$WEBDIR" ]; then
  echo "Set correct path to WEBDIR in lpar2rrd.cfg, it does not exist here: $WEBDIR"
  exit 0
fi 
if [ -f "$HMC_LIST" ]; then
  # HMC_LIST contains a name of file where HMC are listed
  HMC_LIST=`cat $HMC_LIST`
fi
if [ -f "$INPUTDIR/etc/$HMC_LIST" ]; then
  # HMC_LIST contains a name of file where HMC are listed
  HMC_LIST=`cat $INPUTDIR/etc/$HMC_LIST`
fi



#
# Load data from HMC(s) and create graphs
#

for HMC in $HMC_LIST
do
  export HMC
  export HMC_USER=`$PERL $INPUTDIR/bin/hmc_list.pl --username $i`
  $PERL -w $BINDIR/hea.pl 2>>$ERRLOG
  if [ ! $? -eq 0 ]; then
    echo "`date` : $HMC : An error occured in lpar2rrd.pl, check $ERRLOG and output of load.sh" >> $ERRLOG
  fi
done

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
  if [ -f "$INPUTDIR/load_hea.out" ]; then
    cp -p "$INPUTDIR/load_hea.out" "$INPUTDIR/logs"
  fi
fi

exit 0

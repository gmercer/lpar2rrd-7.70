#!/bin/ksh


PATH=$PATH:/usr/bin:/bin:/usr/local/bin:/opt/freeware/bin
export PATH

LANG=C
export LANG

# it is necessary as files need to be readable also for WEB server user
umask 022

#echo `perldoc -m LWP | head -n 3`

# Load LPAR2RRD configuration
. `dirname $0`/etc/lpar2rrd.cfg

#echo `perldoc -m LWP | head -n 3`
#exit 0

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
   BINDIR=$INPUTDIR/bin
   export BINDIR
fi

ERRLOG=$INPUTDIR/logs/error.log-db2

#prg_name=`basename $0`
#PID=`cat "$INPUTDIR/tmp/$prg_name.pid"|sed 's/ //g'`
#if [ ! "$PID"x = "x" ]; then
#  ps -ef|grep "$prg_name"|egrep -v "vi |vim "|awk '{print $2}'|egrep "^$PID$" >/dev/null
#  if [ $? -eq 0 ]; then
#    d=`date`
#    echo "$d: There is already running another copy of $prg_name, exiting ..."
#    ps=`ps -ef|grep "$prg_name"|egrep -v "vi |vim "|awk '{print $2}'|egrep "^$PID$" >/dev/null`
#    echo "$d: There is already running another copy of $prg_name, exiting ...\"$ps\"" >> $ERRLOG
#    exit 1
#  fi
#fi
## ok, there is no other copy of $prg_name
#echo "$$" > "$INPUTDIR/tmp/$prg_name.pid"


PERL5LIB=$BINDIR:$PERL5LIB
export PERL5LIB
#echo `perldoc -m LWP`

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

export ERRLOG

if [ -f $ERRLOG ]; then
  ERR_START=`wc -l $ERRLOG |awk '{print $1}'`
else
  ERR_START=0
fi

# Checks
if [ ! -f "$RRDTOOL" ]; then
  echo "Set correct path to RRDTOOL binary in lpar2rrd.cfg, it does not exist here: $RRDTOOL"
  echo "Set correct path to RRDTOOL binary in lpar2rrd.cfg, it does not exist here: $RRDTOOL" >> $ERRLOG
  exit 1
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
if [ ! -d "$WEBDIR" ]; then
  echo "Set correct path to WEBDIR in lpar2rrd.cfg, it does not exist here: $WEBDIR"
  exit 1
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


#GUI cron job check
prg_name=`basename $0`
PID=`cat "$INPUTDIR/tmp/$prg_name.pid"|sed 's/ //g'`
echo "$$" > "$INPUTDIR/tmp/$prg_name.pid"

DB2_LIST=`$PERL $BINDIR/db2-list.pl`
if [ "$DB2_LIST" = "NO_DB2_HOSTS_FOUND" ]; then
  echo No hosts were found in $INPUTDIR/etc/web_config/hosts.json to run DB2. Check Host Configuration in GUI and configure your databases there.
  exit;
fi

#HS reset
HS_DIR=$INPUTDIR/tmp/health_status_summary/DB2
HS_CHECK=$HS_DIR/hscheck

if [ "$DEMO"x = "x" ] || [ $DEMO -eq 0 ]; then
  if [ -f $HS_CHECK ]; then
    rm -r "$HS_DIR"
  else
    if [ -e $HS_DIR ]; then
      touch $HS_CHECK
    fi
  fi
fi

for MYDB in $DB2_LIST
   do
  export MYDB=$MYDB
  echo Start $MYDB Data Fetch

  $PERL -w $BINDIR/db2-db2json.pl $MYDB 2>>$ERRLOG


  echo "db2-json2rrd.pl : push data to rrd, "`date`

  $PERL -w $BINDIR/db2-json2rrd.pl $MYDB 2>>$ERRLOG
  echo "db2-json2rrd.pl : status $status, "`date`

  # generate html configuration pages
  $PERL -w $BINDIR/db2-genconf.pl $MYDB & 2>>$ERRLOG
done


  # XorMon load data to SQLite
  if [ ! "$XORMON"x = "x" ]; then
    if [ "$XORMON" != "0" ]; then
      echo "db2-json2db.pl             : db, "`date`
      $PERL -w $BINDIR/db2-json2db.pl 2>>$ERRLOG
    fi
  fi


# remove data if they are older than 3 months
######$PERL -w $BINDIR/oracledb-cleanup.pl 2>>$ERRLOG

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
  echo "An error occured in lpar2rrd, check $ERRLOG and output of load_db2.sh"
  echo ""
  echo "$ tail -$ERR_TOT $ERRLOG"
  echo ""
  tail -$ERR_TOT $ERRLOG
fi

edate=`date`
echo "date end all      : $edate"
exit 0

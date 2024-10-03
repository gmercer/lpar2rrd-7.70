#!/bin/ksh

pwd=`pwd`
if [ -d "etc" ]; then
   path="etc"
else
  if [ -d "../etc" ]; then
    path="../etc"
  else
    if [ ! "$INPUTDIR"x = "x" ]; then
      cd $INPUTDIR >/dev/null
      if [ -d "etc" ]; then
         path="etc"
      else
        if [ -d "../etc" ]; then
          path="../etc"
        else
          echo "problem with actual directory, assure you are in LPAR2RRD home, act directory: $pwd, INPUTDIR=$INPUTDIR"
          exit
        fi
      fi
    else
      echo "problem with actual directory, assure you are in LPAR2RRD home, act directory: $pwd, INPUTDIR=$INPUTDIR"
      exit
    fi
  fi
fi

CFG="$pwd/$path/lpar2rrd.cfg"
. $CFG

HMC_USER=`egrep "HMC_USER=" $CFG|grep -v "#"| tail -1|awk -F = '{print $2}'`
HMC=`egrep "HMC_LIST=" $CFG|grep -v "#"| tail -1|awk -F = '{print $2}'|sed 's/"//g'`
SRATE=`egrep "SAMPLE_RATE=" $CFG|grep -v "#"| tail -1|awk -F = '{print $2}'`
SSH=`egrep "SSH=" $CFG|grep -v "#"| tail -1| sed -e 's/SSH=//'`


if [ "$INPUTDIR" = "." ]; then
   INPUTDIR=`pwd`
fi
INPUTDIR=`echo "$INPUTDIR"|sed 's/\bin$//'`
BINDIR=`echo "$BINDIR"|sed 's/\/bin\/bin/\/bin/'`

if [ "$INPUTDIR"x = "x"  ]; then
   INPUTDIR="."
fi
export INPUTDIR

# run it just once a day
TOUCH_FILE="sample_rate-daily.txt"
if [ -f "$INPUTDIR/tmp/$TOUCH_FILE" -a `find $INPUTDIR/tmp/ -mtime +1 -name $TOUCH_FILE 2>/dev/null | wc -l ` -eq 0 ]; then
  echo "sample daily   :$0 : not now"
  exit 0
fi
#echo "$0 : now"
touch $INPUTDIR/tmp/$TOUCH_FILE
cat /dev/null >  $INPUTDIR/logs/sample_rate-daily.log

# check if is not there hanging sample_rate.sh from yesterday, if so, kill it
if [ `ps -ef| grep sample_rate.sh| grep -v grep | wc -l` -gt 0 ]; then
  echo "Killing old sample_rate.sh" >> $INPUTDIR/logs/sample_rate-daily.log
  #ps -ef| grep sample_rate.sh| grep -v grep 
  kill -9 `ps -ef| grep sample_rate.sh| grep -v grep | awk '{print $2}' |xargs`
fi

# subroutines for time trap
  timeout=300  # timeout just to be sure that it does not hung
  #timeout=2  # timeout just to be sure that it does not hung
  cleanup()
  {
    echo "Script timed out on internal timeout $timeout" >> $INPUTDIR/logs/sample_rate-daily.log
    kill -ALRM $pid_wait_time 2>/dev/null #stop timer subshell if running
    sleep 1
    kill -$! 2>/dev/null    #kill last job
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


# calling bin/sample_rate.sh


wait_time $timeout & pid_wait_time=$!         #start the timeout
trap "cleanup" ALRM          # cleanup after timeout
$BINDIR/sample_rate.sh 2>&1 >> $INPUTDIR/logs/sample_rate-daily.log & wait $!           # start the job wait for it and save its return value
status=$?
echo "end sample     : status $status" >> $INPUTDIR/logs/sample_rate-daily.log 
kill -TERM $pid_wait_time 2>/dev/null 1>&2   # send TERM to whole process group
wait $pid_wait_time          # wait for watchit to finish cleanup


#!/bin/ksh

# wrapper to prevent double run & kill same name processes after $minutes time
# this script can have any name :)
# all variables are already exported to env
# run it from cmd line as:
# . etc/lpar2rrd.cfg ; TMPDIR_LPAR=$INPUTDIR/tmp ; export TMPDIR_LPAR ; ./<<this_script_name>> #xx_pidfile_test.sh

prg_name=`basename $0`
PIDFILE="$TMPDIR_LPAR/$prg_name.pid" # if this file is running process,  if older $minutes kill all that name processes

if [ -f $PIDFILE ]; then
  PID=`cat $PIDFILE|sed 's/ //g'`
  if [ ! "$PID"x = "x" ]; then
    ps -ef|grep "$prg_name"|egrep -v "vi |vim "|awk '{print $2}'|egrep "^$PID$" 2>/dev/null
    if [ $? -eq 0 ]; then
      d=`date`
      ps=`ps -ef|grep "$prg_name"|egrep -v "vi |vim "|awk '{print $2}'|egrep "^$PID$" 2>/dev/null`
      echo "$d: There is already running another copy of $prg_name ...\"$ps\""
      echo "$d: There is already running another copy of $prg_name ...\"$ps\"" >> $ERRLOG
  	  minutes=180
	    # minutes=2 # for debug
	    if test `find "$PIDFILE" -mmin +$minutes`
        then echo "$prg_name is running more than $minutes minutes, trying to kill all these processes & exiting..."
          echo "$prg_name is running more than $minutes minutes, trying to kill all these processes & exiting..." >> $ERRLOG
          # kill this process and its subprocesses
          for die in `ps -ef|grep $PID|grep -v grep|awk '{print $2}'`
            do
              echo "process id to die $die"
              kill $die
            done
			    # kill `ps -ef |grep $prg_name| awk '{print $2}' | xargs`
	    else echo "$prg_name is running less than $minutes minutes, exiting..."
			  echo "$prg_name is running less than $minutes minutes, exiting..." >> $ERRLOG
      fi
      exit 1
    fi
  fi
fi
# ok, there is no other copy of $prg_name
echo "$$" > $PIDFILE

echo "Updating       : start updating rrdfiles with vcenter data in background"
$PERL -w $BINDIR/vmware_push_perf_data_to_rrd.pl 2>>$ERRLOG >> $INPUTDIR/logs/load_vmware_rrd.log
# sleep 600 # for debug

#!/bin/ksh
#
# run single vCenter
#


# subroutines for time trap
  timeout=3550  # less then 1 hour timeout
  cleanup()
  {
    echo "vmware timeout : expired after $timeout, killing : kill -TERM -$$"
    echo "vmware timeout : expired after $timeout, killing : kill -TERM -$$" >> $INPUTDIR/logs/load_vmware.log
    trap - ALRM               #reset handler to default
    kill -TERM -$$ 2>/dev/null
    sleep 2
    kill -ALRM $pid_wait_time 2>/dev/null #stop timer subshell if running
    kill $! 2>/dev/null    #kill last job
    exit
  }

  wait_time()
  {
    echo "vmware timeout : timeout has been set to $timeout"
    echo "vmware timeout : timeout has been set to $timeout" >> $INPUTDIR/logs/load_vmware.log
    trap "cleanup" ALRM
    sleep $timeout & wait
    slp_pid=$!
    echo "vmware timeout : expired after $timeout seconds : kill -ALRM $$"
    echo "vmware timeout : expired after $timeout seconds : kill -ALRM $$" >> $INPUTDIR/logs/load_vmware.log
    kill -ALRM $$ 2>/dev/null
    sleep 3
    kill $slp_pid # kill sleep running on the backend
    # sending ALRM to parent somehow does not work, do it in this way as a workaround
    kill -TERM $$ 2>/dev/null
    sleep 1
    kill -TERM -$$ 2>/dev/null
    exit
  }

  if [ "$PERL" = "/opt/freeware/bin/perl" ]; then
    # AIX tricks to get it work together with VMware 6.7
    # Perl LWP module on AIX requires openssl from /usr/lib!!! It does not work with  /opt/freeware/lib one
    # It is a must for /opt/freeware/bin/perl && AIX && REST API https
    PERL5LIB=$INPUTDIR/lib:$PERL5LIB
    export PERL5LIB

    # /usr/lib must be the first, but /opt/freeware/lib must be included as well
    LIBPATH=/usr/lib:/opt/freeware/lib:$LIBPATH
    export LIBPATH
  fi

  wait_time $timeout& pid_wait_time=$!         #start the timeout
  trap "cleanup" ALRM          # cleanup after timeout
  $PERL -w $BINDIR/vmw2rrd.pl 2>>$ERRLOG | tee -a $INPUTDIR/logs/load_vmware.log & wait $!           # start the job wait for it and save its return value
  status=$?
  echo "vmware finish  : status $status"

  kill -ALRM $pid_wait_time 2>/dev/null   # send ALRM signal to watchit
  wait $pid_wait_time          # wait for watchit to finish cleanup
  sleep 2

  # kill all forks just to be sure as sometimes rrdtool processes might hang
  processes=`ps -ef| awk '{print $3}'| grep $$ | xargs`
  if [ ! "$processes"x = "x" ]; then
    echo "Vcleaning procs: $processes"
    kill -TERM -$$ 2>/dev/null # clean up all forks and rrdtools
    sleep 2
    processes=`ps -ef| awk '{print $3}'| grep $$ | xargs`
    echo "Vcleaning done : $processes"
  fi


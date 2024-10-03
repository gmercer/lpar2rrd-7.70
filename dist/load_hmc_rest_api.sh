#!/bin/ksh
PATH=$PATH:/usr/bin:/usr/local/bin:/opt/freeware/bin
export PATH

LANG=C
export LANG

# it is necessary as files need to be readable also for WEB server user
umask 022

#echo `perldoc -m LWP | head -n 3`

# Load LPAR2RRD configuration
. `dirname $0`/etc/lpar2rrd.cfg

# Load "magic" setup
if [ -f `dirname $0`/etc/.magic ]; then
  . `dirname $0`/etc/.magic
  if [ ! "$VM_IMAGE"x = "x" ]; then
    if [ $VM_IMAGE -eq 1 ]; then
      echo "Image environment is set"
    fi
  fi
fi

PROXY_RECEIVE=`$PERL $BINDIR/hmc_list.pl --proxy`
export PROXY_RECEIVE

if [ "$INPUTDIR" = "." ]; then
   INPUTDIR=`pwd`
   export INPUTDIR
   BINDIR=$INPUTDIR/bin
   export BINDIR
fi

LIBPATH_ORI=$LIBPATH
if [ `uname -a|grep AIX|wc -l` -gt 0 ]; then
  # AIX tricks to get it work together with VMware
  PERL5LIB=$INPUTDIR/lib:$PERL5LIB
  export PERL5LIB

  # /usr/lib must be the first, but /opt/freeware/lib must be included as well
  LIBPATH=/usr/lib:/opt/freeware/lib:$LIBPATH
  export LIBPATH
fi


prg_name=`basename $0`
PIDFILE="$INPUTDIR/tmp/$prg_name.pid"

#if [ -f $PIDFILE ]; then
#  PID=`cat $PIDFILE|sed 's/ //g'`
#  if [ ! "$PID"x = "x" ]; then
#    ps -ef|grep "$prg_name"|egrep -v "vi |vim "|awk '{print $2}'|egrep "^$PID$" >/dev/null
#    if [ $? -eq 0 ]; then
#      d=`date`
#      echo "$d: There is already running another copy of $prg_name, exiting ..."
#      ps=`ps -ef|grep "$prg_name"|egrep -v "vi |vim "|awk '{print $2}'|egrep "^$PID$" >/dev/null`
#      echo "$d: There is already running another copy of $prg_name, exiting ...\"$ps\"" >> $ERRLOG-hmc_rest_api
#      exit 1
#    fi
#  fi
#fi

echo "$$" > $PIDFILE

cleanup()
{
  echo "Exiting on alarm"
  exit 2
}

trap "cleanup" ALRM
trap "cleanup" TERM


#HMC_USER=`egrep "HMC_USER=" $CFG|grep -v "#"| tail -1|awk -F = '{print $2}'`
#HMC=`egrep "HMC_LIST=" $CFG|grep -v "#"| tail -1|awk -F = '{print $2}'|sed 's/"//g'`
#SRATE=`egrep "SAMPLE_RATE=" $CFG|grep -v "#"| tail -1|awk -F = '{print $2}'`

# remove "-o PreferredAuthentications=publickey" and "-q" on purpose  to see errors
#SSH=`egrep "SSH=" $CFG|grep -v "#"| tail -1| sed -e 's/SSH=//' -e 's/-o PreferredAuthentications=publickey//' -e 's/ -q / /'`
#echo "$SSH"

if [ -f "$HMC" ]; then
  # HMC contains a name of file where HMC are listed
  HMC=`cat $HMC`
fi

if [ "$HMC_PARALLEL_RUN"x = "x" ]; then
  # new default since 4.95-8 is 5 (was 1)
  HMC_PARALLEL_RUN=5 # when > 1 then HMC are processed concurrently
  #HMC_PARALLEL_RUN=1 # when > 1 then HMC are processed concurrently
fi

TMP=/var/tmp/sample_rate.$$
rm -f $TMP

SSH=`echo $SSH|sed 's/"//g'`
#echo "Going to check HMC as user $HMC_USER, if there appears a prompt for password then allow ssh-key access as per docu."
count=0

export LIBPATH=/usr/lib:/opt/freeware/lib:$LIBPATH

HMC_LIST_PROXY=`$PERL $BINDIR/hmc_list.pl --api-proxy`
HMC_LIST_API=`$PERL $BINDIR/hmc_list.pl --api`
hmc_list_api_empty=0
hmc_list_api_proxy_empty=0
if [ x"$HMC_LIST_API" = "x" ] || [ "$HMC_LIST_API" = "NO_POWER_HOSTS_FOUND" ] ; then
  echo No hosts were found in $INPUTDIR/etc/web_config/hosts.json to run HMC REST API. Check Host Configuration in GUI and configure your HMCs there.
  hmc_list_api_empty=1
fi
if [ x"$HMC_LIST_PROXY" = "x" ] || [ "$HMC_LIST_PROXY" = "NO_POWER_HOSTS_FOUND" ]; then
  echo No hosts were found in $INPUTDIR/etc/web_config/hosts.json to run HMC REST API PROXY.
  hmc_list_api_proxy_empty=1
fi

if [ "$hmc_list_api_proxy_empty" = "1" ] && [ "$hmc_list_api_empty" = "1" ]; then
  echo "Nor proxy nor api access defined. Exiting..."
  exit
fi

pids=""
RESULT=0

cd $INPUTDIR;

if [ ! -d offsite ]; then
  mkdir offsite
fi
if [ "$PROXY_RECEIVE" = 1 ]; then
  for tar_archive in offsite/*.gz
  do
    response=`gunzip $tar_archive`;
    echo "processing $tar_archive => $response"
  done
  for tar_archive in offsite/*.tar
  do
    echo "TAR:$tar_archive"
    response=`tar xvf $tar_archive`
    echo "Response $tar_archive ($?) : =$response="
    if [ ! $? -eq 0 ]; then
      echo "ERROR: tar xvf problem, skipping $!"
      rm $tar_archive
      continue
    else
      echo "Data from $tar_archive loaded sucessfully, removing old tar archiv"
      rm $tar_archive
    fi
  done
fi

if [ "$PROXY_RECEIVE"x = "x" ] || [ "$PROXY_RECEIVE" = 0 ]; then
  cd offsite
  files=`ls *.tar* 2>/dev/null`;
  for tar_archive in $files
  do
    echo "TAR : $tar_archive found but no PROXY_RECEIVE defined. Removing $tar_archive..."
    rm $tar_archive
  done
fi


export REST_API=1
export HMC_JSONS=1

for HMC in $HMC_LIST_API
  do
  PROC=`ps -ef | egrep 'hmc_rest_api.pl' | egrep perf | egrep -e " $HMC " | egrep -v grep | wc -l|sed 's/ //g'`
  if [ "$PROC" = "0" ]; then
    export HMC=$HMC
    export PROXY_RECEIVE=`$PERL $BINDIR/hmc_list.pl --proxy $HMC`
    echo Start $HMC Data Fetch
    $PERL $INPUTDIR/bin/hmc_rest_api.pl $HMC "perf" 2>>$ERRLOG-hmc_rest_api &
    pids="$pids $!"
  else
    echo "Process stuck for hmc_rest_api.pl $HMC"
  fi

done

for pid in $pids; do
  echo "wait pid for $pid"
  wait $pid
done

pids=""
pids2=""
LIBPATH_MOD=$LIBPATH
export LIBPATH=$LIBPATH_ORI

# direct output to logs/load_hmc_rest_api.out only, clean it each run

##############
# CMC
##############

if [ `ps -ef | egrep 'hmc_rest_api.pl' | egrep perf | egrep -e "bin/power_cmc_caller.pl" | egrep -v grep | wc -l|sed 's/ //g'` -eq 0  ]; then
  nohup $PERL $INPUTDIR/bin/power_cmc_caller.pl > $INPUTDIR/logs/power_cmc.out 2>>$ERRLOG-power_cmc  &
fi

HMC_LIST_API_PLUS_PROXY="$HMC_LIST_API $HMC_LIST_PROXY"
PROC=`ps -ef | egrep 'lpar2rrd.pl' | grep -v grep | wc -l|sed 's/ //g'`
for HMC in $HMC_LIST_API_PLUS_PROXY
  do
  if [ "$PROC" = "0" ]; then
    if [ "$PROXY_SEND" = 1 ]; then
      echo "PROXY SEND INSTANCE 1 ACTIVE, break the loading"
      break
    fi
    export REST_API=1
    export HMC_JSONS=1
    export HMC=$HMC;
    export HMC_USER=`$PERL $BINDIR/hmc_list.pl --username $HMC`;
    if [ $HMC_PARALLEL_RUN -eq 1 ]; then
      $PERL -w $INPUTDIR/bin/lpar2rrd.pl 2>>$ERRLOG-hmc_rest_api | tee -a $INPUTDIR/logs/load_hmc_rest_api.out
      pids2="$pids2 $!"
    else
      eval '$PERL -w $INPUTDIR/bin/lpar2rrd.pl 2>> $ERRLOG-hmc_rest_api | tee -a $INPUTDIR/logs/load_hmc_rest_api.out' &
      pids2="$pids2 $!"
    fi
  else
    echo "process stuck for lpar2rrd.pl $PROC"
  fi
done

for pid2 in $pids2; do
  wait $pid2
done

#echo "power-json2db.pl  : collect data from db, "`date`
#$PERL -w $BINDIR/power-json2db.pl 2>>$ERRLOG

echo load_hmc_rest_api.sh end $$

export ALERTING_REST=1
sh $INPUTDIR/load_alert.sh

cp -f $INPUTDIR/logs/load_hmc_rest_api_conf.out $INPUTDIR/logs/load_hmc_rest_api_conf.prev 2>/dev/null
cp -f $INPUTDIR/load_hmc_rest_api_conf.out $INPUTDIR/logs/load_hmc_rest_api_conf.out 2>/dev/null

echo "" > $INPUTDIR/load_hmc_rest_api_conf.out
export LIBPATH=$LIBPATH_MOD

# nohup configuration once a day
for HMC in $HMC_LIST_API
do
  export HMC=$HMC
  export PROXY_RECEIVE=`$PERL $BINDIR/hmc_list.pl --proxy $HMC`
  $PERL $INPUTDIR/bin/hmc_rest_api.pl $HMC "conf" >> $INPUTDIR/load_hmc_rest_api_conf.out 2>>$ERRLOG-hmc_rest_api &
done

cp $INPUTDIR/logs/load_hmc_rest_api.out $INPUTDIR/logs/load_hmc_rest_api.prev 2>/dev/null
cp $INPUTDIR/load_hmc_rest_api.out $INPUTDIR/logs/load_hmc_rest_api.out 2>/dev/null

export LIBPATH=$LIBPATH_ORI
exit

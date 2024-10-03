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

if [ -f $INPUTDIR/etc/version.txt ]; then
  # actually installed version include patch level (in $version is not patch level)
  version_patch=`cat $INPUTDIR/etc/version.txt|tail -1`
  export version_patch
fi

# Set XML Parser
xml_parser_file="$INPUTDIR/tmp/xml_parser"
parser_result=`${PERL} -MXML::Parser -le 'print $INC{"XML/Parser.pm"}'`
if [ -z "$parser_result" ]; then
  if [ -f "$xml_parser_file" ]; then
    rm $xml_parser_file
  fi
else
  touch $xml_parser_file
fi

# copy of connection tests logs
cp -p $INPUTDIR/etc/web_config/config_check_* $INPUTDIR/logs 2>/dev/null

HOSTNAME=`uname -n`
export HOSTNAME

ID=`( lsattr -El sys0 -a systemid 2>/dev/null || hostid ) | sed 's/^.*,//' | awk '{print $1}'`
UN=`uname -a`
UNAME=`echo "$UN $ID"`
export UNAME


UNAME=`uname`
TWOHYPHENS="--"
if [ "$UNAME" = "SunOS" ]; then TWOHYPHENS=""; fi # problem with basename param on Solaris
export TWOHYPHENS

cd $INPUTDIR
# Check if it runs under the right user
if [ `uname -s` = "SunOS" ]; then
  # Solaris does not have -X
  install_user=`ls -l $BINDIR/lpar2rrd.pl|awk '{print $3}'`
else
  install_user=`ls -lX $BINDIR/lpar2rrd.pl|awk '{print $3}'` # must be X to do not cut user name to 8 chars
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

# cleanup of old hanging processes, it happens for VMware, they must be
# 1. same user
# 2. grep "Hiding the command line arguments"
# 3. more than a day old: there is a month in ps output
# lpar2rrd  4391216  6619458   0   Dec 10      -  0:01 Hiding the command line arguments


for proc_space in `ps -ef| grep $running_user| grep "Hiding the command line arguments"| grep -v grep |sed 's/ /===space===/g'`
do
  #echo "=== $proc_space"
  proc=`echo $proc_space|sed 's/===space===/ /g'`
  month=`echo $proc| awk '{print $5}'|sed -e 's/://g' -e 's/[0-9]//g'`
  if [ ! "$month"x = "x" ]; then
    # there is no digit, just characters on possition 5, means process must be older than 1 day
    echo "Killing old process: $month : $proc"
    echo "Killing old process: $proc" >> $ERRLOG
    kill `echo $proc| awk '{print $2}'`
  fi
done


# (without entitlement area in lpar graphs)
# run it from cron as follows
# 30 * * * * export WEBDIR_PUBLIC=/home/lpar2rrd/lpar2rrd/www_public; /home/lpar2rrd/lpar2rrd/load.sh > /home/lpar2rrd/lpar2rrd/load.out 2>&1
# etc/.magic setup (to say the GUI where is the right menu.txt file)
# WWW_ATERNATE_URL="__part_of_web_path__"
# WWW_ATERNATE_TMP="tmp_public"
#

ENTITLEMENT_LESS=0
TMPDIR_LPAR=$INPUTDIR/tmp
if [ ! "$WEBDIR_PUBLIC"x = "x" ]; then
  ENTITLEMENT_LESS=1
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
export ENTITLEMENT_LESS WEBDIR TMPDIR_LPAR


#
# when WEBDIR_PUBLIC is defined then it creates a new (second) web root for public users (on demand extention for a customer)
# ./load.sh html --> it runs only web creation code
HTML=0
if [ ! "$1"x = "x" -a "$1" = "html" ]; then
  HTML=1
  touch $TMPDIR_LPAR/$version-run # force to run html part
  touch $TMPDIR_LPAR/$version-ovirt # force to run html part
  touch $TMPDIR_LPAR/$version-xenserver # force to run html part
  touch $TMPDIR_LPAR/$version-oracledb # force to run html part
  touch $TMPDIR_LPAR/$version-sqlserver # force to run html part
  touch $TMPDIR_LPAR/$version-db2 # force to run html part
  touch $TMPDIR_LPAR/$version-postgres # force to run html part
  touch $TMPDIR_LPAR/$version-oraclevm # force to run html part
  touch $TMPDIR_LPAR/$version-nutanix # force to run html part
  touch $TMPDIR_LPAR/$version-aws # force to run html part
  touch $TMPDIR_LPAR/$version-gcloud # force to run html part
  touch $TMPDIR_LPAR/$version-azure # force to run html part
  touch $TMPDIR_LPAR/$version-kubernetes # force to run html part
  touch $TMPDIR_LPAR/$version-openshift # force to run html part
  touch $TMPDIR_LPAR/$version-cloudstack # force to run html part
  touch $TMPDIR_LPAR/$version-proxmox # force to run html part
  touch $TMPDIR_LPAR/$version-docker # force to run html part
  touch $TMPDIR_LPAR/$version-fusioncompute # force to run html part
  touch $TMPDIR_LPAR/$version-windows # force to run html part
  LPM=0 # switch off LPM search
fi

prg_name=`basename $0`
PIDFILE="$TMPDIR_LPAR/$prg_name.pid"

# ./load.sh custom --> it runs custom group refresh
CUSTOM_GRP=0
if [ ! "$1"x = "x" -a "$1" = "custom" ]; then
  CUSTOM_GRP=1
  touch $TMPDIR_LPAR/$version-run # force to run html part
  LPM=0 # switch off LPM search
  rm -f $TMPDIR_LPAR/custom-group-*  # delete all groups and let them recreate, it delete already unconfigured ones
  PIDFILE="$TMPDIR_LPAR/$prg_name-custom.pid" # allow to run "load.sh custom"
fi

# stopping LPAR2RRD daemon
if [ ! "$1"x = "x" -a "$1" = "daemon_stop" ]; then
  echo "Stopping the daemon"
  if [ -s "$TMPDIR_LPAR/lpar2rrd-daemon.pid" ]; then
    PID=`cat "$TMPDIR_LPAR/lpar2rrd-daemon.pid"|sed 's/ //g'`
    if [ ! "$PID"x = "x" -a `echo $PID | sed  's/[0-9].*//'| egrep -v "^$"|wc -l` -eq 0 ]; then
      run=`ps -ef|grep lpar2rrd-daemon.pl| egrep -v "grep |vi | vim "|grep $PID|wc -l`
      if [ $run -gt 0 ]; then
        kill $PID # to whole process group, even fork processes have to be stopped
      else
        run=`ps -ef|grep lpar2rrd-daemon.pl| egrep -v "grep |vi | vim "| head|awk '{print $2}'| wc -l`
        if [ $run -gt 0 ]; then
          kill `ps -ef|grep lpar2rrd-daemon.pl| egrep -v "grep |vi | vim "| head|awk '{print $2}'`
        else
          echo "Could not found running LPAR2RRD daemon - running, check if it is really running one: ps -ef| grep lpar2rrd-daemon"
        fi
      fi
    else
      echo "Could not found running LPAR2RRD daemon : $TMPDIR_LPAR/lpar2rrd-daemon.pid file does contain PID"
    fi
  else
    run=`ps -ef|grep lpar2rrd-daemon.pl| egrep -v "grep |vi | vim "| head|awk '{print $2}'| wc -l`
    if [ $run -gt 0 ]; then
      kill `ps -ef|grep lpar2rrd-daemon.pl| egrep -v "grep |vi | vim "| head|awk '{print $2}'`
    else
      echo "Could not found running LPAR2RRD daemon - running, check if it is really running one: ps -ef| grep lpar2rrd-daemon"
    fi
  fi
  echo "Exiting"
  exit 0
fi

PID_DAEMON="999999999"
DAEMON_STARTED=0
if [ ! x"$LPAR2RRD_AGENT_DAEMON" = "x" -a ! x"$LPAR2RRD_AGENT_DAEMON_PORT" = "x" ]; then
  if [ $LPAR2RRD_AGENT_DAEMON -eq 1 ]; then
    # Start up LPAR2RRD agent daemon for receiving mem stats directly from LPARs
    # if it is already running then do nothing
    if [ -s "$TMPDIR_LPAR/lpar2rrd-daemon.pid" ]; then
      PID=`cat "$TMPDIR_LPAR/lpar2rrd-daemon.pid"|sed 's/ //g'`
      if [ ! "$PID"x = "x" ]; then
        run=`ps -ef|grep lpar2rrd-daemon.pl| egrep -v "grep |vi | vim "|grep $PID|wc -l`
        if [ $run -eq 0 ]; then
          # start up the daemon
          echo "LPAR2RRD daemon: starting at port:$LPAR2RRD_AGENT_DAEMON_PORT "
          nohup $PERL -w $INPUTDIR/bin/lpar2rrd-daemon.pl 2>>$ERRLOG-daemon 1>>$INPUTDIR/logs/daemon.out &
          sleep 1 # must be here to get time for writing PID into $TMPDIR_LPAR/lpar2rrd-daemon.pid
          DAEMON_STARTED=1
        else
          if [ ! "$1"x = "x" ]; then
            if [ "$1" = "daemon" -o "$1" = "daemon_start" ]; then
              echo "LPAR2RRD daemon: already running"
              exit 0
            fi
          fi
        fi
      fi
    else
      echo "Starting LPAR2RRD daemon on port:$LPAR2RRD_AGENT_DAEMON_PORT "
      nohup $PERL $INPUTDIR/bin/lpar2rrd-daemon.pl 2>>$ERRLOG-daemon 1>>$INPUTDIR/logs/daemon.out &
      sleep 2 # must be here to get time for writing PID into $TMPDIR_LPAR/lpar2rrd-daemon.pid
    fi
    if [ -f "$TMPDIR_LPAR/lpar2rrd-daemon.pid" ]; then
      PID_DAEMON=`cat "$TMPDIR_LPAR/lpar2rrd-daemon.pid"|sed 's/ //g'`
    fi
    if [ `ps -ef|grep -v grep|grep $PID_DAEMON|wc -l` -eq 0 -o `ps -ef|grep -v grep|grep lpar2rrd-daemon|wc -l|sed 's/ //g'` -eq 0 ]; then
      echo "LPAR2RRD daemon: is not running"
      sleep 1
    fi
  fi
  if [ ! "$1"x = "x" ]; then
    if [ "$1" = "daemon" -o "$1" = "daemon_start" ]; then
      exit 0
    fi
  fi
fi


# start RRDCached only if LPAR2RRD_AGENT_DAEMON is allowed
if [ $LPAR2RRD_CACHE_NO -eq 0 -a ! x"$LPAR2RRD_AGENT_DAEMON" = "x" -a ! x"$LPAR2RRD_AGENT_DAEMON_PORT" = "x" ]; then
  if [ $LPAR2RRD_AGENT_DAEMON -eq 1 ]; then
    rrdcached=`whereis rrdcached| awk '{print $2}'`
    if [ ! -f "$rrdcached" ]; then
      if [ -f /opt/freeware/bin/rrdcached ]; then
        rrdcached="/opt/freeware/bin/rrdcached"
      else
        if [ -f /usr/bin/rrdcached ]; then
          rrdcached="/usr/bin/rrdcached"
        fi
      fi
    fi
    if [ "$rrdcached"x = "x" -o ! -f "$rrdcached" ]; then
      echo "RRDCached      : rrdcached binary has not been found"
      #echo "RRDCached      : more info about RRDCached on http://www.lpar2rrd.com/RRDCached.htm "
    else
      cached_timeout=60
      cached_timeout_old=120
      cached_delay=10
      if [ ! "$LPAR2RRD_CACHE_TIMEOUT"x = "x" ]; then
        cached_timeout=$LPAR2RRD_CACHE_TIMEOUT
      fi
      if [ ! "$LPAR2RRD_CACHE_TIMEOUT_OLD"x = "x" ]; then
        cached_timeout_old=$LPAR2RRD_CACHE_TIMEOUT_OLD
      fi
      if [ ! "$LPAR2RRD_CACHE_DELAY"x = "x" ]; then
        cached_delay=$LPAR2RRD_CACHE_DELAY
      fi
      if [ -f "$TMPDIR_LPAR/rrdcached.pid" ]; then
        PID=`cat "$TMPDIR_LPAR/rrdcached.pid"|sed 's/ //g'`
        run=`ps -ef|grep rrdcached| egrep -v "grep |vi | vim "|grep $PID|wc -l`
        if [ $run -eq 0 ]; then
          echo "RRDCached      : starting"
          $rrdcached -m 0660 -l unix:$TMPDIR_LPAR/.sock-lpar2rrd -F -w $cached_timeout -f $cached_timeout_old -z $cached_delay -p $TMPDIR_LPAR/rrdcached.pid
          sleep 2
        else
          echo "RRDCached      : already running"
        fi
      else
        echo "RRDCached      : starting"
        $rrdcached -m 0660 -l unix:$TMPDIR_LPAR/.sock-lpar2rrd -F -w $cached_timeout -f $cached_timeout_old -z $cached_delay -p $TMPDIR_LPAR/rrdcached.pid
        sleep 2
      fi
    fi
  fi
fi

#
# issue VMware on the background
#
$INPUTDIR/load_vmware.sh $1 &

if [ -f $PIDFILE ]; then
  PID=`cat $PIDFILE|sed 's/ //g'`
  if [ ! "$PID"x = "x" ]; then
    ps -ef|grep "$prg_name"|egrep -v "vi |vim "|awk '{print $2}'|egrep "^$PID$" >/dev/null
    if [ $? -eq 0 ]; then
      d=`date`
      echo "$d: There is already running another copy of $prg_name, exiting ..."
      ps=`ps -ef|grep "$prg_name"|egrep -v "vi |vim "|awk '{print $2}'|egrep "^$PID$" >/dev/null`
      echo "$d: There is already running another copy of $prg_name, exiting ...\"$ps\"" >> $ERRLOG
      exit 1
    fi
  fi
fi
# ok, there is no other copy of $prg_name
echo "$$" > $PIDFILE


UPGRADE=0
if [ ! -f $TMPDIR_LPAR/$version ]; then
  if [ ! "$DEBUG"x = "x" ]; then
    if [ $DEBUG -gt 0 ]; then
      echo ""
      echo "Upgrade        : Looks like there has been an upgrade to $version or new installation"
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
  if [ ! -f $WEBDIR/gui-cpu_max_check.html -a -f $INPUTDIR/html/gui-cpu_max_check.html ]; then
    cp $INPUTDIR/html/gui-cpu_max_check.html $WEBDIR/
  fi
  if [ ! -f $WEBDIR/gui-cpu_max_check_vm.html -a -f $INPUTDIR/html/gui-cpu_max_check_vm.html ]; then
    cp $INPUTDIR/html/gui-cpu_max_check_vm.html $WEBDIR/
  fi

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
  ERR_START=`grep -v nohup $ERRLOG |wc -l | awk '{print $1}'`
else
  ERR_START=0
fi

# Checks
if [ "$RRDTOOL"x = "x" ]; then
  echo "RRDTOOL variable is not defined in etc/lpar2rrd.cfg, correct it"
  echo "RRDTOOL variable is not defined in etc/lpar2rrd.cfg, correct it" >> $ERRLOG
  exit 1
fi
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

# RRDTool version checking for graph zooming
$RRDTOOL|grep graphv >/dev/null 2>&1
if [ $? -eq 1 ]; then
  # suggest RRDTool upgrade
  echo ""
  rrd_version=`$rrd -v|head -1|$AWK '{print $2}'`
  echo "Consider RRDtool upgrade to version 1.3.5+ (actual one is $rrd_version)"
  echo "This will allow graph zooming: http://www.lpar2rrd.com/zoom.html"
  echo ""
  # remove file tmp/graphv
  rm -f $INPUTDIR/tmp/graphv
else
  touch $INPUTDIR/tmp/graphv
fi

if [ `$RRDTOOL xport --showtime 2>&1| egrep -v "unknown option|invalid option" | wc -l | sed 's/ //g'` -gt 0 ]; then
  # --showtime is supported, touch it in tmp, must be check both: unknown option|invalid option
  touch $INPUTDIR/tmp/rrdtool-xport-showtime
else
  rm -f $INPUTDIR/tmp/rrdtool-xport-showtime
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
if [ "$REST_API" = 1 ]; then
  HMC_USER=$HMC_USER
fi
if [ x"$HMC_USER" = "x" ] && [ "$REST_API" = 0 ]; then
  echo "HMC_USER does not seem to be set up, correct it in lpar2rrd.cfg"
fi
#if [ x"$HMC_LIST" = "x" ]; then
#  if [ x"$VMWARE_LIST" = "x" ]; then
#    echo "HMC_LIST in etc/lpar2rrd.cfg neither VMWARE are not configured"
#    echo "Continuing as stand-alone Linuxes could be in place ..."
#  else
#    echo "HMC_LIST does not seem to be configured in etc/lpar2rrd.cfg, ignore it in case of VMware usage only"
#  fi
#fi
if [ -f "$HMC_LIST" ]; then
  # HMC_LIST contains a name of file where HMC are listed
  HMC_LIST=`cat $HMC_LIST`
fi
if [ -f "$INPUTDIR/etc/$HMC_LIST" ]; then
  # HMC_LIST contains a name of file where HMC are listed
  HMC_LIST=`cat $INPUTDIR/etc/$HMC_LIST`
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

if [ -f "$BINDIR/virt.pl" ]; then
  $PERL $BINDIR/virt.pl
fi

#
# IBM Power
#

# you can set HMC_PARALLEL_RUN in etc/.magic to persist upgrades
if [ "$HMC_PARALLEL_RUN"x = "x" ]; then
  # new default since 4.95-8 is 5 (was 1)
  HMC_PARALLEL_RUN=5 # when > 1 then HMC are processed concurrently
  #HMC_PARALLEL_RUN=1 # when > 1 then HMC are processed concurrently
fi


mv $INPUTDIR/logs/load_power.log $INPUTDIR/logs/load_power.prev 2>/dev/null

if [ -f $INPUTDIR/etc/web_config/hosts.json ]; then
  HMC_LIST_TMP=`$PERL $BINDIR/hmc_list.pl`;
  HMC_LIST_API=`$PERL $BINDIR/hmc_list.pl --api`;
  HMC_LIST_SSH=`$PERL $BINDIR/hmc_list.pl --old`;
  if [ "$HMC_LIST_TMP" != "NO_POWER_HOSTS_FOUND" ]; then
    echo "HMC web cfg    : HMC is configured through GUI, (HMC_LIST in lpar2rrd.cfg is ignored). Actual HMC_LIST is made from etc/web_config/hosts.json => $HMC_LIST_TMP"
  fi
  if [ "$HMC_LIST_TMP" = "NO_POWER_HOSTS_FOUND" ]; then
    export REST_API=0
  fi
fi

if [ ! "$DEMO"x = "x" ]; then
  # demo site only
  export HMC="hmc1"
  $PERL -w $BINDIR/lpar2rrd.pl 2>>$ERRLOG | tee -a $INPUTDIR/logs/load_power.log
fi

for HMC in $HMC_LIST_API
do
  export REST_API=1
  export HMC_JSONS=1
  export HMC
  if [ $HTML -eq 1 -o $CUSTOM_GRP -eq 1 ]; then continue; fi # let run only web part or custom one

  if [ $HMC_PARALLEL_RUN -eq 1 ]; then
    if  [ $REST_API = 0 ]; then
      $PERL -w $BINDIR/lpar2rrd.pl 2>>$ERRLOG   | tee -a $INPUTDIR/logs/load_power.log
    fi
  else
    if  [ $REST_API = 0 ]; then
      eval '$PERL -w $BINDIR/lpar2rrd.pl 2>>$ERRLOG  | tee -a $INPUTDIR/logs/load_power.log' &
    fi
  fi
done

if [ "$HMC_LIST_SSH" = "" ] && [ "$HMC_LIST_API" = "" ] && [ "$IVM_LIST" = "" ] && [ "$HMC_LIST" != "" ] ; then
  HMC_LIST_SSH=$HMC_LIST
  echo "Host Configuration not found, use old HMC_LIST from etc/lpar2rrd.cfg"
fi

if [ "$HMC_LIST_SSH" != "" ] || [ "$IVM_LIST" != "" ]; then
  HMC_LIST_NO_REST_API="$IVM_LIST $HMC_LIST_SSH"
  if [ ! "$HMC_LIST_SSH" = "hmc1 sdmc1 ivm1" -o ! "$IVM_LIST"x = "x" ]; then
    # go ahead just in case there is not default: hmc1 sdmc1 ivm1
    for HMC in $HMC_LIST_NO_REST_API #for old IVM specified in HMC list to get data through SSH, that doesn't support Rest API + HMC's with Rest API exclude
    do
      export REST_API=0
      export HMC_JSONS=0
      export HMC
      if [ $HTML -eq 1 -o $CUSTOM_GRP -eq 1 ]; then continue; fi # let run only web part or custom one
      echo "Starting load for old $HMC through SSH (not Rest API)"
      if [ $HMC_PARALLEL_RUN -eq 1 ]; then
        $PERL -w $BINDIR/lpar2rrd.pl 2>>$ERRLOG   | tee $INPUTDIR/logs/load_power.log
      else
        eval '$PERL -w $BINDIR/lpar2rrd.pl 2>>$ERRLOG | tee -a $INPUTDIR/logs/load_power.log' &
      fi
    done
  fi
fi

#
# wait until all HMC and vcenter jobs finish
#

if [ $HMC_PARALLEL_RUN -gt 1 ]; then
  echo "jobs -l        : " # just print jobs status
  jobs -l

  for pid in `jobs -l |sed -e 's/+//g' -e 's/-//g'|awk '{print $2}'|egrep -iv "stop|daemon|rrdtool|vi |vim |vmware_run.sh"`
  do
    if [ `egrep "^$pid$" "$TMPDIR_LPAR/lpar2rrd-daemon.pid" 2> /dev/null|wc -l` -gt 0 ]; then
      echo "Skipping daemon: $pid"
      continue
    fi
    echo "Waiting for HMC: $pid"
    wait $pid
  done
fi

export PREDICTION=1
nohup $PERL -w $BINDIR/prediction.pl 2>>$ERRLOG 1>> $INPUTDIR/logs/prediction.out &

#
# Create custom graphs
#

if [ $HTML -eq 0 ]; then
  if [ $CUSTOM_GRP -eq 0 ]; then
    # let it run only once and on the back-end, just to avoid any problem when it runc over an hour on VMware
    if [ -s "$TMPDIR_LPAR/custom.pid" ]; then
      PID=`cat "$TMPDIR_LPAR/custom.pid"|sed 's/ //g'`
      if [ ! "$PID"x = "x" -a `echo $PID | sed  's/[0-9].*//'| egrep -v "^$"|wc -l` -eq 0 ]; then
        run=`ps -ef|grep custom.pl| egrep -v "grep |vi | vim "|grep $PID|wc -l`
        if [ $run -eq 0 ]; then
          date > $INPUTDIR/logs/custom.log
          nohup $PERL -w $BINDIR/custom.pl 2>>$ERRLOG | tee -a $INPUTDIR/logs/custom.log &
        else
          echo "Custom group: not run now, other run is running"
        fi
      else
        date>> $INPUTDIR/logs/custom.log
        nohup $PERL -w $BINDIR/custom.pl 2>>$ERRLOG | tee -a $INPUTDIR/logs/custom.log &
      fi
    else
      date > $INPUTDIR/logs/custom.log
      nohup $PERL -w $BINDIR/custom.pl 2>>$ERRLOG | tee -a $INPUTDIR/logs/custom.log &
    fi
  else
    # manual run, leave it on fronted together with errors
    $PERL -w $BINDIR/custom.pl
    ret=$?
    if [ ! $ret -eq 0 ]; then
      DATE=`date`
      echo "$DATE: an error in $PERL -w $BINDIR/custom.pl: $ret" >> $ERRLOG
    fi
  fi
fi

#
# Check RMC connectivity of all lpars
# It runs just once a day (first run after the midnight)
#
if [ $HTML -eq 0 -a $CUSTOM_GRP -eq 0 ] && [ x"$HMC_LIST_API" = "x" ]; then
  $PERL -w $BINDIR/rmc.pl 2>>$ERRLOG | tee -a $INPUTDIR/logs/load_power.log
  echo "RMC from load.sh"
fi



#
# configuration hmc api
#
last_conf="$INPUTDIR/tmp/restapi/last_configuration"
if [ -f $last_conf ]; then
  timestamp=`$PERL -e '$inp=shift;$v = (stat("$inp"))[9]; print "$v\n";' "$last_conf"`
  if [ "$(( $(date +"%s") - $timestamp ))" -gt "300" ]; then
    rm "$INPUTDIR/tmp/restapi/last_configuration"
  fi
fi

#
# Daily lpar data check
# It runs just once a day (first run after the midnight)
#
if [ $HTML -eq 0 -a $CUSTOM_GRP -eq 0 ]; then
  nohup $PERL -w $BINDIR/daily_lpar_check.pl 2>>$ERRLOG | tee -a $INPUTDIR/logs/load_power.log &
  if [[ -f "$INPUTDIR/tmp/restapi/last_configuration" ]]; then
    rm "$INPUTDIR/tmp/restapi/last_configuration"
  fi
fi

#
# Generate TOP10 for OracleVM/OVirt/OracleDB etc
# It runs just once a day (first run after the midnight)
#
if [ $HTML -eq 0 -a $CUSTOM_GRP -eq 0 ]; then
  $PERL -w $BINDIR/gen_topten.pl 2>>$ERRLOG | tee -a $INPUTDIR/logs/topten.log
fi

#
# Daily lpar count
#
if [ $HTML -eq 0 -a $CUSTOM_GRP -eq 0 ]; then
  $PERL -w $BINDIR/daily_lpars_count.pl 2>>$ERRLOG | tee -a $INPUTDIR/logs/load_power.log
fi

#
# Trim logs error.log*|output.log-*
#
if [ $HTML -eq 0 -a $CUSTOM_GRP -eq 0 ]; then
  $PERL -w $BINDIR/trimlogs.pl 2>>$ERRLOG
fi

#
#
# Install/Update web frontend
#


$BINDIR/install-html.sh power | tee -a $INPUTDIR/logs/load_power.log
ret=$?
if [ ! $ret -eq 0 ]; then
  echo "`date` : An error occured in install-html.sh, return code: $ret" >> $ERRLOG
fi


# create a menu.txt
#if [ $HTML -eq 1 ]; then
#  echo "" > $INPUTDIR/tmp/menu_power_pl.txt
#  echo "" > $INPUTDIR/tmp/tempmenu.txt
#  $PERL $INPUTDIR/bin/power-menu.pl "$hmc" "$managedname" "$REST_API" "$IVM"
#  cat "$INPUTDIR/tmp/menu_power_pl.txt" >> $INPUTDIR/tmp/tempmenu.txt 2>>$ERRLOG
#  cat "$INPUTDIR/tmp/menu.txt" >> $INPUTDIR/tmp/tempmenu.txt 2>>$ERRLOG
#  cp $INPUTDIR/tmp/tempmenu.txt $INPUTDIR/tmp/menu.txt
#  rm $INPUTDIR/tmp/tempmenu.txt
#fi


cp -f $INPUTDIR/logs/load_xenserver.log $INPUTDIR/logs/load_xenserver.prev 2>/dev/null
rm -f $INPUTDIR/logs/load_xenserver.log
cp -f $INPUTDIR/load_xenserver.out $INPUTDIR/logs 2>/dev/null
$BINDIR/install-html.sh xenserver | tee -a $INPUTDIR/logs/load_xenserver.log
ret=$?
if [ ! $ret -eq 0 ]; then
  echo "`date` : An error occured in install-html.sh, return code: $ret" >> $ERRLOG
fi

cp -f $INPUTDIR/logs/load_nutanix.log $INPUTDIR/logs/load_nutanix.prev 2>/dev/null
rm -f $INPUTDIR/logs/load_nutanix.log
cp -f $INPUTDIR/load_nutanix.out $INPUTDIR/logs 2>/dev/null
$BINDIR/install-html.sh nutanix | tee -a $INPUTDIR/logs/load_nutanix.log
ret=$?
if [ ! $ret -eq 0 ]; then
  echo "`date` : An error occured in install-html.sh, return code: $ret" >> $ERRLOG
fi

cp -f $INPUTDIR/logs/load_aws.log $INPUTDIR/logs/load_aws.prev 2>/dev/null
rm -f $INPUTDIR/logs/load_aws.log
cp -f $INPUTDIR/load_aws.out $INPUTDIR/logs 2>/dev/null
$BINDIR/install-html.sh aws | tee -a $INPUTDIR/logs/load_aws.log
ret=$?
if [ ! $ret -eq 0 ]; then
  echo "`date` : An error occured in install-html.sh, return code: $ret" >> $ERRLOG
fi

cp -f $INPUTDIR/logs/load_gcloud.log $INPUTDIR/logs/load_gcloud.prev 2>/dev/null
rm -f $INPUTDIR/logs/load_gcloud.log
cp -f $INPUTDIR/load_gcloud.out $INPUTDIR/logs 2>/dev/null
$BINDIR/install-html.sh gcloud | tee -a $INPUTDIR/logs/load_gcloud.log
ret=$?
if [ ! $ret -eq 0 ]; then
  echo "`date` : An error occured in install-html.sh, return code: $ret" >> $ERRLOG
fi

cp -f $INPUTDIR/logs/load_azure.log $INPUTDIR/logs/load_azure.prev 2>/dev/null
rm -f $INPUTDIR/logs/load_azure.log
cp -f $INPUTDIR/load_azure.out $INPUTDIR/logs 2>/dev/null
$BINDIR/install-html.sh azure | tee -a $INPUTDIR/logs/load_azure.log
ret=$?
if [ ! $ret -eq 0 ]; then
  echo "`date` : An error occured in install-html.sh, return code: $ret" >> $ERRLOG
fi

cp -f $INPUTDIR/logs/load_kubernetes.log $INPUTDIR/logs/load_kubernetes.prev 2>/dev/null
rm -f $INPUTDIR/logs/load_kubernetes.log
cp -f $INPUTDIR/load_kubernetes.out $INPUTDIR/logs 2>/dev/null
$BINDIR/install-html.sh kubernetes | tee -a $INPUTDIR/logs/load_kubernetes.log
ret=$?
if [ ! $ret -eq 0 ]; then
  echo "`date` : An error occured in install-html.sh, return code: $ret" >> $ERRLOG
fi

cp -f $INPUTDIR/logs/load_openshift.log $INPUTDIR/logs/load_openshift.prev 2>/dev/null
rm -f $INPUTDIR/logs/load_openshift.log
cp -f $INPUTDIR/load_openshift.out $INPUTDIR/logs 2>/dev/null
$BINDIR/install-html.sh openshift | tee -a $INPUTDIR/logs/load_openshift.log
ret=$?
if [ ! $ret -eq 0 ]; then
  echo "`date` : An error occured in install-html.sh, return code: $ret" >> $ERRLOG
fi

cp -f $INPUTDIR/logs/load_cloudstack.log $INPUTDIR/logs/load_cloudstack.prev 2>/dev/null
rm -f $INPUTDIR/logs/load_cloudstack.log
cp -f $INPUTDIR/load_cloudstack.out $INPUTDIR/logs 2>/dev/null
$BINDIR/install-html.sh cloudstack | tee -a $INPUTDIR/logs/load_cloudstack.log
ret=$?
if [ ! $ret -eq 0 ]; then
  echo "`date` : An error occured in install-html.sh, return code: $ret" >> $ERRLOG
fi

cp -f $INPUTDIR/logs/load_proxmox.log $INPUTDIR/logs/load_proxmox.prev 2>/dev/null
rm -f $INPUTDIR/logs/load_proxmox.log
cp -f $INPUTDIR/load_proxmox.out $INPUTDIR/logs 2>/dev/null
$BINDIR/install-html.sh proxmox | tee -a $INPUTDIR/logs/load_proxmox.log
ret=$?
if [ ! $ret -eq 0 ]; then
  echo "`date` : An error occured in install-html.sh, return code: $ret" >> $ERRLOG
fi

$BINDIR/install-html.sh docker | tee -a $INPUTDIR/logs/load_docker.log
ret=$?
if [ ! $ret -eq 0 ]; then
  echo "`date` : An error occured in install-html.sh, return code: $ret" >> $ERRLOG
fi

cp -f $INPUTDIR/logs/load_fusioncompute.log $INPUTDIR/logs/load_fusioncompute.prev 2>/dev/null
rm -f $INPUTDIR/logs/load_fusioncompute.log
cp -f $INPUTDIR/load_fusioncompute.out $INPUTDIR/logs 2>/dev/null
$BINDIR/install-html.sh fusioncompute | tee -a $INPUTDIR/logs/load_fusioncompute.log
ret=$?
if [ ! $ret -eq 0 ]; then
  echo "`date` : An error occured in install-html.sh, return code: $ret" >> $ERRLOG
fi

cp -f $INPUTDIR/logs/load_ovirt.log $INPUTDIR/logs/load_ovirt.prev 2>/dev/null
rm -f $INPUTDIR/logs/load_ovirt.log
cp -f $INPUTDIR/load_ovirt.out $INPUTDIR/logs 2>/dev/null
$BINDIR/install-html.sh ovirt | tee -a $INPUTDIR/logs/load_ovirt.log
ret=$?
if [ ! $ret -eq 0 ]; then
  echo "`date` : An error occured in install-html.sh, return code: $ret" >> $ERRLOG
fi

cp -f $INPUTDIR/logs/load_oracledb.log $INPUTDIR/logs/load_oracledb.prev 2>/dev/null
rm -f $INPUTDIR/logs/load_oracledb.log
cp -f $INPUTDIR/load_oracledb.out $INPUTDIR/logs 2>/dev/null
$BINDIR/install-html.sh oracledb | tee -a $INPUTDIR/logs/load_oracledb.log
ret=$?
if [ ! $ret -eq 0 ]; then
  echo "`date` : An error occured in install-html.sh, return code: $ret" >> $ERRLOG
fi

cp -f $INPUTDIR/logs/load_postgres.log $INPUTDIR/logs/load_postgres.prev 2>/dev/null
rm -f $INPUTDIR/logs/load_postgres.log
cp -f $INPUTDIR/load_postgres.out $INPUTDIR/logs 2>/dev/null
$BINDIR/install-html.sh postgres | tee -a $INPUTDIR/logs/load_postgres.log
ret=$?
if [ ! $ret -eq 0 ]; then
  echo "`date` : An error occured in install-html.sh, return code: $ret" >> $ERRLOG
fi

cp -f $INPUTDIR/logs/load_db2.log $INPUTDIR/logs/load_db2.prev 2>/dev/null
rm -f $INPUTDIR/logs/load_db2.log
cp -f $INPUTDIR/load_db2.out $INPUTDIR/logs 2>/dev/null
$BINDIR/install-html.sh db2 | tee -a $INPUTDIR/logs/load_db2.log
ret=$?
if [ ! $ret -eq 0 ]; then
  echo "`date` : An error occured in install-html.sh, return code: $ret" >> $ERRLOG
fi

cp -f $INPUTDIR/logs/load_sqlserver.log $INPUTDIR/logs/load_sqlserver.prev 2>/dev/null
rm -f $INPUTDIR/logs/load_sqlserver.log
cp -f $INPUTDIR/load_sqlserver.out $INPUTDIR/logs 2>/dev/null
$BINDIR/install-html.sh sqlserver | tee -a $INPUTDIR/logs/load_sqlserver.log
ret=$?
if [ ! $ret -eq 0 ]; then
  echo "`date` : An error occured in install-html.sh, return code: $ret" >> $ERRLOG
fi

cp -f $INPUTDIR/logs/load_oraclevm.log $INPUTDIR/logs/load_oraclevm.prev 2>/dev/null
rm -f $INPUTDIR/logs/load_oraclevm.log
cp -f $INPUTDIR/load_oraclevm.out $INPUTDIR/logs 2>/dev/null
$BINDIR/install-html.sh oraclevm | tee -a $INPUTDIR/logs/load_oraclevm.log
ret=$?
if [ ! $ret -eq 0 ]; then
  echo "`date` : An error occured in install-html.sh, return code: $ret" >> $ERRLOG
fi

cp -f $INPUTDIR/logs/load_hyperv.out $INPUTDIR/logs/load_hyperv.prev 2>/dev/null
rm -f $INPUTDIR/logs/load_hyperv.out 2>/dev/null
cp -f $INPUTDIR/load_hyperv.out $INPUTDIR/logs 2>/dev/null
$BINDIR/install-html.sh windows | tee -a $INPUTDIR/logs/load_windows.log
ret=$?
if [ ! $ret -eq 0 ]; then
  echo "`date` : An error occured in install-html.sh windows, return code: $ret" >> $ERRLOG
fi

#
# Heatmap ( must be behind install-html.sh as it relys on actual menu.txt)
#
if [ $HTML -eq 0 -a $CUSTOM_GRP -eq 0 ]; then
  nohup $PERL -w $BINDIR/heatmap.pl power 2>>$ERRLOG | tee -a $INPUTDIR/logs/load_power.log &
fi

#
# Reporter
#
if [ $HTML -eq 0 -a $CUSTOM_GRP -eq 0 ]; then
  cp -f $INPUTDIR/reports/reporter.output.log INPUTDIR/reports/reporter.output.prev 2>/dev/null
  $PERL -w $BINDIR/reporter.pl 2>>$INPUTDIR/reports/reporter.error.log | tee $INPUTDIR/reports/reporter.output.log
fi

#
# Check of lpars which CPU utilization overcome their CPU limits
# It runs just once a day (first run after the midnight)
# It might take a long time therefore it is behind menu creation to allow tool usage after upgrade
#
if [ $HTML -eq 0 -a $CUSTOM_GRP -eq 0 ]; then
  if [ $UPGRADE -eq 1 ]; then
    echo ""
    #echo "You can use GUI since now, Ctrl-F5 in the browser"
    echo "Resource Configuration Advisor has been started on the background"
    echo "It might take about an hour in big environments till it finishes"
    echo ""
  fi
  LC_NUMERIC=C
  export LC_NUMERIC
  if [ ! x"$MAX_CHECK_IBMPOWER" = "x" ]; then
    if [ $MAX_CHECK_IBMPOWER -eq 0 ]; then
      echo "skip max-check.pl due to export MAX_CHECK_IBMPOWER=0 set"
    else
      nohup $PERL -w $BINDIR/max-check.pl 2>>$ERRLOG 1>> $INPUTDIR/logs/load_power.log &
    fi
  else
    nohup $PERL -w $BINDIR/max-check.pl 2>>$ERRLOG 1>> $INPUTDIR/logs/load_power.log &
  fi
  nohup $PERL -w $BINDIR/max-check_vm.pl 2>>$ERRLOG 1>> $INPUTDIR/logs/load_vmware.log &
fi


#
# sample_rate-daily.sh
# switched off, it does not work perfectly (still hanging in timeout)
#
#if [ $HTML -eq 0 -a $CUSTOM_GRP -eq 0 ]; then
#  DATE=`date`
#  echo "start sample   : sample_rate-daily.sh once a day : $DATE"
#  $BINDIR/sample_rate-daily.sh
#fi




# XorMon load data to SQLite
# Power
if [ ! "$XORMON"x = "x" ]; then
  if [ "$XORMON" != "0" ]; then
    $PERL -w $BINDIR/power-json2db.pl 2>>$ERRLOG
  fi
fi
# Power CMC
if [ ! "$XORMON"x = "x" ]; then
  if [ "$XORMON" != "0" ]; then
    $PERL -w $BINDIR/cmc-json2db.pl 2>>$ERRLOG
  fi
fi
# Solaris
if [ -d "$INPUTDIR/data/Solaris" ]; then
  if [ ! "$XORMON"x = "x" ]; then
    if [ "$XORMON" != "0" ]; then
      $PERL -w $BINDIR/solaris_menu2db.pl 2>>$ERRLOG
    fi
  fi
fi
# hyperv windows
if [ -d "$INPUTDIR/data/windows" ]; then
  if [ ! "$XORMON"x = "x" ]; then
    if [ "$XORMON" != "0" ]; then
      $PERL -w $BINDIR/windows_menu2db.pl 2>>$ERRLOG
    fi
  fi
fi
# Linux
if [ -d "$INPUTDIR/data/Linux--unknown" ]; then
  if [ ! "$XORMON"x = "x" ]; then
    if [ "$XORMON" != "0" ]; then
      $PERL -w $BINDIR/linux_menu2db.pl 2>>$ERRLOG
    fi
  fi
fi
# XorMon delete old data from SQLite
if [ ! "$XORMON"x = "x" ]; then
    if [ "$XORMON" != "0" ]; then
      if [ "$DEMO"x = "x" ]; then
        $PERL -w $BINDIR/db-cleanup.pl 2>>$ERRLOG
      fi
  fi
fi
# Docker
if [ -d "$INPUTDIR/data/Docker" ]; then
  DERRLOG=$INPUTDIR/logs/error.log-docker
  CDERRLOG=$INPUTDIR/logs/erased.log-docker
  if [ ! "$XORMON"x = "x" ]; then
    if [ "$XORMON" != "0" ]; then
      $PERL -w $BINDIR/docker-json2db.pl 2>>$DERRLOG
    fi
  fi
  $PERL -w $BINDIR/docker-cleanup.pl 2>>$CDERRLOG
fi

#
# Error handling
#

if [ -f $ERRLOG ]; then
  ERR_END=`grep -v nohup $ERRLOG |wc -l | awk '{print $1}'`
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


# user defined script if needed
if [ `ls -l $INPUTDIR/bin/user_script*.sh 2>/dev/null|wc -l` -gt 0 ]; then
  for uscript in $INPUTDIR/bin/user_script*.sh
  do
    echo "Start user script: $uscript"
    $uscript
  done
fi

edate=`date`
echo "date end all   : $edate"


sleep 1;

exit 0

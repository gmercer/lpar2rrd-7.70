#!/bin/ksh
#set -x 

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

if [ ! x"$INPUTDIR" = "x" ]; then
  CFG="$INPUTDIR/etc/lpar2rrd.cfg"
else
  CFG="$pwd/$path/lpar2rrd.cfg"
fi
. $CFG

# Load "magic" setup
if [ -f `dirname $0`/etc/.magic ]; then
  . `dirname $0`/etc/.magic
fi

if [ "$#" -eq 1 ]; then
  HMC_PAR=$1
fi

cleanup()
{
  echo "Exiting on alarm"
  exit 2
}


trap "cleanup" ALRM
trap "cleanup" TERM

if [ -f "$pwd/$path/$HMC" ]; then
  # HMC_LIST contains a name of file where HMC are listed
  HMC_LIST=`cat $pwd/$path/$HMC_LIST`
fi

if [ -f "$HMC_LIST" ]; then
  # HMC_LIST contains a name of file where HMC are listed
  HMC_LIST=`cat $HMC_LIST`
fi

HMC_LIST=`$PERL $INPUTDIR/bin/hmc_list.pl --old` #21.11.2018 - use HMC_LIST from HostConfiguration
if [ x"$HMC_LIST" = "x" ]; then
  echo "No HMC CLI (ssh) based hosts found in the UI Host Configuration. Add your HMC CLI ssh hosts via the UI."
  echo "Check the docu: http://www.lpar2rrd.com/IBM-Power-Systems-performance-monitoring-installation.htm"
  exit
fi

TMP=/var/tmp/sample_rate.$$
TMP_HMC=/var/tmp/sample_rate-HMC.$$
rm -f $TMP $TMP_HMC

if [ ! "$HMC_PAR"x = "x" ]; then #allow sample rate to test only one HMC, insert $1 into HMC_LIST
  HMC_LIST=$HMC_PAR
fi

if [ "$HMC_LIST" = "hmc1 sdmc1 ivm1" ]; then
  # default stuff
  echo "No HMC has been found"
  echo "Add your HMC in parameter HMC_LIST in etc/lpar2rrd.cfg"
  exit 1
fi

#echo "Access HMC \"$HMC_LIST\" as user $HMC_USER, if there appears a prompt for password then allow ssh-key access as per docu."
#echo "SSH cmd: $SSH <HMC> \"export LANG=en_US; lslparutil -s s -r lpar -n 1 -m <server>  -F time\" "
count=0

CONNTEST="bin/conntest.pl"
if [ ! -f $CONNTEST ]; then
  CONNTEST="./conntest.pl"
fi

for i in $HMC_LIST
do
  prom=0
  count=1
  HMC_USER=`$PERL $INPUTDIR/bin/hmc_list.pl --username $i`
  HMC_SSH_CMD=`$PERL $INPUTDIR/bin/hmc_list.pl --ssh $i`
  if [ "$HMC_SSH_CMD"x = "x" ]; then
    HMC_SSH_CMD=$SSH
  fi
  SSH=$HMC_SSH_CMD

  # remove "-q" on purpose  to see errors
  SSH=`echo $SSH |sed -e 's/"//g' -e 's/ -q/ /g'` 

  if [ "$HMC_USER"x = "x" ]; then
    echo "NOK : HMC: $i , HMC user is not defined, check: GUI --> setting icon on the top-right --> IBM Power --> $i --> and set HMC user"
    continue
  fi

  if [ -f $CONNTEST ]; then
    perl $CONNTEST $i 22 >/dev/null
    if [ $? -eq 1 ]; then
      #echo "Continue with the others"
      echo "NOK : HMC: $i has closed ssh port, allow network connectivity to $i:22"
      continue
    fi
  fi
  echo ""
  rm -f $TMP_HMC
  time1=`$SSH -l $HMC_USER "$i" "date" 2>$TMP_HMC` # there must not be "-q"!!
  if [ -f $TMP_HMC ]; then
    if [ `wc -l $TMP_HMC| awk '{print $1}'` -gt 0 ]; then
      err=`cat $TMP_HMC`
      echo "NOK : $i : ERROR: $err"
      echo "     Assure this cmd return a HMC date: $SSH -l $HMC_USER $i \"date\""
      continue
    fi
  fi

  MNAMES=`$SSH -q -l $HMC_USER "$i" "lssyscfg -r sys -F name" 2>/dev/null|sed 's/ /%20/g'|xargs`
  server_no=0
  if [ "$MNAMES"x = "x" ]; then
    echo "NOK : $i : no any server has not been identified on this HMC"
    echo "     Assure this cmd list servers: $SSH -l $HMC_USER $i \"lssyscfg -r sys -F name\""
    echo "     This is returning it now:"
    $SSH -l $HMC_USER "$i" "lssyscfg -r sys -F name"
    continue
  else 
    echo "OK : $i : HMC_time=$time1"
  fi
  for j in $MNAMES
  do
    server_no=1
    j_space=`echo $j|sed 's/%20/ /g'`
    # Exclude excluded systems
    eval 'echo "$MANAGED_SYSTEMS_EXCLUDE" | egrep "^$j_space:|:$j:|:$j$|^$j$" >/dev/null 2>&1'
    if [ $? -eq 0 ]; then
      #if [ $DEBUG -eq 1 ]; then echo "Excluding      : $j_space"; fi
      continue
    fi

    # just a test without "-q"
    rm -f $TMP_HMC
    RATE=`$SSH -l $HMC_USER $i "export LANG=en_US; lslparutil -r config -m '"$j_space"' -F sample_rate " 2> $TMP_HMC`
    if [ -f $TMP_HMC ]; then
      if [ `wc -l $TMP_HMC| awk '{print $1}'` -gt 0 ]; then
        err=`cat $TMP_HMC`
        echo "NOK : $i : ERROR: $err"
        echo "     Assure this cmd list servers: $SSH -l $HMC_USER $i \"export LANG=en_US; lslparutil -r config -m $j_space -F sample_rate \""
        continue
      fi
    fi

    RATE=`$SSH -q -l $HMC_USER $i "export LANG=en_US; lslparutil -r config -m '"$j_space"' -F sample_rate " 2> $TMP_HMC`
    if [ $SAMPLE_RATE -ne $RATE ]; then
      echo " NOK : $RATE : $j_space : sample rate is $RATE, should be $SAMPLE_RATE"
      echo " $SSH -l hscroot $i \"chlparutil -r config -m $j_space -s $SAMPLE_RATE\"" >> $TMP
    else 
      if [ $SAMPLE_RATE -gt 0 ]; then
        time2=`$SSH -q -l $HMC_USER "$i" "export LANG=en_US; lslparutil -s s -r lpar -n 1 -m '$j_space'  -F time" | sed 's/"//g'`
        if [ `echo "$time2"| grep -i result| wc -l | sed 's/ //g'` -gt 0 ]; then
          echo "  NOK : $RATE : $j_space : server_time=$time2, it must return valid time"
          echo "        command: $SSH -l $HMC_USER $i \"lslparutil -s s -r lpar -n 1 -m '$j_space'  -F time\""
        else
          echo "  OK : $RATE : $j_space : server_time=$time2"
        fi
      else
        echo " NOK : $RATE : $j_space : sample rate is $RATE, should be $SAMPLE_RATE"
        echo " $SSH -l hscroot $i \"chlparutil -r config -m $j_space -s $SAMPLE_RATE\"" >> $TMP
      fi
    fi
  done
done

if [ $count -eq 0 ]; then
  echo ""
  echo "No HMC has been found"
  echo "Add your HMC in parameter HMC_LIST in etc/lpar2rrd.cfg"
  exit 1
fi

if [ -f $TMP ]; then
  echo ""
  echo ""
  echo "Here are commands to fix it, just copy/paste it and provide password when you are prompted"
  echo "After fixing it run the script again to check whether it is ok now"
  cat $TMP

  echo ""
  echo ""
  echo "Optionaly you can do the same job globaly per the HMC"
  for i in `cut -f5  -d " " $TMP|sort|uniq`
  do
    echo " ssh -l hscroot $i <HMC name> \"chlparutil -r config -s $SAMPLE_RATE\""
  done
  rm -f $TMP
  exit 1
fi

echo ""
echo "Assure that HMC_time is more less same as server_time on its servers"
echo "Refer to http://www.lpar2rrd.com/HMC-CLI-time.htm when times are different (30mins+)"
echo ""

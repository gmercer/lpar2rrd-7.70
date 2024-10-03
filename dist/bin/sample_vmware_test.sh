#!/bin/ksh

# test of communication with vmware
# vmware connection taken from etc/lpar2rrd.cfg
# credentials must be set in advance
#

pwd=`pwd`
if [ -d "etc" ]; then
   path="etc"
   path_bin="bin"
else
  if [ -d "../etc" ]; then
    path="../etc"
    path_bin="../bin"
  else
    if [ ! "$INPUTDIR"x = "x" ]; then
      cd $INPUTDIR >/dev/null
      if [ -d "etc" ]; then
         path="etc"
         path_bin="bin"
      else
        if [ -d "../etc" ]; then
          path="../etc"
          path_bin="../bin"
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
HMC=`$PERL -MHostCfg -e 'print HostCfg::getHostConnections("VMware")'`


echo "Going to check VMWARE as user $HMC_USER, credentials must be set in advance"
for i in $HMC
do
  VI_SERVER=$i
  export VI_SERVER
  echo ""
  echo "Test of host: $VI_SERVER"
  loop_test="$pwd/$path_bin/vmware_loop_test.pl"
  perl_res=`$PERL "$loop_test"`
  echo "$perl_res"

done


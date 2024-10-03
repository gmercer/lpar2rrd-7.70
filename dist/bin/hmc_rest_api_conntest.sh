#!/bin/ksh

inputdir=$INPUTDIR

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

PERL5LIB=$BINDIR:$PERL5LIB
export PERL5LIB


if [ `uname -a|grep AIX|wc -l` -gt 0 ]; then
  # AIX tricks to get it work together with VMware
  PERL5LIB=$INPUTDIR/lib:$PERL5LIB
  export PERL5LIB

  # /usr/lib must be the first, but /opt/freeware/lib must be included as well
  LIBPATH=/usr/lib:/opt/freeware/lib:$LIBPATH
  export LIBPATH
fi

if [ -f "$pwd/$path/.magic" ]; then
  . "$pwd/$path/.magic"
fi

cleanup()
{
  echo "Exiting on alarm"
  exit 2
}

trap "cleanup" ALRM
trap "cleanup" TERM


SRATE=`egrep "SAMPLE_RATE=" $CFG|grep -v "#"| tail -1|awk -F = '{print $2}'`

# remove "-o PreferredAuthentications=publickey" and "-q" on purpose  to see errors
SSH=`egrep "SSH=" $CFG|grep -v "#"| tail -1| sed -e 's/SSH=//' -e 's/-o PreferredAuthentications=publickey//' -e 's/ -q / /'`
#echo "$SSH"

if [ -f "$HMC" ]; then
  # HMC contains a name of file where HMC are listed
  HMC=`cat $HMC`
fi


TMP=/var/tmp/sample_rate.$$
rm -f $TMP

SSH=`echo $SSH|sed 's/"//g'`
#echo "Going to check HMC as user $HMC_USER, if there appears a prompt for password then allow ssh-key access as per docu."
count=0

#export LIBPATH=/usr/lib:/opt/freeware/lib:$LIBPATH

export LIBPATH=/usr/lib:/opt/freeware/lib:$LIBPATH
# cmd='bin/sample_rate.sh'
# . $cmd

HMC_LIST=`$PERL $INPUTDIR/bin/hmc_list.pl`
echo "OK HMC:$HMC_LIST"

if [ $# -eq 0 ]
 then
 $PERL $INPUTDIR/bin/hmc-restapi-test.pl
fi
if [ $# -eq 5 ]
  then
  $PERL $INPUTDIR/bin/hmc-restapi-test.pl $1 $2 $3 $4 $5
fi

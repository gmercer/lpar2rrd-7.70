#!/bin/ksh
# Script for obtaining support data
#

# Needed to determine options passed to tar commands
UNAME=`uname`

# Load LPAR2RRD configuration
echo "loading LPAR2RRD configuration"
. `dirname $0`/lpar2rrd.cfg

if [ "$INPUTDIR" = "." ]; then
   INPUTDIR=`pwd`
   export INPUTDIR
fi
TMP="support.list"
SUPPORT_OUT=support.out

cd $INPUTDIR

oslevel -s > $SUPPORT_OUT 2>/dev/null
uname -a >> $SUPPORT_OUT
$RRDTOOL -h >> $SUPPORT_OUT

if [ x"$HMC_LIST" = "x" ]; then
  echo "HMC_LIST does not seem to be set up, correct it in lpar2rrd.cfg"
  exit 0
fi
echo "" >> $SUPPORT_OUT
echo "" >> $SUPPORT_OUT
echo "" >> $SUPPORT_OUT

export LANG=en_US
for HMC in $HMC_LIST
do
  echo "Working for $HMC"
  echo "lshmc -V" >> $SUPPORT_OUT
  $SSH $HMC_USER@$HMC  "lshmc -V" >> $SUPPORT_OUT
  echo "lshmc -v" >> $SUPPORT_OUT
  $SSH $HMC_USER@$HMC  "lshmc -v" >> $SUPPORT_OUT
  echo "lslparutil -r config  -F name,sample_rate" >> $SUPPORT_OUT
  $SSH $HMC_USER@$HMC  "lslparutil -r config  -F name,sample_rate" >> $SUPPORT_OUT
  echo "ls -lRa /opt/hsc/data/utilization" >> $SUPPORT_OUT
  $SSH $HMC_USER@$HMC  "ls -lRa /opt/hsc/data/utilization" >> $SUPPORT_OUT

  # that does not work form managed names with a space within names 
  for i in `$SSH $HMC_USER@$HMC  "lssyscfg -r sys -F name"`
  do
    # Exclude excluded systems
    eval 'echo "$MANAGED_SYSTEMS_EXCLUDE" | egrep "^$i:|:$i:|:$i$|^$i$" >/dev/null 2>&1'
    if [ $? -eq 0 ]; then
      echo "Excluding $HMC:$i"
      continue
    fi

    echo "-----------------------------" >> $SUPPORT_OUT
    echo "Working for $HMC_USER@$HMC $i" >> $SUPPORT_OUT
    echo "-----------------------------" >> $SUPPORT_OUT
    echo "Gathering last data from $HMC:$i"
    $SSH $HMC_USER@$HMC  "lslparutil -s s -r lpar -h 1 -m $i -F time,lpar_name,curr_proc_units,curr_procs,curr_sharing_mode,entitled_cycles,capped_cycles,uncapped_cycles,shared_cycles_while_active  --filter \"event_types=sample\"" >> $SUPPORT_OUT
  done
  echo "" >> $SUPPORT_OUT
  echo "" >> $SUPPORT_OUT
  echo "" >> $SUPPORT_OUT
done

echo "Gathering input files with latest data"
find data -name "*in-[m|d|h]" >$TMP
if [ $UNAME = "AIX" ]; then 
  tar -c -L $TMP -f support-in.tar
else
  tar -c -T $TMP -f support-in.tar
fi

echo "Gathering list of data files"
find data -print -type d -exec ls -l {} \; > support-ls

echo "Creating archive"
if [ -f load.out ]; then
  tar cf support.tar lpar2rrd.cfg error.log load.out support-in.tar $SUPPORT_OUT support-ls
else
  tar cf support.tar lpar2rrd.cfg error.log support-in.tar $SUPPORT_OUT support-ls
fi
echo "Ouput is in support.tar"
echo "Pls compress it : # gzip -9 support.tar, or # compress support.tar"

rm -f support-in.tar support-ls $SUPPORT_OUT $TMP



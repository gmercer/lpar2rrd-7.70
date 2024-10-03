#!/bin/ksh
#
# . /home/lpar2rrd/lpar2rrd/etc/lpar2rrd.cfg; sh ./bin/as400_job_clean.sh
#
# Load LPAR2RRD configuration
#

UN=`uname -a`
TWOHYPHENS="--"
if [[ $UN == *"SunOS"* ]]; then TWOHYPHENS=""; fi # problem with basename param on Solaris

if [ -f etc/lpar2rrd.cfg ]; then
  . etc/lpar2rrd.cfg
else
  if [ -f `dirname $0`/etc/lpar2rrd.cfg ]; then
    . `dirname $0`/etc/lpar2rrd.cfg
  else
    if [ -f `dirname $0`/../etc/lpar2rrd.cfg ]; then
      . `dirname $0`/../etc/lpar2rrd.cfg
    fi
  fi
fi

if [ `echo $INPUTDIR|egrep "bin$"|wc -l` -gt 0 ]; then
  INPUTDIR=`dirname $INPUTDIR`
fi

if [ ! -d "$INPUTDIR" ]; then
  echo "Does not exist \$INPUTDIR; have you loaded environment properly? . /home/lpar2rrd/lpar2rrd/etc/lpar2rrd.cfg"
  exit 1
fi


for as400_space in `find $INPUTDIR/data -type d -name \*--AS400-- | sed 's/ /===space===/g'`
do
  as400=`echo "$as400_space"| sed 's/===space===/ /g'`
  if [ -d "$as400/JOB" ]; then
    as400_clean=`echo "$as400" | sed -e 's/--AS400--//' -e 's/--unknown//'`
    as400_base=`basename $TWOHYPHENS $as400_clean`
    echo "Removing job data: $as400_base ( rm -f $as400/JOB/* )"
    echo "[y/n]"
    read yes
    if [ ! "$yes" = "Y" -a ! "$yes" = "y" ]; then
      continue
    fi
    rm -f $as400/JOB/*
  fi
done

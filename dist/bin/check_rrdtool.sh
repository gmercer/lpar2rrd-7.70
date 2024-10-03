#!/bin/ksh
# usage:
# cd /home/lpar2rrd/lpar2rrd
# ksh ./bin/check_rrdtool.sh
#  --> then it prints wrong source files on the stderr (screen) ...
#
# ERROR: fetching cdp from rra at /lpar2rrd/bin/lpar2rrd.pl line 2329
# ERROR: reading the cookie off /opt/lpar2rrd/data/Carolina-9117-MMD-SN1064D47/unxhmcpa001/fairlane_new_test.rrm faild at
# ERROR: short read while reading header rrd->stat_head
#
# You can schedulle it regulary once a day from crontab, it will send an email to $EMAIL addr
# 0 0 * * * cd /home/lpar2rrd/lpar2rrd; ./bin/check_rrdtool.sh > /var/tmp/check_rrdtool.out 2>&1

UN=`uname -a`
TWOHYPHENS="--"
if [[ $UN == *"SunOS"* ]]; then TWOHYPHENS=""; fi # problem with basename param on Solaris

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


if [ -f etc/.magic ]; then
  . etc/.magic
  # set that in etc/.magic to avoid overwriting after the upgrade
  #EMAIL="me@me.com"
  #EMAIL_ON=1
  # export EMAIL EMAIL_ON
else
  EMAIL_ON=0
fi

if [ ! -f $RRDTOOL ]; then
  echo "ERROR: $RRDTOOL variable must be set up in etc/lpar2rrd.cfg"
  exit 1
fi

SILENT=0
if [ ! "$1"x = "x" ]; then
  if [ "$1" = "silent" ]; then
    SILENT=1
  fi
fi

addr=data
error=0
tmp="/tmp/check_rrdtool.sh-$$"

os_aix=` uname -a|grep AIX|wc -l`
if [ $os_aix -eq 0 ]; then
  ECHO_OPT="-e"
else
  ECHO_OPT=""
fi
if [ -f /usr/bin/echo ]; then
  ECHO="/usr/bin/echo $ECHO_OPT"
else
  ECHO="echo $ECHO_OPT"
fi


if [ $SILENT -eq 0 ]; then
  echo "Data checking"| tee -a $tmp
fi

if [ $SILENT -eq 0 ]; then
  #
  # Silent run does it all in once 
  #
  count=0
  thousand=0
  for DIR in $addr/* # go thriugh all subdirs at first to avoid problem in big environments
  do
    for RRDFILE_space in `find "$DIR" -name \*\.\[a\-z]\[a\-z\]\[a\-z\] |egrep -v "\.json|\.out$|\.csv$|\.vmr$|\.fcs$|\.lan$|\.gpa$|\.col$|\.hea$|\.txt$|\.vmh$|\.cfg$|\.tmp$|\.rrk$|\.rrl$|\.rri$"|sed 's/ /===space===/g'`
    do
      RRDFILE=`echo "$RRDFILE_space"|sed 's/===space===/ /g'`
      RRDFILE_dir=`basename $TWOHYPHENS "$RRDFILE"`
  
      if [ ! -f "$RRDFILE" ]; then
        continue
      fi
      if [ `file "$RRDFILE"| grep "ASCII text"| wc -l| sed 's/ //g'` -eq 1 ]; then
        continue
      fi
  
      # *.rrt might have zero size, skipt them
      if [ `echo "$RRDFILE" | egrep "\.rrt" >/dev/null| wc -l | sed 's/ //g'` ]; then
        if [ ! -s "$RRDFILE" ]; then
          continue
        fi
      fi
  
      if [ `echo "$RRDFILE"|grep no_hmc|wc -l` -eq 1 -a `echo "$RRDFILE"|egrep "\.rrh$"| wc -l` -eq 1 ]; then
        # this could have 0 size, it is ok
        continue
      fi
      (( count = count + 1 ))
      (( thousand = thousand + 1 ))
      if [ $thousand -eq 100 ]; then
        $ECHO  ".\c"
        thousand=0
      fi
      last=`$RRDTOOL last "$RRDFILE" 2>>$tmp-error`
      if [ $? -gt 0 ]; then
        (( error = error + 1 ))
        if [ $SILENT -eq 0 ]; then
          echo "  rm $RRDFILE"| tee -a $tmp
          #ls -l "$RRDFILE"| tee -a $tmp
        else
          echo "rm  $RRDFILE" >> $tmp
        fi
        continue
      fi
      AVG="AVERAGE"
      if [ `echo "$RRDFILE"| egrep ".xrm$"| wc -l | sed 's/ //g'` -eq 1 ]; then
        AVG="MAX"
      fi
      $RRDTOOL fetch "$RRDFILE" $AVG -s $last-60 -e $last-60 >/dev/null 2>>$tmp-error
        if [ $? -gt 0 ]; then
        (( error = error + 1 ))
        if [ $SILENT -eq 0 ]; then
          echo "  rm $RRDFILE"| tee -a $tmp
          #ls -l "$RRDFILE"| tee -a $tmp
        else
          echo "rm  $RRDFILE" >> $tmp
          fi
        continue
      fi
  
      # RRDTool error: ERROR: fetching cdp from rra (sometime can be corrupted only old records when "fetch" and "last" are ok
      rr_1st_var=`$RRDTOOL info "$RRDFILE"  |egrep "^ds"|head -1|sed -e 's/ds\[//' -e 's/\].*//'`
      RRDFILE_colon=`echo "$RRDFILE"|sed 's/:/\\\:/g'`
      $RRDTOOL graph mygraph.png -a PNG --start 900000000  --end=now  DEF:x="$RRDFILE_colon":$rr_1st_var:$AVG PRINT:x:$AVG:%2.1lf >/dev/null  2>>$tmp-error
      if [ $? -gt 0 ]; then
        (( error = error + 1 ))
        if [ $SILENT -eq 0 ]; then
          echo "  rm $RRDFILE"| tee -a $tmp
          #ls -l "$RRDFILE"| tee -a $tmp
        else
          echo "rm  $RRDFILE" >> $tmp
        fi
        continue
      fi
    done
  done
  
  # IBM Power files with longer suffic than 3 characters: rasm, rapm, ralm, rahm, rasrm
  for DIR in $addr/* # go thriugh all subdirs at first to avoid problem in big environments
  do
    for RRDFILE_space in `find "$DIR" -name \*\.ra\[s\|p\|l\|h\]\* |sed 's/ /===space===/g'`
    do
      RRDFILE=`echo "$RRDFILE_space"|sed 's/===space===/ /g'`
      RRDFILE_dir=`basename $TWOHYPHENS "$RRDFILE"`
  
      if [ ! -f "$RRDFILE" ]; then
        continue
      fi
      if [ `file "$RRDFILE"| grep "ASCII text"| wc -l| sed 's/ //g'` -eq 1 ]; then
        continue
      fi
  
      # *.rrt might have zero size, skipt them
      if [ `echo "$RRDFILE" | egrep "\.rrt" >/dev/null| wc -l | sed 's/ //g'` ]; then
        if [ ! -s "$RRDFILE" ]; then
          continue
        fi
      fi
  
      if [ `echo "$RRDFILE"|grep no_hmc|wc -l` -eq 1 -a `echo "$RRDFILE"|egrep "\.rrh$"| wc -l` -eq 1 ]; then
        # this could have 0 size, it is ok
        continue
      fi
      (( count = count + 1 ))
      (( thousand = thousand + 1 ))
      if [ $thousand -eq 100 ]; then
        $ECHO  ".\c"
        thousand=0
      fi
      last=`$RRDTOOL last "$RRDFILE" 2>>$tmp-error`
      if [ $? -gt 0 ]; then
        (( error = error + 1 ))
        if [ $SILENT -eq 0 ]; then
          echo "  rm $RRDFILE"| tee -a $tmp
          #ls -l "$RRDFILE"| tee -a $tmp
        else
          echo "rm  $RRDFILE" >> $tmp
        fi
        continue
      fi
      AVG="AVERAGE"
      if [ `echo "$RRDFILE"| egrep ".xrm$"| wc -l | sed 's/ //g'` -eq 1 ]; then
        AVG="MAX"
      fi
      $RRDTOOL fetch "$RRDFILE" $AVG -s $last-60 -e $last-60 >/dev/null 2>>$tmp-error
        if [ $? -gt 0 ]; then
        (( error = error + 1 ))
        if [ $SILENT -eq 0 ]; then
          echo "  rm $RRDFILE"| tee -a $tmp
          #ls -l "$RRDFILE"| tee -a $tmp
        else
          echo "rm  $RRDFILE" >> $tmp
          fi
        continue
      fi
  
      # RRDTool error: ERROR: fetching cdp from rra (sometime can be corrupted only old records when "fetch" and "last" are ok
      rr_1st_var=`$RRDTOOL info "$RRDFILE"  |egrep "^ds"|head -1|sed -e 's/ds\[//' -e 's/\].*//'`
      RRDFILE_colon=`echo "$RRDFILE"|sed 's/:/\\\:/g'`
      $RRDTOOL graph mygraph.png -a PNG --start 900000000  --end=now  DEF:x="$RRDFILE_colon":$rr_1st_var:$AVG PRINT:x:$AVG:%2.1lf >/dev/null  2>>$tmp-error
      if [ $? -gt 0 ]; then
        (( error = error + 1 ))
        if [ $SILENT -eq 0 ]; then
          echo "  rm $RRDFILE"| tee -a $tmp
          #ls -l "$RRDFILE"| tee -a $tmp
        else
          echo "rm  $RRDFILE" >> $tmp
        fi
        continue
      fi
      done
    done
    echo ""
  fi
  









if [ $SILENT -eq 0 ]; then
  echo "Checked files: $count"| tee -a $tmp
fi

if [ $error -eq 0 ]; then
  echo ""
  echo "No corrupted files have been found"
  echo ""
  rm -f $tmp
else
  echo ""
  if [ $SILENT -eq 0 ]; then
    echo "Printed files are corrupted, remove them manually"
    if [ ! "$EMAIL_ON"x = "x" ]; then
      if [ $EMAIL_ON -eq 1 ]; then
        cat $tmp| mailx -s "LPAR2RRD corrupted files" $EMAIL
      fi
    fi
    rm -f $tmp
    echo ""
  else
    echo "*********************************************************************************"
    echo "There are $error corrupted RRDTool database files, delete them to avoid problems!"
    echo "Get the list of files: cat $tmp"
    echo "Get the list errors: cat $tmp-error"
    echo "*********************************************************************************"
  fi
fi


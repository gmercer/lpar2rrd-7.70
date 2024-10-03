#!/bin/sh
#
# LPAR2RRD update script
# usage : ./update.sh
#         ./update.sh nocheck  # consistency check of RRDTool files is excluded
#
#

LANG=C
export LANG

check=1
if [ ! "$1"x = "x" ]; then
  if [ "$1" = "nocheck" ]; then
    check=0
  fi
fi

AWK="awk"
if [ `uname -s` = "SunOS" ]; then
  AWK="nawk"
fi

os_aix=` uname -s|egrep "^AIX$"|wc -l|sed 's/ //g'`

UN=`uname`
TWOHYPHENS="--"
if [ "$UN" = "SunOS" ]; then TWOHYPHENS=""; fi # problem with basename param on Solaris

# test if "ed" command does not exist, it might happen especially on some Linux distros
ed << END 2>/dev/null 1>&2
q
END
if [ $? -gt 0 ]; then
  echo "ERROR: "ed" command does not seem to be installed or in $PATH"
  echo "Exiting ..."
  exit 1
fi

lpm_find ()
{
  if [ ! -f $dup_tmp ]; then
    #something is wrong
    cat /dev/null > $dup_tmp
    return
  fi

  for i in `cat $dup_tmp|sort`
  do
    server_org=`echo "$i"|cut -d "/" -f1`
    hmc_org=`echo "$i"|cut -d "/" -f2`
    lpar_org=`echo "$i"|cut -d "/" -f3`

    if [ ! -f "$INPUTDIR/data/$server_org/$hmc_org/$lpar_org.$RR" ]; then
      # some proble, skipping
      server_prev=$server_org
      continue
    fi

    server_prev="" # to aviod HMc duall setup

    # nested loop, must be run each lpar with all which have been found, there might be more than 2 lpars
    for ii in `cat $dup_tmp`
    do

      server=`echo "$ii"|cut -d "/" -f1`
      hmc=`echo "$ii"|cut -d "/" -f2`
      lpar=`echo "$ii"|cut -d "/" -f3`

      if [ "$server" = "$server_org" -a "$hmc" = "$hmc_org" -a "$lpar" = "$lpar_org" ]; then
        # it is same record as already processing one, skipping
        server_prev=$server
        continue
      fi

      if [ ! "$hmc" = "$hmc_org" ]; then
        # LPM must be under same HMC/SDMC, exceptions are only IVM
        if [ ! -f $INPUTDIR/data/$server/$hmc/IVM -o ! -f $INPUTDIR/data/$server_org/$hmc_org/IVM ]; then
          continue
        fi
      fi

      if [ ! -f "$INPUTDIR/data/$server/$hmc/$lpar.$RR" ]; then
        # some proble, skipping
        server_prev=$server
        continue
      fi

      if [ "$server" = "$server_org" ]; then
        # probably dual HMC setup, skip this then
        server_prev=$server
        continue
      fi

      if [ "$server_prev"x = "x" ]; then
        server_prev=$server
      else
        if [ "$server_prev" = "$server" ]; then
          continue # due to dual HMC setup
        fi
      fi

      # exclude VIOses
      if [ -f $INPUTDIR/data/$server/$hmc/lpm-exclude.txt ]; then
        egrep "^$lpar\$" $INPUTDIR/data/$server/$hmc/lpm-exclude.txt >/dev/null
        if [ $? -eq 0 ]; then
	  #if [ $DEBUG ]; then echo "LPM new lpar   : $lpar $server:$hmc - looks like VIO, excluding it" ; fi
          continue
        fi
      fi
      if [ -f $INPUTDIR/data/$server_org/$hmc_org/lpm-exclude.txt ]; then
        egrep "^$lpar_org\$" $INPUTDIR/data/$server_org/$hmc_org/lpm-exclude.txt >/dev/null
        if [ $? -eq 0 ]; then
	  #if [ $DEBUG ]; then echo "LPM new lpar   : $lpar_org $server_org:$hmc_org - looks like VIO, excluding it" ; fi
          continue
        fi
      fi
      #if [ $DEBUG ]; then echo "LPM new lpar   : $lpar : $hmc_org:$server_org --> $hmc:$server"; fi
      (( LPM_FOUND = LPM_FOUND + 1 )) # LPM found
      if [ $LPM_FOUND -gt 5  ]; then
        break
      fi
      server_prev=$server
    done
  done

  cat /dev/null > $dup_tmp 	# clean out temp file
  return 0
}

lpm_support ()
{
  dup_tmp=/tmp/lpar2rrd-dup-$$.txt #tmp file
  cat /dev/null > $dup_tmp
  cd $INPUTDIR/data
  lpar_prev=""

  for i in `find . -name \*$RR -exec ls {} \;| sed 's/^\.\///g'|sort -t "/" -k 3`
  do
    server=`echo "$i"|cut -d "/" -f1`
    if [ -h "$server" ]; then
      continue
    fi

    hmc=`echo "$i"|cut -d "/" -f2`
    lpar_all=`echo "$i"|cut -d "/" -f3`
    lpar1=`basename $TWOHYPHENS "$lpar_all" .$RR`
    lpar=`basename $TWOHYPHENS "$lpar1" .rrh` # must be there

    # exclude not LPM stuff
    echo "$lpar" | egrep "^SharedPool[0-9]*" >/dev/null 2>&1
    if [ $? -eq 0 -o "$lpar" = "mem" -o "$lpar" = "pool" ]; then
      if [ `wc -l $dup_tmp|$AWK '{print $1}'` -gt 1 ]; then
        lpm_find
      fi
      continue
    fi

    if [ "$lpar_prev"x = "x" ]; then
      echo "$server/$hmc/$lpar" > $dup_tmp
      lpar_prev=$lpar
      continue
    fi

    if [ "$lpar" = "$lpar_prev" ]; then
      echo "$server/$hmc/$lpar" >> $dup_tmp # add next lpar
    else
      if [ `wc -l $dup_tmp|$AWK '{print $1}'` -gt 1 ]; then
        lpm_find
      fi
      echo "$server/$hmc/$lpar" > $dup_tmp # start new lpar
      lpar_prev=$lpar
    fi

  done

  if [ `wc -l $dup_tmp|$AWK '{print $1}'` -gt 1 ]; then
    lpm_find
  fi
  rm -f $dup_tmp

}

DEBUG_UPD=0
ID=`id -un`

if [ $os_aix -eq 0 ]; then
  ECHO_OPT="-e"
else
  ECHO_OPT=""
fi

umask 022

if [ -d $HOME/lpar2rrd ]; then
  HOME1=$HOME/lpar2rrd
fi

if [ -f "$HOME/etc/.magic" ]; then
  .  $HOME/etc/.magic
fi
if [ -f "/home/lpar2rrd/lpar2rrd/etc/.magic" ]; then
  .  /home/lpar2rrd/lpar2rrd/etc/.magic
fi

if [ `ps -ef|egrep "/load.sh|"|egrep -v "grep"|wc -l` -gt 0 ]; then
  kill `ps -ef|egrep "load.sh"|egrep -v "grep"|$AWK '{print $2}'|xargs` 2>/dev/null
  sleep 2
fi

if [ -f "$HOME/.lpar2rrd_home" ]; then
  HOME1=`cat "$HOME/.lpar2rrd_home"`
fi

if [ ! "$HOME1"x = "x" -a -d "$HOME1" ]; then
  echo $ECHO_OPT "Where is LPAR2RRD actually located [$HOME1]: \c"
else
  if [ x"$HOME1" = "x" ]; then
    echo $ECHO_OPT "Where is LPAR2RRD actually located: \c"
  else
    echo $ECHO_OPT "Where is LPAR2RRD actually located [$HOME1]: \c"
  fi
fi

# check if it is running from the image, then no wait for the input
if [ "$VM_IMAGE"x = "x" ]; then
  read HOMELPAR
else
  if [ $VM_IMAGE -eq 0 ]; then
    read HOMELPAR
  else
    echo ""
    echo "$HOME1"
  fi
fi

if [ x"$HOMELPAR" = "x" ]; then
  HOMELPAR=$HOME1
fi

# Check if it runs under the right user
check_file="$HOMELPAR/bin/lpar2rrd.pl"
if [ ! -f "$check_file" ]; then
  check_file="$HOMELPAR/lpar2rrd.pl"
  if [ ! -f "$check_file" ]; then
    echo "LPAR2RRD product has not been found in: $HOMELPAR"
    exit 1
  fi
fi

if [ `uname -s` = "SunOS" ]; then
  # Solaris does not have -X
  install_user=`ls -l "$check_file"|$AWK '{print $3}'`
else
  install_user=`ls -lX "$check_file"|$AWK '{print $3}'` # must be X to do not cut user name to 8 chars
fi

running_user=`id |$AWK -F\( '{print $2}'|$AWK -F\) '{print $1}'`
if [ ! "$install_user" = "$running_user" ]; then
  echo "You probably trying to run it under wrong user"
  echo "LPAR2RRD files are owned by : $install_user"
  echo "You are : $running_user"
  echo "LPAR2RRD update should run only under user which owns installed package"
  echo "Do you want to really continue? [n]:"
  # check if it is running from the image, then no wait for the input
  if [ "$VM_IMAGE"x = "x" ]; then
    read answer
  else
    if [ $VM_IMAGE -eq 0 ]; then
      read answer
    else
      echo ""
      echo "Exiting as a wrong user ..."
      exit 1
    fi
  fi
  if [ "$answer"x = "x" -o "$answer" = "n" -o "$answer" = "N" ]; then
    exit 1
  fi
fi

CFG24=$HOMELPAR/etc/lpar2rrd.cfg
CFG=$HOMELPAR/etc/lpar2rrd.cfg
cp -p $CFG $CFG-backup

if [ ! -f "$CFG" ]; then
  CFG24=$HOMELPAR/lpar2rrd.cfg
  CFG=$HOMELPAR/lpar2rrd.cfg
  if [ ! -f "$CFG" ]; then
    CFG=$HOMELPAR/load.sh
    if [ ! -f "$CFG" ]; then
      echo "Could not find config file $CFG, LPAR2RRD is not installed there, exiting"
      exit 1
    fi
  fi
fi

pwd=`pwd`
touch test
if [ ! $? -eq 0 ]; then
  echo "Actual user does not have rights to create files in actual directory: $pwd "
  echo "Fix it and re-run upgrade"
  exit 1
fi
rm -f test


if [ -f lpar2rrd.tar.Z ]; then
  which uncompress >/dev/null 2>&1
  if [ $? -eq 0 ]; then
     uncompress -f lpar2rrd.tar.Z
     if [ ! $? -eq 0 ]; then
       echo "Package uncomress encountered a problem"
       echo "Check if actual user owns directory and if there is enough of disk space"
       echo "Exiting without any change"
       exit 1
     fi
  else
     which gunzip >/dev/null 2>&1
     if [ $? -eq 0 ]; then
       gunzip -f lpar2rrd.tar.Z
       if [ ! $? -eq 0 ]; then
         echo "Package uncomress encountered a problem"
         echo "Check if actual user owns directory and if there is enough of disk space"
         echo "Exiting without any change"
         exit 1
       fi
     else
       echo "Could not locate uncompress or gunzip commands. exiting"
       exit  1
     fi
  fi
fi

if [ -f lpar2rrd.tar ]; then
  echo "Extracting distribution"
  tar xf lpar2rrd.tar
  if [ ! $? -eq 0 ]; then
    echo "Package extraction encountered a problem"
    echo "Check if actual user owns directory and if there is enough of disk space"
    echo "Exiting without any change"
    exit 1
  fi
else
  echo "looks like it is already extracted, tar is missing"
fi

if [ ! -d "dist" ]; then
  echo "There is not \"dist\", data was not extracted properly"
  echo "Check if actual user owns directory and if there is enough of disk space"
  echo "Exiting without any change"
  exit 1
fi

cd dist

# Read original configuration
WEBDIR=`sed 's/#.*$//g' $CFG|egrep "WEBDIR=" | tail -1|$AWK -F = '{print $2}'    |sed -e 's/\//\\\\\\\\\//g' -e 's/ //g'|sed -e 's/	//g' -e 's/ /\\\\ /g'`
DB2_CLI_DRIVER_INSTALL_PATH=`sed 's/#.*$//g' $CFG|egrep "DB2_CLI_DRIVER_INSTALL_PATH=" | tail -1|$AWK -F = '{print $2}'    |sed -e 's/\//\\\\\\\\\//g' -e 's/ //g'|sed -e 's/	//g' -e 's/ /\\\\ /g'`
ORACLE_BASE=`sed 's/#.*$//g' $CFG|egrep "ORACLE_BASE=" | tail -1|$AWK -F = '{print $2}'    |sed -e 's/\//\\\\\\\\\//g' -e 's/ //g'|sed -e 's/	//g' -e 's/ /\\\\ /g'`
ORACLE_HOME=`sed 's/#.*$//g' $CFG|egrep "ORACLE_HOME=" | tail -1|$AWK -F = '{print $2}'    |sed -e 's/\//\\\\\\\\\//g' -e 's/ //g'|sed -e 's/	//g' -e 's/ /\\\\ /g'`
TNS_ADMIN=`sed 's/#.*$//g' $CFG|egrep "TNS_ADMIN=" | tail -1|$AWK -F = '{print $2}'    |sed -e 's/\//\\\\\\\\\//g' -e 's/ //g'|sed -e 's/	//g' -e 's/ /\\\\ /g'`
HMC_USER=`sed 's/#.*$//g' $CFG|egrep "HMC_USER=" | tail -1|$AWK -F = '{print $2}'|sed -e 's/	//g' -e 's/ /\\\\ /g'`
HMC_HOSTAME=`sed 's/#.*$//g' $CFG|egrep "HMC_HOSTAME=" | tail -1|$AWK -F = '{print $2}'|sed 's/ /\\\\ /g'|sed -e 's/	//g' -e 's/"/\\\\"/g'`
HMC_LIST=`sed 's/#.*$//g' $CFG|egrep "HMC_LIST=" | tail -1|$AWK -F = '{print $2}'|sed -e 's/\//\\\\\\\\\//g' -e 's/ /\\\\ /g'|sed -e 's/	//g' -e 's/"/\\\\"/g'`
IVM_LIST=`sed 's/#.*$//g' $CFG|egrep "IVM_LIST=" | tail -1|$AWK -F = '{print $2}'|sed -e 's/\//\\\\\\\\\//g' -e 's/ /\\\\ /g'|sed -e 's/	//g' -e 's/"/\\\\"/g'`
MANAGED_SYSTEMS_EXCLUDE=`sed 's/#.*$//g' $CFG|egrep "MANAGED_SYSTEMS_EXCLUDE=" | tail -1|$AWK -F = '{print $2}'|sed 's/ /\\\\ /g'|sed -e 's/	//g' -e 's/"/\\\\"/g'`
PERL=`sed 's/#.*$//g' $CFG|egrep "PERL=" | tail -1|$AWK -F = '{print $2}'|sed -e 's/\//\\\\\\\\\//g' -e 's/ //g'|sed -e 's/	//g' -e 's/ /\\\\ /g'`
# PERL_act save actual perl with no backslashes in path
PERL_act=`sed 's/#.*$//g' $CFG|egrep "PERL=" | tail -1|$AWK -F = '{print $2}'|sed -e 's/ //g'|sed -e 's/	//g' -e 's/ /\\\\ /g'`
RRD=`sed 's/#.*$//g' $CFG|egrep "RRDTOOL=" | tail -1|$AWK -F = '{print $2}' |sed -e 's/\//\\\\\\\\\//g' -e 's/ //g'|sed -e 's/	//g' -e 's/ /\\\\ /g'`
RRD_act=`sed 's/#.*$//g' $CFG|egrep "RRDTOOL=" | tail -1|$AWK -F = '{print $2}' |sed -e 's/ //g'|sed -e 's/        //g' -e 's/ /\\\\ /g'`
SAMPLE_RATE=`sed 's/#.*$//g' $CFG|egrep "SAMPLE_RATE=" | tail -1|$AWK -F = '{print $2}'|sed -e 's/	//g' -e 's/ /\\\\ /g'`
HWINFO=`sed 's/#.*$//g' $CFG|egrep "HWINFO=" | tail -1|$AWK -F = '{print $2}'|sed -e 's/	//g' -e 's/ /\\\\ /g'`
SYS_CHANGE=`sed 's/#.*$//g' $CFG|egrep "SYS_CHANGE=" | tail -1|$AWK -F = '{print $2}'|sed -e 's/	//g' -e 's/ /\\\\ /g'`
RRDHEIGHT=`sed 's/#.*$//g' $CFG|egrep "RRDHEIGHT=" $CFG|egrep -v "#|DASHB_"| tail -1|$AWK -F = '{print $2}'|sed -e 's/	//g' -e 's/ /\\\\ /g'`
RRDWIDTH=`sed 's/#.*$//g' $CFG|egrep "RRDWIDTH=" $CFG|egrep -v "#|DASHB_"| tail -1|$AWK -F = '{print $2}'|sed -e 's/	//g' -e 's/ /\\\\ /g'`
DASHB_RRDHEIGHT=`sed 's/#.*$//g' $CFG|egrep "DASHB_RRDHEIGHT=" | tail -1|$AWK -F = '{print $2}'|sed -e 's/	//g' -e 's/ /\\\\ /g'`
DASHB_RRDWIDTH=`sed 's/#.*$//g' $CFG|egrep "DASHB_RRDWIDTH=" | tail -1|$AWK -F = '{print $2}'|sed -e 's/	//g' -e 's/ /\\\\ /g'`
PERL5LIB=`sed 's/#.*$//g' $CFG|egrep "PERL5LIB=" | tail -1|$AWK -F = '{print $2}'|sed -e 's/ //g'`
DEBUG=`sed 's/#.*$//g' $CFG|egrep "DEBUG=" | tail -1|$AWK -F = '{print $2}'|sed -e 's/	//g' -e 's/ /\\\\ /g'`
EXPORT_TO_CSV=`sed 's/#.*$//g' $CFG|egrep "EXPORT_TO_CSV=" | tail -1|$AWK -F = '{print $2}'|sed -e 's/	//g' -e 's/ /\\\\ /g'`
PICTURE_COLOR=`sed 's/#.*$//g' $CFG|egrep "PICTURE_COLOR=" | tail -1|$AWK -F = '{print $2}'|sed -e 's/	//g' -e 's/ /\\\\ /g'`
HEA=`sed 's/#.*$//g' $CFG|egrep "HEA=" $CFG|grep -v "STEP_HEA"|grep -v "#"| tail -1|$AWK -F = '{print $2}'|sed -e 's/	//g' -e 's/ /\\\\ /g'`
STEP_HEA=`sed 's/#.*$//g' $CFG|egrep "STEP_HEA=" | tail -1|$AWK -F = '{print $2}'|sed -e 's/	//g' -e 's/ /\\\\ /g'`
TOPTEN=`sed 's/#.*$//g' $CFG|egrep "TOPTEN=" | grep -v VMOTION_TOPTEN| tail -1|$AWK -F = '{print $2}'|sed -e 's/	//g' -e 's/ /\\\\ /g'`
VMOTION_TOPTEN=`sed 's/#.*$//g' $CFG|egrep "VMOTION_TOPTEN=" | tail -1|$AWK -F = '{print $2}'|sed -e 's/	//g' -e 's/ /\\\\ /g'`
LPM=`sed 's/#.*$//g' $CFG|egrep "LPM=" | tail -1|$AWK -F = '{print $2}'|sed -e 's/	//g' -e 's/ /\\\\ /g'`
LPAR2RRD_AGENT_DAEMON=`sed 's/#.*$//g' $CFG|egrep "LPAR2RRD_AGENT_DAEMON=" | tail -1|$AWK -F = '{print $2}'|sed -e 's/	//g' -e 's/ /\\\\ /g'`
LPAR2RRD_AGENT_DAEMON_PORT=`sed 's/#.*$//g' $CFG|egrep "LPAR2RRD_AGENT_DAEMON_PORT=" | tail -1|$AWK -F = '{print $2}'|sed -e 's/	//g' -e 's/ /\\\\ /g'`
LPAR2RRD_AGENT_DAEMON_IP=`sed 's/#.*$//g' $CFG|egrep "LPAR2RRD_AGENT_DAEMON_IP=" | tail -1|$AWK -F = '{print $2}'|sed -e 's/	//g' -e 's/ /\\\\ /g'`
LPM_LPAR_EXCLUDE=`sed 's/#.*$//g' $CFG|egrep "LPM_LPAR_EXCLUDE=" | tail -1|$AWK -F = '{print $2}'|sed 's/ /\\\\ /g'|sed -e 's/	//g' -e 's/"/\\\\"/g'`
LPM_SERVER_EXCLUDE=`sed 's/#.*$//g' $CFG|egrep "LPM_SERVER_EXCLUDE=" | tail -1|$AWK -F = '{print $2}'|sed 's/ /\\\\ /g'|sed -e 's/	//g' -e 's/"/\\\\"/g'`
LPM_HMC_EXCLUDE=`sed 's/#.*$//g' $CFG|egrep "LPM_HMC_EXCLUDE=" | tail -1|$AWK -F = '{print $2}'|sed 's/ /\\\\ /g'|sed -e 's/	//g' -e 's/"/\\\\"/g'`
SSH_WEB_IDENT=`sed 's/#.*$//g' $CFG|egrep "SSH_WEB_IDENT=" | tail -1|$AWK -F = '{print $2}' |sed -e 's/-q//' -e 's/\//\\\\\\\\\//g' -e 's/ //g'|sed -e 's/	//g' -e 's/ /\\\\ /g'`
#Do not use here $AWK -F = '{print $2}'  as there might be more "=" inside the param !!!
SSH=`sed 's/#.*$//g' $CFG|egrep "SSH=" | tail -1| sed -e 's/^.*SSH=//' -e 's/"//g' -e 's/	//g'`
#SSH=`sed 's/#.*$//g' $CFG|egrep "SSH=" | tail -1|$AWK -F = '{print $2}' |sed -e 's/-q//' -e 's/\//\\\\\\\\\//g' |sed -e 's/	//g' -e 's/ /\\\\ /g'`
#SSH=`sed 's/#.*$//g' $CFG|egrep "SSH=" | tail -1|$AWK -F = '{print $2}'|sed 's/ /\\\\ /g'|sed -e 's/	//g' -e 's/"/\\\\"/g'`
ACL_ADMIN_GROUP=`sed 's/#.*$//g' $CFG|egrep "ACL_ADMIN_GROUP=" | tail -1|$AWK -F = '{print $2}'|sed -e 's/\//\\\\\\\\\//g' -e 's/ /\\\\ /g' -e 's/"/\\\\"/g' -e 's/	//g'`
ACL_GRPLIST_VARNAME=`sed 's/#.*$//g' $CFG|egrep "ACL_GRPLIST_VARNAME=" | tail -1|$AWK -F = '{print $2}'|sed -e 's/\//\\\\\\\\\//g' -e 's/ /\\\\ /g' -e 's/"/\\\\"/g' -e 's/	//g'`
LEGEND_HEIGHT=`sed 's/#.*$//g' $CFG|egrep "LEGEND_HEIGHT=" | tail -1|$AWK -F = '{print $2}'|sed -e 's/	//g' -e 's/ /\\\\ /g'`
PDF_PAGE_SIZE=`sed 's/#.*$//g' $CFG|egrep "PDF_PAGE_SIZE=" | tail -1|$AWK -F = '{print $2}'|sed -e 's/	//g' -e 's/ /\\\\ /g'`


if [ "$SSH"x = "x" ]; then
  # in case it is not there for any reason
  SSH="ssh -q"
fi

# if OpenSSH then place there: -o ConnectTimeout=80 -o StrictHostKeyChecking=no -o PreferredAuthentications=publickey
if [ `$SSH -V 2>&1|grep -i OpenSSH|wc -l` -eq 1 ]; then
  if [ `echo "$SSH"|grep -i ConnectTimeout|wc -l` -eq 0 ]; then
    SSH_tmp="$SSH"
    SSH=`echo "$SSH_tmp -o ConnectTimeout=80 -o StrictHostKeyChecking=no -o PreferredAuthentications=publickey "`
  fi
  if [ `echo "$SSH"|grep -i SendEnv|wc -l` -eq 0 ]; then
    SSH_tmp="$SSH"
    SSH=`echo "$SSH_tmp -o SendEnv=no "`
  fi
fi
if [ `echo "$SSH"|grep -- "-q" |wc -l` -eq 0 ]; then
  # "-q" must be there always
  SSH_tmp=$SSH
  SSH="$SSH_tmp -q "
fi
SSH_tmp=$SSH

# Solaris ssh does not recognize -o SendEnv=no
if [ `uname|grep SunOS|wc -l|  sed 's/ //g'` -eq 1 ]; then
  SSH=`echo $SSH_tmp|sed -e 's/\//\\\\\\\\\//g' -e 's/ /\\\\ /g' -e 's/^/\\\\"/'  -e 's/$/\\\\ \\\\"/'|sed 's/ -o SendEnv=no/ /g'`
else
  SSH=`echo $SSH_tmp|sed -e 's/\//\\\\\\\\\//g' -e 's/ /\\\\ /g' -e 's/^/\\\\"/'  -e 's/$/\\\\ \\\\"/'`
fi



WEBDIR_PLAIN=`echo $WEBDIR | sed 's/\\\//g'`

if [ -f ../version.txt ]; then
  # actually installed version
  version_new=`cat ../version.txt|tail -1|sed 's/ .*//'`
fi

if [ -f "$HOMELPAR/etc/version.txt" ]; then
  version=`egrep "[0-9]\.[0-9]" $HOMELPAR/etc/version.txt|tail -1|sed 's/ .*//'`
  VER=`egrep "[0-9]\.[0-9]" $HOMELPAR/etc/version.txt|tail -1|sed 's/ .*//'|sed 's/-.*$//'`  # get only major version info
else
  # old version of getting version
  if [ `grep "# version " $CFG|wc -l` -eq 1 ]; then
    VER=`egrep "# version " $CFG|tail -1|$AWK '{print $3}'`
  else
    VER=`egrep "version=" $CFG|tail -1|$AWK -F= '{print $2}'`
  fi
  version=$VER
fi

#if [ "$LPM_LPAR_EXCLUDE"X = "X" ]; then
#  LPM_LPAR_EXCLUDE=""
#fi

#if [ "$LPM_SERVER_EXCLUDE"X = "X" ]; then
#  LPM_SERVER_EXCLUDE=""
#fi

#if [ "$LPM_HMC_EXCLUDE"X = "X" ]; then
#  LPM_HMC_EXCLUDE=""
#fi

if [ "$LPAR2RRD_AGENT_DAEMON"X = "X" ]; then
  LPAR2RRD_AGENT_DAEMON=0
fi

if [ "$LPAR2RRD_AGENT_DAEMON_PORT"X = "X" ]; then
  LPAR2RRD_AGENT_DAEMON_PORT=8162
fi

if [ "$LPAR2RRD_AGENT_DAEMON_IP"X = "X" ]; then
  LPAR2RRD_AGENT_DAEMON_IP=0.0.0.0
fi
if [ "$LPM"X = "X" ]; then
  LPM=1
fi
# set LPM=1 after upgrade from free to the full version
#if [ "$LPM" = "0" -a ! -f "$HOMELPAR/bin/premium.pl" -a -f "bin/premium.pl" ]; then
  # only if upgrade is from free to premium version, not when premium to premium
#  LPM=1
#fi

hash_ACL_ADMIN_GROUP="\#ACL_ADMIN_GROUP"
if [ "$ACL_ADMIN_GROUP"X = "X" ]; then
  ACL_ADMIN_GROUP=lpar2rrd-admins
  hash_ACL_ADMIN_GROUP="ACL_ADMIN_GROUP"
fi

hash_ACL_GRPLIST_VARNAME="\#ACL_GRPLIST_VARNAME"
if [ "$ACL_GRPLIST_VARNAME"X = "X" ]; then
  ACL_GRPLIST_VARNAME=AUTHENTICATE_MEMBEROF
  hash_ACL_GRPLIST_VARNAME="ACL_GRPLIST_VARNAME"
fi

if [ "$TOPTEN"X = "X" -o "$TOPTEN" = "10" ]; then
  TOPTEN=50 # new top10 default since 4.60
fi

if [ "$VMOTION_TOPTEN"X = "X"  ]; then
  VMOTION_TOPTEN=100
fi

if [ "$SYS_CHANGE"X = "X" ]; then
  SYS_CHANGE=100
fi

if [ "$RRDHEIGHT"X = "X" ]; then
  RRDHEIGHT=150
fi

if [ "$RRDWIDTH"X = "X" ]; then
  RRDWIDTH=700
fi

if [ "$DASHB_RRDHEIGHT"X = "X" ]; then
  DASHB_RRDHEIGHT=50
fi

if [ "$LEGEND_HEIGHT"X = "X" ]; then
  LEGEND_HEIGHT=120
fi

if [ "$DASHB_RRDWIDTH"X = "X" ]; then
  DASHB_RRDWIDTH=120
fi

if [ "$PDF_PAGE_SIZE"X = "X" ]; then
  PDF_PAGE_SIZE=A4
fi

if [ "$DEBUG"X = "X" ]; then
  DEBUG=1
fi

if [ "$PICTURE_COLOR"X = "X" -o "$PICTURE_COLOR" = "D3D2D2" -o "$PICTURE_COLOR" = "E3E2E2" -o "$PICTURE_COLOR" = "F7FCF8" ]; then
  PICTURE_COLOR=F7F7F7
fi

if [ "$EXPORT_TO_CSV"X = "X" ]; then
  EXPORT_TO_CSV=1
fi

if [ "$SSH_WEB_IDENT"X = "X" ]; then
  #SSH_WEB_IDENT="\\\/home\\\/lpar2rrd\\\/.ssh\\\/realt_rsa"
  SSH_WEB_IDENT=`echo "$HOME/.ssh/realt_rsa"| sed -e 's/\//\\\\\\\\\//g' -e 's/ //g'|sed 's/ /\\\\ /g'`
fi

if [ "$HEA"X = "X" ]; then
  HEA=1
fi

# fix for the bug from old version
if [ $HEA -eq 300 ]; then
  HEA=1
fi

if [ "$SSH"X = "X" ]; then
  SSH=`echo "ssh" |sed -e 's/\//\\\\\\\\\//g' -e 's/ /\\\\ /g' -e 's/^/\\\\"/'  -e 's/$/\\\\ \\\\"/'`
fi

if [ "$DEBUG"X = "X" ]; then
  DEBUG=1
fi

if [ "$STEP_HEA"X = "X" ]; then
  STEP_HEA=300
fi

if [ "$ORACLE_HOME"X = "X" ]; then
  ORACLE_HOME=`echo "/opt/oracle/instantclient_XY"|sed -e 's/\//\\\\\\\\\//g' -e 's/ /\\\\ /g' -e 's/^/\\\\"/'  -e 's/$/\\\\"/'`
fi

if [ "$ORACLE_BASE"X = "X" ]; then
  ORACLE_BASE=`echo "/opt/oracle"|sed -e 's/\//\\\\\\\\\//g' -e 's/ /\\\\ /g' -e 's/^/\\\\"/'  -e 's/$/\\\\"/'`
fi

if [ "$DB2_CLI_DRIVER_INSTALL_PATH"X = "X" ]; then
  DB2_CLI_DRIVER_INSTALL_PATH=`echo "/home/lpar2rrd/db2_cli_odbc_driver/odbc_cli/clidriver"|sed -e 's/\//\\\\\\\\\//g' -e 's/ /\\\\ /g' -e 's/^/\\\\"/'  -e 's/$/\\\\"/'`
fi

if [ "$"X = "X" ]; then
  =300
fi


echo "$PERL5LIB"|grep ":" >/dev/null 2>&1
if [ ! $? -eq 0 ]; then
    # perl/5.8.8 must be always first!
    PERL5LIB=/usr/opt/perl5/lib/site_perl/5.8.8/aix-thread-multi:/usr/lib64/perl5/vendor_perl/5.8.8:/opt/freeware/lib/perl/5.8.8:/opt/freeware/lib/perl/5.8.0:/usr/opt/perl5/lib/site_perl/5.8.2:/usr/lib/perl5/vendor_perl/5.8.5:/usr/share/perl5:/usr/lib/perl5:/usr/opt/perl5/lib/site_perl/5.8.8/aix-thread-multi:/opt/freeware/lib/perl5/vendor_perl/5.8.8/ppc-thread-multi
fi

bit64=`file $PERL_act 2>/dev/null| grep 64-bit| wc -l | sed 's/ //g'`

# add actual paths
# This /usr/opt/perl5/lib/site_perl/5.8.8/aix-thread-multi must be befor /usr/opt/perl5/lib/site_perl/5.10.1/aix-thread-multi when is /opt/freeware/bin/perl used otherwisi is usede wrong SSLeay.so
# (https.pm is not found then)

if [ "$PERL_act" = "/opt/freeware/bin/perl" ]; then
  # AIX, excluded /usr/opt/perl5/lib64/5.28.1 which causing a problem
  PPATH="/usr/opt/perl5/lib/site_perl/5.8.8/aix-thread-multi
/opt/freeware/lib/perl5/vendor_perl/5.8.8/ppc-thread-multi
/usr/opt/perl5/lib/site_perl/5.8.8/aix-thread-multi
/opt/freeware/lib/perl5/site_perl/5.22.0/ppc-aix-thread-multi
/usr/lib64/perl5
/opt/freeware/lib/perl5
/opt/freeware/lib/perl
/opt/freeware/lib/perl5/vendor_perl/5.8.8
/usr/opt/perl5/lib/site_perl
/usr/lib/perl5/vendor_perl
/usr/share/perl5/vendor_perl
/opt/csw/share/perl/csw
/opt/csw/lib/perl/site_perl
/usr/opt/perl5/lib/site_perl/5.8.8/aix-thread-multi
/usr/opt/perl5/lib/site_perl/5.10.1/aix-thread-multi
/opt/freeware/lib/perl5/site_perl/5.22.0
/usr/opt/perl5/lib/site_perl/5.10.1
/usr/opt/perl5/lib/site_perl/5.28.1
/usr/lib64/perl5/vendor_perl"
else
  if [ $bit64 -eq 0 ]; then
    PPATH="/usr/opt/perl5/lib/site_perl/5.8.8/aix-thread-multi
/opt/freeware/lib/perl5/vendor_perl/5.8.8/ppc-thread-multi
/usr/opt/perl5/lib/site_perl/5.8.8/aix-thread-multi
/opt/freeware/lib/perl5/site_perl/5.22.0/ppc-aix-thread-multi
/opt/freeware/lib/perl5
/opt/freeware/lib/perl
/opt/freeware/lib/perl5/vendor_perl/5.8.8
/usr/opt/perl5/lib/site_perl
/usr/lib/perl5/vendor_perl
/usr/share/perl5/vendor_perl
/opt/csw/share/perl/csw
/opt/csw/lib/perl/site_perl
/usr/opt/perl5/lib/site_perl/5.8.8/aix-thread-multi
/usr/opt/perl5/lib/site_perl/5.10.1/aix-thread-multi
/opt/freeware/lib/perl5/site_perl/5.28.0/ppc-aix-thread-multi
/opt/freeware/lib/perl5/site_perl/5.22.0
/usr/opt/perl5/lib
/usr/opt/perl5/lib/site_perl/5.10.1
/usr/opt/perl5/lib/site_perl/5.28.1
/opt/freeware/lib/perl5/5.30/vendor_perl"
  else
    PPATH="/usr/opt/perl5/lib/site_perl/5.8.8/aix-thread-multi
/opt/freeware/lib/perl5/vendor_perl/5.8.8/ppc-thread-multi
/usr/opt/perl5/lib/site_perl/5.8.8/aix-thread-multi
/opt/freeware/lib/perl5/site_perl/5.22.0/ppc-aix-thread-multi
/usr/lib64/perl5
/opt/freeware/lib/perl5
/opt/freeware/lib/perl
/opt/freeware/lib/perl5/vendor_perl/5.8.8
/usr/opt/perl5/lib/site_perl
/usr/lib/perl5/vendor_perl
/usr/share/perl5/vendor_perl
/opt/csw/share/perl/csw
/opt/csw/lib/perl/site_perl
/usr/opt/perl5/lib/site_perl/5.8.8/aix-thread-multi
/usr/opt/perl5/lib/site_perl/5.10.1/aix-thread-multi
/opt/freeware/lib/perl5/site_perl/5.28.0/ppc-aix-thread-multi
/opt/freeware/lib/perl5/site_perl/5.22.0
/usr/opt/perl5/lib64/5.28.1
/usr/opt/perl5/lib64/5.28.0
/usr/opt/perl5/lib64
/usr/opt/perl5/lib
/usr/opt/perl5/lib/site_perl/5.10.1
/usr/opt/perl5/lib/site_perl/5.28.1
/usr/lib64/perl5/vendor_perl
/opt/freeware/lib/perl5/5.30/vendor_perl
/opt/freeware/lib64/perl5/5.30/vendor_perl
/usr/opt/perl5/lib64/site_perl"

  fi
fi

# /opt/csw/share/perl/csw is necessary on Solaris

perl_version=`$PERL_act -v| grep "This is perl"| sed -e 's/^.* (v//' -e 's/) .*//' -e 's/^.* v//' -e 's/ .*//'`
perl_subversion=`$PERL_act -v| grep "This is perl"| sed -e 's/^.* (v//' -e 's/) .*//' -e 's/^.* v//' -e 's/ .*//' -e 's/\.[0-9][0-9]$//' -e 's/\.[0-9]$//' `

PLIB=`for ppath in $PPATH
do
  echo $PERL5LIB|grep "$ppath/$perl_version"  >/dev/null
  if [ ! $? -eq 0  -a -d "$ppath/$perl_version" ]; then
    echo "$ppath/$perl_version"
    echo "$ppath/$perl_version/vendor_perl"
    if [ $os_aix -eq 1 ]; then
      if [ $bit64 -eq 0 ]; then
        echo "$ppath/$perl_version/ppc-aix-thread-multi"
        echo "$ppath/$perl_version/aix-thread-multi"
      else
        echo "$ppath/$perl_version/aix-thread-multi-64all" # this must be behind 32bit!
      fi
    fi
  else
    echo $PERL5LIB|grep "$ppath"  >/dev/null
    if [ ! $? -eq 0  -a -d "$ppath" ]; then
      echo "$ppath"
    fi
  fi

  echo $PERL5LIB|grep "$ppath/$perl_subversion"  >/dev/null
  if [ ! $? -eq 0  -a -d "$ppath/$perl_subversion" ]; then
    echo "$ppath/$perl_subversion"
    echo "$ppath/$perl_subversion/vendor_perl"
    if [ $os_aix -eq 1 ]; then
      if [ $bit64 -eq 0 ]; then
        echo "$ppath/$perl_subversion/ppc-aix-thread-multi"
        echo "$ppath/$perl_subversion/aix-thread-multi"
      else
        echo "$ppath/$perl_subversion/aix-thread-multi-64all" # this must be behind 32bit!
      fi
    fi
  else
    echo $PERL5LIB|grep "$ppath"  >/dev/null
    if [ ! $? -eq 0  -a -d "$ppath" ]; then
      echo "$ppath"
    fi
  fi

done|xargs|sed -e 's/ /\:/g' -e 's/\:\:/\:/g'`

if [ `echo "$PERL5LIB"|grep aix-thread-multi|wc -l` -eq 0 ]; then
  PERL5LIB="$PERL5LIB:/usr/opt/perl5/lib/site_perl/5.8.8/aix-thread-multi"
fi
if [ `echo "$PERL5LIB"|grep ppc-thread-multi|wc -l` -eq 0 ]; then
  PERL5LIB="$PERL5LIB:/opt/freeware/lib/perl5/vendor_perl/5.8.8/ppc-thread-multi"
fi

if [ `echo "$PLIB:$PERL5LIB"|grep "$HOMELPAR/vmware-lib"|wc -l` -eq 0 ]; then
  if [ "$PLIB"x = "x" ]; then
    PERL5LIB=`echo "$HOMELPAR/vmware-lib:$PERL5LIB"`
  else
    PERL5LIB=`echo "$HOMELPAR/vmware-lib:$PLIB:$PERL5LIB"`
  fi
else
  if [ ! "$PLIB"x = "x" ]; then
    PERL5LIB=`echo "$PLIB:$PERL5LIB"`
  fi
fi
if [ `echo "$PERL5LIB"|egrep "^$HOMELPAR/bin"|wc -l` -eq 0 ]; then
  # Placing BINDIR ($HOMELPAR/bin) on start of PERL5LIB : 5.09-21
  PERL5LIB=`echo "$HOMELPAR/bin:$PERL5LIB"`
fi

#if [ $os_aix -gt 0 ]; then
#  # AIX must have $HOMELPAR/lib on start due to https support
#  #  No no, VMware requires $HOMELPAR/lib at the end on AIX!!!
#  if [ `echo "$PERL5LIB"|egrep "^$HOMELPAR/lib:" |wc -l` -eq 0 ]; then
#    PERL5LIB="$HOMELPAR/lib:$PERL5LIB"
#  fi
#else
#fi

# Clean up PERL5LIB, place only existing dirs
PERL5LIB_new=""
for lib_path in `echo $PERL5LIB| sed 's/:/ /g'`
do
  if [ -d "$lib_path" ]; then
    if [ `echo "$PERL5LIB_new" | egrep "$lib_path:|$lib_path$" | wc -l | sed 's/ //g'` -eq 1 ]; then
      continue
    fi
    if [ `echo "$lib_path" | egrep "$HOMELPAR/bin$|$HOMELPAR/vmware-lib$|/usr/opt/perl5/lib/site_perl/5.8.8/aix-thread-multi$|/opt/freeware/lib/perl5/vendor_perl/5.8.8/ppc-thread-multi$" | wc -l | sed 's/ //g'` -eq 1 ]; then
      # exclude $HOMELPAR/bin & $HOMELPAR/vmware-lib; they will be added later on
      continue
    fi
    if [ "$PERL5LIB_new"x = "x" ]; then
      PERL5LIB_new=$lib_path
    else
      PERL5LIB_new=$PERL5LIB_new:$lib_path
    fi
  fi
done

# $HOMELPAR/vmware-lib must be always on the 2nd possition otherwise error 500 might appear
if [ -d /usr/opt/perl5/lib/site_perl/5.8.8/aix-thread-multi -a "$PERL_act" = "/opt/freeware/bin/perl" ]; then
  # /usr/opt/perl5/lib/site_perl/5.8.8/aix-thread-multi must be before the others ontherwise problem with perl-Crypt-SSLeay and TLS 1...
  PERL5LIB=$HOMELPAR/bin:$HOMELPAR/vmware-lib:/opt/freeware/lib/perl5/vendor_perl/5.8.8/ppc-thread-multi:/usr/opt/perl5/lib/site_perl/5.8.8/aix-thread-multi:$PERL5LIB_new
else
  PERL5LIB=$HOMELPAR/bin:$HOMELPAR/vmware-lib:$PERL5LIB_new
fi

# it must be checked again as $HOMELPAR/lib do not have to exist yet if original version was quite old
if [ `echo "$PERL5LIB"|grep "$HOMELPAR/lib" |wc -l` -eq 0 ]; then
  PERL5LIB="$PERL5LIB:$HOMELPAR/lib"
fi

PERL5LIB=`echo "$PERL5LIB"|sed -e 's/::/:/g' -e 's/\//\\\\\\\\\//g' -e 's/ //g'`


if [ "$VER" = "" ]; then
  # very old version did not have version string inside, so putting here something lower than 241
  VER="100"
fi

VER_ORG=`echo $VER|sed 's/\.//g'`

if [ $DEBUG_UPD -eq 1 ]; then
  echo "
	$WEBDIR
	$HMC_USER
	$HMC_LIST
	$HMC_HOSTAME
	$MANAGED_SYSTEMS_EXCLUDE
	$PERL
	$RRDTOOL
	$SRATE
	$VER
	$WEBDIR_PLAIN
	$HWINFO
	$SYS_CHANG
	$RRDHEIGHT
	$RRDWIDTH
	$PERL5LIB
	$PICTURE_COLOR
	$DEBUG
  	$EXPORT_TO_CSV
  	$HEA
  	$STEP_HEA
  	$TOPTEN
  	$VMOTION_TOPTEN
  	$LPM
  	$LPM_LPAR_EXCLUDE
  	$LPM_SERVER_EXCLUDE
  	$LPM_HMC_EXCLUDE
  "
fi

# Original edition: free/full test
free_edition_org=1
if [ ! -f "$HOMELPAR/tmp/menu.txt" ]; then
  echo ""
  echo "Could not found $HOMELPAR/tmp/menu.txt, considering original edition as a Free one"
  echo ""
else
  if [ `egrep "^O:0:" "$HOMELPAR/tmp/menu.txt" | wc -l | sed 's/ //g'` -gt 0 ]; then
    # full version
    free_edition_org=0
  fi
fi

# New edition: free/full test
free_edition_new=1
if [ `echo $pwd| egrep -- "-full|-trial-"| wc -l|  sed 's/ //g'` -eq 1 ]; then
  # full version
  free_edition_new=0
fi


if [ $free_edition_org -eq 0 -a $free_edition_new -eq 1 ]; then
  echo ""
  echo "You are going to install the Free edition over the Enterprise edition!!!"
  echo "Enterprise edition features will be deleted from your instance:"
  echo "Type enter to continue, Ctrl-C to interrupt it"
  # check if it is running from the image, then no wait for the input
  if [ "$VM_IMAGE"x = "x" ]; then
    read full
  else
    if [ $VM_IMAGE -eq 0 ]; then
      read full
    else
      echo "yes"
      full="yes"
    fi
  fi
  rm -f $HOMELPAR/bin/premium* $HOMELPAR/bin/genreport.sh $HOMELPAR/etc/rperf_table.txt $HOMELPAR/bin/premium_lpm_find.pl $HOMELPAR/bin/reporter-premium.pl
  rm -f $HOMELPAR/lpar2rrd-cgi/vcenter-list-cgi.sh $HOMELPAR/bin/vcenter-list-cgi.pl $HOMELPAR/bin/offsite.sh $HOMELPAR/bin/genreport.sh $HOMELPAR/bin/offsite_vmware.sh
  # cannot be otherwise CWE for core does not work
  #rm -f $HOMELPAR/lpar2rrd-cgi/lpar-list-cgi.sh $HOMELPAR/bin/lpar-list-cgi.pl
  #rm -f $HOMELPAR/lpar2rrd-cgi/lpar-list-rep.sh $HOMELPAR/bin/lpar-list-rep.pl
  echo "Enterprise edition features have been deleted."
fi

if [ $free_edition_new -eq 1 ]; then
  rm -f $HOMELPAR/lpar2rrd-cgi/vcenter-list-cgi.sh $HOMELPAR/bin/vcenter-list-cgi.pl $HOMELPAR/bin/premium_lpm_find.pl $HOMELPAR/bin/offsite.sh $HOMELPAR/bin/genreport.sh $HOMELPAR/bin/offsite_vmware.sh $HOMELPAR/bin/reporter-premium.pl
  # cannot be otherwise CWE for core does not work
  #rm -f $HOMELPAR/lpar2rrd-cgi/lpar-list-cgi.sh $HOMELPAR/bin/lpar-list-cgi.pl
  #rm -f $HOMELPAR/lpar2rrd-cgi/lpar-list-rep.sh $HOMELPAR/bin/lpar-list-rep.pl
fi

# cleanup original before code copy

rm -f $HOMELPAR/html/.b
rm -f $HOMELPAR/html/.f
rm -f $HOMELPAR/html/.h
rm -f $HOMELPAR/html/.g
rm -f $HOMELPAR/html/.i
rm -f $HOMELPAR/html/.l
rm -f $HOMELPAR/html/.n
rm -f $HOMELPAR/html/.m
rm -f $HOMELPAR/html/.o
rm -f $HOMELPAR/html/.p
rm -f $HOMELPAR/html/.q
rm -f $HOMELPAR/html/.v
rm -f $HOMELPAR/html/.r
rm -f $HOMELPAR/html/.s 
rm -f $HOMELPAR/html/.t
rm -f $HOMELPAR/html/.x 



echo "Backing up original version : $version to $HOMELPAR/BACKUP-INSTALL/lpar2rrd-$version"
if [ ! -d $HOMELPAR/BACKUP-INSTALL ]; then
  mkdir $HOMELPAR/BACKUP-INSTALL
fi
if [ ! -d $HOMELPAR/BACKUP-INSTALL/lpar2rrd-$version ]; then
  mkdir $HOMELPAR/BACKUP-INSTALL/lpar2rrd-$version
fi

#
echo "Saving $version configuration"
#cp -R $HOMELPAR/logs $HOMELPAR/BACKUP-INSTALL/lpar2rrd-$version/ 2>/dev/null
if [ -f "$HOMELPAR/logs/alert_history.log" ]; then
  cp -p $HOMELPAR/logs/alert_history.log $HOMELPAR/BACKUP-INSTALL/lpar2rrd-$version/alert_history.log
fi
rm -f $HOMELPAR/logs/* 2>/dev/null # clean up logs
if [ -f "$HOMELPAR/BACKUP-INSTALL/lpar2rrd-$version/alert_history.log" ]; then
  # keep alert_history.log through upgrades
  mv $HOMELPAR/BACKUP-INSTALL/lpar2rrd-$version/alert_history.log $HOMELPAR/logs/
fi
#gzip -f9 $HOMELPAR/BACKUP-INSTALL/lpar2rrd-$version/logs/* 1>/dev/null 2>&1 #compress old logs

cp -Rp $HOMELPAR/etc $HOMELPAR/bin $HOMELPAR/BACKUP-INSTALL/lpar2rrd-$version/ 2>/dev/null
cp $HOMELPAR/*.cfg $HOMELPAR/*.txt $HOMELPAR/*.sh $HOMELPAR/BACKUP-INSTALL/lpar2rrd-$version/ 2>/dev/null

# Remove XorMon DB
if [ $VER_ORG -lt 709 ]; then
  if [ -f "$HOMELPAR/data/_DB/data.db" ]; then
    if [ "$DEMO"x = "x" ]; then
      echo ""
      echo "Removing XorMon configuration database, it will be re-created automatically within an hour"
      echo ""
      rm -f $HOMELPAR/data/_DB/*
    fi
  fi
fi

if [ $VER_ORG -lt 704 ]; then
  # Kubernetes beta removal
  if [ -d "$HOMELPAR/data/Kubernetes" ]; then
    rm -rf "$HOMELPAR/data/Kubernetes"
  fi
fi

if [ $VER_ORG -lt 622 ]; then
  # Oracle DB cleaning
  if [ -d "$HOMELPAR/data/OracleDB" ]; then
    echo "OracleDB cleaning of bad data"
    rm -f $HOMELPAR/data/OracleDB/*/Wait_class/*
    rm -f $HOMELPAR/data/OracleDB/*/Services/*
    rm -f $HOMELPAR/data/OracleDB/*/RAC/*
    rm -f $HOMELPAR/data/OracleDB/*/Disk_latency/*
  fi
fi

if [ $VER_ORG -lt 600 ]; then
  # house cleaning only for old distros
  if [ -d "$HOMELPAR/data/XEN_VMs" ]; then
    echo ""
    echo "Looks like you have beta tested XEN"
    echo "It will not work now, there has been format change"
    echo "Remove data manually: rm -r $HOMELPAR/data/XEN* "
  fi
fi

if [ $VER_ORG -lt 511 ]; then
  # house cleaning only for old distros
  if [ -d "$HOMELPAR/data/oVirt/storage" -a "$DEMO"x = "x" ]; then
    echo "Removing oVirt storage capacity data, old format"
    rm -f "$HOMELPAR"/data/oVirt/storage/sd-*.rrd
  fi
fi

if [ $VER_ORG -lt 239 ]; then
  # house cleaning only for old distros
  mv $HOMELPAR/*.sh $HOMELPAR/*.pl $HOMELPAR/*.pm $HOMELPAR/BACKUP-INSTALL/lpar2rrd-$version/ 2>/dev/null
  mv $HOMELPAR/lpar2rrd-[1-9]* $HOMELPAR/BACKUP-INSTALL/  2>/dev/null # move away old backups
fi

if [ $VER_ORG -lt 618 ]; then
  # Removing CPU Total from beta releases, they were wrong
  rm -f "$HOMELPAR"/data/*/*/pool_total.rrt
  rm -f "$HOMELPAR"/data/*/*/pool_total.rxm
fi

if [ $VER_ORG -lt 752 ]; then
  # Removing CPU data/*/*/*_multipathing.txt, some might have been created wrongly without hardlinking
  find $HOMELPAR -name \*_multipathing.txt -exec rm -f {} \;
fi

rm -f $HOMELPAR/html/.v $HOMELPAR/html/.p $HOMELPAR/html/.h $HOMELPAR/html/.o $HOMELPAR/html/.x $HOMELPAR/html/.s $HOMELPAR/html/.l $HOMELPAR/html/.b
cp -Rp $HOMELPAR/html $HOMELPAR/lpar2rrd-cgi $HOMELPAR/bin $HOMELPAR/BACKUP-INSTALL/lpar2rrd-$version/ 2>/dev/null

chown $ID $HOMELPAR
if [ ! $? -eq 0 ]; then
  echo "Problem with ownership of $HOMELPAR"
  echo "Fix it and run it again : chown  $ID $HOMELPAR"
  exit 1
fi

# clean up agent directory to do not leave there old versions
if [ -d "$HOMELPAR/agent" ]; then
  rm -f $HOMELPAR/agent/*
  echo "Download the latest agent from: http://www.lpar2rrd.com/download-xorux.htm" > $HOMELPAR/agent/Readme.txt
  echo "Use it even if you are a customer and use LPAR2RRD Enterprise Edition" >> $HOMELPAR/agent/Readme.txt
fi

# save cfg
if [ -f $HOMELPAR/etc/alias.cfg ]; then
  mv $HOMELPAR/etc/alias.cfg $HOMELPAR/etc/alias.cfg-org
fi
if [ -f $HOMELPAR/etc/alert_filesystem_exclude.cfg ]; then
  mv $HOMELPAR/etc/alert_filesystem_exclude.cfg $HOMELPAR/etc/alert_filesystem_exclude.cfg-org
fi
if [ -f $HOMELPAR/etc/heatmap_exclude.cfg ]; then
  mv $HOMELPAR/etc/heatmap_exclude.cfg $HOMELPAR/etc/heatmap_exclude.cfg-org
fi

# Clean up html/jquery/* a www/jquery/*   before upgrade from old stuff
rm -rf $HOMELPAR/html/jquery/*  $WEBDIR_PLAIN/jquery/* $HOMELPAR/html/css/*  $WEBDIR_PLAIN/css/*

echo "Copy new version to the target destination"
chmod 644 $HOMELPAR/lib/*pm 2>/dev/null # was some problem in past
cp -R * $HOMELPAR/

# Copy web files directly, do not wait for next load.sh
cp $HOMELPAR/html/*html $HOMELPAR/html/*ico $HOMELPAR/html/*png $HOMELPAR/html/*pdf $WEBDIR_PLAIN
pwd_org=`pwd`
cd $HOMELPAR/html
tar cf - jquery css | (cd $WEBDIR_PLAIN ; tar xf - )
cd $pwd_org

if [ $os_aix -gt 0 ]; then
  # extract perl lib for https REST API support (LWP 6.06)
  if [ -f ../perl_aix_ssl.tar.Z ]; then
    uncompress -f ../perl_aix_ssl.tar.Z
  fi
  if [ -f ../perl_aix_ssl.tar ]; then
    tar xf ../perl_aix_ssl.tar
    cp -R lib $HOMELPAR/
  else
    echo "ERROR during: uncompress -f perl_aix_ssl.tar.Z : install it manually"
    echo "  uncompress -f perl_aix_ssl.tar.Z; cd $HOMELPAR/; tar xvf perl_aix_ssl.tar"
  fi
fi

# Clean agent dir (old agents), no more distributing OS agents with the lpar2rrd server
rm -f $HOMELPAR/agent/lpar2rrd-agent*

if [ ! -f "$HOMELPAR/tmp/menu.txt" -a -f "$HOMELPAR/html/menu_default.txt" ]; then
  #place default menu.txt
  cp $HOMELPAR/html/menu_default.txt $HOMELPAR/tmp/menu.txt
fi


# return cfg
if [ -f $HOMELPAR/etc/alias.cfg-org ]; then
  mv $HOMELPAR/etc/alias.cfg $HOMELPAR/etc/alias.cfg.example
  mv $HOMELPAR/etc/alias.cfg-org $HOMELPAR/etc/alias.cfg
fi
if [ -f $HOMELPAR/etc/alert_filesystem_exclude.cfg-org ]; then
  mv $HOMELPAR/etc/alert_filesystem_exclude.cfg $HOMELPAR/etc/alert_filesystem_exclude.cfg.example
  mv $HOMELPAR/etc/alert_filesystem_exclude.cfg-org $HOMELPAR/etc/alert_filesystem_exclude.cfg
fi
if [ -f $HOMELPAR/etc/heatmap_exclude.cfg-org ]; then
  mv $HOMELPAR/etc/heatmap_exclude.cfg $HOMELPAR/etc/alias.cfg.example
  mv $HOMELPAR/etc/heatmap_exclude.cfg-org $HOMELPAR/etc/heatmap_exclude.cfg
fi

if [ `grep "#VM:" $HOMELPAR/etc/alias.cfg 2>/dev/null| wc -l | sed 's/ //g'` -eq 0 ]; then
  echo "#" >> $HOMELPAR/etc/alias.cfg
  echo "# VMware" >> $HOMELPAR/etc/alias.cfg
  echo "#VM:VC01_VM01:oracle server alias" >> $HOMELPAR/etc/alias.cfg
  echo "#" >> $HOMELPAR/etc/alias.cfg
fi


# it mus be here to get configured cfg as soon as possible after copy it over
echo "Configuring new $CFG"

if [ $VER_ORG -lt 239 ]; then
  eval ' sed -e 's/WEBDIR=.*/WEBDIR=$WEBDIR/g' \
           -e 's/RRDTOOL=.*/RRDTOOL=$RRD/g' -e 's/SAMPLE_RATE=.*/SAMPLE_RATE=$SAMPLE_RATE/g' \
           -e 's/HMC_USER=.*/HMC_USER=$HMC_USER/g' -e 's/HMC_LIST=".*"/HMC_LIST=$HMC_HOSTAME/g' \
           -e 's/MANAGED_SYSTEMS_EXCLUDE=.*/MANAGED_SYSTEMS_EXCLUDE=$MANAGED_SYSTEMS_EXCLUDE/g' \
	   -e 's/PERL=.*/PERL=$PERL/g' -e 's/HWINFO=.*/HWINFO=$HWINFO/g' \
	   -e 's/DEBUG=.*/DEBUG=$DEBUG_CFG/g' \
       $HOMELPAR/etc/lpar2rrd.cfg > $HOMELPAR/etc/lpar2rrd.cfg-new '
else
  eval ' sed -e 's/WEBDIR=.*/WEBDIR=$WEBDIR/g' \
           -e 's/RRDTOOL=.*/RRDTOOL=$RRD/g' -e 's/SAMPLE_RATE=.*/SAMPLE_RATE=$SAMPLE_RATE/g' \
           -e 's/HMC_USER=.*/HMC_USER=$HMC_USER/g' -e 's/HMC_LIST=".*"/HMC_LIST=$HMC_LIST/g' \
           -e 's/MANAGED_SYSTEMS_EXCLUDE=.*/MANAGED_SYSTEMS_EXCLUDE=$MANAGED_SYSTEMS_EXCLUDE/g' \
	   -e 's/PERL=.*/PERL=$PERL/g' -e 's/HWINFO=.*/HWINFO=$HWINFO/g' \
	   -e 's/SYS_CHANGE=.*/SYS_CHANGE=$SYS_CHANGE/g' -e 's/RRDHEIGHT=.*/RRDHEIGHT=$RRDHEIGHT/g' \
	   -e 's/RRDWIDTH=.*/RRDWIDTH=$RRDWIDTH/g' -e 's/PERL5LIB=.*/PERL5LIB=$PERL5LIB/g' \
           -e 's/DASHB_RRDHEIGHT=.*/DASHB_RRDHEIGHT=$DASHB_RRDHEIGHT/g' -e 's/DASHB_RRDWIDTH=.*/DASHB_RRDWIDTH=$DASHB_RRDWIDTH/g' \
	   -e 's/PICTURE_COLOR=.*/PICTURE_COLOR=$PICTURE_COLOR/g' -e 's/DEBUG=.*/DEBUG=$DEBUG/g' \
	   -e 's/HEA=.*/HEA=$HEA/g' -e 's/STEP_HEA=.*/STEP_HEA=$STEP_HEA/g' \
	   -e 's/^TOPTEN=.*/TOPTEN=$TOPTEN/g' -e 's/$hash_ACL_ADMIN_GROUP=.*/ACL_ADMIN_GROUP=$ACL_ADMIN_GROUP/g' \
	   -e 's/VMOTION_TOPTEN=.*/VMOTION_TOPTEN=$VMOTION_TOPTEN/g' \
	   -e 's/$hash_ACL_GRPLIST_VARNAME=.*/ACL_GRPLIST_VARNAME=$ACL_GRPLIST_VARNAME/g' \
	   -e 's/LPM=.*/LPM=$LPM/g' -e 's/LPM_HMC_EXCLUDE=.*/LPM_HMC_EXCLUDE=$LPM_HMC_EXCLUDE/g' \
	   -e 's/LPAR2RRD_AGENT_DAEMON=.*/LPAR2RRD_AGENT_DAEMON=$LPAR2RRD_AGENT_DAEMON/g' \
	   -e 's/LPAR2RRD_AGENT_DAEMON_PORT=.*/LPAR2RRD_AGENT_DAEMON_PORT=$LPAR2RRD_AGENT_DAEMON_PORT/g' \
	   -e 's/LPAR2RRD_AGENT_DAEMON_IP=.*/LPAR2RRD_AGENT_DAEMON_IP=$LPAR2RRD_AGENT_DAEMON_IP/g' \
	   -e 's/LPM_SERVER_EXCLUDE=.*/LPM_SERVER_EXCLUDE=$LPM_SERVER_EXCLUDE/g' \
	   -e 's/LPM_LPAR_EXCLUDE=.*/LPM_LPAR_EXCLUDE=$LPM_LPAR_EXCLUDE/g' -e 's/IVM_LIST=".*"/IVM_LIST=$IVM_LIST/g' \
	   -e 's/EXPORT_TO_CSV=.*/EXPORT_TO_CSV=$EXPORT_TO_CSV/g' -e 's/LEGEND_HEIGHT=.*/LEGEND_HEIGHT=$LEGEND_HEIGHT/g' \
	   -e 's/SSH_WEB_IDENT=.*/SSH_WEB_IDENT=$SSH_WEB_IDENT/g' -e 's/PDF_PAGE_SIZE=.*/PDF_PAGE_SIZE=$PDF_PAGE_SIZE/g' \
	   -e 's/ORACLE_BASE=.*/ORACLE_BASE=$ORACLE_BASE/g' -e 's/ORACLE_HOME=.*/ORACLE_HOME=$ORACLE_HOME/g' \
	   -e 's/TNS_ADMIN=.*/TNS_ADMIN=$TNS_ADMIN/g' -e 's/DB2_CLI_DRIVER_INSTALL_PATH=.*/DB2_CLI_DRIVER_INSTALL_PATH=$DB2_CLI_DRIVER_INSTALL_PATH/g' \
       	   -e 's/SSH=.*/SSH=$SSH/g' $HOMELPAR/etc/lpar2rrd.cfg > $HOMELPAR/etc/lpar2rrd.cfg-new '
fi

if [ `cat $HOMELPAR/etc/lpar2rrd.cfg-new|wc -l|sed 's/ //g'`  -eq 0 ]; then
  echo ""
  echo "ERROR: Configuration of $HOMELPAR/etc/lpar2rrd.cfg failed, original file is kept"
  echo "       This might cause unpredictable problems, contact LPAR2RRD support in case anything is not working fine after the update"
  echo ""
  cp $CFG-backup $CFG
else
  mv $HOMELPAR/etc/lpar2rrd.cfg-new $HOMELPAR/etc/lpar2rrd.cfg
fi
rm -f $CFG-backup


if [ -h $HOMELPAR/realt-error.log ]; then
  # must be removed here before chown ...
  # it is an old stuff
  rm -f $HOMELPAR/realt-error.log
fi
if [ -h $HOMELPAR/logs/error-cgi.log ]; then
  rm -f $HOMELPAR/logs/error-cgi.log
fi

echo "Setting file/dir permissions, it might take some time in big environments"
chown $ID $HOMELPAR/* 2>&1|egrep -v "error-cgi|lost+found"
chown -R $ID $HOMELPAR/lpar2rrd-cgi
chown -R $ID $HOMELPAR/html
chown $ID $HOMELPAR/etc
chown $ID $HOMELPAR/etc/*.cfg
chown $ID $HOMELPAR/etc/*.txt
chown $ID $HOMELPAR/etc/*.conf 2>/dev/null
chown -R $ID $HOMELPAR/logs 2>&1|egrep -v "error-cgi"
if [ -f "$HOMELPAR/.magic" ]; then
  chown $ID $HOMELPAR/.magic 2>&1
  chmod 755 $HOMELPAR/.magic 2>&1
fi
chown -R $ID $HOMELPAR/scripts
chown -R $ID $HOMELPAR/www   2>/dev/null
if [ ! -d $HOMELPAR/tmp ]; then
  mkdir $HOMELPAR/tmp
fi
if [ "$VM_IMAGE"x = "x" ]; then
  chmod 777 $HOMELPAR/tmp  # due to Xormon & "Refresh" feature which need to save temp files there
else
  chmod 755 $HOMELPAR/tmp  # not necessary on the image
fi
chmod 755 $HOMELPAR/logs
chmod -R 755 $HOMELPAR/lib
chmod 755 $HOMELPAR/dbschema
chmod 644 $HOMELPAR/dbschema/* 2>/dev/null
chmod 644 $HOMELPAR/lib/*pm
chmod 666 $HOMELPAR/logs/* 2>&1|egrep -v "error-cgi"
chmod 755 $HOMELPAR
chmod 755 $HOMELPAR/bin
chmod -R 755 $HOMELPAR/html  # must be due tue subdirs jquery, images ...
chmod -R 755 $HOMELPAR/lpar2rrd-cgi
chmod -R o+r $HOMELPAR/www  2>/dev/null
chmod -R o+x $HOMELPAR/www 2>/dev/null
chmod 755 $HOMELPAR/bin/*.pl
chmod 755 $HOMELPAR/bin/*.pm
chmod 755 $HOMELPAR/bin/*.sh
chmod 755 $HOMELPAR/*.sh
# do not touch etc/web_config here!
chmod 644 $HOMELPAR/etc/*.cfg
chmod 644 $HOMELPAR/etc/*.txt
chmod 644 $HOMELPAR/etc/*.conf 2>/dev/null
chmod 755 $HOMELPAR/scripts/*
chmod 644 $HOMELPAR/*.txt

if [ ! -h $HOMELPAR/logs/error-cgi.log ]; then
  ln -s /var/tmp/lpar2rrd-realt-error.log $HOMELPAR/logs/error-cgi.log 2>/dev/null
fi
if [ -f /var/tmp/lpar2rrd-realt-error.log ]; then
  # remove cgi-bin error log if rights are sufficient
  cat /dev/null > /var/tmp/lpar2rrd-realt-error.log 2>/dev/null
fi

if [ "$VM_IMAGE"x = "x" ]; then
  # only for non image update, it might take a long time and on image should not happen such things
  echo   "chmod -R o+r,o+x $HOMELPAR/data"
  chmod -R o+r,o+x $HOMELPAR/data 2>&1|egrep -v " path name does not exist|No such file or directory"
  #echo   "chown -R $ID $HOMELPAR/data"
  #chown -R $ID $HOMELPAR/data 2>&1|egrep -v " path name does not exist|No such file or directory"
  #echo   "chmod -R o+x $HOMELPAR/data"
  #chmod -R o+x $HOMELPAR/data 2>&1|egrep -v " path name does not exist|No such file or directory"
  echo ""
fi

cd $HOMELPAR

if [ ! -d "$WEBDIR_PLAIN" ]; then
  mkdir "$WEBDIR_PLAIN"
fi

if [ ! -d "$HOMELPAR/etc/web_config" ]; then
  mkdir "$HOMELPAR/etc/web_config"
fi
if [ "$VM_IMAGE"x = "x" ]; then
  chmod 777 "$HOMELPAR/etc/web_config"
  chmod 777 "$HOMELPAR/reports"
else
  chmod 755 "$HOMELPAR/etc/web_config"
  chmod 755 "$HOMELPAR/reports"
fi


if [ ! -f "$HOMELPAR/etc/web_config/htusers.cfg" ]; then
  echo 'admin:$apr1$CSoXefyw$wGe9K7Ld5ClOEozE4zC.T1' >  $HOMELPAR/etc/web_config/htusers.cfg
  if [ "$VM_IMAGE"x = "x" ]; then
    chmod 666 $HOMELPAR/etc/web_config/htusers.cfg
  else
    chmod 600 $HOMELPAR/etc/web_config/htusers.cfg
  fi
fi

rm -f $HOMELPAR/bin/load.sh # it comes by a mistake with some version, remove it (fixed definitelly in 4.91 at least)

if [ "$VM_IMAGE"x = "x" ]; then
  # Check whether web user has read&executable rights for CGI dir lpar2rrd-cgi
  www=`echo "$WEBDIR"|sed 's/\\\//g'`
  DIR=""
  IFS_ORG=$IFS
  IFS="/"
  for i in $www
  do
    IFS=$IFS_ORG
    NEW_DIR=`echo $DIR$i/`
    #echo "01 $NEW_DIR -- $i -- $DIR ++ $www"
    NUM=`ls -dLl $NEW_DIR |$AWK '{print $1}'|sed -e 's/d//g' -e 's/-//g' -e 's/w//g' -e 's/\.//g'| wc -c`
    #echo "02 $NUM"
    if [ ! $NUM -eq 7 ]; then
      echo ""
      echo "WARNING, directory : $NEW_DIR has probably wrong rights" | sed 's/\/\//\//g'
      echo "         $www dir and its subdirs have to be executable&readable for WEB user"
      ls -lLd $NEW_DIR| sed 's/\/\//\//g'
      echo ""
    fi
    DIR=`echo "$NEW_DIR/"`
    #echo $DIR
    IFS="/"
  done
  IFS=$IFS_ORG


  # Check whether web user has read&executable rights for CGI dir lpar2rrd-cgi
  CGI="$HOMELPAR/lpar2rrd-cgi"
  DIR=""
  IFS_ORG=$IFS
  IFS="/"
  for i in $CGI
  do
    IFS=$IFS_ORG
    NEW_DIR=`echo $DIR$i/`
    NUM=`ls -dLl $NEW_DIR |$AWK '{print $1}'|sed -e 's/d//g' -e 's/-//g' -e 's/w//g' -e 's/\.//g'| wc -c`
    #echo $NUM
    if [ ! $NUM -eq 7 ]; then
      echo ""
      echo "WARNING, directory : $NEW_DIR has probably wrong rights" | sed 's/\/\//\//g'
      echo "         it dir has to be executable&readable for WEB user"
      ls -lLd $NEW_DIR| sed 's/\/\//\//g'
      echo ""
    fi
    DIR=`echo "$NEW_DIR/"`
    #echo $DIR
    IFS="/"
  done
  IFS=$IFS_ORG
fi


if [ $VER_ORG -lt 300 ]; then
  echo ""
  echo "*******************************************************************"
  echo "Now manually remove LPAR2RRD web content by : rm -r $WEBDIR_PLAIN/*"
  echo "It will be all recovered during next LPAR2RRD run"
  echo "*******************************************************************"
  echo ""
fi

if [ $VER_ORG -lt 239 ]; then
echo "Update your web server, following example is for Apache"
echo "Just append following into your httpd.conf and restart Apache by : apachectl restart"
echo ""
echo "# CGI-BIN"
echo "ScriptAlias /lpar2rrd-cgi/ \"$HOMELPAR/lpar2rrd-cgi/\""
echo "<Directory \"$HOMELPAR/lpar2rrd-cgi\">"
echo "    AllowOverride None"
echo "    Options ExecCGI Includes"
echo "    Order allow,deny"
echo "    Allow from all"
echo "</Directory>"
echo ""
fi

if [ $VER_ORG -lt 259 ]; then
  SSH_WEB_IDENT=`echo $SSH_WEB_IDENT|sed 's/\\\\//g'`
  if [ ! -d $HOME/.ssh ]; then
    echo "Could not be found directory with ssh-keys ($HOME/.ssh)"
    echo "You must do it manually"
    echo " - find location of id_dsa or id_rsa file"
    echo " - under root do :"
    echo "   # cp __YOUR_LOCATION__/id_dsa $SSH_WEB_IDENT"
    echo "   # chown $WWW_USER $SSH_WEB_IDENT"
    echo "   # chmod 600 $SSH_WEB_IDENT"
    echo ""
  else
    chmod 755 $HOME/.ssh
    if [ -f $HOME/.ssh/id_dsa ]; then
      cp -f $HOME/.ssh/id_dsa $SSH_WEB_IDENT
      chmod 600 $SSH_WEB_IDENT
    else
      if [ -f $HOME/.ssh/id_rsa ]; then
        cp -f $HOME/.ssh/id_rsa $SSH_WEB_IDENT
        chmod 600 $SSH_WEB_IDENT
      else
        echo "Could not be found ssh-keys in ($HOME/.ssh)"
        echo "You must do it manually"
        echo " - find location of id_dsa or id_rsa file"
        echo " - under root do :"
        echo "   # cp __YOUR_LOCATION__/id_dsa $SSH_WEB_IDENT"
        echo "   # chown $WWW_USER $SSH_WEB_IDENT"
        echo "   # chmod 600 $SSH_WEB_IDENT"
        echo ""
      fi
    fi
  fi
  WWW_USER=`ps -ef|egrep "apache|httpd"|grep -v grep|$AWK '{print $1}'|grep -v "root"|head -1`
  WWW_USER_GUESS=0
  if [ "$WWW_USER"x = x ]; then
    WWW_USER=nobody
    WWW_USER_GUESS=1
  fi
  echo ""
  echo "To install \"real-time\" refresh you need to allow to WEB user automatic logon to HMC"
  echo "Just copy&past following instructions:"
  echo ""
  echo "  1. login as root"
  if [ $WWW_USER_GUESS -eq 1 ]; then
    echo "  2. # chown $WWW_USER $SSH_WEB_IDENT   (suppose $WWW_USER is the WEB user)"
  else
    echo "  2. # chown $WWW_USER $SSH_WEB_IDENT"
  fi
  echo "  3. # chmod 600 $SSH_WEB_IDENT"
  echo ""
  echo ""
fi

rm -f $HOMELPAR/tmp/[1-9]* 2>/dev/null # do not remove everything aas usually, topten files should stay

rm -f $HOMELPAR/lpar_html.pl # distributed in 3.10 by a mistake


#crontab -l 2>/dev/null |grep -i hea >/dev/null
#if [ ! $? -eq 0 ]; then
#  echo "to allow IVE (HEA) and FC (only for IVE servers) stats add into cron via "crontab -e":"
#  echo "0,5,10,15,20,25,30,35,40,45,50,55 * * * * $HOMELPAR/load_hea.sh > $HOMELPAR/load_hea.out 2>&1"
#  echo ""
#fi

# search potential LPM lpars
export INPUTDIR=$HOMELPAR # for compatability rasons
LPM_FOUND=0

# no LPM search any more, 6.00, not necessary
if [ $free_edition_new -eq 1 ]; then
  #RR="rrm"
  #lpm_support
  rm -f $INPUTDIR/bin/premium_lpm_find.sh # remove it, it was in free version by a mistake, fixed in 5.08
fi

#if [ $LPM_FOUND -gt 0 ]; then
#  echo ""
#  echo "*********************************************************************"
#  if [ $LPM_FOUND -gt 5  ]; then
#    echo "Live Partition Mobility has been very likely identified"
#  else
#    echo "Live Partition Mobility has been probably identified"
#  fi
#  echo "LPAR2RRD free version does not support this feature"
#  echo "Check http://lpar2rrd.com/support.htm how to obtain LPM aware version"
#  echo "LPAR2RRD will work without aware of LPM ..."
#  echo "*********************************************************************"
#  echo ""
#fi

# fix memory rrdtool, there was limit 1TB for ram
if [ $VER_ORG -lt 402 ]; then
  find $HOMELPAR/data -name "mem.rr*" -exec $RRDTOOL tune {} --maximum curr_avail_mem:1000000000000 \;
  find $HOMELPAR/data -name "mem.rr*" -exec $RRDTOOL tune {} --maximum conf_sys_mem:1000000000000 \;
  find $HOMELPAR/data -name "mem.rr*" -exec $RRDTOOL tune {} --maximum sys_firmware_mem:1000000000000 \;
fi

# move rperf tables from version < 3.20 into etc/
if [ ! -f $HOMELPAR/etc/rperf_user.txt ]; then
  if [ -f $HOMELPAR/rperf_user.txt ]; then
    mv $HOMELPAR/rperf_user.txt $HOMELPAR/etc/rperf_user.txt
  fi
fi

if [ ! -f $HOMELPAR/etc/rperf_table.txt ]; then
  if [ -f $HOMELPAR/rperf_table.txt ]; then
    mv $HOMELPAR/rperf_table.txt $HOMELPAR/etc/rperf_table.txt
  fi
fi
rm -f $HOMELPAR/rperf_table.txt

# copy rperf_user table, do not overwrite it!!
if [ ! -f $HOMELPAR/etc/rperf_user.txt -a -f $HOMELPAR/etc/rperf_user.txt_template ]; then
  mv $HOMELPAR/etc/rperf_user.txt_template $HOMELPAR/etc/rperf_user.txt
else
  rm -f $HOMELPAR/etc/rperf_user.txt_template
fi

rm -f tmp/[1-9]* error.log error.log-hea apache-cfg.txt lpar2rrd.cfg 2>/dev/null
rm -rf config

# move old backup dirs into centra backup
for dir in lpar2rrd-[1-3]*
do
  if [ -d $dir ]; then
    #echo $dir
    mv $dir BACKUP-INSTALL/ 2>/dev/null
  fi
done

# change #!bin/ksh in shell script to #!bin/bash on Linux platform
os_linux=` uname -s|egrep "^Linux$"|wc -l|sed 's/ //g'`
if [ $os_linux -eq 1 ]; then
  # If Linux then change all "#!bin/sh --> #!bin/bash
  for sh in $HOMELPAR/bin/*.sh $HOMELPAR/bin/check_lpar2rrd
  do
  ed $sh << EOF 2>/dev/null 1>&2
1s/\/ksh/\/bash/
w
q
EOF
  done

  for sh in $HOMELPAR/scripts/*.sh
  do
  ed $sh << EOF 2>/dev/null 1>&2
1s/\/ksh/\/bash/
w
q
EOF
  done

  for sh in $HOMELPAR/*.sh
  do
  ed $sh << EOF 2>/dev/null 1>&2
1s/\/ksh/\/bash/
w
q
EOF
  done

  for sh in $HOMELPAR/lpar2rrd-cgi/*.sh
  do
  ed $sh << EOF 2>/dev/null 1>&2
1s/\/ksh/\/bash/
w
q
EOF
  done

else
  # for AIX Solaris etc, all should be already in place just to be sure ...
  # change all "#!bin/sh --> #!bin/bash
  for sh in $HOMELPAR/bin/*.sh
  do
  ed $sh << EOF >/dev/null 2>&1
1s/\/bash/\/ksh/
w
q
EOF
  done

  for sh in $HOMELPAR/scripts/*.sh
  do
  ed $sh << EOF >/dev/null 2>&1
1s/\/bash/\/ksh/
w
q
EOF
  done

  for sh in $HOMELPAR/*.sh
  do
  ed $sh << EOF >/dev/null 2>&1
1s/\/bash/\/ksh/
w
q
EOF
  done

  for sh in $HOMELPAR/lpar2rrd-cgi/*.sh
  do
  ed $sh << EOF >/dev/null 2>&1
1s/\/bash/\/ksh/
w
q
EOF
  done

fi

# fix when in config files appeared by a bug .rrm or .rrh sufixes
LIST="$HOMELPAR/etc/alert.cfg $HOMELPAR/etc/favourites.cfg $HOMELPAR/etc/custom_groups.cfg"
for file in $LIST
do
  if [ -f $file ]; then
  ed $file << EOF 2>/dev/null 1>&2
g/\.rrm/s/\.rrm//
g/\.rrh/s/\.rrh//
w
q
EOF
  fi
done

# set graph sending along with alarms, default last 8 hours
if [ $VER_ORG -lt 350 ]; then
  if [ -f $HOMELPAR/etc/alert.cfg ]; then
    ed $HOMELPAR/etc/alert.cfg << EOF 2>/dev/null 1>&2
g/EMAIL_GRAPH=0/s/EMAIL_GRAPH=0/EMAIL_GRAPH=8/
w
q
EOF
  fi
fi

# not necessary since 4.70 due to a new GUI
#echo ""
#echo "Custom groups config file update"
#$HOMELPAR/scripts/update_cfg_custom-groups.sh update

custom_cfg="$HOMELPAR/etc/custom_groups.cfg"
if [ -f "$custom_cfg" -a `grep " WARNING " "$custom_cfg" 2>/dev/null| wc -l` -eq 0 ]; then
  mv "$custom_cfg" "$custom_cfg-bck"
  cat << END > "$custom_cfg"
#
# !!!!!!!!!!!!!!!! WARNING !!!!!!!!!!!!!!!!
#
# This configuration file is not more used since v4.70
# Configure Custom Groups directly in the GUI : GUI --> Custom Groups --> Configuration
# http://www.lpar2rrd.com/custom_groups.html
#
# !!!!!!!!!!!!!!!! WARNING !!!!!!!!!!!!!!!!
#
END
  cat "$custom_cfg-bck" >> "$custom_cfg"
  rm -f "$custom_cfg-bck"

  # change all_pools --> CPU pool : since 4.70
  ed $HOMELPAR/etc/$custom_cfg << EOF 2>/dev/null 1>&2
g/:all_pools:/s/:all_pools:/:CPU pool:/
w
q
EOF
fi

# Refresh custom restriction after the upgrade
rm -f $HOMELPAR/tmp/.custom-group-*.cmd 2>/dev/null

# remove custom cmd definitions to be sure that they are reinitiated after upgrade,
rm -f $HOMELPAR/tmp/custom-group-* 2>/dev/null

# remove color file for total HMC graphs, new format came in 4.90
find $HOMELPAR/data . -name  lpars.col -exec rm -f {} \;

# no longer used (since 4.75)
#echo ""
#echo "Favourites config file update"
#$HOMELPAR/scripts/update_cfg_favourites.sh update

# no longer used (since 5.00)
#echo ""
#echo "Alert config file update"
#$HOMELPAR/scripts/update_cfg_alert.sh update


# space cheking as new memory rrd files will appera there
if [ $VER_ORG -lt 330 ]; then
  no_lpars=`find $HOMELPAR/data -name "*rr[m|h]"|wc -l|sed 's/ //g'`
  echo ""
  echo "Assure there is at least $no_lpars MB free in the fs where LPAR2RRD is installed!!"
  echo "It will be needed for new memory graphs"
  echo ""
fi

# delete old AS400 JOB rrd files, new format is there since 4.88
if [ $VER_ORG -lt 488 ]; then
  for as400_space in `find $HOMELPAR/data -type d -name \*--AS400-- | sed 's/ /===space===/g'`
  do
  as400=`echo "$as400_space"| sed 's/===space===/ /g'`
  if [ -d "$as400/JOB" ]; then
    rm -f $as400/JOB/*
  fi
  done
fi

# ulimit check
# necessary for big aggregated graphs
#
# AIX:
# chuser  data=8388608  lpar2rrd (4GB)
# chuser  stack=1048576 lpar2rrd (512MB)

ulimit_message=0
data=`ulimit -d`
stack=`ulimit -s`
if [ $os_aix -eq 1 ]; then
  if [ ! "$data" = "unlimited" -a ! "$data" = "hard" -a ! "$data" = "soft" ]; then
    if [ $data -lt 4194304 ]; then
      echo ""
      echo "Warning: increase data ulimit for $ID user, it is actually too low ($data kB)"
      echo "Assure that the same limits has even the web user (apache/nobody/http)"
      echo "  under root: chuser  data=8388608 $ID # 4GB"
    fi
  fi
  if [ ! "$stack" = "unlimited" -a ! "$stack" = "hard" -a ! "$data" = "soft" ]; then
    if [ $stack -lt 524288  ]; then
      echo ""
      echo "Warning: increase stack ulimit for $ID user, it is actually too low ($stack kB)"
      echo "Assure that the same limits has even the web user (apache/nobody/http)"
      echo "  under root: chuser  stack=1048576 $ID # 512MB"
    fi
  fi
else # Linux
  if [ ! "$data" = "unlimited" -a ! "$data" = "hard" -a ! "$data" = "soft" ]; then
    if [ $data -lt 4194304 ]; then
      echo ""
      echo "Warning: increase data ulimit for $ID user, it is actually too low ($data)"
      echo "Assure that the same limits has even the web user (apache/nobody/http)"
      echo "  under root: vi /etc/security/limits.conf"
      echo "    @$ID        hard    data            4194304"
      echo "    @$ID        soft    data            4194304"
    fi
  fi
  if [ ! "$stack" = "unlimited" -a ! "$stack" = "hard" -a ! "$data" = "soft" ]; then
    if [ $stack -lt 524288  ]; then
      echo ""
      echo "Warning: increase stack ulimit for $ID user, it is actually too low ($stack)"
      echo "Assure that the same limits has even the web user (apache/nobody/http)"
      echo "  under root: vi /etc/security/limits.conf"
      echo "    @$ID        hard    stack           524288"
      echo "    @$ID        soft    stack           524288"
    fi
  fi
fi


files=`ulimit -n`
if [ $os_aix -eq 1 ]; then
  if [ ! "$files" = "unlimited"  ]; then
    if [ $files -lt 8192 ]; then
      echo ""
      echo "Warning: increase open files ulimit for $ID user, it is actually too low ($files)"
      echo "  under root: chuser  nofiles=8192 $ID"
    fi
  fi
else # Linux
  if [ ! "$files" = "unlimited"  ]; then
    if [ $files -lt 8192 ]; then
      echo ""
      echo "Warning: increase open files ulimit for $ID user, it is actually too low ($files)"
      echo "  under root: vi /etc/security/limits.conf"
      echo "    @$ID        hard    nofile            8192"
      echo "    @$ID        soft    nofile            8192"
    fi
  fi
fi

# Check process limits on AIX only
if [ $os_aix -eq 1 ]; then
  maxuproc=`lsattr -El sys0 -a maxuproc| awk '{print $2}'`
  if [ ! "$maxuproc"x = "x" ]; then
    if [ $maxuproc -lt 129 ]; then
      echo ""
      echo "Warning: definitely increase user process limit, it is actually too low ($maxuproc)"
      echo "  under root: chdev -l sys0 -a maxuproc=1024"
    else
      if [ $maxuproc -lt 1024 ]; then
        echo ""
        echo "Warning: increase user process limit, it could be low when you monitoring a lot of devices ($maxuproc)"
        echo "  under root: chdev -l sys0 -a maxuproc=1024"
      fi
    fi
  fi
fi

rm -f $HOMELPAR/tmp/ent-run # force to run cpu config advisor

# stop the agent daemon
if [ -f "$HOMELPAR/tmp/lpar2rrd-daemon.pid" ]; then
  PID=`cat "$HOMELPAR/tmp/lpar2rrd-daemon.pid"|sed 's/ //g'`
  if [ ! "$PID"x = "x" ]; then
    echo ""
    echo "Stopping LPAR2RRD daemon"
    kill `cat "$HOMELPAR/tmp/lpar2rrd-daemon.pid"` 2>/dev/null
  fi
fi
run=`ps -ef|grep lpar2rrd-daemon.pl| egrep -v "grep |vi | vim "|wc -l`
if [ $run -gt 0 ]; then
  # just to make sure ....
  kill `ps -ef|grep lpar2rrd-daemon.pl| egrep -v "grep |vi | vim "|$AWK '{print $2}'` 2>/dev/null
fi

cd $HOMELPAR
if [ $os_aix -eq 0 ]; then
  free=`df .|grep -iv filesystem|xargs|$AWK '{print $4}'`
  freemb=`echo "$free/1048"|bc 2>/dev/null`
  if [ $? -eq 0 -a ! "$freemb"x = "x" ]; then
    if [ $freemb -lt 1048 ]; then
      echo ""
      echo "WARNING: free space in $HOMELPAR is too low : $freemb MB"
      echo "         note that 1 HMC needs about 1GB space depends on number of servers/lpars"
    fi
  fi
else
  free=`df .|grep -iv filesystem|xargs|$AWK '{print $3}'`
  freemb=`echo "$free/2048"|bc 2>/dev/null`
  if [ $? -eq 0 -a ! "$freemb"x = "x" ]; then
    if [ $freemb -lt 1048 ]; then
      echo ""
      echo "WARNING: free space in $HOMELPAR is too low : $freemb MB"
      echo "         note that 1 HMC needs about 1GB space depends on number of servers/lpars"
    fi
  fi
fi



if [ $VER_ORG -lt 401 ]; then
  # fix of 4.00 where was limit for all memory agent related stored values 100GB
  echo ""
  echo "Fixing memory agent files (the bug in v4.00)"
  find $HOMELPAR/data -name "mem.mmm" -exec $RRDTOOL tune {} --maximum in_use_work:102400000000 \; 2>&1 |grep -v "unknown data source"
  find $HOMELPAR/data -name "mem.mmm" -exec $RRDTOOL tune {} --maximum in_use_clnt:102400000000 \; 2>&1 |grep -v "unknown data source"
  find $HOMELPAR/data -name "mem.mmm" -exec $RRDTOOL tune {} --maximum size:102400000000 \; 2>&1 |grep -v "unknown data source"
  find $HOMELPAR/data -name "mem.mmm" -exec $RRDTOOL tune {} --maximum nuse:102400000000 \; 2>&1 |grep -v "unknown data source"
  find $HOMELPAR/data -name "mem.mmm" -exec $RRDTOOL tune {} --maximum free:102400000000 \; 2>&1 |grep -v "unknown data source"
  find $HOMELPAR/data -name "mem.mmm" -exec $RRDTOOL tune {} --maximum pin:102400000000 \; 2>&1 |grep -v "unknown data source"
fi

if [ $VER_ORG -lt 481 ]; then
  # there was a too low limit for LAN/SEA/SAN maximums
  echo ""
  echo "Fixing max on OS agent files, it can take a minute"
  echo "SEA is running"
  find $HOMELPAR/data -name "sea-*.mmm" -exec $RRDTOOL tune {} --maximum recv_bytes:12500000000 --maximum trans_bytes:12500000000 --maximum recv_packets:12500000 --maximum trans_packets:12500000 \; 2>&1
  echo "SAN is running"
  find $HOMELPAR/data -name "san-fcs*.mmm" -exec $RRDTOOL tune {} --maximum recv_bytes:12800000000 --maximum trans_bytes:12800000000 --maximum iops_in:12500000 --maximum iops_out:12500000 \; 2>&1
  echo "LAN is running"
  find $HOMELPAR/data -name "lan-*.mmm" -exec $RRDTOOL tune {} --maximum recv_bytes:12500000000 --maximum trans_bytes:12500000000 --maximum recv_packets:12500000 --maximum trans_packets:12500000 \; 2>&1
  echo "end of the data fix"
fi

# append OS agent info into rperf_user.txt
if [ -f "$HOMELPAR/etc/rperf_user.txt" -a `egrep "When you use OS agent" $HOMELPAR/etc/rperf_user.txt 2>/dev/null|wc -l` -eq 0 ]; then
cat << END >> $HOMELPAR/etc/rperf_user.txt

#
# When you use OS agent feature (V4.00+) on at least of one LPAR per each server/frame then
#   you do not need to use this file, CPU frequency is passed from the agents
#

END
fi

# setting up the font dir (necessary for 1.3 on AIX)
FN_PATH="<?xml version=\"1.0\"?>
<!DOCTYPE fontconfig SYSTEM \"fonts.dtd\">
<fontconfig>
<dir>/opt/freeware/share/fonts/dejavu</dir>
</fontconfig>"

if [ ! -f "$HOME/.config/fontconfig/.fonts.conf" -o `grep -i deja "$HOME/.config/fontconfig/.fonts.conf" 2>/dev/null|wc -l` -eq 0 ]; then
  if [ ! -d "$HOME/.config" ]; then
    mkdir "$HOME/.config"
  fi
  if [ ! -d "$HOME/.config/fontconfig" ]; then
    mkdir "$HOME/.config/fontconfig"
  fi
  echo $FN_PATH >> "$HOME/.config/fontconfig/.fonts.conf"
fi
chmod 644 "$HOME/.config/fontconfig/.fonts.conf"
# no, no, it issues this error:
# Fontconfig warning: "/opt/freeware/etc/fonts/conf.d/50-user.conf", line 9: reading configurations from ~/.fonts.conf is deprecated.
#if [ ! -f "$HOME/.fonts.conf" ]; then
#  echo $FN_PATH > "$HOME/.fonts.conf"
#  chmod 644 "$HOME/.fonts.conf"
#fi


# for web server user home
if [ ! -d "$HOMELPAR/tmp/home" ]; then
  mkdir "$HOMELPAR/tmp/home"
fi
#if [ ! -f "$HOMELPAR/tmp/home/.fonts.conf" ]; then
#  echo $FN_PATH > "$HOMELPAR/tmp/home/.fonts.conf"
#fi
if [ ! -d "$HOMELPAR/tmp/home/.config" ]; then
  mkdir "$HOMELPAR/tmp/home/.config" 2>/dev/null
  if [ ! $? -eq 0 ]; then
    # Once we saw tmp/home dir created and under apache user what is wrong, it is a workaround
    mv "$HOMELPAR/tmp/home" "$HOMELPAR/tmp/home.$$"
    mkdir "$HOMELPAR/tmp/home/"
    mkdir "$HOMELPAR/tmp/home/.config"
  fi
fi
if [ ! -d "$HOMELPAR/tmp/home/.config/fontconfig" ]; then
  mkdir "$HOMELPAR/tmp/home/.config/fontconfig"
fi
if [ ! -f "$HOMELPAR/tmp/home/.config/fontconfig/fonts.conf" ]; then
  echo $FN_PATH >> "$HOMELPAR/tmp/home/.config/fontconfig/fonts.conf"
fi
chmod 755 "$HOMELPAR/tmp/home"
chmod 755 "$HOMELPAR/tmp/home/.config"
chmod 755 "$HOMELPAR/tmp/home/.config/fontconfig"
chmod 644 "$HOMELPAR/tmp/home/.config/fontconfig/fonts.conf"

# remove new fencybox, we use the older open GNU licensed now:
rm -f $HOMELPAR/html/jquery/jquery.fancybox.pack.js

if [ $free_edition_new -eq 1  -a -f "$HOMELPAR/etc/rperf_table.txt" ]; then
  # remove rperf_table.txt in free version if there already is, leave only free_rperf_table.txt there
  rm -f $HOMELPAR/etc/rperf_table.txt 
fi
if [ $free_edition_new -eq 1 ]; then
  rm -f "$HOMELPAR/bin/premium.pl" "$HOMELPAR/bin/offsite*.sh" "$HOMELPAR/bin/reporter-premium.pl"
fi

#use_agent=`find $HOMELPAR/data -name "*.mmm"|wc -l`
#if [ $use_agent -eq 0 ]; then
#  echo "Consider to install the OS agent if you want get more OS metrics like memory usage/LAN/SAN/paging ..."
#  echo "http://www.lpar2rrd.com/agent.htm"
#fi

# RRDTool version checking for graph zooming
$RRD_act|grep graphv >/dev/null 2>&1
if [ $? -eq 1 ]; then
  # suggest RRDTool upgrade
  echo ""
  rrd_version=`$rrd -v|head -1|$AWK '{print $2}'`
  echo "Consider RRDtool upgrade to version 1.3.5+ (actual one is $rrd_version)"
  echo "This will allow graph zooming: http://www.lpar2rrd.com/zoom.html"
  echo ""
fi

if [ $os_linux -gt 0 ]; then
  # LinuxSE warning
  SELINUX=`ps -ef | grep -i selinux| grep -v grep|wc -l`

  if [ "$SELINUX" -gt 0  ]; then
    GETENFORCE=`getenforce 2>/dev/null`
    if [ "$GETENFORCE" = "Enforcing" ]; then
      echo ""
      echo "Warning!!!!!"
      echo "SELINUX status is Enforcing, it might cause problem during Apache setup"
      echo "like this in Apache error_log: (13)Permission denied: access to /XXXX denied"
      echo ""
    fi
  fi
fi

# VMware
# following for compatability purposes of old beta releases
if [ ! -d "$HOMELPAR/.vmware" ]; then
  if [ -d "$HOME/.vmware" ]; then
    mv  $HOME/.vmware $HOMELPAR/
  else
    mkdir $HOMELPAR/.vmware
    chmod 755 $HOMELPAR/.vmware
  fi
fi
if [ ! -d "$HOMELPAR/.vmware/credstore" ]; then
  if [ -d "$HOME/.vmware/credstore" ]; then
    mv  $HOME/.vmware/credstore $HOMELPAR/.vmware/
  else
    mkdir $HOMELPAR/.vmware/credstore
  fi
fi
if [ ! -d "$HOMELPAR/vmware-lib" -a -d "$HOME/vmware-lib" ]; then
  # only for compatability purposes with early beta VMware programm
  mv $HOME/vmware-lib $HOMELPAR/
fi

if [ -f "$HOMELPAR/etc/.magic" ]; then
  .  $HOMELPAR/etc/.magic
fi
if [ "$VM_IMAGE"x = "x" ]; then
  # not image, adjust rights (on image web server is running under lpar2rrd so not rights issue)
  if [ -d $HOMELPAR/.vmware/credstore ]; then
    chmod 777 $HOMELPAR/.vmware/credstore # must be 777 to allow writes of Apache user
    if [ -f "$HOMELPAR/.vmware/credstore/vicredentials.xml" ]; then
      chmod 666 $HOMELPAR/.vmware/credstore/vicredentials.xml 2>/dev/null # must be 666 to allow writes of Apache user
    fi
  fi
fi

# do that before ./bin/check_rrdtool.sh to can interrupt it
if [ ! "$version_new"x = "x" ]; then
  date=`date "+%Y-%m-%d_%H:%M"`
  echo "$version_new $date $pwd" >> $HOMELPAR/etc/version.txt
fi
echo "$HOMELPAR" > $HOME/.lpar2rrd_home 2>/dev/null

if [ -f "$HOMELPAR/bin/load.sh" ]; then
  # load.sh apeard since some version in bin dir what is wrong and it confuses people
  rm -f "$HOMELPAR/bin/load.sh"
fi

# CPU ready
# do not use CPU ready data since 4.96, they are wrong, make timestamp
if [ $VER_ORG -lt 496 ]; then
  if [ -d "$HOMELPAR/data/vmware_VMs" ]; then
    if [ ! -f "$HOMELPAR/data/vmware_VMs/CPU_ready_time.txt" ]; then
      date "+%s" > "$HOMELPAR/data/vmware_VMs/CPU_ready_time.txt"
    fi
  fi
fi

rm -f $HOMELPAR/www/heatmap-*html $HOMELPAR/html/heatmap-*html
rm -f $HOMELPAR/www/heatmap-*html $HOMELPAR/html/heatmap-*html

# remove old JSON, very old one might cause a problem, actually it is distributed in lib
rm -f $HOMELPAR/bin/JSON*pm

# Apache authorization
cat << END > $HOMELPAR/html/.htaccess
SetEnv XORUX_ACCESS_CONTROL 1
AuthUserFile $HOMELPAR/etc/web_config/htusers.cfg
AuthName "$WLABEL Authorized personnel only."
AuthType Basic
Require valid-user
END

# WEB GUI cleaning
rm -f $HOMELPAR/tmp/menu.cache $HOMELPAR/tmp/env.cache
rm -f $HOMELPAR/html/app.manifest $HOMELPAR/www/app.manifest $WEBDIR/app.manifest

if [ "$VM_IMAGE"x = "x" -a "$VI_IMAGE"x = "x" ]; then
  # this is intended only for image env, making changes for ACL in httpd.conf
  rm -f $HOMELPAR/bin/acl_enable.sh
fi

# fix for perl 5.26+ in VMware API
if [ -f $HOMELPAR/vmware-lib/URI/Escape.pm ]; then
  perl -pi $HOMELPAR/bin/URI_Escape_patch.pl $HOMELPAR/vmware-lib/URI/Escape.pm
fi

crontab_tmp="/tmp/crontab.$$"
crontab -l > $crontab_tmp
if [ ! "$VM_IMAGE"x = "x" ]; then
  if [ $VM_IMAGE -eq 1 ]; then
    grep  "load_hmc_rest_api.sh" $crontab_tmp >/dev/null 2>&1
    if [ ! $? -eq 0 ]; then
      echo "" >> $crontab_tmp
      echo "# IBM Power Systems - REST API" >> $crontab_tmp
      echo "0,20,40 * * * * $HOMELPAR/load_hmc_rest_api.sh > $HOMELPAR/load_hmc_rest_api.out 2>&1" >> $crontab_tmp
    fi

    # MS Hyper-V
    grep  "load_hyperv.sh" $crontab_tmp >/dev/null 2>&1
    if [ ! $? -eq 0 ]; then
      echo "" >> $crontab_tmp
      echo "# MS Hyper-V support   " >> $crontab_tmp
      echo "0,20,40 * * * *  $HOMELPAR/load_hyperv.sh > $HOMELPAR/load_hyperv.out 2>&1 " >> $crontab_tmp
    fi

    # XEN
    grep  "load_xenserver.sh" $crontab_tmp >/dev/null 2>&1
    if [ ! $? -eq 0 ]; then
      echo "" >> $crontab_tmp
      echo "# XEN Server support   " >> $crontab_tmp
      echo "0,20,40 * * * *  $HOMELPAR/load_xenserver.sh > $HOMELPAR/load_xenserver.out 2>&1 " >> $crontab_tmp
    fi

    grep  "load_ovirt.sh" $crontab_tmp >/dev/null 2>&1
    if [ ! $? -eq 0 ]; then
      echo "" >> $crontab_tmp
      echo "# oVirt / RHV Server support   " >> $crontab_tmp
      echo "0,20,40 * * * *  $HOMELPAR/load_ovirt.sh > $HOMELPAR/load_ovirt.out 2>&1 " >> $crontab_tmp
    fi

    grep  "load_nutanix.sh" $crontab_tmp >/dev/null 2>&1
    if [ ! $? -eq 0 ]; then
      echo "" >> $crontab_tmp
      echo "# Nutanix support   " >> $crontab_tmp
      echo "0,20,40 * * * *  $HOMELPAR/load_nutanix.sh > $HOMELPAR/load_nutanix.out 2>&1 " >> $crontab_tmp
    fi

    grep  "load_oraclevm.sh" $crontab_tmp >/dev/null 2>&1
    if [ ! $? -eq 0 ]; then
      echo "" >> $crontab_tmp
      echo "# OracleVM support   " >> $crontab_tmp
      echo "0,20,40 * * * *  $HOMELPAR/load_oraclevm.sh > $HOMELPAR/load_oraclevm.out 2>&1 " >> $crontab_tmp
    fi

    grep  "load_oracledb.sh" $crontab_tmp >/dev/null 2>&1
    if [ ! $? -eq 0 ]; then
      echo "" >> $crontab_tmp
      echo "# Oracle DB support   " >> $crontab_tmp
      echo "0,5,10,15,20,25,30,35,40,45,50,55 * * * *  $HOMELPAR/load_oracledb.sh > $HOMELPAR/load_oracledb.out 2>&1 " >> $crontab_tmp
    fi

    # AWS
    grep  "load_aws.sh" $crontab_tmp >/dev/null 2>&1
    if [ ! $? -eq 0 ]; then
      echo "" >> $crontab_tmp
      echo "# AWS support   " >> $crontab_tmp
      echo "0,20,40 * * * *  $HOMELPAR/load_aws.sh > $HOMELPAR/load_aws.out 2>&1 " >> $crontab_tmp
    fi

    # Azure
    grep  "load_azure.sh" $crontab_tmp >/dev/null 2>&1
    if [ ! $? -eq 0 ]; then
      echo "" >> $crontab_tmp
      echo "# Azure support   " >> $crontab_tmp
      echo "0,20,40 * * * *  $HOMELPAR/load_azure.sh > $HOMELPAR/load_azure.out 2>&1 " >> $crontab_tmp
    fi

    # GCloud
    grep  "load_gcloud.sh" $crontab_tmp >/dev/null 2>&1
    if [ ! $? -eq 0 ]; then
      echo "" >> $crontab_tmp
      echo "# Gcloud support   " >> $crontab_tmp
      echo "0,20,40 * * * *  $HOMELPAR/load_gcloud.sh > $HOMELPAR/load_gcloud.out 2>&1 " >> $crontab_tmp
    fi

    # Kubernetes
    grep  "load_kubernetes.sh" $crontab_tmp >/dev/null 2>&1
    if [ ! $? -eq 0 ]; then
      echo "" >> $crontab_tmp
      echo "# Kubernetes support   " >> $crontab_tmp
      echo "0,20,40 * * * *  $HOMELPAR/load_kubernetes.sh > $HOMELPAR/load_kubernetes.out 2>&1 " >> $crontab_tmp
    fi

    # OpenShift
    grep  "load_openshift.sh" $crontab_tmp >/dev/null 2>&1
    if [ ! $? -eq 0 ]; then
      echo "" >> $crontab_tmp
      echo "# RedHat OpenShift support   " >> $crontab_tmp
      echo "0,20,40 * * * *  $HOMELPAR/load_openshift.sh > $HOMELPAR/load_openshift.out 2>&1 " >> $crontab_tmp
    fi

    # Proxmox
    grep  "load_proxmox.sh" $crontab_tmp >/dev/null 2>&1
    if [ ! $? -eq 0 ]; then
      echo "" >> $crontab_tmp
      echo "# Proxmox support   " >> $crontab_tmp
      echo "0,20,40 * * * *  $HOMELPAR/load_proxmox.sh > $HOMELPAR/load_proxmox.out 2>&1 " >> $crontab_tmp
    fi

    # cloudstack 
    grep  "load_cloudstack.sh" $crontab_tmp >/dev/null 2>&1
    if [ ! $? -eq 0 ]; then
      echo "" >> $crontab_tmp
      echo "# CloudStack support   " >> $crontab_tmp
      echo "0,20,40 * * * *  $HOMELPAR/load_cloudstack.sh > $HOMELPAR/load_cloudstack.out 2>&1 " >> $crontab_tmp
    fi

    # fusioncompute
    grep  "load_fusioncompute.sh" $crontab_tmp >/dev/null 2>&1
    if [ ! $? -eq 0 ]; then
      echo "" >> $crontab_tmp
      echo "# Fusion Compute support   " >> $crontab_tmp
      echo "0,20,40 * * * *  $HOMELPAR/load_fusioncompute.sh > $HOMELPAR/load_fusioncompute.out 2>&1 " >> $crontab_tmp
    fi

    # MS SQL Server
    grep  "load_sqlserver.sh" $crontab_tmp >/dev/null 2>&1
    if [ ! $? -eq 0 ]; then
      echo "" >> $crontab_tmp
      echo "# MS SQL Server database support   " >> $crontab_tmp
      echo "0,5,10,15,20,25,30,35,40,45,50,55 * * * *  $HOMELPAR/load_sqlserver.sh > $HOMELPAR/load_sqlserver.out 2>&1 " >> $crontab_tmp
    fi

    # PostgreSQL Database
    grep  "load_postgres.sh" $crontab_tmp >/dev/null 2>&1
    if [ ! $? -eq 0 ]; then
      echo "" >> $crontab_tmp
      echo "# PostgreSQL Database support   " >> $crontab_tmp
      echo "0,5,10,15,20,25,30,35,40,45,50,55 * * * *  $HOMELPAR/load_postgres.sh > $HOMELPAR/load_postgres.out 2>&1 " >> $crontab_tmp
    fi

    # IBM Db2
    grep  "load_db2.sh" $crontab_tmp >/dev/null 2>&1
    if [ ! $? -eq 0 ]; then
      echo "" >> $crontab_tmp
      echo "# IBM Db2 support   " >> $crontab_tmp
      echo "0,5,10,15,20,25,30,35,40,45,50,55 * * * *  $HOMELPAR/load_db2.sh > $HOMELPAR/load_db2.out 2>&1 " >> $crontab_tmp
    fi

    if [ -s $crontab_tmp ]; then
      crontab < $crontab_tmp
    else
      echo "ERROR: crontab has not been updated, perhaps not enough space in /tmp, Hyper-V, XEN, oVirt / RHV and  IBM Power REST API support miss in crontab"
      echo ""
    fi
 fi
else
 # Non image environment

 # IBM Power
 # first check if HMC is used (mean IBM Power is configured), if so then place crontab automatically
 for hmc in $HMC_LIST
 do
   if [ `ls -ld data/*/$hmc 2>/dev/null| wc -l | sed 's/ //g'` -gt  0 ]; then
     # HMC is configured and used, go ahead!
     if [ `grep load.sh $crontab_tmp| sed 's/#.*$//g'| grep "$HOMELPAR"| wc -l | sed 's/ //g'| wc -l` -gt 0 ]; then
       # musi tam uz byt i load.sh jinak nic nedelat
       if [ `grep load_hmc_rest_api.sh $crontab_tmp| sed 's/#.*$//g'| grep "$HOMELPAR"| wc -l | sed 's/ //g'| wc -l` -eq 0 ]; then
         # add it
         echo "" >> $crontab_tmp
         echo "# IBM Power Systems - REST API" >> $crontab_tmp
         echo "0,20,40 * * * * $HOMELPAR/load_hmc_rest_api.sh > $HOMELPAR/load_hmc_rest_api.out 2>&1" >> $crontab_tmp
         if [ -s $crontab_tmp ]; then
           crontab < $crontab_tmp
           crontab -l > $crontab_tmp
         else
           echo "ERROR: crontab has not been updated, perhaps not enough space in /tmp, IBM Power REST API misses in entry in crontab"
           echo ""
         fi
         break
       fi
     fi
   fi
 done

 # MS Hyper-V
 grep  "load_hyperv.sh" $crontab_tmp >/dev/null 2>&1
 if [ ! $? -eq 0 ]; then
   echo "" >> $crontab_tmp
   echo "# MS Hyper-V support   " >> $crontab_tmp
   echo "0,20,40 * * * *  $HOMELPAR/load_hyperv.sh > $HOMELPAR/load_hyperv.out 2>&1 " >> $crontab_tmp
   if [ -s $crontab_tmp ]; then
     crontab < $crontab_tmp
   else
     echo "ERROR: crontab has not been updated, perhaps not enough space in /tmp, Hyper-V support misses in crontab"
     echo ""
   fi
 fi

 # XEN
 grep  "load_xenserver.sh" $crontab_tmp >/dev/null 2>&1
 if [ ! $? -eq 0 ]; then
   echo "" >> $crontab_tmp
   echo "# XEN Server support   " >> $crontab_tmp
   echo "0,20,40 * * * *  $HOMELPAR/load_xenserver.sh > $HOMELPAR/load_xenserver.out 2>&1 " >> $crontab_tmp
   if [ -s $crontab_tmp ]; then
     crontab < $crontab_tmp
   else
     echo "ERROR: crontab has not been updated, perhaps not enough space in /tmp, XEN Server support misses in crontab"
     echo ""
   fi
 fi

 # oVirt
 grep  "load_ovirt.sh" $crontab_tmp >/dev/null 2>&1
 if [ ! $? -eq 0 ]; then
   echo "" >> $crontab_tmp
   echo "# oVirt / RHV support   " >> $crontab_tmp
   echo "0,20,40 * * * *  $HOMELPAR/load_ovirt.sh > $HOMELPAR/load_ovirt.out 2>&1 " >> $crontab_tmp
   if [ -s $crontab_tmp ]; then
     crontab < $crontab_tmp
   else
     echo "ERROR: crontab has not been updated, perhaps not enough space in /tmp, oVirt / RHV support misses in crontab"
     echo ""
   fi
 fi

 # OracleVM
 grep  "load_oraclevm.sh" $crontab_tmp >/dev/null 2>&1
 if [ ! $? -eq 0 ]; then
   echo "" >> $crontab_tmp
   echo "# OracleVM support   " >> $crontab_tmp
   echo "0,20,40 * * * *  $HOMELPAR/load_oraclevm.sh > $HOMELPAR/load_oraclevm.out 2>&1 " >> $crontab_tmp
   if [ -s $crontab_tmp ]; then
     crontab < $crontab_tmp
   else
     echo "ERROR: crontab has not been updated, perhaps not enough space in /tmp, OracleVM support misses in crontab"
     echo ""
   fi
 fi

 # Nutanix
 grep  "load_nutanix.sh" $crontab_tmp >/dev/null 2>&1
 if [ ! $? -eq 0 ]; then
   echo "" >> $crontab_tmp
   echo "# Nutanix  " >> $crontab_tmp
   echo "0,20,40 * * * *  $HOMELPAR/load_nutanix.sh > $HOMELPAR/load_nutanix.out 2>&1 " >> $crontab_tmp
   if [ -s $crontab_tmp ]; then
     crontab < $crontab_tmp
   else
     echo "ERROR: crontab has not been updated, perhaps not enough space in /tmp, Nutanix support misses in crontab"
     echo ""
   fi
 fi

 # OracleDB
 grep  "load_oracledb.sh" $crontab_tmp >/dev/null 2>&1
 if [ ! $? -eq 0 ]; then
   echo "" >> $crontab_tmp
   echo "# Oracle Database support   " >> $crontab_tmp
   echo "0,5,10,15,20,25,30,35,40,45,50,55 * * * *  $HOMELPAR/load_oracledb.sh > $HOMELPAR/load_oracledb.out 2>&1 " >> $crontab_tmp
   if [ -s $crontab_tmp ]; then
     crontab < $crontab_tmp
   else
     echo "ERROR: crontab has not been updated, perhaps not enough space in /tmp, Oracle Database support misses in crontab"
     echo ""
   fi
 fi

 # AWS
 grep  "load_aws.sh" $crontab_tmp >/dev/null 2>&1
 if [ ! $? -eq 0 ]; then
   echo "" >> $crontab_tmp
   echo "# AWS support   " >> $crontab_tmp
   echo "0,20,40 * * * *  $HOMELPAR/load_aws.sh > $HOMELPAR/load_aws.out 2>&1 " >> $crontab_tmp
   if [ -s $crontab_tmp ]; then
     crontab < $crontab_tmp
   else
     echo "ERROR: crontab has not been updated, perhaps not enough space in /tmp, AWS support misses in crontab"
     echo ""
   fi
 fi

 # Azure
 grep  "load_azure.sh" $crontab_tmp >/dev/null 2>&1
 if [ ! $? -eq 0 ]; then
   echo "" >> $crontab_tmp
   echo "# Azure support   " >> $crontab_tmp
   echo "0,20,40 * * * *  $HOMELPAR/load_azure.sh > $HOMELPAR/load_azure.out 2>&1 " >> $crontab_tmp
   if [ -s $crontab_tmp ]; then
     crontab < $crontab_tmp
   else
     echo "ERROR: crontab has not been updated, perhaps not enough space in /tmp, Azure support misses in crontab"
   fi
 fi

 # GCloud
 grep  "load_gcloud.sh" $crontab_tmp >/dev/null 2>&1
 if [ ! $? -eq 0 ]; then
   echo "" >> $crontab_tmp
   echo "# Gcloud support   " >> $crontab_tmp
   echo "0,20,40 * * * *  $HOMELPAR/load_gcloud.sh > $HOMELPAR/load_gcloud.out 2>&1 " >> $crontab_tmp
   if [ -s $crontab_tmp ]; then
     crontab < $crontab_tmp
   else
     echo "ERROR: crontab has not been updated, perhaps not enough space in /tmp, Gcloud support misses in crontab"
     echo ""
   fi
 fi

 # Kubernetes
 grep  "load_kubernetes.sh" $crontab_tmp >/dev/null 2>&1
 if [ ! $? -eq 0 ]; then
   echo "" >> $crontab_tmp
   echo "# Kubernetes support   " >> $crontab_tmp
   echo "0,20,40 * * * *  $HOMELPAR/load_kubernetes.sh > $HOMELPAR/load_kubernetes.out 2>&1 " >> $crontab_tmp
   if [ -s $crontab_tmp ]; then
     crontab < $crontab_tmp
   else
     echo "ERROR: crontab has not been updated, perhaps not enough space in /tmp, Kubernetes support misses in crontab"
     echo ""
   fi
 fi

 # OpenShift
 grep  "load_openshift.sh" $crontab_tmp >/dev/null 2>&1
 if [ ! $? -eq 0 ]; then
   echo "" >> $crontab_tmp
   echo "# RedHat OpenShift support   " >> $crontab_tmp
   echo "0,20,40 * * * *  $HOMELPAR/load_openshift.sh > $HOMELPAR/load_openshift.out 2>&1 " >> $crontab_tmp
   if [ -s $crontab_tmp ]; then
     crontab < $crontab_tmp
   else
     echo "ERROR: crontab has not been updated, perhaps not enough space in /tmp, OpenShift support misses in crontab"
     echo ""
   fi
 fi

 # Proxmox
 grep  "load_proxmox.sh" $crontab_tmp >/dev/null 2>&1
 if [ ! $? -eq 0 ]; then
   echo "" >> $crontab_tmp
   echo "# Proxmox support   " >> $crontab_tmp
   echo "0,20,40 * * * *  $HOMELPAR/load_proxmox.sh > $HOMELPAR/load_proxmox.out 2>&1 " >> $crontab_tmp
   if [ -s $crontab_tmp ]; then
     crontab < $crontab_tmp
   else
     echo "ERROR: crontab has not been updated, perhaps not enough space in /tmp, Proxmox support misses in crontab"
     echo ""
   fi
 fi

 # PostgreSQL
 grep  "load_postgres.sh" $crontab_tmp >/dev/null 2>&1
 if [ ! $? -eq 0 ]; then
   echo "" >> $crontab_tmp
   echo "# PostgreSQL Database support   " >> $crontab_tmp
   echo "0,5,10,15,20,25,30,35,40,45,50,55 * * * *  $HOMELPAR/load_postgres.sh > $HOMELPAR/load_postgres.out 2>&1 " >> $crontab_tmp
   if [ -s $crontab_tmp ]; then
     crontab < $crontab_tmp
   else
     echo "ERROR: crontab has not been updated, perhaps not enough space in /tmp, Oracle Database support misses in crontab"
     echo ""
   fi
 fi

 # MS SQL Server
 grep  "load_sqlserver.sh" $crontab_tmp >/dev/null 2>&1
 if [ ! $? -eq 0 ]; then
   echo "" >> $crontab_tmp
   echo "# MS SQL Server database support   " >> $crontab_tmp
   echo "0,5,10,15,20,25,30,35,40,45,50,55 * * * *  $HOMELPAR/load_sqlserver.sh > $HOMELPAR/load_sqlserver.out 2>&1 " >> $crontab_tmp
   if [ -s $crontab_tmp ]; then
     crontab < $crontab_tmp
   else
     echo "ERROR: crontab has not been updated, perhaps not enough space in /tmp, Oracle Database support misses in crontab"
     echo ""
   fi
 fi

 # fusioncompute
 grep  "load_fusioncompute.sh" $crontab_tmp >/dev/null 2>&1
 if [ ! $? -eq 0 ]; then
   echo "" >> $crontab_tmp
   echo "# Fusion Compute support   " >> $crontab_tmp
   echo "0,20,40 * * * *  $HOMELPAR/load_fusioncompute.sh > $HOMELPAR/load_fusioncompute.out 2>&1 " >> $crontab_tmp
   if [ -s $crontab_tmp ]; then
     crontab < $crontab_tmp
   else
     echo "ERROR: crontab has not been updated, perhaps not enough space in /tmp, Fusion Compute support misses in crontab"
     echo ""
   fi
 fi

fi
rm -f $crontab_tmp

# Hyper-V: fix of an error when was placed in crontab this wrong path (in 6.00):
# 0,20,40 * * * *  $HOMELPAR/lpar2rrd/load_hyperv.sh > $HOMELPAR/load_hyperv.out 2>&1 "
#
if [ `crontab -l| egrep "$HOMELPAR/lpar2rrd/load_hyperv.sh " | wc -l | sed 's/ //g'` -gt 0 ]; then
  crontab -l | egrep -v "$HOMELPAR/lpar2rrd/load_hyperv.sh|Hyper-V" > $crontab_tmp
  echo "" >> $crontab_tmp
  echo "# MS Hyper-V support   " >> $crontab_tmp
  echo "0,20,40 * * * *  $HOMELPAR/load_hyperv.sh > $HOMELPAR/load_hyperv.out 2>&1 " >> $crontab_tmp
  crontab < $crontab_tmp
  rm -f $crontab_tmp
fi


cron_all=`crontab -l 2>/dev/null| egrep "\/load.sh|\/load_.*sh " | grep lpar2rrd | egrep -v "#"|sed -e 's/ >.*//g' -e 's/^.*\* //g'| wc -l`
cron_uniq=`crontab -l 2>/dev/null| egrep "\/load.sh|\/load_.*sh " | grep lpar2rrd | egrep -v "#"|sed -e 's/ >.*//g' -e 's/^.*\* //g' |sort|uniq|wc -l`
if [ $cron_all -gt $cron_uniq ]; then
  echo "ERROR: You have probably duplicated rows in crontab, check it manually  via: crontab -e:"
  echo "=========="
  crontab -l 2>/dev/null| egrep "\/load.sh|\/load_.*sh " | grep lpar2rrd | egrep -v "#"|sed -e 's/ >.*//g' -e 's/^.*\* //g'| sort
  echo "=========="
  echo ""
fi

if [ $os_aix -eq 1 ]; then
  # AIX (at least) rrdtool 1.7 issue when prints mem profiling info to pwd/mon.out
  touch $HOMELPAR/lpar2rrd-cgi/mon.out
  chmod 777 $HOMELPAR/lpar2rrd-cgi/mon.out
  touch $HOMELPAR/bin/mon.out
  chmod 777 $HOMELPAR/bin/mon.out
  touch $HOMELPAR/tmp/home/mon.out 2>/dev/null
  chmod 777 $HOMELPAR/tmp/home/mon.out 2>/dev/null
fi


# lpar2rrd v5.08-6+ (new Solaris implementation uses that as a directory)
if [ -h "$HOMELPAR/data/Solaris" ]; then
  rm -f "$HOMELPAR/data/Solaris"
fi

# remove menu cache files if they exist
rm -f $HOMELPAR/tmp/env.cache $HOMELPAR/tmp/menu.cache

# remove possibility to collect logs from UI
rm -f $HOMELPAR/lpar2rrd-cgi/collect_logs.sh $HOMELPAR/html/support_logs.html $HOMELPAR/bin/collect_logs.pl $HOMELPAR/lpar2rrd-cgi/test-healthcheck-cgi.sh

# clean out from old programs
rm -f $HOMELPAR/scripts/update_cfg_alert.sh $HOMELPAR/scripts/update_cfg_custom-groups.sh $HOMELPAR/scripts/update_cfg_custom-groups.sh_pre_4.70 $HOMELPAR/scripts/update.sh $HOMELPAR/bin/qs_volume.pl
rm -f $HOMELPAR/bin/hyperv_cmd.pl $HOMELPAR/bin/hyperv_load.pl $HOMELPAR/bin/check_stor2rrd $HOMELPAR/bin/alrt_ext.pl $HOMELPAR/bin/AlertStor2rrd.pm $HOMELPAR/bin/Storcfg2html.pm $HOMELPAR/bin/LAST_SYNC
rm -f $HOMELPAR/bin/svcconfig.pl $HOMELPAR/bin/storage.pl $HOMELPAR/bin/lpar2rrd-agent.pl $HOMELPAR/bin/load_entitle.sh $HOMELPAR/bin/hcheck.sh $HOMELPAR/bin/hist_reports.sh $HOMELPAR/bin/extract.pl $HOMELPAR/bin/diff.sh $HOMELPAR/alert.sh $HOMELPAR/bin/alert.cfg
rm -f $HOMELPAR/bin/san_clean.sh $HOMELPAR/bin/update_data $HOMELPAR/bin/svcperf.pl $HOMELPAR/bin/print_hist_intervals.pl $HOMELPAR/bin/MD5.pm
rm -f $HOMELPAR/bin/alert.sh $HOMELPAR/bin/alerting.pl $HOMELPAR/bin/update_data.sh $HOMELPAR/bin/.lpar-search.pl.swp
rm -f $HOMELPAR/html/jquery/.gitignore $HOMELPAR/www/jquery/.gitignore  $HOMELPAR/bin/.lpar2rrd-daemon.pl.swp

# Must be at the end due to HOME setting
if [ $os_aix -gt 0 ]; then
  # Font cache refresh, it migh speed up significantly graphs creation on AIX
  # it creates it in /home/lpar2rrd/tmp/home/.cache/fontconfig and in /home/lpar2rrd/.cache/fontconfig
  if [ ! -d "$HOMELPAR/tmp/home" ]; then
    mkdir "$HOMELPAR/tmp/home"
  fi
  fc-cache -fv 1>/dev/null 2>&1 # used -f since 7.42
  HOME="$HOMELPAR/tmp/home"; fc-cache -fv 1>/dev/null 2>&1
fi

# IPv6 support, however not on AIX, there is an issue
if [ ! $os_aix -eq 1 ]; then
  rhel_ver_check=`rpm --eval '%{rhel}' 2>/dev/null`
  if [ $? -eq 0 ]; then
    # skip CentOS 6 and older
    if [ ! -n "$rhel_ver_check" ] || [ `echo $rhel_ver_check| grep rhel| wc -l| sed 's/ //g'` -eq 1 ] || [ "$rhel_ver_check" -gt 6 ]; then
      for file_snmp in $HOMELPAR/bin/*.pl
      do
ed $file_snmp << EOF 1>/dev/null 2>/dev/null
g/IO::Socket::INET/s/IO::Socket::INET/IO::Socket::IP/g
w
q
EOF
      done
      for file_snmp in $HOMELPAR/bin/*.pm
      do
ed $file_snmp << EOF 1>/dev/null 2>/dev/null
g/IO::Socket::INET/s/IO::Socket::INET/IO::Socket::IP/g
w
q
EOF
      done
    fi
  else
    # OS version not found, go ahead only in case of Linux
    if [ `uname -s` = "Linux" ]; then
      for file_snmp in $HOMELPAR/bin/*.pl
      do
ed $file_snmp << EOF 1>/dev/null 2>/dev/null
g/IO::Socket::INET/s/IO::Socket::INET/IO::Socket::IP/g
w
q
EOF
      done
      for file_snmp in $HOMELPAR/bin/*.pm
      do
ed $file_snmp << EOF 1>/dev/null 2>/dev/null
g/IO::Socket::INET/s/IO::Socket::INET/IO::Socket::IP/g
w
q
EOF
      done
    fi
  fi
fi

# Checking installed Perl modules, it must be after above IPv6
cd $HOMELPAR
. etc/lpar2rrd.cfg; export INPUTDIR=$HOMELPAR; $PERL bin/perl_modules_check.pl $PERL
echo ""

# add unique ID of each device
# it must be behind bin/perl_modules_check.pl to use environment setup PERL5LIB (especially bin must be there)
# KZ note: run this script in each upgrade, before it was only when upgrade was from version less than 704
cd $HOMELPAR/
export INPUTDIR=$HOMELPAR # this must be defined for bin/uniqueid.pl!!!
$PERL_act bin/uniqueid.pl  > logs/uniqueid.log 2>&1

# DB schema update, must be behind env setup PERL5LIB
if [ -f "$HOMELPAR/data/_DB/data.db" ]; then
  for sql in `ls $HOMELPAR/dbschema/*| sort `
  do
    sql_name=`basename $sql .sql`
    if [ $sql_name -ge $VER_ORG ]; then
      echo "DB schema update: $sql"
      sqlite3 -cmd '.timeout 30000' $HOMELPAR/data/_DB/data.db < $sql
      if [ ! $? -eq 0 ]; then
        echo "SQLite DB lock perhaps, wait 5 seconds and try again"
        sleep 5
        sqlite3 -cmd '.timeout 30000' $HOMELPAR/data/_DB/data.db < $sql
      fi
    fi
  done
fi

if [ -f "$HOMELPAR/data/_DB/data.db" ]; then
  # DB init: every time, add new stuff
  sqlite3 -cmd '.timeout 30000' $HOMELPAR/data/_DB/data.db < $HOMELPAR/etc/dbinit.sql
fi

if [ $VER_ORG -lt 712 ]; then
  echo "./bin/alert_history_log_fmt.sh"
  cd $HOMELPAR
  ./bin/alert_history_log_fmt.sh
  cd - >/dev/null
fi

if [ $VER_ORG -lt 742 ]; then
  if [ -d "$HOMELPAR/data/oVirt/storage" ]; then
    echo ""
    echo "Removing wrong RHV storage IOPS data"
    echo ""
    rm -f $HOMELPAR/data/oVirt/storage/disk2-*.rrd
  fi
fi

# Removal of temp files not being removed, only for IBM Power, it tests HMC presence at first
ibm_power=`ls -l $HOMELPAR/data/*.rrx 2>/dev/null| wc -l| sed 's/ //g'`
if [ $ibm_power -gt 0 ]; then
  echo ""
  echo "Removing uncleared temporary files ..."
  find $HOMELPAR/data -type f -name cpu-pools-mapping.txt-tmp-\* -exec rm -f {} \;
  # session files, they will be moved to tmp dir in 7.52 or so
  find $HOMELPAR/data -mtime +1 -type f -name "session_*.tmp" -exec rm -f  {}  \;
fi

# removal of some temp files
rm -f $HOMELPAR/tmp/alert_graph_*png

# Test if HMCs are not over the limit, env is alredy set above
# only for IBM Power
over_limit=""
if [ $free_edition_new -eq 1 ]; then
  # free edition
  over_limit=`$PERL -MHostCfg -e 'HostCfg::getUnlicensed();'`
else
  # IBM Power edition must be included, othervise also print, check act dir to see if that is a full version
  ibm_power_full=`echo $pwd| egrep "lpar2rrd-[1-9].*-p[a-z,-].*full|lpar2rrd-[0-9,.,-]*-full"| wc -l|  sed 's/ //g'`
  if [ $free_edition_new -eq 0 -a $ibm_power_full -eq 0 ]; then
    over_limit=`$PERL -MHostCfg -e 'HostCfg::getUnlicensed();'`
  fi
fi
if [ ! "$over_limit"x = "x" ]; then
  #print excluded HMCs
  echo ""
  echo "*********************************"
  echo "************ WARNING ************"
  echo "You have configured more than 4 HMCs, limit of the Free edition is 4"
  echo "Consider to upgrade to the Enterprise edition: https://lpar2rrd.com/support.php"
  echo "List of excluded HMCs (will not be updated anymore):"
  echo ""
  $PERL -MHostCfg -e 'HostCfg::getUnlicensed();'
  echo ""
  echo ""
  echo "************ WARNING ************"
  echo "*********************************"
  echo ""
fi
#echo "==== $ibm_power - $ibm_power_full : $free_edition_new - $free_edition_org == $pwd"

echo ""
echo "Upgrade to version $version_new is done"
echo "Now you can start the tool:"
echo ""
echo " cd $HOMELPAR"
echo " ./load.sh 2>&1 | tee logs/load.out-initial"
echo ""
echo "Wait for finishing of that, then refresh the GUI (Ctrl-F5)"
echo ""


if [ "$VM_IMAGE"x = "x" -a $check -eq 1 -a $VER_ORG -lt 480 ]; then
  # not for image so far, it might be too slow
  echo ""
  echo "Checking consistency of all RRDtool DB files, it might take a few minutes in a big environment"
  echo "You can leave it running or interrupt it by Ctrl-C and start it whenever later on"
  echo "  just check out the results when it finishes"
  echo "cd $HOMELPAR; ./bin/check_rrdtool.sh silent"
  cd $HOMELPAR
  ./bin/check_rrdtool.sh silent
  cd - >/dev/null
fi



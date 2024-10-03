#!/bin/ksh

# Load STOR2RRD environment
CGID=`dirname $0`
if [ "$CGID" = "." ]; then
  CGID=`pwd`
fi
INPUTDIR_NEW=`dirname $CGID`
. $INPUTDIR_NEW/etc/lpar2rrd.cfg

umask 000

# Load "magic" setup
if [ -f $INPUTDIR/etc/.magic ]; then
  . $INPUTDIR/etc/.magic
fi

#
# 1. test if DBI module is installed
#
ret=`$PERL -e 'eval "use DBI; print 1" or print 0'`
if [ $ret -eq "0" ]; then
  echo "DBI module is not installed correctly!"
  echo ""
  echo "NOK"
  echo "Follow installation manual: https://xormon.com/install-xormon.php#backend"
  exit 1
fi

#
# 2. test creating temporary DB
#
err_tmp="$INPUTDIR/tmp/tmp.db-err"
db_tmp="$INPUTDIR/tmp/tmp.db"

if [ -f $db_tmp ]; then
  rm -f $db_tmp
fi
if [ -f $err_tmp ]; then
  rm -f $err_tmp
fi

ret=`$PERL -I. -MSQLiteDataWrapper -e 'SQLiteDataWrapper::dbConnect({ db_file => "'$db_tmp'" })' 2>$err_tmp`

if [ -s $err_tmp ]; then
  cat $err_tmp
  rm -f $err_tmp

  if [ -f $db_tmp ]; then
    rm -f $db_tmp
  fi

  echo ""
  echo ""
  echo "SQLite is not installed correctly!"
  echo ""
  echo "NOK"
  echo "Follow installation manual: https://xormon.com/install-xormon.php#backend"
  exit 1
fi

if [ -f $err_tmp ]; then
  rm -f $err_tmp
fi
if [ -f $db_tmp ]; then
  rm -f $db_tmp

  #echo "Temporary SQLite DB was created succesfully!"
  #exit 0
fi

#
# 3. test SQLite version, must be higher than 3.8
#
cmd="sqlite3 --version"
ret=`$cmd`
ver=`echo $ret | awk 'BEGIN{FS=" "}{print $1}'`
fir=`echo $ver | awk 'BEGIN{FS="."}{print $1}'`
sec=`echo $ver | awk 'BEGIN{FS="."}{print $2}'`
if [ "$fir"x = "x" -o "$sec"x = "x" ]; then
  echo "Cannot recognize SQLite version! Must be at least 3.8 or higher!"
  echo $cmd
  echo $ret

  echo ""
  echo "NOK"
  echo "Follow installation manual: https://xormon.com/install-xormon.php#backend"
  exit 1
fi
if [ $fir -lt 3 ]; then
  echo "SQLite version is too old! Must be at least 3.8 or higher!"
  echo $cmd
  echo $ret

  echo ""
  echo "NOK"
  echo "Follow installation manual: https://xormon.com/install-xormon.php#backend"
  exit 1
fi
if [ $sec -lt 8 ]; then
  echo "SQLite version is too old! Must be at least 3.8 or higher!"
  echo $cmd
  echo $ret

  echo ""
  echo "NOK"
  echo "Follow installation manual: https://xormon.com/install-xormon.php#backend"
  exit 1
fi

echo ""
echo "OK"
exit 0

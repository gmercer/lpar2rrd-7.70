#!/bin/sh

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

if [ $XORMON ] && [ "$XORMON" != "0" ] && [ "$XORMON" != "1" ] && [ $REMOTE_ADDR ] && [ $HTTP_XORUX_APP == "Xormon" ]; then
    if [ "$REMOTE_ADDR" != "$XORMON" ]; then
        echo "Content-type: text/plain"
        echo "Status: 412 IP not allowed";
        echo ""
        echo "IP address $REMOTE_ADDR is not trusted Xormon host!"
        exit
    fi
fi

# Content-type
echo "Content-type: text/plain"

#
# 1. test if DBI module is installed
#
ret=`$PERL -e 'eval "use DBI; print 1" or print 0'`
if [ $ret -eq "0" ]; then
  echo "Xorux-Status: ERROR"
  echo ""
  echo "DBI module is not installed correctly!"
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
  echo "Xorux-Status: ERROR"
  echo ""
  cat $err_tmp
  rm -f $err_tmp

  if [ -f $db_tmp ]; then
    rm -f $db_tmp
  fi

  echo ""
  echo ""
  echo "SQLite is not installed correctly!"
  echo "Follow installation manual: https://xormon.com/install-xormon.php#backend"
  exit 1
fi

if [ -f $err_tmp ]; then
  rm -f $err_tmp
fi
if [ -f $db_tmp ]; then
  rm -f $db_tmp

  #echo "Xorux-Status: OK"
  #echo ""
  #echo "Temporary SQLite DB was created succesfully!"
  #echo ""
  #echo "OK"
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
  echo "Xorux-Status: ERROR"
  echo ""
  echo "Cannot recognize SQLite version! Must be at least 3.8 or higher!"
  echo $cmd
  echo $ret
  echo ""
  echo "Follow installation manual: https://xormon.com/install-xormon.php#backend"
  exit 1
fi
if [ $fir -lt 3 ]; then
  echo "Xorux-Status: ERROR"
  echo ""
  echo "SQLite version is too old! Must be at least 3.8 or higher!"
  echo $cmd
  echo $ret
  echo ""
  echo "Follow installation manual: https://xormon.com/install-xormon.php#backend"
  exit 1
fi
if [ $sec -lt 8 ]; then
  echo "Xorux-Status: ERROR"
  echo ""
  echo "SQLite version is too old! Must be at least 3.8 or higher!"
  echo $cmd
  echo $ret
  echo ""
  echo "Follow installation manual: https://xormon.com/install-xormon.php#backend"
  exit 1
fi

echo "Xorux-Status: OK"
echo ""
exit 0

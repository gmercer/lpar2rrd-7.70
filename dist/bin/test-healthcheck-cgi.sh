#!/bin/ksh
#
#
# Output redirection to logs/test-healthcheck.log
#
# Copy that script before usage to stor2rrd-cgi directory
# it is not there by default to for security purposes
#


# Load LPAR2RRD environment
CGID=`dirname $0`
if [ "$CGID" = "." ]; then
  CGID=`pwd`
fi
INPUTDIR_NEW=`dirname $CGID`
. $INPUTDIR_NEW/etc/lpar2rrd.cfg

# Load "magic" setup
if [ -f $INPUTDIR/etc/.magic ]; then
  . $INPUTDIR/etc/.magic
fi

umask 000
ERRLOG="/var/tmp/lpar2rrd-realt-error.log"
export ERRLOG

rm -f $LOGDIR/test-healthcheck.log

exec $BINDIR/test-healthcheck.sh 2>>$ERRLOG | tee $LOGDIR/test-healthcheck.log

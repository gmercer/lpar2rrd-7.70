#!/bin/sh

# Load LPAR2RRD environment
CGID=`dirname $0`
if [ "$CGID" = "." ]; then
  CGID=`pwd`
fi
INPUTDIR_NEW=`dirname $CGID`
. $INPUTDIR_NEW/etc/lpar2rrd.cfg

TMPDIR_LPAR="$INPUTDIR/tmp"
export TMPDIR_LPAR

# Load "magic" setup
if [ -f $INPUTDIR/etc/.magic ]; then
  . $INPUTDIR/etc/.magic
fi

umask 000
ERRLOG="/var/tmp/lpar2rrd-realt-error.log"
export ERRLOG

if [ $XORMON ] && [ "$XORMON" != "0" ] && [ "$XORMON" != "1" ] && [ $REMOTE_ADDR ] && [ $HTTP_XORUX_APP == "Xormon" ]; then
    if [ "$REMOTE_ADDR" != "$XORMON" ]; then
        echo "Content-type: text/plain"
        echo "Status: 412 IP not allowed";
        echo ""
        echo "IP address $REMOTE_ADDR is not trusted Xormon host!"
        exit
    fi
fi

exec $PERL $BINDIR/lpar2rrd-cgi.pl 2>>$ERRLOG


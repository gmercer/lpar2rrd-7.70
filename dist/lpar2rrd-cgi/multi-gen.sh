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

if [ ! "$VM_IMAGE"x = "x" -o ! "$VI_IMAGE"x = "x" ]; then
  # keep 022 umask on image, it is all running under same user
  umask 022
else
  # must be 000, lpar2rrd user must be able to remove apache owned files
  umask 002
fi

ERRLOG="/var/tmp/lpar2rrd-realt-error.log"
export ERRLOG

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

exec $PERL $BINDIR/gen_multi.pl 2>>$ERRLOG


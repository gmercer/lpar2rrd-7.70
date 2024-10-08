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

umask 002
ERRLOG="/var/tmp/lpar2rrd-realt-error.log"
export ERRLOG

# Load "magic" setup
if [ -f $INPUTDIR/etc/.magic ]; then
  . $INPUTDIR/etc/.magic
fi

if [ $XORMON ] && [ "$XORMON" != "0" ] && [ "$XORMON" != "1" ] && [ $REMOTE_ADDR ] && [ $HTTP_XORUX_APP == "Xormon" ]; then
    if [ "$REMOTE_ADDR" != "$XORMON" ]; then
        printf "Content-type: text/plain\n"
        printf "Status: 412 IP not allowed\n";
        printf "\n"
        printf "Host $REMOTE_ADDR is not trusted Xormon host!";
        exit
    fi
fi

exec $PERL $BINDIR/settings.pl 2>>$ERRLOG


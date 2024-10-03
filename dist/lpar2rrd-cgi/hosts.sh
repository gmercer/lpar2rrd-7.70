#!/bin/sh

# Load LPAR2RRD environment
CGID=`dirname $0`
if [ "$CGID" = "." ]; then
  CGID=`pwd`
fi
INPUTDIR_NEW=`dirname $CGID`
. $INPUTDIR_NEW/etc/lpar2rrd.cfg

if [ `uname -a|grep AIX|wc -l` -gt 0 ]; then
  # AIX tricks to get it work together with VMware
  PERL5LIB=$INPUTDIR/lib:$PERL5LIB
  export PERL5LIB

  # /usr/lib must be the first, but /opt/freeware/lib must be included as well
  LIBPATH=/usr/lib:/opt/freeware/lib:$LIBPATH
  export LIBPATH
fi

TMPDIR_LPAR="$INPUTDIR/tmp"
export TMPDIR_LPAR

umask 002
ERRLOG="/var/tmp/lpar2rrd-realt-error.log"
export ERRLOG
export VM_IMAGE=1

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

exec $PERL $BINDIR/host_cfg.pl 2>>$ERRLOG


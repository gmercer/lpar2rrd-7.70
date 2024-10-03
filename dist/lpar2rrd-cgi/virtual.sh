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

umask 000
ERRLOG="/var/tmp/lpar2rrd-realt-error.log"
export ERRLOG

exec $PERL $BINDIR/virtual-cpu-acc.pl 2>>$ERRLOG


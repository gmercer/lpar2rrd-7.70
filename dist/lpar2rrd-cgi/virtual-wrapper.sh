#!/bin/sh
# 
# Load LPAR2RRD environment
CGID=`dirname $0`
if [ "$CGID" = "." ]; then
  CGID=`pwd`
fi
INPUTDIR_NEW=`dirname $CGID`
. $INPUTDIR_NEW/etc/lpar2rrd.cfg

TMPDIR="$INPUTDIR/tmp"
export TMPDIR

umask 000
ERRLOG="/var/tmp/lpar2rrd-realt-error.log"
export ERRLOG

#echo "$QUERY_STRING" >> /tmp/qrstpr


echo "Content-type: text/html"
echo ""
echo "<html><body><p>"
echo "<iframe src='/lpar2rrd-cgi/virtual-cgi.sh?$QUERY_STRING' style='position: absolute; width: 99%; height: 90%; border: 0'>"
echo "</iframe>"
echo "</body></html>"

#!/bin/sh
#
# CGI-BIN testing script
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

umask 000
ERRLOG="/var/tmp/lpar2rrd-realt-error.log"
export ERRLOG

echo "Content-type: text/html"
echo ""
echo "<HTML>"
echo "<body><h2>It is working!</h2>"
echo "<b>You should see LPAR2RRD environment here:</b><pre>"
set|egrep -i "HMC|DOCUMENT_ROOT|HEA|COD|HWINFO|LPM|PERL|PICTURE|RRD|lpar2rrd|BINDIR|EXPORT_TO_CSV|LDR_CNTRL|MANAGED_SYSTEMS|MAX_ENT|SAMPLE_RATE|SYS_CHANGE|TOPTEN|DEBUG|version="|egrep -v "^_="
echo "</pre><br><br><b>Here is the OS environment:</b><pre>"
set|egrep -iv "HMC|DOCUMENT_ROOT|HEA|COD|HWINFO|LPM|PERL|PICTURE|RRD|lpar2rrd|BINDIR|EXPORT_TO_CSV|LDR_CNTRL|MANAGED_SYSTEMS|MAX_ENT|SAMPLE_RATE|SYS_CHANGE|TOPTEN|DEBUG|version="|egrep -v "^_="
echo "</pre></body></html>"

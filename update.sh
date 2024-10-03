#!/bin/sh
#
# LPAR2RRD update script wrapper
# usage : ./update.sh
#
#
LOG="/var/tmp/lpar2rrd-install.log-$$"

sh ./scripts/$0 $1 2>&1| tee $LOG

PRODUCT_HOME=`cat "$HOME/.lpar2rrd_home"`
if [ -f "$HOME/.lpar2rrd_home" -a -d "$PRODUCT_HOME" ]; then
  mv $LOG $PRODUCT_HOME/logs 2>/dev/null
fi

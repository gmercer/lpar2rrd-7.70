#!/bin/ksh
#
# LPAR2RRD example script for external alerting
#
# Note: use this as en example, do not make changes here, this script is overwritten after each upgrade
#

SOURCE=$1 		# Source of the alert
TYPE=$2			# POOL or LPAR (VM)
SERVER=$3		# server name
LPAR_or_POOL=$4 	# VM/LPAR or IBM Power POOL name
ACT_UTILIZATION=$5	# actual utilization
MAX_UTLIZATION_LIMIT=$6 # utilization limit - maximum
HMC=$7                  # HMC for IBM Power
filesystem_name=$8      # FS name in case FS alerting

#
# here is the place for your code ....
#

OUT_FILE=/tmp/alert_log-lpar2rrd

echo "Received alert : $SOURCE $TYPE $SERVER $LPAR_or_POOL $filesystem_name : $ACT_UTILIZATION : $MAX_UTLIZATION_LIMIT - $HMC" >> $OUT_FILE

exit 0

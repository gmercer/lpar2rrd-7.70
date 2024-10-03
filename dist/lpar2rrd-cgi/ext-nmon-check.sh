#!/bin/sh

echo "Content-type: application/json"
echo ""

# check if daemon is running
if ps -ef | grep -q [l]par2rrd-daemon.pl 
then 
	# echo "LPAR2RRD daemon is running"
	DAEMON='true'
else 
	# echo "LPAR2RRD daemon is stopped" 
	DAEMON='false'
fi

# check if agent is installed
if [ -f /opt/lpar2rrd-agent/lpar2rrd-agent.pl ]
then 
	AGENTSAYS=`perl /opt/lpar2rrd-agent/lpar2rrd-agent.pl | head -n 1`
	if echo "$AGENTSAYS" | grep -q version
	then 
		VER=`echo "$AGENTSAYS" | awk -F: '{ print $2 }'`
		# echo "LPAR2RRD agent is installed ($VER)"
		AGENT="\"$VER\""
	else 
		# echo "Cannot determine agent version, please upgrade"
		AGENT='0'
	fi
else 
	# echo "LPAR2RRD daemon is not installed" 
	AGENT='false'
fi
echo "{\"agent\": $AGENT, \"daemon\": $DAEMON}"

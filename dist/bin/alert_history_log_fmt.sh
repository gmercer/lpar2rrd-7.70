#!/bin/ksh

if [ ! -d "etc" ]; then
  if [ -d "../etc" ]; then
    cd ..
  else
    echo "Problem with actual directory, assure you are in LPAR2RRD home"
    echo "Then run : sh load.sh"
    exit
  fi
fi
# Load LPAR2RRD configuration
pwd=`pwd`

CFG="$pwd/etc/lpar2rrd.cfg"
. $CFG

# lpar2rrd home
LparHome="$pwd"

# alert_history.log
AlertHistLog="$LparHome/logs/alert_history.log"
AlertHistLogBkp="${AlertHistLog}.bkp"

# alert_event_history.log
AlertEventHistLog="$LparHome/logs/alert_event_history.log"
AlertEventHistLogBkp="${AlertEventHistLog}.bkp"

# log file, if needed
LogFile="/dev/null"

## alert_history.log
# make sure alert_history.log exists or quit
if [ -f "$AlertHistLog" ]; then # file exists
  # skip if already formatted (check for "; ")
  if grep -e "; " "$AlertHistLog" > /dev/null 2>&1; then
    echo "INFO: $AlertHistLog already reformated"
  else
    # copy alert_history.log to alert_history.log.bkp and reformat if successful
    #cp -pf "$AlertHistLog" "$AlertHistLogBkp" > /dev/null 2>&1
    cp -pf "$AlertHistLog" "$AlertHistLogBkp"
    if [ $? -eq 0 ]; then  # copy successfull
      echo "INFO: $AlertHistLog copied to $AlertHistLogBkp"
      (cat "$AlertHistLogBkp" | sed 's/ *$//g' | sed 's/ \(LPAR\)/:\1/' | sed 's/ \(SERVER\)/:\1/' | sed 's/: /:/' | sed 's/, /; /'| awk -F ":" '{printf "%s:%s:%s; %s; %s; %s; %s:%s:%s:%s\n", $1, $2, $3, $4, $5, $6, $7, $8, $9, $10}'  > "$AlertHistLog")
      echo "INFO: Reformatted $AlertHistLog"
    else # copy failed
      echo "ERROR: Could not copy $AlertHistLog to $AlertHistLogBkp"
      echo "WARN: $AlertHistLog not reformatted"
    fi
  fi
else # file doesn't exist
  echo "WARN: $AlertHistLog does not exist"
fi

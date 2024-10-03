#!/bin/ksh

pwd=`pwd`
if [ -d "etc" ]; then
   path="etc"
else
  if [ -d "../etc" ]; then
    path="../etc"
  else
    if [ ! "$INPUTDIR"x = "x" ]; then
      cd $INPUTDIR >/dev/null
      if [ -d "etc" ]; then
         path="etc"
      else
        if [ -d "../etc" ]; then
          path="../etc"
        else
          echo "problem with actual directory, assure you are in LPAR2RRD home, act directory: $pwd, INPUTDIR=$INPUTDIR"
          exit
        fi
      fi
    else
      echo "problem with actual directory, assure you are in LPAR2RRD home, act directory: $pwd, INPUTDIR=$INPUTDIR"
      exit
    fi
  fi
fi

CFG="$pwd/$path/lpar2rrd.cfg"
. $CFG

if [ ! -f "$PERL" ]; then
  echo "Set correct path to Perl binary in lpar2rrd.cfg, it does not exist here: $PERL"
  exit 1
fi

# Load "magic" setup
if [ -f $INPUTDIR/etc/.magic ]; then
  . $INPUTDIR/etc/.magic
fi

if [ "$#" == 4 ]; then
  # force run
  rm -f "$INPUTDIR/tmp/oVirt_getrestapi.touch"

  #echo "usage: bin/ovirt-api2json.sh <host> <port> <username> <password>"
  host="$1"
  port="$2"
  username="$3"
  password="$4"
  OUT=`$PERL -w $BINDIR/ovirt-api2json.pl "$host" "$port" "$username" "$password"`
  ret=$?
  echo "$OUT"
  exit 0
fi

OUT=`$PERL -w $BINDIR/ovirt-api2json.pl`
ret=$?
echo "$OUT"

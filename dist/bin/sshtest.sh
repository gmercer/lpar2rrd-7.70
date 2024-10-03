#!/bin/ksh

if [ "$#" -lt 3 ]; then
  echo "usage: bin/sshtest.sh <host> <port> <username> <path-to-key>"
  exit 2
fi

if [ "$INPUTDIR"x = "x" ]; then
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
fi

if [ ! -f "$PERL" ]; then
  echo "Set correct path to Perl binary in lpar2rrd.cfg, it does not exist here: $PERL"
  exit 1
fi

# Load "magic" setup
if [ -f $INPUTDIR/etc/.magic ]; then
  . $INPUTDIR/etc/.magic
fi

host="$1"
port="$2"
username="$3"
sshkey="$4"
OUT=`$PERL -w $BINDIR/sshtest.pl "$host" "$port" "$username" "$sshkey"`
ret=$?
echo "$OUT"

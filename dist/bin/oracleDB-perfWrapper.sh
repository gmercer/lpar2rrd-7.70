#!/bin/ksh

BINDIR=$1
MYDB=$2

echo "oracleDB-db2json.pl : collect data from db $MYDB, "`date`
$PERL -w $BINDIR/oracleDB-db2json.pl $MYDB 2>>$ERRLOG

echo "oracleDB-json2rrd.pl : push data to rrd, "`date`

$PERL -w $BINDIR/oracleDB-json2rrd.pl $MYDB 2>>$ERRLOG
echo "oracleDB-json2rrd.pl $MYDB : status $status, "`date`

exit 0

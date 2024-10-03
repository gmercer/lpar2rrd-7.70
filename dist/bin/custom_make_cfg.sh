#!/bin/ksh
#
# TODO
# - prefix ";" in lpar pool names by "\:"

# during upgrade run this and move to alert.cfg
OUT="`pwd`/custom_groups.cfg_template"

echo "Custom groups configuration template will be created here:"
echo "  $OUT"
echo ""

cat << END > $OUT
#
# LPAR2RRD custom group configuration file
#
# It is a configuration file for creating custom groups of lpars
# they are shown separately in the gui and aggregated
# typical usage is for clusters or for lpars running one application
#
# Usage
# below you see simple lpar list. If you want to create a group called "cluster_one"
# then simply after the double coma of lpars you wish place that name
# When a lpar needs to belong to more groups then create a new row with a new group name
# As soon as it is done then you will see the new group under "Custom" page on the web
#
# If you need to use double colon in lpar/pool/group name then prefix it by backslash
# Rows without group name are ignored
#
# You can use wild cards in server name and pool/lpar name
# Examples
#  POOL:.*:.*:pool-all   --> group pool-all will contain all pools from all servers
#  LPAR:.*:.*:lpar-all   --> group lpar-all will contain all lpars from all servers
#  LPAR:p[6,7].*:vio.*:vio-p67  --> group vio-p67 will contain lpars started vio* from servers started with p6 or p7 string
#
#

# [POOL|LPAR]:server:[lpar_name|pool_name]:your_group_name

END

UN=`uname -a`
TWOHYPHENS="--"
if [[ $UN == *"SunOS"* ]]; then TWOHYPHENS=""; fi # problem with basename param on Solaris

cd data
for server in `ls|sort`
do

  if [ -L $server ]; then
    continue
  fi

  if [ -d $server ]; then
    echo "Custom groups template creating for $server" 1>&2
    cd $server
    echo "POOL:$server:default_pool:"
    for lpar_full in `find . -mtime -500 -name "*.rr[h|m]"` # takes only lpars/pools which have been updated in last 5 days
    do
      lpar=`basename $TWOHYPHENS "$lpar_full" .rrm`
      if [ "$lpar" = "pool" -o "$lpar" = "SharedPool0" ]; then
        continue # defaut pool is already echoed before
      fi
      if [ $lpar = "mem" ]; then
        continue # not for memory
      fi
      echo "$lpar"|egrep SharedPool >/dev/null 2>&1
      if [ $? -eq 0 ]; then
        # it is a pool, now map it to name
        pool_inx=`echo "$lpar"|sed 's/SharedPool//`
        pool=`egrep "^$pool_inx," */cpu-pools-mapping.txt|head -1|sed -e 's/.*cpu-pools-mapping\.txt://' -e 's/^[0-9],//' -e 's/^[0-9][0-9],//'`
        echo "#1POOL:$server:$pool:"
      else
        lpar_name=`echo "$lpar"|sed 's/:/\\:/g'` # ":" in lpar names to "\:"
        echo "#2LPAR:$server:$lpar_name:"
      fi
    done|sort|sed 's/^#[1,2]//g'|uniq
    cd ../
  fi
done >> $OUT


#!/bin/ksh
#
# TODO
# - prefix ";" in lpar pool names by "\:"

if [ ! -d "etc" ]; then
  if [ -d "../etc" ]; then
    cd ..
  else
    echo "problem with actual directory, assure you are in LPAR2RRD home"
    exit
  fi
fi

LHOME=`pwd|sed -e 's/scripts//' -e 's/\/\//\//' -e 's/\/$//'` # it must be here
pwd=`pwd`
cd data
cfg="$pwd/etc/favourites.cfg"

if [ -f "$cfg" ]; then
  echo "Favourites configuration update is running:"
  echo "  $cfg"
  echo ""

else
  echo "Favourites initial configuration is running:"
  echo "  $cfg"
  echo ""

cat << END > $cfg
# 
# LPAR2RRD favourites configuration file
#
# It is a configuration file for creating favourites section for quick
# access to most important graphs of lpars or CPU pools.
#
# Usage
# below you see simple lpar and CPU pool list. If you want to add any lpar or pool
# into your favourites then place name after the last double quote.
# It will be then visible under that name.
# LPAR2RRD applies changes during the next run.
# You will see your chosen graph with your name under favourites section.
#
#
# If you need to use a colon in lpar/pool/favourites name then prefix it by backslash
# Rows without favourite name are ignored
#
#
# This file has been created by cmd: 
#	./scripts/update_cfg_favourites.sh
# To update it about new servers/pools/lpars simply run this script
# It keeps actual setup and appends here newly found servers/pools/lpars

# [POOL|LPAR]:server:[lpar_name|pool_name]:your_favourite_name
#=============================================================

END

fi


for server_space in `ls|egrep -v -- "--HMC--"|sort|sed 's/ /+===============+/g'`
do

  server=`echo $server_space|sed 's/+===============+/ /g'`
  if [ -L "$server" ]; then
    continue
  fi

  if [ -d "$server" ]; then
    if [ `ls -l $server/*/vmware.txt 2>/dev/null| wc -l` -gt 0 -o `echo $server|grep vmware_VMs|wc -l` -gt 0 ]; then
      continue # VMware is not supported yert
    fi
    if [ ! "$1" = "update" ]; then
      echo "Checking $server" 1>&2
    fi
    cd "$server"
    egrep "POOL:$server:all_pools:" $cfg >/dev/null
    if [ ! $? -eq 0 ]; then
      echo "POOL:$server:all_pools:"
    fi

    # 4.10 - no more aggregated graphs
    #egrep "LPAR:$server:lpars_aggregated:" $cfg >/dev/null
    #if [ ! $? -eq 0 ]; then
    #  echo "LPAR:$server:lpars_aggregated:"
    #fi

    for lpar_full_space in `find . -mtime -5 -name "*.rr[h|m]"|sed 's/ /+===============+/g'` # takes only lpars/pools which have been updated in last 5 days
    do
      lpar_full=`echo $lpar_full_space|sed 's/+===============+/ /g'`
      lparm=`basename "$lpar_full" .rrm`
      lpar_slash=`basename "$lparm" .rrh`
      lpar=`echo $lpar_slash| sed 's/&&1/\//g'`
      if [ "$lpar"x = "x" -o "$lpar" = ".rrm" -o "$lpar" = ".rrh" ]; then
        continue # NULL lpar name
      fi
      if [ "$lpar" = "pool" -o "$lpar" = "mem-pool" -o "$lpar" = "mem" ]; then
        continue # pool is already echoed before
      fi
      echo "$lpar"|egrep SharedPool >/dev/null 2>&1
      if [ $? -eq 0 ]; then
        # it is a pool, now map it to name
        pool_inx=`echo "$lpar"|sed 's/SharedPool//'`
        pool=`egrep "^$pool_inx," */cpu-pools-mapping.txt|head -1|sed -e 's/.*cpu-pools-mapping\.txt://' -e 's/^[0-9],//' -e 's/^[0-9][0-9],//'`
        egrep "POOL:$server:$pool:" $cfg >/dev/null
        if [ ! $? -eq 0 ]; then
          echo "#1POOL:$server:$pool:"
        fi
      else
        lpar_name=`echo "$lpar"|sed 's/:/\\:/g'` # ":" in lpar names to "\:"
        egrep "LPAR:$server:$lpar_name:" $cfg >/dev/null
        if [ ! $? -eq 0 ]; then
          echo "#2LPAR:$server:$lpar_name:"
        fi
      fi
    done|sort|sed 's/^#[1,2]//g'|uniq
    echo ""
    cd ../
  fi
done >> $cfg

ed $cfg   << EOF >/dev/null 2>&1
g/:lpars_aggregated:/d
g/^$/d
w
q
EOF




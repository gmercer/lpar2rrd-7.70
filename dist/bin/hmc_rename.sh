#!/bin/ksh
#
# HMC rename script
# it goes through LPAR2RRD data dir, and renames old HMC data for new HMC name
# Note: It deletes all data belonging to the new HMC (it moves then to $backup_dir)
#
# from LPAR2RRD working dir (/home/lpar2rrd/lpar2rrd) run this:
# 1. Assure you have a backup of data directory
# 2. comment out crontab entries
#   - load.sh
#   - load_hmc_rest_api.sh
# 3. run this cmd for HMC rename
#  ./bin/hmc_rename.sh <old HMC> <new HMC> [-c]
#  "-c" parameter says that any rename requires confirmation per server level
# 4. allow commented our crontab jobs from point 2o
# 5. force new full load and execute it
# rm tmp/[5-9]*
# ./load.sh 
# 
# You should see new HMC names in the UI
#

UN=`uname -a`
TWOHYPHENS="--"
if [[ $UN == *"SunOS"* ]]; then TWOHYPHENS=""; fi # problem with basename param on Solaris

data_dir=data
backup_dir="backup_hmc_rename"
hmc_old=$1
hmc_new=$2
confirmed_passed=$3

if [ "$hmc_old"x = "x" -o "$hmc_old" = "-c" ]; then
  echo "Error: old HMC has not been specified"
  exit 1
fi

if [ "$hmc_new"x = "x" -o "$hmc_new" = "-c" ]; then
  echo "Error: new HMC has not been specified"
  exit 1
fi

confirmed=0
if [ ! "$confirmed_passed"x = "x" ]; then
  if [ "$confirmed_passed" = "-c" ]; then
     confirmed=1
     echo "selected confirmation mode, each move will require confirmation"
  else
     echo "non confirmation mode, all will be done automatically"
     echo "Press enter to continue"
     read xy
  fi
else
  echo "non confirmation mode, all will be done automatically"
  echo "Press enter to continue"
  read xy
fi


echo "Renaming $hmc_old to $hmc_new"
echo "Press enter to continue"
read x

if [ ! -d "$data_dir" ]; then
  echo "Error: data dir does not exist here: $data_dir"
  exit 1
fi

if [ ! -d "$backup_dir" ]; then
  mkdir "$backup_dir" 2>/dev/null
  ret=$?
  if [ ! -d "$backup_dir" ]; then
    echo "Error: backup data dir cannot be created: mkdir $backup_dir : $ret"
    exit 1
  fi
fi

count=0
for server in $data_dir/*
do
  if [ -L "$server" -o -f "$server" ]; then
    continue
  fi
  cd "$server"
  server_base=`basename $TWOHYPHENS "$server"`
  for hmc_act in *
  do
    if [ ! -d "$hmc_act" ]; then
      continue
    fi
    if [ "$hmc_act" = "$hmc_old" ]; then

      # backup hmc_new
      if [ $confirmed -eq 1 ]; then
        echo "Working for $server_base: $hmc_old to $hmc_new, continue [y|n]"
        read yesno
        if [ "$yesno"x = "x" ]; then
          echo "  skipping"
          continue
        fi
        if [ ! "$yesno" = "y" ]; then
          echo "  skipping"
          continue
        fi
      fi
      if [ -d "$hmc_new" ]; then
        echo "Backing up: $server_base/$hmc_new to $backup_dir"
        if [ ! -d "../../$backup_dir/$server_base-$hmc_new" ]; then
          mv "$hmc_new" "../../$backup_dir/$server_base-$hmc_new"
        else
          rm -f "../../$backup_dir/$server_base-$hmc_new"
          mv "$hmc_new" "../../$backup_dir/$server_base-$hmc_new"
        fi
      fi
      if [ -d "$hmc_new" ]; then
        echo "ERROR: $hmc_new move did not work for $server_base, leaving it as it is for now"
        continue
      fi

      # HMC rename
      echo "Renaming $server_base : $hmc_old to $hmc_new"
      mv $hmc_old $hmc_new
      (( count = count + 1 ))
    fi
  done
  cd - >/dev/null
done


echo "Removing LPM info, it will be recreated during next ./load.sh run"
echo "It might take a minute in big env"
echo ""
# LPM cleaning out, next ./load.sh recreates it automatically
find $data_dir -name \*.rrk -exec rm {} \;
find $data_dir -name \*.rrl -exec rm {} \;

echo "$count servers has been updated - HMC has been renamed"

###############################
#Configure the new HMC (you might let it work in parallel if that is possible for some time)
#Gunzip the script and copy it into /home/lpar2rrd/lpar2rrd/bin (755, lpar2rrd owner)
#Make sure you have valid backup, you might create a tar ball of data dir for example.
#Assure that all data files are owned by lpar2rrd user:
#under root : chown -R lpar2rrd data
#su - lpar2rrd
#cd /home/lpar2rrd/lpar2rrd
#sh ./hmc_rename.sh <old HMC> <new HMC> -c
#
#./load.sh html
#
#Refresh the GUI
#Check the data in the GUI
#
#run the script after server migration to the new HMC.
#Does not matter when you configure the new HMC in lpar2rrd. You can do it prior running the script or after that.
#
#Remove the old HMC from etc/lpar2rrd.cfg before run the script.
#

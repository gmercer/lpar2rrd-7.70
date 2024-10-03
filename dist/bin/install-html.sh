#!/bin/ksh

#set -x

PATH=$PATH:/usr/bin:/bin
export PATH
umask 0022

if [ ! -d $WEBDIR ]; then
   echo "WEBDIR does not exist, supply it as the first parametr"
   exit 1
fi
if [ ! -d $INPUTDIR ]; then
   echo "Source does not exist, supply it as the second parametr"
   exit 1
fi
if [ ! -f $PERL ]; then
   echo "perl path is invalid, correct it and re-run the tool"
   exit 1
fi

xormon=0
if [ ! "$XORMON"x = "x" ]; then
  xormon=$XORMON
fi

type_lpar="L"
type_lpar_removed="R"
type_wpar="W"

type_amenu="A" # VMWARE CLUSTER menu
type_bmenu="B" # VMWARE RESOURCEPOOL menu
type_cmenu="C" # custom group menu
type_fmenu="F" # favourites menu
type_gmenu="G" # global menu
type_hmenu="H" # HMC menu
type_zmenu="Z" # datastore menu
type_smenu="S" # server menu
type_dmenu="D" # server menu - already deleted (non active) servers
type_tmenu="T" # tail menu
type_vmenu="V" # VMWARE total menu
type_qmenu="Q" # tool version
type_hdt_menu="HDT" # hyperv disk global
type_hdi_menu="HDI" # hyperv disk item


type_version="O" # free(open)/full version (1/0)
type_ent="E" # ENTITLEMENT_LESS for DTE

type_server_power="P" # power
type_server_vmware="V" # vmware
type_server_kvm="K" # KVM
type_server_hyperv="H" # Hyper-V
type_server_hitachi="B" # Hitachi blade
type_server_xenserver="X" # XenServer
type_server_ovirt="O" # oVirt
type_server_oracle="Q" # OracleDB
type_server_sqlserver="D" # SQLServer
type_server_postgres="T" # PostgreSQL
type_server_db2="F" # DB2
type_server_oraclevm="U" # OracleVM
type_server_nutanix="N" # Nutanix
type_server_aws="A" # AWS
type_server_gcloud="G" # GCloud
type_server_azure="Z" # Azure
type_server_kubernetes="K" # Kubernetes
type_server_openshift="R" # RedHat Openshift
type_server_cloudstack="E" # Apache CloudStack
type_server_proxmox="M" # Proxmox
type_server_docker="I" # Proxmox
type_server_fusioncompute="W" # Huawei FusionCompute

CGI_DIR="lpar2rrd-cgi"

gmenu_created=0 # global Power  menu is created only once
vmenu_created=0 # global VMWare menu is created only once
smenu_created=0 # super menu is created only once -favorites and customs groups

# L - lpar
# G - global menu
# S - server menu
# T - tail menu
# H - HMC menu

premium=0
if [ -f "$INPUTDIR/bin/premium.sh" ];  then
  premium=1
fi

ALIAS_CFG="$INPUTDIR/etc/alias.cfg"
ALIAS=0
# 10 days in secs`
TEND=864000

if [ -f "$ALIAS_CFG" ]; then
  ALIAS=1
fi
IVM=0
SDMC=0
if [ "$TMPDIR_LPAR"x = "x" ]; then
  TMPDIR_LPAR="$INPUTDIR/tmp"
fi
INDEX=$INPUTDIR/html

version_run="$version-run"
MENU_OUT=""
VMWARE=0
XEN=0
OVIRT=0
ORACLEDB=0
SQLSERVER=0
POSTGRES=0
DB2=0
ORACLEVM=0
NUTANIX=0
AWS=0
GCLOUD=0
AZURE=0
KUBERNETES=0
OPENSHIFT=0
CLOUDSTACK=0
PROXMOX=0
DOCKER=0
FUSIONCOMPUTE=0
WINDOWS=0
MENU_OUT="$TMPDIR_LPAR/menu_no_virtualisation.txt-tmp"

# echo "--------------------- install-html.sh $1 param"
if [ ! "$1"x = "x" -a "$1" = "power" ]; then
  MENU_OUT="$TMPDIR_LPAR/menu_power.txt-tmp"
  MENU_OUT_FINAL="$TMPDIR_LPAR/menu_power.txt"
fi
if [ ! "$1"x = "x" -a "$1" = "vmware" ]; then
  MENU_OUT="$TMPDIR_LPAR/menu_vmware.txt-tmp"
  MENU_OUT_FINAL="$TMPDIR_LPAR/menu_vmware.txt"
  version_run="$version-vmware"
  VMWARE=1
fi
if [ ! "$1"x = "x" -a "$1" = "xenserver" ]; then
  MENU_XENSERVER_JSON_OUT="$TMPDIR_LPAR/menu_xenserver.json"
  version_run="$version-xenserver"
  XEN=1
fi
if [ ! "$1"x = "x" -a "$1" = "nutanix" ]; then
  MENU_NUTANIX_JSON_OUT="$TMPDIR_LPAR/menu_nutanix.json"
  version_run="$version-nutanix"
  NUTANIX=1
fi
if [ ! "$1"x = "x" -a "$1" = "aws" ]; then
  MENU_AWS_JSON_OUT="$TMPDIR_LPAR/menu_aws.json"
  version_run="$version-aws"
  AWS=1
fi
if [ ! "$1"x = "x" -a "$1" = "gcloud" ]; then
  MENU_GCLOUD_JSON_OUT="$TMPDIR_LPAR/menu_gcloud.json"
  version_run="$version-gcloud"
  GCLOUD=1
fi
if [ ! "$1"x = "x" -a "$1" = "azure" ]; then
  MENU_AZURE_JSON_OUT="$TMPDIR_LPAR/menu_azure.json"
  version_run="$version-azure"
  AZURE=1
fi
if [ ! "$1"x = "x" -a "$1" = "kubernetes" ]; then
  MENU_KUBERNETES_JSON_OUT="$TMPDIR_LPAR/menu_kubernetes.json"
  version_run="$version-kubernetes"
  KUBERNETES=1
fi
if [ ! "$1"x = "x" -a "$1" = "openshift" ]; then
  MENU_OPENSHIFT_JSON_OUT="$TMPDIR_LPAR/menu_openshift.json"
  version_run="$version-openshift"
  OPENSHIFT=1
fi
if [ ! "$1"x = "x" -a "$1" = "cloudstack" ]; then
  MENU_CLOUDSTACK_JSON_OUT="$TMPDIR_LPAR/menu_cloudstack.json"
  version_run="$version-cloudstack"
  CLOUDSTACK=1
fi
if [ ! "$1"x = "x" -a "$1" = "proxmox" ]; then
  MENU_PROXMOX_JSON_OUT="$TMPDIR_LPAR/menu_proxmox.json"
  version_run="$version-proxmox"
  PROXMOX=1
fi
if [ ! "$1"x = "x" -a "$1" = "docker" ]; then
  MENU_DOCKER_JSON_OUT="$TMPDIR_LPAR/menu_docker.json"
  version_run="$version-docker"
  DOCKER=1
fi
if [ ! "$1"x = "x" -a "$1" = "fusioncompute" ]; then
  MENU_FUSIONCOMPUTE_JSON_OUT="$TMPDIR_LPAR/menu_fusioncompute.json"
  version_run="$version-fusioncompute"
  FUSIONCOMPUTE=1
fi
if [ ! "$1"x = "x" -a "$1" = "ovirt" ]; then
  MENU_OVIRT_JSON_OUT="$TMPDIR_LPAR/menu_ovirt.json"
  version_run="$version-ovirt"
  OVIRT=1
fi
if [ ! "$1"x = "x" -a "$1" = "oracledb" ]; then
  MENU_ORACLEDB_JSON_OUT="$TMPDIR_LPAR/menu_oracledb.json"
  version_run="$version-oracledb"
  ORACLEDB=1
fi
if [ ! "$1"x = "x" -a "$1" = "sqlserver" ]; then
  MENU_SQLSERVER_JSON_OUT="$TMPDIR_LPAR/menu_sqlserver.json"
  version_run="$version-sqlserver"
  SQLSERVER=1
fi
if [ ! "$1"x = "x" -a "$1" = "db2" ]; then
  MENU_DB2_JSON_OUT="$TMPDIR_LPAR/menu_db2.json"
  version_run="$version-db2"
  DB2=1
fi
if [ ! "$1"x = "x" -a "$1" = "postgres" ]; then
  MENU_POSTGRES_JSON_OUT="$TMPDIR_LPAR/menu_postgres.json"
  version_run="$version-postgres"
  POSTGRES=1
fi
if [ ! "$1"x = "x" -a "$1" = "oraclevm" ]; then
  MENU_ORACLEVM_JSON_OUT="$TMPDIR_LPAR/menu_oraclevm.json"
  version_run="$version-oraclevm"
  ORACLEVM=1
fi
if [ ! "$1"x = "x" -a "$1" = "windows" ]; then
  MENU_OUT="$TMPDIR_LPAR/menu_windows_pl.txt-tmp"
  MENU_OUT_FINAL="$TMPDIR_LPAR/menu_windows_pl.txt"
  MENU_WINDOWS_OUT="$TMPDIR_LPAR/menu_windows_pl.txt"
  version_run="$version-windows"
  WINDOWS=1
fi

if [ $VMWARE -eq 1 -o $XEN -eq 1 -o $NUTANIX -eq 1 -o $AWS -eq 1 -o $GCLOUD -eq 1 -o $AZURE -eq 1 -o $KUBERNETES -eq 1 -o $OPENSHIFT -eq 1 -o $CLOUDSTACK -eq 1 -o $PROXMOX -eq 1 -o $DOCKER -eq 1 -o $FUSIONCOMPUTE -eq 1 -o $OVIRT -eq 1 -o $ORACLEDB -eq 1 -o $SQLSERVER -eq 1 -o $DB2 -eq 1 -o $POSTGRES -eq 1 -o $ORACLEVM -eq 1 -o $WINDOWS -eq 1 ]; then
  # new JSON menu: avoid dealing with menu.txt (MENU_OUT)
  :
elif [ "$MENU_OUT"x = "x" ]; then
  echo "install-html.sh must be called with param either 'power', 'vmware', 'xenserver', 'nutanix', 'aws', 'gcloud', 'azure', 'kubernetes', 'openshift', 'cloudstack', 'proxmox', 'docker', 'fusioncompute', 'ovirt' , 'oracledb', 'sqlserver', 'postgres', 'oraclevm', 'windows' or 'db2', exiting !!!"
  echo "MENU_OUT,$MENU_OUT,"
  exit
fi


rm -f $MENU_OUT

if [ ! -f "$MENU_OUT_FINAL" ]; then
  echo "going this way 244 install-html.sh"
  if [ "$1" = "vmware" -o "$1" = "power" ]; then
    # force to create tmp/menu.txt when it does not exist
    if [ $DEBUG ]; then echo "menu           : $MENU_OUT_FINAL is missing, force it to create a new one"; fi
    touch "$TMPDIR_LPAR/$version_run"
  fi
fi


if [ ! -f "$MENU_XENSERVER_JSON_OUT" ]; then
  if [ "$1" = "xenserver" ]; then
    # force to create tmp/menu_xenserver.json, if it does not exist
    if [ $DEBUG ]; then echo "menu           : menu_$1.json is missing, force it to create a new one"; fi
    touch "$TMPDIR_LPAR/$version_run"
  fi
else
  timestamp_xen=`$PERL -e '$inp=shift;$v = (stat("$inp"))[9]; print "$v\n";' $MENU_XENSERVER_JSON_OUT`
  now=`(date +"%s")`
  oneday_back=$(($now - 86400))
  if [ $oneday_back -ge $timestamp_xen ]; then touch "$TMPDIR_LPAR/$version_run"; fi
fi

if [ ! -f "$MENU_NUTANIX_JSON_OUT" ]; then
  if [ "$1" = "nutanix" ]; then
    # force to create tmp/menu_nutanix.json, if it does not exist
    if [ $DEBUG ]; then echo "menu           : menu_$1.json is missing, force it to create a new one"; fi
    touch "$TMPDIR_LPAR/$version_run"
  fi
else
  timestamp_nutanix=`$PERL -e '$inp=shift;$v = (stat("$inp"))[9]; print "$v\n";' $MENU_NUTANIX_JSON_OUT`
  now=`(date +"%s")`
  oneday_back=$(($now - 86400))
  if [ $oneday_back -ge $timestamp_nutanix ]; then touch "$TMPDIR_LPAR/$version_run"; fi
fi

if [ ! -f "$MENU_AWS_JSON_OUT" ]; then
  if [ "$1" = "aws" ]; then
    # force to create tmp/menu_aws.json, if it does not exist
    if [ $DEBUG ]; then echo "menu           : menu_$1.json is missing, force it to create a new one"; fi
    touch "$TMPDIR_LPAR/$version_run"
  fi
else
  timestamp_aws=`$PERL -e '$inp=shift;$v = (stat("$inp"))[9]; print "$v\n";' $MENU_AWS_JSON_OUT`
  now=`(date +"%s")`
  oneday_back=$(($now - 86400))
  if [ $oneday_back -ge $timestamp_aws ]; then touch "$TMPDIR_LPAR/$version_run"; fi
fi

if [ ! -f "$MENU_GCLOUD_JSON_OUT" ]; then
  if [ "$1" = "gcloud" ]; then
    # force to create tmp/menu_gcloud.json, if it does not exist
    if [ $DEBUG ]; then echo "menu           : menu_$1.json is missing, force it to create a new one"; fi
    touch "$TMPDIR_LPAR/$version_run"
  fi
else
  timestamp_gcloud=`$PERL -e '$inp=shift;$v = (stat("$inp"))[9]; print "$v\n";' $MENU_GCLOUD_JSON_OUT`
  now=`(date +"%s")`
  oneday_back=$(($now - 86400))
  if [ $oneday_back -ge $timestamp_gcloud ]; then touch "$TMPDIR_LPAR/$version_run"; fi
fi

if [ ! -f "$MENU_AZURE_JSON_OUT" ]; then
  if [ "$1" = "azure" ]; then
    # force to create tmp/menu_azure.json, if it does not exist
    if [ $DEBUG ]; then echo "menu           : menu_$1.json is missing, force it to create a new one"; fi
    touch "$TMPDIR_LPAR/$version_run"
  fi
else
  timestamp_azure=`$PERL -e '$inp=shift;$v = (stat("$inp"))[9]; print "$v\n";' $MENU_AZURE_JSON_OUT`
  now=`(date +"%s")`
  oneday_back=$(($now - 86400))
  if [ $oneday_back -ge $timestamp_azure ]; then touch "$TMPDIR_LPAR/$version_run"; fi
fi

if [ ! -f "$MENU_KUBERNETES_JSON_OUT" ]; then
  if [ "$1" = "kubernetes" ]; then
    # force to create tmp/menu_kubernetes.json, if it does not exist
    if [ $DEBUG ]; then echo "menu           : menu_$1.json is missing, force it to create a new one"; fi
    touch "$TMPDIR_LPAR/$version_run"
  fi
else
  timestamp_kubernetes=`$PERL -e '$inp=shift;$v = (stat("$inp"))[9]; print "$v\n";' $MENU_KUBERNETES_JSON_OUT`
  now=`(date +"%s")`
  oneday_back=$(($now - 86400))
  if [ $oneday_back -ge $timestamp_kubernetes ]; then touch "$TMPDIR_LPAR/$version_run"; fi
fi

if [ ! -f "$MENU_OPENSHIFT_JSON_OUT" ]; then
  if [ "$1" = "openshift" ]; then
    # force to create tmp/menu_openshift.json, if it does not exist
    if [ $DEBUG ]; then echo "menu           : menu_$1.json is missing, force it to create a new one"; fi
    touch "$TMPDIR_LPAR/$version_run"
  fi
else
  timestamp_openshift=`$PERL -e '$inp=shift;$v = (stat("$inp"))[9]; print "$v\n";' $MENU_OPENSHIFT_JSON_OUT`
  now=`(date +"%s")`
  oneday_back=$(($now - 86400))
  if [ $oneday_back -ge $timestamp_openshift ]; then touch "$TMPDIR_LPAR/$version_run"; fi
fi

if [ ! -f "$MENU_CLOUDSTACK_JSON_OUT" ]; then
  if [ "$1" = "cloudstack" ]; then
    # force to create tmp/menu_cloudstack.json, if it does not exist
    if [ $DEBUG ]; then echo "menu           : menu_$1.json is missing, force it to create a new one"; fi
    touch "$TMPDIR_LPAR/$version_run"
  fi
else
  timestamp_cloudstack=`$PERL -e '$inp=shift;$v = (stat("$inp"))[9]; print "$v\n";' $MENU_CLOUDSTACK_JSON_OUT`
  now=`(date +"%s")`
  oneday_back=$(($now - 86400))
  if [ $oneday_back -ge $timestamp_cloudstack ]; then touch "$TMPDIR_LPAR/$version_run"; fi
fi

if [ ! -f "$MENU_PROXMOX_JSON_OUT" ]; then
  if [ "$1" = "proxmox" ]; then
    # force to create tmp/menu_proxmox.json, if it does not exist
    if [ $DEBUG ]; then echo "menu           : menu_$1.json is missing, force it to create a new one"; fi
    touch "$TMPDIR_LPAR/$version_run"
  fi
else
  timestamp_proxmox=`$PERL -e '$inp=shift;$v = (stat("$inp"))[9]; print "$v\n";' $MENU_PROXMOX_JSON_OUT`
  now=`(date +"%s")`
  oneday_back=$(($now - 86400))
  if [ $oneday_back -ge $timestamp_proxmox ]; then touch "$TMPDIR_LPAR/$version_run"; fi
fi

if [ ! -f "$MENU_DOCKER_JSON_OUT" ]; then
  if [ "$1" = "docker" ]; then
    # force to create tmp/menu_docker.json, if it does not exist
    if [ $DEBUG ]; then echo "menu           : menu_$1.json is missing, force it to create a new one"; fi
    touch "$TMPDIR_LPAR/$version_run"
  fi
else
  timestamp_docker=`$PERL -e '$inp=shift;$v = (stat("$inp"))[9]; print "$v\n";' $MENU_DOCKER_JSON_OUT`
  now=`(date +"%s")`
  oneday_back=$(($now - 86400))
  if [ $oneday_back -ge $timestamp_docker ]; then touch "$TMPDIR_LPAR/$version_run"; fi
fi

if [ ! -f "$MENU_FUSIONCOMPUTE_JSON_OUT" ]; then
  if [ "$1" = "fusioncompute" ]; then
    # force to create tmp/menu_fusioncompute.json, if it does not exist
    if [ $DEBUG ]; then echo "menu           : menu_$1.json is missing, force it to create a new one"; fi
    touch "$TMPDIR_LPAR/$version_run"
  fi
else
  timestamp_fusioncompute=`$PERL -e '$inp=shift;$v = (stat("$inp"))[9]; print "$v\n";' $MENU_FUSIONCOMPUTE_JSON_OUT`
  now=`(date +"%s")`
  oneday_back=$(($now - 86400))
  if [ $oneday_back -ge $timestamp_fusioncompute ]; then touch "$TMPDIR_LPAR/$version_run"; fi
fi

if [ ! -f "$MENU_OVIRT_JSON_OUT" ]; then
  if [ "$1" = "ovirt" ]; then
    # force to create tmp/menu_ovirt.json, if it does not exist
    if [ $DEBUG ]; then echo "menu           : menu_$1.json is missing, force it to create a new one"; fi
    touch "$TMPDIR_LPAR/$version_run"
  fi
else
  timestamp_ovirt=`$PERL -e '$inp=shift;$v = (stat("$inp"))[9]; print "$v\n";' $MENU_OVIRT_JSON_OUT`
  now=`(date +"%s")`
  oneday_back=$(($now - 86400))
  if [ $oneday_back -ge $timestamp_ovirt ]; then touch "$TMPDIR_LPAR/$version_run"; fi
fi

if [ ! -f "$MENU_ORACLEDB_JSON_OUT" ]; then
  if [ "$1" = "oracledb" ]; then
    # force to create tmp/menu_oraceldb.json, if it does not exist
    if [ $DEBUG ]; then echo "menu           : menu_$1.json is missing, force it to create a new one"; fi
    touch "$TMPDIR_LPAR/$version_run"
  fi
else
  timestamp_ordb=`$PERL -e '$inp=shift;$v = (stat("$inp"))[9]; print "$v\n";' $MENU_ORACLEDB_JSON_OUT`
  now=`(date +"%s")`
  oneday_back=$(($now - 86400))
  if [ $oneday_back -ge $timestamp_ordb ]; then touch "$TMPDIR_LPAR/$version_run"; fi
fi

if [ ! -f "$MENU_DB2_JSON_OUT" ]; then
  if [ "$1" = "db2" ]; then
    # force to create tmp/menu_db2.json, if it does not exist
    if [ $DEBUG ]; then echo "menu           : menu_$1.json is missing, force it to create a new one"; fi
    touch "$TMPDIR_LPAR/$version_run"
  fi
else
  timestamp_db2=`$PERL -e '$inp=shift;$v = (stat("$inp"))[9]; print "$v\n";' $MENU_DB2_JSON_OUT`
  now=`(date +"%s")`
  oneday_back=$(($now - 86400))
  if [ $oneday_back -ge $timestamp_db2 ]; then touch "$TMPDIR_LPAR/$version_run"; fi
fi

if [ ! -f "$MENU_POSTGRES_JSON_OUT" ]; then
  if [ "$1" = "postgres" ]; then
    # force to create tmp/menu_postgres.json, if it does not exist
    if [ $DEBUG ]; then echo "menu           : menu_$1.json is missing, force it to create a new one"; fi
    touch "$TMPDIR_LPAR/$version_run"
  fi
else
  timestamp_pstgrs=`$PERL -e '$inp=shift;$v = (stat("$inp"))[9]; print "$v\n";' $MENU_POSTGRES_JSON_OUT`
  now=`(date +"%s")`
  oneday_back=$(($now - 86400))
  if [ $oneday_back -ge $timestamp_pstgrs ]; then touch "$TMPDIR_LPAR/$version_run"; fi
fi

if [ ! -f "$MENU_SQLSERVER_JSON_OUT" ]; then
  if [ "$1" = "sqlserver" ]; then
    # force to create tmp/menu_sqlserver.json, if it does not exist
    if [ $DEBUG ]; then echo "menu           : menu_$1.json is missing, force it to create a new one"; fi
    touch "$TMPDIR_LPAR/$version_run"
  fi
else
  timestamp_sqls=`$PERL -e '$inp=shift;$v = (stat("$inp"))[9]; print "$v\n";' $MENU_SQLSERVER_JSON_OUT`
  now=`(date +"%s")`
  oneday_back=$(($now - 86400))
  if [ $oneday_back -ge $timestamp_sqls ]; then touch "$TMPDIR_LPAR/$version_run"; fi
fi

if [ ! -f "$MENU_ORACLEVM_JSON_OUT" ]; then
  if [ "$1" = "oraclevm" ]; then
    # force to create tmp/menu_oraclevm.json, if it does not exist
    if [ $DEBUG ]; then echo "menu           : menu_$1.json is missing, force it to create a new one"; fi
    touch "$TMPDIR_LPAR/$version_run"
  fi
else
  timestamp_orvm=`$PERL -e '$inp=shift;$v = (stat("$inp"))[9]; print "$v\n";' $MENU_ORACLEVM_JSON_OUT`
  now=`(date +"%s")`
  oneday_back=$(($now - 86400))
  if [ $oneday_back -ge $timestamp_orvm ]; then touch "$TMPDIR_LPAR/$version_run"; fi
fi

if [ ! -f "$MENU_WINDOWS_OUT" ]; then
  if [ "$1" = "windows" ]; then
    # force to create tmp/menu_windows.txt, if it does not exist
    if [ $DEBUG ]; then echo "menu           : menu_$1.txt is missing, force it to create a new one"; fi
    touch "$TMPDIR_LPAR/$version_run"
  fi
else
  timestamp_win=`$PERL -e '$inp=shift;$v = (stat("$inp"))[9]; print "$v\n";' $MENU_WINDOWS_OUT`
  now=`(date +"%s")`
  oneday_back=$(($now - 86400))
  if [ $oneday_back -ge $timestamp_win ]; then touch "$TMPDIR_LPAR/$version_run"; fi
fi


pwd=`pwd`
CONFIG_DIR=$INPUTDIR/data	# must be absolute path
TIME=`$PERL -e '$v = time(); print "$v\n"'`
dashb="class=\"relpos\"><div><div class=\"favs favoff\"></div>"

if [ "$KEEP_VIRTUAL"x = "x" ]; then # accounting for DHL
  KEEP_VIRTUAL=0
fi
if [ "$ENTITLEMENT_LESS"x = "x" ]; then # DTE Energy
  ENTITLEMENT_LESS=0
fi

if [ ! -d "$WEBDIR/favourites" ]; then
  mkdir "$WEBDIR/favourites"
fi
. $INPUTDIR/bin/fav.sh  # read favorites code


if [ ! -d "$WEBDIR/custom" ]; then
  mkdir "$WEBDIR/custom"
fi


if [ $DEBUG ]; then echo "installing WWW : install-html.sh $1"; fi
if [ $DEBUG ]; then echo "Host identif   : $UNAME "; fi
DATE=`date`
if [ $DEBUG ]; then echo "timestamp      : $DATE "; fi

#LPM=1     # "./load.sh html" sets LPM=0
if [ $premium -eq 1 -a $LPM -eq 1 -a "$1" = "power" ]; then
  if [ -f $TMPDIR_LPAR/$version-LPM -o $UPGRADE -eq 1 ]; then
    . $INPUTDIR/bin/premium.sh
    # prepare LPM, graph will be created one run after
    # find and symlink lpar under LPM
    if [ $DEBUG ]; then echo "LPM search     : rrm"; fi
    RR="rrm"
    RR_NEW="rrl"

    #lpm_support --> shell LPM based search is no longer used, perl one is being used now

    if [ -f "$INPUTDIR/bin/premium_lpm_find.pl" ]; then
      listing=`$PERL "$INPUTDIR/bin/premium_lpm_find.pl"`
      if [ $? -eq 0 ]; then
        echo "$listing";
        echo "LPM            : premium_lpm_find.pl: OK"
      else
        echo "LPM            : premium_lpm_find.pl failed with value $?"
      fi
    else
      echo "timestamp      : no LPM support "
    fi
    # find and symlink lpar under LPM for old hourly DBs
    # excluded from 4.81-006
    #if [ $DEBUG ]; then echo "LPM search     : rrh"; fi
    #RR="rrh"
    #RR_NEW="rri"
    #lpm_support

    RR=""
    DATE=`date`
    if [ $DEBUG ]; then echo "timestamp LPM  : $DATE "; fi
    rm -f $TMPDIR_LPAR/$version-LPM
  fi
fi

# copy of index pages and others
cp $INPUTDIR/html/not-implemented-yet.html $INPUTDIR/html/nmonfile.html $INPUTDIR/html/noscript.html $INPUTDIR/html/wipecookies.html $INPUTDIR/html/index.html $INPUTDIR/html/dashboard.html $INPUTDIR/html/cpu_workload_estimator.html $WEBDIR/

#
### subroutines
#

find_out_alias ()
{
      #find out alias in etc/alias.cfg
      x_slash=$1
      item_type=$2 # LPAR or VM

      lpar_menu=$x_slash
      if [ $ALIAS -eq 1 ]; then
        i_slash_colon=`echo "$x_slash"|sed 's/:/\\\\\\\\:/g'` # support colon in lpar name (use back slash for prefixing colons in etc/alias.cfg)
        for alias_row in `egrep "^$item_type:$i_slash_colon:" $ALIAS_CFG |sed 's/ /=====space=====/g'|head -1 2>/dev/null`
        do
          # use 3th - 100th column to allow users use colons in the alias name
          l_alias_tmp=`echo "$alias_row"|sed -e 's/\\\\:/=====colon=====/g' |cut -d":" -f "3-100"|sed -e 's/. $//' -e 's/=====space=====/ /g' -e 's/=====colon=====/:/g'`
          lpar_menu=`echo "$x_slash [$l_alias_tmp]"`
        done
      fi
      echo "$lpar_menu"
}

# WPAR search
wpar_search ()
{
  w_lpar_dir=$1
  w_lpar=$2
  w_lpar_url=$3
  w_hmc=$4
  w_server=$5
  w_hmc_url=$6
  w_server_url=$7
  for w_lpar_item in "$w_lpar_dir"/*
  do
    if [ ! -d "$w_lpar_item" ]; then
      continue
    fi
    if [ `ls -l -- "$w_lpar_item"/*.mmm 2>/dev/null|wc -l` -eq 0 ]; then
      continue
    fi
    wpar=`basename $TWOHYPHENS "$w_lpar_item"`
    if [ $DEBUG -eq 1 ]; then echo "WPAR found     : $wpar : $w_lpar_item"; fi
    wpar_url=`$PERL -e '$s=shift;$s=~s/([^a-zA-Z0-9_.!:~*()'\''-])/sprintf("%%%02X", ord($1))/ge;print "$s\n";' "$wpar"`

    #find out alias in etc/alias.cfg
    if [ $ALIAS -eq 1 ]; then
      wpar_colon=`echo "$wpar"|sed 's/:/\\\\\\\\:/g'` # support colon in lpar name (use back slash for prefixing colons in etc/alias.cfg)
      for alias_row in `egrep "^WPAR:$wpar_colon:" $ALIAS_CFG |sed 's/ /=====space=====/g'|head -1 2>/dev/null`
      do
        # use 3th - 100th column to allow users use colons in the alias name
        w_alias=`echo $alias_row|sed -e 's/\\\\:/=====colon=====/g' |cut -d":" -f "3-100"|sed -e 's/. $//' -e 's/=====space=====/ /g' -e 's/=====colon=====/:/g'`
        wpar=`echo "$wpar [$w_alias]"`
      done
    fi

    menu "$type_wpar" "$w_hmc" "$w_server" "$wpar_url" "$wpar" "/$CGI_DIR/detail.sh?host=$w_hmc_url&server=$w_server_url&lpar=$lpar_url--WPAR--$wpar_url&item=lpar&entitle=$ENTITLEMENT_LESS&gui=1&none=none" "$w_lpar"
  done
}


# create skeleton of menu
menu () {
  a_type=$1
  a_hmc=`echo "$2"|sed -e 's/:/===double-col===/g' -e 's/\\\\_/ /g'`
  a_server=`echo "$3"|sed -e 's/:/===double-col===/g' -e 's/\\\\_/ /g'`
  a_lpar=`echo "$4"|sed 's/:/===double-col===/g'`
  a_text=`echo "$5"|sed 's/:/===double-col===/g'`
  a_url=`echo "$6"|sed -e 's/:/===double-col===/g' -e 's/ /%20/g'`
  a_lpar_wpar=`echo "$7"|sed 's/:/===double-col===/g'` # lpar name when wpar is passing
  a_last_time=$8

  if [ ! "$LPARS_EXCLUDE"x = "x" ]; then
    if [ `echo "$4"|egrep "$LPARS_EXCLUDE"|wc -l` -eq 1 ]; then
      # keep 2 independent "if" otherwise Solaris has some problem with that
      # excluding some LPARs based on a string : LPARS_EXCLUDE --> etc/.magic
      echo "lpar exclude   : $2:$2:$4 - exclude string: $LPARS_EXCLUDE"
      return 1
    fi
  fi

  if [ "$type_server" = "$type_server_power" -a "$a_type" = "$type_gmenu" -a $gmenu_created -eq 1 ]; then
    return # print global menu once
  fi
  #if [ "$type_server" = "$type_server_kvm" -a "$a_type" = "$type_gmenu" -a $kmenu_created -eq 1 ]; then
  #  return # print global menu once
  #fi
  if [ "$type_server" = "$type_server_vmware" -a  "$a_type" = "$type_gmenu" -a $vmenu_created -eq 1 ]; then
    return # print global menu once
  fi

  echo "$a_type:$a_hmc:$a_server:$a_lpar:$a_text:$a_url:$a_lpar_wpar:$a_last_time:$type_server" >> $MENU_OUT
}

# check if the HMC is alive (at least one server under the HMC has been updated in past 10 days)
check_hmc_alive ()
{

  hmc_once=0
  for pool_file_space in `ls $INPUTDIR/data/*/"$1"/pool.rrm 2>/dev/null|sed 's/ /\%20/g'`
  do
    (( hmc_once = hmc_once + 1 ))
    pool_file=`echo "$pool_file_space"|sed 's/\%20/ /g'`
    access_t=`$PERL -e '$inp=shift;$v = (stat("$inp"))[9]; print "$v\n";' "$pool_file"`
    tot=`expr $TEND + $access_t`
    if [ $tot -gt $TIME ]; then
      return 1
    fi
  done

  # and the same for pool.rrh
  for pool_file_space in `ls $INPUTDIR/data/*/"$1"/pool.rrh 2>/dev/null|sed 's/ /\%20/g'`
  do
    (( hmc_once = hmc_once + 1 ))
    pool_file=`echo "$pool_file_space"|sed 's/\%20/ /g'`
    access_t=`$PERL -e '$inp=shift;$v = (stat("$inp"))[9]; print "$v\n";' "$pool_file"`
    tot=`expr $TEND + $access_t`
    if [ $tot -gt $TIME ]; then
      return 1
    fi
  done

  # nothing alive has been found, death HMc
  return 0

  #if [ $hmc_once -eq 0 ]; then
  #  # something went wrong, it did not list the HMC, then consider it rather as alive
  #  if [ $DEBUG -eq 1 ]; then echo "HMC test       : $1 HMC has not been listed : $hmc_once"; fi
  #  return 1
  #else
  #  return 0
  #fi
}


# menu GLOBAL-->HMC
menu_hmc  ()
{
 HMCLIST=`for h1 in $WEBDIR/*; do if [ -d "$h1" ]; then echo $h1|sed 's/ /%20/g'; fi done|sort -f|egrep -v "\.png|\.html|upload|jquery|css|\/no_hmc$|\/favourites$|\/custom$"|xargs -n 1024`

 for hmc1 in $HMCLIST
 do
   hmc1=`echo $hmc1|sed 's/%20/ /g'`
   # directory test is already above
   #if [ ! -d "$hmc1" ]; then
   #  continue
   #fi

   hmc1base=`basename $TWOHYPHENS "$hmc1"`
   ivm_file=`ls $INPUTDIR/data/*/"$hmc1base"/IVM 2>/dev/null `
   if [ ! "$ivm_file"x = "x" ]; then
     # Looks like IVM, exclude it here
     continue
   fi

   # since 4.8
   # sometimes there is empty data/*/hmc1base dir e.g. user removed, or when debugging or beta testing
   empty_dir=`find "$INPUTDIR"/data/*/"$hmc1base"/ -type f 2>/dev/null|wc -l|sed 's/ //g'`
   if [ $empty_dir -eq 0 ]; then
     # Looks like empty, exclude it here
     continue
   fi

   has_one_server=0
   for srv in $hmc1/*
   do
     if [ -f "$srv/config.html" -o -f "$srv/vmware.txt" ]; then
       has_one_server=1
       break
     fi
   done

   # find out server type
   type_server=$type_server_power
   vmware_find=`ls $INPUTDIR/data/*/"$hmc1base"/vmware.txt 2>/dev/null|wc -l `
   if [ $vmware_find -gt 0  ]; then
      type_server=$type_server_vmware
   fi
   kvm_find=`ls $INPUTDIR/data/*/"$hmc1base"/kvm.txt 2>/dev/null |wc -l`
   if [  $kvm_find -gt 0 ]; then
       type_server=$type_server_kvm
   fi

   if [ $has_one_server -eq 1 ]; then #  -a ! "$type_server" = "$type_server_vmware" -a ! "$type_server" = "$type_server_kvm" ]; then
   # print only HMC with at least one attached server, it is security test to avoid trash inside
     check_hmc_alive $hmc1base
     if [ $? -eq 1 ]; then
       menu "$type_hmenu" "$hmc1base" "$hmc1base" "/$CGI_DIR/detail.sh?host=$hmc1base&server=nope&lpar=nope&item=hmctotals&entitle=$ENTITLEMENT_LESS&gui=1&none=none"
       echo "add to menu $type_hmenu  : $hmc1base"
     else
       if [ $DEBUG -eq 1 ]; then echo "HMC dead       : $hmc1base does not any active server attached, excluding it"; fi
     fi
   fi

 done
}



print_log () {

cat << END
<div  id="tabs"> <ul>
  <li><a href="/$CGI_DIR/log-cgi.sh?name=errcgi&gui=$new_gui">CGI-BIN</a></li>
  <li><a href="/$CGI_DIR/log-cgi.sh?name=loadout&gui=$new_gui">Run time</a></li>
  <li><a href="/$CGI_DIR/log-cgi.sh?name=errlog&gui=$new_gui">Error</a></li>
END
if [ -s "$INPUTDIR/logs/error.log-daemon" ]; then
  echo " <li><a href=\"/$CGI_DIR/log-cgi.sh?name=errlogdaemon&gui=$new_gui\">Daemon</a></li>"
fi
if [ -s "$INPUTDIR/logs/error.log-vmware" ]; then
  echo " <li><a href=\"/$CGI_DIR/log-cgi.sh?name=errlogvm&gui=$new_gui\">VMware</a></li>"
fi
if [ -s "$INPUTDIR/logs/counter-info.txt" ]; then
  echo " <li><a href=\"/$CGI_DIR/log-cgi.sh?name=counters&gui=$new_gui\">VMware counters</a></li>"
fi
if [ -s /var/log/httpd/error_log ]; then
  # Apache error log
  echo " <li><a href=\"/$CGI_DIR/log-cgi.sh?name=apache&gui=$new_gui\">Apache</a></li>"
fi
if [ -s "$INPUTDIR/logs/error.log-hyperv" ]; then
  echo " <li><a href=\"/$CGI_DIR/log-cgi.sh?name=errloghyperv&gui=$new_gui\">Hyper-V</a></li>"
fi
if [ -s "$INPUTDIR/logs/error.log-ovirt" ]; then
  echo " <li><a href=\"/$CGI_DIR/log-cgi.sh?name=errlogovirt&gui=$new_gui\">oVirt</a></li>"
fi
if [ -s "$INPUTDIR/logs/error.log-xen" ]; then
  echo " <li><a href=\"/$CGI_DIR/log-cgi.sh?name=errlogxen&gui=$new_gui\">XenServer</a></li>"
fi
if [ -s "$INPUTDIR/logs/error.log-nutanix" ]; then
  echo " <li><a href=\"/$CGI_DIR/log-cgi.sh?name=errlognutanix&gui=$new_gui\">Nutanix</a></li>"
fi
if [ -s "$INPUTDIR/logs/error.log-aws" ]; then
  echo " <li><a href=\"/$CGI_DIR/log-cgi.sh?name=errlogaws&gui=$new_gui\">AWS</a></li>"
fi
if [ -s "$INPUTDIR/logs/error.log-gcloud" ]; then
  echo " <li><a href=\"/$CGI_DIR/log-cgi.sh?name=errloggcloud&gui=$new_gui\">GCloud</a></li>"
fi
if [ -s "$INPUTDIR/logs/error.log-azure" ]; then
  echo " <li><a href=\"/$CGI_DIR/log-cgi.sh?name=errlogazure&gui=$new_gui\">Azure</a></li>"
fi
if [ -s "$INPUTDIR/logs/error.log-kubernetes" ]; then
  echo " <li><a href=\"/$CGI_DIR/log-cgi.sh?name=errlogkubernetes&gui=$new_gui\">Kubernetes</a></li>"
fi
if [ -s "$INPUTDIR/logs/error.log-openshift" ]; then
  echo " <li><a href=\"/$CGI_DIR/log-cgi.sh?name=errlogopenshift&gui=$new_gui\">Red Hat OpenShift</a></li>"
fi
if [ -s "$INPUTDIR/logs/error.log-cloudstack" ]; then
  echo " <li><a href=\"/$CGI_DIR/log-cgi.sh?name=errlogcloudstack&gui=$new_gui\">Apache CloudStack</a></li>"
fi
if [ -s "$INPUTDIR/logs/error.log-proxmox" ]; then
  echo " <li><a href=\"/$CGI_DIR/log-cgi.sh?name=errlogproxmox&gui=$new_gui\">Proxmox</a></li>"
fi
if [ -s "$INPUTDIR/logs/error.log-fusioncompute" ]; then
  echo " <li><a href=\"/$CGI_DIR/log-cgi.sh?name=errlogfusioncompute&gui=$new_gui\">FusionCompute</a></li>"
fi
if [ -s "$INPUTDIR/logs/error.log-oracledb" ]; then
  echo " <li><a href=\"/$CGI_DIR/log-cgi.sh?name=errlogoracledb&gui=$new_gui\">OracleDB</a></li>"
fi
if [ -s "$INPUTDIR/logs/error.log-sqlserver" ]; then
  echo " <li><a href=\"/$CGI_DIR/log-cgi.sh?name=errlogsqlserver&gui=$new_gui\">SQLServer</a></li>"
fi
if [ -s "$INPUTDIR/logs/error.log-db2" ]; then
  echo " <li><a href=\"/$CGI_DIR/log-cgi.sh?name=errlogdb2&gui=$new_gui\">db2</a></li>"
fi
if [ -s "$INPUTDIR/logs/error.log-postgres" ]; then
  echo " <li><a href=\"/$CGI_DIR/log-cgi.sh?name=errlogpostgres&gui=$new_gui\">PostgreSQL</a></li>"
fi
if [ -s "$INPUTDIR/logs/error.log-oraclevm" ]; then
  echo " <li><a href=\"/$CGI_DIR/log-cgi.sh?name=errlogoraclevm&gui=$new_gui\">OracleVM</a></li>"
fi
if [ -s "$INPUTDIR/logs/error.log-hmc_rest_api" ]; then
  echo " <li><a href=\"/$CGI_DIR/log-cgi.sh?name=errlogibmrest&gui=$new_gui\">IBM Power- REST</a></li>"
fi

echo "<li><a href='/$CGI_DIR/log-cgi.sh?name=audit&gui=$new_gui'>Audit</a></li>"

#if [ ! $ENTITLEMENT_LESS -eq 1 ]; then
#  echo "  <li><a href=\"/$CGI_DIR/log-cgi.sh?name=entitle&gui=$new_gui\">Resource Configuration Advisor</a></li>"
#fi
#echo "  <li><a href=\"/$CGI_DIR/log-cgi.sh?name=alhist&gui=$new_gui\">Alert history</a></li>"
#echo "  <li><a href=\"/$CGI_DIR/log-cgi.sh?name=counters&gui=$new_gui\">VMware counters</a></li>"

cat << END
   </ul>
</div>

END

}


print_sys_log () {
hmc_sys="$1"
server_sys="$2"
new_gui=$3

cat << END
<div  id="tabs">
<ul>
  <li class="tabhmc"><a href="$hmc_sys/$server_sys/gui-change-state.html">State change</a></li>
  <li class="tabhmc"><a href="$hmc_sys/$server_sys/gui-change-config.html">Config change</a></li>
</ul>
</div>
END
}


print_cfg () {
new_gui=$1

cat << END
<div  id="tabs"> <ul>
  <li><a href="/$CGI_DIR/log-cgi.sh?name=maincfg&gui=$new_gui">Global</a></li>
  <li><a href="/$CGI_DIR/log-cgi.sh?name=favcfg&gui=$new_gui">Favourites</a></li>
  <li><a href="/$CGI_DIR/log-cgi.sh?name=custcfg&gui=$new_gui">Custom Groups</a></li>
  <li><a href="/$CGI_DIR/log-cgi.sh?name=alrtcfg&gui=$new_gui">Alerting</a></li>
   </ul>
</div>
END
}


# build hmc based lpar and server cvs files into global one
create_cvs_global () {

first=0
cvs_global_lpar="lpar-config.csv"
if [ `ls $WEBDIR/*/*-lpar-config.csv 2>/dev/null|wc -l` -gt 0 ]; then
  for cvs_file in $WEBDIR/*/*-lpar-config.csv
  do
    act=`$PERL -e 'use Data::Dumper;$inp=shift;$m=shift;$h=shift;$cvs_file=shift; @arr=(stat("$cvs_file")); $v = time - $arr[9];print "$v";' "$INPUTDIR" "$managedname" "$hmc" "$cvs_file"`
    if [ $act -gt 864000 ]; then
      echo "ACT skip $cvs_file";
      continue
    fi
    if [ $first -eq 0 ]; then
      first=1
      cp "$cvs_file" "$WEBDIR/$cvs_global_lpar"
      continue
    fi
    egrep -v "^HMC;server;lpar_name;" "$cvs_file" >> "$WEBDIR/$cvs_global_lpar"
  done
fi


first=0
cvs_global_server="server-config.csv"
if [ `ls $WEBDIR/*/*-server-config.csv 2>/dev/null|wc -l` -gt 0 ]; then
  for cvs_file in $WEBDIR/*/*-server-config.csv
  do
    if [ $first -eq 0 ]; then
      first=1
      cp "$cvs_file" "$WEBDIR/$cvs_global_server"
      continue
    fi

    egrep -v "^HMC;server;" "$cvs_file" >> "$WEBDIR/$cvs_global_server"
  done
fi
}

print_cfg_global () {

cat << END
<BR>
<font size="-1"><A HREF="lpar-config.csv" target="_blank">CSV LPAR GLOBAL</A> / <A HREF="server-config.csv" target="_blank">CSV Server GLOBAL</A></font>
<CENTER>
<TABLE class="tabsyscfg"> <TR>
END

cd $WEBDIR

tmp_search="gui-config-high-sum.html-tmp"


# header at first
for lcfg in `ls */$tmp_search 2>/dev/null|sort`
do
  hmccfg=`echo $lcfg|cut -d"/" -f1`
  servercfg=`echo $lcfg|cut -d"/" -f2`
  lcfg_path=`echo $lcfg|sed s/-tmp$//`
  echo "<td><center><h3><a href="$lcfg_path">$hmccfg</a></h3></center></td>"
done
echo "</tr><tr>"

# body
for lcfg in `ls */$tmp_search 2>/dev/null|sort`
do
  #hmccfg=`echo $lcfg|cut -d"/" -f1`
  #servercfg=`echo $lcfg|cut -d"/" -f2`
  echo "<TD valign="top">"
  cat $lcfg
  echo "</td>"
done
echo "</tr></table>"
echo "</center><br><br><table><tr><td bgcolor=\"#80FF80\"> <font size=\"-1\"> running</font></td>"
echo "<td bgcolor=\"#FF8080\"> <font size=\"-1\"> not running</font></td>"
echo "<td bgcolor=\"#FFFF80\"> <font size=\"-1\"> CPU pool</font></td></tr></table><br>"
date=`date`
echo "<font size="-1">It is updated once a day, last run: $date"
#" to see normal cocors in vim  in following lines
}


as400_cleaning () {
  # AS400 cleaning
  # It must be here to assure that old AS400 data is regularly deleted
  # remove DISK data files inactive for more than 8 days (they are not displayed in the GUI anyway)
  if [ $DEBUG ]; then echo "AS400 cleaning : "; fi
  for as400_space in `find $INPUTDIR/data -type d -name \*--AS400-- | sed 's/ /===space===/g'`
  do
    as400=`echo "$as400_space"| sed 's/===space===/ /g'`
    if [ -d "$as400/DSK" ]; then
      #if [ $DEBUG ]; then echo "AS400 cleaning : $as400"; fi
      # must be +8 here!
      find "$as400/DSK" -type f -mtime +8 -exec rm -f {} \;
    fi
  done
}

job_cleaning () {
  # clean all files in /JOB dirs older 8 or 30 days
  if [ $DEBUG ]; then echo "clean all /JOB : ,$CUSTOMER,"; fi
  for job_space in `find $INPUTDIR/data -type d -name JOB | sed 's/ /===space===/g'`
  do
    job=`echo "$job_space"| sed 's/===space===/ /g'`
    if [ -d "$job" ]; then
      # if [ $DEBUG ]; then echo "all JOB cleaning : $job"; fi
      # must be +8 here!
      if [ "$CUSTOMER" = "PPF" ]; then
        # echo "clean for $CUSTOMER"
        find "$job/" -type f -mtime +30 -exec rm -f {} \;
      else
        find "$job/" -type f -mtime +8 -exec rm -f {} \;
      fi
    fi
  done
}

cfg_backup ()
{
  cd $INPUTDIR/etc/web_config/
  date_act=`date "+%Y-%m-%d_%H:%M"`
  if [ ! -d ../.web_config ]; then
    mkdir ../.web_config
  fi
  for cfg_file in *.cfg *.json
  do
    if [ -f $cfg_file ]; then
      if [ ! -f ../.web_config/$cfg_file ]; then
        cp -p $cfg_file ../.web_config/$cfg_file-$date_act
        cp -p $cfg_file ../.web_config/$cfg_file
      else
        if [ `diff $cfg_file ../.web_config/$cfg_file 2>/dev/null| wc -l` -gt 0 ]; then
          cp -p $cfg_file ../.web_config/$cfg_file-$date_act
          cp -p $cfg_file ../.web_config/$cfg_file
        fi
      fi
    fi
  done
  cd - >/dev/null
}

sys_cfg () {
# To get some basic system overview for troubleshooting and healthcheck activities
echo "======== id; date; tail -5 $INPUTDIR/etc/version.txt, cat $INPUTDIR/etc/.magic" > $INPUTDIR/logs/sys.log
if [ -f /var/www/html/index.html -a ! $VI_IMAGE"x" = "x" ]; then
  grep "Virtual Appliance version" /var/www/html/index.html 2>/dev/null| sed -e 's/^.*Virtual Appliance version/Virtual Appliance version/' -e 's/is brought to you by.*//' >> $INPUTDIR/logs/sys.log
fi
id >> $INPUTDIR/logs/sys.log
date >> $INPUTDIR/logs/sys.log
tail -5 $INPUTDIR/etc/version.txt >> $INPUTDIR/logs/sys.log
cat $INPUTDIR/etc/.magic >> $INPUTDIR/logs/sys.log 2>/dev/null
echo "" >> $INPUTDIR/logs/sys.log
echo "======== df $INPUTDIR/data" >> $INPUTDIR/logs/sys.log
df $INPUTDIR/data >> $INPUTDIR/logs/sys.log 2>/dev/null
echo "" >> $INPUTDIR/logs/sys.log
echo "======== uname -a" >> $INPUTDIR/logs/sys.log
uname -a >> $INPUTDIR/logs/sys.log 2>/dev/null
echo "" >> $INPUTDIR/logs/sys.log
echo "======== ls -l $INPUTDIR/bin" >> $INPUTDIR/logs/sys.log
ls -l $INPUTDIR/bin >> $INPUTDIR/logs/sys.log 2>/dev/null
echo "" >> $INPUTDIR/logs/sys.log
echo "======== ls -l $INPUTDIR/" >> $INPUTDIR/logs/sys.log
ls -l $INPUTDIR >> $INPUTDIR/logs/sys.log 2>/dev/null
echo "" >> $INPUTDIR/logs/sys.log
echo "======== ls -la $INPUTDIR/etc/web_config" >> $INPUTDIR/logs/sys.log
ls -la $INPUTDIR/etc/web_config >> $INPUTDIR/logs/sys.log 2>/dev/null
echo "" >> $INPUTDIR/logs/sys.log
echo "======== ps -ef |egrep \"apache|httpd|2rrd\" " >> $INPUTDIR/logs/sys.log
ps -ef |egrep "apache|httpd|2rrd" >> $INPUTDIR/logs/sys.log 2>/dev/null
echo "" >> $INPUTDIR/logs/sys.log
echo "======== ps -ef |egrep 2rrd| wc -l " >> $INPUTDIR/logs/sys.log
ps -ef |egrep "2rrd"| wc -l >> $INPUTDIR/logs/sys.log 2>/dev/null
echo "" >> $INPUTDIR/logs/sys.log
echo "======== crontab -l" >> $INPUTDIR/logs/sys.log
crontab -l >> $INPUTDIR/logs/sys.log 2>/dev/null
echo "" >> $INPUTDIR/logs/sys.log
echo "======== ulimit -a" >> $INPUTDIR/logs/sys.log
ulimit -a >> $INPUTDIR/logs/sys.log 2>/dev/null
echo "" >> $INPUTDIR/logs/sys.log
echo "======== vmstat 3 2" >> $INPUTDIR/logs/sys.log
vmstat 3 2 2>/dev/null >> $INPUTDIR/logs/sys.log
echo "" >> $INPUTDIR/logs/sys.log
echo "======== ls -lL $INPUTDIR/data " >> $INPUTDIR/logs/sys.log
ls -lL $INPUTDIR/data >> $INPUTDIR/logs/sys.log
if [ `uname -a|grep AIX|wc -l| sed 's/ //g' ` -gt 0 ]; then
  echo "" >> $INPUTDIR/logs/sys.log
  echo "======== AIX " >> $INPUTDIR/logs/sys.log
  echo "======== lsattr -El sys0  |grep maxuproc " >> $INPUTDIR/logs/sys.log
  lsattr -El sys0  |grep maxuproc  >> $INPUTDIR/logs/sys.log
  echo "" >> $INPUTDIR/logs/sys.log
  echo "======== svmon -G -O unit=MB" >> $INPUTDIR/logs/sys.log
  svmon -G -O unit=MB  >> $INPUTDIR/logs/sys.log
  echo "" >> $INPUTDIR/logs/sys.log
  echo "======== lparstat -i | grep Online Virtual " >> $INPUTDIR/logs/sys.log
  lparstat -i | grep "Online Virtual" >> $INPUTDIR/logs/sys.log
  echo "" >> $INPUTDIR/logs/sys.log
  ulimit -c 0 # must be there as it migh coredump on some AIXes when running from crontab
  if [ "$AIX_SKIP_RPM"x = "x" ]; then
    echo "======== https : rpm -q perl-Crypt-SSLeay perl-Net_SSLeay.pm openssl " >> $INPUTDIR/logs/sys.log
    rpm -q perl-Crypt-SSLeay perl-Net_SSLeay.pm openssl >> $INPUTDIR/logs/sys.log 2>>$INPUTDIR/logs/sys.log
  fi
  echo "" >> $INPUTDIR/logs/sys.log
  echo "LIBPATH: $LIBPATH" >> $INPUTDIR/logs/sys.log
  echo "PERL: $PERL" >> $INPUTDIR/logs/sys.log
  echo "PERL5LIB: $PERL5LIB" >> $INPUTDIR/logs/sys.log
  libpath_save=$LIBPATH
  export LIBPATH=/usr/lib:/opt/freeware/lib:$LIBPATH
  echo "" >> $INPUTDIR/logs/sys.log
  echo "======== $PERL -MLWP -e \'print \"LWP Version: \$LWP::VERSION\"\' " >> $INPUTDIR/logs/sys.log
  $PERL -MLWP -e 'print "LWP Version: $LWP::VERSION\n"'  >> $INPUTDIR/logs/sys.log
  unset LIBPATH
  export LIBPATH=$libpath_save
  echo "======== $PERL -MLWP -e \'print \"LWP Version: $LWP::VERSION\"\' " >> $INPUTDIR/logs/sys.log
  $PERL -MLWP -e 'print "LWP Version: $LWP::VERSION\n"'  >> $INPUTDIR/logs/sys.log
else
  echo "" >> $INPUTDIR/logs/sys.log
  echo "======== egrep \"^processor\" /proc/cpuinfo 2>/dev/null| wc -l" >> $INPUTDIR/logs/sys.log
  egrep "^processor" /proc/cpuinfo 2>/dev/null| wc -l >> $INPUTDIR/logs/sys.log
  echo "" >> $INPUTDIR/logs/sys.log
  echo "======== free 2>/dev/null" >> $INPUTDIR/logs/sys.log
  free 2>/dev/null >> $INPUTDIR/logs/sys.log
  echo "" >> $INPUTDIR/logs/sys.log
  echo "======== ls -l  /var/tmp/systemd-private*/tmp/*2rrd-realt-error.log 2>/dev/null" >> $INPUTDIR/logs/sys.log
  ls -l  /var/tmp/systemd-private*/tmp/*2rrd-realt-error.log 2>/dev/null >> $INPUTDIR/logs/sys.log
  echo "" >> $INPUTDIR/logs/sys.log
  echo "======== rpm -q perl-LWP-Protocol-https perl-Crypt-SSLeay perl-Mozilla-CA perl-libwww-perl openssl openssh 2>/dev/null" >> $INPUTDIR/logs/sys.log
  rpm -q perl-LWP-Protocol-https perl-Crypt-SSLeay perl-Mozilla-CA perl-libwww-perl openssl openssh 2>/dev/null >> $INPUTDIR/logs/sys.log
  echo "" >> $INPUTDIR/logs/sys.log
  echo "======== dpkg --list liblwp-protocol-https-perl libcrypt-ssleay-perl libio-socket-ssl-perl libmozilla-ldap-perl " >> $INPUTDIR/logs/sys.log
  dpkg --list liblwp-protocol-https-perl libcrypt-ssleay-perl libio-socket-ssl-perl libmozilla-ldap-perl >> $INPUTDIR/logs/sys.log 2>/dev/null
  echo "" >> $INPUTDIR/logs/sys.log
  echo "======== $PERL -MLWP -e \'print \"LWP Version: $LWP::VERSION\"\' " >> $INPUTDIR/logs/sys.log
  $PERL -MLWP -e 'print "LWP Version: $LWP::VERSION\n"'  >> $INPUTDIR/logs/sys.log
fi
echo "" >> $INPUTDIR/logs/sys.log
echo "======== ls -l $INPUTDIR/vmware-lib " >> $INPUTDIR/logs/sys.log
ls -l $INPUTDIR/vmware-lib >> $INPUTDIR/logs/sys.log
echo "" >> $INPUTDIR/logs/sys.log
echo "======== $PERL bin/perl_modules_check.pl " >> $INPUTDIR/logs/sys.log
$PERL $INPUTDIR/bin/perl_modules_check.pl >> $INPUTDIR/logs/sys.log
echo "" >> $INPUTDIR/logs/sys.log
echo "======== ls -la $INPUTDIR/etc $INPUTDIR/etc/web_config" >> $INPUTDIR/logs/sys.log
ls -la $INPUTDIR/etc $INPUTDIR/etc/web_config >> $INPUTDIR/logs/sys.log
echo "" >> $INPUTDIR/logs/sys.log
echo "======== cat $INPUTDIR/etc/lpar2rrd.cfg" >> $INPUTDIR/logs/sys.log
cat $INPUTDIR/etc/lpar2rrd.cfg >> $INPUTDIR/logs/sys.log
echo "" >> $INPUTDIR/logs/sys.log
echo "======== cat $INPUTDIR/tmp/HMC-version-*txt" >> $INPUTDIR/logs/sys.log
for hmc_name in $INPUTDIR/tmp/HMC-version-*txt
do
  hmc_version=`cat $hmc_name 2>/dev/null`
  hmc_name_base=`basename $hmc_name .txt`
  echo "$hmc_name_base: $hmc_version" | sed 's/HMC-version-//' >> $INPUTDIR/logs/sys.log
done
if [ -f $INPUTDIR/vmware-lib/apps/connect.pl ]; then
  echo "" >> $INPUTDIR/logs/sys.log
  echo "======== VMware: $PERL $INPUTDIR/vmware-lib/apps/connect.pl --version " >> $INPUTDIR/logs/sys.log
  $PERL $INPUTDIR/vmware-lib/apps/connect.pl --version >> $INPUTDIR/logs/sys.log
  echo "" >> $INPUTDIR/logs/sys.log
  echo "======== VMware: ls -l $INPUTDIR/vmware-lib/ " >> $INPUTDIR/logs/sys.log
  ls -l $INPUTDIR/vmware-lib/ >> $INPUTDIR/logs/sys.log
fi
if [ -f "$INPUTDIR/etc/web_config/hosts.json" ]; then
  egrep -v "passw|ssh-key-id|_secret_|host|[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}" "$INPUTDIR/etc/web_config/hosts.json" >> $INPUTDIR/logs/sys.log
fi
echo "" >> $INPUTDIR/logs/sys.log
echo "" >> $INPUTDIR/logs/sys.log
echo "======== ls -l /var/tmp/systemd-private*/tmp/lpar2rrd-realt-error.log /var/tmp/lpar2rrd-realt-error.log" >> $INPUTDIR/logs/sys.log
ls -l /var/tmp/systemd-private*/tmp/lpar2rrd-realt-error.log /var/tmp/lpar2rrd-realt-error.log >> $INPUTDIR/logs/sys.log 2>/dev/null
echo "" >> $INPUTDIR/logs/sys.log
echo "======== tail -50 /var/tmp/systemd-private*/tmp/lpar2rrd-realt-error.log" >> $INPUTDIR/logs/sys.log
tail -50 /var/tmp/systemd-private*/tmp/lpar2rrd-realt-error.log >> $INPUTDIR/logs/sys.log 2>/dev/null
echo "" >> $INPUTDIR/logs/sys.log
echo "======== tail -50 /var/tmp/lpar2rrd-realt-error.log" >> $INPUTDIR/logs/sys.log
tail -50 /var/tmp/lpar2rrd-realt-error.log >> $INPUTDIR/logs/sys.log 2>/dev/null
echo "END" >> $INPUTDIR/logs/sys.log
}

# checks if managed name is alive: if it does not update
#  pool.rrm for 10 days then it is considered as dead
is_alive() {

# never use same name of variable in function as it the program globally!!!!
hmcA=`echo "$1"|sed 's/\\\\_/ /g'`
managednameA=`echo "$2"|sed 's/\\\\_/ /g'`

if [ `echo "$managednameA"|egrep -- "--unknown$"|wc -l` -eq 1 -o `echo "$hmcA"|egrep "^no_hmc$"|wc -l` -eq 1 ]; then
  # lpars without the HMC, exclude old one (they might appear there if LPAR is installed before the server has allowed util collection
  # always alive so far
  if [ `find $INPUTDIR/data/"$managednameA"/"$hmcA" -type f -mtime -10 2>/dev/null|wc -l` -gt 1 ]; then
    return 0
  else
    return 1
  fi
fi

# webdir always live so far
if [ -f "$INPUTDIR/data/$managednameA/$hmcA/vmware.txt" ]; then
  return 0
fi


if [ ! -d $INPUTDIR/data/"$managednameA"/"$hmcA" ]; then
 if [ -d "$WEBDIR/$hmcA/$managednameA" ]; then
   #if [ $DEBUG -eq 1 ]; then echo "rm old system  : rm -rf $WEBDIR/$hmcA/$managednameA (no HMC found)"; fi
   rm -rf $WEBDIR/"$hmcA"/"$managednameA"
 fi
 return 1
fi


access_t=0
if [ -f "$INPUTDIR/data/$managednameA/$hmcA/pool.rrm" ]; then
  access_t=`$PERL -e '$inp=shift;$m=shift;$h=shift;$v = (stat("$inp/data/$m/$h/pool.rrm"))[9]; print "$v\n";' $INPUTDIR "$managednameA" $hmcA`
else if [ -f "$INPUTDIR/data/$managednameA/$hmcA/pool.rrh" ]; then
       access_t=`$PERL -e '$inp=shift;$m=shift;$h=shift;$v = (stat("$inp/data/$m/$h/pool.rrh"))[9]; print "$v\n";' $INPUTDIR "$managednameA" $hmcA`
     fi
fi

tot=`expr $TEND + $access_t`

if [ $tot -lt $TIME ]; then
  # it is death
  if [ -d "$WEBDIR/$hmcA/$managednameA" ]; then
    #if [ $DEBUG -eq 1 ]; then echo "rm old system  : rm -rf $WEBDIR/$hmcA/$managednameA (is not being updated for >10days)"; fi
    rm -rf $WEBDIR/"$hmcA"/"$managednameA"
  fi
  return 1
fi

return 0
}

# checks if file is alive (if it does not update for 30 days then it is considered as dead)
file_alive() {
# echo file_alive "$1" that is all
if [ -f "$1" ]; then
  # echo lives $1
  if [ `find "$1" -mtime +$active_days 2>/dev/null | wc -l ` -eq 0 ]; then
      return 0 # is alive
  else
      return 1 # is dead
  fi
else
  return 1 # is dead
fi
}

#
### subroutines part end
#

#if [ -f $TMPDIR_LPAR/$version_run ]; then
if [ `find "$TMPDIR_LPAR/menu.txt" -mtime +1 2>/dev/null | wc -l ` -gt 0 ];then
  touch "$TMPDIR_LPAR/$version_run"
fi

#
# real start of the script`
#


if [ $UPGRADE -eq 0 ]; then
  if [ ! -f $TMPDIR_LPAR/$version_run ]; then
    if [ $DEBUG -eq 1 ]; then echo "Menu           : no menu refresh for $1 $TMPDIR_LPAR/$version_run"; fi
    exit 0
  else
    if [ $DEBUG -eq 1 ]; then echo "Menu           : menu refresh for $1"; fi
  fi
else
  if [ $DEBUG -eq 1 ]; then echo "Menu           : due to an upgrade, re-newing web pages"; fi
  touch $TMPDIR_LPAR/$version
fi

if [ $UPGRADE -eq 1  -o ! -f $WEBDIR/not-implemented-yet.html -o ! -f $WEBDIR/cgcfg-help.html -o ! -f $WEBDIR/nmonfile.html -o ! -f $WEBDIR/noscript.html -o ! -f $WEBDIR/wipecookies.html -o ! -f "$WEBDIR/index.html" -o ! -f "$WEBDIR/gui-help.html" -o ! -f "$WEBDIR/dashboard.html" -o ! -f "$WEBDIR/cpu_workload_estimator.html" ]; then
  cp "$INPUTDIR/html/cpu_workload_estimator.html" "$WEBDIR/"
  cp "$INPUTDIR/html/dashboard.html" "$WEBDIR/"
  cp "$INPUTDIR/html/gui-help.html" "$WEBDIR/"
  cp "$INPUTDIR/html/index.html" "$WEBDIR/"
  cp "$INPUTDIR/html/wipecookies.html" "$WEBDIR/"
  cp "$INPUTDIR/html/noscript.html" "$WEBDIR/"
  cp "$INPUTDIR/html/nmonfile.html" "$WEBDIR/"
  cp "$INPUTDIR/html/test.html" "$WEBDIR/"
  cp "$INPUTDIR/html/favicon.ico" "$WEBDIR/"
  cp "$INPUTDIR/html/robots.txt" "$WEBDIR/"
  cp "$INPUTDIR/html/cgcfg-help.html" "$WEBDIR/"
  cp "$INPUTDIR/html/not-implemented-yet.html" "$WEBDIR/"
  cp "$INPUTDIR/html/Premium_support_LPAR2RRD.pdf" "$WEBDIR/"

  # remove new fancybox as we use the older GNU licensed now
  rm -f "$WEBDIR/jquery/jquery.fancybox.pack.js"
fi


if [ ! -d "$WEBDIR/jquery" -o $UPGRADE -eq 1 -o ! -d "$WEBDIR/css" ]; then
  if [ ! -L "$WEBDIR/jquery" ]; then
    cd $INPUTDIR/html
    tar cf - jquery | (cd $WEBDIR ; tar xf - )
    cd - >/dev/null
  fi
fi

if [ ! -d "$WEBDIR/css" -o $UPGRADE -eq 1 ]; then
  if [ ! -L "$WEBDIR/css" ]; then
    cd $INPUTDIR/html
    tar cf - css | (cd $WEBDIR ; tar xf - )
    cd - >/dev/null
  fi
fi

# No, no, it must be done manually once apache is properly configured
# copy must be done even to cgi-bin dir
#if [ ! -f "$WEBDIR/.htaccess" -a -f "$INPUTDIR/html/.htaccess" ]; then
#  copy only once
#  cp "$INPUTDIR/html/.htaccess" "$WEBDIR/.htaccess"
#fi

# it must run all the time but only once for all technologies
if [ ! "$1"x = "x" -a "$1" = "power" ]; then
  cfg_backup
  sys_cfg
  as400_cleaning
  job_cleaning

  # create pages with physical and logical configuration
  echo "config global  : creating global config"
  G_CFG="$WEBDIR/config-global.htm"
  G_CFG_GUI_BASE="gui-config-global.htm"
  G_CFG_GUI="$WEBDIR/$G_CFG_GUI_BASE"
  print_cfg_global > "$G_CFG_GUI"
  DATE=`date`
  echo "config global  : creating CSV global config $DATE"
  create_cvs_global
date
fi


if [ "$VMWARE_ACTIVE_DAYS"x = "x" ]; then
  active_days=30
else
  active_days=$VMWARE_ACTIVE_DAYS
fi
# echo "active_days $active_days"


###################################################################################################
# Main section
###################################################################################################
# echo "1313 install-html.sh Main section"

# generate linux_uuid_name.txt for all agent VMs
if [ -d "$INPUTDIR/data/Linux--unknown" ]; then
  `$PERL $INPUTDIR/bin/find_active_lpar.pl "AGENT_UUIDS" 2>>$ERRLOG`
  DATE=`date`
  if [ $? -eq 0 ]; then
    echo "AGENT_UUIDS    : OK at $DATE, find_active_lpar.pl (Linux)"
  else
    echo "AGENT_UUIDS    : AGENT_UUIDS failed with value $? find_active_lpar.pl (Linux)"
  fi
fi

# XEN part
if [ $XEN -eq 1 ]; then
  rm -f $MENU_XENSERVER_JSON_OUT

  if [ -d "$INPUTDIR/data/XEN" -o -d "$INPUTDIR/data/XEN_VMs" ]; then
    # write menu json to file, only if it is non-empty
    MENU_JSON=`$PERL -w $INPUTDIR/bin/xen-genmenu.pl 2>>$ERRLOG`

    if [ -n "$MENU_JSON" ]; then
      echo "$MENU_JSON" >> "$MENU_XENSERVER_JSON_OUT"
    fi
  fi

  rm -f $TMPDIR_LPAR/$version_run
  exit
fi

# NUTANIX part
if [ $NUTANIX -eq 1 ]; then
  rm -f $MENU_NUTANIX_JSON_OUT

  if [ -d "$INPUTDIR/data/NUTANIX" ]; then
    # write menu json to file, only if it is non-empty
    MENU_JSON=`$PERL -w $INPUTDIR/bin/nutanix-genmenu.pl 2>>$ERRLOG`

    if [ -n "$MENU_JSON" ]; then
      echo "$MENU_JSON" >> "$MENU_NUTANIX_JSON_OUT"
    fi
  fi

  rm -f $TMPDIR_LPAR/$version_run
  exit
fi

# AWS part
if [ $AWS -eq 1 ]; then
  rm -f $MENU_AWS_JSON_OUT

  if [ -d "$INPUTDIR/data/AWS" ]; then
    # write menu json to file, only if it is non-empty
    MENU_JSON=`$PERL -w $INPUTDIR/bin/aws-genmenu.pl 2>>$ERRLOG`

    if [ -n "$MENU_JSON" ]; then
      echo "$MENU_JSON" >> "$MENU_AWS_JSON_OUT"
    fi
  fi

  rm -f $TMPDIR_LPAR/$version_run
  exit
fi

# GCloud part
if [ $GCLOUD -eq 1 ]; then
  rm -f $MENU_GCLOUD_JSON_OUT

  if [ -d "$INPUTDIR/data/GCloud" ]; then
    # write menu json to file, only if it is non-empty
    MENU_JSON=`$PERL -w $INPUTDIR/bin/gcloud-genmenu.pl 2>>$ERRLOG`

    if [ -n "$MENU_JSON" ]; then
      echo "$MENU_JSON" >> "$MENU_GCLOUD_JSON_OUT"
    fi
  fi

  rm -f $TMPDIR_LPAR/$version_run
  exit
fi

# Azure part
if [ $AZURE -eq 1 ]; then
  rm -f $MENU_AZURE_JSON_OUT

  if [ -d "$INPUTDIR/data/Azure" ]; then
    # write menu json to file, only if it is non-empty
    MENU_JSON=`$PERL -w $INPUTDIR/bin/azure-genmenu.pl 2>>$ERRLOG`

    if [ -n "$MENU_JSON" ]; then
      echo "$MENU_JSON" >> "$MENU_AZURE_JSON_OUT"
    fi
  fi

  rm -f $TMPDIR_LPAR/$version_run
  exit
fi

# Kubernetes part
if [ $KUBERNETES -eq 1 ]; then
  rm -f $MENU_KUBERNETES_JSON_OUT

  if [ -d "$INPUTDIR/data/Kubernetes" ]; then
    # write menu json to file, only if it is non-empty
    MENU_JSON=`$PERL -w $INPUTDIR/bin/kubernetes-genmenu.pl 2>>$ERRLOG`

    if [ -n "$MENU_JSON" ]; then
      echo "$MENU_JSON" >> "$MENU_KUBERNETES_JSON_OUT"
    fi
  fi

  rm -f $TMPDIR_LPAR/$version_run
  exit
fi

# Openshift part
if [ $OPENSHIFT -eq 1 ]; then
  rm -f $MENU_OPENSHIFT_JSON_OUT

  if [ -d "$INPUTDIR/data/Openshift" ]; then
    # write menu json to file, only if it is non-empty
    MENU_JSON=`$PERL -w $INPUTDIR/bin/openshift-genmenu.pl 2>>$ERRLOG`

    # if [ -n "$MENU_JSON" ]; then
    #  echo "$MENU_JSON" >> "$MENU_OPENSHIFT_JSON_OUT"
    # fi
  fi

  rm -f $TMPDIR_LPAR/$version_run
  exit
fi

# Cloudstack part
if [ $CLOUDSTACK -eq 1 ]; then
  rm -f $MENU_CLOUDSTACK_JSON_OUT

  if [ -d "$INPUTDIR/data/Cloudstack" ]; then
    # write menu json to file, only if it is non-empty
    MENU_JSON=`$PERL -w $INPUTDIR/bin/cloudstack-genmenu.pl 2>>$ERRLOG`

    if [ -n "$MENU_JSON" ]; then
      echo "$MENU_JSON" >> "$MENU_CLOUDSTACK_JSON_OUT"
    fi
  fi

  rm -f $TMPDIR_LPAR/$version_run
  exit
fi

# Proxmox part
if [ $PROXMOX -eq 1 ]; then
  rm -f $MENU_PROXMOX_JSON_OUT

  if [ -d "$INPUTDIR/data/Proxmox" ]; then
    # write menu json to file, only if it is non-empty
    MENU_JSON=`$PERL -w $INPUTDIR/bin/proxmox-genmenu.pl 2>>$ERRLOG`

    if [ -n "$MENU_JSON" ]; then
      echo "$MENU_JSON" >> "$MENU_PROXMOX_JSON_OUT"
    fi
  fi

  rm -f $TMPDIR_LPAR/$version_run
  exit
fi

# Docker part
if [ $DOCKER -eq 1 ]; then
  rm -f $MENU_DOCKER_JSON_OUT

  if [ -d "$INPUTDIR/data/Docker" ]; then
    # write menu json to file, only if it is non-empty
    MENU_JSON=`$PERL -w $INPUTDIR/bin/docker-genmenu.pl 2>>$ERRLOG`

    if [ -n "$MENU_JSON" ]; then
      echo "$MENU_JSON" >> "$MENU_DOCKER_JSON_OUT"
    fi
  fi

  rm -f $TMPDIR_LPAR/$version_run
  exit
fi

# FusionCompute part
if [ $FUSIONCOMPUTE -eq 1 ]; then
  rm -f $MENU_FUSIONCOMPUTE_JSON_OUT

  if [ -d "$INPUTDIR/data/FusionCompute" ]; then
    # write menu json to file, only if it is non-empty
    MENU_JSON=`$PERL -w $INPUTDIR/bin/fusioncompute-genmenu.pl 2>>$ERRLOG`

    if [ -n "$MENU_JSON" ]; then
      echo "$MENU_JSON" >> "$MENU_FUSIONCOMPUTE_JSON_OUT"
    fi
  fi

  rm -f $TMPDIR_LPAR/$version_run
  exit
fi

# oVirt part
if [ $OVIRT -eq 1 ]; then
  rm -f $MENU_OVIRT_JSON_OUT

  if [ -d "$INPUTDIR/data/oVirt" -a -f "$INPUTDIR/data/oVirt/metadata.json" ]; then
    MENU_JSON=`$PERL -w $INPUTDIR/bin/ovirt-genmenu.pl 2>>$ERRLOG`

    if [ -n "$MENU_JSON" ]; then
      echo "$MENU_JSON" >> "$MENU_OVIRT_JSON_OUT"
    fi
  fi

  rm -f $TMPDIR_LPAR/$version_run
  exit
fi

# OracleDB part
if [ $ORACLEDB -eq 1 ]; then
  rm -f $MENU_ORACLEDB_JSON_OUT

  if [ -d "$INPUTDIR/data/OracleDB" ]; then
    MENU_JSON=`$PERL -w $INPUTDIR/bin/oracleDB-genmenu.pl 2>>$ERRLOG`
  fi

  rm -f $TMPDIR_LPAR/$version_run
  exit
fi

#IBM Db2 part
if [ $DB2 -eq 1 ]; then
  rm -f $MENU_DB2_JSON_OUT

  if [ -d "$INPUTDIR/data/DB2" ]; then
    MENU_JSON=`$PERL -w $INPUTDIR/bin/db2-genmenu.pl 2>>$ERRLOG`
  fi

  rm -f $TMPDIR_LPAR/$version_run
  exit
fi

# PostgreSQL part
if [ $POSTGRES -eq 1 ]; then
  rm -f $MENU_POSTGRES_JSON_OUT

  if [ -d "$INPUTDIR/data/PostgreSQL" ]; then
    MENU_JSON=`$PERL -w $INPUTDIR/bin/postgres-genmenu.pl 2>>$ERRLOG`
  fi

  rm -f $TMPDIR_LPAR/$version_run
  exit
fi

# SQLServer part
if [ $SQLSERVER -eq 1 ]; then
  rm -f $MENU_SQLSERVER_JSON_OUT

  if [ -d "$INPUTDIR/data/SQLServer" ]; then
    MENU_JSON=`$PERL -w $INPUTDIR/bin/sqlserver-genmenu.pl 2>>$ERRLOG`
  fi

  rm -f $TMPDIR_LPAR/$version_run
  exit
fi

# OracleVM part
if [ $ORACLEVM -eq 1 ]; then
  rm -f $MENU_ORACLEVM_JSON_OUT

  if [ -d "$INPUTDIR/data/OracleVM" ]; then
    MENU_JSON=`$PERL -w $INPUTDIR/bin/orvm-genmenu.pl 2>>$ERRLOG`

    if [ -n "$MENU_JSON" ]; then
      echo "$MENU_JSON" >> "$MENU_ORACLEVM_JSON_OUT"
    fi
  fi

  rm -f $TMPDIR_LPAR/$version_run
  exit
fi

# WINDOWS hyperv part
if [ $WINDOWS -eq 1 ]; then
  rm -f $MENU_WINDOWS_OUT >/dev/null 2>&1

  if [ -d "$INPUTDIR/data/windows" ]; then
    `$PERL -w $INPUTDIR/bin/windows-menu.pl 2>>$ERRLOG`
    # add all HYPERV VMs if exist
    # HYPERV is ok here because it does have special menu file
    `$PERL $INPUTDIR/bin/find_active_lpar.pl "HYPERV" >> "$TMPDIR_LPAR/menu_windows_pl.txt" 2>>$ERRLOG`
    if [ $? -eq 0 ]; then
      echo "Hyper-V        : find_active_lpar.pl : OK"
    else
      echo "Hyper-V        : find_active_lpar.pl failed with value $?"
    fi
    cat "$TMPDIR_LPAR/menu_windows_pl.txt" >> $MENU_OUT 2>>$ERRLOG
  fi

  rm -f $TMPDIR_LPAR/$version_run
  exit
fi

#
### separated vmware part creates only vmware lines
#
if [ $VMWARE -eq 1 ]; then
  DATE=`date`
  echo "timestamp      : $DATE install-html-vmware start ----------"
  if [ -f "$INPUTDIR/bin/install-html-vmware.pl" ]; then
    nohup $PERL "$INPUTDIR/bin/install-html-vmware.pl" 2>>$ERRLOG &
#    if [ $? -eq 0 ]; then
#      echo "VMware         : $PERL $INPUTDIR/bin/install-html-vmware.pl: OK"
#    else
#      echo "WMware         : $PERL $INPUTDIR/bin/install-html-vmware.pl failed with value $?"
#    fi
#    cat "$TMPDIR_LPAR/menu_vmware_pl.txt" >> $MENU_OUT
  else
    . $INPUTDIR/bin/install-html-vmware.sh
  fi
#  DATE=`date`
#  echo "before wait $DATE"
#  wait
#  DATE=`date`
#  echo "after wait $DATE"
#
#  echo "timestamp      : $DATE install-html-vmware finish ----------"

  # add all VMWARE VMs if exist
  # use file in tmpdir
  menu_vms_file="$TMPDIR_LPAR/menu_vms_pl.txt"
  if [ -d "$INPUTDIR/data/vmware_VMs" ]; then
    # `$PERL $INPUTDIR/bin/find_active_lpar.pl "VMWARE" >> $MENU_OUT 2>>$ERRLOG`
    `$PERL $INPUTDIR/bin/find_active_lpar.pl "VMWARE" > $menu_vms_file 2>>$ERRLOG`
    if [ $? -eq 0 ]; then
      DATE=`date`
      echo "VMware         : find_active_lpar.pl OK at $DATE"
    else
      echo "VMware         : find_active_lpar.pl failed with value $?"
      DATE=`date`
      if [ $DEBUG ]; then echo "timestamp      : $DATE  finish"; fi
    fi
  fi

  DATE=`date`
  echo "before wait    :$DATE"
  wait
  DATE=`date`
  echo "after wait     :$DATE"

  cat "$TMPDIR_LPAR/menu_vmware_pl.txt" >> $MENU_OUT 2>>$ERRLOG
  if [ -f "$menu_vms_file" ]; then
    cat "$menu_vms_file" >> $MENU_OUT 2>>$ERRLOG
  fi

  DATE=`date`
  echo "timestamp      : $DATE install-html-vmware finish ----------"

  $PERL $INPUTDIR/bin/power-menu.pl "$hmc" "$managedname" "$REST_API" "$IVM"
  cat "$INPUTDIR/tmp/menu_power_pl.txt" >> $MENU_OUT 2>>$ERRLOG


  # copy new menu over the prod ove
  if [ -f $MENU_OUT ]; then
    cp $MENU_OUT $MENU_OUT_FINAL
    # create total tmp/menu.txt which is used by heatmap, daily_check etc., start always with IBM Power menu
    if [ -f "$TMPDIR_LPAR/menu_power.txt" ]; then
      cp "$TMPDIR_LPAR/menu_power.txt" $TMPDIR_LPAR/menu.txt #do not copy the menu here, it is in load.sh now
      cat $MENU_OUT >> $TMPDIR_LPAR/menu.txt
    else
      cp $MENU_OUT $TMPDIR_LPAR/menu.txt
    fi
    if [ -f "$TMPDIR_LPAR/menu_windows_pl.txt" ]; then
      cat "$TMPDIR_LPAR/menu_windows_pl.txt" >> $TMPDIR_LPAR/menu.txt
    fi
  else
    echo "menu does not exist: file $MENU_OUT, probably no VMware configured"
    exit
  fi

  # data_check Vmotion tab
  echo "lpar_start_counter : in background"
  nohup $PERL -w $BINDIR/lpar_start_counter.pl > $TMPDIR/lpar_start_counter.txt 2>>$ERRLOG &
  #if [ $? -eq 0 ]; then
  #  echo "command lpar_start_counter.pl: OK"
  #else
  #  echo "command lpar_start_counter.pl failed with value $?"
  #fi

  rm -f $TMPDIR_LPAR/$version_run

  RET=`grep ":ERROR:" $MENU_OUT`
  if [ `echo $RET| wc -w` -gt 1 ]; then
    echo "ERROR menu.txt : $RET"
  fi
  exit
fi

#
### power part creates all necessary menu lines except vmware lines
#

if [ $premium -eq 1 ]; then # BINDIR cannot be used here as it is relative
  technology=""
  if [ -f "$INPUTDIR/html/.p" ]; then
    technology="$technology:p"
  fi
  if [ -f "$INPUTDIR/html/.v" ]; then
    technology="$technology:v"
  fi
  if [ -f "$INPUTDIR/html/.s" ]; then
    technology="$technology:s"
  fi
  if [ -f "$INPUTDIR/html/.x" ]; then
    technology="$technology:x"
  fi
  if [ -f "$INPUTDIR/html/.o" ]; then
    technology="$technology:o"
  fi
  if [ -f "$INPUTDIR/html/.h" ]; then
    technology="$technology:h"
  fi
  technology=`echo $technology| sed 's/^://g'`
  menu "$type_version" "0" "$technology" "" "" "" ""
else
  menu "$type_version" "1" "" "" "" "" ""
fi

menu "$type_ent" "$ENTITLEMENT_LESS" "" "" "" "" ""

version_act=$version
if [ -f $INPUTDIR/etc/version.txt ]; then
  # actually installed version include patch level (in $version is not patch level)
  version_act=`cat $INPUTDIR/etc/version.txt|tail -1| sed 's/ .*//'`
fi
menu "$type_qmenu" "$version_act"

# add all IBM Power LPARs (include X86 Linuxes, NMON, AS400)
DATE=`date`
echo "Power          : find_active_lpar.pl: $DATE starting"
`$PERL $INPUTDIR/bin/find_active_lpar.pl >> $MENU_OUT 2>>$ERRLOG`
DATE=`date`
if [ $? -eq 0 ]; then
  echo "Power          : find_active_lpar.pl: OK at $DATE "
else
  echo "Power          : find_active_lpar.pl failed with value $? at $DATE"
fi

# add all Hitachi if exist
# Hitachi is ok here because it does not have special menu file
if [ -d "$INPUTDIR/data/Hitachi" ]; then
  `$PERL $INPUTDIR/bin/find_active_lpar.pl "HITACHI" >> $MENU_OUT 2>>$ERRLOG`
  if [ $? -eq 0 ]; then
    echo "Hitachi        : find_active_lpar.pl OK"
  else
    echo "Hitachi        : find_active_lpar.pl failed with value $?"
  fi
fi

# add all SOLARIS if exist
if [ -d "$INPUTDIR/data/Solaris" ]; then
  `$PERL $INPUTDIR/bin/find_active_lpar.pl "SOLARIS-L" >> $MENU_OUT 2>>$ERRLOG`
  if [ $? -eq 0 ]; then
    echo "Solaris        : find_active_lpar.pl - SOLARIS with LDOM - OK"
  else
    echo "Solaris        : find_active_lpar.pl failed with value $?"
  fi
elif [ -d "$INPUTDIR/data/Solaris--unknown" ]; then
  `$PERL $INPUTDIR/bin/find_active_lpar.pl "SOLARIS-L" >> $MENU_OUT 2>>$ERRLOG`
  if [ $? -eq 0 ]; then
    echo "Solaris        : find_active_lpar.pl - SOLARIS without LDOM - OK"
  else
    echo "Solaris        : find_active_lpar.pl failed with value $?"
  fi
fi
print_cfg > $WEBDIR/gui-cfg.html
print_log > $WEBDIR/gui-log.html

# must be here to let created all www/* structure
menu_hmc # it creates Global HMC menu --> it runs only once

menu "$type_tmenu" "doc" "Documentation" "gui-help.html"
menu "$type_tmenu" "dcheck" "Data check" "/$CGI_DIR/detail.sh?host=&server=&lpar=cod&item=data_check&entitle=0&none=none"
#menu "$type_tmenu" "lcfg" "Configuration list" "gui-cfg.html"
# excluded, it is not necessary anymore -PH
menu "$type_tmenu" "logs" "Logs" "gui-log.html"
if [ ! "$VI_IMAGE"x = "x" ]; then
  if [ $VI_IMAGE -eq 1 ]; then
    menu "$type_tmenu" "update" "Product upgrade" "/$CGI_DIR/upgrade.sh?cmd=form"
  fi
fi

favourite  # favourite load

# add custom groups
if [ -f "$INPUTDIR/etc/web_config/custom_groups.cfg" -o -f "$INPUTDIR/etc/custom_groups.cfg" ]; then
  `$PERL $INPUTDIR/bin/custom-genmenu.pl >> $MENU_OUT 2>>$ERRLOG`
  if [ $? -eq 0 ]; then
    echo "Custom         : custom-genmenu.pl: OK"
  else
    echo "Custom         : custom-genmenu.pl failed with value $?"
  fi
fi

menu "$type_tmenu" "ACL" "Access Control" "/$CGI_DIR/acl.sh"

# copy new menu over the prod ove
if [ -f $MENU_OUT ]; then
  cp $MENU_OUT $MENU_OUT_FINAL
  # create total tmp/menu.txt which is used by heatmap, daily_check etc.
  cp $MENU_OUT $TMPDIR_LPAR/menu.txt
  if [ -f "$TMPDIR_LPAR/menu_vmware.txt" ]; then
    cat "$TMPDIR_LPAR/menu_vmware.txt" >> $TMPDIR_LPAR/menu.txt
  fi
  if [ -f "$TMPDIR_LPAR/menu_windows_pl.txt" ]; then
    cat "$TMPDIR_LPAR/menu_windows_pl.txt" >> $TMPDIR_LPAR/menu.txt
  fi
elif [ -f $MENU_XENSERVER_JSON_OUT -o -f $MENU_NUTANIX_JSON_OUT -o -f $MENU_AWS_JSON_OUT -o -f $MENU_GCLOUD_JSON_OUT -o -f $MENU_AZURE_JSON_OUT -o -f $MENU_KUBERNETES_JSON_OUT -o -f $MENU_OPENSHIFT_JSON_OUT -o -f $MENU_CLOUDSTACK_JSON_OUT -o -f $MENU_PROXMOX_JSON_OUT -o -f $MENU_DOCKER_JSON_OUT -o -f $MENU_FUSIONCOMPUTE_JSON_OUT -o -f $MENU_OVIRT_JSON_OUT -o -f $MENU_ORACLEDB_JSON_OUT -o -f $MENU_POSTGRES_JSON_OUT -o -f $MENU_SQLSERVER_JSON_OUT -o -f $MENU_DB2_JSON_OUT -o -f $MENU_ORACLEVM_JSON_OUT ]; then
  # new JSON menu: avoid dealing with menu.txt (MENU_OUT)
  :
else
  echo "menu does not exist: file $MENU_OUT"
fi

#  clean out NMON online grapher files
if [ -d "$INPUTDIR/data_all" ]; then
  # clean all temp files older than 2 days
  find /tmp -name ext-nmon-query-\* -mtime +2 -exec rm -f {} 2>/dev/null \;
  find "$INPUTDIR/data_all"  -mtime +2 -type l -exec rm -f {} 2>/dev/null \;
  find "$INPUTDIR/data_all"  -mtime +2 -type f -exec rm -f {} 2>/dev/null \;
  find "$INPUTDIR/data_all"  -mtime +2 -type d -exec rm -rf {} 2>/dev/null \;
fi

# Clean out <defunct> processe
if [ `ps -ef| grep lpar2rrd | grep -v grep | grep "<defunct>"| wc -l |sed 's/ //g'` -gt 0 ]; then
  echo "Defuncts       : killing defuncts"
  kill -9 `ps -ef| grep lpar2rrd | grep -v grep | grep "<defunct>" | awk '{print $2}' |xargs` 2>/dev/null
  # lpar2rrd user is hardcoded on purpose
fi

# back up GUI config files
cd $INPUTDIR/etc
if [ ! -d .web_config ]; then
  mkdir .web_config
fi
if [ ! -f .web_config/Readme.txt ]; then
  echo "here is backup of all modification in GUI configuration files done through the web" > .web_config/Readme.txt
fi

rm -f $TMPDIR_LPAR/$version_run

RET=`grep ":ERROR:" $MENU_OUT`
if [ `echo $RET| wc -w` -gt 1 ]; then
  echo "ERROR menu.txt : $RET"
fi


exit

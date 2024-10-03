#!/bin/ksh
#
# VMware API install script
#

umask 022

if [ -f etc/lpar2rrd.cfg ]; then
  . etc/lpar2rrd.cfg
else
  if [ -f `dirname $0`/etc/lpar2rrd.cfg ]; then
    . `dirname $0`/etc/lpar2rrd.cfg
  else
    if [ -f `dirname $0`/../etc/lpar2rrd.cfg ]; then
      . `dirname $0`/../etc/lpar2rrd.cfg
    fi
  fi
fi

# Load "magic" setup
if [ -f `dirname $0`/etc/.magic ]; then
  . `dirname $0`/etc/.magic
fi

if [ `echo $INPUTDIR|egrep "/bin$"|wc -l` -gt 0 ]; then
  INPUTDIR=`dirname $INPUTDIR`
fi

if [ ! -d "$INPUTDIR" ]; then
  echo "Does not exist \$INPUTDIR; have you loaded environment properly? . /home/lpar2rrd/lpar2rrd/etc/lpar2rrd.cfg"
  exit 1
fi
if [ ! -f "$INPUTDIR/etc/lpar2rrd.cfg" ]; then
  echo "LPAR2RRD product working dir has not been found : $INPUTDIR"
  echo "exiting"
  exit 0
fi

# must be here to change "." for the real path
cd $INPUTDIR
INPUTDIR=`pwd`

os_aix=`uname -a|grep AIX|wc -l|sed 's/ //g'`
MIN_FS_SPACE=300 # 300MB space is needed for the package extraction and installation

# HOME space check
if [ $os_aix -gt 0 ]; then
  if [ `df -m $INPUTDIR |grep -iv free|awk '{print $3}'| sed 's/\..*//'` -lt $MIN_FS_SPACE ]; then
    echo "Increase filesystem space in user home directory to $MIN_FS_SPACE MB at least"
    exit 0
  fi
else
  if [ `df -m $INPUTDIR |grep -iv available|xargs|awk '{print $4}'| sed 's/\..*//'` -lt $MIN_FS_SPACE ]; then
    echo "Increase filesystem space in user home directory to $MIN_FS_SPACEMB at least"
    exit 0
  fi
fi

if [ $# -lt 1 ]
then
  echo "You have to specify directory with VMware SDK install package"
  echo "Exiting..."
  exit
fi

PKGPATH=$1


# check if it is running under right user
install_user=`ls -l "$0"|awk '{print $3}'`
running_user=`id |awk -F\( '{print $2}'|awk -F\) '{print $1}'`
if [ ! "$install_user" = "$running_user" ]; then
  echo "You probably trying to run it under wrong user"
  echo "LPAR2RRD files are owned by : $install_user"
  echo "You are : $running_user"
  echo "LPAR2RRD update should run only under user which owns installed package"
  echo "Do you want to really continue? [n]:"
  read answer
  if [ "$answer"x = "x" -o "$answer" = "n" -o "$answer" = "N" ]; then
    exit
  fi
fi


# select the most recent version of package if any
if [ -d $PKGPATH ]; then
  PKGNAME=`ls -r1 $PKGPATH/VMware-vSphere-Perl-SDK-*tar.gz 2>/dev/null| head -n 1`
fi
if [ -f $PKGPATH ]; then
  PKGNAME=$PKGPATH
fi
if [ "$PKGNAME"x = "x" ]; then
  echo "Could not identify VMware-vSphere-Perl-SDK package, it probably does not exist here: $PKGPATH"
  echo "Exiting ..."
  exit 
fi


if [ ! -f $PKGNAME -o "$PKGNAME"x = "x" ]; then
  echo "There is no VMware Perl SDK install package in the specified directory: $PKGPATH " | sed 's/bin\/\.\.\///'
  echo "Exiting..."
  exit
fi

echo "$PKGNAME found" | sed 's/bin\/\.\.\///'
cd $INPUTDIR

# extract  package
echo "Extracting selected package to $INPUTDIR/vmware-vsphere-cli-distrib ..."| sed 's/bin\/\.\.\///'
gunzip < $PKGNAME | tar xf - 2> /dev/null
if [ ! -d "$INPUTDIR/vmware-vsphere-cli-distrib" ]; then
  echo "Has not been found extracted distribution in: $INPUTDIR/vmware-vsphere-cli-distrib"| sed 's/bin\/\.\.\///'
  echo "Exiting..."
  exit
fi

# remove older Perl SDK
if [ -d "$INPUTDIR/vmware-lib" ]; then
  echo "Removing original Vmware Perl SDK"
  rm -rf $INPUTDIR/vmware-lib
fi

# install selected libraries and apps
echo "Installing selected libraries and apps to $INPUTDIR/vmware-lib ..."| sed 's/bin\/\.\.\///'
cd $INPUTDIR/vmware-vsphere-cli-distrib
mkdir $INPUTDIR/vmware-lib 
if [ -d lib/VMware/share/VMware ]; then
  cp -R lib/VMware/share/VMware $INPUTDIR/vmware-lib
else
  echo "Vmware libraries count not be found in distribution : $INPUTDIR/vmware-vsphere-cli-distrib/lib/VMware/share/VMware"
  exit 1
fi
rm -rf $INPUTDIR/vmware-lib/VMware/pyexe # remove useless Linux binaries
cp -R lib/libwww-perl-*/lib/* $INPUTDIR/vmware-lib 2>/dev/null
cp -R lib/URI-*/lib/* $INPUTDIR/vmware-lib 2>/dev/null
cp -R apps/general $INPUTDIR/vmware-lib/apps

cd $INPUTDIR
echo ""

if [ $os_aix -eq 0 ]; then
    echo "Do not forget to install perl-Crypt-SSLeay package!"
else
    echo "If you have problems with Crypt-SSLeay during runtime then install following:"
    #echo "  downaload http://sourceforge.net/projects/xcat/files/aix/xcat-dep/6.1/perl-Crypt-SSLeay-0.57-2.aix6.1.ppc.rpm and install as root:"
    echo "  rpm -Uvh perl-Crypt-SSLeay-0.57-2.aix6.1.ppc.rpm"
    echo "  rpm -Uvh --nodeps --replacefiles perl-Net_SSLeay.pm-1.55-3.aix6.1.ppc.rpm"
    echo "More here: http://www.lpar2rrd.com/https.htm"
    #echo "  - or download tar.gz version of that RPM package from here http://www.lpar2rrd.com/download/perl-Crypt-SSLeay-0.57.aix6.1.ppc.tar.gz and extract needed files:"
    #echo "    gunzip perl-Crypt-SSLeay-0.57.aix6.1.ppc.tar.gz"
    #echo "    tar xvf perl-Crypt-SSLeay-0.57.aix6.1.ppc.tar"
    #echo "    cp -R perl-Crypt-SSLeay-0.57/usr/opt/perl5/lib/site_perl/5.8.8/aix-thread-multi/* $INPUTDIR/vmware-lib"
#    cp -R lib/Crypt-SSLeay-0.55-0.9.8/lib/* $INPUTDIR/vmware-lib
fi
find $INPUTDIR/vmware-lib -type d -exec chmod 755 {} \;
find $INPUTDIR/vmware-lib -type f -exec chmod 644 {} \;
find $INPUTDIR/vmware-lib/apps -type f -name "*\.pl" -exec chmod 755 {} \;

# clean up
if [ -d "$INPUTDIR/vmware-vsphere-cli-distrib" ]; then
  rm -rf $INPUTDIR/vmware-vsphere-cli-distrib
fi
if [ -d "perl-Crypt-SSLeay-0.57" ]; then
  rm -rf perl-Crypt-SSLeay-0.57
fi

if [ ! -d "$INPUTDIR/.vmware" ]; then
  mkdir "$INPUTDIR/.vmware"
  chmod 755 "$INPUTDIR/.vmware"
fi
if [ ! -d "$INPUTDIR/.vmware/credstore" ]; then
  mkdir "$INPUTDIR/.vmware/credstore"
  chmod 777 "$INPUTDIR/.vmware/credstore" # must be 777 to allow writes of Apache user
fi

# fix for perl 5.26+ in VMware API
if [ -f $INPUTDIR/vmware-lib/URI/Escape.pm ]; then
  perl -pi $INPUTDIR/bin/URI_Escape_patch.pl $INPUTDIR/vmware-lib/URI/Escape.pm
fi


#echo Libraries and apps were copied to $INPUTDIR/vmware-lib ...
#echo ""
#echo "Don't forget to include this path to PERL5LIB in etc/lpar2rrd.cfg!"
#echo "export PERL5LIB=$INPUTDIR/vmware-lib:\$PERL5LIB"

# When VMware Perl SDK 6.7+, then remove SSOConnection module which require Text/Template.pm
# SSOConnection we do not use anyway
if [ -f  "$INPUTDIR/vmware-lib/VMware/VICommon.pm" ]; then 
  ed $INPUTDIR/vmware-lib/VMware/VICommon.pm << EOF > /dev/null
g/use VMware::SSOConnection/s/use VMware::SSOConnection/#use VMware::SSOConnection/g
w
q
EOF
else
  echo "ERROR: Could not found $INPUTDIR/vmware-lib/VMware/VICommon.pm and deleted Perl Text/Template.pm dependency"
fi

# Fix for RHEL8+
# \n cannot be used in "sed" due to AIX :(
sed 's/.*PERL_LWP_SSL_VERIFY_HOSTNAME.* = 0;/\$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0;\
 eval {\
# required for new IO::Socket::SSL versions\
require IO::Socket::SSL;\nIO::Socket::SSL->import\(\);\
IO::Socket::SSL::set_ctx_defaults\( SSL_verify_mode => 0 \);\
};/'  $INPUTDIR/vmware-lib/VMware/VICommon.pm > $INPUTDIR/vmware-lib/VMware/VICommon.pm-ok
if [ -f "$INPUTDIR/vmware-lib/VMware/VICommon.pm-ok" ]; then
  mv $INPUTDIR/vmware-lib/VMware/VICommon.pm-ok $INPUTDIR/vmware-lib/VMware/VICommon.pm
else
  echo "Error: an issue with customisation of $INPUTDIR/vmware-lib/VMware/VICommon.pm"
fi

find $INPUTDIR/vmware-lib -type f -exec chmod 644 {} \;
find $INPUTDIR/vmware-lib -type d -exec chmod 755 {} \;


echo ""
echo "Testing it: "
echo ". $INPUTDIR/etc/lpar2rrd.cfg"
echo "$PERL $INPUTDIR/vmware-lib/apps/connect.pl --version"
$PERL $INPUTDIR/vmware-lib/apps/connect.pl --version

echo ""
echo ""
echo "Continue by define VMware hosts and their credentials"
echo "UI: settings icon --> VMware --> New"
exit 0

echo "Test connection:"
echo "cd $INPUTDIR"| sed 's/bin\/\.\.\///'
echo ". etc/lpar2rrd.cfg"| sed 's/bin\/\.\.\///'
echo "\$PERL $INPUTDIR/vmware-lib/apps/credstore_admin.pl add  -s <VMware ESXi or Vcenter host> -u <username> -p <password>"| sed 's/bin\/\.\.\///'
echo "\$PERL $INPUTDIR/vmware-lib/apps/credstore_admin.pl list"| sed 's/bin\/\.\.\///'
echo "\$PERL $INPUTDIR/vmware-lib/apps/connect.pl --server <VMware ESXi or Vcenter host>"| sed 's/bin\/\.\.\///'


#if (system("ld -shared -o $path/SSLeay.so $path/SSLeay.o -lcrypto -lssl") >> 8) {
#      print wrap("Unable to link the Crypt::SSLeay Perl module.  Secured " .
#                 "connections will be unavailable until you install the " .
#                 "Crypt::SSLeay module.\n\n", 0);
# exit 1;


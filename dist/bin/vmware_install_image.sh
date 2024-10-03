#!/bin/bash
#
# VMware API install script
#

. /home/lpar2rrd/lpar2rrd/etc/lpar2rrd.cfg

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
  exit 1
fi

#echo "$INPUTDIR"

WHEREAMI=`pwd`
os_aix=`uname -a|grep AIX|wc -l|sed 's/ //g'`
MIN_FS_SPACE=300 # 300MB space is needed for the package extraction and installation

# HOME space check
if [ $os_aix -gt 0 ]; then
  if [ `df -m $INPUTDIR |grep -iv free|awk '{print $3}'| sed 's/\..*//'` -lt $MIN_FS_SPACE ]; then
    echo "Increase filesystem space in user home directory to $MIN_FS_SPACE MB at least"
    exit 1
  fi
else
  if [ `df -m $INPUTDIR |grep -iv available|awk '{print $4}'| sed 's/\..*//'` -lt $MIN_FS_SPACE ]; then
    echo "Increase filesystem space in user home directory to $MIN_FS_SPACEMB at least"
    exit 1
  fi
fi


lpar=`echo "$WHEREAMI" | grep  lpar2rrd| wc -l `

if [ $# -lt 1 ]
then
  echo "You have to specify directory with VMware SDK install package"
  echo "Exiting..."
  exit 1
fi

PKGPATH=$1

# select the most recent version of package if any
PKGNAME=`ls -r1 $PKGPATH/VMware-vSphere-Perl-SDK-*.tar.gz 2>/dev/null| head -n 1`

if [ ! -f $PKGNAME -o "$PKGNAME"x = "x" ]; then
  echo "There is no VMware Perl SDK install package in the specified directory: $PKGPATH " | sed 's/bin\/\.\.\///'
  echo "Exiting..."
  exit 1
fi

echo "$PKGNAME found" | sed 's/bin\/\.\.\///'
cd $INPUTDIR

# extract  package
echo "Extracting selected package to $INPUTDIR/vmware-vsphere-cli-distrib ..."| sed 's/bin\/\.\.\///'
gunzip < $PKGNAME | tar xf - 2> /dev/null
ret=$?
if [ ! -d "$INPUTDIR/vmware-vsphere-cli-distrib" ]; then
  echo "Has not been found extracted distribution in: $INPUTDIR/vmware-vsphere-cli-distrib"| sed 's/bin\/\.\.\///'
  echo "Error: $?"
  echo "Try <a href=\"https://www.lpar2rrd.com/VMware-performance-monitoring-installation.php#VMWARE\"><b>manual installation</b></a> instead."
  echo "Exiting..."
  exit 1
fi

# install selected libraries and apps
echo "Installing selected libraries and apps to $INPUTDIR/vmware-lib ..."| sed 's/bin\/\.\.\///'
cd $INPUTDIR/vmware-vsphere-cli-distrib
mkdir $INPUTDIR/vmware-lib 2>/dev/null
cp -R lib/VMware/share/VMware $INPUTDIR/vmware-lib
rm -rf $INPUTDIR/vmware-lib/VMware/pyexe # remove useless Linux binaries
cp -R lib/libwww-perl-*/lib/* $INPUTDIR/vmware-lib
cp -R lib/URI-*/lib/* $INPUTDIR/vmware-lib
cp -R apps/general $INPUTDIR/vmware-lib/apps
echo ""

if [ $os_aix -eq 0 ]; then
    echo "Do not forget to install perl-Crypt-SSLeay package!"
else
    echo "If you have problems with Crypt-SSLeay during runtime then:"
    echo "  downaload http://sourceforge.net/projects/xcat/files/aix/xcat-dep/6.1/perl-Crypt-SSLeay-0.57-2.aix6.1.ppc.rpm and install as root:"
    echo "  rpm -Uvh perl-Crypt-SSLeay-0.57-2.aix6.1.ppc.rpm"
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

# fix for perl 5.26+ in VMware API
if [ -f $INPUTDIR/vmware-lib/URI/Escape.pm ]; then
  perl -pi $INPUTDIR/bin/URI_Escape_patch.pl $INPUTDIR/vmware-lib/URI/Escape.pm
fi

#echo Libraries and apps were copied to $INPUTDIR/vmware-lib ...
#echo ""
#echo "Don't forget to include this path to PERL5LIB in etc/lpar2rrd.cfg!"
#echo "export PERL5LIB=$INPUTDIR/vmware-lib:\$PERL5LIB"

# With VMware Perl SDK 6.7+ remove SSOConnection module which require Text/Template.pm
# SSOConnection we do not use anyway
if [ -f  "$INPUTDIR/vmware-lib/VMware/VICommon.pm" ]; then
  sed --in-place=.old 's/\(use VMware::SSOConnection.*\)/# \1/g' $INPUTDIR/vmware-lib/VMware/VICommon.pm
fi

# LWP SSL fix for VMware SDK
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

echo ""
echo "Continue by define VMware hosts and their credentials"
echo "GUI: menu --> VMware --> Configure --> Add credentials"
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


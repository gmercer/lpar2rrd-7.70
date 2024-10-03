#!/bin/sh
#
# LPAR2RRD install script
# usage                         : ./install.sh
# usage (wrap up the distro)    : ./install.sh wrap
# usage (unatended installation): ./install.sh <LPAR2RRD installation directory>
#


LANG=C
export LANG
HOME_ORG=$HOME

wlabel=lpar2rrd
WLABEL=LPAR2RRD

if [ -f wlabel.txt ]; then
  wlabel=`cat wlabel.txt| tail -1`
  WLABEL=`echo $wlabel| tr '[:lower:]' '[:upper:]'`
fi

if [ ! "$1"x = "x" ]; then
  if [ "$1" = "wrap" ]; then
    # create a package, internall usage only
    ver=`grep "version=" dist/etc/lpar2rrd.cfg|sed 's/version=//g'`
    if [ "$ver"x = "x" ]; then
      echo "Something is wroing, cannot find the version"
      exit 1
    fi
    if [ -f lpar2rrd.tar.Z ]; then
      echo "removing lpar2rrd.tar.Z"
      rm lpar2rrd.tar.Z
    fi
    if [ -f lpar2rrd.tar ]; then
      echo "removing lpar2rrd.tar"
      rm lpar2rrd.tar
    fi
    tar cvf lpar2rrd.tar dist
    compress lpar2rrd.tar
    if [ -f lpar2rrd.tar.Z ]; then
      echo "removing dist"
      rm -r dist
    fi
    echo ""
    echo "$ver has been created"
    echo ""
    exit
  else
    # unatended installation
    if [ -d "$1" ]; then
       HOMELPAR=$1
    else
       echo "Unrecognized instalation parameter ($1) or not existing LPAR2RRD home directory, exiting"
       exit
    fi
  fi
fi


os_aix=` uname -s|egrep "^AIX$"|wc -l|sed 's/ //g'`


# test if "ed" command does not exist, it might happen especially on some Linux distros
ed << END 2>/dev/null 1>&2
q
END
if [ $? -gt 0 ]; then
  echo "ERROR: "ed" command does not seem to be installed or in $PATH"
  echo "Linux under root account: yum install ed"
  echo "Exiting ..."
  exit 1
fi
echo "1+1"|bc 2>/dev/null 1>&2
if [ $? -gt 0 ]; then
  echo "ERROR: "bc" command does not seem to be installed or in $PATH"
  echo "Linux under root account: yum install bc"
  echo "Exiting ..."
  exit 1
fi

umask 0022 
ID=`id -un`
if [ $os_aix -eq 0 ]; then
  ECHO_OPT="-e"
else
  ECHO_OPT=""
fi


echo "LPAR2RRD installation under user : \"$ID\""
echo " make sure it is realy the user which should own it"
echo ""
if [ "$HOMELPAR"x = "x" ]; then
  echo "Where LPAR2RRD will be installed [$HOME/lpar2rrd]:"
  read HOMELPAR
fi
echo ""

if [ "$HOMELPAR"x = "x" ]; then
    HOMELPAR="$HOME/lpar2rrd"
fi

if [ -f $HOMELPAR/bin/lpar2rrd.pl -o -f $HOMELPAR/lpar2rrd.pl ]; then
  echo "LPAR2RRD instance already exists there, use update.sh script for the update"
  exit 0
fi


if [ "$HOMELPAR"x = "x" ]; then
  HOMELPAR=$HOME/lpar2rrd
fi

if [ ! -d "$HOMELPAR" ]; then
  echo "Creating $HOMELPAR"
  echo ""
  mkdir "$HOMELPAR"
  if [ ! $? -eq 0 ]; then
    echo "Error during creation of $HOMELPAR, exiting ..."
    exit 0
  fi
fi

touch test 
pwd=`pwd`
if [ ! $? -eq 0 ]; then
  echo "Actual user does not have rights to create files in actual directory: $pwd "
  echo "Fix it and re-run installation"
  exit 1
fi
rm -f test


if [ -f lpar2rrd.tar.Z ]; then
  which uncompress >/dev/null 2>&1 
  if [ $? -eq 0 ]; then 
     uncompress -f lpar2rrd.tar.Z 
  else 
     which gunzip >/dev/null 2>&1 
     if [ $? -eq 0 ]; then 
       gunzip -f lpar2rrd.tar.Z 
     else 
       echo "Could not locate uncompress or gunzip commands. exiting" 
       exit 
     fi 
  fi 
fi

chown $ID $HOMELPAR
if [ ! $? -eq 0 ]; then
  echo "Problem with ownership of $HOMELPAR"
  echo "Fix it and run it again : chown  $ID $HOMELPAR"
  exit 0
fi

echo "Extracting distribution"
tar xf lpar2rrd.tar

echo "Copy distribution to the target location: $HOMELPAR"
# mv dist/* $HOMELPAR/ # tar must be used due to Docker
apath=`pwd`
cd dist
tar cf - . | (cd $HOMELPAR/; tar xf - )
cd $apath

if [ $os_aix -gt 0 ]; then

  # extract perl lib for https REST API support (LWP 6.06)
  if [ -f perl_aix_ssl.tar.Z ]; then
    uncompress -f perl_aix_ssl.tar.Z
  fi
  if [ -f perl_aix_ssl.tar ]; then
    tar xf perl_aix_ssl.tar
    cp -R lib $HOMELPAR/
  else
    echo "ERROR during: uncompress -f perl_aix_ssl.tar.Z : install it manually"
    echo "  uncompress -f perl_aix_ssl.tar.Z; cd $HOMELPAR/; tar xvf perl_aix_ssl.tar"
  fi
fi

if [ -f version.txt ]; then
  version=`cat version.txt|tail -1|sed 's/ .*//'`
fi

#  put WEB files immediately after the upgrade to do not have to wait for the end of upgrade
echo "Copy GUI files : $HOMELPAR/www"
cp $HOMELPAR/html/*html $HOMELPAR/www
cp $HOMELPAR/html/*ico $HOMELPAR/www
cp $HOMELPAR/html/*png $HOMELPAR/www

cd $HOMELPAR/html
tar cf - jquery | (cd $HOMELPAR/www; tar xf - )
tar cf - css    | (cd $HOMELPAR/www; tar xf - )
#cd - >/dev/null
if [ ! -f "$HOMELPAR/tmp/menu.txt" -a -f "$HOMELPAR/html/menu_default.txt" ]; then
  #place default menu.txt
  cp $HOMELPAR/html/menu_default.txt $HOMELPAR/tmp/menu.txt
fi

if [ `grep $WLABEL $HOMELPAR/etc/.magic 2>/dev/null | wc -l | sed 's/ //g'` -eq 0 ]; then
  if [ ! "$WLABEL" = "LPAR2RRD" ]; then
    # add wlabel
    echo "WLABEL=$WLABEL" >> $HOMELPAR/etc/.magic
    echo "export WLABEL" >> $HOMELPAR/etc/.magic
  fi
fi


echo "Setting up directory permissions"
chown -R $ID $HOMELPAR 2>&1 |grep -v "lost+found"
chmod 755 $HOMELPAR
chmod 666 $HOMELPAR/logs/error.log
chmod 755 $HOMELPAR/data
chmod 755 $HOMELPAR/lib
chmod 755 $HOMELPAR/www
chmod 755 $HOMELPAR/bin
chmod 755 $HOMELPAR/etc
chmod 755 $HOMELPAR/scripts
chmod 755 $HOMELPAR/logs
if [ ! -d $HOMELPAR/tmp ]; then
  mkdir $HOMELPAR/tmp
fi
if [ "$VM_IMAGE"x = "x" ]; then
  chmod 777 $HOMELPAR/tmp  # due to "Refresh" feature which need to save temp files there
else
  chmod 755 $HOMELPAR/tmp  # not necessary on the image
fi
chmod -R 755 $HOMELPAR/html  # must be due tue subdirs jquery, images ...
chmod -R 755 $HOMELPAR/lpar2rrd-cgi
chmod -R o+r $HOMELPAR/data
chmod -R o+x $HOMELPAR/data
chmod -R o+r $HOMELPAR/www
chmod -R o+x $HOMELPAR/www
chmod 755 $HOMELPAR/dbschema
chmod 644 $HOMELPAR/dbschema/*
chmod 755 $HOMELPAR/bin/*.pl
chmod 755 $HOMELPAR/bin/*.pm
chmod 755 $HOMELPAR/bin/*.sh
chmod 755 $HOMELPAR/*.sh
chmod 644 $HOMELPAR/etc/*.cfg
chmod 755 $HOMELPAR/scripts/*
chmod 644 $HOMELPAR/*.txt
if [ -h $HOMELPAR/error-cgi.log ]; then
  rm $HOMELPAR/error-cgi.log
fi
if [ -h $HOMELPAR/realt-error.log ]; then
  rm $HOMELPAR/realt-error.log
fi
if [ ! -h $HOMELPAR/logs/error-cgi.log ]; then
  ln -s /var/tmp/lpar2rrd-realt-error.log $HOMELPAR/logs/error-cgi.log
fi

if [ -f $HOMELPAR/etc/rperf_user.txt_template ]; then
  mv $HOMELPAR/etc/rperf_user.txt_template $HOMELPAR/etc/rperf_user.txt
fi

if [ ! -d "$HOMELPAR/etc/web_config" ]; then
  mkdir "$HOMELPAR/etc/web_config"
fi
if [ "$VM_IMAGE"x = "x" ]; then
  chmod 777 "$HOMELPAR/etc/web_config"
  chmod 777 "$HOMELPAR/reports"
else
  chmod 755 "$HOMELPAR/etc/web_config"
  chmod 755 "$HOMELPAR/reports"
fi


if [ ! -f "$HOMELPAR/etc/web_config/htusers.cfg" ]; then
  echo 'admin:$apr1$CSoXefyw$wGe9K7Ld5ClOEozE4zC.T1' >  $HOMELPAR/etc/web_config/htusers.cfg
  if [ "$VM_IMAGE"x = "x" ]; then
    chmod 666 $HOMELPAR/etc/web_config/htusers.cfg
  else
    chmod 600 $HOMELPAR/etc/web_config/htusers.cfg
  fi
fi


export PATH=$PATH:/opt/freeware/bin
rrd=`which rrdtool | awk '{print $1}'|wc -w`
if [ $rrd -eq 0 ]; then
  if [ -f /opt/freeware/bin/rrdtool ]; then
    rrd="/opt/freeware/bin/rrdtool"
  else
    echo ""
    echo "Warning: RRDTool has not been found in \$PATH, using RRDTOOL=/usr/bin/rrdtool"
    echo "         assure it is ok, if not then edit $HOMELPAR/etc/lpar2rrd.cfg and change it"
    echo ""
    rrd="/usr/bin/rrdtool"
  fi
else
  rrd=`which rrdtool|awk '{print $1}'`
fi

if [ -f /opt/freeware/bin/perl ]; then
  per="/opt/freeware/bin/perl"
else 
  per=`which perl|awk '{print $1}'|wc -w`
  if [ $per -eq 0 ]; then
    echo ""
    echo "Warning: Perl has not been found in \$PATH, placing /usr/bin/perl"
    echo "         assure it is ok, if not then edit $HOMELPAR/etc/lpar2rrd.cfg and change it"
    echo ""
    per="/usr/bin/perl"
  else
    per=`which perl|awk '{print $1}'`
  fi
fi

if [ ! "$CUSTOM_PERL_INTERPRETER"x = "x" -a -f "$CUSTOM_PERL_INTERPRETER" ]; then
  per="$CUSTOM_PERL_INTERPRETER"
fi

# replace path for actual one in config files


HOMELPAR_slash=`echo $HOMELPAR|sed 's/\//\\\\\\//g'`
HOME_slash=`echo $HOME|sed 's/\//\\\\\\//g'`
rrd_slash=`echo $rrd|sed 's/\//\\\\\\//g'`
per_slash=`echo $per|sed 's/\//\\\\\\//g'`
bit64=`file $per 2>/dev/null| grep 64-bit| wc -l | sed 's/ //g'`


# add actual paths
PERL5LIB=/opt/freeware/lib/perl5/vendor_perl/5.8.8/ppc-thread-multi:/usr/opt/perl5/lib/site_perl/5.8.8/aix-thread-multi:/usr/lib64/perl5:/usr/lib64/perl5/vendor_perl/5.8.8:/opt/freeware/lib/perl/5.8.8:/opt/freeware/lib/perl/5.8.0:/usr/opt/perl5/lib/site_perl/5.8.2:/usr/lib/perl5/vendor_perl/5.8.5:/usr/share/perl5:/usr/lib/perl5:/usr/opt/perl5/lib/site_perl/5.8.8/aix-thread-multi:/opt/freeware/lib/perl5/vendor_perl/5.8.8/ppc-thread-multi:/usr/lib64/perl5/vendor_perl:/usr/lib/perl5/vendor_perl

# add actual paths
# This /usr/opt/perl5/lib/site_perl/5.8.8/aix-thread-multi must be befor /usr/opt/perl5/lib/site_perl/5.10.1/aix-thread-multi when is /opt/freeware/bin/perl used otherwisi is usede wrong SSLeay.so
# (https.pm is not found then)
p_ver=`$per -e 'print "$]\n"'`
if [ "$per" = "/opt/freeware/bin/perl" -a $p_ver = "5.008008" ]; then
  # AIX, excluded /usr/opt/perl5/lib64/5.28.1 which causing a problem
  PPATH="/usr/opt/perl5/lib/site_perl/5.8.8/aix-thread-multi
/opt/freeware/lib/perl5/vendor_perl/5.8.8/ppc-thread-multi
/usr/opt/perl5/lib/site_perl/5.8.8/aix-thread-multi
/opt/freeware/lib/perl5/site_perl/5.22.0/ppc-aix-thread-multi
/opt/freeware/lib64/perl5
/opt/freeware/lib/perl5
/opt/freeware/lib/perl
/usr/opt/perl5/lib/site_perl
/opt/freeware/lib/perl5/vendor_perl/5.8.8
/usr/share/perl5/vendor_perl
/opt/csw/share/perl/csw
/opt/csw/lib/perl/site_perl
/usr/opt/perl5/lib/site_perl/5.10.1/aix-thread-multi
/opt/freeware/lib/perl5/site_perl/5.28.0/ppc-aix-thread-multi
/opt/freeware/lib/perl5/site_perl
/usr/lib64/perl5/vendor_perl
/usr/opt/perl5/lib/site_perl/5.10.1
/usr/opt/perl5/lib/site_perl/5.28.1
/usr/opt/perl5/lib64/site_perl"
else
  if [ $bit64 -eq 0 ]; then
    PPATH="/usr/opt/perl5/lib/site_perl/5.8.8/aix-thread-multi
/opt/freeware/lib/perl5/vendor_perl/5.8.8/ppc-thread-multi
/usr/opt/perl5/lib/site_perl/5.8.8/aix-thread-multi
/opt/freeware/lib/perl5/site_perl/5.22.0/ppc-aix-thread-multi
/opt/freeware/lib/perl5
/opt/freeware/lib/perl
/usr/opt/perl5/lib/site_perl
/usr/lib/perl5/vendor_perl
/opt/freeware/lib/perl5/vendor_perl/5.8.8
/opt/freeware/lib/perl5/vendor_perl
/usr/share/perl5/vendor_perl
/opt/csw/share/perl/csw
/opt/csw/lib/perl/site_perl
/usr/opt/perl5/lib/site_perl/5.10.1/aix-thread-multi
/usr/opt/perl5/lib/site_perl/
/opt/freeware/lib/perl5/site_perl/5.28.0/ppc-aix-thread-multi
/opt/freeware/lib/perl5/site_perl/5.22.0
/opt/freeware/lib/perl5/site_perl/
/usr/opt/perl5/lib
/usr/opt/perl5/lib/site_perl/5.10.1
/usr/opt/perl5/lib/site_perl/5.28.1
/opt/freeware/lib/perl5/5.30/vendor_perl"
  else
    PPATH="/usr/opt/perl5/lib/site_perl/5.8.8/aix-thread-multi
/opt/freeware/lib/perl5/vendor_perl/5.8.8/ppc-thread-multi
/usr/opt/perl5/lib/site_perl/5.8.8/aix-thread-multi
/opt/freeware/lib/perl5/site_perl/5.22.0/ppc-aix-thread-multi
/opt/freeware/lib64/perl5
/opt/freeware/lib/perl5
/opt/freeware/lib/perl
/usr/opt/perl5/lib/site_perl
/usr/lib/perl5/vendor_perl
/opt/freeware/lib/perl5/vendor_perl/5.8.8
/opt/freeware/lib/perl5/vendor_perl
/usr/share/perl5/vendor_perl
/opt/csw/share/perl/csw
/opt/csw/lib/perl/site_perl
/usr/opt/perl5/lib/site_perl/5.10.1/aix-thread-multi
/usr/opt/perl5/lib/site_perl/
/opt/freeware/lib/perl5/site_perl/5.28.0/ppc-aix-thread-multi
/opt/freeware/lib/perl5/site_perl/5.22.0
/opt/freeware/lib/perl5/site_perl/
/usr/opt/perl5/lib64/5.28.1
/usr/opt/perl5/lib64/5.28.0
/usr/opt/perl5/lib64
/usr/opt/perl5/lib
/usr/lib64/perl5/vendor_perl
/usr/opt/perl5/lib64/site_perl
/usr/opt/perl5/lib64/site_perl/5.28.1
/usr/opt/perl5/lib64/site_perl/5.28.1/aix-thread-multi-64all
/usr/opt/perl5/lib/site_perl/5.10.1
/usr/opt/perl5/lib/site_perl/5.28.1
/opt/freeware/lib/perl5/5.30/vendor_perl
/opt/freeware/lib64/perl5/5.30/vendor_perl
/usr/opt/perl5/lib64/site_perl"
  fi
fi


# /opt/csw/share/perl/csw is necessary on Solaris

perl_version=`$per -v| grep "This is perl"| sed -e 's/^.* (v//' -e 's/) .*//' -e 's/^.* v//' -e 's/ .*//'`
perl_subversion=`$per -v| grep "This is perl"| sed -e 's/^.* (v//' -e 's/) .*//' -e 's/^.* v//' -e 's/ .*//' -e 's/\.[0-9][0-9]$//' -e 's/\.[0-9]$//' `

PLIB=`for ppath in $PPATH
do
  echo $PERL5LIB|grep "$ppath/$perl_version"  >/dev/null
  if [ ! $? -eq 0  -a -d "$ppath/$perl_version" ]; then
    echo "$ppath/$perl_version"
    echo "$ppath/$perl_version/vendor_perl"
    if [ $os_aix -eq 1 ]; then
      if [ $bit64 -eq 0 ]; then
        echo "$ppath/$perl_version/ppc-aix-thread-multi"
        echo "$ppath/$perl_version/aix-thread-multi"
      else
        echo "$ppath/$perl_version/aix-thread-multi-64all" # this must be behind 32bit!
      fi
    fi
  else
    echo $PERL5LIB|grep "$ppath"  >/dev/null
    if [ ! $? -eq 0  -a -d "$ppath" ]; then
      echo "$ppath"
    fi
  fi

  echo $PERL5LIB|grep "$ppath/$perl_version/aix-thread-multi"  >/dev/null
  if [ ! $? -eq 0  -a -d "$ppath/$perl_version/aix-thread-multi" ]; then
    echo "$ppath/$perl_version/aix-thread-multi"
  fi

  echo $PERL5LIB|grep "$ppath/$perl_version/ppc-aix-thread-multi"  >/dev/null
  if [ ! $? -eq 0  -a -d "$ppath/$perl_version/ppc-aix-thread-multi" ]; then
    echo "$ppath/$perl_version/ppc-aix-thread-multi"
  fi

  echo $PERL5LIB|grep "$ppath/$perl_version/vendor_perl"  >/dev/null
  if [ ! $? -eq 0  -a -d "$ppath/$perl_version/vendor_perl" ]; then
    echo "$ppath/$perl_version/vendor_perl"
  fi


  echo $PERL5LIB|grep "$ppath/$perl_subversion"  >/dev/null
  if [ ! $? -eq 0  -a -d "$ppath/$perl_subversion" ]; then
    echo "$ppath/$perl_subversion"
    echo "$ppath/$perl_subversion/vendor_perl"
    if [ $os_aix -eq 1 ]; then
      if [ $bit64 -eq 0 ]; then
        echo "$ppath/$perl_subversion/ppc-aix-thread-multi"
        echo "$ppath/$perl_subversion/aix-thread-multi"
      else
        echo "$ppath/$perl_subversion/aix-thread-multi-64all" # this must be behind 32bit!
      fi
    fi
  else
    echo $PERL5LIB|grep "$ppath"  >/dev/null
    if [ ! $? -eq 0  -a -d "$ppath" ]; then
      echo "$ppath"
    fi
  fi

  echo $PERL5LIB|grep "$ppath/$perl_subversion/aix-thread-multi"  >/dev/null
  if [ ! $? -eq 0  -a -d "$ppath/$perl_subversion/aix-thread-multi" ]; then
    echo "$ppath/$perl_subversion/aix-thread-multi"
  fi

  echo $PERL5LIB|grep "$ppath/$perl_subversion/ppc-aix-thread-multi"  >/dev/null
  if [ ! $? -eq 0  -a -d "$ppath/$perl_subversion/ppc-aix-thread-multi" ]; then
    echo "$ppath/$perl_subversion/ppc-aix-thread-multi"
  fi

  echo $PERL5LIB|grep "$ppath/$perl_subversion/vendor_perl"  >/dev/null
  if [ ! $? -eq 0  -a -d "$ppath/$perl_subversion/vendor_perl" ]; then
    echo "$ppath/$perl_subversion/vendor_perl"
  fi

done|xargs|sed 's/ /:/g'`

perl5lib="$HOMELPAR/bin:$HOMELPAR/vmware-lib:$PLIB:$PERL5LIB:$HOMELPAR/lib"

# Clean up PERL5LIB, place only existing dirs
PERL5LIB_new=""
for lib_path in `echo $perl5lib| sed 's/:/ /g'`
do
  if [ -d "$lib_path" ]; then
    if [ `echo "$PERL5LIB_new" | egrep "$lib_path:|$lib_path$" | wc -l | sed 's/ //g'` -eq 1 ]; then
      continue
    fi
    if [ "$PERL5LIB_new"x = "x" ]; then
      PERL5LIB_new=$lib_path
    else
      PERL5LIB_new=$PERL5LIB_new:$lib_path
    fi
  fi
done

# AIX: always keep this in PERL5LIB
# /opt/freeware/lib/perl/5.8.8:/usr/opt/perl5/lib/site_perl/5.8.8/aix-thread-multi:/opt/freeware/lib/perl5/vendor_perl/5.8.8/ppc-thread-multi
if [ $os_aix -eq 1 ]; then
  if [ `echo "$PERL5LIB_new"|grep "/opt/freeware/lib/perl/5.8.8" | wc -l` -eq 0 ]; then
    PERL5LIB_new="$PERL5LIB_new:/opt/freeware/lib/perl/5.8.8"
  fi
  if [ `echo "$PERL5LIB_new"|grep "/usr/opt/perl5/lib/site_perl/5.8.8/aix-thread-multi" | wc -l` -eq 0 ]; then
    PERL5LIB_new="$PERL5LIB_new:/usr/opt/perl5/lib/site_perl/5.8.8/aix-thread-multi"
  fi
  if [ `echo "$PERL5LIB_new"|grep "/opt/freeware/lib/perl5/vendor_perl/5.8.8/ppc-thread-multi" | wc -l` -eq 0 ]; then
    PERL5LIB_new="$PERL5LIB_new:/opt/freeware/lib/perl5/vendor_perl/5.8.8/ppc-thread-multi"
  fi
fi

# Solaris: always keep this in PERL5LIB
# /opt/csw/share/perl/csw /opt/csw/lib/perl/site_perl
if [ `uname|grep SunOS|wc -l|  sed 's/ //g'` -eq 1 ]; then
  if [ `echo "$PERL5LIB_new"|grep "/opt/csw/share/perl/csw" | wc -l` -eq 0 ]; then
    PERL5LIB_new="$PERL5LIB_new:/opt/csw/share/perl/csw"
  fi
  if [ `echo "$PERL5LIB_new"|grep "/opt/csw/lib/perl/site_perl" | wc -l` -eq 0 ]; then
    PERL5LIB_new="$PERL5LIB_new:/opt/csw/lib/perl/site_perl"
  fi
fi


perl5lib_slash=`echo "$PERL5LIB_new"|sed -e 's/::/:/g' -e 's/\//\\\\\\//g'`
 
echo "Configuring $HOMELPAR/etc/lpar2rrd.cfg" 
ed $HOMELPAR/etc/lpar2rrd.cfg << EOF 1>/dev/null
g/__LPAR2RRD_HOME__/s/__LPAR2RRD_HOME__/$HOMELPAR_slash/g
g/__USER_HOME__/s/__USER_HOME__/$HOME_slash/g
g/__LPAR2RRD_USER__/s/__LPAR2RRD_USER__/$ID/g
g/__RRDTOOL__/s/__RRDTOOL__/$rrd_slash/g
g/__PERL__/s/__PERL__/$per_slash/g
g/__PERL5LIB__/s/__PERL5LIB__/$perl5lib_slash/g
w
q
EOF
ret=$?
if [ ! $ret -eq 0 ]; then
  if [ $ret -eq 127 ]; then
    echo ""
    echo "Error!"
    echo "Probably does not exist command: \"ed\" "
    echo "If it is the case then install ed, \"rm -r $HOMELPAR\" and run install once more"
  else
    echo ""
    echo "Error!"
    echo "Customization of $HOMELPAR/etc/lpar2rrd.cfg failed"
    echo "Contact product support ... "
  fi
  exit 0
fi

# Solaris ssh does not recognizes -o SendEnv=no
if [ `uname|grep SunOS|wc -l|  sed 's/ //g'` -eq 1 ]; then
ed $HOMELPAR/etc/lpar2rrd.cfg << EOF 1>/dev/null
g/ -o SendEnv=no/s/ -o SendEnv=no/ /g
w
q
EOF
fi

# creating ssh keys if they do not exist
echo "" |ssh-keygen -t dsa -P "" 2>/dev/null 1>/dev/null
SSH_WEB_IDENT=$HOME/.ssh/realt_dsa
#if [ ! -f "$SSH_WEB_IDENT" ]; then 
#  # realt_dsa exist, then probably keay are already in place
#  echo "Do you want to create ssh-keys now (ssh-keygen -t dsa)?[n]"
#  read Y
#
#  if [ "$Y" = "y" -o "$Y" = "Y" ]; then
#    echo ""
#    ssh-keygen -t dsa
#    echo ""
#    echo ""
#  fi
#fi


WWW_USER=`ps -ef|egrep "apache|httpd"|grep -v grep|awk '{print $1}'|grep -v "root"|head -1`
if [ "$WWW_USER"x = x ]; then
  WWW_USER=nobody
fi

if [ ! -d $HOME/.ssh ]; then
    echo "Could not be found directory with ssh-keys ($HOME/.ssh)"
    echo " You wil need to do manually following:"
    echo " 1. create ssh-keys (ssh-keygen -t dsa)"
    echo " 2. copy keys to a new file and assign read rights for the web user : $WWW_USER"
    echo "   # cp $HOME/.ssh/id_dsa $HOME/.ssh/realt_dsa"
    echo "   under root account :"
    echo "   # chown $WWW_USER $HOME/.ssh/realt_dsa"
    echo "   # chmod 600 $HOME/.ssh/realt_dsa"
    echo ""
else
    if [ ! -f "$SSH_WEB_IDENT" ]; then 
      chmod 755 $HOME/.ssh
      if [ -f $HOME/.ssh/id_dsa ]; then
        cp -f $HOME/.ssh/id_dsa $SSH_WEB_IDENT
        chmod 600 $SSH_WEB_IDENT 
      else
        if [ -f $HOME/.ssh/id_rsa ]; then
          cp -f $HOME/.ssh/id_rsa $SSH_WEB_IDENT
          chmod 600 $SSH_WEB_IDENT 
        else
          echo "Could not be found ssh-keys in ($HOME/ssh)"
          echo " You wil need to do manually following:"
          echo " 1. create ssh-keys (ssh-keygen -t dsa)"
          echo " You wil need to do manually following:"
          echo " 2. copy keys to a new file and assign read rights for the web user : $WWW_USER"
          echo "   # cp $HOME/.ssh/id_dsa $HOME/.ssh/realt_dsa"
          echo "   under root account :"
          echo "   # chown $WWW_USER $SSH_WEB_IDENT
          echo "   # chmod 600 $SSH_WEB_IDENT
          echo ""
        fi
      fi
   fi
fi


# stop the agent daemon althought it is the installation!! who knows what user is doing ...
if [ -f "$HOMELPAR/tmp/lpar2rrd-daemon.pid" ]; then
  PID=`cat "$HOMELPAR/tmp/lpar2rrd-daemon.pid"|sed 's/ //g'`
  if [ ! "$PID"x = "x" ]; then
    echo "Stopping LPAR2RRD daemon"
    kill `cat "$HOMELPAR/tmp/lpar2rrd-daemon.pid"`
  fi
fi
run=`ps -ef|grep lpar2rrd-daemon.pl| egrep -v "grep |vi | vim "|wc -l`
if [ $run -gt 0 ]; then
  kill `ps -ef|grep lpar2rrd-daemon.pl| egrep -v "grep |vi | vim "|awk '{print $2}'` 2>/dev/null
fi


cd $HOMELPAR

# change #!bin/ksh in shell script to #!bin/bash on Linux platform
os_linux=` uname -s|egrep "^Linux$"|wc -l|sed 's/ //g'`
if [ $os_linux -eq 1 ]; then
  # If Linux then change all "#!bin/sh --> #!bin/bash
  for sh in $HOMELPAR/bin/*.sh $HOMELPAR/bin/check_lpar2rrd
  do
  ed $sh << EOF >/dev/null 2>&1
1s/\/ksh/\/bash/
w
q
EOF
  done

  for sh in $HOMELPAR/scripts/*.sh
  do
  ed $sh << EOF >/dev/null 2>&1
1s/\/ksh/\/bash/
w
q
EOF
  done

  for sh in $HOMELPAR/*.sh
  do
  ed $sh << EOF >/dev/null 2>&1
1s/\/ksh/\/bash/
w
q
EOF
  done

  for sh in $HOMELPAR/lpar2rrd-cgi/*.sh
  do
  ed $sh << EOF >/dev/null 2>&1
1s/\/ksh/\/bash/
w
q
EOF
  done

else
  # for AIX Solaris etc, all should be already in place just to be sure ...
  # change all "#!bin/bash --> #!bin/ksh
  for sh in $HOMELPAR/bin/*.sh
  do
  ed $sh << EOF >/dev/null 2>&1
1s/\/bash/\/ksh/
w
q
EOF
  done

  for sh in $HOMELPAR/scripts/*.sh
  do
  ed $sh << EOF >/dev/null 2>&1
1s/\/bash/\/ksh/
w
q
EOF
  done

  for sh in $HOMELPAR/*.sh
  do
  ed $sh << EOF >/dev/null 2>&1
1s/\/bash/\/ksh/
w
q
EOF
  done

  for sh in $HOMELPAR/lpar2rrd-cgi/*.sh
  do
  ed $sh << EOF >/dev/null 2>&1
1s/\/bash/\/ksh/
w
q
EOF
  done
fi

# not necessary since 4.70 due to a new GUI
#echo ""
#echo "Custom groups config file creation"
#$HOMELPAR/scripts/update_cfg_custom-groups.sh update

# not longer used (since 4.75)
#echo ""
#echo "Favourites config file creation"
#$HOMELPAR/scripts/update_cfg_favourites.sh update

#echo ""
#echo "Alerting config file creation"
#$HOMELPAR/scripts/update_cfg_alert.sh update

# Check web user has read&executable rights for CGI dir lpar2rrd-cgi
dir=`echo "$HOMELPAR/www"|sed 's/\\\//g'`
DIR=""
IFS_ORG=$IFS
IFS="/"
for i in $dir
do
  IFS=$IFS_ORG
  NEW_DIR=`echo $DIR$i/`
  #echo "01 $NEW_DIR -- $i -- $DIR ++ $www"
  NUM=`ls -dLl $NEW_DIR |awk '{print $1}'|sed -e 's/d//g' -e 's/-//g' -e 's/w//g' -e 's/\.//g'| wc -c`
  #echo "02 $NUM"
  if [ ! $NUM -eq 7 ]; then
    echo ""
    echo "WARNING, directory : $NEW_DIR has probably wrong rights"| sed 's/\/\//\//g'
    echo "         $www dir and its subdirs have to be executable&readable for WEB user"
    ls -lLd $NEW_DIR| sed 's/\/\//\//g'
    echo ""
  fi
  DIR=`echo "$NEW_DIR/"`
  #echo $DIR
  IFS="/"
done
IFS=$IFS_ORG


# ulimit check
# necessary for big aggregated graphs
#
# AIX:
# chuser  data=8388608  lpar2rrd (4GB)
# chuser  stack=1048576 lpar2rrd (512MB)

ulimit_message=0
data=`ulimit -d`
stack=`ulimit -s`
if [ $os_aix -eq 1 ]; then
  if [ ! "$data" = "unlimited" -a ! "$data" = "hard" -a ! "$data" = "soft" ]; then
    if [ $data -lt 4194304 ]; then
      echo ""
      echo "Warning: increase data ulimit for $ID user, it is actually too low ($data kB)"
      echo "Assure that the same limits has even the web user (apache/nobody/http)"
      echo "  under root: chuser  data=8388608 $ID # 4GB"
    fi
  fi
  if [ ! "$stack" = "unlimited" -a ! "$stack" = "hard" -a ! "$data" = "soft" ]; then
    if [ $stack -lt 524288  ]; then
      echo ""
      echo "Warning: increase stack ulimit for $ID user, it is actually too low ($stack kB)"
      echo "Assure that the same limits has even the web user (apache/nobody/http)"
      echo "  under root: chuser  stack=1048576 $ID # 512MB"
    fi
  fi
else # Linux
  if [ ! "$data" = "unlimited" -a ! "$data" = "hard" -a ! "$data" = "soft" ]; then
    if [ $data -lt 4194304 ]; then
      echo ""
      echo "Warning: increase data ulimit for $ID user, it is actually too low ($data)"
      echo "Assure that the same limits has even the web user (apache/nobody/http)"
      echo "  under root: vi /etc/security/limits.conf"
      echo "    @$ID        hard    data            4194304"
      echo "    @$ID        soft    data            4194304"
    fi
  fi
  if [ ! "$stack" = "unlimited" -a ! "$stack" = "hard" -a ! "$data" = "soft" ]; then
    if [ $stack -lt 524288  ]; then
      echo ""
      echo "Warning: increase stack ulimit for $ID user, it is actually too low ($stack)"
      echo "Assure that the same limits has even the web user (apache/nobody/http)"
      echo "  under root: vi /etc/security/limits.conf"
      echo "    @$ID        hard    stack           524288"
      echo "    @$ID        soft    stack           524288"
    fi
  fi
fi

# Check process limits on AIX only
if [ $os_aix -eq 1 ]; then
  maxuproc=`lsattr -El sys0 -a maxuproc| awk '{print $2}'`
  if [ ! "$maxuproc"x = "x" ]; then
    if [ $maxuproc -lt 129 ]; then
      echo ""
      echo "Warning: definitely increase user process limit, it is actually too low ($maxuproc)"
      echo "  under root: chdev -l sys0 -a maxuproc=1024"
    else
      if [ $maxuproc -lt 1024 ]; then
        echo ""
        echo "Warning: increase user process limit, it could be low when you monitoring a lot of devices ($maxuproc)"
        echo "  under root: chdev -l sys0 -a maxuproc=1024"
      fi
    fi
  fi
fi


cd $HOMELPAR
if [ $os_aix -eq 0 ]; then
  free=`df .|grep -iv filesystem|xargs|awk '{print $4}'`
  freemb=`echo "$free/1048"|bc 2>/dev/null`
  if [ $? -eq 0 -a ! "$freemb"x = "x" ]; then
    if [ $freemb -lt 1048 ]; then
      echo ""
      echo "WARNING: free space in $HOMELPAR is too low : $freemb MB"
      echo "         note that 1 HMC needs about 1GB space depends on number of servers/lpars"
    fi
  fi
else
  free=`df .|grep -iv filesystem|xargs|awk '{print $3}'`
  freemb=`echo "$free/2048"|bc 2>/dev/null`
  if [ $? -eq 0 -a ! "$freemb"x = "x" ]; then
    if [ $freemb -lt 1048 ]; then
      echo ""
      echo "WARNING: free space in $HOMELPAR is too low : $freemb MB"
      echo "         note that 1 HMC needs about 1GB space depends on number of servers/lpars"
    fi
  fi
fi


# setting up the font dir (necessary for 1.3 on AIX)
FN_PATH="<?xml version=\"1.0\"?>
<!DOCTYPE fontconfig SYSTEM \"fonts.dtd\">
<fontconfig>
<dir>/opt/freeware/share/fonts/dejavu</dir>
</fontconfig>"

if [ ! -f "$HOME/.config/fontconfig/.fonts.conf" -o `grep -i deja "$HOME/.config/fontconfig/.fonts.conf" 2>/dev/null|wc -l` -eq 0 ]; then
  if [ ! -d "$HOME/.config" ]; then
    mkdir "$HOME/.config"
  fi
  if [ ! -d "$HOME/.config/fontconfig" ]; then
    mkdir "$HOME/.config/fontconfig"
  fi
  echo $FN_PATH >> "$HOME/.config/fontconfig/.fonts.conf"
fi
chmod 644 "$HOME/.config/fontconfig/.fonts.conf"
# no, no, it issues this error:
# Fontconfig warning: "/opt/freeware/etc/fonts/conf.d/50-user.conf", line 9: reading configurations from ~/.fonts.conf is deprecated.
#if [ ! -f "$HOME/.fonts.conf" ]; then
#  echo $FN_PATH > "$HOME/.fonts.conf"
#  chmod 644 "$HOME/.fonts.conf"
#fi


# for web server user home
if [ ! -d "$HOMELPAR/tmp/home" ]; then
  mkdir "$HOMELPAR/tmp/home"
fi
#if [ ! -f "$HOMELPAR/tmp/home/.fonts.conf" ]; then
#  echo $FN_PATH > "$HOMELPAR/tmp/home/.fonts.conf"
#fi
if [ ! -d "$HOMELPAR/tmp/home/.config" ]; then
  mkdir "$HOMELPAR/tmp/home/.config"
fi
if [ ! -d "$HOMELPAR/tmp/home/.config/fontconfig" ]; then
  mkdir "$HOMELPAR/tmp/home/.config/fontconfig"
fi
if [ ! -f "$HOMELPAR/tmp/home/.config/fontconfig/fonts.conf" ]; then
  echo $FN_PATH >> "$HOMELPAR/tmp/home/.config/fontconfig/fonts.conf"
fi
chmod 755 "$HOMELPAR/tmp/home"
chmod 755 "$HOMELPAR/tmp/home/.config"
chmod 755 "$HOMELPAR/tmp/home/.config/fontconfig"
chmod 644 "$HOMELPAR/tmp/home/.config/fontconfig/fonts.conf"

# RRDTool existency checking
$rrd >/dev/null 2>&1
ret=$?
if [ ! $ret -eq 127 ]; then
  $rrd|grep graphv >/dev/null 2>&1
  ret=$?
  if [ $ret -eq 1 ]; then
    # suggest RRDTool upgrade
    rrd_version=`$rrd -v|head -1|awk '{print $2}'`
    echo "Condider RRDtool upgrade to version 1.3.5+ (actual one is $rrd_version)"
    echo "This will allow graph zooming: http://www.lpar2rrd.com/zoom.html"
    echo ""
  fi
fi

if [ $os_linux -gt 0 ]; then
  # LinuxSE warning
  SELINUX=`ps -ef | grep -i selinux| grep -v grep|wc -l`

  if [ "$SELINUX" -gt 0  ]; then
    GETENFORCE=`getenforce 2>/dev/null`
    if [ "$GETENFORCE" = "Enforcing" ]; then
      echo ""
      echo "Warning!!!!!"
      echo "SELINUX status is Enforcing, it might cause a problem during Apache setup"
      echo "like this in Apache error_log: (13)Permission denied: access to /XXXX denied"
      echo ""
    fi
  fi
fi

#VMware
if [ ! -d "$HOMELPAR/.vmware" ]; then
  mkdir "$HOMELPAR/.vmware"
  chmod 755 "$HOMELPAR/.vmware"
fi
if [ ! -d "$HOMELPAR/.vmware/credstore" ]; then
  mkdir "$HOMELPAR/.vmware/credstore"
  chmod 777 "$HOMELPAR/.vmware/credstore" # must be 777 to allow writes of Apache user
fi

# Apache authorization, it must be here because path has to be modified as per installation home
cat << END > $HOMELPAR/html/.htaccess
SetEnv XORUX_ACCESS_CONTROL 1
AuthUserFile $HOMELPAR/etc/web_config/htusers.cfg
AuthName "$WLABEL Authorized personnel only."
AuthType Basic
Require valid-user
END

if [ $os_aix -eq 1 ]; then
  # AIX (at least) rrdtool 1.7 issue when prints mem profiling info to pwd/mon.out
  touch $HOMELPAR/lpar2rrd-cgi/mon.out
  chmod 777 $HOMELPAR/lpar2rrd-cgi/mon.out
  touch $HOMELPAR/bin/mon.out
  chmod 777 $HOMELPAR/bin/mon.out

  # Font cache refresh, it migh speed up significantly graphs creation on AIX
  # it creates it in /home/lpar2rrd/tmp/home/.cache/fontconfig and in /home/lpar2rrd/.cache/fontconfig
  if [ ! -d "$HOMELPAR/tmp/home" ]; then
    mkdir "$HOMELPAR/tmp/home"
  fi
  fc-cache -fv 1>/dev/null 2>&1
  HOME="$HOMELPAR/tmp/home"; fc-cache -fv 1>/dev/null 2>&1
fi

# IPv6 support, however not on AIX, there is an issue
if [ ! $os_aix -eq 1 ]; then
  rhel_ver_check=`rpm --eval '%{rhel}'`
  if [ $? -eq 0 ]; then
    # skip CentOS 6 and older
    if [ ! -n "$rhel_ver_check" ] || [ `echo $rhel_ver_check| grep rhel| wc -l| sed 's/ //g'` -eq 1 ] || [ "$rhel_ver_check" -gt 6 ]; then
      for file_snmp in $HOMELPAR/bin/*.pl
      do
ed $file_snmp << EOF 1>/dev/null 2>/dev/null
g/IO::Socket::INET/s/IO::Socket::INET/IO::Socket::IP/g
w
q
EOF
      done
      for file_snmp in $HOMELPAR/bin/*.pm
      do
ed $file_snmp << EOF 1>/dev/null 2>/dev/null
g/IO::Socket::INET/s/IO::Socket::INET/IO::Socket::IP/g
w
q
EOF
      done
    fi
  else
    # OS version not found, go ahead only in case of Linux
    if [ `uname -s` = "Linux" ]; then
      for file_snmp in $HOMELPAR/bin/*.pl
      do
ed $file_snmp << EOF 1>/dev/null 2>/dev/null
g/IO::Socket::INET/s/IO::Socket::INET/IO::Socket::IP/g
w
q
EOF
      done
      for file_snmp in $HOMELPAR/bin/*.pm
      do
ed $file_snmp << EOF 1>/dev/null 2>/dev/null
g/IO::Socket::INET/s/IO::Socket::INET/IO::Socket::IP/g
w
q
EOF
      done
    fi
  fi
fi

# Checking installed Perl modules, it must be after above IPv6
cd $HOMELPAR
. etc/lpar2rrd.cfg; export INPUTDIR=$HOMELPAR; $PERL bin/perl_modules_check.pl $PERL
echo ""


echo ""
echo "Installation has finished"
echo "Follow post-install instructions at:"
echo "  http://www.lpar2rrd.com/install.htm"

date=`date "+%Y-%m-%d_%H:%M"`
echo "$version $date $pwd" >> $HOMELPAR/etc/version.txt
echo "$HOMELPAR" > $HOME_ORG/.lpar2rrd_home 2>/dev/null


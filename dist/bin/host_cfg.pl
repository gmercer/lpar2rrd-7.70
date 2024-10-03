
use strict;
use warnings;
use CGI::Carp qw(fatalsToBrowser);
use MIME::Base64 qw(encode_base64 decode_base64);
use Data::Dumper;
use File::Copy;
use File::Temp qw/ tempfile/;
use JSON;
use Fcntl ':flock';    # import LOCK_* constants
use File::Basename;
use HostCfg;
use ACL;
use POSIX qw (strftime);
use Xorux_lib;

my $acl = ACL->new;

my $useacl        = $acl->useACL();
my $isAdmin       = $acl->isAdmin();
my $aclAdminGroup = $acl->getAdminGroup();
my $basedir       = $ENV{INPUTDIR};
$basedir ||= "..";
my $bindir        = "$basedir/bin";
my $perl          = $ENV{PERL};
my $ssh_web_ident = $ENV{SSH_WEB_IDENT};
my $webdir        = $ENV{WEBDIR};
my $vmwlibdir     = "$basedir/vmware-lib/apps";
my $credstore     = "$basedir/.vmware/credstore/vicredentials.xml";

my $whoami = `whoami`;
chop $whoami;
my $host_cfg_log = "$basedir/etc/web_config/config_check_$whoami.log";
open( my $host_cfg_log_fh, ">>", $host_cfg_log );

my %platforms = (
  power         => { longname => "IBM Power Systems", pid => 'load_hmc_rest_api.sh.pid', croncmd => "# IBM Power Systems - REST API\n0,20,40 * * * * $basedir/load_hmc_rest_api.sh > $basedir/load_hmc_rest_api.out 2>&1" },
  vmware        => { longname => "VMware",            pid => 'load_vmware.sh.pid' },
  xen           => { longname => "XenServer",         pid => 'load_xenserver.sh.pid',     croncmd => "# XEN Server support\n0,20,40 * * * *  $basedir/load_xenserver.sh > $basedir/load_xenserver.out 2>&1" },
  nutanix       => { longname => "Nutanix",           pid => 'load_nutanix.sh.pid',       croncmd => "# Nutanix\n0,20,40 * * * *  $basedir/load_nutanix.sh > $basedir/load_nutanix.out 2>&1" },
  aws           => { longname => "AWS",               pid => 'load_aws.sh.pid',           croncmd => "# AWS\n0,20,40 * * * *  $basedir/load_aws.sh > $basedir/load_aws.out 2>&1" },
  gcloud        => { longname => "GCloud",            pid => 'load_gcloud.sh.pid',        croncmd => "# Google Cloud\n0,20,40 * * * *  $basedir/load_gcloud.sh > $basedir/load_gcloud.out 2>&1" },
  azure         => { longname => "Azure",             pid => 'load_azure.sh.pid',         croncmd => "# Microsoft Azure\n0,20,40 * * * *  $basedir/load_azure.sh > $basedir/load_azure.out 2>&1" },
  kubernetes    => { longname => "Kubernetes",        pid => 'load_kubernetes.sh.pid',    croncmd => "# Kubernetes\n0,20,40 * * * *  $basedir/load_kubernetes.sh > $basedir/load_kubernetes.out 2>&1" },
  openshift     => { longname => "Red Hat OpenShift", pid => 'load_openshift.sh.pid',     croncmd => "# Openshift\n0,20,40 * * * *  $basedir/load_openshift.sh > $basedir/load_openshift.out 2>&1" },
  cloudstack    => { longname => "Apache CloudStack", pid => 'load_cloudstack.sh.pid',    croncmd => "# Apache CloudStack\n0,20,40 * * * *  $basedir/load_cloudstack.sh > $basedir/load_cloudstack.out 2>&1" },
  proxmox       => { longname => "Proxmox",           pid => 'load_proxmox.sh.pid',       croncmd => "# Proxmox\n0,20,40 * * * *  $basedir/load_proxmox.sh > $basedir/load_proxmox.out 2>&1" },
  fusioncompute => { longname => "FusionCompute",     pid => 'load_fusioncompute.sh.pid', croncmd => "# Huawei FusionCompute\n0,20,40 * * * *  $basedir/load_fusioncompute.sh > $basedir/load_fusioncompute.out 2>&1" },
  hyperv        => { longname => "Hyper-V",           pid => 'load_hyperv.sh.pid' },
  kvm           => { longname => "KVM" },
  ovirt         => { longname => "RHV (oVirt)",       pid => 'load_ovirt.sh.pid',     croncmd => "# oVirt / RHV Server support\n0,20,40 * * * *  $basedir/load_ovirt.sh > $basedir/load_ovirt.out 2>&1" },
  oraclevm      => { longname => "OracleVM",          pid => 'load_oraclevm.sh.pid',  croncmd => "# OracleVM\n0,20,40 * * * *  $basedir/load_oraclevm.sh > $basedir/load_oraclevm.out 2>&1" },
  oracledb      => { longname => "OracleDB",          pid => 'load_oracledb.sh.pid',  croncmd => "# OracleDB\n0,5,10,15,20,25,30,35,40,45,50,55  * * * *  $basedir/load_oracledb.sh > $basedir/load_oracledb.out 2>&1" },
  sqlserver     => { longname => "SQLServer",         pid => 'load_sqlserver.sh.pid', croncmd => "# SQLServer\n0,5,10,15,20,25,30,35,40,45,50,55  * * * *  $basedir/load_sqlserver.sh > $basedir/load_sqlserver.out 2>&1" },
  postgres      => { longname => "PostgreSQL",        pid => 'load_postgres.sh.pid',  croncmd => "# PostgreSQL\n0,5,10,15,20,25,30,35,40,45,50,55  * * * *  $basedir/load_postgres.sh > $basedir/load_postgres.out 2>&1" },
  db2           => { longname => "DB2",               pid => 'load_db2.sh.pid',       croncmd => "# DB2\n0,5,10,15,20,25,30,35,40,45,50,55  * * * *  $basedir/load_db2.sh > $basedir/load_db2.out 2>&1" },
  cmc           => { longname => "IBM Power CMC", pid => 'load_hmc_rest_api.sh.pid', croncmd => "# IBM Power Systems - REST API\n0,20,40 * * * * $basedir/load_hmc_rest_api.sh > $basedir/load_hmc_rest_api.out 2>&1" },
  custom        => { longname => "Custom Group" },
  common        => { longname => "load.sh", pid => 'load.sh.pid', croncmd => "0 * * * *  $basedir/load.sh > $basedir/load.out 2>&1" },
);

# print STDERR "$useacl  $aclAdminGroup\n";

my $json = JSON->new->utf8->pretty;

sub file_write {
  my $file = shift;
  open my $IO, ">", $file or die "Cannot open $file for output: $!\n";
  print $IO @_;
  close $IO;
}

sub file_write_append {
  my $file = shift;
  my $IO;
  if ( -f $file ) {
    open $IO, ">>", $file or die "Cannot open $file for output: $!\n";
  }
  else {
    open $IO, ">", $file or die "Cannot open $file for output: $!\n";
  }
  print $IO @_;
  close $IO;
}

sub file_read {
  my $file = shift;
  open my $IO, $file or die "Cannot open $file for input: $!\n";
  my @data = <$IO>;
  close $IO;
  wantarray ? @data : join( '' => @data );
}

sub trim {
  my $s = shift;
  if ($s) {
    $s =~ s/^\s+|\s+$//g;
  }
  return $s;
}

my $buffer;

if ( !defined $ENV{'REQUEST_METHOD'} ) {
  print "Content-type: text/plain\n\n";
  print "No command specified, exiting...";

  my %hosts = %{ HostCfg::getHostConnections("IBM Power Systems") };
  print Dumper \%hosts;
  exit;
}

if ( lc $ENV{'REQUEST_METHOD'} eq "post" ) {
  read( STDIN, $buffer, $ENV{'CONTENT_LENGTH'} );
}
else {
  $buffer = $ENV{'QUERY_STRING'};
}

my %PAR = %{ Xorux_lib::parse_url_params($buffer) };

# print STDERR Dumper \%PAR;

if ( !defined $PAR{cmd} ) {
  print "Content-type: text/plain\n\n";
  print "No command specified, exiting...";
  exit;
}

elsif ( $PAR{cmd} eq "json" ) {    ### Get list of credentials
  my ( $cfg, $imported ) = HostCfg::getNoPassRawConfig($aclAdminGroup);

  #warn $imported;
  if ($imported) {
    print "X-Hosts-Imported: true\n";
  }
  print "Content-type: application/json\n\n";
  print $cfg;

}
elsif ( $PAR{cmd} eq "form" ) {
  print "Content-type: text/html\n\n";

  my $platform = $PAR{platform};
  my $user     = "admin";
  if ( $acl->getUser() ) {
    $user = $acl->getUser();
  }

  if ( $useacl && !$isAdmin ) {
    print "<div>You have to be a member of Administrators group to change hosts configuration!</div>";
    exit;
  }
  my @errors;

  if ( $platform eq "ovirt" ) {
    my @reqmods = qw(DBI DBD::Pg);
    for my $mod (@reqmods) {
      eval {
        ( my $file = $mod ) =~ s|::|/|g;
        require $file . '.pm';
        $mod->import();
        1;
      } or do {
        push @errors, "$@";
      }
    }
  }

  if ( $platform eq "vmware" && !-e "$vmwlibdir/credstore_admin.pl" ) {
    print "<p><b>VMware Perl SDK</b> libraries and apps are not installed yet. We are not authorized to redistribute the <b>VMWare Perl SDK</b> due to licensing restrictions.<p>";
    if ( defined $ENV{VI_IMAGE} && $ENV{VI_IMAGE} ) {
      print <<_MARKER_;
    <p>Download <a href='https://code.vmware.com/sdk/vsphere-perl' target="blank"><b>vSphere Perl SDK</b></a> from VMware website to your computer and then upload it to the running appliance via following form:<br>
    It requires free registration at VMware.<br>
    Does not matter if 32bit or 64bit package<br>
    VMware-vSphere-Perl-SDK-&lt;version&gt;.tar.gz, download one of *tar.gz</p>
    <form id="sdk-install" action="/lpar2rrd-cgi/vmwcfg.sh" method="post" enctype="multipart/form-data">
    <p>File to Upload: <input type="file" accept=".gz" name="sdk"></p>
    <p><input type="submit" id="sdk-upload" name="Submit" value="Upload SDK file" /></p>
    <div class="progress">
      <div class="bar"></div >
      <div class="percent">0%</div >
    </div>
    </form>
  <div id="status"></div>
_MARKER_
    }
    else {
      print "<p>Try <a href=\"https://www.lpar2rrd.com/VMware-performance-monitoring-installation.php#VMWARE\"><b>manual installation</b></a> instead.</p>";
    }
    exit;
  }
  elsif ( $platform eq "ovirt" && @errors ) {
    print "<p style='font-style: italic'><span style='color: red'>Warning:</span> You cannot use Postgres database, your host system cannot find required Perl modules:<p>" . join( "</p><p>", @errors ) . "</p><p>Install modules as per this <b><a href='http://www.lpar2rrd.com/oVirt-Postgres-support.htm' target='_blank'>document</a></b>.</p>";
  }
  elsif ( $platform eq "ibm" ) {
    # TABs for Power CFG
    print "<p></p><div id='tabs' class='tabbed_cfg' style='text-align: center;'> \
    <ul> \
    <li><a href='/lpar2rrd-cgi/hosts.sh?cmd=form&platform=power'>HMC</a></li> \
    <li><a href='/lpar2rrd-cgi/hosts.sh?cmd=form&platform=cmc'>CMC</a></li> \
    </ul>";

    print "</div>";
  }
  else {
    cfgpage( $platform );
  }

}

elsif ( $PAR{cmd} eq "saveall" ) {    ### Save configuration as is
  my $basedir = $ENV{INPUTDIR};
  $basedir ||= "..";

  my $cfgdir = "$basedir/etc/web_config";

  my $tmpdir = "$basedir/tmp";
  if ( defined $ENV{TMPDIR_LPAR} ) {
    $tmpdir = $ENV{TMPDIR_LPAR};
  }

  # print "Content-type: application/json\n\n";
  print "Content-type: text/html\n\n";
  if ( $PAR{acl} ) {
    my $retstr   = "";
    my $old_json = file_read("$cfgdir/hosts.json");
    my $old_cfg  = decode_json($old_json);

    # if ( $ENV{'SERVER_NAME'} eq "demo.stor2rrd.com" ) {
    if ( $ENV{'DEMO'} ) {
      $retstr = "\"msg\" : \"<div>This demo site does not allow saving any changes you do in the admin GUI panel.</div>\"";
      $retstr .= ", \"cfg\" : \"\"";
      print "{ \"status\" : \"fail\", $retstr }";
      exit;
    }

    # disable for now...
    if ( $useacl && !$isAdmin ) {
      print "{ \"status\" : \"fail\", \"msg\" : \"<div>You have to be a member of Administrators group to change hosts configuration!</div>\" }";
      exit;
    }
    if ( open( my $CFG, ">", "$cfgdir/hosts.json" ) ) {
      my $cfg = decode_json( $PAR{acl} );

      # merge unchanged old passwords from saved cfg file
      foreach my $platform ( keys %{ $cfg->{platforms} } ) {
        if ( $cfg->{platforms}{$platform}{aliases} ) {
          foreach my $alias ( keys %{ $cfg->{platforms}{$platform}{aliases} } ) {
            foreach my $key ( keys %{ $cfg->{platforms}{$platform}{aliases}{$alias} } ) {
              if ( $key =~ "password" ) {
                if ( ( $cfg->{platforms}{$platform}{aliases}{$alias}{$key} eq "1" ) || ( $cfg->{platforms}{$platform}{aliases}{$alias}{$key} eq "YA==" ) ) {    # Base64 encoded empty string
                  if ( defined $old_cfg->{platforms}{$platform}{aliases}{$alias}{$key} ) {                                                                      # if the password was set earlier
                    $cfg->{platforms}{$platform}{aliases}{$alias}{$key} = $old_cfg->{platforms}{$platform}{aliases}{$alias}{$key};
                  }
                }
              }
            }
          }
        }
      }
      flock( $CFG, LOCK_EX );
      print $CFG $json->encode($cfg);
      close $CFG;
      $retstr = "\"msg\" : \"<div>Hosts configuration has been successfully saved!<br /><br /></div>\"";

      if ( $PAR{toremove} ) {
        my $flag_file = "$basedir/tmp/$ENV{version}-run";
        `touch $flag_file`;        # set flag to regenerate menu on next load
        chmod 0666, $flag_file;    # allow backend to delete that file

        if ( $ENV{XORMON} ) {
          require SQLiteDataWrapper;
          my $retval = SQLiteDataWrapper::deleteItemFromConfig( { label => $PAR{toremove}, hw_type => $PAR{hw_type}, hostname => $PAR{hostname}, uuid => $PAR{uuid} } );
          warn "Remove device '$PAR{toremove}' (HW type: $PAR{hw_type}, UUID: $PAR{uuid}) from Xormon database: $retval";
        }
      }
      print "{ \"status\" : \"success\", $retstr }";

      require LogCfgChanges;
      my $new_json = file_read("$cfgdir/hosts.json");
      LogCfgChanges::save_diff( $old_json, $new_json, "hosts.json", $acl->getUser() );
    }
    else {
      print "{ \"status\" : \"fail\", \"msg\" : \"<div>File $cfgdir/hosts.json cannot be written by webserver, check apache user permissions: <span style='color: red'>$!</span></div>\" }";
    }
  }
  else {
    print "{ \"status\" : \"fail\", \"msg\" : \"<div>No data was written to hosts.json</div>\" }";
  }

}
elsif ( $PAR{cmd} eq "grptree" ) {
  my %cfg = ReporterCfg::getConfig();
  print "Content-type: application/json\n\n";
  print "[";
  my $n1 = "";

  # print Dumper \%cfg;
  foreach my $grp ( sort keys %{ $cfg{groups} } ) {
    if ( $grp eq "$aclAdminGroup" ) {
      next;
    }
    print $n1 . "{\"title\":\"$grp\"}\n";
    $n1 = "\n,";
  }
  print "]\n";
}

elsif ( $PAR{cmd} eq "sshkeys" ) {    ### Get SSH keys
  print "Content-type: application/json\n\n";
  my @keys = HostCfg::getSSHKeys();
  print $json->encode( \@keys );
}
elsif ( $PAR{cmd} eq "conntest" ) {
  print "Content-type: application/json\n\n";
  my $host     = $PAR{host};
  my $port     = $PAR{port};
  my $platform = $PAR{platform};
  my $alias    = $PAR{alias};

  if ( defined $platform && defined $host && ( $platform eq "Kubernetes" || $platform eq "Openshift" ) ) {
    my @row = split( /:/, $host );
    $host = defined $row[0] ? $row[0] : $host;
    $port = defined $row[1] ? $row[1] : ();
  }
  elsif ( defined $platform && defined $host && $platform eq "SQLServer" ) {
    my @row = split( /\\/, $host );
    $host = defined $row[0] ? $row[0] : $host;
  }

  if ( $platform and $platform eq "OracleDB" ) {
    my %creds = %{ HostCfg::getHostConnections("OracleDB") };
    if ( $alias and $creds{$alias}{type} eq "RAC" ) {
      my $msg     = "";
      my $err_msg = "";
      foreach my $odb_host ( @{ $creds{$alias}{hosts} } ) {
        my %result = connTest( $odb_host, $port );
        if ( $result{status} eq "1" ) {
          $msg .= "$result{msg} </br>";
        }
        elsif ( $result{status} eq "0" ) {
          $err_msg .= "$result{msg} </br>";
        }
      }
      if ( $err_msg eq "" ) {
        result( 1, $msg );
      }
      else {
        result( 0, $err_msg );
      }
    }
    else {
      my %result = connTest( $host, $port );
      result( $result{status}, $result{msg} );
    }
  }
  elsif ($platform and $platform eq "IBM Power CMC") {
    # simple API, no token, +proxy
    my %creds = %{ HostCfg::getHostConnections("IBM Power CMC") };

    if ( $alias and $creds{$alias}{username} ) {

      my $host     = $creds{$alias}{host};
      my $username = $creds{$alias}{username};
      my $password = $creds{$alias}{password};

      my $proxy = '';
      if ( $creds{$alias}{proto} && $creds{$alias}{proxy_url}){
        $proxy = "$creds{$alias}{proto}://$creds{$alias}{proxy_url}";
      }
      #warn Dumper %creds;
      #warn "$host $username $password $proxy";
      my $output = `$perl $bindir/power_cmc-apitest.pl "$host" "$username" "$password" "$proxy"`;
      #result( $result{status}, $result{msg} );
      #my %result = connTestProxy( $host, $port, $proxy);
      if ($output =~ /^\s{0,3}OK/){
        $output =~ s/^\s{0,3}OK/<span class='noerr'>OK<\/span>/;
        my $out_message = "Connection to $host $output";
        result( 1, $output );
        exit
      }
      else{
        $output = "<span class='error'>NOK<\/span>".$output;
        result( 0, $output );
        exit
      }
    }
  }
  else {
    my %result = connTest( $host, $port );
    result( $result{status}, $result{msg} );
  }

}

elsif ( $PAR{cmd} eq "apitest" ) {

  print "Content-type: application/json\n\n";

  my $platform = $PAR{platform};
  my $alias    = $PAR{alias};

  my $cfg = HostCfg::getHostCfg( $platform, $alias );

  my $host     = $PAR{host};
  my $port     = $PAR{port};
  my $proto    = $PAR{proto};
  my $username = $PAR{username};

  # my $password = HostCfg::unobscure_password( $PAR{password} );
  my $password = $cfg->{password};

  if ( $platform eq "XenServer" ) {

    # warn "$host $username $password";
    my $output = `$perl $bindir/xen-test-xapi.pl "$host" "$port" "$proto" "$username" "$password"`;
    print $output;
    exit;
  }
  elsif ( $platform eq "Nutanix" ) {
    my $output = `$perl $bindir/nutanix-apitest.pl "$host" "$port" "$proto" "$username" "$password"`;
    print $output;
    exit;
  }
  elsif ( $platform eq "AWS" ) {
    my $aws_alias = $PAR{alias};
    $password  = HostCfg::unobscure_password($cfg->{aws_secret_access_key});
    my $output    = `$perl $bindir/aws-apitest.pl "$host" "$aws_alias" "$username" "$password"`;
    print $output;
    exit;
  }
  elsif ( $platform eq "GCloud" ) {
    my $aws_alias = $PAR{alias};
    my $output    = `$perl $bindir/gcloud-apitest.pl "$host" "$aws_alias"`;
    print $output;
    exit;
  }
  elsif ( $platform eq "Azure" ) {
    my $aws_alias = $PAR{alias};
    my $output    = `$perl $bindir/azure-apitest.pl "$host" "$aws_alias"`;
    print $output;
    exit;
  }
  elsif ( $platform eq "Cloudstack" ) {
    my $output = `$perl $bindir/cloudstack-apitest.pl "$host" "$port" "$proto" "$username" "$password"`;
    print $output;
    exit;
  }
  elsif ( $platform eq "Proxmox" ) {
    my $output = `$perl $bindir/proxmox-apitest.pl "$host" "$port" "$proto" "$username" "$password"`;
    print $output;
    exit;
  }
  elsif ( $platform eq "FusionCompute" ) {
    my $output = `$perl $bindir/fusioncompute-apitest.pl "$host" "$port" "$proto" "$username" "$password" "$PAR{type}" "$PAR{instance}"`;
    print $output;
    exit;
  }
  elsif ( $platform eq "Kubernetes" || $platform eq "Openshift" ) {
    my $k8s_alias = $PAR{alias};
    my $output    = `$perl $bindir/kubernetes-apitest.pl "$host" "$PAR{password}" "$PAR{proto}" "$k8s_alias" "$platform"`;
    print $output;
    exit;
  }
  elsif ( $platform eq "IBM Power CMC" ) {
    #warn "APITEST: CMC";
    my $output = `$perl $bindir/power_cmc-apitest.pl "$host"`;
    #warn "test done?";
    #warn "$output";
    #print "HERE";
    print $output;
    exit;
  }
  elsif ( $platform eq "IBM Power Systems" ) {
    my $managednames = `\$PERL $basedir/bin/hmc-restapi-test.pl "$host" 2>>$host_cfg_log`;
    chomp($managednames);
    if ( length($managednames) != 0 && $managednames !~ m/No Servers Found/ && $managednames !~ m/^NOK/ ) {
      result( 1, "API HMC OK : $host" );
      exit;
    } elsif ($managednames =~ m/^NOK/){
      result ( 0, "$managednames" );
      exit;
    }
    else {
      print $managednames;
      result( 0, "User $username authorization failed on $proto://$host:$port.<br>Check username and password<br>Check if $host version is at least HMC v8 otherwise use HMC CLI (SSH)<br>Troubleshooting: <a href=\"www.lpar2rrd.com/IBM-Power-Systems-REST-API-troubleshooting.htm\">www.lpar2rrd.com/IBM-Power-Systems-REST-API-troubleshooting.htm</a>", $managednames );
      exit;
    }
  }
  elsif ( $platform eq "VMware" ) {
    my $call_err = "$perl $basedir/vmware-lib/apps/connect.pl --credstore '$credstore' --server '$host' --username '$username' --password '$password' --portnumber '$port' --protocol '$proto' 2>&1";
    my $conn;
    eval {
      local $SIG{ALRM} = sub { die 'Timed Out'; };
      alarm 30;
      $conn = `$perl $basedir/vmware-lib/apps/connect.pl --credstore '$credstore' --server '$host' --username '$username' --password '$password' --portnumber '$port' --protocol '$proto' 2>&1`;
      alarm 0;
    };
    alarm 0;    # race condition protection
    if ( $@ && $@ =~ /Timed Out/ ) {
      result( 0, "$@", "API login to $host timed out after 30 seconds!" );
    }
    elsif ( $conn =~ "Connection Successful" ) {
      result( 1, "API authorization to $host is <span class='noerr'>OK</span>." );
    }
    else {
      if ( $conn =~ "Server version unavailable" ) {
        my $outext = `$perl $basedir/bin/perl_modules_check.pl`;
        if ( $outext =~ "Perl module has not been found" ) {
          $outext =~ s/\n/<br>\n/g;
          result( 0, "$conn<br>$outext\n" );
        }
        else {
          result( 0, "API authorization to $host has failed!<br>$conn\n" );
        }
      }
      else {
        result( 0, "API authorization to $host has failed!<br>$conn\n" );
      }
    }
  }
  elsif ( $platform eq "RHV (oVirt)" ) {
    require DBI;
    my $driver   = "Pg";
    my $database = "ovirt_engine_history";
    my $dsn      = "DBI:$driver:dbname = $database; host = $host; port = $port";
    my $dbh      = DBI->connect( $dsn, $username, $password, { RaiseError => 0 } );
    if ($dbh) {
      my $stmt = qq(SELECT * FROM calendar LIMIT 5;);
      my $sth  = $dbh->prepare($stmt);
      my $rv   = $sth->execute();
      if ($rv) {
        if ( $rv < 0 ) {
          result( 0, $DBI::errstr );
        }
        else {
          result( 1, "Connected database successfully" );
        }
      }
      else {
        result( 0, $DBI::errstr );
      }
    }
    else {
      result( 0, $DBI::errstr );
    }
  }
  elsif ( $platform eq "OracleVM" ) {

    # warn "$host $username $password";
    my $output = `$perl $bindir/oraclevm-test-api.pl "$host" "$port" "$proto" "$username" "$password"`;
    print $output;
    exit;
  }
  elsif ( $platform eq "OracleDB" ) {

    #warn "$username $host $password";
    my %creds   = %{ HostCfg::getHostConnections("OracleDB") };
    my $type    = $PAR{type};
    my $alias   = $PAR{alias};
    my $db_name = $PAR{instance};
    if ( defined $type and $type eq "RAC" ) {
      $host = join( " ", @{ $creds{$alias}{hosts} } );
    }
    my $output = `$perl $bindir/oracledb-test-api.pl "$db_name" "$host" "$port" "$type" "$username" "\"\'$password\'\""`;
    print $output;
    exit;
  }
  elsif ( $platform eq "SQLServer" ) {

    #warn "$username $host $password";
    my %creds   = %{ HostCfg::getHostConnections("SQLServer") };
    my $type    = $PAR{type};
    my $alias   = $PAR{alias};
    my $db_name = $PAR{instance};

    my $output = `$perl $bindir/sqlserver-apitest.pl "$db_name" "$host" "$port" "$type" "$username" "\"\'$password\'\""`;
    print $output;
    exit;
  }
  elsif ( $platform eq "PostgreSQL" ) {

    #warn "$username $host $password";
    my %creds   = %{ HostCfg::getHostConnections("PostgreSQL") };
    my $type    = $PAR{type};
    my $alias   = $PAR{alias};
    my $db_name = $PAR{instance};
    if ( defined $type and $type eq "RAC" ) {
      $host = join( " ", @{ $creds{$alias}{hosts} } );
    }
    my $output = `$perl $bindir/postgres-apitest.pl "$db_name" "$host" "$port" "$type" "$username" "\"\'$password\'\""`;
    print $output;
    exit;
  }
  elsif ( $platform eq "SQLServer" ) {

    #warn "$username $host $password";
    my %creds   = %{ HostCfg::getHostConnections("SQLServer") };
    my $type    = $PAR{type};
    my $alias   = $PAR{alias};
    my $db_name = $PAR{instance};
    my $output  = `$perl $bindir/sqlserver-apitest.pl "$db_name" "$host" "$port" "$type" "$username" "\"\'$password\'\""`;
    print $output;
    exit;
  }
  elsif ( $platform eq "DB2" ) {

    #warn "$username $host $password";
    my %creds   = %{ HostCfg::getHostConnections("DB2") };
    my $type    = $PAR{type};
    my $alias   = $PAR{alias};
    my $db_name = $PAR{instance};
    my $output  = `$perl $bindir/db2-apitest.pl "$db_name" "$host" "$port" "$type" "$username" "\"\'$password\'\""`;
    print $output;
    exit;
  }
  elsif ( $platform eq "IBM Power CMC" ) {
    #warn "HERE---------";
    #warn "$username $host $password";
    my $alias   = $PAR{alias};
    my %creds   =  %{HostCfg::getHostConnections("IBM Power CMC")};

    my $host     = $creds{$alias}{host};
    my $username = $creds{$alias}{username};
    my $password = $creds{$alias}{password};

    my $proxy_url = "";

    if ( defined $creds{$alias}{proxy_url} && $creds{$alias}{proxy_url} && defined $creds{$alias}{proto} && $creds{$alias}{proto} ) {
      $proxy_url = "$creds{$alias}{proto}".'://'."$creds{$alias}{proxy_url}";
    }
    my $output  = `$perl $bindir/power_cmc-apitest.pl "$host" "$username" "$password" "$proxy_url" `;
    print $output;
    exit;
  }
  else {
    print "{ \"success\": false, \"error\" : \"Not implemented, WIP\"}";
  }
}

# SSH authentication (key-based)
elsif ( $PAR{cmd} eq "sshtest" ) {
  print "Content-type: application/json\n\n";
  my $platform = $PAR{platform};
  my $host     = $PAR{host};
  my $port     = $PAR{port};
  my $username = $PAR{username};
  my $sshkey;
  if ( $platform eq "IBM Power Systems" ) {
    result( 0, "Do not use basic SSH test for Power." );
    exit;
    $sshkey = $ssh_web_ident;
  }
  else {
    $sshkey = $PAR{sshkey};
  }

  # test SSH, only if LPAR2RRD is running the same user as Apache user
  my $lpar_owner    = get_lpar2rrd_owner();
  my $lpar_run_user = `whoami`;
  chomp $lpar_run_user;
  if ( ( defined $ENV{VI_IMAGE} && $ENV{VI_IMAGE} == 1 ) || $lpar_owner eq $lpar_run_user ) {

    # warn "$host $port $username $sshkey";
    my $response = `$bindir/sshtest.sh "$host" "$port" "$username" "$sshkey"`;
    print $response;
    exit;
  }
  else {
    result( 0, "Test can be done only manually via ssh command line<br><br>\n" . " su - $lpar_owner<br>\n" . " cd $basedir<br>\n" . " ./bin/sshtest.sh $host $port $username $sshkey" );
  }

  exit;
}

# test commands/environment over SSH
elsif ( $PAR{cmd} eq "sshdatatest" ) {

  print "Content-type: application/json\n\n";
  my $platform = $PAR{platform};
  my $host     = $PAR{host};
  my $port     = $PAR{port};
  my $username = $PAR{username};
  my $sshkey;
  if ( $platform eq "IBM Power Systems" ) {
    $sshkey = $ssh_web_ident;
  }
  else {
    $sshkey = $PAR{sshkey};
  }

  # setup the script and alternative help message for your platform
  my ( $ssh_cmd, $alt_help );
  my $lpar_run_user = `whoami`;
  chomp $lpar_run_user;
  my $lpar_owner = get_lpar2rrd_owner();

  if ( $platform eq "IBM Power Systems" ) {
    $ssh_cmd  = "sh $bindir/sample_rate.sh $host";
    $alt_help = "<br>Test can be done only manually via ssh command line<br><br>\nsu - $lpar_owner<br>cd $basedir<br>./bin/sample_rate.sh $host<br>\n";
    if ( ( defined $ENV{VI_IMAGE} && $ENV{VI_IMAGE} == 1 ) || $lpar_owner eq $lpar_run_user ) {
      my $output = `$ssh_cmd`;
      my %out;
      my @lines = split( "\n", $output );

      for ( my $i = 0; $i <= ( scalar(@lines) ); $i++ ) {
        if ( defined $lines[$i] && $lines[$i] ne "" && $lines[$i] =~ m/OK/ ) {

          my ( $first, $time ) = split( "=", $lines[$i] );
          my @first_part = split( ":", $first );
          my $status;
          my $hmc_status;
          my $sample_rate;
          my $servername;
          my $hmc_time;
          my $host;
          my $server_time;

          if ( defined $first_part[3] && $first_part[3] ne "" ) {    #SERVER
            ( $status, $sample_rate, $servername ) = ( $first_part[0], $first_part[1], $first_part[2] );
            $out{server}{$servername}{lparsutil_time} = $time;
            $out{server}{$servername}{status}         = $status;
            $out{server}{$servername}{sample_rate}    = $sample_rate;
          }
          else {                                                     #HMC
            ( $hmc_status, $host ) = ( $first_part[0], $first_part[1] );
            $out{hmc_info}{hmc_time} = $time;
            $out{hmc_info}{host}     = $host;
            $out{hmc_info}{status}   = $status;
          }

        }
      }
      if ( !defined $out{hmc_info}{hmc_time} ) {
        $output =~ s/\n/<br>/g;
        result( 0, "Error: $output" );
        exit;
      }
      my $html;
      my $i = 0;
      $html = "<table id=\"pwrsrvtest\"><tbody>";
      $html .= "<tr><td>HMC Time</td><td id=$i><span>$out{hmc_info}{hmc_time}</span></td></tr>";
      $i++;
      foreach my $servername ( keys %{ $out{server} } ) {
        $html .= "<tr>
                 <td>$servername</td>
                 <td id=\"td_$i\">
                    <span>$out{server}{$servername}{status} Sample Rate:$out{server}{$servername}{sample_rate}, $out{server}{$servername}{lparsutil_time}</span>
                 </td>
              </tr>";
        $i++;
      }
      $html .= "</tbody></table><br>Assure that HMC_time is more less same as server_time on its servers.<br>Refer to <a target=\"blank\" href=\"http://www.lpar2rrd.com/HMC-CLI-time.htm\">http://www.lpar2rrd.com/HMC-CLI-time.htm</a> when times are different (30mins+)";
      result( 1, $html );
      exit;
    }
    else {
      result( 0, $alt_help );
      exit;
    }
  }
  elsif ( $platform eq "XenServer" ) {
    $ssh_cmd  = "$bindir/xen-test-ssh.sh \"$host\" \"$port\" \"$username\" \"$sshkey\"";
    $alt_help = "Test can be done only manually via ssh command line<br><br>\n" . " su - $lpar_owner<br>\n" . " cd $basedir<br>\n" . " ./bin/xen-test-ssh.sh $host $port $username $sshkey";
  }
  else {
    result( 0, "test not supported for $platform" );
    exit;
  }

  # test SSH, only if LPAR2RRD is running in the image, thus access to keys is not an issue
  if ( ( defined $ENV{VI_IMAGE} && $ENV{VI_IMAGE} == 1 ) || $lpar_owner eq $lpar_run_user ) {

    # warn "$host $port $username $sshkey";
    my $output = `$ssh_cmd`;
    print $output;
  }
  else {
    result( 0, $alt_help );
  }

  exit;
}

elsif ( $PAR{cmd} eq "vmwaredatatest" ) {

  print "Content-type: application/json\n\n";

  my $alias    = $PAR{alias};
  my $platform = $PAR{platform};
  my $host     = $PAR{host};
  my $port     = $PAR{port};
  my $proto    = $PAR{proto};
  my $username = $PAR{username};
  my $password = HostCfg::unobscure_password( $PAR{password} );
  if ($password eq "") {
    my $cfgdir = "$basedir/etc/web_config";
    my $old_json = file_read("$cfgdir/hosts.json");
    my $old_cfg  = decode_json($old_json);
    if ( $old_cfg->{platforms}{VMware}{aliases} && $old_cfg->{platforms}{VMware}{aliases}{$alias} && $old_cfg->{platforms}{VMware}{aliases}{$alias}{password} ) {
      $password = $old_cfg->{platforms}{VMware}{aliases}{$alias}{password};
    }
  }
  my $call_err = "$perl $basedir/vmware-lib/apps/connect.pl --credstore '$credstore' --server '$host' --username '$username' --password '$password' --portnumber '$port' --protocol '$proto' 2>&1";
  my $conn     = "";

  # save STDOUT and redirect actual one to /dev/null,
  # Opts::validate() can print on stdout some garbage what leds to incorect answer to front-end
  open( my $oldout, ">&STDOUT" );
  open( LOG,        ">/dev/null" );
  *STDOUT = *LOG;

  eval {
    local $SIG{ALRM} = sub { die 'Timed Out'; };
    alarm 60;

    require VMware::VIRuntime;

    # easy test if at least one VM and one HostSystem presented
    $ENV{VI_SERVER}    = "$host";
    $ENV{VI_USERNAME}  = "$username";
    $ENV{VI_CREDSTORE} = "$credstore";
    Opts::parse();
    Opts::validate();
    Util::connect();

    my $obj_views = Vim::find_entity_views( view_type => 'VirtualMachine', properties => ['name'] );
    if ( !defined $obj_views || $obj_views eq "" || !defined @$obj_views[0] ) {
      $conn = "not presented any VirtualMachine - is there Read-only permission for all Vmware folders?";
    }
    $obj_views = Vim::find_entity_views( view_type => 'HostSystem', properties => ['name'] );
    if ( !defined $obj_views || $obj_views eq "" || !defined @$obj_views[0] ) {
      $conn = "not presented any HostSystem - is there Read-only permission for all Vmware folders?";
    }
    Util::disconnect();
    alarm 0;

    # recovery of STDOUT
    close(LOG);
    open( STDOUT, ">&", $oldout ) or die "Can't dup \$oldout: $!";

    if ( $conn =~ "not presented" ) {
      result( 0, "$conn" );
    }
    else {
      result( 1, "$conn" );
    }
  };
  alarm 0;    # race condition protection

  if ($@) {

    # recovery of STDOUT
    close(LOG);
    open( STDOUT, ">&", $oldout ) or die "Can't dup \$oldout: $!";
    if ( $@ =~ /Timed Out/ ) {
      result( 0, "Data test timed out after 60 seconds!" );
    }
    else {
      if ( $@ =~ /stty failed/ ) {
        result( 0, "Data test failed: <br>Most probably you have more entries of that vCenter in $credstore<br>Edit it and remove all except the last one and try it again" );
      }
      else {
        result( 0, "Data test failed: <br>$@" );
      }
    }
  }

}
elsif ( $PAR{cmd} eq "vmwareremovecreds" ) {    ### remove selected credentials
  print "Content-type: application/json\n\n";
  if ( defined $ENV{DEMO} ) {
    &result( 0, "You cannot remove credentials in live demo" );
    exit;
  }
  my $alias    = $PAR{alias};
  my $username = $PAR{username};
  my $server   = $PAR{server};
  if ( $server && $username ) {    # alias is empty, remove credentials too
                                   # my $call = "PER5LIB=$perl5lib; $perl $vmwlibdir/connect.pl --credstore $credstore --server $server --username $username --verbose";
    my $call = "$perl $vmwlibdir/credstore_admin.pl --credstore '$credstore' remove --server '$server' --username '$username' 2>&1";

    # print $call . "\n";
    my $conn = `$call`;
    if ( $? == -1 ) {
      &result( 0, "command failed: $!" );
    }
    elsif ( $? == 0 ) {
      chomp $conn;
      if ( $conn =~ "successfully" ) {
        &result( 1, "$conn" );
      }
      else {
        &result( 0, "$conn" );
      }
    }
    else {
      my $arg = sprintf( "command exited with value %d", $? >> 8 );
      &result( 0, "$arg\n$conn" );
    }
  }
  else {
    &result( 0, "You have to specify server and username!" );
  }

}
elsif ( $PAR{cmd} eq "vmwareaddcreds" ) {    ### add new connection
  print "Content-type: application/json\n\n";
  my $alias    = $PAR{alias};
  my $username = $PAR{username};
  my $server   = $PAR{server};
  my $password = HostCfg::unobscure_password( $PAR{password} );
  if ($password eq "") {
    my $cfgdir = "$basedir/etc/web_config";
    my $old_json = file_read("$cfgdir/hosts.json");
    my $old_cfg  = decode_json($old_json);
    if ( $old_cfg->{platforms}{VMware}{aliases} && $old_cfg->{platforms}{VMware}{aliases}{$alias} && $old_cfg->{platforms}{VMware}{aliases}{$alias}{password} ) {
      $password = $old_cfg->{platforms}{VMware}{aliases}{$alias}{password};
    }
  }

  if ( $alias && $server && $username && $password ) {
    $ENV{VMPASS} = $password;
    my $call = "$perl $vmwlibdir/credstore_admin.pl --credstore '$credstore' add --server '$server' --username '$username' --password \"\$VMPASS\" 2>&1";
    my $conn = `$call`;
    $ENV{VMPASS} = "";
    if ( -e $credstore && -f _ && -r _ ) {

      # check other user read permissions
      use Fcntl ':mode';
      my $mode       = ( stat($credstore) )[2];
      my $other_read = $mode & S_IROTH;
      if ( !$other_read ) {

        # set 644 if not world readable
        chmod 0644, $credstore;
      }
      $mode = sprintf "%04o", S_IMODE($mode);
    }
    if ( $? == -1 ) {
      &result( 0, "command failed: $!" );
    }
    elsif ( $? == 0 ) {
      chomp $conn;
      if ( $conn =~ "successfully" ) {
        &result( 1, "$conn" );
      }
      else {
        &result( 0, "$conn" );
      }
    }
    else {
      my $arg = sprintf( "command exited with value %d", $? >> 8 );
      &result( 0, "$arg $conn" );
    }
  }
  else {
    &result( 0, "You have to specify alias, server, username and password!" );
  }
}

elsif ( $PAR{cmd} eq "powerserverlist" ) {
  print "Content-type: application/json\n\n";
  my $hmc     = $PAR{hmc};
  my $srvlist = `\$PERL $basedir/bin/hmc-restapi-test.pl "$hmc" 2>>$host_cfg_log`;
  if ( $srvlist =~ m/expired/ || $srvlist =~ m/No Servers Found/ ) {
    result( 0, "No servers found. Maybe not supported HMC version (should be at least v8)", $srvlist );
  }
  else {
    print $srvlist;
  }
}

elsif ( $PAR{cmd} eq "powerserversingletest" ) {
  print "Content-type: application/json\n\n";
  my $platform   = $PAR{platform};
  my $hmc        = $PAR{hmc};
  my $server     = $PAR{server};
  my $testresult = `\$PERL $basedir/bin/hmc-restapi-test.pl "$hmc" "$server" 2>>$host_cfg_log`;
  if ( $testresult ne "" ) {
    result( 0, $testresult, $testresult );
  }
  else {
    result( 1, "API SRV OK : $server" );
  }
}

# return empty string if file not exists || version number
elsif ( $PAR{cmd} eq "gethmcversion" ) {
  print "Content-type: application/json\n\n";
  my $hmcversion;
  my $hmc = $PAR{hmc};
  if ( $hmc ne "" ) {
    my $verfile = "$basedir/tmp/HMC-version-$hmc.txt";
    if ( -e $verfile && -f _ && -r _ ) {
      if ( open( my $fh, '<', $verfile ) ) {
        my $row = <$fh>;
        chomp $row;
        $hmcversion = $row;
        close($fh);
      }
    }
  }
  my %res = ( hmcversion => $hmcversion );
  print encode_json( \%res );
}

elsif ( $PAR{cmd} eq "cmc_configuration" ) {
  print "Content-type: application/json\n\n";
  my $hmcversion;

  # collect UVMIDs of HMCs under console
  # for each pair up UVMID with host alias from config

  my $msg = " Not implemented.";
  my %res = ("info" => $msg, "success" => 1);
  print encode_json( \%res );
}

close($host_cfg_log_fh);

sub cronTest {
  my $platform = shift;
  my $pidfile  = "$basedir/tmp/$platforms{$platform}{pid}";
  if ( -e $pidfile && -f _ && -r _ ) {
    my $age = ( -M $pidfile ) * 86400;
    if ( $age > 7200 ) {    # if file modify time > 2 hours
      if ( $platform eq "common" ) {
        if ( !$ENV{VI_IMAGE} ) {
          return "<div><p style='font-style: italic'><span style='color: red'>Error:</span> Main cron job (load.sh) not running, please check it out!\nAdd this line into into LPAR2RRD crontab:</p><pre>0 * * * *  $basedir/load.sh > $basedir/load.out 2>&1</pre></div>";
        }
        else {
          return "";
        }
      }
      else {
        return "<div><p style='font-style: italic'><span style='color: red'>Error:</span> Cron job not running, please check it out!</p></div>";
      }
    }
    else {
      return "";
    }
  }
  else {
    if ( $platform eq "common" ) {
      if ( !$ENV{VI_IMAGE} ) {
        return "<div><p style='font-style: italic'><span style='color: red'>Error:</span> Main cron job (load.sh) not found, it has to be configured! Add these lines to LPAR2RRD user crontab:<br><pre>$platforms{$platform}{croncmd}</pre></div>";
      }
      else {
        return "";
      }
    }
    else {
      if ( $platform eq "power" ) {
        return "<div><p style='font-style: italic'><span style='color: red'>Error:</span> Cron job not found, it has to be configured! <br>Note this is checked once a 20 minutes only, ignore it if you have just fixed it.<br><br>Add these lines to lpar2rrd user crontab (just if you use HMC REST API access):<br><pre>$platforms{$platform}{croncmd}</pre></div>";
      }

      #      if ( $platform eq "oracledb" && ! $ENV{ORACLE_ENABLED} ) {
      #        return "<div><p>It is not implemented yet. It is going to be released <b><href=''>soon</a></b>.</p><p><a href='https://www.lpar2rrd.com/Oracle-DB-performance-monitoring.php'>More info...</a></p>";
      #      }
      #if ( $platform eq "oraclevm" && ! $ENV{ORACLE_ENABLED} ) {
      #  return "<div><p>It is not implemented yet. It is going to be released <b><href=''>soon</a></b>.</p><p><a href='https://www.lpar2rrd.com/Oracle-VM-performance-monitoring.php'>More info...</a></p>";
      #}
      else {
        return "<div><p style='font-style: italic'><span style='color: red'>Error:</span> Cron job not found, it has to be configured! <br>Note this is checked once a 20 minutes only, ignore it if you have just fixed it.<br><br>Add these lines to lpar2rrd user crontab:<br><pre>$platforms{$platform}{croncmd}</pre></div>";
      }
    }
  }
}

sub jsonTimeToHuman {
  my $str = shift;
  $str =~ tr/TZ/ /;
  return $str;
}

sub urldecode {
  my $s = shift;
  $s =~ s/\%([A-Fa-f0-9]{2})/pack('C', hex($1))/seg;
  $s =~ s/\+/ /g;
  return $s;
}

sub encode_base64url {
  my $e = encode_base64( shift, "" );
  $e =~ s/=+\z//;
  $e =~ tr[+/][-_];
  return $e;
}

sub decode_base64url {
  my $s = shift;
  $s =~ tr[-_][+/];
  $s .= '=' while length($s) % 4;
  return decode_base64($s);
}

sub result {
  my ( $status, $msg, $log ) = @_;
  $log ||= "";

  # $status = ( $status ) ? "true" : "false";
  my %res = ( success => $status, error => $msg, log => $log );
  print STDERR strftime( "%F %H:%M:%S", localtime(time) ) . "$status:$msg - $log\n\n";
  print $host_cfg_log_fh strftime( "%F %H:%M:%S", localtime(time) ) . "$status:$msg - $log\n\n";
  print encode_json( \%res );
}

sub get_lpar2rrd_owner {
  my $check_file   = "$ENV{INPUTDIR}/bin/lpar2rrd.pl";
  my $install_user = "";
  my $err_text     = "";
  if ( -f "$check_file" ) {
    my $uname = `uname -s`;
    chop $uname;
    my $file_list = "";
    if ( $uname eq "SunOS" ) {
      $file_list = `ls -l "$check_file" 2>/dev/null`;
    }
    else {
      $file_list = `ls -lX "$check_file" 2>/dev/null`;
    }
    chop $file_list;
    ( undef, undef, $install_user ) = split( " ", $file_list );
    return $install_user;
  }
  return "";
}

sub connTestProxy {
  my $host = shift;
  my $port = shift;
  my $proxy = shift;

  my %result;

  use IO::Socket::INET;
  my $sock;

  eval {
    local $SIG{ALRM} = sub { die 'Timed Out'; };
    alarm 10;
    $sock = new IO::Socket::INET(
      PeerAddr => $host,
      PeerPort => $port,
      Proto    => 'tcp',
      Timeout  => 3
    );

    alarm 0;
  };
  alarm 0;    # race condition protection
  if ( $@ && $@ =~ /Timed Out/ ) {
    $result{status} = 0;
    $result{msg}    = "TCP connection to $host:$port timed out after 10 seconds!";
    return %result;
  }
  elsif ($sock) {
    $result{status} = 1;
    $result{msg}    = "TCP connection to $host:$port is <span class='noerr'>OK</span>.";
    return %result;
  }
  else {
    $result{status} = 0;
    $result{msg}    = "TCP connection to $host:$port has failed! Open it on the firewall.";
    return %result;
  }
}

sub connTest {
  my $host = shift;
  my $port = shift;
  my %result;

  use IO::Socket::INET;
  my $sock;

  eval {
    local $SIG{ALRM} = sub { die 'Timed Out'; };
    alarm 10;
    $sock = new IO::Socket::INET(
      PeerAddr => $host,
      PeerPort => $port,
      Proto    => 'tcp',
      Timeout  => 3
    );

    alarm 0;
  };
  alarm 0;    # race condition protection
  if ( $@ && $@ =~ /Timed Out/ ) {
    $result{status} = 0;
    $result{msg}    = "TCP connection to $host:$port timed out after 10 seconds!";
    return %result;
  }
  elsif ($sock) {
    $result{status} = 1;
    $result{msg}    = "TCP connection to $host:$port is <span class='noerr'>OK</span>.";
    return %result;
  }
  else {
    $result{status} = 0;
    $result{msg}    = "TCP connection to $host:$port has failed! Open it on the firewall.";
    return %result;
  }
}

sub cfgpage {
  my $platform = shift;
    print <<_MARKER_;
<div style='text-align: center'>
  <div style='display: inline-block'>
    <div style='float: left; margin-right: 10px; outline: none' class="cggrpnames">
        <table id="hosttable" class="cfgtree" data-platform="$platform">
          <thead>
          <tr>
            <th>Alias <button class="addnewhost">New</button></th>
            <th>Edit</th>
            <th class="hideme">Clone</th>
            <th>Delete</th>
            <th>Hostname / IP</th>
            <th>Connection Test</th>
          </tr>
          </thead>
          <tbody>
          </tbody>
        </table>
      </div>
      <br style="clear: both">
      <div id="cfgcomment" style="max-width: 80em; font-size: smaller; text-align: left;">
_MARKER_
    print cronTest($platform);
    print cronTest("common");

    if ( -e "$webdir/hostcfg-$platform.html" && -f _ && -r _ ) {
      print file_read("$webdir/hostcfg-$platform.html");
    }
    print "</div><br style='clear: both'>";
    use XoruxEdition;
    if ( length( premium() ) != 6 ) {
    print <<_LINKS_;
    <div class="free-links">
    <p><b>Use the following links to:</b></p>
    <ul>
    <li>provide us with <b>Feedback</b>: <a target="_blank" href="https://lpar2rrd.com/contact.php#feedback">lpar2rrd.com/contact.php#feedback</a></li>
    <li>get a <b>Quote</b>: <a target="_blank" href="https://lpar2rrd.com/quote-form.php">lpar2rrd.com/quote-form.php</a></li>
    <li>learn more about the <b>Enterprise Edition</b>: <a target="_blank" href="https://lpar2rrd.com/support.php">lpar2rrd.com/support.php</a></li>
    <li>request an <b>Online session</b>: <a target="_blank" href="https://lpar2rrd.com/live_form.php">lpar2rrd.com/live_form.php</a></li>
    </ul>
    </div>
_LINKS_
    }
    print <<_MARKER_;
  </div>
</div>

_MARKER_
  }

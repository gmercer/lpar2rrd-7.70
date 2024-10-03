use strict;
use warnings;
use LoadDataModuleVMWare;
use File::Copy;
use HostCfg;
use POSIX ":sys_wait_h";

# set unbuffered stdout
$| = 1;

# my $version = "$ENV{version}";
# my $webdir  = $ENV{WEBDIR};
# my $bindir  = $ENV{BINDIR};
my $basedir = $ENV{INPUTDIR};
my $tmpdir  = "$basedir/tmp";
if ( defined $ENV{TMPDIR_LPAR} ) {
  $tmpdir = $ENV{TMPDIR_LPAR};
}

# my $DEBUG                   = $ENV{DEBUG};
# my $wrkdir                  = "$basedir/data";
my $vmware_data_dir = "$tmpdir/VMWARE/";
my @returns;    # filehandles for forking

$SIG{'ALRM'} = "handler";
alarm(10500);

### proxy part
# check if exist proxy files in tmp/
# if yes -> mv & gunzig & untar files to tmp/VMWARE
if ( !-d $tmpdir ) {
  main::error( " does not exist $tmpdir : " . __FILE__ . ":" . __LINE__ ) && return 0;
}
my $dh_tmp;
if ( !opendir( $dh_tmp, $tmpdir ) ) {
  print " Can't open $tmpdir : $! " . __FILE__ . ":" . __LINE__ . "\n";
  return 0;
}
my @per_files = grep /^\d\d\d\d\d\d\d\d\d\d_.*.txt.tar.gz$/, readdir $dh_tmp;
if ( ( @per_files && ( scalar @per_files > 0 ) ) || -f "$tmpdir/vmware_proxy_ball.tar.gz" ) {
  if ( !-d $vmware_data_dir ) {
    if ( !mkdir $vmware_data_dir ) {
      mkdir( "$vmware_data_dir", 0755 ) || main::error( " Cannot mkdir $vmware_data_dir: $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    }
  }
  if ( -f "$tmpdir/vmware_proxy_ball.tar.gz" ) {
    my $result = `gunzip "$tmpdir/vmware_proxy_ball.tar.gz" 2>&1`;
    if ( $result ne "" ) {
      main::error( " Can't gunzip $tmpdir/vmware_proxy_ball.tar.gz : ,$result, " . __FILE__ . ":" . __LINE__ );
      if ( $result =~ /exists/ ) {
        unlink "$tmpdir/vmware_proxy_ball.tar";
        $result = `gunzip "$tmpdir/vmware_proxy_ball.tar.gz" 2>&1`;
        if ( $result ne "" ) {
          main::error( " Can't gunzip $tmpdir/vmware_proxy_ball.tar.gz : ,$result, " . __FILE__ . ":" . __LINE__ ) && return 0;
        }
      }
    }
    $result = `tar -xf "$tmpdir/vmware_proxy_ball.tar" -C $basedir 2>&1`;
    if ( $result ne "" ) {
      main::error( " Can't untar $tmpdir/vmware_proxy_ball.tar to $vmware_data_dir : ,$result, " . __FILE__ . ":" . __LINE__ );
    }
    else {
      unlink "$tmpdir/vmware_proxy_ball.tar";
    }
  }
  while ( my $per_file = shift @per_files ) {
    if ( !move "$tmpdir/$per_file", "$vmware_data_dir/$per_file" ) {
      main::error( " Can't move $tmpdir/$per_file to $vmware_data_dir/$per_file : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
    }
    my $result = `gunzip "$vmware_data_dir/$per_file" 2>&1`;
    if ( $result ne "" ) {
      main::error( " Can't gunzip $vmware_data_dir/$per_file : ,$result, " . __FILE__ . ":" . __LINE__ ) && return 0;
    }
    my $per_file_tar = $per_file;
    $per_file_tar =~ s/\.gz$//;

    # print "142 untar $vmware_data_dir/$per_file_tar\n";
    $result = `cd $vmware_data_dir; tar -xvf "$per_file_tar" >/dev/null`;
    if ( $result ne "" ) {
      main::error( " Can't untar $vmware_data_dir/$per_file_tar : ,$result, " . __FILE__ . ":" . __LINE__ ) && return 0;
    }
    else {
      unlink "$vmware_data_dir/$per_file_tar";

      # and immediatelly push all perf data to rrd files
      LoadDataModuleVMWare::push_data_from_timed_files(".*");
    }
  }
}
### proxy part end

my $config        = HostCfg::getHostConnections("VMware");
my @conf_arr      = split " ", $config;
my $vcenter_count = 1;
my @pid           = ();

foreach (@conf_arr) {
  my $definition = $_;

  # print "105 working for definition $definition\n";
  # Hosting|10.22.11.10|lpar2rrd@xorux.local
  ( undef, my $host_name, undef ) = split /\|/, $definition;

  # forking vcenters
  local *FH;
  $pid[$vcenter_count] = open( FH, "-|" );    # this is fork

  if ( not defined $pid[$vcenter_count] ) {
    error("$host_name vcenters could not fork");
    print "$host_name vcenters could not fork\n";
  }
  elsif ( $pid[$vcenter_count] == 0 ) {
    print "Fork vcenter   : $host_name : $vcenter_count child pid $$\n";

    LoadDataModuleVMWare::push_data_from_timed_files($host_name);

    print "Fork vcentr fin: $host_name : $vcenter_count child pid $$\n";
    exit(0);
  }
  print "Parent continue: vcenter $host_name: $pid[$vcenter_count ] parent pid $$\n";
  push @returns, *FH;
  $vcenter_count++;
}

# this operation should clear all finished forks 'defunct'
print_fork_output();

alarm(0);

sub handler {

  kill -15, $$;    # clean up

  error( "Timeout OUT for LoadDataModuleVMWare::push_data_from_timed_files " . __FILE__ . ":" . __LINE__ );
  exit;
}

# error handling
sub error {
  my $text     = shift;
  my $act_time = localtime();
  chomp($text);

  # print "ERROR          : $text : $!\n";
  print STDERR "$act_time: $text : $!\n";

  return 1;
}

sub print_fork_output {
  return if ( scalar @returns == 0 );

  # print output of all forks
  foreach my $fh (@returns) {
    while (<$fh>) {
      print $_;
    }
    close($fh);
  }
      # @returns = (); # clear the filehandle list

  waitpid( -1, WNOHANG );    # take stats of forks and remove 'defunct' processes
  print "All chld finish: push perf data to rrd\n";
}


use 5.008_008;

use strict;
use warnings;

use RRDp;
use Data::Dumper;
use File::Copy;
use Xorux_lib qw(error read_json write_json);
use POSIX ":sys_wait_h";
use SQLServerLoadDataModule;
use SQLServerDataWrapper;

defined $ENV{INPUTDIR} || warn("INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg ") && exit 1;
my $sh_alias;

if (@ARGV) {
  $sh_alias = $ARGV[0];
}

if ( !$sh_alias ) {
  warn "SQLServer couldn't retrieve alias" & exit 1;
}

my $alias       = $sh_alias;
my $inputdir    = $ENV{INPUTDIR};
my $rrdtool     = $ENV{RRDTOOL};
my $tmpdir      = "$inputdir/tmp";
my $home_dir    = "$inputdir/data/SQLServer";
my $act_dir     = "$home_dir/$alias";
my $iostats_dir = "$home_dir/$alias/iostats";

unless ( -d $home_dir ) {
  mkdir( $home_dir, 0755 ) || warn("Cannot mkdir $home_dir: $!") && exit 1;
}
unless ( -d $act_dir ) {
  mkdir( $act_dir, 0755 ) || warn("Cannot mkdir $act_dir: $!") && exit 1;
}
unless ( -d $iostats_dir ) {
  mkdir( $iostats_dir, 0755 ) || warn("cannot mkdir $iostats_dir: $!") && exit 1;
}

unless ( -d $iostats_dir ) {
  print "sqlserver-json2rrd.pl : no iostats dir, skip\n";
  exit 1;
}

my $act_time = time;

load_perf_data();

exit 0;

sub load_perf_data {
  my @pids;
  my $pid;

  my $rrdtool_version = 'Unknown';
  $_ = `$rrdtool`;
  if (/^RRDtool ([1-9]*\.[0-9]*(\.[0-9]*)?)/) {
    $rrdtool_version = $1;
  }
  print "RRDp    version   : $RRDp::VERSION\n";
  print "RRDtool version   : $rrdtool_version\n";
  my @files;
  opendir( DH, $iostats_dir ) || warn("Could not open '$iostats_dir' for reading '$!'\n") && exit;

  #@files = sort( grep /.*sqlserver_.*\.json/, readdir DH );
  @files = sort( grep /sqlserver_.*\.json/, readdir DH );

  #  print Dumper \@files;
  closedir(DH);

  my $perf_act = $files[$#files];
  load_perf_file($perf_act);
  if ( -f "$iostats_dir/$perf_act" ) {
    unlink "$iostats_dir/$perf_act";
  }

  return 1;
}

sub load_perf_file {
  my $file = shift;
  my ( $can_read, $ref );

  # read perf file
  if ( -f "$iostats_dir/$file" ) {
    ( $can_read, $ref ) = Xorux_lib::read_json("$iostats_dir/$file");
    backup_file($file);
  }
  else {
    warn("Perf file for $sh_alias doesn't exist ") && exit 1;
  }

  unless ($can_read) {
    print "sqlserver-json2rrd.pl : file $file cannot be loaded\n";
    warn("Perf file $file for $sh_alias cannot be loaded ");
    return 0;
  }

  print Dumper \$ref;
  print "sqlserver-json2rrd.pl : processing file $file\n";
  my $data = work_counters($ref);
  if ( $data and $data ne 0 ) {
    Xorux_lib::write_json( "$iostats_dir/sqlsrvr_perf.json-nperf", $data );
  }
  else {
    return 0;
  }

  RRDp::start "$rrdtool";

  my @folder_types = ( "Virtual", "Counters", "Wait_events", "Capacity" );

  foreach my $folder_type (@folder_types) {
    type_to_rrd( $folder_type, $data );
  }

  RRDp::end;
  return 1;
}

sub type_to_rrd {
  my $_type = shift;
  my $_data = shift;
  my $lc_type;

  $lc_type = lc($_type);
  unless ( $_data->{$lc_type} ) {
    return;
  }

  foreach my $db ( keys %{ $_data->{$lc_type} } ) {
    my $act_db   = "$home_dir/$alias/$db";
    my $type_dir = "$act_db/$_type";

    unless ( -d $act_db ) {
      mkdir( $act_db, 0755 ) || warn("Cannot mkdir $act_db: $!") && next;
    }
    unless ( -d $type_dir ) {
      mkdir( $type_dir, 0755 ) || warn("cannot mkdir $type_dir: $!") && next;
    }
    my $rrd_path = SQLServerDataWrapper::get_filepath_rrd( { type => $lc_type, uuid => $alias, id => $db, skip_acl => 1 } );
    print $rrd_path;
    data_to_rrd( $rrd_path, $_data->{_info}->{timestamp}, $lc_type, $_data->{$lc_type}->{$db}, $alias );
  }
}

sub work_counters {
  my $_data    = shift;
  my %act_perf = %{$_data};
  my %new_perf;
  my %old_perf;

  #  my %non_counters = %{SQLServerDataWrapper::get_non_counters()};
  my $perf_l = "$iostats_dir/sqlsrvr_perf_last.json";
  my ( $p_can_read, $p_ref );

  if ( -e $perf_l ) {
    my $modtime  = ( stat($perf_l) )[9];
    my $timediff = time - $modtime;
    if ( $timediff >= 420 ) {
      unlink($perf_l);
      Xorux_lib::write_json( "$perf_l", $_data );
      return 0;
    }
    ( $p_can_read, $p_ref ) = Xorux_lib::read_json($perf_l);
  }
  else {
    Xorux_lib::write_json( "$perf_l", $_data );
    return 0;
  }
  if ($p_can_read) {
    %old_perf = %{$p_ref};
    my @dbs;
    my %raw_metrics = (
      "Database pages"              => "1",
      "Extension allocated pages"   => "1",
      "Extension free pages"        => "1",
      "Page life expectancy"        => "1",
      "Target pages"                => "1",
      "Transactions"                => "1",
      "User Connections"            => "1",
      "Free Memory (KB)"            => "1",
      "Free Memory (KB)"            => "1",
      "Reserved Server Memory (KB)" => "1",
      "Target Server Memory (KB)"   => "1",
      "Total Server Memory (KB)"    => "1",
      "Active Transactions"         => "1"

    );
    for my $type ( keys %act_perf ) {
      if ( $type ne "_info" ) {
        for my $db ( keys %{ $act_perf{$type} } ) {
          for my $metric ( keys %{ $act_perf{$type}{$db} } ) {

            #            if(!$non_counters{$metric}){
            next if ( !defined $old_perf{$type}{$db}{$metric}
              or $old_perf{$type}{$db}{$metric} eq "0"
              or $old_perf{$type}{$db}{$metric} == 0
              or $act_perf{$type}{$db}{$metric} < $old_perf{$type}{$db}{$metric} );
            if ( $type eq "wait_events" ) {
              $new_perf{$type}{$db}{$metric} = ( $act_perf{$type}{$db}{$metric} - $old_perf{$type}{$db}{$metric} );
            }
            else {
              $new_perf{$type}{$db}{$metric} = ( $act_perf{$type}{$db}{$metric} - $old_perf{$type}{$db}{$metric} ) / 300;
            }

            if ( $raw_metrics{$metric} or $type eq "capacity" ) {    #or $type eq "wait_events"){
              if ( $metric eq 'Free Memory (KB)'
                or $metric eq 'Reserved Server Memory (KB)'
                or $metric eq 'Target Server Memory (KB)'
                or $metric eq 'Total Server Memory (KB)' )
              {
                $new_perf{$type}{$db}{$metric} = $act_perf{$type}{$db}{$metric} / 1000;
              }
              else {
                $new_perf{$type}{$db}{$metric} = $act_perf{$type}{$db}{$metric};
              }
            }

            #            }else{
            #              $new_perf{$type}{$db}{$metric} = $act_perf{$type}{$db}{$metric};
            #            }
          }
          my %ratios = (
            "Cache Hit Ratio"     => "Cache Hit Ratio Base",
            "Log Cache Hit Ratio" => "Log Cache Hit Ratio Base",
          );
          for my $r_type ( keys %ratios ) {
            if ( $new_perf{$type}{$db}{$r_type} and $new_perf{$type}{$db}{ $ratios{$r_type} } ) {
              $new_perf{$type}{$db}{$r_type} = $new_perf{$type}{$db}{$r_type} / $new_perf{$type}{$db}{ $ratios{$r_type} };
              $new_perf{$type}{$db}{$r_type} *= 100;
            }
          }
          push( @dbs, $db );
        }
      }
    }

    $new_perf{_info} = $act_perf{_info};

    #    $new_perf{_locks} = $act_perf{_locks};
    #    $new_perf{_sessions} = $act_perf{_sessions};
    #    $new_perf{_wait_event} = $act_perf{_wait_event};
    #    $new_perf{_event} = $act_perf{_event};
    #    $new_perf{_vacuum} = $act_perf{_vacuum};
    Xorux_lib::write_json( $perf_l, \%act_perf );
    return \%new_perf;
  }
  else {
    Xorux_lib::write_json( $perf_l, \%act_perf );
    return 0;
  }
}

sub data_to_rrd {
  my $_rrd_path  = shift;
  my $_timestamp = shift;
  my $_type_ns   = shift;
  my $_data      = shift;
  my $_alias     = shift;

  unless ( -f $_rrd_path ) {
    SQLServerLoadDataModule::create_rrd( $_rrd_path, $act_time, $_type_ns );
  }
  print Dumper \$_data;
  SQLServerLoadDataModule::update_rrd( $_rrd_path, $_timestamp, $_type_ns, $_data, $_alias );

}

sub backup_file {

  # expects file name for the file, that's supposed to be moved from iostats_dir, with file
  # name "hostname_datetime.json" to tmpdir
  my $src_file = shift;
  my $source   = "$iostats_dir/$src_file";
  $src_file =~ s/\.json//;
  my $target = "$tmpdir/sqlserverperf\_last1_$alias.json";
  move( $source, $target ) or warn("Cannot backup data $source: $!");

  return 1;
}    ## sub backup_file


use strict;
use warnings;

use JSON;
use Data::Dumper;
use Date::Parse;

use Xorux_lib qw(error read_json write_json file_time_diff);
use HostCfg;
use File::Copy;
use SQLServerDataWrapper;
use Db2DataWrapper;

defined $ENV{INPUTDIR} || warn("INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ") && exit 1;

my $sh_out = "";
if (@ARGV) {
  $sh_out = $ARGV[0];
}

my @sh_arr   = split( /,/, $sh_out );
my $sh_alias = $sh_arr[0];

if ( !$sh_alias ) {
  warn("No SQLServer host retrieved from params.") && exit 1;
}

my %creds         = %{ HostCfg::getHostConnections("SQLServer") };
my $alias         = $sh_alias;
my $upgrade       = defined $ENV{UPGRADE} ? $ENV{UPGRADE} : 0;
my $version       = $ENV{version};
my $inputdir      = $ENV{INPUTDIR};
my $home_dir      = "$inputdir/data/SQLServer";
my $conf_dir      = "$home_dir/$alias/Configuration";
my $generate_time = localtime();
my $total_alias;

my %headers = (
  'main' => [
    "host_platform",
    "host_release",
    "host_distribution",
    "physical_memory",
    "virtual_memory",
    "remote access",
    "remote data archive",
    "max_workers_count",
    "softnuma_configuration",
    "socket_count",
    "cpu_count",
    "numa_node_count",
    "cores_per_socket",
    "hyperthread_ratio",
    "max degree of parallelism"
  ],
  'datafiles2' => [
    "SchemaName",
    "TableName",
    "Type",
    "TotalSpace",
    "UsedSpace",
    "UsedPercent",
    "rows"
  ],
  'flgrps' => [
    "File Group Name",
    "DB File Name",
    "File Size",
    "File Path"
  ],

);

my %one_liners = (
  cluster => 1,
);

my %multi_liners = (
  main       => 1,
  datafiles2 => 1,
  flgrps     => 1,
);

my %fancy = (
  datafiles2 => {
    rows => {
      3 => 1,
      4 => 1,
    },
    sortby   => 4,
    headline => "TOP 50 Relations"
  },
  main => {
    rows => {
      3 => 1,
      4 => 1,
    },
    sortby   => 1,
    headline => "Main"
  },
  flgrps => {
    rows => {
      2 => 1,
    },
    sortby   => 3,
    headline => "Filegroups"
  }

);

gen_total_conf();

$alias = $sh_alias;

my ( $code, $ref );

if ( -f "$conf_dir/sqlserver_conf.json" ) {
  ( $code, $ref ) = Xorux_lib::read_json("$conf_dir/sqlserver_conf.json");
}

if ($code) {
  my $data         = $ref;
  my $run_conf     = 0;
  my $checkup_file = "$conf_dir/gen_conf_hourly";
  if ( -e $checkup_file ) {
    my $modtime  = ( stat($checkup_file) )[9];
    my $timediff = time - $modtime;
    if ( $timediff >= 3540 ) {
      $run_conf = 1;
      open my $fh, '>', $checkup_file;
      print $fh "1\n";
      close $fh;
    }
  }
  elsif ( !-e $checkup_file ) {
    $run_conf = 1;
    open my $fh, '>', $checkup_file;
    print $fh "1\n";
    close $fh;
  }
  if (1) {    #$run_conf){
    for my $header_m ( keys %multi_liners ) {
      warn $header_m;
      for my $db ( keys %{ $data->{_cluster}->{$header_m} } ) {
        my $table = gen_multirow( $data->{_cluster}->{$header_m}->{$db}, $header_m );
        create_file( $header_m, $table, SQLServerDataWrapper::get_uuid( $alias, $db ) );
      }
    }
  }
}

sub gen_multirow {
  my $arr     = shift;
  my $type    = shift;
  my $columns = "";
  my @h_arr   = @{$arr};
  my $rows    = "";

  for my $row ( 0 .. $#h_arr ) {
    my @columns;
    foreach my $header ( @{ $headers{$type} } ) {
      if ( $header eq "File Size" ) {
        push( @columns, $arr->[$row]->{$header} * 8000 );
      }
      else {
        push( @columns, $arr->[$row]->{$header} );
      }
    }
    $rows .= ${ generate_row( \@columns, $type ) };
  }
  my $table = ${ generate_table( \@{ $headers{$type} }, \$rows, $fancy{$type}{headline}, $type ) };
  return $table;
}

sub create_file {
  my $type   = shift;
  my $tables = shift;
  my $uuid   = shift;
  my $file;

  $file = SQLServerDataWrapper::get_dir( $type, $alias, $uuid );
  print $file. "\n";
  if ( $file ne "err" ) {
    open( HOSTH, '>', $file ) || Xorux_lib::error( "Couldn't open file $file $!" . __FILE__ . ":" . __LINE__ );
    print HOSTH $tables;
    print HOSTH "<br>\n";
    if ( $type ne "Health status" ) {
      print HOSTH "It is updated once an hour, last run: " . $generate_time;
    }
    else {
      print HOSTH "Last updated: " . $generate_time;
    }
    close(HOSTH);
  }
}

sub gen_total_conf {
  my $total_conf_dir = "$home_dir/_Totals/Configuration";
  my %total_arc;
  for my $_alias ( keys %creds ) {
    my $_conf_dir = "$home_dir/$_alias/Configuration";
    my ( $acode, $aref );
    if ( -f "$_conf_dir/arc.json" ) {
      ( $acode, $aref ) = Xorux_lib::read_json("$_conf_dir/arc.json");
    }
    if ($acode) {
      for my $hostname ( keys %{ $aref->{hostnames} } ) {
        $total_arc{hostnames}{$hostname} = $aref->{hostnames}->{$hostname};
      }
    }
  }

  Xorux_lib::write_json( "$total_conf_dir/arc_total.json", \%total_arc );
}

################################################################################

sub generate_row {
  my $val_ref = shift;
  my $type    = shift;
  my @values  = @{$val_ref};
  my $row     = '';
  $row .= "<tr>\n";
  my $counter = 0;

  foreach my $value (@values) {
    $value = '' unless defined $value;
    if ( defined $type and $fancy{$type}{rows}{$counter} ) {
      my $fancy_value = Db2DataWrapper::get_fancy_value($value);
      warn "$type $value $fancy_value $counter";
      $row .= "<td style=\"text-align:left; color:black; \"data-text=\"$value\" nowrap=\"\">$fancy_value</td>\n";
    }
    else {
      $row .= "<td style=\"text-align:left; color:black;\" nowrap=\"\">$value</td>\n";
    }
    $counter++;
  }
  $row .= "</tr>\n";

  return \$row;
}

sub generate_table {
  my @header   = @{ shift @_ };
  my $rows     = ${ shift @_ };
  my $headline = shift;
  my $type     = shift;
  my $acc      = "";

  if ( $rows eq '' ) {
    return \$acc;
  }

  $acc .= "<center>\n";
  if ( defined $headline ) {
    my $sortby = 1;
    if ( defined $type and $fancy{$type}{sortby} ) {
      $sortby = $fancy{$type}{sortby};
    }
    $acc .= "<br><br>$headline:<b></b>\n";
    $acc .= "<table class =\"tabconfig tablesorter tablesorter-ice tablesorter7f0583dfe15c8 hasFilter\" data-sortby=\"$sortby\">\n";
  }
  else {
    $acc .= "<br>\n";
    $acc .= "<table class =\"tabconfig tablesorter tablesorter-ice tablesorter7f0583dfe15c8 hasFilter\">\n";
  }

  $acc .= "<thead>\n";
  $acc .= "<tr>\n";
  if ( defined $headline and ( $headline eq "Main info" or $headline eq "Tablespace info" ) ) {
    if ( $total_alias ne "" and $headline ne "Main info" ) {
      $acc .= "<th class = \"sortable\" style=\"text-align:center; color:black;\" nowrap=\"\">LPAR2RRD Alias</th>\n";
    }
    else {
      if ( $headline eq "Tablespace info" ) {
        $acc .= "<th class = \"sortable\" aria-sort=\"descending\" style=\"text-align:center; color:black;\" nowrap=\"\"></th>\n";
      }
    }
  }
  else {
    unless ( defined $headline and $headline eq "Health status" ) {
      if ( $headline and $headline eq "Alert History" ) {
        $acc .= "<th class = \"sortable\" aria-sort=\"descending\" style=\"text-align:center; color:black;\" nowrap=\"\">INSTANCE</th>\n";
      }
      else {
        #I dunno
        #$acc .= "<th class = \"sortable\" aria-sort=\"descending\" style=\"text-align:center; color:black;\" nowrap=\"\"></th>\n";
      }
    }
  }

  foreach my $column (@header) {
    $column =~ s/_count/s/g;
    $column =~ s/ss/s/g;
    $column =~ s/_/ /g;
    $column = ucfirst($column);
    $acc .= "<th class = \"sortable\" style=\"text-align:center; color:black;\" nowrap=\"\">$column</th>\n";
  }

  $acc .= "</tr>\n";
  $acc .= "</thead>\n";
  $acc .= "<tbody>\n";

  $acc .= $rows;
  $acc .= "</tbody>\n";
  $acc .= "</table>\n";
  $acc .= "</center>\n";

  return \$acc;
}



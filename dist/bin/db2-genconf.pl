use strict;
use warnings;

use JSON;
use Data::Dumper;
use Date::Parse;

use Xorux_lib qw(error read_json write_json file_time_diff);
use HostCfg;
use File::Copy;
use Db2DataWrapper;

defined $ENV{INPUTDIR} || warn("INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ") && exit 1;

my $sh_out = "";
if (@ARGV) {
  $sh_out = $ARGV[0];
}

my @sh_arr   = split( /,/, $sh_out );
my $sh_alias = $sh_arr[0];

if ( !$sh_alias ) {
  warn("No DB2 host retrieved from params.") && exit 1;
}

my %creds         = %{ HostCfg::getHostConnections("DB2") };
my $alias         = $sh_alias;
my $upgrade       = defined $ENV{UPGRADE} ? $ENV{UPGRADE} : 0;
my $version       = $ENV{version};
my $inputdir      = $ENV{INPUTDIR};
my $home_dir      = "$inputdir/data/DB2";
my $conf_dir      = "$home_dir/$alias/Configuration";
my $generate_time = localtime();
my $total_alias;

my %headers = (
  'member' => [
    'ID',
    'HOME_HOST',
    'CUR_HOST',
    'STATE',
    'ALERT',
  ],
  'size' => [
    'Name',
    'Used',
    'Free',
    'Total',
    'Used %',
  ],
  'main' => [
    'Member',
    'Server platform',
    'Product name', 
    'Status',
    'Service level',
    'Start time',
    'Timezone',
  ]
);
my %one_liners = (
  cluster => 1,
);

my %multi_liners = (
 size   => 1,
 member => 1,
 main   => 1,
);

my %fancy = (
  size => {
    rows => {
      1 => 1,
      2 => 1,
      3 => 1,
    },
    sortby   => 2,
    headline => "Size"
  },
  member => {
    rows => {
    },
    sortby   => 1,
    headline => "Members"
  },
  main => {
    rows => {
    },
    sortby   => 1,
    headline => "Main"
  }

);

gen_total_conf();

$alias = $sh_alias;

my ( $code, $ref );

if ( -f "$conf_dir/db2_conf.json" ) {
  ( $code, $ref ) = Xorux_lib::read_json("$conf_dir/db2_conf.json");
}

if ($code) {
  my $data         = $ref;
  #my $run_conf     = 0;
  #my $checkup_file = "$conf_dir/gen_conf_hourly";
  #if ( -e $checkup_file ) {
  #  my $modtime  = ( stat($checkup_file) )[9];
  #  my $timediff = time - $modtime;
  #  if ( $timediff >= 3540 ) {
  #    $run_conf = 1;
  #    open my $fh, '>', $checkup_file;
  #    print $fh "1\n";
  #    close $fh;
  #  }
  #}
  #elsif ( !-e $checkup_file ) {
  #  $run_conf = 1;
  #  open my $fh, '>', $checkup_file;
  #  print $fh "1\n";
  #  close $fh;
  #}
  if (1){
    for my $header_m ( keys %multi_liners ) {
      print  $header_m;
      next if (!defined $data->{_cluster}->{$header_m});
      for my $db ( keys %{ $data->{_cluster}->{$header_m} } ) {
        print Dumper $data->{_cluster}->{$header_m};
        my $table = gen_multirow( $data->{_cluster}->{$header_m}, $header_m );
        create_file( $header_m, $table, Db2DataWrapper::get_uuid( $alias, $db ) );
      }
    }
  }
}

sub gen_multirow {
  my $hash    = shift;
  my $type    = shift;
  my $columns = "";

  my $rows    = "";
  my $reset   = "";
  for my $row (keys %{$hash}){
    my @h_arr     = @{$hash->{$row}};
    for my $column ( 0 .. $#h_arr ) {
      my @columns;
      foreach my $header ( @{ $headers{$type} } ) {
        push( @columns, $h_arr[$column]{$header} );
      }
      print Dumper \@columns;
      if ($row eq "2nd_header"){
        $reset .= ${ generate_row( \@columns, $type, 1 ) };
      }else{
        $rows .= ${ generate_row( \@columns, $type, 0 ) };
      }
    }
  }
  $rows = $reset . $rows;
  print $rows;
  my $table = ${ generate_table( \@{ $headers{$type} }, \$rows, $fancy{$type}{headline}, $type ) };
  return $table;
}

sub create_file {
  my $type   = shift;
  my $tables = shift;
  my $uuid   = shift;
  my $file;

  $file = Db2DataWrapper::get_dir( $type, $alias, $uuid );
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
  my $sec_hdr = shift;
  my @values  = @{$val_ref};
  my $row     = '';
  $row .= "<tr>\n";
  my $counter = 0;
  my $align = "left";
  if ($type eq "size"){
    $align = "right";
  }

  foreach my $value (@values) {
    $value = '' unless defined $value;
    if ( defined $type and $fancy{$type}{rows}{$counter} ) {
      my $fancy_value = Db2DataWrapper::get_fancy_value($value);
      warn "$type $value $fancy_value $counter";
      $row .= "<td style=\"text-align:$align; color:black; padding-right:2em; \"data-text=\"$value\" nowrap=\"\">$fancy_value</td>\n";
    }
    else {
      $row .= "<td style=\"text-align:$align; color:black;padding-right:2em\" nowrap=\"\">$value</td>\n";
    }
    $counter++;
  }
  $row .= "</tr>\n";

  if ($sec_hdr){
    $row .= "</tbody>\n<tbody>\n";
    $row =~ s/td/th/g;
  }

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


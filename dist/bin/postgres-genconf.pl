use strict;
use warnings;

use JSON;
use Data::Dumper;
use Date::Parse;

use Xorux_lib qw(error read_json write_json file_time_diff);
use HostCfg;
use File::Copy;
use PostgresDataWrapper;
use Db2DataWrapper;

defined $ENV{INPUTDIR} || warn("INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ") && exit 1;

my $sh_out = "";
if (@ARGV) {
  $sh_out = $ARGV[0];
}

my @sh_arr   = split( /,/, $sh_out );
my $sh_alias = $sh_arr[0];

if ( !$sh_alias ) {
  warn("No PostgreSQL host retrieved from params.") && exit 1;
}

my %creds         = %{ HostCfg::getHostConnections("PostgreSQL") };
my $alias         = $sh_alias;
my $upgrade       = defined $ENV{UPGRADE} ? $ENV{UPGRADE} : 0;
my $version       = $ENV{version};
my $inputdir      = $ENV{INPUTDIR};
my $home_dir      = "$inputdir/data/PostgreSQL";
my $conf_dir      = "$home_dir/$alias/Configuration";
my $generate_time = localtime();
my $total_alias;

my %headers = (
  '_main'           => [ "work_mem",    "autovacuum_work_mem",  "wal_sync_method", "shared_buffers", "wal_buffers", "max_connections", "effective_cache_size", "temp_buffers", "maintenance_work_mem", "max_wal_size", "random_page_cost", "min_wal_size" ],
  'Tablespace info' => [ "TBS size MB", "TBS allocate size MB", "TBS max size MB" ],
  '_relations'      => [ "Namespace",   "Name",                 "Type", "Size", "Pages", "Rows" ],
);

my %one_liners = (
  _main => 1,
);

my %multi_liners = (
  _relations => 1,
);

gen_total_conf();

$alias = $sh_alias;

my ( $code, $ref );

if ( -f "$conf_dir/postgres_conf.json" ) {
  ( $code, $ref ) = Xorux_lib::read_json("$conf_dir/postgres_conf.json");
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

    for my $header ( keys %one_liners ) {
      warn $header;
      my $table = gen_info( $data->{_cluster}->{$header}, $header );
      create_file( $header, $table );
    }
    for my $header_m ( keys %multi_liners ) {
      warn $header_m;
      for my $db ( keys %{ $data->{_cluster}->{$header_m} } ) {
        my $table = gen_multirow( $data->{_cluster}->{$header_m}->{$db}, $header_m );
        create_file( $header_m, $table, PostgresDataWrapper::get_uuid( $alias, $db ) );
      }
    }

  }
}

sub gen_info {
  my $hsh     = shift;
  my $type    = shift;
  my $columns = "";

  my @column;
  foreach my $header ( @{ $headers{$type} } ) {
    my @help_arr = @{ $hsh->{$header} };
    for my $c_row ( 0 .. $#help_arr ) {
      push( @column, $hsh->{$header}->[$c_row]->{setting} );
    }
    $columns = generate_row( \@column, $type );
  }
  print Dumper $columns;

  my $table = ${ generate_table( \@{ $headers{$type} }, $columns, "Main", "info" ) };
  return $table;
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
      push( @columns, $arr->[$row]->{$header} );
    }
    $rows .= ${ generate_row( \@columns, $type ) };
  }
  my $table = ${ generate_table( \@{ $headers{$type} }, \$rows, "TOP 50 Relations", "relations" ) };
  return $table;
}

sub create_file {
  my $type   = shift;
  my $tables = shift;
  my $uuid   = shift;
  my $file;

  $file = PostgresDataWrapper::get_dir( $type, $alias, $uuid );
  print $file. "\n";
  if ( $file ne "err" ) {
    open( HOSTH, '>', $file ) || warn("Couldn't open file $file $!");
    print HOSTH $tables;    #, \$h_rows ) };
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
    if ( $counter == 3 and defined $type and $type eq "_relations" ) {
      my $fancy_value = Db2DataWrapper::get_fancy_value($value);
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
  my $acc      = "";

  if ( $rows eq '' ) {
    return \$acc;
  }

  $acc .= "<center>\n";
  if ( defined $headline ) {
    if ( $headline =~ /Relations/ ) {
      $acc .= "<br><br>$headline:<b></b>\n";
      $acc .= "<table class =\"tabconfig tablesorter tablesorter-ice tablesorter7f0583dfe15c8 hasFilter\" data-sortby=\"4\">\n";
    }
    else {
      $acc .= "<br><br><b>$headline:</b>\n";
      $acc .= "<table class =\"tabconfig tablesorter tablesorter-ice tablesorter7f0583dfe15c8 hasFilter\">\n";
    }
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
        #$acc .= "<th class = \"sortable\" aria-sort=\"descending\" style=\"text-align:center; color:black;\" nowrap=\"\"></th>\n";
      }
    }
  }

  #  if(defined $headline and $headline eq "Tablespace info"){
  #    if($total_alias ne ""){
  #      $acc .= "<th class = \"sortable\" style=\"text-align:center; color:black;\" nowrap=\"\">LPAR2RRD Alias</th>\n";
  #    }else{
  #      $acc .= "<th class = \"sortable\" aria-sort=\"descending\" style=\"text-align:center; color:black;\" nowrap=\"\"></th>\n";
  #    }
  #  }
  foreach my $column (@header) {
    $acc .= "<th class = \"sortable\" style=\"text-align:center; color:black;\" nowrap=\"\">$column</th>\n";
  }
  if ( defined $headline and $headline eq "Tablespace info" ) {
    $acc .= "<th class = \"sortable\" style=\"text-align:center; color:black;\" nowrap=\"\">Used %</th>\n";
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


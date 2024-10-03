use strict;
use warnings;

use Data::Dumper;
use Xorux_lib qw(error read_json write_json);
use DBI;
use HostCfg;
use PostgresDataWrapper;

my $sh_alias;

if (@ARGV) {
  $sh_alias = $ARGV[0];
}

if ( !$sh_alias ) {
  warn "PostgreSQL couldn't retrieve alias" && exit 1;
}

my $alias          = "$sh_alias";
my $inputdir       = $ENV{INPUTDIR};
my $home_dir       = "$inputdir/data/PostgreSQL";
my $act_dir        = "$home_dir/$alias";
my $iostats_dir    = "$act_dir/iostats";
my $conf_dir       = "$act_dir/Configuration";
my $hs_dir         = "$ENV{INPUTDIR}/tmp/health_status_summary";
my $hs_dir_psql    = "$hs_dir/PostgreSQL";
my $total_dir      = "$home_dir/_Totals";
my $total_conf_dir = "$total_dir/Configuration";
my %creds          = %{ HostCfg::getHostConnections("PostgreSQL") };
my $db_name        = $creds{$alias}{instance};
my $port           = $creds{$alias}{port};
my $username       = $creds{$alias}{username};
my $password       = $creds{$alias}{password};
my $ip             = $creds{$alias}{host};
my $use_whitelist  = $creds{$alias}{use_whitelist};

#warn Dumper \%creds;
my %whitelisted;

#warn $use_whitelist;
if ($use_whitelist) {
  if ( defined $creds{$alias}{dbs}[0] ) {
    foreach my $wl_db ( @{ $creds{$alias}{dbs} } ) {
      $whitelisted{$wl_db} = 1;
    }
  }
}

#warn Dumper \%whitelisted;

my @health_status;
my %db_ids;
my %arc;
$arc{hostnames}{ $creds{$alias}{uuid} }{alias} = $alias;

unless ( -d $home_dir ) {
  mkdir( $home_dir, 0755 ) || warn("Cannot mkdir $home_dir: $!") && exit 1;
}
unless ( -d $act_dir ) {
  mkdir( $act_dir, 0755 ) || warn("Cannot mkdir $act_dir: $!") && exit 1;
}
unless ( -d $iostats_dir ) {
  mkdir( $iostats_dir, 0755 ) || warn("Cannot mkdir $iostats_dir: $!") && exit 1;
}
unless ( -d $hs_dir ) {
  mkdir( $hs_dir, 0755 ) || warn("Cannot mkdir $hs_dir: $!") && exit 1;
}
unless ( -d $hs_dir_psql ) {
  mkdir( $hs_dir_psql, 0755 ) || warn("Cannot mkdir $hs_dir_psql: $!") && exit 1;
}
unless ( -d $conf_dir ) {
  mkdir( $conf_dir, 0755 ) || warn("Cannot mkdir $conf_dir: $!") && exit 1;
}
unless ( -d $total_dir ) {
  mkdir( $total_dir, 0755 ) || warn("Cannot mkdir $total_dir: $!") && exit 1;
}
unless ( -d $total_conf_dir ) {
  mkdir( $total_conf_dir, 0755 ) || warn("Cannot mkdir $total_conf_dir: $!") && exit 1;
}

my %query = (
  "_dbs"        => "SELECT datid, datname, blks_read, blks_hit, tup_returned, tup_fetched, tup_inserted, tup_updated, tup_deleted, xact_commit, xact_rollback, deadlocks, temp_files,temp_bytes, pg_database_size(datname) as \"locks\" FROM pg_stat_database;",
  "_cluster"    => "SELECT buffers_backend, buffers_clean, buffers_checkpoint, checkpoints_req, checkpoints_timed FROM pg_stat_bgwriter;",
  "_main"       => "show all;",
  "_locks"      => "SELECT database,locktype,granted FROM pg_locks;",
  "_sessions"   => "SELECT datid, datname, usename, state FROM pg_stat_activity WHERE state != 'undefined';",
  "_wait_event" => "SELECT datid, datname, wait_event_type, wait_event FROM pg_stat_activity WHERE wait_event_type != 'undefined' AND wait_event != 'undefined';",

  #  "_vacuum"     => "SELECT datid, datname, phase FROM pg_stat_progress_vacuum WHERE phase != 'undefined';",
  "_relations" => "SELECT nspname AS \"Namespace\", relname AS \"Name\", relkind AS \"Type\",
                           pg_relation_size(C.oid) AS \"Size\", relpages AS \"Pages\",reltuples AS \"Rows\"
                    FROM pg_class C
                    LEFT JOIN pg_namespace N ON (N.oid = C.relnamespace)
                    WHERE nspname NOT IN ('pg_catalog', 'information_schema')
                    ORDER BY pg_relation_size(C.oid) DESC
                    LIMIT 50;"
);

#SELECT spcname as "Tablespace", pg_size_pretty(pg_tablespace_size(spcname)) as "Volume", spclocation FROM pg_tablespace;
#
#SELECT EXTRACT(epoch FROM NOW());

my %conf_sa = (
  shared_buffers       => "1",
  work_mem             => "1",
  max_connections      => "1",
  temp_buffers         => "1",
  maintenance_work_mem => "1",
  autovacuum_work_mem  => "1",
  wal_buffers          => "1",
  effective_cache_size => "1",
  random_page_cost     => "1",
  min_wal_size         => "1",
  max_wal_size         => "1",
  wal_sync_method      => "1",
  wal_buffers          => "1",
);

my %rel_types = (
  r => "ordinary table",
  i => "index",
  S => "sequence",
  v => "view",
  m => "materialized view",
  c => "composite type",
  t => "TOAST table",
  f => "foreign table",
);

my $time = time;

my @perf_types = ( "_dbs", "_cluster", "_locks", "_sessions", "_wait_event" );

my $pre_perf = get_data( "PERF", $db_name, $ip, $port, $username, $password, "skip" );

my $act_perf = make_perf($pre_perf);
Xorux_lib::write_json( "$iostats_dir/postgres_perf.json", $act_perf );
Xorux_lib::write_json( "$conf_dir/arc.json",              \%arc );

my $db_longnames = rrd_check();
my $current_full_db;
my @pre_conf;
my $g_main = 0;
for my $db ( keys %{$db_longnames} ) {
  $current_full_db = $db;
  my @db_parts = split( "-", $db );
    pop(@db_parts);
    my $alm_full = join("-",@db_parts);
  next if ( !( defined $db_parts[0] ) or $db_parts[0] eq "template0" or $db_parts[0] eq "shrdrltn" );
  if ( $g_main == 0 ) {
    get_data( "CONF+", $alm_full, $ip, $port, $username, $password,undef, $alm_full );
    $g_main = 1;
  }
  else {
    get_data( "CONF", $alm_full, $ip, $port, $username, $password,undef, $alm_full );
  }
}

generate_hsfiles();
my $act_conf = make_conf( \@pre_conf );
Xorux_lib::write_json( "$conf_dir/postgres_conf.json", $act_conf );

sub get_data {
  my $type      = shift;
  my $_db_name  = shift;
  my $_ip       = shift;
  my $_port     = shift;
  my $_username = shift;
  my $_password = shift;
  my $skip      = shift;
  my $current_full_db = shift;
  my $result;
  my $dbh = DBI->connect( "DBI:Pg:dbname=$_db_name;host=$_ip;port=$_port", "$_username", "$_password", { PrintError => 0 } );

  my $time_is_now = time;
  my $err         = 0;
  $err = DBI->errstr;
  if ( !( defined $skip ) ) {
    if ($err) {
      my @row;
      $row[0] = "PostgreSQL";
      $row[1] = "$alias";
      $row[2] = "$current_full_db";
      $row[3] = "NOT_OK";
      $row[4] = "$time_is_now";
      $row[5] = $err;
      push( @health_status, \@row );
    }
    else {
      my @row;
      $row[0] = "PostgreSQL";
      $row[1] = "$alias";
      $row[2] = "$current_full_db";
      $row[3] = "OK";
      $row[4] = "$time_is_now";
      push( @health_status, \@row );
    }
  }

  if ( !( defined $dbh ) ) {
    if ( defined $skip ) {
      warn $err;
    }
    return "empty";
  }

  if ( $type eq "PERF" ) {
    my @pre_perf;

    foreach my $_type (@perf_types) {
      if ( $_type and $query{$_type} ) {
        my $array = get_query_result( $dbh, $_type );
        my %temp_hash;
        $temp_hash{type}    = $_type;
        $temp_hash{db_name} = $_db_name;
        $temp_hash{data}    = $array;
        push( @pre_perf, \%temp_hash );
      }
    }
    return \@pre_perf;
  }
  elsif ( $type =~ /CONF/ ) {
    if ( $type eq "CONF+" ) {
      my $arr = get_query_result( $dbh, "_main" );
      my %temp_hsh;
      $temp_hsh{type}    = "_main";
      $temp_hsh{data}    = $arr;
      $temp_hsh{db_name} = $_db_name;
      push( @pre_conf, \%temp_hsh );
    }
    my $array = get_query_result( $dbh, "_relations" );
    my %temp_hash;
    $temp_hash{type}    = "_relations";
    $temp_hash{data}    = $array;
    $temp_hash{db_name} = $current_full_db;
    
    push( @pre_conf, \%temp_hash );
  }

  # clean up
  $dbh->disconnect();

  return "empty";
}

sub get_query_result {
  my $_dbh  = shift;
  my $_type = shift;
  my @array;
  my $sth = $_dbh->prepare( $query{$_type} );

  #$sth = $dbh->prepare("show all;");
  $sth->execute();

  if ( $_type eq "_main" ) {
    while ( my $ref = $sth->fetchrow_hashref() ) {
      if ( $conf_sa{ $ref->{name} } ) {
        push( @array, $ref );
      }
    }
  }
  else {
    while ( my $ref = $sth->fetchrow_hashref() ) {
      push( @array, $ref );
    }
  }

  return \@array;
}

sub make_conf {
  my $rows    = shift;
  my @r_array = @{$rows};

  my %conf;
  foreach my $row_type (@r_array) {
    if ( $row_type->{type} eq "_main" ) {
      foreach my $row ( @{ $row_type->{data} } ) {
        my %hash_row = %{$row};
        $conf{_cluster}{_main}{ $row->{name} }[0]{setting} = $row->{setting};
      }
    }
    elsif ( $row_type->{type} eq "_relations" ) {
      my $counter = 0;
      foreach my $row ( @{ $row_type->{data} } ) {
        my %hash_row = %{$row};
        $hash_row{Type} = $rel_types{ $hash_row{Type} };

        #$hash_row{Size} = to_gib($hash_row{Size});
        $conf{_cluster}{_relations}{ $row_type->{db_name} }[$counter] = \%hash_row;
        $counter++;
      }
    }
  }
  $conf{_info}{timestamp}     = time;
  $conf{_info}{readable_time} = localtime( $conf{_info}{timestamp} );
  return \%conf;
}

sub make_perf {
  my $rows    = shift;
  my @r_array = @{$rows};

  my %perf;
  foreach my $row_type (@r_array) {
    if ( $row_type->{type} eq "_dbs" ) {
      foreach my $row ( @{ $row_type->{data} } ) {
        my %hash_row = %{$row};
        my %hr_dupl  = %hash_row;
        if ( !( defined $hash_row{datname} ) ) {
          $hash_row{datname} = "shrdrltn";
        }
        delete $hr_dupl{datid};
        delete $hr_dupl{datname};
        my $accepted = 0;
        if ($use_whitelist) {
          if ( $whitelisted{ $hash_row{datname} } ) {
            $accepted = 1;
          }
        }
        else {
          $accepted = 1;
        }

        if ($accepted) {
          $hr_dupl{cursors}                                  = 0;
          $hr_dupl{locks}                                    = to_gib( $hr_dupl{locks} );
          $perf{_dbs}{"$hash_row{datname}-$hash_row{datid}"} = \%hr_dupl;
          my $uuid = PostgresDataWrapper::md5_string("$alias-$hash_row{datname}-$hash_row{datid}");
          $arc{hostnames}{ $creds{$alias}{uuid} }{_dbs}{$uuid}{label}    = $hash_row{datname};
          $arc{hostnames}{ $creds{$alias}{uuid} }{_dbs}{$uuid}{id}       = $hash_row{datid};
          $arc{hostnames}{ $creds{$alias}{uuid} }{_dbs}{$uuid}{filename} = "$hash_row{datname}-$hash_row{datid}";
          $db_ids{ $hash_row{datid} }                                    = "$hash_row{datname}-$hash_row{datid}";
        }
      }
    }
    elsif ( $row_type->{type} eq "_locks" ) {
      $perf{_locks} = rrd_check();

      foreach my $row ( @{ $row_type->{data} } ) {
        my %hash_row = %{$row};
        next if ( !( defined $hash_row{database} ) or $hash_row{database} eq "undef" );
        if ( $hash_row{granted} ) {
          next if ( !( defined $db_ids{ $hash_row{database} } ) );
          if ( exists $perf{_locks}{ $db_ids{ $hash_row{database} } }{ "h" . $hash_row{locktype} } ) {
            $perf{_locks}{ $db_ids{ $hash_row{database} } }{ "h" . $hash_row{locktype} } += 1;
          }
          else {
            $perf{_locks}{ $db_ids{ $hash_row{database} } }{ "h" . $hash_row{locktype} } = 1;
          }
        }
        else {
          next if ( !( defined $hash_row{database} ) );
          if ( exists $perf{_locks}{ $db_ids{ $hash_row{database} } }{ "a" . $hash_row{locktype} } ) {
            $perf{_locks}{ $db_ids{ $hash_row{database} } }{ "a" . $hash_row{locktype} } += 1;
          }
          else {
            $perf{_locks}{ $db_ids{ $hash_row{database} } }{ "a" . $hash_row{locktype} } = 1;
          }
        }
      }
    }
    elsif ( $row_type->{type} eq "_sessions" ) {
      $perf{_sessions} = rrd_check();

      foreach my $row ( @{ $row_type->{data} } ) {
        my %hash_row = %{$row};
        my $state    = $hash_row{state};
        next if ( !( defined $state ) );
        $state =~ s/\(//g;
        $state =~ s/\)//g;
        $state =~ s/ /_/g;
        if ( exists $perf{_sessions}{"$hash_row{datname}-$hash_row{datid}"}{$state} ) {
          $perf{_sessions}{"$hash_row{datname}-$hash_row{datid}"}{$state} += 1;
        }
        else {
          $perf{_sessions}{"$hash_row{datname}-$hash_row{datid}"}{$state} = 1;
        }
      }
    }
    elsif ( $row_type->{type} eq "_wait_event" ) {
      $perf{_wait_event} = rrd_check();
      $perf{_event}      = rrd_check();

      foreach my $row ( @{ $row_type->{data} } ) {
        my %hash_row = %{$row};
        next if ( !defined $hash_row{datname} or !defined $hash_row{datid} );
        if ( defined $hash_row{wait_event_type} ) {
          my $state = $hash_row{wait_event_type};
          if ( exists $perf{_wait_event}{"$hash_row{datname}-$hash_row{datid}"}{$state} ) {
            $perf{_wait_event}{"$hash_row{datname}-$hash_row{datid}"}{$state} += 1;
          }
          else {
            $perf{_wait_event}{"$hash_row{datname}-$hash_row{datid}"}{$state} = 1;
          }
        }
        elsif ( defined $hash_row{wait_event} ) {
          if ( exists $perf{_event}{"$hash_row{datname}-$hash_row{datid}"}{ $hash_row{wait_event} } ) {
            $perf{_event}{"$hash_row{datname}-$hash_row{datid}"}{ $hash_row{wait_event} } += 1;
          }
          else {
            $perf{_event}{"$hash_row{datname}-$hash_row{datid}"}{ $hash_row{wait_event} } = 1;
          }
        }
      }
    }

    #elsif($row_type->{type} eq "_vacuum"){
    #      $perf{_vacuum} = rrd_check();
    #
    #      foreach my $row (@{$row_type->{data}}){
    #        my %hash_row = %{$row};
    #        my $state = $hash_row{phase};
    #        if(exists $perf{_vacuum}{"$hash_row{datname}-$hash_row{datid}"}{$state}){
    #          $perf{_vacuum}{"$hash_row{datname}-$hash_row{datid}"}{$state} += 1;
    #        }else{
    #          $perf{_vacuum}{"$hash_row{datname}-$hash_row{datid}"}{$state} = 1;
    #        }
    #      }
    #    }
    elsif ( $row_type->{type} eq "_cluster" ) {
      $perf{_cluster} = $row_type->{data}->[0];
    }
  }

  $perf{_info}{timestamp}     = time;
  $perf{_info}{readable_time} = localtime( $perf{_info}{timestamp} );

  return \%perf;
}

sub table2hash {
  my $data = shift;

  $data =~ s/ //g;
  $data =~ s/\|/;;;/g;
  my @data_rows = split( "\n", $data );
  my $header    = shift @data_rows;
  shift @data_rows;
  my @header_sp = split( ";;;", $header );

  #print "$header\n\n";
  #print Dumper \@header_sp;
  #print Dumper \@data_rows;

  my @rows;
  foreach my $row (@data_rows) {
    my %hash;
    my @atoms = split( ";;;", $row );

    if ( $#atoms == $#header_sp ) {
      for ( my $i = 0; $i <= $#atoms; $i++ ) {
        $hash{ $header_sp[$i] } = $atoms[$i];
      }
      push( @rows, \%hash );
    }
  }
  return \@rows;
}

sub round {
  my $value    = shift;
  my $decimals = shift;

  return $value = sprintf( "%." . "$decimals" . "f", $value );
}

# transforms given gmtime to UTC #
sub gmtime2utc {
  my ( $sec, $min, $hour, $mday, $mon, $year, $secbool ) = @_;
  $year += 1900;
  $mon  += 1;
  $mon  = sprintf( "%02d", $mon );
  $mday = sprintf( "%02d", $mday );
  $hour = sprintf( "%02d", $hour );
  $min  = sprintf( "%02d", $min );
  if ( defined $secbool and $secbool == 1 ) {
    return "$year-$mon-$mday" . "T" . "$hour:$min:$sec" . "Z";
  }
  else {
    return "$year-$mon-$mday" . "T" . "$hour:$min:00Z";
  }
}

sub generate_hsfiles {
  foreach my $row (@health_status) {
    my @row_arr = @{$row};

    if ( $row_arr[3] eq "OK" ) {
      my $checkup_file_ok  = "$hs_dir_psql/$alias\_$row_arr[2].ok";
      my $checkup_file_nok = "$hs_dir_psql/$alias\_$row_arr[2].nok";
      if ( -f $checkup_file_nok ) {
        unlink $checkup_file_nok;
      }

      #if ($instance_names{$row_arr[2]}){
      #  $row_arr[2] = $instance_names{$row_arr[2]};
      #}
      my $joined_row = join( " : ", @row_arr );
      open my $fh, '>', $checkup_file_ok;

      print $fh $joined_row;
      close $fh;

    }
    elsif ( $row_arr[3] eq "NOT_OK" ) {
      my $checkup_file_ok  = "$hs_dir_psql/$alias\_$row_arr[2].ok";
      my $checkup_file_nok = "$hs_dir_psql/$alias\_$row_arr[2].nok";
      if ( -f $checkup_file_ok ) {
        unlink $checkup_file_ok;
      }

      if ( !-f $checkup_file_nok ) {

        #if ($instance_names{$row_arr[2]}){
        #  $row_arr[2] = $instance_names{$row_arr[2]};
        #}
        my $joined_row = join( " : ", @row_arr );
        open my $fh, '>', $checkup_file_nok;
        print $fh $joined_row;
        close $fh;
      }
    }
  }
}

sub rrd_check {
  my %_empty_dbs;
  for my $id ( keys %db_ids ) {
    $_empty_dbs{ $db_ids{$id} } = {};
  }
  return \%_empty_dbs;
}

sub filetime {
  my ( $sec, $min, $hour, $mday, $mon, $year ) = ( localtime( $time - 120 ) );
  my $utctime = gmtime2utc( $sec, $min, $hour, $mday, $mon, $year );
  $utctime = substr( $utctime, 0, -4 );
  $utctime =~ s/-//g;
  $utctime =~ s/://g;
  $utctime =~ s/T/_/g;

  return $utctime;
}

sub to_gib {
  my $value = shift;
  my $GiB   = 1073741824;
  if ( !( defined $value ) or $value eq 0 ) {
    return 0;
  }
  return sprintf( "%.1f", ( $value / $GiB ) );
}

sub to_tib {
  my $value = shift;
  my $GiB   = 1073741824;
  if ( !( defined $value ) or $value eq 0 ) {
    return 0;
  }
  return sprintf( "%.3f", ( ( $value / $GiB ) / 1024 ) );
}

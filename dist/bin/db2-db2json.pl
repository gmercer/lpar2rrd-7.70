use strict;
use warnings;

use JSON;
use Data::Dumper;

use Xorux_lib qw(error read_json);
use Db2DataWrapper;
use DatabasesWrapper;
use HostCfg;
use DBI;
require DBD::DB2::Constants;
require DBD::DB2;


my $sh_alias;

if (@ARGV) {
  $sh_alias = $ARGV[0];
}

if ( !$sh_alias ) {
  warn "DB2 couldn't retrieve alias" && exit 1;
}

my $alias          = "$sh_alias";
my $inputdir       = $ENV{INPUTDIR};
my $home_dir       = "$inputdir/data/DB2";
my $act_dir        = "$home_dir/$alias";
my $iostats_dir    = "$act_dir/iostats";
my $conf_dir       = "$act_dir/Configuration";
my $hs_dir         = "$ENV{INPUTDIR}/tmp/health_status_summary";
my $hs_dir_db2     = "$hs_dir/DB2";
my $total_dir      = "$home_dir/_Totals";
my $total_conf_dir = "$total_dir/Configuration";
my %creds          = %{ HostCfg::getHostConnections("DB2") };
my $hostname       = $creds{$alias}{host};
my $db_name        = $creds{$alias}{instance};
my $db             = $creds{$alias}{instance};
my $port           = $creds{$alias}{port};
my $user           = $creds{$alias}{username};
my $pass           = $creds{$alias}{password}; 
my $type           = "PERF";


my %arc;
$arc{hostnames}{ $creds{$alias}{uuid} }{alias} = $alias;
my $db_id = Xorux_lib::uuid_big_endian_format( Db2DataWrapper::md5_string("total-$alias") );
$arc{hostnames}{ $creds{$alias}{uuid} }{alias} = $alias;
$arc{hostnames}{ $creds{$alias}{uuid} }{label} = "Total";

my @health_status;

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
unless ( -d $hs_dir_db2 ) {
  mkdir( $hs_dir_db2, 0755 ) || warn("Cannot mkdir $hs_dir_db2: $!") && exit 1;
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
  "members" => "SELECT * FROM TABLE(MON_GET_DATABASE(-2))",
  "bp" => qq(SELECT "BP_NAME", "POOL_TEMP_XDA_P_READS", "POOL_TEMP_DATA_L_READS", "POOL_TEMP_XDA_L_READS", "POOL_INDEX_L_READS", "POOL_XDA_L_READS", "POOL_DATA_L_READS", "POOL_DATA_WRITES", "POOL_INDEX_WRITES", "POOL_XDA_WRITES", "DIRECT_WRITE_TIME", "POOL_INDEX_P_READS", "POOL_WRITE_TIME", "DIRECT_WRITES", "POOL_TEMP_INDEX_P_READS", "DIRECT_READS", "POOL_DATA_P_READS", "POOL_TEMP_DATA_P_READS", "DIRECT_READ_TIME", "POOL_XDA_P_READS", "POOL_TEMP_INDEX_L_READS", "POOL_READ_TIME" FROM TABLE(MON_GET_BUFFERPOOL('',-2));)
);

my %c_query = (
  "size" => "
      SELECT varchar(tbsp_name, 30) as tbsp_name,
        TBSP_TOTAL_PAGES * TBSP_PAGE_SIZE AS SIZE,
        TBSP_FREE_PAGES * TBSP_PAGE_SIZE AS FREE,
        (TBSP_PAGE_TOP * 1.0 / TBSP_TOTAL_PAGES) * 100 AS USED_PCT,
        TBSP_PAGE_TOP * TBSP_PAGE_SIZE AS MAXUSED
      FROM TABLE(MON_GET_TABLESPACE('',-2)) AS t 
      ORDER BY free ASC;",
#  "_bfrp" => "
#      SELECT VARCHAR(TBS.TBSP_NAME,20) AS TABLESPACE
#        ,TBS.TBSP_ID AS ID, TBS.TBSP_TYPE AS TYPE
#        ,TBS.TBSP_CONTENT_TYPE AS DATATYPE
#        ,VARCHAR(BP.BPNAME,20) AS BUFFERPOOL
#        ,TBS.TBSP_PAGE_SIZE / 1024 AS PAGE_SIZE
#        ,TBS.TBSP_TOTAL_PAGES * TBS.TBSP_PAGE_SIZE / 1024 / 1024 AS SIZE_MB
#        ,TBS.TBSP_FREE_PAGES * TBS.TBSP_PAGE_SIZE / 1024 / 1024 AS FREE_MB
#        ,TBS.TBSP_FREE_PAGES * 1.0 / TBS.TBSP_TOTAL_PAGES * 100  AS FREE_PCT
#        ,TBS.TBSP_PAGE_TOP * TBS.TBSP_PAGE_SIZE / 1024 / 1024 AS MAXUSED_MB
#        ,VARCHAR(TBS.TBSP_STATE,20) AS STATE
#        ,CASE WHEN TBS.TBSP_USING_AUTO_STORAGE=1 THEN 'Y' ELSE 'N' END AS AUTO
#        ,VARCHAR(TBS.STORAGE_GROUP_NAME,20) AS STORAGE_GROUP  -- !!!!!  Only for > v10
#        ,CASE WHEN TBS.FS_CACHING=1 THEN 'N' ELSE 'Y' END AS FS_CACHE   -- fs_caching=1 is 
#      FROM TABLE(SYSPROC.MON_GET_TABLESPACE('', -2)) TBS
#        INNER JOIN SYSCAT.BUFFERPOOLS BP ON TBS.TBSP_CUR_POOL_ID = BP.BUFFERPOOLID",
	"member" => "
       SELECT ID,
         HOME_HOST AS HOME_HOST, 
         CURRENT_HOST AS CUR_HOST, 
         STATE AS STATE, 
         ALERT 
			 FROM SYSIBMADM.DB2_MEMBER;",
  "main" => "SELECT MEMBER, DB2_STATUS,TIMEZONEID,PRODUCT_NAME,SERVER_PLATFORM,SERVICE_LEVEL,DB2START_TIME,AGENTS_REGISTERED,IDLE_AGENTS,AGENTS_STOLEN FROM TABLE(MON_GET_INSTANCE(-2));",
);

my %conf_sa = (
  shared_buffers => "1",
  wal_buffers    => "1",
);

my @perf_types = ( "size","member","members","main","bp");

my $pre_perf = get_data("PERF", $db_name, $db, $hostname, $port, $user, $pass);
  #print Dumper $pre_perf;
  my $act_perf;
#if ( $pre_perf ne "err" ) {
  #my $db_id = Xorux_lib::uuid_big_endian_format( SQLServerDataWrapper::md5_string("$row->{database_name}-$row->{database_id}-$alias") );
  #$arc{hostnames}{ $creds{$alias}{uuid} }{alias} = $alias;
  #$arc{hostnames}{ $creds{$alias}{uuid} }{label} = "Cluster";

  #$arc{hostnames}{ $creds{$alias}{uuid} }{_dbs}{$db_id}{id}    = "$row->{database_id}";
  #$arc{hostnames}{ $creds{$alias}{uuid} }{_dbs}{$db_id}{label} = "$row->{database_name}";

  ##  warn Dumper \%arc;
  #Xorux_lib::write_json( "$conf_dir/arc.json", \%arc );

  $act_perf = make_perf($pre_perf);
#  print Dumper $act_perf;
#}

my $act_conf = make_conf($pre_perf);

if (defined $act_conf->{_cluster}->{size}){ 
 Xorux_lib::write_json( "$conf_dir/db2_conf.json",    $act_conf );
}
Xorux_lib::write_json( "$iostats_dir/db2_perf.json", $act_perf );
Xorux_lib::write_json( "$conf_dir/arc.json",        \%arc );



sub make_perf {
  my $_data      = shift;
  my %_data      = %{$_data};

  my %perf;
  my $mem_total;
  foreach my $type ( @perf_types ) {

    if ( $type eq "members" ) {

      foreach my $row ( @{ $_data{$type}{data} } ) {
        my %clean_row = clean_data($row);
        $mem_total = add_to_hash($mem_total, \%clean_row);
        my $n_id =  Xorux_lib::uuid_big_endian_format(Db2DataWrapper::md5_string("$row->{MEMBER}-$alias")); 
        $arc{hostnames}{ $creds{$alias}{uuid} }{_dbs}{$n_id}{label} = "$row->{MEMBER}";

        $perf{$type}{ $row->{MEMBER} } = \%clean_row;
       }
    }elsif ( $type eq "bp" ) {

      foreach my $row ( @{ $_data{$type}{data} } ) {
        my %clean_row = clean_data($row);
        
        my $n_id =  Xorux_lib::uuid_big_endian_format(Db2DataWrapper::md5_string("$row->{BP_NAME}-$alias")); 
        $arc{hostnames}{ $creds{$alias}{uuid} }{_bps}{$n_id}{label} = "$row->{BP_NAME}";

        $perf{$type}{ $row->{BP_NAME} } = \%clean_row;
       }
    }elsif ( $type eq "main" ) {
      foreach my $row ( @{ $_data{$type}{data} } ) {
        my %row_dup = %{$row};
        delete $row_dup{'MEMBER'};
        delete $row_dup{'DB2_STATUS'};
        delete $row_dup{'TIMEZONEID'};
        delete $row_dup{'PRODUCT_NAME'};
        delete $row_dup{'SERVER_PLATFORM'};
        delete $row_dup{'SERVICE_LEVEL'};
        delete $row_dup{'DB2START_TIME'};
        $mem_total = add_to_hash($mem_total, \%row_dup);
      
        $perf{members}{ $row->{MEMBER} }{ 'AGENTS_STOLEN'}     = $row->{ 'AGENTS_STOLEN'}; 
        $perf{members}{ $row->{MEMBER} }{ 'IDLE_AGENTS'}       = $row->{ 'IDLE_AGENTS'};   
        $perf{members}{ $row->{MEMBER} }{ 'AGENTS_REGISTERED'} = $row->{ 'AGENTS_REGISTERED'};
      }
    }
  }
  $perf{members}{Total} = $mem_total;
  $perf{_info}{timestamp}     = time;
  $perf{_info}{readable_time} = localtime( $perf{_info}{timestamp} );

  return \%perf;
}

sub make_conf {
  my $_data      = shift;
  my %_data      = %{$_data};
  my %conf_types = (
    "size"   => 1,
    "member" => 1,
    "main"   => 1,
  );

  my %perf;
  for my $type ( keys %conf_types ) {
    print Dumper \%perf;
    if ( $type eq "size" and $_data{$type}) {
      foreach my $row ( @{ $_data{$type}{data} } ) {
        my %nr;
        my %row_dup = %{$row};

        $perf{_cluster}{size}{$row_dup{'TBSP_NAME'}}[0]{'Free'}    = $row_dup{'FREE'};
        $perf{_cluster}{size}{$row_dup{'TBSP_NAME'}}[0]{'Used'}    = $row_dup{'MAXUSED'};
        $perf{_cluster}{size}{$row_dup{'TBSP_NAME'}}[0]{'Used %'}  = sprintf( "%.0f", $row_dup{'USED_PCT'});
        $perf{_cluster}{size}{$row_dup{'TBSP_NAME'}}[0]{'Total'}   = $row_dup{'SIZE'};
        $perf{_cluster}{size}{$row_dup{'TBSP_NAME'}}[0]{'Name'}    = $row_dup{'TBSP_NAME'};

        $perf{_cluster}{size}{"2nd_header"}[0]{'Free'}    += $row_dup{'FREE'}; 
        $perf{_cluster}{size}{"2nd_header"}[0]{'Used'}    += $row_dup{'MAXUSED'}; 
        $perf{_cluster}{size}{"2nd_header"}[0]{'Total'}   += $row_dup{'SIZE'}; 
      }
      $perf{_cluster}{size}{"2nd_header"}[0]{'Name'}    = "Total"; 
      $perf{_cluster}{size}{"2nd_header"}[0]{'Total'}   = $perf{_cluster}{size}{"2nd_header"}[0]{'Total'} ? $perf{_cluster}{size}{"2nd_header"}[0]{'Total'} : 1;
      $perf{_cluster}{size}{"2nd_header"}[0]{'Used'}    = $perf{_cluster}{size}{"2nd_header"}[0]{'Used'} ? $perf{_cluster}{size}{"2nd_header"}[0]{'Used'} : 1;
      $perf{_cluster}{size}{"2nd_header"}[0]{'Used %'}  = sprintf( "%.0f", ($perf{_cluster}{size}{"2nd_header"}[0]{'Used'} / $perf{_cluster}{size}{"2nd_header"}[0]{'Total'}) * 100); 
    }elsif ( $type eq "member" ) {
      my $row_i = 0;
      foreach my $row ( @{ $_data{$type}{data} } ) {
        my %row_dup = %{$row};
        my %nr;
        $perf{_cluster}{member}{$row_dup{ID}}[$row_i]{'ID'}        = $row_dup{'ID'};
        $perf{_cluster}{member}{$row_dup{ID}}[$row_i]{'ALERT'}     = $row_dup{'ALERT'};
        $perf{_cluster}{member}{$row_dup{ID}}[$row_i]{'STATE'}     = $row_dup{'STATE'};
        $perf{_cluster}{member}{$row_dup{ID}}[$row_i]{'CUR_HOST'}  = $row_dup{'CUR_HOST'};
        $perf{_cluster}{member}{$row_dup{ID}}[$row_i]{'HOME_HOST'} = $row_dup{'HOME_HOST'};
      }
    }elsif ( $type eq "main" ) {
      my $row_i = 0;
      foreach my $row ( @{ $_data{$type}{data} } ) {
        my %row_dup = %{$row};
        my %nr;
        $perf{_cluster}{main}{$row_dup{MEMBER}}[$row_i]{'Member'}          = $row_dup{'MEMBER'};
        $perf{_cluster}{main}{$row_dup{MEMBER}}[$row_i]{'Status'}          = $row_dup{'DB2_STATUS'};
        $perf{_cluster}{main}{$row_dup{MEMBER}}[$row_i]{'Timezone'}        = $row_dup{'TIMEZONEID'};
        $perf{_cluster}{main}{$row_dup{MEMBER}}[$row_i]{'Product name'}    = $row_dup{'PRODUCT_NAME'};
        $perf{_cluster}{main}{$row_dup{MEMBER}}[$row_i]{'Server platform'} = $row_dup{'SERVER_PLATFORM'};
        $perf{_cluster}{main}{$row_dup{MEMBER}}[$row_i]{'Service level'}   = $row_dup{'SERVICE_LEVEL'};
        $perf{_cluster}{main}{$row_dup{MEMBER}}[$row_i]{'Start time'}      = $row_dup{'DB2START_TIME'};
      }
    }
  }

  $perf{_info}{timestamp}     = time;
  $perf{_info}{readable_time} = localtime( $perf{_info}{timestamp} );

  return \%perf;
}

sub clean_data {
  my $data = shift;

   my @perf_metrics = (
    "AGENTS_TOP",
    "NUM_POOLED_AGENTS",
    "NUM_ASSOC_AGENTS",
    "NUM_COORD_AGENTS",
    "NUM_LOCKS_HELD",
    "NUM_LOCKS_WAITING",
    "LOCK_ESCALS",
    "LOCK_TIMEOUTS",
    "DEADLOCKS",
    "POOL_DATA_L_READS",
    "POOL_TEMP_DATA_L_READS",
    "POOL_INDEX_L_READS",
    "POOL_TEMP_INDEX_L_READS",
    "POOL_XDA_L_READS",
    "POOL_TEMP_XDA_L_READS",
    "POOL_DATA_P_READS",
    "POOL_TEMP_DATA_P_READS",
    "POOL_INDEX_P_READS",
    "POOL_TEMP_INDEX_P_READS",
    "POOL_XDA_P_READS",
    "POOL_TEMP_XDA_P_READS",
    "POOL_DATA_WRITES",
    "POOL_INDEX_WRITES",
    "POOL_XDA_WRITES",
    "DIRECT_READS",
    "DIRECT_WRITES",
    "DIRECT_READ_TIME",
    "POOL_READ_TIME",
    "POOL_WRITE_TIME",
    "ROWS_MODIFIED",
    "ROWS_RETURNED",
    "ROWS_READ",
    "ROWS_UPDATED",
    "ROWS_DELETED",
    "ROWS_INSERTED",
    "INT_ROWS_DELETED",
    "INT_ROWS_INSERTED",
    "INT_ROWS_UPDATED",
    "FED_ROWS_DELETED",
    "FED_ROWS_INSERTED",
    "FED_ROWS_UPDATED",
    "FED_ROWS_READ",
    "TCPIP_SEND_VOLUME",
    "TCPIP_RECV_VOLUME",
    "IPC_SEND_VOLUME",
    "IPC_RECV_VOLUME",
    "FCM_SEND_VOLUME",
    "FCM_RECV_VOLUME",
    "PKG_CACHE_INSERTS",
    "PKG_CACHE_LOOKUPS",
    "TOTAL_APP_COMMITS",
    "TOTAL_APP_ROLLBACKS",
    "DIRECT_WRITE_TIME",
    "LOG_DISK_WAIT_TIME",
    "TCPIP_SEND_WAIT_TIME",
    "TCPIP_RECV_WAIT_TIME",
    "IPC_SEND_WAIT_TIME",
    "IPC_RECV_WAIT_TIME",
    "FCM_SEND_WAIT_TIME",
    "FCM_RECV_WAIT_TIME",
    "CF_WAIT_TIME",
    "CLIENT_IDLE_WAIT_TIME",
    "LOCK_WAIT_TIME",
    "AGENT_WAIT_TIME",
    "WLM_QUEUE_TIME_TOTAL",
    "CONNECTIONS_TOP",
    "TOTAL_CONS",
    "TOTAL_SEC_CONS",
    "APPLS_CUR_CONS",
  );

  my %new_perf;
  for my $metric (@perf_metrics){
    if (defined $data->{$metric}){
      $new_perf{$metric} = $data->{$metric};
    }#else{
     # #$new_perf{$metric} = 0;
     #}
  }
  $new_perf{LOGICAL_READS}  = $new_perf{POOL_DATA_L_READS} + $new_perf{POOL_TEMP_DATA_L_READS} + $new_perf{POOL_INDEX_L_READS} + $new_perf{POOL_TEMP_INDEX_L_READS} + $new_perf{POOL_XDA_L_READS} + $new_perf{POOL_TEMP_XDA_L_READS};
  $new_perf{PHYSICAL_READS} = $new_perf{POOL_DATA_P_READS} + $new_perf{POOL_TEMP_DATA_P_READS} + $new_perf{POOL_INDEX_P_READS} + $new_perf{POOL_TEMP_INDEX_P_READS} + $new_perf{POOL_XDA_P_READS} + $new_perf{POOL_TEMP_XDA_P_READS};
  $new_perf{WRITES}         = $new_perf{POOL_DATA_WRITES}  + $new_perf{POOL_INDEX_WRITES}      + $new_perf{POOL_XDA_WRITES};
  $new_perf{POOL_READS}     = $new_perf{LOGICAL_READS} + $new_perf{PHYSICAL_READS};
  $new_perf{POOL_WRITES}    = $new_perf{WRITES};

  return %new_perf;
}

sub add_to_hash {
  my $prev_hash = shift;
  my $cur_hash  = shift;

  if(keys %{$prev_hash} == 0){
    return $cur_hash;
  }else{
    for my $key (keys %{$cur_hash}){
      if(defined $prev_hash->{$key}){
        $prev_hash->{$key} = $prev_hash->{$key} + $cur_hash->{$key};
      }else{
        $prev_hash->{$key} = $cur_hash->{$key};
      }
    }
    return $prev_hash;
  }
}

sub get_data {
  my $_type     = shift;
  my $_db_name  = shift;
  my $_db       = shift;
  my $_hostname = shift;
  my $_port     = shift;
  my $_user     = shift;
  my $_pass     = shift;



  my $string = "dbi:DB2:DATABASE=$_db; HOSTNAME=$_hostname; PORT=$_port; PROTOCOL=TCPIP; UID=$_user; PWD=$_pass;";
  my $dbh = DBI->connect($string, { PrintError => 0 } );

  my $result;

  my $time_is_now = time;
  my $err         = 0;
  $err = DBI->errstr;

  if ( $err and !( defined $dbh ) ) {
    my @row;
    $row[0] = "DB2";
    $row[1] = "$alias";
    $row[2] = "$_db_name";
    $row[3] = "NOT_OK";
    $row[4] = "$time_is_now";
    $row[5] = $err;
    push( @health_status, \@row );
  }
  else {
    my @row;
    $row[0] = "DB2";
    $row[1] = "$alias";
    $row[2] = "$_db_name";
    $row[3] = "OK";
    $row[4] = "$time_is_now";
    push( @health_status, \@row );
  }
  generate_hsfiles();

  if ( !( defined $dbh ) ) {
    warn $err;
    return "err";
  }

  my %_data;

  #trade
  for my $query_name ( keys %query ) {
    print "$query_name\n\n";
    my $array_ref = get_query_result( $dbh, $query{$query_name} );
    $_data{$query_name}{data} = $array_ref;
    $_data{$query_name}{info}{db_name} = $_db_name;
  }

  if (DatabasesWrapper::can_update("$act_dir/size_hourly", 300, 1)){
    for my $query_name ( keys %c_query ) {
      print "$query_name\n\n";
      my $array_ref = get_query_result( $dbh, $c_query{$query_name} );
      $_data{$query_name}{data} = $array_ref;
      $_data{$query_name}{info}{db_name} = $_db_name;
    }
  }

  # clean up
  $dbh->disconnect();

  return \%_data;
}

sub get_query_result {
  my $_dbh  = shift;
  my $query = shift;
  my @array;

  #warn $query;
  my $sth = $_dbh->prepare($query);
  $sth->execute();

  while ( my $ref = $sth->fetchrow_hashref() ) {
    push( @array, $ref );
  }
  return \@array;
}

sub convert_to_gb {
  my $_value  = shift;
  my $type    = shift;
  my $new_val = $_value;
  if ( defined $new_val and $new_val =~ / KB/ ) {
    $new_val =~ s/ KB//g;
    $new_val /= 1000;
  }
  elsif ( defined $new_val and $new_val =~ / MB/ ) {
    $new_val =~ s/ MB//g;
    $new_val /= 1;
  }
  elsif ( defined $new_val and $new_val =~ / GB/ ) {
    $new_val =~ s/ GB//g;
  }
  elsif ( defined $new_val and $new_val =~ / TB/ ) {
    $new_val =~ s/ TB//g;
    $new_val *= 1;
  }
  else {
    warn "$_value, $type";
    return 0;
  }

  return $new_val;
}

sub generate_hsfiles {
  foreach my $row (@health_status) {
    my @row_arr = @{$row};

    if ( $row_arr[3] eq "OK" ) {
      my $checkup_file_ok  = "$hs_dir_db2/$alias\_$row_arr[2].ok";
      my $checkup_file_nok = "$hs_dir_db2/$alias\_$row_arr[2].nok";
      if ( -f $checkup_file_nok ) {
        unlink $checkup_file_nok;
      }
      my $joined_row = join( " : ", @row_arr );
      open my $fh, '>', $checkup_file_ok;

      print $fh $joined_row;
      close $fh;

    }
    elsif ( $row_arr[3] eq "NOT_OK" ) {
      my $checkup_file_ok  = "$hs_dir_db2/$alias\_$row_arr[2].ok";
      my $checkup_file_nok = "$hs_dir_db2/$alias\_$row_arr[2].nok";
      if ( -f $checkup_file_ok ) {
        unlink $checkup_file_ok;
      }

      if ( !-f $checkup_file_nok ) {
        my $joined_row = join( " : ", @row_arr );
        open my $fh, '>', $checkup_file_nok;
        print $fh $joined_row;
        close $fh;
      }
    }
  }
}



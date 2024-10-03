# PowerDataWrapper.pm
# interface for accessing IBM Power data:
#   provides filepaths

package PowerDataWrapperJSON;

use strict;

use JSON;
use Data::Dumper;
use Xorux_lib qw(error read_json write_json);
use HostCfg;
use Digest::MD5 qw(md5 md5_hex md5_base64);
use Storable;

#use PowerDataWrapper;

defined $ENV{INPUTDIR} || Xorux_lib::error( "INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded " . __FILE__ . ":" . __LINE__ ) && exit 1;

my $hmc                             = $ENV{HMC};
my $server                          = $ENV{MANAGEDNAME};
my $inputdir                        = $ENV{INPUTDIR};
my $wrkdir                          = "$inputdir/data";
my $power_conf                      = "$inputdir/tmp/power_conf.storable";
my $servers_conf                    = "$inputdir/tmp/servers_conf.storable";
my %dictionary                      = ();
my $metadata_loaded                 = 0;
my $db_file                         = "$wrkdir/_DB/data.db";
my $actual_configuration_in_seconds = 86400;
my $actual_power_conf_in_seconds    = 300;

my $POOLS;
my $VMS;
my $dictionary = get_dictionary();

my $SERV = {};
my $CONF = {};

my $acl;
my $use_sql;

if ( defined $ENV{XORMON} && $ENV{XORMON} ) {
  $use_sql = 1;

  require ACLx;
  $acl = ACLx->new();

  sub isGranted {
    my $uuid = shift;
    return $acl->isGranted( { hw_type => 'POWER', item_id => $uuid, match => 'granted' } );
  }
}

################################################################################

sub get_filepath_rrd {
  my %params = shift;
  my $type   = $params{type} if ( defined $params{type} );    # type = VM / POOL / SERVER
  my $uuid   = $params{uid} if ( defined $params{uid} );      # uuid = uuid(md5 hash)
  my $ext    = $params{ext} if ( defined $params{ext} );
  my $host   = $params{host} if ( defined $params{host} );

  if ( !defined $type || !defined $uuid ) {
    return;
  }

  #ACL Check
  return if ( $use_sql && !$acl->isGranted($uuid) );

  if ( $type eq "VM" ) {
    my $vm_label     = get_label( $type, $uuid );
    my $server_uid   = get_vm_parent($uuid);
    my $server_label = get_label( 'SERVER', $server_uid );
    my $hmc_uid      = get_server_parent($server_uid);
    my $hmc_label    = get_label( 'HMC', $hmc_uid );
    if ( defined $host && $host ne "" ) { $hmc_label = $host; }

    $vm_label =~ s/\//&&1/g;
    if ( $server_label eq '' || $hmc_label eq '' ) {
      return '';
    }
    return "$wrkdir/$server_label/$hmc_label/$vm_label.$ext";
  }
  elsif ( $type eq "POOL" ) {
    opendir( DIR, "$inputdir/tmp/restapi" );
    my @files = grep( /\.HMC_SHP$/, readdir(DIR) );
    closedir(DIR);

    #    my @files = <$inputdir/tmp/restapi/HMC_SHP_*>;
    foreach my $file (@files) {
      if ( Xorux_lib::file_time_diff($file) <= $actual_configuration_in_seconds ) {
        my $servername = parse_servername_from_filename($file);
        my $f_content  = {};
        $f_content = Xorux_lib::read_json($file) if ( -e $file );
        foreach my $pool_hash ( keys %{$f_content} ) {
          if ( $uuid eq $f_content->{$pool_hash}{UUID} ) {
            return "$inputdir/data/$servername/$hmc/SharedPool$f_content->{$pool_hash}{PoolID}.$ext";
          }
        }
      }
    }
  }
  elsif ( $type eq "SERVER" ) {
    my $server_label = get_label( 'SERVER', $uuid );
    my $hmc_uid      = get_server_parent($uuid);
    my $hmc_label    = get_label( 'HMC', $hmc_uid );
    return "$wrkdir/$server_label/$hmc_label/pool.$ext";
  }
  elsif ( $type eq "INT" ) {
  }
  return '';
}

sub get_filepath_rrd_vm {
  my $vm_name     = shift;
  my $managedname = shift;
  my $type        = shift;
  return ( $vm_name, "$wrkdir/$managedname/$hmc/$vm_name.$type" ) if ( defined $type && $type ne "" );
  return ( $vm_name, "$wrkdir/$managedname/$hmc/$vm_name" )       if ( defined $type && $type eq "" );
}

sub get_filepath_rrd_cpupool {
  my $managedname = shift;
  my $host        = shift;
  my $type        = shift;
  return "$wrkdir/$managedname/$host/pool_total.$type";
}

sub get_label {
  my $type = shift;    # type = VM / POOL / SERVER
  my $uuid = shift;    # uuid = uuid(md5 hash)
  $type = uc($type);
  my $out;

  my $result = get_items($type);
  foreach my $item_hash ( @{$result} ) {
    my $uuid_test = ( keys %{$item_hash} )[0];
    if ( $uuid eq $uuid_test ) {
      return $item_hash->{$uuid};
    }
  }
  return '';
}

sub get_pool_name {
  my $uid = shift;
  foreach my $pool_uid ( keys %{ $CONF->{pools} } ) {
    return $CONF->{pools}{$pool_uid}{name} if ( $pool_uid eq $uid );
  }
  return "undefined";
}

sub get_conf {
  my $conf;
  $conf->{servers}    = {};
  $conf->{vms}        = {};
  $conf->{pools}      = {};
  $conf->{interfaces} = {};
  $conf->{LAN}        = {};
  $conf->{SAN}        = {};
  $conf->{SAS}        = {};
  $conf->{SRI}        = {};

  #add servers to conf
  my $servers = $SERV;
  $conf->{servers} = $servers;

  #add hmcs to conf
  my $hmcs = get_hmcs($servers) if ( defined $servers );

  #  $conf->{hmcs} = $hmcs;
  foreach my $hmc_uid ( keys %{$hmcs} ) {
    my $hmc_label = $hmcs->{$hmc_uid}{label};

    #    my $hmc_uid = md5_string($hmc_label);
    $conf->{hmcs}{$hmc_uid}{label} = $hmc_label;
  }

  foreach my $server_uid ( keys %{$servers} ) {
    my $server_name = $servers->{$server_uid}{label};

    #add vms to conf
    my $vms = get_vms( $server_uid, $server_name, $servers );
    $conf->{vms} = { %{ $conf->{vms} }, %{$vms} } if defined($vms);

    #add pools to conf
    my $pools = get_pools( $server_uid, $server_name, $servers );
    $conf->{pools} = { %{ $conf->{pools} }, %{$pools} } if defined($pools);

    #add interfaces to conf
    my @types = ( "LAN", "SAN", "SAS", "HEA", "SRI" );
    foreach my $type (@types) {
      my $interfaces = get_interfaces( $type, $server_uid, $server_name );
      $conf->{$type} = { %{ $conf->{$type} }, %{$interfaces} } if ( defined $interfaces && defined $conf->{$type} );
      if ( !defined $conf->{$type} && defined $interfaces ) { $conf->{$type} = $interfaces; }
    }

    #add daemon uuids to database
  }
  if ( !defined $conf ) { $conf = {}; }
  return $conf;
}

# return: [ uuid1 => "label1", uuid2 => "label2", ... ]
sub get_items {
  my $item_type = shift;    # item_type = VM / POOL / SERVER
  $item_type = uc($item_type);
  my $parent  = shift;      # parent (optional)
  my $servers = $SERV;
  my $parents;
  my $out;
  my $items;
  my $server_name;

  if ( !defined $parent ) {
    @{$parents} = keys %{$servers};
  }
  else {
    push( @{$parents}, $parent );
  }
  foreach my $p ( @{$parents} ) {
    $server_name = $servers->{$p}{label};
    if ( $item_type eq "SERVER" ) {
      $out = { %$out, %$servers } if defined $out;
      if ( !defined $out ) { $out = $servers; }

    }
    elsif ( $item_type eq "POOL" ) {
      my $pools = get_pools( $p, $server_name, $servers );
      if ( !defined $pools ) { next; }
      $out = { %$out, %$pools } if defined $out;
      if ( !defined $out ) { $out = $pools; }

    }
    elsif ( $item_type eq "VM" ) {
      my $vms = get_vms( $p, $server_name, $servers );
      if ( !defined $vms ) { next; }
      $out = { %$out, %$vms } if defined $out;
      if ( !defined $out ) { $out = $vms; }

    }
    elsif ( $item_type eq "HMC" ) {
      my $hmcs = get_hmcs($servers);
      if ( !defined $hmcs ) { next; }
      $out = { %$out, %$hmcs } if defined $out;
      if ( !defined $out ) { $out = $hmcs; }

    }
    elsif ( $item_type eq "LAN" || $item_type eq "SAN" || $item_type eq "SAS" || $item_type eq "HEA" || $item_type eq "SRI" ) {
      my $int = get_interfaces( $item_type, $p, $server_name );
      if ( !defined $int ) { next; }
      $out = { %$out, %$int } if defined $out;
      if ( !defined $out ) { $out = $int; }

    }
    else {
      Xorux_lib::error( "Unknown type $item_type " . __FILE__ . ":" . __LINE__ );
      return '';
    }
  }

  my $prev_item = "";
  my $sorted;
  my $last_i;

  #  if (ref($out) ne "HASH"){ return; }
  #  #foreach my $key (sort { lc($out->{$a}{label}) cmp lc($out->{$b}{label}) } keys %{ $out } ) {
  #  #foreach my $key (sort { $out->{$a} <=> $out->{$b} } keys %{$out->{label}} ) {
  foreach my $key ( keys %{$out} ) {
    my $value   = $out->{$key}{label};
    my %item    = ( $key => $value );
    my $aclitem = { hw_type => 'POWER', item_id => $key, match => 'granted' };
    push( @{$sorted}, \%item );
  }
  return $sorted if defined $sorted;
  return [];
}

sub get_hmcs {
  my $hmcs;
  my %hosts = %{ HostCfg::getHostConnections("IBM Power Systems") };
  foreach my $alias ( keys %hosts ) {
    my $hmc_uid = md5_string( $hosts{$alias}{host} );
    $hmcs->{$hmc_uid}{label} = $hosts{$alias}{host};
  }
  return $hmcs;
}

sub get_server_parent {
  my $server_uuid = shift;
  my $servers     = $SERV;
  if ( !defined $servers->{$server_uuid}{parent} || ref( $servers->{$server_uuid}{parent} ) ne "ARRAY" ) {
    return 1;
  }
  foreach my $current_parent ( @{ $servers->{$server_uuid}{parent} } ) {
    return $current_parent;    #select the first one. It doesn't matter which active HMC is returned
  }
  return 1;
}

sub get_server_metric {
  ( $SERV, $CONF ) = init() if ( !defined $CONF->{servers} );
  my $managedname   = shift;
  my $metric        = shift;
  my $default_value = shift;
  my $servers       = $SERV;
  my $server_uuid   = get_item_uid( { type => 'server', label => "$managedname" } );
  return $servers->{$server_uuid}{$metric} if defined $servers->{$server_uuid}{$metric};

  ##warn "Not found $metric for $managedname with uid $server_uuid\n";
  return $default_value;
}

sub get_metric_from_config_cfg {
  my $path   = shift;
  my $metric = shift;
  open( my $fh, "<", $path ) || warn "cannot open $path at " . __FILE__ . ":" . __LINE__ . "\n";
  my @lines = <$fh>;
  close($fh);
  my ($h) = grep /$metric/, @lines;
  $h =~ s/^.*$metric//g;
  $h =~ s/^\s+|\s+$//;
  chomp($h);
  return $h;
}

sub get_pool_parent {
  my $uid = shift;
  foreach my $pool_uid ( keys %{ $CONF->{pools} } ) {
    if ( $pool_uid eq $uid ) {
      return $CONF->{pools}{$pool_uid}{parent} if defined $CONF->{pools}{$pool_uid}{parent};
      return '';
    }
  }
}

sub get_vm_parent {
  my $uid = shift;
  foreach my $vm_uid ( keys %{ $CONF->{vms} } ) {
    if ( $vm_uid eq $uid ) {
      return $CONF->{vms}{$vm_uid}{parent} if defined $CONF->{vms}{$vm_uid}{parent};
      return '';
    }
  }
}

sub get_int_parent {
  my $uid  = shift;
  my $type = shift;
  $type = uc($type);
  foreach my $int_uid ( keys %{ $CONF->{$type} } ) {
    if ( $int_uid eq $uid ) {
      return $CONF->{$type}{$int_uid}{parent} if defined $CONF->{$type}{$int_uid}{parent};
      return '';
    }
  }
}

sub get_pool_id {
  my $pool_uuid   = shift;
  my $server_uuid = shift;
  foreach my $uid ( keys %{ $CONF->{pools} } ) {
    if ( $uid eq $pool_uuid ) {
      return $CONF->{pools}{$pool_uuid}{id} if defined $CONF->{pools}{$pool_uuid}{id};
      return '';
    }
  }
  return '';
}

#return : { uuid1 => { label => "label1", UUID => "UUID1", ... , parent => "parent_hmc1" }, uuid2 => { label => "label2", UUID => "UUID2", ... , parent => "parent_hmc2" } }
sub get_servers {
  my @files = <$inputdir/tmp/restapi/HMC_INFO*>;

  if ( scalar @files == 0 ) {
    return {};
  }

  my $out;
  my $UUID_check;
  foreach my $file (@files) {
    if ( Xorux_lib::file_time_diff($file) <= $actual_configuration_in_seconds ) {
      my $act_hmc = $file;
      ( undef, $act_hmc ) = split( "HMC_INFO_", $act_hmc );
      ( $act_hmc, undef ) = split( '\.json', $act_hmc );
      my $file_content = {};
      $file_content = Xorux_lib::read_json($file) if ( -e $file );
      if ( $file_content eq "1" ) { next; }
      foreach my $i ( keys %{$file_content} ) {
        my $config_ssh       = "$inputdir/data/$file_content->{$i}{name}/$act_hmc/config.cfg";
        my @config_ssh_lines = ();
        if ( -e $config_ssh && Xorux_lib::file_time_diff($config_ssh) <= $actual_configuration_in_seconds ) {
          open( my $fh, "$config_ssh" );
          @config_ssh_lines = <$fh>;
          close($fh);
        }
        my $server_conf_file         = "$inputdir/tmp/restapi/HMC_SERVER_$file_content->{$i}{name}_conf.json";
        my $server_conf_file_content = {};
        $server_conf_file_content = Xorux_lib::read_json($server_conf_file) if ( -e $server_conf_file );

        #my $serial = $file_content->{$i}{SerialNumber}{content} if (ref($file_content->{$i}{SerialNumber}) eq "HASH");
        #print STDERR "SERIAL : $serial\n";
        my $machine_type = $file_content->{$i}{MachineType}{content} if ( ref( $file_content->{$i}{MachineType} ) eq "HASH" );
        my $model        = $file_content->{$i}{Model}{content}       if ( ref( $file_content->{$i}{Model} ) eq "HASH" );
        my $UUID         = $file_content->{$i}{UUID};

        $out->{$UUID}{Model}       = $model;
        $out->{$UUID}{MachineType} = $machine_type;

        my $done = 0;
        $done                 = 1 if $UUID_check->{$UUID};
        $UUID_check->{$UUID}  = 1;
        $out->{$UUID}{parent} = [] if ( !defined $out->{$UUID}{parent} || ref( $out->{$UUID}{parent} ) ne "ARRAY" );
        my $hmc_uid = md5_string($act_hmc);
        if ( $done == 0 ) {
          $out->{$UUID}{label}     = $file_content->{$i}{name} if defined $file_content->{$i}{name};
          $out->{$UUID}{UUID}      = $UUID                     if defined $UUID;
          $out->{$UUID}{REST_UUID} = $file_content->{$i}{id}   if defined $file_content->{$i}{id};
          $out->{$UUID}{type}      = "server";
          $out->{$UUID}{parent_type} = "HMC";
          foreach my $metric ( keys %{$server_conf_file_content} ) {
            $out->{$UUID}{$metric} = $server_conf_file_content->{$metric};
          }
        }

        #print "DEBUG1 $act_hmc, $hmc_uid : " . ref($out) . ", " . ref($out->{$UUID}) . ", " . ref($out->{$UUID}{parent}) . "\n";
        push( @{ $out->{$UUID}{parent} }, md5_string($act_hmc) );

        #print "DEBUG2 $act_hmc, $hmc_uid : " . ref($out) . ", " . ref($out->{$UUID}) . ", " . ref($out->{$UUID}{parent}) . "\n";
        #print Dumper $out->{$UUID}{parent};
        my $config_json_path    = "$inputdir/data/$file_content->{$i}{name}/$act_hmc/CONFIG.json";
        my $config_json_content = {};
        $config_json_content                       = Xorux_lib::read_json($config_json_path)                     if ( -e $config_json_path );
        $out->{$UUID}{CurrentProcessingUnitsTotal} = $config_json_content->{server}{CurrentProcessingUnitsTotal} if ( defined $config_json_content->{server}{CurrentProcessingUnitsTotal} );
        foreach my $metric_value (@config_ssh_lines) {
          if ( $metric_value =~ /</ || $metric_value !~ /^[a-z]/ || $metric_value eq "" || $metric_value =~ /slot_num/ || $metric_value =~ /unit_phys_loc/ || $metric_value =~ /lpar_name/ || $metric_value =~ /adapter_id/ ) { next; }
          if ( $metric_value =~ m/Physical IO/ || $metric_value =~ m/pend_avail_pool_proc_units/ ) { last; }
          ( my $metric, my $value ) = split( " ", $metric_value );
          if ( $metric =~ m/,/ ) {
            my @sub_metrics = split( ",", $metric );
            foreach my $sub_metric (@sub_metrics) {
              my ( $sub_met, $sub_val ) = split( "=", $sub_metric );
              if ( defined $dictionary->{server}{$sub_met} ) {
                $sub_met = $dictionary->{server}{$sub_met};
              }
              elsif ( defined $dictionary->{memory}{$sub_met} ) {
                $sub_met = $dictionary->{memory}{$sub_met};
              }
              else {
                next;
              }
              $out->{$UUID}{$sub_met} = $sub_val;
            }
          }
          else {
            #            if (defined $dictionary->{server}{$metric}) { $metric = $dictionary->{server}{$metric}; } else { next; }
            if ( defined $dictionary->{server}{$metric} ) { $metric = $dictionary->{server}{$metric}; }
            if ( defined $dictionary->{memory}{$metric} ) { $metric = $dictionary->{memory}{$metric}; }
            $out->{$UUID}{$metric} = $value;
          }
        }
      }
    }
  }
  if ( !defined $out ) { $out = {}; }

  #print STDERR Dumper $out;
  return $out;
}

#return : { uuid1 => { label => "label1", UUID => "UUID1", ... , parent => "parent_uuid1" }, uuid2 => { label => "label2", UUID => "UUID2", ... , parent => "parent_uuid2" } }
sub get_pools {
  my $parent     = shift;
  my $servername = shift;
  my $SERVERS    = shift;
  my $out;
  if ( !defined $servername || !defined $SERVERS ) {
    return {};
  }
  my $srv_tmp = $servername;
  $srv_tmp =~ s/ /\\ /g;
  my @files = <$inputdir/tmp/restapi/HMC_SHP_$srv_tmp*>;
  foreach my $file (@files) {
    if ( Xorux_lib::file_time_diff($file) <= $actual_configuration_in_seconds ) {

      #my $servername = parse_servername_from_filename($file);
      my $label_test = get_some_label( "SERVER", $parent, $SERVERS );
      if ( !defined $servername || !defined $label_test ) { next; }
      if ( $servername ne $label_test )                   { next; }
      my $file_content = {};
      $file_content = Xorux_lib::read_json($file) if ( -e $file );
      foreach my $pool_id ( keys %{$file_content} ) {
        my $id                          = $file_content->{$pool_id}{PoolID};
        my $UUID_POOL                   = $file_content->{$pool_id}{UUID};
        my $name                        = $file_content->{$pool_id}{PoolName};
        my $available_proc_units        = $file_content->{$pool_id}{AvailableProcUnits};
        my $current_reserved_proc_units = $file_content->{$pool_id}{CurrentReservedProcessingUnits};
        my $pending_reserved_proc_units = $file_content->{$pool_id}{PendingReservedProcessingUnits};
        my $maximum_proc_units          = $file_content->{$pool_id}{MaximumProcessingUnits};
        my $pool;
        $pool->{id}    = $id             if defined $id;
        $pool->{label} = "SharedPool$id" if defined $id;
        $pool->{type}  = "pool";
        $pool->{name}  = $name;
        $pool->{parent}      = $parent if defined $parent;
        $pool->{parent_type} = "SERVER";
        $pool->{UUID}        = $UUID_POOL if defined $UUID_POOL;
        $out->{$UUID_POOL}   = $pool;

        foreach my $metric ( keys %{ $file_content->{$pool_id} } ) {
          my $metric_dict = $metric;
          if ( defined $dictionary->{pool}{$metric} ) { $metric_dict = $dictionary->{pool}{$metric}; }
          $out->{$UUID_POOL}{$metric_dict} = $file_content->{$pool_id}{$metric} if defined $file_content->{$pool_id}{$metric};
        }
      }
    }
  }
  if ( !defined $out ) { return {}; }
  return $out;
}

#return : { uuid1 => { label => "label1", UUID => "UUID1", ... , parent => "parent_uuid1" }, uuid2 => { label => "label2", UUID => "UUID2", ... , parent => "parent_uuid2" } }
sub get_vms {

  #server name as parameter
  my $parent     = shift;
  my $servername = shift;
  my $SERVERS    = shift;
  my $out;
  my $srv_tmp = $servername;
  $srv_tmp =~ s/ /\\ /g;
  my @files = <$inputdir/tmp/restapi/HMC_LPARS_$srv_tmp*>;

  #my $alias_file = "$inputdir/etc/alias.cfg";
  #my @aliases = <$alias_file>;
  #print STDERR Dumper \@aliases;
  if ( defined $parent && $servername ne get_some_label( "SERVER", $parent, $SERVERS ) ) {
    next;
  }
  foreach my $file (@files) {
    if ( Xorux_lib::file_time_diff($file) <= $actual_configuration_in_seconds ) {
      my $file_content = {};
      $file_content = Xorux_lib::read_json($file) if ( -e $file );
      foreach my $lpar_name ( keys %{$file_content} ) {
        my $vm;
        my $UUID_vm = $file_content->{$lpar_name}{UUID};
        $out->{$UUID_vm}{label} = $lpar_name;
        $out->{$UUID_vm}{type}  = "vm";
        $out->{$UUID_vm}{UUID}  = $UUID_vm;
        my $in_pool = 0;
        $out->{$UUID_vm}{parent}       = $parent;
        $out->{$UUID_vm}{parent_label} = $servername;
        $out->{$UUID_vm}{parent_type}  = "SERVER";

        foreach my $metric ( keys %{ $file_content->{$lpar_name} } ) {
          my $new_metric_name = "";
          if ( defined $dictionary->{vm}{$metric} ) { $new_metric_name = $dictionary->{vm}{$metric}; }
          if ( $new_metric_name eq "" )             { $new_metric_name = $metric; }
          $out->{$UUID_vm}{$new_metric_name} = $file_content->{$lpar_name}{$metric} if defined $file_content->{$lpar_name}{$metric};
        }
      }
    }
  }
  return $out;
}

sub get_interfaces {
  my $type = shift;    # lan, san, sas
  $type = uc($type);
  my $server_uuid = shift;
  my $server_name = shift;
  my @servers_to_do;
  my $out = {};
  push( @servers_to_do, $server_uuid ) if defined $server_uuid;
  if ( !defined $server_uuid || $server_uuid eq "" ) {
    @servers_to_do = keys %{$SERV};
  }

  #  foreach my $server_uuid( @servers_to_do ){
  #    $server_name = get_label("SERVER", $server_uuid);
  my @files = <$inputdir/data/$server_name/*\/$type*aliases*>;
  foreach my $file (@files) {
    if ( -e $file && Xorux_lib::file_time_diff($file) <= $actual_configuration_in_seconds ) {
      my $alias_file_content = {};
      $alias_file_content = Xorux_lib::read_json($file) if ( -e $file );
      foreach my $physical_location ( keys %{$alias_file_content} ) {
        my $UUID = $alias_file_content->{$physical_location}{UUID};
        if ( !defined $UUID || $UUID eq "" ) {

          #warn "Not found UID : $physical_location in $file for\n";
          #warn Dumper $alias_file_content;
          next;
        }
        my $partition = $alias_file_content->{$physical_location}{partition};
        my $ent       = $alias_file_content->{$physical_location}{alias};
        $out->{$UUID}{label}        = "$physical_location" if defined $physical_location;
        $out->{$UUID}{partition}    = $partition           if defined $partition;
        $out->{$UUID}{ent}          = $ent                 if defined $ent;
        $out->{$UUID}{parent}       = $server_uuid         if defined $server_uuid;
        $out->{$UUID}{parent_label} = $server_name         if defined $server_name;
      }
    }
  }

  #  }
  if ( $type eq "HEA" ) {
    opendir( DIR, "$inputdir/data/$server_name" ) || return {};
    my @hmc_dirs = readdir(DIR);
    closedir(DIR);
    foreach my $hmc (@hmc_dirs) {
      if ( $hmc eq '.' || $hmc eq '..' || $hmc =~ /\.rrl$/ ) { next; }
      my $dirpath = "$inputdir/data/$server_name/$hmc/adapters";
      if ( !-d $dirpath ) { next; }
      opendir( DIR, $dirpath ) || warn( "No directory $inputdir/data/$server_name/$hmc/adapters found in file: " . __FILE__ . ":" . __LINE__ . "\n" ) && next;
      my @files = grep( /\.rahm$/, readdir(DIR) );
      closedir(DIR);
      foreach my $file (@files) {
        if ( $file eq '\.' || $file eq '\.\.' ) { next; }
        my $label = $file;
        $file = "$inputdir/data/$server_name/$hmc/adapters/$file";
        if ( -e $file && Xorux_lib::file_time_diff($file) <= $actual_configuration_in_seconds ) {
          my $UUID = md5_string($file);
          if ( !defined $UUID || $UUID eq "" ) {

            #warn "Not found UID : $physical_location in $file for\n";
            #warn Dumper $alias_file_content;
            next;
          }
          $label =~ s/\..*//g;
          $out->{$UUID}{label}        = $label if defined $label;
          $out->{$UUID}{partition}    = "";
          $out->{$UUID}{ent}          = "";
          $out->{$UUID}{parent}       = $server_uuid if defined $server_uuid;
          $out->{$UUID}{parent_label} = $server_name if defined $server_name;
        }
      }
    }
  }
  if ( $type eq "SRI" ) {
    opendir( DIR, "$inputdir/data/$server_name" ) || return {};
    my @hmc_dirs = readdir(DIR);
    closedir(DIR);
    foreach my $hmc (@hmc_dirs) {
      if ( $hmc eq '.' || $hmc eq '..' ) { next; }
      my $file = "$inputdir/data/$server_name/$hmc/sriov_log_port_list.json";
      if ( -e $file ) {
        my $sriov_aliases = {};
        $sriov_aliases = Xorux_lib::read_json($file) if ( -e $file );
        foreach my $sriov_physical_port ( keys %{$sriov_aliases} ) {
          my $UUID_physical_port = md5_string("$hmc $server_uuid $sriov_physical_port");
          if ( !defined $UUID_physical_port || $UUID_physical_port eq "" ) {

            #warn "Not found UID : $physical_location in $file for\n";
            #warn Dumper $alias_file_content;
            next;
          }
          $out->{$UUID_physical_port}{label}        = $sriov_physical_port;
          $out->{$UUID_physical_port}{parent}       = $server_uuid;
          $out->{$UUID_physical_port}{parent_label} = $server_name;
        }
      }
    }
  }
  return $out;
}

sub get_vm_tabs {
  my $uuid        = shift;
  my $vm_name     = get_label( "VM", $uuid );
  my $parent      = get_vm_parent($uuid);
  my $parent_name = get_label( "SERVER", $parent );
  my $hmc_uid     = get_server_parent($parent);
  my $hmc         = get_label( "HMC", $hmc_uid );

  #print "lpar ($parent, $parent_name, $hmc) s uuid:$uuid  ($vm_name) ma tyto taby : 111\n";
  my @vm_dir = ();
  my @tabs;
  if ( -d "$inputdir/data/$parent_name/$hmc/$vm_name" ) {
    opendir( DIR, "$inputdir/data/$parent_name/$hmc/$vm_name" ) || warn( "No directory $inputdir/data/$parent_name/$hmc/$vm_name found in file: " . __FILE__ . ":" . __LINE__ . "\n" ) && return;
    @vm_dir = readdir(DIR);
    closedir(DIR);
  }
  foreach my $file (@vm_dir) {
    if ( ($file) eq '.' || $file eq '..' ) { next; }

    #    print "file : $file\n";
    if ( $file =~ m/mem.mmm/ ) {
      push( @tabs, { "mem" => "Memory" } );    #Memory OS
    }
    elsif ( $file =~ m/cpu.mm/ ) {
      push( @tabs, { "oscpu" => "CPU OS" } );    #CPU OS
    }
    elsif ( $file =~ m/pgs/ ) {
      push( @tabs, { "pg1" => "Paging 1" } );    #Paging1
    }
    elsif ( $file =~ m/pg2/ ) {
      push( @tabs, { "pg2" => "Paging 2" } );    #Paging2
    }
    elsif ( $file =~ m/lan.mmm/ ) {
      push( @tabs, { "lan" => "LAN" } );         #LAN
    }
    elsif ( $file =~ m/san-.*mmm/ ) {
      push( @tabs, { "san" => "SAN" } );
    }
    elsif ( $file =~ m/FS/ ) {
      push( @tabs, { "FS" => "FS" } );
    }
    elsif ( $file =~ m/san_resp.*mmm/ ) {
      push( @tabs, { "san_resp" => "SAN RESP" } );
    }
    else {
      @tabs = ();
    }

    #print "filepath vm_dir : $inputdir/data/$parent_name/$hmc/$vm_name/$file\n";
  }

  #add standard tabs
  return \@tabs;
}

sub get_some_label {
  my $type = shift;    # type = VM / POOL / SERVER
  my $uuid = shift;    # uuid = uuid(md5 hash)
  if ( $type eq "SERVER" ) {
    return $SERV->{$uuid}{label};
  }
  elsif ( $type eq "POOL" ) {
    return "SharedPool$POOLS->{$uuid}{id}";
  }
  elsif ( $type =~ "VM" ) {
    return $VMS->{$uuid}{label};
  }
}

sub lpar_id_to_name {
  my $server_name = shift;
  my $lpar_id     = shift;
  my $CNF         = shift;
  if ( !defined $lpar_id     || $lpar_id eq "" )     { Xorux_lib::error( "Not defined lpar_id " . __FILE__ . ":" . __LINE__ . "\n" );     return ""; }
  if ( !defined $server_name || $server_name eq "" ) { Xorux_lib::error( "Not defined server_name " . __FILE__ . ":" . __LINE__ . "\n" ); return ""; }

  #print "Reading file : $inputdir/tmp/restapi/HMC_LPARS_$server_name\_conf.json at ".__FILE__.":".__LINE__."\n";
  my $info = {};
  if ( defined $CNF && ref($CNF) eq "HASH" ) {
    $info = $CNF->{vms} if ( defined $CNF->{vms} );
  }
  foreach my $lpar_uid ( keys %{$info} ) {
    my $lpar         = $info->{$lpar_uid};
    my $lparname     = $lpar->{name};
    my $partition_id = $lpar->{PartitionID};
    if ( $lpar_id eq $partition_id ) {
      return $lparname;
    }
  }
  return "";
}

sub get_server_uid {
  my $in = shift;
  foreach my $srv_uid ( keys %{$SERV} ) {
    if ( $SERV->{$srv_uid}{label} eq $in ) {
      return $srv_uid;
    }
  }
}

sub get_item_uid {
  my @keys_servers = keys %{$SERV};
  ( $SERV, $CONF ) = init() if ( !( defined $CONF->{servers} ) );
  my $print     = 0;
  my $params    = shift;
  my $uid_type  = "undefined";
  my $item_type = lc( $params->{type} );
  my $label     = $params->{label};
  my $parent    = $params->{parent};
  my $items;

  if    ( $item_type eq "vm" )         { $uid_type = "vms"; }
  elsif ( $item_type eq "shpool" )     { $uid_type = "pools"; }
  elsif ( $item_type eq "pool" )       { $uid_type = "servers"; }
  elsif ( $item_type eq "pool-total" ) { $uid_type = "servers"; }
  elsif ( $item_type eq "memory" )     { $uid_type = "servers"; }
  elsif ( $item_type eq "server" )     { $uid_type = "servers"; }
  elsif ( $item_type =~ "lan-aggr" )   { $uid_type = "servers"; }
  elsif ( $item_type =~ "san-aggr" )   { $uid_type = "servers"; }
  elsif ( $item_type =~ "sas-aggr" )   { $uid_type = "servers"; }
  elsif ( $item_type =~ "hea-aggr" )   { $uid_type = "servers"; }
  elsif ( $item_type =~ "sri-aggr" )   { $uid_type = "servers"; }
  elsif ( $item_type =~ "vm-aggr" )    { $uid_type = "servers"; }
  elsif ( $item_type =~ "lan" )        { $uid_type = "LAN"; }
  elsif ( $item_type =~ "san" )        { $uid_type = "SAN"; }
  elsif ( $item_type =~ "sas" )        { $uid_type = "SAS"; }
  elsif ( $item_type =~ "hea" )        { $uid_type = "HEA"; }
  elsif ( $item_type =~ "sri" )        { $uid_type = "SRI"; }

  foreach my $uid ( keys %{ $CONF->{$uid_type} } ) {

    #print STDERR Dumper $CONF->{$uid_type} if ($uid_type eq "pools");
    if ( $uid_type eq 'pools' ) {    #shared pools don't have label in configuration but id/name.
      my $id = $label;
      $id =~ s/SharedPool//g;
      return $uid if ( $id eq $CONF->{$uid_type}{$uid}{id} && $parent eq $CONF->{$uid_type}{$uid}{parent} );
    }
    elsif ( $uid_type eq "LAN" || $uid_type eq "SAS" || $uid_type eq "SAN" || $uid_type eq "HEA" ) {

      #return $uid if ($label eq $CONF->{$uid_type}{$uid}{label});
      if ( $ENV{XORMON} ) {
        my $str = "$CONF->{$uid_type}{$uid}{partition} $CONF->{$uid_type}{$uid}{ent}";
        return $uid if ( $label eq $str || $label eq $CONF->{$uid_type}{$uid}{label} );
      }
      else {
        return $uid if ( $label eq $CONF->{$uid_type}{$uid}{label} );
      }
    }
    else {    #find label and return uid if label eq the conf label
      return $uid if ( defined $CONF->{$uid_type}{$uid}{label} && defined $label && $label eq $CONF->{$uid_type}{$uid}{label} );
    }
  }
  return "not_found";
}

sub get_status {
  my $type = shift;
  my $id   = shift;
  if ( $type eq 'VM' ) {
    my $rrd_file             = get_filepath_rrd( { type => $type, uid => $id, ext => 'rrm' } );
    my $rrd_file_created_ago = Xorux_lib::file_time_diff($rrd_file);
    if ( $rrd_file_created_ago && $rrd_file_created_ago < 3600 ) {
      return "L";
    }
    else {
      return "R";
    }
  }
}

sub getPartitionState {
  my $id             = shift;
  my $PartitionState = "unknown";
  foreach my $vm_id ( keys %{ $CONF->{vms} } ) {
    if ( $vm_id eq $id ) {
      $PartitionState = $CONF->{vms}{$vm_id}{state};
      if ( defined $PartitionState ) {
        return $PartitionState;
      }
    }
  }
  if ( !defined $PartitionState ) {
    $PartitionState = get_status( 'VM', $id );
    if ( $PartitionState eq "L" ) {
      return "rrd_current";
    }
    else {
      return "rrd_not_current";
    }
  }
}

sub update_conf {
  my $local_conf                      = shift;
  my $last_conf_generated_seconds_ago = Xorux_lib::file_time_diff($power_conf);

  # if power_conf.storable exists and it's new -> load it
  if ( -e $power_conf && Xorux_lib::file_time_diff($power_conf) <= $actual_power_conf_in_seconds ) {
    return Storable::retrieve($power_conf);
  }

  # if power_conf.storable exists and it is not new -> load it and add the currently found data
  my $history_CONF = {};
  $history_CONF = Storable::retrieve($power_conf) if ( -e $power_conf );
  foreach my $type ( keys %{$local_conf} ) {
    if ( ref( $local_conf->{$type} ) eq "HASH" ) {
      foreach my $item_uid ( keys %{ $local_conf->{$type} } ) {
        $history_CONF->{$type}{$item_uid} = $local_conf->{$type}{$item_uid};
        $history_CONF->{$type}{$item_uid}{last_update} = time;
      }
    }
    if ( ref( $local_conf->{$type} ) eq "ARRAY" ) {
      foreach my $item ( @{ $local_conf->{$type} } ) {
        foreach my $item_uid ( keys %{$item} ) {
          my $item_conf = $item->{$item_uid};
          $item_conf->{last_update} = time;
          push( @{ $history_CONF->{$type} }, $item_conf );
        }
      }
    }
  }

  # write the content into power_conf.storable file and return it
  Storable::store( $history_CONF, $power_conf ) || warn "Cannot write to file in " . __FILE__ . ":" . __LINE__ . "\n";
  return $history_CONF;
}

sub getServerCount {
  my $hmc_uid      = shift;
  my $hmc          = get_label( "HMC", $hmc_uid );
  my $server_count = scalar keys %{$SERV};
  return $server_count;
}

sub getLparCount {
  my $hmc_uid      = shift;
  my $hmc          = get_label( "HMC", $hmc_uid );
  my $server_count = scalar keys %{$SERV};
  my $lpars_count  = 0;
  foreach my $server_uid ( keys %{$SERV} ) {

    #    if ( ! HmcServerRelated ($server_uid, $hmc_uid) ){ next; }
    my $lpars_on_server = get_items( 'VM', $server_uid );
    foreach my $lpar ( @{$lpars_on_server} ) {
      my $lpar_id     = ( keys %{$lpar} )[0];
      my $lpar_status = getPartitionState($lpar_id);
      if ( $lpar_status =~ m/running/ ) {
        $lpars_count++;
      }
    }
  }
  return $lpars_count;
}

sub get_dictionary {
  my $dict;

  #server
  $dict->{server}{serial_num}       = "SerialNumber";
  $dict->{server}{SerialNumber}     = "serial_num";
  $dict->{server}{PrimaryIPAddress} = "ipaddr";
  $dict->{server}{ipaddr}           = "PrimaryIPAddress";
  $dict->{server}{State}            = "state";
  $dict->{server}{state}            = "State";
  $dict->{server}{DetailedState}    = "detailed_state";
  $dict->{server}{detailed_state}   = "DetailedState";
  $dict->{server}{SystemTime}       = "sys_time";
  $dict->{server}{sys_time}         = "SystemTime";

  #pool processor
  $dict->{server}{"ConfigurableSystemProcessorUnits"}            = "configurable_sys_proc_units";
  $dict->{server}{"configurable_sys_proc_units"}                 = "ConfigurableSystemProcessorUnits";
  $dict->{server}{"CurrentAvailableSystemProcessorUnits"}        = "curr_avail_sys_proc_units";
  $dict->{server}{"curr_avail_sys_proc_units"}                   = "CurrentAvailableSystemProcessorUnits";
  $dict->{server}{"PendingAvailableSystemProcessorUnits"}        = "pend_avail_sys_proc_units";
  $dict->{server}{"pend_avail_sys_proc_units"}                   = "PendingAvailableSystemProcessorUnits";
  $dict->{server}{"InstalledSystemProcessorUnits"}               = "installed_sys_proc_units";
  $dict->{server}{"installed_sys_proc_units"}                    = "InstalledSystemProcessorUnits";
  $dict->{server}{"DeconfiguredSystemProcessorUnits"}            = "deconfig_sys_proc_units";
  $dict->{server}{"deconfig_sys_proc_units"}                     = "DeconfiguredSystemProcessorUnits";
  $dict->{server}{"MinimumProcessorUnitsPerVirtualProcessor"}    = "min_proc_units_per_virtual_proc";
  $dict->{server}{"min_proc_units_per_virtual_proc"}             = "MinimumProcessorUnitsPerVirtualProcessor";
  $dict->{server}{"MaximumAllowedVirtualProcessorsPerPartition"} = "max_virtual_procs_per_lpar";
  $dict->{server}{"max_virtual_procs_per_lpar"}                  = "MaximumAllowedVirtualProcessorsPerPartition";

  #shared pools
  $dict->{pool}{"name"}                            = "PoolName";
  $dict->{pool}{"PoolName"}                        = "name";
  $dict->{pool}{"shared_proc_pool_id"}             = "PoolID";
  $dict->{pool}{"PoolID"}                          = "shared_proc_pool_id";
  $dict->{pool}{"curr_reserved_pool_proc_units"}   = "CurrentReservedProcessingUnits";
  $dict->{pool}{"CurrentReservedProcessingUnits"}  = "curr_reserved_pool_proc_units";
  $dict->{pool}{"max_pool_proc_units"}             = "MaximumProcessingUnits";
  $dict->{pool}{"MaximumProcessingUnits"}          = "max_pool_proc_units";
  $dict->{pool}{"pend_reserved_pool_proc_units"}   = "PendingReserverdProcessingUnits";
  $dict->{pool}{"PendingReserverdProcessingUnits"} = "pend_reserved_pool_proc_units";

  #memory
  $dict->{memory}{"configurable_sys_mem"}         = "ConfigurableSystemMemory";
  $dict->{memory}{"ConfigurableSystemMemory"}     = "configurable_sys_mem";
  $dict->{memory}{"pend_avail_sys_mem"}           = "PendingAvailableSystemMemory";
  $dict->{memory}{"PendingAvailableSystemMemory"} = "pend_avail_sys_mem";
  $dict->{memory}{"curr_avail_sys_mem"}           = "CurrentAvailableSystemMemory";
  $dict->{memory}{"CurrentAvailableSystemMemory"} = "curr_avail_sys_mem";
  $dict->{memory}{"installed_sys_mem"}            = "InstalledSystemMemory";
  $dict->{memory}{"InstalledSystemMemory"}        = "installed_sys_mem";
  $dict->{memory}{"deconfig_sys_mem"}             = "DeconfiguredSystemMemory";
  $dict->{memory}{"DeconfiguredSystemMemory"}     = "deconfig_sys_mem";
  $dict->{memory}{"sys_firmware_mem"}             = "SYSTEM_FIRMWARE_MEM";
  $dict->{memory}{"SYSTEM_FIRMWARE_MEM"}          = "sys_firmware_mem";
  $dict->{memory}{"mem_region_size"}              = "MemoryRegionSize";
  $dict->{memory}{"MemoryRegionSize"}             = "mem_region_size";

  #vms
  $dict->{vm}{"PartitionName"}                                           = "name";
  $dict->{vm}{"name"}                                                    = "PartitionName";
  $dict->{vm}{"PartitionType"}                                           = "vm_env";
  $dict->{vm}{"vm_env"}                                                  = "PartitionType";
  $dict->{vm}{"PartitionState"}                                          = "state";
  $dict->{vm}{"state"}                                                   = "PartitionState";
  $dict->{vm}{"ResourceMonitoringControlOperatingSystemShutdownCapable"} = "resource_config";
  $dict->{vm}{"resource_config"}                                         = "ResourceMonitoringControlOperatingSystemShutdownCapable";
  $dict->{vm}{"OperatingSystemVersion"}                                  = "os_version";
  $dict->{vm}{"os_version"}                                              = "OperatingSystemVersion";
  $dict->{vm}{"LogicalSerialNumber"}                                     = "logical_serial_num";
  $dict->{vm}{"logical_serial_num"}                                      = "LogicalSerialNumber";

  return $dict;
}

sub md5_string {
  my $data = shift;
  my $out  = md5_hex($data);
  return $out;
}

sub handle_db_error {
  my $error = shift;
  Xorux_lib::error("SQLite error: $error");
  return 1;
}

sub parse_servername_from_filename {
  my $in = shift;
  ( undef, undef, my $servername, undef ) = split( "_", $in );
  ( $servername, undef ) = split( "_", $servername );
  return $servername;
}

sub init {
  my $server_configuration_file = {};
  my $env_configuration_file    = {};

  if ( $ENV{DEMO} ) {
    my $b = Storable::retrieve("$inputdir/tmp/power_fake.storable");
    my $a = Storable::retrieve("$inputdir/tmp/servers_fake.storable");
    return ( $a, $b );
  }

  if ( Xorux_lib::file_time_diff($power_conf) >= 3600 || Xorux_lib::file_time_diff($power_conf) == 0 || Xorux_lib::file_time_diff($servers_conf) >= 3600 || Xorux_lib::file_time_diff($servers_conf) == 0 ) {

    #print STDERR "Generating new configuration serv, conf\n";
    $server_configuration_file = get_servers();
    $SERV                      = $server_configuration_file;
    $env_configuration_file    = get_conf();
    $CONF                      = $env_configuration_file;
    eval {
      my @data     = keys %{$server_configuration_file};
      my $data_ok  = scalar @data;
      my @data2    = keys %{ $env_configuration_file->{'servers'} };
      my $data2_ok = scalar @data2;
      if ( $data_ok && $data2_ok ) {
        Storable::store( $server_configuration_file, $servers_conf ) if ( defined keys %{$server_configuration_file} );
        Storable::store( $env_configuration_file,    $power_conf )   if ( defined keys %{ $env_configuration_file->{servers} } );

        #Xorux_lib::write_json ("/tmp/servers_conf.json", $SERV) if (defined $server_configuration_file);
        #Xorux_lib::write_json ("/tmp/power_conf.json", $CONF) if (defined $env_configuration_file);
      }
    };
  }
  else {
    eval {
      $server_configuration_file = Storable::retrieve($servers_conf) if ( -e $servers_conf );
      $env_configuration_file    = Storable::retrieve($power_conf)   if ( -e $power_conf );
    };
    if ($@) {
      warn("*****WARNING*****\n");
      warn("Cannot retrieve configuration files - remove them => 'cd $inputdir; rm tmp/power_conf.storable tmp/servers_conf.storable;'\n");
    }
    $SERV = $server_configuration_file;
    $CONF = $env_configuration_file;
  }
  return ( $server_configuration_file, $env_configuration_file );
}

1;

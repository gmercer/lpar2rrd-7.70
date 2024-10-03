# orvm-json2rrd.pl
# store OracleVM data retrieved from XAPI into RRDs

use 5.008_008;

use strict;
use warnings;

use Data::Dumper;
use File::Copy;
use JSON qw(decode_json encode_json);
use RRDp;
use Xorux_lib qw(error write_json);
use OracleVmDataWrapper;
use OracleVmLoadDataModule;
use POSIX ":sys_wait_h";

defined $ENV{INPUTDIR} || Xorux_lib::error( " INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg " . __FILE__ . ":" . __LINE__ ) && exit 1;
my $upgrade = defined $ENV{UPGRADE} ? $ENV{UPGRADE} : 0;

# data file paths
my $inputdir            = $ENV{INPUTDIR};
my $version             = "$ENV{version}";
my $oraclevm_dir        = "$inputdir/data/OracleVM";
my $iostats_dir         = "$oraclevm_dir/iostats";
my $rrd_filepath_server = "$oraclevm_dir/server";
my $rrd_filepath_vm     = "$oraclevm_dir/vm";
my $metadata_dir        = "$oraclevm_dir/metadata";
my $metadata_file       = "$oraclevm_dir/conf.json";
my $tmpdir              = "$inputdir/tmp";
my $etcdir              = "$inputdir/etc";
my $metadata_tmp_file   = "$metadata_file-part";
my $touch_file          = "$inputdir/tmp/ORVM_genconf.touch";
my $run_touch_file      = "$inputdir/tmp/$version-oraclevm";    # for generating menu
my $host_json_file      = "$etcdir/web_config/hosts.json";
my $rrdtool             = $ENV{RRDTOOL};
my $act_time            = time;

my $LPAR2RRD_FORK_MAX = defined $ENV{LPAR2RRD_FORK_MAX} && $ENV{LPAR2RRD_FORK_MAX} =~ /^\d{1,3}$/ ? $ENV{LPAR2RRD_FORK_MAX} : 16;
my %metadata_loaded;
my %metadata;
my %processed_on_host;
my %conf_values;
my %nic_parent_map;
my %hash_metadata;
my $rrd_start_time;
my $data;
my $db_hostname;

#########################################################################################
unless ( -d $oraclevm_dir ) {
  mkdir( "$oraclevm_dir", 0755 ) || Xorux_lib::error( "Cannot mkdir $oraclevm_dir: $!" . __FILE__ . ":" . __LINE__ ) && exit;
}
unless ( -d $rrd_filepath_vm ) {
  mkdir( "$rrd_filepath_vm", 0755 ) || Xorux_lib::error( "Cannot mkdir $rrd_filepath_vm: $!" . __FILE__ . ":" . __LINE__ ) && exit;
}

unless ( -d $rrd_filepath_server ) {
  mkdir( $rrd_filepath_server, 0755 ) || Xorux_lib::error( "Cannot mkdir $rrd_filepath_server: $!" . __FILE__ . ":" . __LINE__ ) && exit;
}

unless ( -d $metadata_dir ) {
  mkdir( $metadata_dir, 0755 ) || Xorux_lib::error( "Cannot mkdir $metadata_dir: $!" . __FILE__ . ":" . __LINE__ ) && exit;
}

unless ( -d $iostats_dir ) {
  print "orvm-json2rrd.pl : no iostats dir, skip\n";
  exit 1;
}

update_backup_file();
load_metadata();
load_perf_data();

exit 0;

sub load_perf_data {
  my @pids;
  my $pid;

  my $rrdtool_version = 'Unknown';
  $_ = `rrdtool`;
  if (/^RRDtool ([1-9]*\.[0-9]*(\.[0-9]*)?)/) {
    $rrdtool_version = $1;
  }
  print "RRDp    version   : $RRDp::VERSION \n";
  print "RRDtool version   : $rrdtool_version\n";

  opendir( DH, $iostats_dir ) || Xorux_lib::error("Could not open '$iostats_dir' for reading '$!'\n") && exit;
  my @files = sort( grep /perf/, readdir DH );
  closedir(DH);

  my $file_count = scalar @files;
  my $fork_no    = $file_count > $LPAR2RRD_FORK_MAX ? $LPAR2RRD_FORK_MAX : $file_count;

  print "orvm-json2rrd.pl : processing $file_count perf files with $fork_no forks\n";

  my $i = 0;
  while ( $i < $fork_no ) {
    unless ( defined( $pid = fork() ) ) {
      Xorux_lib::error( "Error: failed to fork:" . __FILE__ . ":" . __LINE__ );
      next;
    }
    else {
      if ($pid) {
        push @pids, $pid;
        $i++;
      }
      else {
        last;
      }
    }
  }

  unless ($pid) {
    while ( $i < $file_count ) {
      load_perf_file( $files[$i] );
      $i += $LPAR2RRD_FORK_MAX;
    }

    exit 0;
  }

  for $pid (@pids) {
    waitpid( $pid, 0 );
  }

  return 1;
}

sub load_perf_file {
  my $file = shift;
  my ( $code, $ref );

  RRDp::start "$rrdtool";

  # read perf file
  if ( -f "$iostats_dir/$file" ) {
    ( $code, $ref ) = Xorux_lib::read_json("$iostats_dir/$file");
    backup_file($file);

    unless ($code) {
      print "orvm-json2rrd.pl : file $file cannot be loaded\n";
      Xorux_lib::error( "Perf file $file cannot be loaded " . __FILE__ . ":" . __LINE__ );
      return 0;
    }
  }

  $db_hostname = $1;

  #unless ( $metadata_loaded{ $db_hostname } ) {
  #  print "ovirt-json2rrd.pl : no metadata for host $db_hostname, skipping file $file\n";
  #  Xorux_lib::error( "No metadata for host $db_hostname, perf file $file cannot be processed " . __FILE__ . ":" . __LINE__ );
  #  return 0;
  #}

  $data = $ref;
  print "orvm-json2rrd.pl : processing file $file\n";

  #print Dumper $data;

  eval {
    ######## create or update VM/SERVER only CPU,MEM
    foreach my $type ( keys %{$data} ) {
      if ( $type !~ /^server$|^vm$/ ) { next; }
      foreach my $uuid ( keys %{ $data->{$type} } ) {
        my $perf_data = $data->{$type}{$uuid};
        my $rrd_path;
        if ( $type =~ /^server$/ ) {
          $rrd_path = OracleVmDataWrapper::get_filepath_rrd( { type => $type, uuid => $uuid, skip_acl => 1 } );
        }
        elsif ( $type =~ /^vm/ ) {
          $rrd_path = OracleVmDataWrapper::get_filepath_rrd( { type => $type, uuid => $uuid, skip_acl => 1 } );
        }
        if ( defined $rrd_path && $rrd_path eq '' ) { next; }
        unless ( -f $rrd_path ) {
          my $directory_uuid = $rrd_path;
          $directory_uuid =~ s/sys\.rrd//g;
          unless ( -d "$directory_uuid" ) {
            mkdir("$directory_uuid") || Xorux_lib::error( " Cannot mkdir $directory_uuid: $!" . __FILE__ . ":" . __LINE__ );
          }
          OracleVmLoadDataModule::create_rrd( $rrd_path, $act_time, $type );
        }

        # update RRDs
        if ( $type eq 'server' ) {
          OracleVmLoadDataModule::update_rrd_server( $rrd_path, $perf_data, $hash_metadata{specification}{server}{$uuid} );
        }
        elsif ( $type eq 'vm' ) {
          OracleVmLoadDataModule::update_rrd_vm( $rrd_path, $perf_data, $hash_metadata{specification}{vm}{$uuid} );
        }

      }
    }

    ###### create or update SERVER and VM net and disk statistic
    foreach my $type ( keys %{$data} ) {
      if ( $type !~ /^server_net$|^server_disk$|^vm_disk$|^vm_net$/ ) { next; }
      foreach my $uuid ( keys %{ $data->{$type} } ) {
        my $perf_data = $data->{$type}{$uuid};
        foreach my $component_name ( keys %{ $data->{$type}{$uuid} } ) {
          my $rrd_path;

          # filepath load
          #$component_name =~ s/\.iso|\.img//g;
          if ( $type =~ /^server_net$/ ) {
            $rrd_path = OracleVmDataWrapper::get_filepath_rrd( { type => $type, uuid => $uuid, component_name => $component_name, skip_acl => 1 } );
          }
          elsif ( $type =~ /^server_disk$/ ) {
            $rrd_path = OracleVmDataWrapper::get_filepath_rrd( { type => $type, uuid => $uuid, component_name => $component_name, skip_acl => 1 } );
          }
          elsif ( $type =~ /^vm_disk$/ ) {
            $rrd_path = OracleVmDataWrapper::get_filepath_rrd( { type => $type, uuid => $uuid, component_name => $component_name, skip_acl => 1 } );
          }
          elsif ( $type =~ /^vm_net$/ ) {
            $rrd_path = OracleVmDataWrapper::get_filepath_rrd( { type => $type, uuid => $uuid, component_name => $component_name, skip_acl => 1 } );
          }

          # create RRD
          unless ( -f $rrd_path ) {
            OracleVmLoadDataModule::create_rrd( $rrd_path, $act_time, $type );

            #print Dumper $perf_data;
          }

          # update RRDs
          elsif ( $type eq 'server_net' ) {
            OracleVmLoadDataModule::update_rrd_server_net( $rrd_path, $perf_data, $component_name );

            #print Dumper $perf_data;
          }
          elsif ( $type eq 'server_disk' ) {
            OracleVmLoadDataModule::update_rrd_server_disk( $rrd_path, $perf_data, $component_name );

            #print Dumper $perf_data;
          }
          elsif ( $type eq 'vm_disk' ) {
            OracleVmLoadDataModule::update_rrd_vm_disk( $rrd_path, $perf_data, $component_name );

            #print Dumper $perf_data;
          }
          elsif ( $type eq 'vm_net' ) {

            #print "$rrd_path,$component_name!!!\n";
            OracleVmLoadDataModule::update_rrd_vm_net( $rrd_path, $perf_data, $component_name );

            #print Dumper $perf_data;
          }
        }
      }
    }
  };
  if ($@) {
    Xorux_lib::error( "Error while saving data from  $file to RRDs: $@ : " . __FILE__ . ":" . __LINE__ );
  }

  RRDp::end;
  return 1;
}

################################################################################
sub load_metadata {
  my $save_conf_flag = check_configuration_update();
  opendir( DH, $iostats_dir ) || Xorux_lib::error("Could not open '$iostats_dir' for reading '$!'\n") && exit;
  my @files = grep /.*serverinfo.*\.json|.*vminfo.*\.json|.*repository.*\.json|.*managerinfo.*\.json/, readdir DH;
  closedir(DH);
  unless ( scalar @files ) {
    print "orvm-json2rrd.pl : no data files, skip\n";
    exit 1;
  }
  foreach my $file ( sort @files ) {
    my ( $code, $ref );
    if ( -f "$iostats_dir/$file" ) {
      ( $code, $ref ) = Xorux_lib::read_json("$iostats_dir/$file");
      backup_file($file);
    }

    if ( $save_conf_flag == 1 ) {

      # ZAPIS DO METADATA FILU!!!!!
      #open( JSON_FH, "> $metadata_file" ) || die "error: cannot save the metadata JSON\n";
      #print JSON_FH "$json_data\n";
      #close(JSON_FH);

      if ($code) {
        eval {
          $data = $ref;

          #print Dumper $data;
          #$db_hostname = $data->{db_hostname};
          print "orvm-json2rrd.pl : processing file $file\n";

          #unless ( defined $db_hostname ) {
          #  print "orvm-json2rrd.pl : missing hostname in file $file\n";
          #  Xorux_lib::error( "Missing hostname in file $file cannot be processed " . __FILE__ . ":" . __LINE__ );
          #  next;
          #}

          ##### Get OracleVM name from etc/hosts.json
          my @host_cfg_file;
          my ( $oraclevm_name, $ip_address, $host_uuid );
          if ( -f $host_json_file ) {
            my ( $code, $ref );
            my ( undef, $ip_test ) = split( /_/, $file );
            ( $code, $ref ) = Xorux_lib::read_json("$host_json_file");
            my $manager_data = $ref;
            foreach my $alias ( keys %{ $manager_data->{'platforms'}{'OracleVM'}{'aliases'} } ) {
              $ip_address = $manager_data->{'platforms'}{'OracleVM'}{'aliases'}{$alias}{'host'};
              $host_uuid  = $manager_data->{'platforms'}{'OracleVM'}{'aliases'}{$alias}{'uuid'};
              if ( $ip_test eq $ip_address ) {
                $oraclevm_name = $alias;
              }
            }
          }
          if ( $file =~ /serverinfo/ ) {
            load_servers( $oraclevm_name, $host_uuid );

            #unlink $file or Xorux_lib::error( "Cannot unlink $file: $! " . __FILE__ . ":" . __LINE__ );
          }
          if ( $file =~ /vminfo/ ) {
            load_vms();

            #unlink $file or Xorux_lib::error( "Cannot unlink $file: $! " . __FILE__ . ":" . __LINE__ );
          }
          if ( $file =~ /repository/ ) {
            load_repos();

            #unlink $file or Xorux_lib::error( "Cannot unlink $file: $! " . __FILE__ . ":" . __LINE__ );
          }
          if ( $file =~ /filesystem/ ) {
            load_fsy();

            #unlink $file or Xorux_lib::error( "Cannot unlink $file: $! " . __FILE__ . ":" . __LINE__ );
          }
          if ( $file =~ /manager/ ) {
            load_manager($oraclevm_name);

            #unlink $file or Xorux_lib::error( "Cannot unlink $file: $! " . __FILE__ . ":" . __LINE__ );
          }

          #print Dumper \%hash_metadata;
          Xorux_lib::write_json( $metadata_file, \%hash_metadata );

          #if ( Xorux_lib::write_json( $metadata_tmp_file, \%hash_metadata ) ) {
          #  $metadata_loaded{ $db_hostname } = 1;
          #}
        };
        if ($@) {
          Xorux_lib::error( "Error while saving conf_file from $file: $@ : " . __FILE__ . ":" . __LINE__ );
        }
      }
    }

    if ( keys %metadata_loaded ) {
      rename( $metadata_tmp_file, $metadata_file );
    }
  }
  return 1;

}

sub load_servers {
  my $oraclevm_name = shift;
  my $host_uuid     = shift;

  #print Dumper $data;
  if ( defined $data->{'server'} && ref( $data->{'server'} ) eq "ARRAY" ) {
    foreach ( @{ $data->{'server'} } ) {
      my $server_name       = $_->{'name'}[0];
      my $server_hostname   = $_->{'hostname'}[0];
      my $manager_uuid      = $_->{'managerUuid'}[0];
      my $mem_server        = $_->{'memory'}[0];
      my $usable_mem_server = $_->{'usableMemory'}[0];
      my $threads_server    = $_->{'threadsPerCore'}[0];
      my $enabled_cpu_cores = $_->{'enabledProcessorCores'}[0];
      my $cpu_sockets       = $_->{'populatedProcessorSockets'}[0];
      my $cpu_type          = $_->{'processorType'}[0];
      my $ip_addr           = $_->{'ipAddress'}[0];
      my $manufac           = $_->{'manufacturer'}[0];
      my $product_name      = $_->{'productName'}[0];
      my $serial_num        = $_->{'serialNumber'}[0];
      my $bios_version      = $_->{'biosVersion'}[0];
      my $server_uuid       = "";
      my $cyc1              = 0;
      my $cyc2              = 0;
      my $cyc3              = 0;
      ######### CHECK SUMMARY DATA FROM SERVER
      #print "==============\n";
      #print Dumper $_;
      #print "==============\n";
      #########
      if ( defined $_->{'serverPoolId'} && ref( $_->{'serverPoolId'} ) eq "ARRAY" ) {
        foreach my $server_pool_hash ( @{ $_->{'serverPoolId'} } ) {

          #print Dumper $server_pool_hash;
          my $server_pool_uuid = $server_pool_hash->{'value'}[0];
          my $server_pool_name = $server_pool_hash->{'name'}[0];
          if ( !exists $hash_metadata{'specification'}{'server_pool'}{$server_pool_uuid} ) {
            $hash_metadata{labels}{server_pool}{$server_pool_uuid} = $server_pool_name;
          }

          #print Dumper @{$hash_metadata{architecture}{manager_s}{$manager_uuid}{server_pool}};
          if ( !grep( /$server_pool_uuid/, @{ $hash_metadata{architecture}{manager_s}{$manager_uuid}{server_pool} } ) ) {
            push @{ $hash_metadata{architecture}{manager_s}{$manager_uuid}{server_pool} }, $server_pool_uuid;
          }
          foreach my $hypervisor_hash ( @{ $_->{'hypervisor'} } ) {
            my $hypervisor_type = $hypervisor_hash->{'type'}[0];
            my $hypervisor_vers = $hypervisor_hash->{'version'}[0];
            foreach my $server_hash ( @{ $_->{'id'} } ) {
              $server_uuid = $server_hash->{'value'}[0];
              chomp($server_uuid);
              $server_uuid =~ s/\://g;
              $hash_metadata{labels}{server}{$server_uuid}                               = $server_name;
              $hash_metadata{specification}{server}{$server_uuid}{hypervisor_type}       = $hypervisor_type;
              $hash_metadata{specification}{server}{$server_uuid}{hypervisor_name}       = $hypervisor_vers;
              $hash_metadata{specification}{server}{$server_uuid}{hostname}              = $server_hostname;
              $hash_metadata{specification}{server}{$server_uuid}{total_memory}          = $mem_server;
              $hash_metadata{specification}{server}{$server_uuid}{usable_memory}         = $usable_mem_server;
              $hash_metadata{specification}{server}{$server_uuid}{server_name}           = $server_name;
              $hash_metadata{specification}{server}{$server_uuid}{threads_percore}       = $threads_server;
              $hash_metadata{specification}{server}{$server_uuid}{enabledProcessorCores} = $threads_server;
              $hash_metadata{specification}{server}{$server_uuid}{cpu_sockets}           = $cpu_sockets;
              $hash_metadata{specification}{server}{$server_uuid}{cpu_type}              = $cpu_type;
              $hash_metadata{specification}{server}{$server_uuid}{ip_address}            = $ip_addr;
              $hash_metadata{specification}{server}{$server_uuid}{manufactur}            = $manufac;
              $hash_metadata{specification}{server}{$server_uuid}{product_name}          = $product_name;
              $hash_metadata{specification}{server}{$server_uuid}{serial_number}         = $serial_num;
              $hash_metadata{specification}{server}{$server_uuid}{bios_version}          = $bios_version;
              $hash_metadata{specification}{server}{$server_uuid}{parent_serverpool}     = $server_pool_uuid;
              $hash_metadata{architecture}{server_pool}{$server_pool_uuid}{parent}       = $manager_uuid;
              push @{ $hash_metadata{architecture}{server_pool}{$server_pool_uuid}{server} }, $server_uuid;
              push @{ $hash_metadata{architecture}{server_pool_config}{$server_pool_uuid} }, $server_uuid;
              push @{ $hash_metadata{architecture}{manager}{$manager_uuid}{server} }, $server_uuid;

              if ( !grep( /$manager_uuid/, @{ $hash_metadata{architecture}{hostcfg}{$host_uuid}{manager} } ) ) {
                push @{ $hash_metadata{architecture}{hostcfg}{$host_uuid}{manager} }, $manager_uuid;
              }
              foreach my $vm_hash ( @{ $_->{'vmIds'} } ) {
                my $vm_uuid = $vm_hash->{'value'}[0];
                my $vm_name = $vm_hash->{'name'}[0];
                $server_uuid =~ s/\://g;
                chomp( $vm_uuid, $vm_name );
                push @{ $hash_metadata{architecture}{server_pool}{$server_pool_uuid}{vm} }, $vm_uuid;
                push @{ $hash_metadata{arch_server}{server_pool}{$server_pool_uuid}{vm} },  $vm_uuid;
                push @{ $hash_metadata{architecture}{vms_server}{$server_uuid} },           $vm_uuid;
                push @{ $hash_metadata{architecture}{vms_server_pool}{$server_pool_uuid} }, $vm_uuid;
                push @{ $hash_metadata{architecture}{manager}{$manager_uuid}{vm} }, $vm_uuid;

                if ( !exists $hash_metadata{architecture}{server_pool}{$server_pool_uuid}{server} ) {

                  #push @{ $hash_metadata{architecture}{server_pool}{ $server_pool_uuid }{server} }, $server_uuid;
                  #$hash_metadata{architecture}{server_pool}{ $server_pool_uuid }{server}  = $server_uuid;
                }
              }
            }
          }
        }
      }

      #else{ ### STANDALONE SERRVER WITHOUR SERVER_POOL(CLUSTER)
      #  if ( defined $_->{'id'} && ref($_->{'id'}) eq "ARRAY" ){
      #    foreach my $server_hash( @{ $_->{'id'}} ) {
      #        $server_uuid = $server_hash->{'value'}[0];
      #        chomp ($server_uuid);
      #        $server_uuid =~ s/\://g;
      #        push @{ $hash_metadata{architecture}{standalone_server}},$server_uuid;
      #        if ( defined $_->{'vmIds'} && ref($_->{'vmIds'}) eq "ARRAY" ){
      #          foreach my $vm_hash( @{ $_->{'vmIds'}} ) {
      #            my $vm_uuid = $vm_hash->{'value'}[0];
      #            my $vm_name = $vm_hash->{'name'}[0];
      #            $server_uuid =~ s/\://g;
      #            chomp ($vm_uuid,$vm_name);
      #            push @{ $hash_metadata{arch_server_stand}{server}{$server_uuid}{vm} }, $vm_uuid;
      #          }
      #        }
      #        else{
      #          my $vm_uuid = "";
      #          push @{ $hash_metadata{arch_server_stand}{server}{$server_uuid}{vm} }, $vm_uuid;
      #        }
      #    }
      #  }
      #}
      foreach my $cpu_id ( @{ $_->{'cpuIds'} } ) {
        my $cpu_uuid = $cpu_id->{'value'}[0];
        my $cpu_name = $cpu_id->{'type'}[0];
        $cpu_uuid =~ s/\://g;
        $cpu_name =~ s/\:/===double-col===/g;
        $hash_metadata{specification}{server}{$server_uuid}{cpu_id}{$cpu_uuid} = $cpu_name;
        $cyc1++;
      }
      foreach my $eth_hash ( @{ $_->{'ethernetPortIds'} } ) {
        my $eth_id   = $eth_hash->{'value'}[0];
        my $eth_name = $eth_hash->{'name'}[0];
        $eth_id   =~ s/\://g;
        $eth_name =~ s/\:/===double-col===/g;
        $hash_metadata{specification}{server}{$server_uuid}{net_id}{$eth_id} = $eth_name;
        $cyc2++;
      }
      foreach my $stor_hash ( @{ $_->{'storageInitiatorIds'} } ) {
        my $stor_id   = $stor_hash->{'value'}[0];
        my $stor_name = $stor_hash->{'name'}[0];
        $stor_id   =~ s/\://g;
        $stor_name =~ s/\:/===double-col===/g;
        $hash_metadata{specification}{server}{$server_uuid}{stor_id}{$stor_id} = $stor_name;
        $cyc3++;
      }
    }
  }

}

sub load_vms {

  #  print Dumper $data;
  if ( defined $data->{'vm'} && ref( $data->{'vm'} ) eq "ARRAY" ) {
    foreach ( @{ $data->{'vm'} } ) {
      my $vm_name     = $_->{'name'}[0];
      my $curr_mem_vm = $_->{'currentMemory'}[0];
      my $mem_vm      = $_->{'memory'}[0];
      my $os_type     = $_->{'osType'}[0];
      my $cpu_count   = $_->{'cpuCount'}[0];
      my $domain_type = $_->{'vmDomainType'}[0];
      if ( defined $_->{'id'} && ref( $_->{'id'} ) eq "ARRAY" ) {
        foreach my $vm_hash ( @{ $_->{'id'} } ) {
          my $vm_uuid = $vm_hash->{'value'}[0];
          unless ( -d "$rrd_filepath_vm/$vm_uuid" ) {
            mkdir("$rrd_filepath_vm/$vm_uuid")
              || Xorux_lib::error( " Cannot mkdir $rrd_filepath_vm/$vm_uuid: $!" . __FILE__ . ":" . __LINE__ );
          }
          if ( defined $_->{'virtualNicIds'} && ref( $_->{'virtualNicIds'} ) eq "ARRAY" ) {
            foreach my $virtual_nic_hash ( @{ $_->{'virtualNicIds'} } ) {
              my $vn_nic_id   = $virtual_nic_hash->{'value'}[0];
              my $vn_nic_name = $virtual_nic_hash->{'name'}[0];
              $hash_metadata{labels}{vm}{$vm_uuid}                        = $vm_name;
              $hash_metadata{specification}{vm}{$vm_uuid}{vm_name}        = $vm_name;
              $hash_metadata{specification}{vm}{$vm_uuid}{current_memory} = $mem_vm;
              $hash_metadata{specification}{vm}{$vm_uuid}{memory}         = $mem_vm;
              $hash_metadata{specification}{vm}{$vm_uuid}{os_type}        = $os_type;
              $hash_metadata{specification}{vm}{$vm_uuid}{cpu_count}      = $cpu_count;
              $hash_metadata{specification}{vm}{$vm_uuid}{vn_nic_id}      = $vn_nic_id;
              $hash_metadata{specification}{vm}{$vm_uuid}{vn_nic_name}    = $vn_nic_name;
              $hash_metadata{specification}{vm}{$vm_uuid}{domain_type}    = $domain_type;

              if ( defined $_->{'serverId'} && ref( $_->{'serverId'} ) eq "ARRAY" ) {
                foreach my $server_hash ( @{ $_->{'serverId'} } ) {
                  my $server_uuid = $server_hash->{'value'}[0];
                  $server_uuid =~ s/\://g;
                  $hash_metadata{specification}{vm}{$vm_uuid}{parent_server} = $server_uuid;
                }
              }
              if ( defined $_->{'serverPoolId'} && ref( $_->{'serverPoolId'} ) eq "ARRAY" ) {
                foreach my $serverpool_hash ( @{ $_->{'serverPoolId'} } ) {
                  my $serverpool_uuid = $serverpool_hash->{'value'}[0];
                  $hash_metadata{specification}{vm}{$vm_uuid}{parent_server_pool} = $serverpool_uuid;
                }
              }

              #$hash_metadata{specification}{vm}{$vm_uuid}{parent_server_pool} = $vm_name;
            }
          }
        }
      }
    }
  }

}

sub load_repos {

  #print Dumper $data;
  if ( defined $data->{'repository'} && ref( $data->{'repository'} ) eq "ARRAY" ) {
    foreach ( @{ $data->{'repository'} } ) {
      my $repo_name = $_->{'name'}[0];
      foreach my $v_disk_id ( @{ $_->{'virtualDiskIds'} } ) {
        my $v_disk_uuid = $v_disk_id->{'value'}[0];
        my $v_disk_name = $v_disk_id->{'name'}[0];
        $v_disk_uuid =~ s/\.iso|\.img//g;
        $repo_name   =~ s/\.iso|\.img//g;
        $v_disk_uuid =~ s/\/dev\/mapper\///g;
        $repo_name   =~ s/\/dev\/mapper\///g;
        foreach my $fs_id ( @{ $_->{'fileSystemId'} } ) {
          my $fs_uuid = $fs_id->{'value'}[0];
          my $fs_name = $fs_id->{'name'}[0];
          $hash_metadata{labels}{fs}{$fs_uuid} = $fs_name;

          #$hash_metadata{labels}{repos_main}{$repo_name} = $v_disk_name;
          $hash_metadata{labels}{repos}{$v_disk_uuid}    = $v_disk_name;
          $hash_metadata{labels}{repos_main}{$repo_name} = $v_disk_name;
        }
      }
    }
  }
}

sub load_manager {
  my $oraclevm_name = shift;
  if ( defined $data->{'manager'} && ref( $data->{'manager'} ) eq "ARRAY" ) {
    foreach ( @{ $data->{'manager'} } ) {
      my $manager_uuid = $_->{'managerUuid'}[0];
      my $manager_name = $_->{'name'}[0];
      $hash_metadata{labels}{manager}{$manager_uuid} = $oraclevm_name;
    }
  }
}

sub load_fs {

  #print Dumper $data;
  if ( defined $data->{'filesystem'} && ref( $data->{'filesystem'} ) eq "ARRAY" ) {
    foreach ( @{ $data->{'filesystem'} } ) {

      #my $manager_uuid = $_->{'managerUuid'}[0];
      #my $manager_name = $_->{'name'}[0];
      #$hash_metadata{labels}{manager}{$manager_uuid} = $oraclevm_name;
    }
  }
}
###################################################################################################

sub check_configuration_update {
  my $save_conf_flag = 0;

  if ( !-f $touch_file ) {
    $save_conf_flag = 1;
    `touch $touch_file`;
    `touch $run_touch_file`;    # generate menu_ovirt.json
  }
  else {
    my $run_time  = ( stat($touch_file) )[9];
    my $hour_back = time - 3600;

    #print "$run_time--$hour_back--$touch_file\n";
    #my ( undef, undef, undef, $actual_day )   = localtime( time() );
    #my ( undef, undef, undef, $last_run_day ) = localtime( $run_time );
    #$save_conf_flag = !( $actual_day == $last_run_day && $upgrade == 0 );
    #print "$save_conf_flag,$actual_day -- $last_run_day -- $upgrade\n";
    if ( $run_time < $hour_back ) {
      $save_conf_flag = 1;
    }
    else {
      $save_conf_flag = 0;
    }
  }

  if ( $save_conf_flag == 1 ) {

    #my @old_files = <$iostats_dir/*.json>;

    print "orvm-json2rrd.pl : save new configuration files, " . localtime() . "\n";

    `touch $touch_file`;

    #foreach my $file ( @old_files ) {
    #if ($file =~ /perf/){next;}
    #  unlink $file or Xorux_lib::error( "Cannot unlink $file: $! " . __FILE__ . ":" . __LINE__ ); ########### ODKOMENTOVAT!!!
    #}
  }
  else {
    print "orvm-json2rrd.pl : don't save configuration files, " . localtime() . "\n";
  }

  return $save_conf_flag;
}

######################################################################################################

sub update_backup_file {
  my @old_files = <$tmpdir/OracleVM_*_last2.txt>;
  my @new_files = <$tmpdir/OracleVM_*_last1.txt>;

  foreach my $file (@old_files) {
    unlink $file or Xorux_lib::error( "Cannot unlink $file: $! " . __FILE__ . ":" . __LINE__ );
  }

  foreach my $file (@new_files) {
    my $target = $file;
    $target =~ s/_last1\.txt$/_last2.txt/;
    move( $file, $target ) or Xorux_lib::error( "Cannot unlink $file: $! " . __FILE__ . ":" . __LINE__ );
  }

  return 1;
}

sub backup_file {

  # expects file name for the file, that's supposed to be moved from iostats_dir, with file
  # name "hostname_datetime.json" to tmpdir
  my $src_file = shift;
  my $source   = "$iostats_dir/$src_file";
  $src_file =~ s/\.json//;
  my $target = "$tmpdir/$src_file\_last1.txt";

  move( $source, $target ) or Xorux_lib::error( "Cannot backup data $source: $!" . __FILE__ . ":" . __LINE__ );

  return 1;
}    ## sub backup_file


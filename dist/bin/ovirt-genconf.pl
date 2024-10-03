# ovirt-genconf.pl
# generate configuration from data/oVirt/configuration/*.json files and data/oVirt/metadata.json and save it as html pages

use 5.008_008;

use strict;
use warnings;

use JSON;
use Data::Dumper;

use Xorux_lib qw(error read_json write_json file_time_diff);
use OVirtDataWrapper;
use OVirtMenu;

defined $ENV{INPUTDIR} || warn( ' INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $upgrade        = defined $ENV{UPGRADE} ? $ENV{UPGRADE} : 0;
my $version        = "$ENV{version}";
my $inputdir       = $ENV{INPUTDIR};
my $main_data_dir  = "$inputdir/data/oVirt";
my $metadata_file  = "$main_data_dir/metadata.json";
my $conf_dir       = "$main_data_dir/configuration";
my $touch_file     = "$inputdir/tmp/oVirt_genconf.touch";
my $run_touch_file = "$inputdir/tmp/$version-ovirt";              # for generating menu
my $generate_time  = localtime();

# REST API metadata (storage volume id)
my $json_dir           = "$main_data_dir/iostats/restapi";
my $storage_volume_ids = get_rest_api_data();

# RRD tool init for reading perf data (capacity)
my $rrdtool = $ENV{RRDTOOL};
if ( !-f "$rrdtool" ) {
  warn( 'Set correct path to rrdtool binary, it does not exist here: ' . $rrdtool . ' ' . __FILE__ . ':' . __LINE__ );
}
require RRDp;
RRDp::start "$rrdtool";

my $hosts_cfg_file           = "$conf_dir/hosts.html";
my $vms_cfg_file             = "$conf_dir/vms.html";
my $storage_domains_cfg_file = "$conf_dir/storage_domains.html";
my $storage_vm_cfg_file      = "$conf_dir/storage_vms.html";
my $vm_disk_cfg_file         = "$conf_dir/vm_disks.html";

my $host_rows    = '';
my $vm_rows      = '';
my $sd_rows      = '';
my $sd_vm_rows   = '';
my $vm_disk_rows = '';

my @host_header = (
  'Datacenter',            'Cluster',        'Host name',       'FQDN or IP',        'Memory [GB]',
  'Swap [GB]',             'CPU model',      'Number of cores', 'Number of sockets', 'CPU speed [MHz]',
  'OS',                    'Kernel version', 'KVM version',     'Threads per core',
  'Hardware product name', 'Hardware serial number'
);
my @vm_header = (
  'Datacenter',        'Cluster', 'VM name', 'Type', 'Memory [GB]', 'CPU per socket',
  'Number of sockets', 'OS'
);
my @storage_domain_header = (
  'Datacenter', 'Storage domain name', 'Storage domain type', 'Storage type',
  'Size [GB]',  'Used [GB]',           'Free [GB]'
);
my @storage_domain_header_rest_api = (
  'Datacenter', 'Storage domain name', 'Storage domain type', 'Storage type', 'Volume ID',
  'Size [GB]',  'Used [GB]',           'Free [GB]'
);
my @storage_vm_header = ( 'Datacenter', 'Storage domain', 'Virtual disk', 'VM' );
my @vm_disk_header = (
  'Datacenter',     'VM',        'Storage domain',              'Virtual disk',
  'Allocated [GB]', 'Used [GB]', 'Total allocated [GB] per VM', 'Total used [GB] per VM'
);

unless ( -d $conf_dir ) {
  mkdir( $conf_dir, 0755 ) || warn( localtime() . ": Cannot mkdir $conf_dir: $!" . __FILE__ . ':' . __LINE__ );
}

if ( !-f $touch_file ) {
  `touch $touch_file`;
  `touch $run_touch_file`;    # generate menu_ovirt.json
  print 'ovirt-genconf.pl  : first run after install, ' . localtime() . "\n";
}
else {
  my $run_time = ( stat($touch_file) )[9];
  my ( undef, undef, undef, $actual_day )   = localtime( time() );
  my ( undef, undef, undef, $last_run_day ) = localtime($run_time);

  if ( $actual_day == $last_run_day && $upgrade == 0 ) {
    print 'ovirt-genconf.pl  : already ran today, skip' . "\n";
    exit 0;                   # run just once a day
  }
  else {
    `touch $touch_file`;
    `touch $run_touch_file`;    # generate menu_ovirt.json
    print 'ovirt-genconf.pl  : generate configuration, ' . localtime() . "\n";
  }
}

opendir( my $DH, $conf_dir ) || warn( localtime() . ": Could not open '$conf_dir' for reading '$!'\n" ) && exit;
my @files = grep /.*.json/, readdir $DH;
closedir $DH;

foreach my $file ( sort @files ) {
  my ( $code, $ref );

  if ( -f "$conf_dir/$file" ) {
    ( $code, $ref ) = Xorux_lib::read_json("$conf_dir/$file");
  }

  if ($code) {
    my $data = $ref;

    eval {
      my $act_time =
        defined $data->{timestamp}
        ? $data->{timestamp}
        : warn( localtime() . ': Missing timestamp on configuration ' . $file . ' ' . __FILE__ . ':' . __LINE__ );

      gen_hosts_html($data);
      gen_vms_html($data);
      gen_storage_domains_html( $data, $storage_volume_ids );
      gen_vm_disk_html($data);
    };
    if ($@) {
      warn( localtime() . ': Error while generating configuration file ' . "$file : $@ : " . __FILE__ . ':' . __LINE__ );
    }
  }
}

{
  # the storage-disk-vm table is generated from the shared $metadata_file with 'architecture' as a whole
  gen_storage_vm_html();
}

if ($host_rows) {
  open( my $HOSTH, '>', $hosts_cfg_file ) || warn( localtime() . ": Couldn't open file $hosts_cfg_file $!" . __FILE__ . ':' . __LINE__ );
  print $HOSTH ${ generate_table( \@host_header, \$host_rows ) };
  print $HOSTH "<br>\n";
  print $HOSTH 'It is updated once a day, last run: ' . $generate_time;
  close $HOSTH;
}

if ($vm_rows) {
  open( my $VMH, '>', $vms_cfg_file ) || warn( localtime() . ": Couldn't open file $vms_cfg_file $!" . __FILE__ . ':' . __LINE__ );
  print $VMH ${ generate_table( \@vm_header, \$vm_rows ) };
  print $VMH "<br>\n";
  print $VMH 'It is updated once a day, last run: ' . $generate_time;
  close $VMH;
}

if ($sd_rows) {
  open( my $SDH, '>', $storage_domains_cfg_file ) || warn( localtime() . ": Couldn't open file $storage_domains_cfg_file $!" . __FILE__ . ':' . __LINE__ );
  if ( defined $storage_volume_ids && %{$storage_volume_ids} ) {
    @storage_domain_header = @storage_domain_header_rest_api;
  }
  print $SDH ${ generate_table( \@storage_domain_header, \$sd_rows ) };
  print $SDH "<br>\n";
  print $SDH 'It is updated once a day, last run: ' . $generate_time;
  close $SDH;
}

if ($sd_vm_rows) {
  open( my $SDVMH, '>', $storage_vm_cfg_file ) || warn( localtime() . ": Couldn't open file $storage_vm_cfg_file $!" . __FILE__ . ':' . __LINE__ );
  print $SDVMH ${ generate_table( \@storage_vm_header, \$sd_vm_rows ) };
  print $SDVMH "<br>\n";
  print $SDVMH 'It is updated once a day, last run: ' . $generate_time;
  close $SDVMH;
}

if ($vm_disk_rows) {
  open( my $VMDH, '>', $vm_disk_cfg_file ) || warn( localtime() . ": Couldn't open file $vm_disk_cfg_file $!" . __FILE__ . ':' . __LINE__ );
  print $VMDH ${ generate_table( \@vm_disk_header, \$vm_disk_rows ) };
  print $VMDH "<br>\n";
  print $VMDH 'It is updated once a day, last run: ' . $generate_time;
  close $VMDH;
}

print 'ovirt-genconf.pl  : finish, ' . localtime() . "\n";
exit 0;

################################################################################

sub gen_hosts_html {
  my $data = shift;
  my $datacenter_name = defined $data->{datacenter}{datacenter_name} ? $data->{datacenter}{datacenter_name} : '';

  foreach my $host_uuid ( keys %{ $data->{host} } ) {
    my $host = $data->{host}{$host_uuid};

    my $cluster_name = defined $host->{cluster_name} ? $host->{cluster_name} : '';
    my $host_name    = defined $host->{host_name}    ? $host->{host_name}    : '';
    my $fqdn_or_ip   = defined $host->{fqdn_or_ip}   ? $host->{fqdn_or_ip}   : '';
    my $memory_size = defined $host->{memory_size_mb} ? sprintf "%.0f", $host->{memory_size_mb} / 1024 : '';
    my $swap_size   = defined $host->{swap_size_mb}   ? sprintf "%.0f", $host->{swap_size_mb} / 1024   : '';
    my $cpu_model         = defined $host->{cpu_model}              ? $host->{cpu_model}              : '';
    my $number_of_cores   = defined $host->{number_of_cores}        ? $host->{number_of_cores}        : '';
    my $number_of_sockets = defined $host->{number_of_sockets}      ? $host->{number_of_sockets}      : '';
    my $cpu_speed_mh      = defined $host->{cpu_speed_mh}           ? $host->{cpu_speed_mh}           : '';
    my $host_os           = defined $host->{host_os}                ? $host->{host_os}                : '';
    my $kernel_version    = defined $host->{kernel_version}         ? $host->{kernel_version}         : '';
    my $kvm_version       = defined $host->{kvm_version}            ? $host->{kvm_version}            : '';
    my $threads_per_core  = defined $host->{threads_per_core}       ? $host->{threads_per_core}       : '';
    my $hw_product_name   = defined $host->{hardware_product_name}  ? $host->{hardware_product_name}  : '';
    my $hw_serial_number  = defined $host->{hardware_serial_number} ? $host->{hardware_serial_number} : '';

    my $host_url = OVirtMenu::get_url( { type => 'host', id => $host_uuid } );
    my $host_link = "<a href=\"${host_url}\" class=\"backlink\"><b>${host_name}</b></a>";

    $host_rows .= ${
      generate_row(
        $datacenter_name, $cluster_name, $host_link, $fqdn_or_ip,
        $memory_size,     $swap_size,    $cpu_model, $number_of_cores,
        $number_of_sockets, $cpu_speed_mh,    $host_os, $kernel_version, $kvm_version,
        $threads_per_core,  $hw_product_name, $hw_serial_number
      )
    };
  }

  return 1;
}

sub gen_vms_html {
  my $data = shift;
  my $datacenter_name = defined $data->{datacenter}{datacenter_name} ? $data->{datacenter}{datacenter_name} : '';

  foreach my $vm_uuid ( keys %{ $data->{vm} } ) {
    my $vm = $data->{vm}{$vm_uuid};

    my $cluster_name = defined $vm->{cluster_name} ? $vm->{cluster_name} : '';
    my $vm_name      = defined $vm->{vm_name}      ? $vm->{vm_name}      : '';
    my $vm_type      = defined $vm->{vm_type}      ? $vm->{vm_type}      : '';
    my $memory_size       = defined $vm->{memory_size_mb}    ? sprintf "%.0f", $vm->{memory_size_mb} / 1024 : '';
    my $cpu_per_socket    = defined $vm->{cpu_per_socket}    ? $vm->{cpu_per_socket}                        : '';
    my $number_of_sockets = defined $vm->{number_of_sockets} ? $vm->{number_of_sockets}                     : '';
    my $operating_system  = defined $vm->{operating_system}  ? $vm->{operating_system}                      : '';

    my $vm_url = OVirtMenu::get_url( { type => 'vm', id => $vm_uuid } );
    my $vm_link = "<a href=\"${vm_url}\" class=\"backlink\"><b>${vm_name}</b></a>";

    $vm_rows .= ${
      generate_row(
        $datacenter_name, $cluster_name,      $vm_link, $vm_type, $memory_size,
        $cpu_per_socket,  $number_of_sockets, $operating_system
      )
    };
  }

  return 1;
}

sub gen_storage_domains_html {
  my $data            = shift;
  my $data_extra      = shift;
  my $datacenter_name = defined $data->{datacenter}{datacenter_name} ? $data->{datacenter}{datacenter_name} : '';

  foreach my $sd_uuid ( keys %{ $data->{storage_domain} } ) {
    my $sd = $data->{storage_domain}{$sd_uuid};

    my $storage_domain_name = defined $sd->{storage_domain_name} ? $sd->{storage_domain_name} : '';
    my $storage_domain_type = defined $sd->{storage_domain_type} ? $sd->{storage_domain_type} : '';
    my $storage_type        = defined $sd->{storage_type}        ? $sd->{storage_type}        : '';
    my $total_disk_size_gb  = defined $sd->{total_disk_size_gb}  ? $sd->{total_disk_size_gb}  : '';
    my $used_disk_size_gb   = defined $sd->{used_disk_size_gb}   ? $sd->{used_disk_size_gb}   : '';
    my $free_disk_size_gb   = defined $sd->{free_disk_size_gb}   ? $sd->{free_disk_size_gb}   : '';

    my $volume_ids;
    if ( defined $data_extra && %{$data_extra} ) {
      $volume_ids = defined $data_extra->{$sd_uuid} ? join( '<br>', @{ $data_extra->{$sd_uuid} } ) : '';
    }

    my $storage_domain_url = OVirtMenu::get_url( { type => 'storage_domain', id => $sd_uuid } );
    my $storage_domain_link = "<a href=\"${storage_domain_url}\" class=\"backlink\"><b>$storage_domain_name</b></a>";

    if ( defined $volume_ids ) {
      $sd_rows .= ${
        generate_row(
          $datacenter_name,    $storage_domain_link, $storage_domain_type, $storage_type, $volume_ids,
          $total_disk_size_gb, $used_disk_size_gb,   $free_disk_size_gb
        )
      };
    }
    else {
      $sd_rows .= ${
        generate_row(
          $datacenter_name,    $storage_domain_link, $storage_domain_type, $storage_type,
          $total_disk_size_gb, $used_disk_size_gb,   $free_disk_size_gb
        )
      };
    }
  }

  return 1;
}

sub gen_storage_vm_html {
  my $arch_vm = OVirtDataWrapper::get_conf_section('arch-vm');

  foreach my $datacenter_uuid ( @{ OVirtDataWrapper::get_uuids('datacenter') } ) {
    my $datacenter_label = OVirtDataWrapper::get_label( 'datacenter', $datacenter_uuid );

    my $count_storages = 0;
    foreach my $storage_domain_uuid ( @{ OVirtDataWrapper::get_arch( $datacenter_uuid, 'datacenter', 'storage_domain' ) } ) {
      my $storage_domain_label = OVirtDataWrapper::get_label( 'storage_domain', $storage_domain_uuid );
      my $storage_domain_url = OVirtMenu::get_url( { type => 'storage_domain', id => $storage_domain_uuid } );
      my $storage_domain_link = "<a href=\"${storage_domain_url}\" class=\"backlink\"><b>${storage_domain_label}</b></a>";
      $count_storages++;

      my $count_disks = 0;
      foreach my $disk_uuid ( @{ OVirtDataWrapper::get_arch( $storage_domain_uuid, 'storage_domain', 'disk' ) } ) {
        my $disk_label = OVirtDataWrapper::get_label( 'disk', $disk_uuid );
        my $disk_url = OVirtMenu::get_url( { type => 'disk', id => $disk_uuid } );
        my $disk_link = "<a href=\"${disk_url}\" class=\"backlink\"><b>${disk_label}</b></a>";
        $count_disks++;

        my $count_vms = 0;
        foreach my $vm_uuid ( keys %{$arch_vm} ) {
          if ( grep( /^$disk_uuid$/, @{ $arch_vm->{$vm_uuid}{disk} } ) ) {
            my $vm_label = OVirtDataWrapper::get_label( 'vm', $vm_uuid );
            my $vm_url = OVirtMenu::get_url( { type => 'vm', id => $vm_uuid } );
            my $vm_link = "<a href=\"${vm_url}\" class=\"backlink\"><b>${vm_label}</b></a>";
            $count_vms++;

            $sd_vm_rows .= ${ generate_row( $datacenter_label, $storage_domain_link, $disk_link, $vm_link ) };
          }
        }

        unless ($count_vms) {
          $sd_vm_rows .= ${ generate_row( $datacenter_label, $storage_domain_link, $disk_link, '' ) };
        }
      }

      unless ($count_disks) {
        $sd_vm_rows .= ${ generate_row( $datacenter_label, $storage_domain_link, '', '' ) };
      }
    }

    unless ($count_storages) {
      $sd_vm_rows .= ${ generate_row( $datacenter_label, '', '', '' ) };
    }
  }

  return 1;
}

# TODO remove
sub gen_vm_disk_html_0 {
  my $data            = shift;
  my $datacenter_name = defined $data->{datacenter}{datacenter_name} ? $data->{datacenter}{datacenter_name} : '';
  my $arch_vm         = OVirtDataWrapper::get_conf_section('arch-vm');

  foreach my $vm_uuid ( keys %{ $data->{vm} } ) {
    my $vm = $data->{vm}{$vm_uuid};

    my $cluster_name = defined $vm->{cluster_name} ? $vm->{cluster_name} : '';
    my $vm_name      = defined $vm->{vm_name}      ? $vm->{vm_name}      : '';
    my $vm_url = OVirtMenu::get_url( { type => 'vm', id => $vm_uuid } );
    my $vm_link = "<a href=\"${vm_url}\" class=\"backlink\"><b>${vm_name}</b></a>";

    my $disks = $arch_vm->{$vm_uuid}{disk};
    my @disk_links;
    my $disk_size_allocated = my $disk_size_used = my $disk_size_used_max = 0;
    foreach my $disk_uuid ( @{$disks} ) {
      my $disk_label = OVirtDataWrapper::get_label( 'disk', $disk_uuid );
      my $disk_url = OVirtMenu::get_url( { type => 'disk', id => $disk_uuid } );
      my $disk_link = "<a href=\"${disk_url}\" class=\"backlink\"><b>${disk_label}</b></a>";
      push @disk_links, $disk_link;

      my $disk = $data->{disk}{$disk_uuid};
      $disk_size_allocated += defined $disk->{vm_disk_size_mb} ? sprintf "%.1f", ( $disk->{vm_disk_size_mb} / 1024 ) : '';
      my $size = get_disk_space_perf($disk_uuid);
      $disk_size_used += $size;
    }

    $vm_disk_rows .= ${
      generate_row(
        $datacenter_name,     $vm_link, join( '<br>', @disk_links ),
        $disk_size_allocated, $disk_size_used
      )
    };
  }

  return 1;
}

sub gen_vm_disk_html {
  my $data            = shift;
  my $datacenter_name = defined $data->{datacenter}{datacenter_name} ? $data->{datacenter}{datacenter_name} : '';
  my $arch_vm         = OVirtDataWrapper::get_conf_section('arch-vm');
  my $arch_disk       = OVirtDataWrapper::get_conf_section('arch-disk');

  foreach my $vm_uuid ( keys %{ $data->{vm} } ) {
    my $vm = $data->{vm}{$vm_uuid};

    my $cluster_name = defined $vm->{cluster_name} ? $vm->{cluster_name} : '';
    my $vm_name      = defined $vm->{vm_name}      ? $vm->{vm_name}      : '';
    my $vm_url = OVirtMenu::get_url( { type => 'vm', id => $vm_uuid } );
    my $vm_link = "<a href=\"${vm_url}\" class=\"backlink\"><b>${vm_name}</b></a>";

    my $disks = $arch_vm->{$vm_uuid}{disk};
    my $disk_size_allocated_aggr = my $disk_size_used_aggr = 0;
    foreach my $disk_uuid ( @{$disks} ) {
      my $disk = $data->{disk}{$disk_uuid};
      $disk_size_allocated_aggr += defined $disk->{vm_disk_size_mb} ? sprintf "%.1f", ( $disk->{vm_disk_size_mb} / 1024 ) : '';
      my $size = get_disk_space_perf($disk_uuid);
      $disk_size_used_aggr += $size;
    }
    my $disk_size_allocated = my $disk_size_used = 0;
    foreach my $disk_uuid ( @{$disks} ) {
      my $storage_domain_uuid  = $arch_disk->{$disk_uuid}{parent};
      my $storage_domain_label = OVirtDataWrapper::get_label( 'storage_domain', $storage_domain_uuid );
      my $storage_domain_url   = OVirtMenu::get_url( { type => 'storage_domain', id => $storage_domain_uuid } );
      my $storage_domain_link  = "<a href=\"${storage_domain_url}\" class=\"backlink\"><b>${storage_domain_label}</b></a>";

      my $disk_label = OVirtDataWrapper::get_label( 'disk', $disk_uuid );
      my $disk_url = OVirtMenu::get_url( { type => 'disk', id => $disk_uuid } );
      my $disk_link = "<a href=\"${disk_url}\" class=\"backlink\"><b>${disk_label}</b></a>";

      my $disk = $data->{disk}{$disk_uuid};
      $disk_size_allocated = defined $disk->{vm_disk_size_mb} ? sprintf "%.1f", ( $disk->{vm_disk_size_mb} / 1024 ) : '';
      my $disk_size_used = get_disk_space_perf($disk_uuid);

      $vm_disk_rows .= ${
        generate_row(
          $datacenter_name,          $vm_link, $storage_domain_link, $disk_link,
          $disk_size_allocated,      $disk_size_used,
          $disk_size_allocated_aggr, $disk_size_used_aggr
        )
      };
    }
  }

  return 1;
}

################################################################################

sub get_rest_api_data {
  my %result;

  opendir( my $DH, $json_dir ) || return;
  my @files = grep /.*-storagedomains-last.json/, readdir $DH;
  closedir $DH;

  foreach my $file ( sort @files ) {
    my $conf = get_conf("$json_dir/$file");
    foreach my $sd ( @{ $conf->{storage_domain} } ) {
      my $sd_id = $sd->{id};
      foreach my $storage ( @{ $sd->{storage} } ) {
        foreach my $volume_group ( @{ $storage->{volume_group} } ) {
          foreach my $logical_units ( @{ $volume_group->{logical_units} } ) {
            foreach my $logical_unit ( @{ $logical_units->{logical_unit} } ) {
              my $lu_id = $logical_unit->{id};

              # the first character is (always?) an extra '3' so remove it
              $lu_id =~ s/^.//;
              push @{ $result{$sd_id} }, $lu_id;
            }
          }
        }
      }
    }
  }

  return \%result;
}

sub get_conf {
  my $conf_file  = shift;
  my %dictionary = ();
  {
    my $content;
    local $/;
    if ( open( my $fh, '<', "$conf_file" ) ) {
      $content = <$fh>;
      close($fh);
      %dictionary = %{ decode_json($content) };
    }
  }
  return \%dictionary;
}

################################################################################

sub get_disk_space_perf {
  my $uuid = shift;

  my $disk_rrd = OVirtDataWrapper::get_filepath_rrd( { type => 'disk', uuid => $uuid } );
  if ( -f $disk_rrd ) {
    my $start_time = "now-3600";
    my $end_time   = time();
    my $name_out   = "test";
    RRDp::cmd qq(graph "$name_out"
    "--start" "$start_time"
    "--end" "$end_time"
    "DEF:space_mb=$disk_rrd:vm_disk_size_mb:AVERAGE"
    "CDEF:space_gb=space_mb,1024,/"
    "PRINT:space_gb:AVERAGE: %6.1lf"
    );
    my $answer = RRDp::read;
    if ( $$answer =~ "ERROR" ) {
      error("Rrdtool error : $$answer");
      return;
    }
    my $aaa = $$answer;
    ( undef, my $disk ) = split( "\n", $aaa );
    $disk = nan_to_null($disk);
    chomp($disk);

    return $disk;    # $line_disk_usage;
  }

  return;
}

sub nan_to_null {
  my $number = shift;
  $number =~ s/NaNQ/0/g;
  $number =~ s/NaN/0/g;
  $number =~ s/-nan/0/g;
  $number =~ s/nan/0/g;    # rrdtool v 1.2.27
  $number =~ s/,/\./;
  $number =~ s/\s+//;
  return $number;
}

################################################################################

sub generate_row {
  my @values = @_;
  my $rows   = '';

  $rows .= "<tr>\n";
  foreach my $value (@values) {
    $value = '' unless defined $value;
    $rows .= "<td style=\"text-align:left; color:black;\" nowrap=\"\">$value</td>\n";
  }
  $rows .= "</tr>\n";

  return \$rows;
}

sub generate_table {
  my @header   = @{ shift @_ };
  my $rows     = ${ shift @_ };
  my $headline = shift;
  my $acc      = '';

  if ( $rows eq '' ) {
    return \$acc;
  }

  $acc .= "<center>\n";
  $acc .= defined $headline ? "<br><br><b>$headline:</b>\n" : "<br>\n";
  $acc .= "<table class =\"tabconfig tablesorter tablesorter-ice tablesorter7f0583dfe15c8 hasFilter\">\n";
  $acc .= "<thead>\n";
  $acc .= "<tr>\n";

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

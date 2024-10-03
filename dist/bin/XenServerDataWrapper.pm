# XenServerDataWrapper.pm
# interface for accessing XenServer data:
#   provides lists of objects (hosts, vms, pools,…), respective filepaths and metadata, such as labels
#   metadata can be stored in a JSON file or in an SQLite database
#     thus backends XenServerDataWrapperJSON and XenServerDataWrapperSQLite

package XenServerDataWrapper;

use strict;
use warnings;

use Data::Dumper;
use JSON;
use Xorux_lib;

require XenServerDataWrapperJSON;

# if $ENV{XORMON}: require XenServerDataWrapperSQLite;

# XorMon-only (ACL, TODO add XenServerDataWrapperSQLite as metadata source)
my $acl;
my $use_sql = 0;
if ( defined $ENV{XORMON} && $ENV{XORMON} ) {
  $use_sql = 1;

  require ACLx;
  $acl = ACLx->new();

  sub isGranted {
    my $uuid = shift;
    return $acl->isGranted( { hw_type => 'XENSERVER', item_id => $uuid, match => 'granted' } );
  }
}

defined $ENV{INPUTDIR} || warn( localtime() . ': INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ' . __FILE__ . ':' . __LINE__ ) && exit 1;

my $inputdir = $ENV{INPUTDIR};
my $wrkdir   = "$inputdir/data";

my $hosts_path = "$wrkdir/XEN";
my $vms_path   = "$wrkdir/XEN_VMs";
my $conf_file  = "$wrkdir/XEN_iostats/conf.json";

################################################################################

# TODO define types of objects "use constant …"

use constant TYPES => qw( vm host pool storage network );

################################################################################

sub get_filepath_rrd {

  # params: { type => '(vm|host|storage|network)', uuid => 'DEADBEEF' }
  #     optional flag skip_acl, optional legacy param id
  my $params = shift;

  return unless ( defined $params->{type} && defined $params->{uuid} );
  my ( $type, $uuid, $skip_acl );
  $type     = $params->{type};
  $uuid     = $params->{uuid};
  $skip_acl = ( defined $params->{skip_acl} ) ? $params->{skip_acl} : 0;

  my $filepath;
  if ( $type eq 'vm' ) {
    $filepath = "${vms_path}/$uuid.rrd";
  }
  elsif ( $type eq 'host' ) {
    $filepath = "${hosts_path}/$uuid/sys.rrd";
  }
  elsif ( $type eq 'storage' ) {

    # cover both call contexts: (a) host uuid and device id, (b) device uuid
    if ( defined $params->{id} ) {
      my $id = $params->{id};
      $filepath = "${hosts_path}/$uuid/disk-$id.rrd";

      # TODO translate ID to UUID for finer ACL check
    }
    else {
      my $short_uuid = shorten_sr_uuid($uuid);
      foreach my $host_uuid ( @{ get_parent( 'storage', $uuid ) } ) {
        $filepath = "${hosts_path}/${host_uuid}/disk-${short_uuid}.rrd";
        next unless ( -f $filepath );
      }
    }
  }
  elsif ( $type eq 'network' ) {

    # cover both call contexts: (a) host uuid and device id, (b) device uuid
    if ( defined $params->{id} ) {
      my $id = $params->{id};
      $filepath = "${hosts_path}/$uuid/lan-$id.rrd";

      # TODO translate ID to UUID for finer ACL check
    }
    else {
      my $pif_device = get_network_device($uuid);
      foreach my $host_uuid ( @{ get_parent( 'network', $uuid ) } ) {
        $filepath = "${hosts_path}/${host_uuid}/lan-${pif_device}.rrd";
        next unless ( -f $filepath );
      }
    }
  }
  else {
    return;
  }

  # ACL check
  if ( $use_sql && !$skip_acl ) {
    if ( !isGranted($uuid) ) {
      return;
    }
  }

  if ( defined $filepath ) {
    return $filepath;
  }
  else {
    return;
  }
}

################################################################################

#     get_items({ item_type   => $string1, # e.g. 'vm', 'pool', 'storage'
#                 parent_type => $string2, # e.g. 'pool', 'host'
#                 parent_uuid => $string3,
#                 item_mask   => $regex1,  # TODO
#                 parent_mask => $regex2   # TODO
#               });
#
# return: ( { uuid1 => 'label1' }, { uuid2 => 'label2' }, ... )

# get_items returns anything that is present on the host, but may not be running
# thus, the item may not have a performance (RRD) file
# that leads to issues when generating aggregated graphs, unless you always check the RRD filepath

sub get_items {
  my $params = shift;
  my $result;

  # unknown item type
  return unless ( defined $params->{item_type} );

  # TODO if ($use_sql) { $result = XenServerDataWrapperSQLite::get_items($params); }
  $result = XenServerDataWrapperJSON::get_items($params);

  if ($use_sql) {
    my @filtered_result;
    foreach my $item ( @{$result} ) {
      my %result_item = %{$item};
      my ( $uuid, $label ) = each %result_item;
      if ( $acl->isGranted( { hw_type => 'XENSERVER', item_id => $uuid } ) ) {
        push @filtered_result, $item;
      }
    }
    $result = \@filtered_result;
  }

  return $result;
}

sub is_active {
  return get_items( { item_type => 'host' } ) ? 1 : 0;
}

################################################################################

sub get_conf {
  my $result = XenServerDataWrapperJSON::get_conf(@_);
  return $result;
}

sub get_conf_section {
  my $result = XenServerDataWrapperJSON::get_conf_section(@_);
  return $result;
}

sub get_parent {
  my $result = XenServerDataWrapperJSON::get_parent(@_);
  return $result;
}

sub get_network_uuid {
  my $result = XenServerDataWrapperJSON::get_network_uuid(@_);
  return $result;
}

sub get_network_device {
  my $result = XenServerDataWrapperJSON::get_network_device(@_);
  return $result;
}

sub complete_sr_uuid {
  my $result = XenServerDataWrapperJSON::complete_sr_uuid(@_);
  return $result;
}

sub shorten_sr_uuid {
  my $uuid = shift;
  return ( split( '-', $uuid ) )[0];
}

sub get_labels {
  return get_conf_section('labels');
}

sub get_label {
  my $result = XenServerDataWrapperJSON::get_label(@_);
  return $result;
}

sub get_host_cpu_count {
  my $result = XenServerDataWrapperJSON::get_host_cpu_count(@_);
  return $result;
}

sub get_conf_update_time {
  my $result = XenServerDataWrapperJSON::get_conf_update_time(@_);
  return $result;
}

################################################################################

1;

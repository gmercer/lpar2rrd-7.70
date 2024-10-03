# PowerInterfaceWrapper.pm
# interface for accessing IBM Power data:
#   provides filepaths

use PowerDataWrapper;

package PowerInterfaceWrapper;

use strict;
use warnings;
use JSON;
use Data::Dumper;
use Xorux_lib qw(error read_json write_json);
use HostCfg;
use Digest::MD5 qw(md5 md5_hex md5_base64);

defined $ENV{INPUTDIR} || Xorux_lib::error( "INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded " . __FILE__ . ":" . __LINE__ ) && exit 1;

my $INT = load_int();

=begin usage_example
foreach my $uid (@{get_uuids()}){
  #$uid  = 'cdfa0c54-777c-3402-b16e-9d73f9b62ab5';
  my $npiv = get_npiv_json($uid);
  my $vscsi = get_vscsi_json($uid);

  print "NPIV $uid\n";
  print Dumper $npiv;

  print "VSCSI $uid\n";
  print Dumper $vscsi;
  #exit;
}
=cut

sub load_int {
  my $int;
  opendir( DIR, "$ENV{INPUTDIR}/tmp/restapi" );
  my @files = readdir(DIR);
  foreach my $file (@files) {
    my $file_full_path = "$ENV{INPUTDIR}/tmp/restapi/$file";
    if ( !-e $file_full_path || $file !~ m/_info_/ ) {
      next;
    }
    else {
      my $content = Xorux_lib::read_json($file_full_path) || warn "Cannot open $file " . __FILE__ . ":" . __LINE__ . "\n" && next;
      ( my $type, my $uid ) = split( "_info_", $file );
      $uid =~ s/\.json//g;
      $int->{$uid}{$type} = $content;
    }
  }
  closedir(DIR);
  return $int;

}

sub get_uuids {
  my @server_uuids = keys %{$INT};
  return \@server_uuids;
}

sub get_npiv_json {
  my $int        = $INT;
  my $server_uid = shift;
  $int = $int->{$server_uid}{'npiv'};
  my $npiv_maps = [];
  if ( ref($int) eq "ARRAY" ) {
    foreach my $map ( @{$int} ) {
      my $npiv_out;
      $npiv_out->{SystemName}                        = $map->{SystemName};
      $npiv_out->{ServerMapPort}                     = $map->{ServerAdapter}{MapPort};
      $npiv_out->{ServerLocalPartition}              = $map->{ServerAdapter}{LocalPartition};
      $npiv_out->{ServerConnectingPartition}         = $map->{ServerAdapter}{ConnectingPartition};
      $npiv_out->{ServerConnectingVirtualSlotNumber} = $map->{ServerAdapter}{ConnectingVirtualSlotNumber};
      $npiv_out->{ServerVirtualSlotNumber}           = $map->{ServerAdapter}{VirtualSlotNumber};
      $npiv_out->{ServerLocationCode}                = $map->{ServerAdapter}{LocationCode};
      $npiv_out->{ClientLocalPartitionID}            = $map->{ClientAdapter}{LocalPartitionID};
      $npiv_out->{ClientConnectingVirtualSlotNumber} = $map->{ClientAdapter}{ConnectingVirtualSlotNumber};
      $npiv_out->{ClientConnectingPartitionID}       = $map->{ClientAdapter}{ConnectingPartitionID};
      $npiv_out->{ClientVirtualSlotNumber}           = $map->{ClientAdapter}{VirtualSlotNumber};
      $npiv_out->{ClientWWPNs}                       = $map->{ClientAdapter}{WWPNs};
      $npiv_out->{AvailablePorts}                    = $map->{Port}{AvailablePorts};
      $npiv_out->{TotalPorts}                        = $map->{Port}{TotalPorts};
      $npiv_out->{PortName}                          = $map->{Port}{PortName};
      $npiv_out->{WWPN}                              = $map->{Port}{WWPN};
      $npiv_out->{PortLocationCode}                  = $map->{Port}{LocationCode};
      push( @{$npiv_maps}, $npiv_out );
    }
  }
  return $npiv_maps;
}

sub get_vscsi_json {
  my $int        = $INT;
  my $server_uid = shift;
  $int = $int->{$server_uid}{'vscsi'};
  my $vscsi_maps = [];
  if ( ref($int) eq "ARRAY" ) {
    foreach my $map ( @{$int} ) {
      my $vscsi_out;
      $vscsi_out->{SystemName}                 = $map->{ServerAdapter}{SystemName};
      $vscsi_out->{RemoteLogicalPartitionName} = $map->{ServerAdapter}{RemoteLogicalPartitionName};
      $vscsi_out->{AdapterName}                = $map->{ServerAdapter}{AdapterName};
      $vscsi_out->{ServerVirtualSlotNumber}    = $map->{ServerAdapter}{VirtualSlotNumber};
      $vscsi_out->{Partition}                  = $map->{Partition};
      $vscsi_out->{ClientVirtualSlotNumber}    = $map->{ClientAdapter}{VirtualSlotNumber};
      $vscsi_out->{ServerBackingDeviceName}    = $map->{ServerAdapter}{BackingDeviceName};
      $vscsi_out->{DiskName}                   = $map->{Storage}{VirtualDisk}{DiskName};
      $vscsi_out->{PartitionSize}              = $map->{Storage}{VirtualDisk}{PartitionSize};
      $vscsi_out->{DiskCapacity}               = $map->{Storage}{VirtualDisk}{DiskCapacity};
      $vscsi_out->{DiskLabel}                  = $map->{Storage}{VirtualDisk}{DiskLabel};
      push( @{$vscsi_maps}, $vscsi_out );
    }
  }
  return $vscsi_maps;
}

sub get_int_json {
  my $int        = $INT;
  my $server_uid = shift;
  $int = $int->{$server_uid}{'interfaces'};
  return $int;
}

1;

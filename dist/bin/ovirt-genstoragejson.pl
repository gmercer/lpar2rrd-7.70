# ovirt-genstoragejson.pl
#   generate oVirt storage-architecture configuration report
#   inputs:
#     data warehouse conf data/oVirt/metadata.json
#     rest api conf data/oVirt/iostats/restapi/$host-$query-last.json ($query: storagedomains, disks, vms)
#   output:
#     json on stdout

use strict;
use warnings;

use JSON;
use Data::Dumper;

use OVirtDataWrapper;

my $inputdir = $ENV{INPUTDIR};
my $json_dir = "$inputdir/data/oVirt/iostats/restapi";

my $rrdtool = $ENV{RRDTOOL};
if ( !-f "$rrdtool" ) {
  warn( 'Set correct path to rrdtool binary, it does not exist here: ' . $rrdtool . ' ' . __FILE__ . ':' . __LINE__ );
}
require RRDp;
RRDp::start "$rrdtool";

my %output;
my $json = JSON->new->utf8;
$json->pretty( [1] );

opendir( my $DH, $json_dir ) || warn( 'Could not open ' . $json_dir . ' for reading ' . "'$!'\n" ) && exit;
my @files = grep /.*-last.json/, readdir $DH;
closedir $DH;

foreach my $file ( sort @files ) {
  my %report;
  if ( grep( /.*-storagedomains-last.json/, $file ) ) {
    %report = %{ get_storage_domain_report($file) };
  }
  elsif ( grep( /.*-disks-last.json/, $file ) ) {
    %report = %{ get_vm_disk_report($file) };
  }
  else {
    next;
  }

  %output = ( %output, %report );
}

my $final_report = { "RHEV" => \%output };
print $json->encode($final_report);

exit 0;

################################################################################

# Storage domain section
# output: 'StorageDomain:id1' : { 'name' : 'foo', 'LogicalUnits' : { 'id2' : 'serial' } }
#   read: "Storage Domain 'id1' named 'foo' has Volume Group with Logical Units 'id2' and 'serial'

sub get_storage_domain_report {
  my $conf_file = shift;
  my $conf      = get_conf("$json_dir/$conf_file");
  my %result;

  foreach my $sd ( @{ $conf->{storage_domain} } ) {
    my $sd_id = $sd->{id};
    foreach my $storage ( @{ $sd->{storage} } ) {
      foreach my $volume_group ( @{ $storage->{volume_group} } ) {
        foreach my $logical_units ( @{ $volume_group->{logical_units} } ) {
          foreach my $logical_unit ( @{ $logical_units->{logical_unit} } ) {
            my $lu_id = $logical_unit->{id};

            # the first character is (always?) an extra '3' so remove it
            $lu_id =~ s/^.//;
            my $serial = @{ $logical_unit->{serial} }[0];
            unless ( exists $result{"StorageDomain:${sd_id}"}{'name'} ) {
              $result{"StorageDomain:${sd_id}"}{'name'} = OVirtDataWrapper::get_label( 'storage_domain', $sd_id );
            }
            $result{"StorageDomain:${sd_id}"}{'LogicalUnits'}{$lu_id} = $serial;
          }
        }
      }
    }
  }

  return \%result;
}

# VM-Disk section
# output: 'VM:id1' : { 'name' : 'foo', 'VirtualDisks' : { 'id2' : { 'id3' : 12345 } } }
#   read: "VM 'id1' named 'foo' has Virtual Disks 'id2' located on Storage Domain 'id3' with allocated 12345 GiB"

sub get_vm_disk_report {
  my $conf_file = shift;
  my $conf      = get_conf("$json_dir/$conf_file");
  $conf_file =~ s/-disks-last.json/-vms-last.json/;
  my $conf_mapping = get_conf("$json_dir/$conf_file");
  my $arch_vm      = OVirtDataWrapper::get_conf_section('arch-vm');

  # my $arch_vd = OVirtDataWrapper::get_conf_section('arch-disk');
  my %result;

  foreach my $vm ( keys %{$arch_vm} ) {
    my $disk_attachments = @{ $conf_mapping->{$vm} }[1];
    foreach my $disk_attachment ( @{$disk_attachments} ) {
      my $disk_uuid = $disk_attachment->{id};
      foreach my $virtual_disk ( @{ $conf->{disk} } ) {
        if ( $virtual_disk->{id} eq $disk_uuid ) {
          unless ( exists $result{"VM:$vm"}{'name'} ) {
            $result{"VM:$vm"}{'name'} = OVirtDataWrapper::get_label( 'vm', $vm );
          }

          my $disk_type = @{ $virtual_disk->{storage_type} }[0];
          if ( $disk_type eq 'lun' ) {
            my $lun_storage  = @{ $virtual_disk->{lun_storage} }[0];
            my $logical_unit = @{ $lun_storage->{logical_units} }[0];
            my $lun          = @{ $logical_unit->{logical_unit} }[0];
            my $lun_id       = $lun->{id};
            # the first character is (always?) an extra '3' so remove it
            $lun_id =~ s/^.//;
            my $disk_size    = sprintf "%.1f", ( @{ $lun->{size} }[0] / ( 1024**3 ) );

            $result{"VM:$vm"}{'DirectLun'}{$lun_id} = $disk_size;
          }
          else {
            my $storage_domain = @{ $virtual_disk->{storage_domains} }[0];
            my $sd_attr        = @{ $storage_domain->{storage_domain} }[0];
            my $sd_uuid        = $sd_attr->{id};
            my $disk_size      = sprintf "%.1f", ( @{ $virtual_disk->{provisioned_size} }[0] / ( 1024**3 ) );

            $result{"VM:$vm"}{'VirtualDisks'}{$disk_uuid}{$sd_uuid} = $disk_size;
          }
          last;
        }
      }
    }
  }

  return \%result;
}

################################################################################

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

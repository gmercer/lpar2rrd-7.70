# WindowsDataWrapper.pm
# interface for accessing WINDOWS data:

package WindowsDataWrapper;

use strict;
use warnings;
use JSON;
use Data::Dumper;
use Xorux_lib qw(error read_json write_json);
use HostCfg;
use Digest::MD5 qw(md5 md5_hex md5_base64);

defined $ENV{INPUTDIR} || Xorux_lib::error( "INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded " . __FILE__ . ":" . __LINE__ ) && exit 1;
my $basedir = $ENV{INPUTDIR};
my $tmpdir  = "$basedir/tmp";
if ( defined $ENV{TMPDIR_LPAR} ) {
  $tmpdir = $ENV{TMPDIR_LPAR};
}

################################################################################

sub get_item_uid {
  my $params = shift;
  my $result;
  my $type = $params->{type};

  if ( $type eq "wvm" ) {

    # print STDERR "29 WindowsDataWrapper.pm \$type $type\n";
    # necessary to find out domain for server from windows/<hyperv_cluster>/node_list.html
    # $id = WindowsDataWrapper::get_item_uid( { type => $type, cluster => $params->{cluster}, host => $params->{host}, vm_uuid => $params->{vm_uuid} } );
    my $host    = $params->{host};
    my $cluster = $params->{cluster};
    my $vm_uuid = $params->{vm_uuid};

    my $file_name = "$basedir/data/windows/cluster_$cluster/node_list.html";

    # print STDERR "36 WindowsDataWrapper.pm \$file_name $file_name\n";
    open( my $FF, "<$file_name" ) || error( "can't open $file_name: $! :" . __FILE__ . ":" . __LINE__ ) && return 0;
    my @node_list = (<$FF>);
    close($FF);
    my @matches = grep {/$host/} @node_list;

    # <TR> <TD><B>MSNET-HVCL</B></TD> <TD align="center">ad.xorux.com</TD> <TD align="center">HVNODE01</TD> <TD align="center">UnDeFiNeD</TD>
    ( undef, my $domain, undef ) = split "center\">", $matches[0];
    $domain =~ s/<.*//g;

    # print STDERR "43 WindowsDataWrapper.pm \$domain $domain\n";
    # return ("ad.xorux.com_server_HVNODE02_vm_8127B1FB-FFD6-4A9F-82BC-36CF9F18F03D");
    return ( "$domain" . "_server_$host" . "_vm_$vm_uuid" );
  }
  else {
    Xorux_lib::error( "WindowsDataWrapper unknown item \$type $type " . __FILE__ . ":" . __LINE__ );
    return;
  }
}

1;

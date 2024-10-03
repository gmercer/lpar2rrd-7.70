# VmwareDataWrapper.pm
# interface for accessing VMWARE data:

package VmwareDataWrapper;

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

my $use_sql = 0;

################################################################################
# uses menu.txt

sub get_item_uid {
  my $type = shift;
  my $qs   = shift;
  my $result;

  if ($use_sql) {

    #$result = VmwareDataWrapperSQL::get_item_uid(@_);
  }
  else {
    #$result = PowerDataWrapperJSON::get_item_uid(@_);
    my @menu = ();
    read_menu( \@menu );
    if ( $type eq "vm" ) {

      # print STDERR "32 VmwareDataWrapper.pm \$type $type \$qs $qs\n";
      # $type vm $qs host=10.22.11.10&server=10.22.11.8&lpar=RedHat-dev-DC&item=lpar&entitle=0&none=none&d_platform=VMware
      # from heatmap
      # host=10.22.11.10&server=cluster_New%20Cluster&lpar=freenas01&item=lpar&uuid=501cc9e0-a95e-7f86-8e7a-3a38b70e7eeb&entitle=0&gui=1&none=none
      #
      # return ('eb6102a7-1fa0-4376-acbb-f67e34a2212c_28_vm_500f7363-b0f9-559e-0f1e-3970d5c3bb0d');
      # from menu.txt
      # L:cluster_New Cluster:10.22.11.8:500f7363-b0f9-559e-0f1e-3970d5c3bb0d:RedHat-dev-DC:/lpar2rrd-cgi/detail.sh?host=10.22.11.10&server=10.22.11.8&lpar=500f7363-b0f9-559e-0f1e-3970d5c3bb0d&item=lpar&entitle=0&gui=1&none=none::Hosting:V:::
      # V:10.22.11.10:Totals:/lpar2rrd-cgi/detail.sh?host=10.22.11.10&server=vmware_eb6102a7-1fa0-4376-acbb-f67e34a2212c_28&lpar=nope&item=hmctotals&entitle=0&gui=1&none=none:::Hosting::V:
      ( my $host_server, my $vm_name ) = split( "lpar=", $qs );
      my $vm_uuid = "";
      if ( index( $vm_name, "uuid=" ) != -1 ) {
        ( undef, $vm_uuid, undef ) = split( "uuid=", $vm_name );
        $vm_uuid =~ s/&.*//g;

        # print STDERR "VmwareDataWrapper.pm 53 \$vm_uuid $vm_uuid\n";
      }
      else {
        $vm_name =~ s/&item=.*//;
        my @matches = grep { /$vm_name/ && /$host_server/ } @menu;

        # print STDERR "44 VmwareDataWrapper.pm \@matches @matches\n";
        if ( !@matches || scalar @matches < 1 ) {
          Xorux_lib::error( "no menu.txt item for \$host_server $host_server && \$vm_name $vm_name " . __FILE__ . ":" . __LINE__ );
          return;
        }
        ( undef, undef, undef, $vm_uuid, undef ) = split( ":", $matches[0] );
      }
      ( my $host, undef ) = split( "&", $qs );
      $host =~ s/host=//;
      $host = "V:" . $host . ":Totals:";
      my @matches = grep {/$host/} @menu;

      # print STDERR "56 VmwareDataWrapper.pm \@matches @matches\n";
      if ( !@matches || scalar @matches < 1 ) {
        Xorux_lib::error( "no menu.txt item for \$host $host" . __FILE__ . ":" . __LINE__ );
        return;
      }
      ( undef, my $vcenter_uuid ) = split( "server=", $matches[0] );

      # print STDERR "62 VmwareDataWrapper.pm \$vcenter_uuid $vcenter_uuid\n";
      $vcenter_uuid =~ s/\&.*//;
      $vcenter_uuid =~ s/vmware_//;
      chomp $vcenter_uuid;
      return ( "$vcenter_uuid" . "_vm_" . "$vm_uuid" );
    }
    elsif ( $type eq "pool" ) {

      # $type pool $qs host=10.22.11.10&server=10.22.11.8&lpar=pool&item=pool&entitle=0&none=none&d_platform=VMware
      # return ('eb6102a7-1fa0-4376-acbb-f67e34a2212c_28_cluster_domain-c87_esxi_10.22.11.8');
      # from menu.txt
      # S:cluster_New Cluster:10.22.11.8:CPUpool-pool:CPU pool:/lpar2rrd-cgi/detail.sh?host=10.22.11.10&server=10.22.11.8&lpar=pool&item=pool&entitle=0&gui=1&none=none::1584697380:V:
      # A:10.22.11.10:cluster_New Cluster:Totals:/lpar2rrd-cgi/detail.sh?host=cluster_domain-c87&server=vmware_eb6102a7-1fa0-4376-acbb-f67e34a2212c_28&lpar=nope&item=cluster&entitle=0&gui=1&none=none::Hosting::V:
      ( my $host_server, undef ) = split( "&lpar=", $qs );
      my @matches = grep { /S:cluster/ && /$host_server/ } @menu;

      # print STDERR "77 VmwareDataWrapper.pm \@matches @matches\n";
      if ( !@matches || scalar @matches < 1 ) {
        Xorux_lib::error( "no menu.txt item for \$host_server $host_server && S:cluster " . __FILE__ . ":" . __LINE__ );
        return;
      }
      ( undef, my $cluster_name, undef ) = split( ":", $matches[0] );
      ( my $host, undef ) = split( "&", $qs );
      $host =~ s/host=//;
      $host    = "A:" . $host . ":" . $cluster_name . ":";
      @matches = grep {/$host/} @menu;

      # print STDERR "87 VmwareDataWrapper.pm \@matches @matches\n";
      if ( !@matches || scalar @matches < 1 ) {
        Xorux_lib::error( "no menu.txt item for \$host $host" . __FILE__ . ":" . __LINE__ );
        return;
      }
      ( my $cluster_domain, my $vcenter_uuid ) = split( "&server=", $matches[0] );

      # print STDERR "93 VmwareDataWrapper.pm \$cluster_domain $cluster_domain \$vcenter_uuid $vcenter_uuid\n";
      $vcenter_uuid =~ s/\&.*//;
      $vcenter_uuid =~ s/vmware_//;
      chomp $vcenter_uuid;
      ( undef, $cluster_domain ) = split( "host=", $cluster_domain );
      ( undef, my $server ) = split( "server=", $host_server );

      # print STDERR "99 \$server $server \$cluster_domain $cluster_domain \$vcenter_uuid $vcenter_uuid\n";
      return ( "$vcenter_uuid" . "_" . "$cluster_domain" . "_esxi_" . "$server" );
    }
    elsif ( $type eq "vcenter" ) {

      # from name get vcenter id
      # V:10.22.11.10:Totals:/lpar2rrd-cgi/detail.sh?host=10.22.11.10&server=vmware_eb6102a7-1fa0-4376-acbb-f67e34a2212c_28&lpar=nope&item=hmctotals&entitle=0&gui=1&none=none:::Hosting::V:
      # $qs vcenter=Merit_OL&item=vtop10&d_platform=VMware&platform=VMware
      # print STDERR "116 \$qs $qs\n";
      ( undef, my $vcenter_name, undef ) = split( "=", $qs );
      $vcenter_name =~ s/&item//;
      my @matches = grep { /V:/ && /:$vcenter_name:/ } @menu;
      if ( !@matches || scalar @matches < 1 ) {
        Xorux_lib::error( "no menu.txt item for \$vcenter_name $vcenter_name" . __FILE__ . ":" . __LINE__ );
        return;
      }
      ( undef, undef, my $vcenter_uuid, undef ) = split( "=", $matches[0] );
      $vcenter_uuid =~ s/&.*//g;
      $vcenter_uuid =~ s/vmware_//;

      #my $vcenter_uuid = "eb6102a7-1fa0-4376-acbb-f67e34a2212c_28";
      return ($vcenter_uuid);
    }
    elsif ( $type eq "datastore" ) {

      # from uuid get datastore id for dbase
      # Z:10.22.11.10:datastore_DC:SAN-Comp-development:/lpar2rrd-cgi/detail.sh?host=datastore_datacenter-2&server=vmware_eb6102a7-1fa0-4376-acbb-f67e34a2212c_28&lpar=591c40de-576c4922-9ce2-e4115bd41b18&item=datastore&entitle=0&gui=1&none=none::Hosting::V:Compellent/SAN dev pro/:group-s326:
      # coming from acl $qs host=datastore_DC&server=CoolHousing_PRG&lpar=SAN-Comp-development&item=datastore&entitle=0&none=none&d_platform=VMware&datastore_uuid=591c40de-576c4922-9ce2-e4115bd41b18&acl=acl
      my @matches = ();
      if ( $qs =~ /acl=acl/ ) {
        ( undef, my $datastore_uuid ) = split "datastore_uuid=", $qs;
        $datastore_uuid =~ s/&.*//g;
        chomp $datastore_uuid;
        @matches = grep { /Z:/ && /$datastore_uuid/ } @menu;
      }
      else {
        @matches = grep { /Z:/ && /$qs/ } @menu;
      }
      if ( !@matches || scalar @matches < 1 ) {
        Xorux_lib::error( "no menu.txt item for \$qs ,$qs, for datastore" . __FILE__ . ":" . __LINE__ );
        return;
      }
      if ( scalar @matches > 1 ) {
        Xorux_lib::error( "more>1 menu.txt item for \$qs $qs for datastore \@matches ,@matches, " . __FILE__ . ":" . __LINE__ );
      }

      # print STDERR "142 VmwareDataWrapper.pm matches[0] $matches[0]\n";
      ( undef, undef, undef, undef, my $datastore_uuid, undef ) = split ":", $matches[0];
      ( undef, my $vcenter_uuid, $datastore_uuid, undef ) = split "&", $datastore_uuid;
      $datastore_uuid =~ s/lpar=//;
      $vcenter_uuid   =~ s/server=vmware_//;
      $datastore_uuid = "$vcenter_uuid" . "_ds_" . "$datastore_uuid";
      return ($datastore_uuid);
    }
    elsif ( $type eq "clustcpu" ) {

      #print STDERR "150 \$qa $qs\n";
      return 123;    # anything
    }
    elsif ( $type eq "vm_cluster_totals" ) {
      my @matches = ();

      # print STDERR "167 VmwareDataWrapper.pm \$qs $qs\n";
      # $qs vcenter=Merit_OL&cluster=ClusterOL&item=vm_cluster_totals&d_platform=VMware
      ( undef, my $vcenter_name, my $cluster_name ) = split( "=", $qs );
      $vcenter_name =~ s/&.*//g;
      $cluster_name =~ s/&.*//g;

      # grep "New Cluster" menu.txt|grep Hosting|grep cluster_domain|grep Totals
      @matches = grep { /$vcenter_name/ && /$cluster_name/ && /Totals/ } @menu;

      # A:10.22.11.10:cluster_New Cluster:Totals:/lpar2rrd-cgi/detail.sh?host=cluster_domain-c87&server=vmware_eb6102a7-1fa0-4376-acbb-f67e34a2212c_28&lpar=nope&item=cluster&entitle=0&gui=1&none=none::Hosting::V:
      ( undef, my $cluster_uuid, my $vmware_uuid ) = split( "=", $matches[0] );
      $cluster_uuid =~ s/&.*//g;
      $vmware_uuid  =~ s/&.*//g;
      $vmware_uuid  =~ s/^vmware_//;
      return "$vmware_uuid" . "_" . "$cluster_uuid";
    }
    else {
      Xorux_lib::error( "unknown item \$type $type " . __FILE__ . ":" . __LINE__ );
      return;
    }
  }
}

# in following sub possibly test if using DB
sub getItemParents {

  # $uid_hash
  my $params = shift;

  return SQLiteDataWrapper::getItemParents($params);
}

sub getItemLabel {
  my $params = shift;

  # print Dumper("nevim kolik",$params);
  # 'item_id' => 'eb6102a7-1fa0-4376-acbb-f67e34a2212c_28'
  my @menu = ();
  read_menu( \@menu );

  # V:10.22.11.10:Totals:/lpar2rrd-cgi/detail.sh?host=10.22.11.10&server=vmware_eb6102a7-1fa0-4376-acbb-f67e34a2212c_28&lpar=nope&item=hmctotals&entitle=0&gui=1&none=none:::Hosting::V:
  my $vcenter_id = $params->{'item_id'};

  # print STDERR " nevim $vcenter_id\n";
  my @matches = grep { /$vcenter_id/ && /^V:/ } @menu;

  # print STDERR "44 VmwareDataWrapper.pm \@matches @matches\n";
  if ( !@matches || scalar @matches < 1 ) {
    Xorux_lib::error( "no menu.txt item for vcenter id $vcenter_id cannot get label " . __FILE__ . ":" . __LINE__ );
    return;
  }
  ( undef, undef, undef, undef, undef, undef, my $vcenter_label, undef ) = split( ":", $matches[0] );

  return ($vcenter_label);
}

# read tmp/menu.txt
sub read_menu {
  my $menu_ref = shift;
  open( FF, "<$tmpdir/menu.txt" ) || error( "can't open $tmpdir!menu.txt: $! :" . __FILE__ . ":" . __LINE__ ) && return 0;
  @$menu_ref = (<FF>);
  close(FF);
  return;
}

1;

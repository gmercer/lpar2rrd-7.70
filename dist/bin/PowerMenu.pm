# PowerMenu.pm
# page types and associated tools for generating front-end menu and tabs for Power

package PowerMenu;

use strict;

use JSON;
use Data::Dumper;
use Xorux_lib;
use PowerDataWrapper;

my $inputdir = '/home/lpar2rrd/lpar2rrd';
$inputdir = $ENV{INPUTDIR} if ( defined $ENV{INPUTDIR} );

my ( $SERV, $CONF ) = PowerDataWrapper::init();

################################################################################
my @page_types = (
  { type       => "vm",
    platform   => "Power",
    url_base   => "/lpar2rrd-cgi/detail.sh",
    url_params => [ "host", "server", "lpar", "item", "vm" ],
    tabs       => [ { cpu => "CPU" } ]
  },
  { type       => "pool",
    platform   => "Power",
    url_base   => "/lpar2rrd-cgi/detail.sh",
    url_params => [ "host", "server", "lpar", "item", "pool" ],
    tabs       => [
      { cpu_cores1 => "CPU1" },
      { cpu_cores2 => "CPU2" },
      { cpu_cores3 => "CPU3" },
      { cpu_cores4 => "CPU4" }
    ]
  },
  { type       => "configuration",
    platform   => "Power",
    url_base   => "/lpar2rrd-cgi/detail.sh",
    url_params => ["item"],
    tabs       => [
      { servers         => "Servers" },
      { enterprise_pool => "Enterprise Pool" },
      { interfaces      => "Interfaces" },
      { cli             => "CLI" },
      { network         => "Network" },
      { vscsi           => "VSCSI" },
      { npiv            => "NPIV" }
    ]
  },
  { type       => "cpu_workload_estimator",
    platform   => "Power",
    url_base   => "cpu_workload_estimator.html",
    url_params => [],
    tabs       => []
  },
  { type       => "Heatmap",
    platform   => "Power",
    url_base   => "heatmap-power.html",
    url_params => [],
    tabs       => [
      { lpar => "LPAR" },
      { lpar => "Server" }
    ]
  },
  { type       => "resource_configuration_advisor",
    platform   => "Power",
    url_base   => "gui-cpu_max_check.html",
    url_params => [],
    tabs       => []
  },
  { type       => "historical_reports",
    platform   => "Power",
    url_base   => "/lpar2rrd-cgi/histrep.sh",
    url_params => ["mode"],
    tabs       => []
  },
  { type       => "top10_global",
    platform   => "Power",
    url_base   => "/lpar2rrd-cgi/detail.sh",
    url_params => ["item"],
    tabs       => []
  },
  { type       => "nmon_file_grapher",
    platform   => "Power",
    url_base   => "nmonfile.html",
    url_params => [],
    tabs       => []
  },
  { type       => "rmc_check",
    platform   => "Power",
    url_base   => "gui-rmc.html",
    url_params => [],
    tabs       => []
  },
  { type       => "hmc-totals",
    platform   => "Power",
    url_base   => "/lpar2rrd-cgi/detail.sh",
    url_params => [ "host", "server", "lpar", "item", "type" ],
    tabs       => [
      { server => "Server" },
      { lpar   => "LPAR" },
      { count  => "Count" },
      { cpu    => "CPU" },
      { memory => "Memory" },
      { paging => "Paging" }
    ]
  },
  { type       => "interface",
    platform   => "Power",
    url_base   => "/lpar2rrd-cgi/detail.sh",
    url_params => [ "host", "server", "lpar", "item" ],
    tabs       => []
  },
  { type       => "memory",
    platform   => "Power",
    url_base   => "/lpar2rrd-cgi/detail.sh",
    url_params => [ "host", "server", "lpar", "item", "type" ],
    tabs       => []
  },
  { type       => "topten",
    platform   => "Power",
    url_base   => "/lpar2rrd-cgi/detail.sh",
    url_params => [ "host", "server", "item", "type" ],
    tabs       => []
  },
  { type       => "view",
    platform   => "Power",
    url_base   => "/lpar2rrd-cgi/detail.sh",
    url_params => [ "host", "server", "lpar", "item", "type" ],
    tabs       => []
  },
  { type       => "pool",
    platform   => "Power",
    url_base   => "/lpar2rrd-cgi/detail.sh",
    url_params => [],
    tabs       => [ { "cpu" => "CPU Pool" }, { "cpu_max" => "CPU Pool Max" }, { "lpar_agg" => "LPARs Aggregated" }, { "configuration" => "Configuration" } ]
  },
  { type       => "shpool",
    platform   => "Power",
    url_base   => "/lpar2rrd-cgi/detail.sh",
    url_params => [],
    tabs       => [ { "cpu" => "CPU Pool" }, { "cpu_max" => "CPU Pool Max" }, { "lpar_agg" => "LPARs Aggregated" }, { "configuration" => "Configuration" } ]
  },
  { type       => "another_type",
    platform   => "Power",
    url_base   => "/lpar2rrd-cgi/detail.sh",
    url_params => [ "uuid", "type" ],
    tabs       => []
  }

);

if ( defined $ENV{XORMON} && $ENV{XORMON} ) {
  my $file = "$inputdir/etc/links_power.json";
  @page_types = @{ Xorux_lib::read_json($file) } if ( -e $file );
}

################################################################################

sub create_folder {
  my $title  = shift;
  my %folder = ( "folder" => "true", "title" => $title, children => [] );

  return \%folder;
}

sub create_page {
  my $title = shift;
  my $url   = shift;
  my %page  = ( "title" => $title, "str" => $title, "href" => $url );

  if ( $title eq 'Heatmap' ) {
    $page{extraClasses} = 'boldmenu';
  }

  return \%page;
}

sub get_url {

  # accepts a hash with named parameters: type, and respective url_params
  my ($args) = @_;

  #print STDERR Dumper $args;
  my $url;
  foreach my $page_type (@page_types) {
    $args->{type} = lc( $args->{type} );
    if ( $page_type->{type} eq $args->{type} ) {
      $url =
          $page_type->{url_base} =~ /\.html$/
        ? $page_type->{url_base}
        : "$page_type->{url_base}?platform=$page_type->{platform}&type=$page_type->{type}";

      foreach my $param ( @{ $page_type->{url_params} } ) {
        $url .= "&$param=$args->{$param}";
      }
      last;
    }
  }

  return $url;
}

sub get_tabs {
  my $type = shift;

  for my $page_type (@page_types) {
    if ( $page_type->{type} eq $type ) {
      return $page_type->{tabs};
    }
  }
  return ();
}

################################################################################

sub get_powerserver_root {
  my @menu;

  push @menu, create_page( 'Heatmap',       'heatmap-power.html' );
  push @menu, create_page( 'Configuration', '/lpar2rrd-cgi/detail.sh?platform=Power&type=configuration' );

  foreach my $pool ( @{ PowerDataWrapper::get_pool_list() } ) {
    push @menu, create_folder_lazy( PowerDataWrapper::get_label( "pool", $pool ), "Power", "pool", $pool );
  }

  return \@menu;
}

sub get_powerserver_pool {
  my $pool = shift;
  my @menu;

  my $totals_url = PowerMenu::get_url( { type => "pool-aggr", pool => $pool } );
  push @menu, PowerMenu::create_page( "Totals", $totals_url );

  foreach my $host ( @{ PowerDataWrapper::get_host_in_pool_list($pool) } ) {
    push @menu, create_folder_lazy( PowerDataWrapper::get_label( "host", $host ), "Power", "host", $host );
  }

  push @menu, create_folder_lazy( "VM",      "Power", "vm",      $pool );
  push @menu, create_folder_lazy( "Storage", "Power", "storage", $pool );

  return \@menu;
}

################################################################################

# expects hash as parameter : { type => "page_type", uid => "abcd1234_uid" }
sub url_new_to_old {
  my $out       = "";
  my $in        = shift;
  my $page_type = "";
  my $uid       = "";

  #print STDERR "In url_new_to_old\n";
  #print STDERR Dumper $in;

  $page_type = $in->{type} if defined $in->{type};
  $uid       = $in->{id}   if defined $in->{id};

  if ( $page_type eq "hmc-totals" ) {
    my $hmc_label = "";
    my $hmcs      = PowerDataWrapper::get_items("hmc");
    foreach my $hmc_item ( @{$hmcs} ) {
      foreach my $hmc_uid ( keys %{$hmc_item} ) {
        if ( $hmc_uid eq $uid ) {
          $hmc_label = $hmc_item->{$hmc_uid};
        }
      }
    }
    return {
      url_base => '/lpar2rrd-cgi/detail.sh',
      params   => {
        type   => 'hmc-totals',
        host   => $hmc_label,
        server => 'nope',
        lpar   => 'nope',
        item   => 'hmctotals'
      }
    };
  }
  elsif ( $page_type eq "cpu_workload_estimator" ) {
    return {
      url_base => 'cpu_workload_estimator.html',
      params   => {}
    };
  }
  elsif ( $page_type eq "resource_configuration_advisor" ) {
    return {
      url_base => 'gui-cpu_max_check.html',
      params   => {}
    };
  }
  elsif ( $page_type eq "Heatmap" ) {
    return {
      url_base => 'heatmap-power.html',
      params   => {}
    };
  }
  elsif ( $page_type eq "historical_reports" ) {
    return {
      url_base => '/lpar2rrd-cgi/histrep.sh?mode=global',
      params   => {}
    };
  }
  elsif ( $page_type eq "configuration" ) {
    return {
      url_base => '/lpar2rrd-cgi/detail.sh',
      params   => {
        lpar => 'cod',
        item => 'servers'
      }
    };
  }
  elsif ( $page_type eq "top10_global" ) {
    return {
      url_base => '',
      params   => {
        lpar => 'cod',
        item => 'topten'
      }
    };
  }
  elsif ( $page_type eq "nmon_file_grapher" ) {
    return {
      url_base => 'nmonfile.html',
      params   => {}
    };
  }
  elsif ( $page_type eq "rmc_check" ) {
    return {
      url_base => 'gui-rmc.html',
      params   => {}
    };
  }
  elsif ( $page_type eq "hmc" ) {
    my $hmc_label = PowerDataWrapper::get_label( "HMC", $uid );

    #    $hmc_label = $hmc_label->{label} if (ref($hmc_label) eq "HASH");
    return {
      url_base => '/lpar2rrd-cgi/detail.sh',
      params   => {
        host   => $hmc_label,
        server => 'nope',
        lpar   => 'nope',
        item   => 'hmctotals'
      }
    };
  }
  elsif ( $page_type eq "vm" ) {
    my $vm_label     = PowerDataWrapper::get_label( "VM", $uid );
    my $server_uid   = PowerDataWrapper::get_vm_parent($uid);
    my $server_label = PowerDataWrapper::get_label( "SERVER", $server_uid );
    my $hmc_uid      = PowerDataWrapper::get_server_parent($server_uid);
    my $hmc_label    = PowerDataWrapper::get_label( "HMC", $hmc_uid );

    #    $hmc_label = $hmc_label->{label} if (ref($hmc_label) eq "HASH");

    return {
      url_base => '/lpar2rrd-cgi/detail.sh',
      params   => {
        host   => $hmc_label,
        server => $server_label,
        lpar   => $vm_label,
        item   => 'lpar'
      }
    };
  }
  elsif ( $page_type eq "pool" ) {
    my $pool_label   = "CPU Pool";
    my $server_uid   = $uid;
    my $server_label = PowerDataWrapper::get_label( "SERVER", $server_uid );

    #print STDERR "test : $server_uid -> $server_label\n";
    my $hmc_uid   = PowerDataWrapper::get_server_parent($server_uid);
    my $hmc_label = PowerDataWrapper::get_label( "HMC", $hmc_uid );

    #    $hmc_label        = $hmc_label->{label} if (ref($hmc_label) eq "HASH");
    return {
      url_base => '/lpar2rrd-cgi/detail.sh',
      params   => {
        host   => $hmc_label,
        server => $server_label,
        lpar   => 'pool',
        item   => 'pool'
      }
    };
  }
  elsif ( $page_type eq "shpool" ) {
    my $server_uid   = PowerDataWrapper::get_pool_parent($uid);
    my $server_label = PowerDataWrapper::get_label( "SERVER", $server_uid );
    my $pool_label   = PowerDataWrapper::get_label( "POOL", $uid );
    my $pool_id      = PowerDataWrapper::get_pool_id( $uid, $server_uid );
    my $hmc_uid      = PowerDataWrapper::get_server_parent($server_uid);
    my $hmc_label    = PowerDataWrapper::get_label( "HMC", $hmc_uid );

    #    $hmc_label        = $hmc_label->{label} if (ref($hmc_label) eq "HASH");
    return {
      url_base => '/lpar2rrd-cgi/detail.sh',
      params   => {
        host   => $hmc_label,
        server => $server_label,
        lpar   => "SharedPool$pool_id",
        item   => 'shpool'
      }
    };
  }
  elsif ( $page_type eq "memory" ) {
    my $server_uid   = $uid;
    my $server_label = PowerDataWrapper::get_label( "SERVER", $server_uid );
    my $hmc_uid      = PowerDataWrapper::get_server_parent($server_uid);
    my $hmc_label    = PowerDataWrapper::get_label( "HMC", $hmc_uid );

    #    $hmc_label        = $hmc_label->{label} if (ref($hmc_label) eq "HASH");
    return {
      url_base => '/lpar2rrd-cgi/detail.sh',
      params   => {
        host   => $hmc_label,
        server => $server_label,
        lpar   => 'cod',
        item   => 'memalloc'
      }
    };
  }
  elsif ( $page_type eq "topten" ) {
    my $server_uid   = $uid;
    my $server_label = PowerDataWrapper::get_label( "SERVER", $server_uid );
    my $hmc_uid      = PowerDataWrapper::get_server_parent($server_uid);
    my $hmc_label    = PowerDataWrapper::get_label( "HMC", $hmc_uid );

    #    $hmc_label        = $hmc_label->{label} if (ref($hmc_label) eq "HASH");
    return {
      url_base => '/lpar2rrd-cgi/detail.sh',
      params   => {
        host   => $hmc_label,
        server => $server_label,
        lpar   => 'cod',
        item   => 'topten'
      }
    };
  }
  elsif ( $page_type eq "view" ) {
    my $server_uid   = $uid;
    my $server_label = PowerDataWrapper::get_label( "SERVER", $server_uid );
    my $hmc_uid      = PowerDataWrapper::get_server_parent($server_uid);
    my $hmc_label    = PowerDataWrapper::get_label( "HMC", $hmc_uid );

    #    $hmc_label        = $hmc_label->{label} if (ref($hmc_label) eq "HASH");
    return {
      url_base => '/lpar2rrd-cgi/detail.sh',
      params   => {
        host   => $hmc_label,
        server => $server_label,
        lpar   => 'cod',
        item   => 'view'
      }
    };
  }
  elsif ( $page_type eq "lan-aggr" ) {
    my $server_uid   = $uid;
    my $server_label = PowerDataWrapper::get_label( "SERVER", $server_uid );
    my $hmc_uid      = PowerDataWrapper::get_server_parent($server_uid);
    my $hmc_label    = PowerDataWrapper::get_label( "HMC", $hmc_uid );

    #    $hmc_label        = $hmc_label->{label} if (ref($hmc_label) eq "HASH");
    my $url = "/lpar2rrd-cgi/detail.sh?host=$hmc_label&server=$server_label&lpar=lan-totals&item=power_lan&entitle=0&gui=1&none=none";
    return {
      url_base => '/lpar2rrd-cgi/detail.sh',
      params   => {
        host   => $hmc_label,
        server => $server_label,
        lpar   => 'lan-totals',
        item   => 'power_lan'
      }
    };
  }
  elsif ( $page_type eq "sri-aggr" ) {
    my $server_uid   = $uid;
    my $server_label = PowerDataWrapper::get_label( "SERVER", $server_uid );
    my $hmc_uid      = PowerDataWrapper::get_server_parent($server_uid);
    my $hmc_label    = PowerDataWrapper::get_label( "HMC", $hmc_uid );

    #    $hmc_label        = $hmc_label->{label} if (ref($hmc_label) eq "HASH");
    my $url = "/lpar2rrd-cgi/detail.sh?host=$hmc_label&server=$server_label&lpar=sri-totals&item=power_sri&entitle=0&gui=1&none=none";
    return {
      url_base => '/lpar2rrd-cgi/detail.sh',
      params   => {
        host   => $hmc_label,
        server => $server_label,
        lpar   => 'sri-totals',
        item   => 'power_sri'
      }
    };
  }
  elsif ( $page_type eq "hea-aggr" ) {
    my $server_uid   = $uid;
    my $server_label = PowerDataWrapper::get_label( "SERVER", $server_uid );
    my $hmc_uid      = PowerDataWrapper::get_server_parent($server_uid);
    my $hmc_label    = PowerDataWrapper::get_label( "HMC", $hmc_uid );

    #    $hmc_label        = $hmc_label->{label} if (ref($hmc_label) eq "HASH");
    my $url = "/lpar2rrd-cgi/detail.sh?host=$hmc_label&server=$server_label&lpar=hea-totals&item=power_hea&entitle=0&gui=1&none=none";
    return {
      url_base => '/lpar2rrd-cgi/detail.sh',
      params   => {
        host   => $hmc_label,
        server => $server_label,
        lpar   => 'hea-totals',
        item   => 'power_hea'
      }
    };
  }
  elsif ( $page_type eq "sas-aggr" ) {
    my $server_uid   = $uid;
    my $server_label = PowerDataWrapper::get_label( "SERVER", $server_uid );
    my $hmc_uid      = PowerDataWrapper::get_server_parent($server_uid);
    my $hmc_label    = PowerDataWrapper::get_label( "HMC", $hmc_uid );

    #    $hmc_label        = $hmc_label->{label} if (ref($hmc_label) eq "HASH");
    my $url = "/lpar2rrd-cgi/detail.sh?host=$hmc_label&server=$server_label&lpar=sas-totals&item=power_sas&entitle=0&gui=1&none=none";
    return {
      url_base => '/lpar2rrd-cgi/detail.sh',
      params   => {
        host   => $hmc_label,
        server => $server_label,
        lpar   => 'sas-totals',
        item   => 'power_sas'
      }
    };
  }
  elsif ( $page_type eq "san-aggr" ) {
    my $server_uid   = $uid;
    my $server_label = PowerDataWrapper::get_label( "SERVER", $server_uid );
    my $hmc_uid      = PowerDataWrapper::get_server_parent($server_uid);
    my $hmc_label    = PowerDataWrapper::get_label( "HMC", $hmc_uid );

    #    $hmc_label        = $hmc_label->{label} if (ref($hmc_label) eq "HASH");
    my $url = "/lpar2rrd-cgi/detail.sh?host=$hmc_label&server=$server_label&lpar=san-totals&item=power_san&entitle=0&gui=1&none=none";
    return {
      url_base => '/lpar2rrd-cgi/detail.sh',
      params   => {
        host   => $hmc_label,
        server => $server_label,
        lpar   => 'san-totals',
        item   => 'power_san'
      }
    };
  }
  elsif ( $page_type eq "lan" || $page_type eq "san" || $page_type eq "sas" || $page_type eq "hea" || $page_type eq "sri" ) {
    my $int_uid = $uid;
    my $ext     = "";
    if ( $page_type eq "lan" ) { $ext = ".ralm"; }
    if ( $page_type eq "san" ) { $ext = ".rasm"; }
    if ( $page_type eq "sas" ) { $ext = ".rapm"; }
    if ( $page_type eq "sri" ) { $ext = ".rasrm"; }
    if ( $page_type eq "hea" ) { $ext = ".rahm"; }
    my $int_label = PowerDataWrapper::get_label( $page_type, $uid );
    $int_label = $int_label->{label} if ref $int_label eq "HASH" && defined $int_label->{label};
    my $server_uid   = PowerDataWrapper::get_int_parent( $int_uid, $page_type );
    my $server_label = PowerDataWrapper::get_label( "SERVER", $server_uid );
    my $hmc_uid      = PowerDataWrapper::get_server_parent($server_uid);
    my $hmc_label    = PowerDataWrapper::get_label( "HMC", $hmc_uid );

    #    $hmc_label        = $hmc_label->{label} if (ref($hmc_label) eq "HASH");
    my $url = "/lpar2rrd-cgi/detail.sh?host=$hmc_label&server=$server_label&lpar=$int_label$ext&item=power_$page_type&entitle=0&gui=1&none=none";
    return {
      url_base => '/lpar2rrd-cgi/detail.sh',
      params   => {
        host   => $hmc_label,
        server => $server_label,
        lpar   => "$int_label$ext",
        item   => "power_$page_type"
      }
    };
  }
  else {
    return {
      url_base => 'unknown',
      params   => { item => 'another_type not defined url' }
    };
  }

  return {};
}

sub gen_url {
  my $url_hash = shift;
  my $url      = "";

  $url = $url_hash->{url_base} . '?';
  my @params = keys %{ $url_hash->{params} };
  foreach my $par (@params) {
    $url .= "$par=$url_hash->{params}{$par}" if ( defined $url_hash->{params}{$par} );
    if ( $par ne $params[-1] ) { $url .= '&'; }

    #warn Dumper $url_hash;
  }
  return $url;
}

sub url_old_to_new {
  my $url = shift;
  my $params;
  my %out;
  $url = Xorux_lib::urldecode($url);
  $url =~ s/===double-col===/:/g;
  $url =~ s/%20/ /g;
  $url =~ s/%3A/:/g;
  $url =~ s/%2F/&&1/g;
  $url =~ s/%23/#/g;
  $url =~ s/%3B/;/g;

  my $qs = $url;
  my $type;
  my $id;

  ( undef, $qs ) = split( "\\?", $qs );
  $params = Xorux_lib::parse_url_params($qs);

  if ( $params->{item} eq "lpar" ) {
    $type = 'vm';
    $id   = PowerDataWrapper::get_item_uid( { type => $type, label => $params->{lpar} } );
  }
  elsif ( $params->{item} eq "pool" ) {
    $type = "pool";
    $id   = PowerDataWrapper::get_item_uid( { type => $type, label => $params->{server} } );
  }
  elsif ( $params->{item} eq "shpool" ) {
    $type = "shpool";
    $id   = PowerDataWrapper::get_item_uid( { type => $type, label => $params->{lpar} } );
  }
  elsif ( $params->{item} eq "memalloc" ) {
    $type = "memory";
    $id   = PowerDataWrapper::get_item_uid( { type => "server", label => $params->{server} } );
  }
  elsif ( $params->{mode} eq "power" && defined( $params->{host} ) ) {
    $type = "local_historical_reports";
    $id   = "not_supported_anymore";
  }
  elsif ( $params->{mode} eq "global" ) {
    $type = "historical_reports";
    $id   = "";
  }
  elsif ( $params->{item} eq "topten" && defined( $params->{server} ) ) {
    $type = "topten";
    $id   = PowerDataWrapper::get_item_uid( { type => "server", label => $params->{server} } );
  }
  elsif ( $params->{item} eq "view" && defined( $params->{server} ) ) {
    $type = "view";
    $id   = PowerDataWrapper::get_item_uid( { type => "server", label => $params->{server} } );
  }
  elsif ( $params->{item} =~ "power_" && $params->{lpar} !~ m/totals/ ) {
    $type = $params->{item};
    $type =~ s/power_//g;
    my $label = $params->{lpar};
    $label =~ s/\..*//g;
    $id = PowerDataWrapper::get_item_uid( { type => $type, label => $label } );
  }
  elsif ( $params->{item} =~ "power_lan" && $params->{lpar} =~ m/totals/ ) {
    $type = "lan-aggr";
    my $label = $params->{server};
    $id = PowerDataWrapper::get_item_uid( { type => $type, label => $label } );
  }
  elsif ( $params->{item} =~ "power_san" && $params->{lpar} =~ m/totals/ ) {
    $type = "san-aggr";
    my $label = $params->{server};
    $id = PowerDataWrapper::get_item_uid( { type => $type, label => $label } );
  }
  elsif ( $params->{item} =~ "power_sas" && $params->{lpar} =~ m/totals/ ) {
    $type = "sas-aggr";
    my $label = $params->{server};
    $id = PowerDataWrapper::get_item_uid( { type => $type, label => $label } );
  }
  elsif ( $params->{item} =~ "power_hea" && $params->{lpar} =~ m/totals/ ) {
    $type = "hea-aggr";
    my $label = $params->{server};
    $id = PowerDataWrapper::get_item_uid( { type => $type, label => $label } );
  }
  elsif ( $params->{item} =~ "power_sri" && $params->{lpar} =~ m/totals/ ) {
    $type = "sri-aggr";
    my $label = $params->{server};
    $id = PowerDataWrapper::get_item_uid( { type => $type, label => $label } );
  }
  elsif ( $params->{item} =~ "hmctotals" ) {
    $type = "hmc-totals";
    $id   = "";
  }
  else {
    return;
  }

  my $menu = Menu->new( lc 'Power' );
  if ($id) {
    $url = $menu->page_url( $type, $id );
  }
  else {
    $url = $menu->page_url($type);
  }
  return $url;
}

1;

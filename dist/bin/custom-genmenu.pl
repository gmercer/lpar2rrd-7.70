# custom-genmenu.pl
#   parse Custom groups configuration file and create a menu entry for each (supported) custom group
#   this program is expected to be called by `install-html.sh`, which redirects the output to `tmp/menu.txt`

use strict;
use warnings;

use Data::Dumper;
use Xorux_lib qw(error);

#`. /home/lpar2rrd/lpar2rrd/etc/lpar2rrd.cfg`;

###### RUN SCRIPT WITHOUT ARGUMENTS
######
###### .  /home/lpar2rrd/lpar2rrd/etc/lpar2rrd.cfg ; $PERL ./bin/custom-genmenu.pl
######

defined $ENV{INPUTDIR} || error( " Not defined INPUTDIR, probably have not read etc/lpar2rrd.cfg " . __FILE__ . ":" . __LINE__ ) && exit 1;
my $basedir = $ENV{INPUTDIR};

# mostly copied from `custom.pl` (`load_cfg`) and merged with some parts of `install-html.sh` and `find_active_lpar.pl`
sub custom_groups_cfg2menu {
  my $cfg = "$basedir/etc/custom_groups.cfg";
  if ( -f "$basedir/etc/web_config/custom_groups.cfg" ) {
    $cfg = "$basedir/etc/web_config/custom_groups.cfg";
  }

  if ( !-f $cfg ) {

    # cfg does not exist
    error( "custom : custom cfg file does not exist: $cfg " . __FILE__ . ":" . __LINE__ );
    exit 1;
  }

  my $final_menu = "";
  my %hash_lines = ();    # to filter equal lines
  open( FHR, "< $cfg" );
  foreach my $line (<FHR>) {
    chomp($line);
    $line =~ s/ *$//g;    # delete spaces at the end
    if ( $line =~ m/^$/ || $line !~ m/^(POOL|LPAR|VM|XENVM|NUTANIXVM|PROXMOXVM|FUSIONCOMPUTEVM|KUBERNETESNODE|KUBERNETESNAMESPACE|OPENSHIFTNODE|OPENSHIFTPROJECT|OVIRTVM|SOLARISZONE|SOLARISLDOM|HYPERVM|LINUX|ESXI|ORVM|ODB)/ || $line =~ m/^#/ || $line !~ m/:/ || $line =~ m/:$/ || $line =~ m/: *$/ ) {
      next;
    }

    # note: whoever saves the config must ensure that they encode colons inside names properly
    ( my $type, my $server, my $name, my $group_act ) = split( /(?<!\\):/, $line );    # my super regex takes just not backslashed colon
    if ( $type eq '' || $server eq '' || $name eq '' || $group_act eq '' ) {
      error( "custom : syntax error in $cfg: $line " . __FILE__ . ":" . __LINE__ );
      next;
    }
    $server    =~ s/===========doublecoma=========/===double-col===/g;
    $name      =~ s/===========doublecoma=========/===double-col===/g;
    $name      =~ s/\//\&\&1/g;
    $group_act =~ s/ *$//g;                                                            # delete spaces at the end
    $group_act =~ s/===========doublecoma=========/===double-col===/g;
    my $group_act_url = $group_act;
    $group_act_url =~ s/ /%20/g;                                                       # use URL-safe characters for spaces

    # form the menu line
    my $menu_line = "";
    $menu_line .= "C";                                                                 # the first symbol: C from "Custom groups"
    $menu_line .= ":$group_act_url";                                                   # group name encoded
    $menu_line .= ":$group_act";                                                       # group name
    $menu_line .= ":/lpar2rrd-cgi/detail.sh";                                          # base URL
                                                                                       # use $host to communicate the platform to `detail-cgi.pl`
    $menu_line .= "?host=";

    if ( $type eq 'POOL' || $type eq 'LPAR' ) {
      $menu_line .= "Power";
    }
    elsif ( $type eq 'VM' ) {
      $menu_line .= "VMware";
    }
    elsif ( $type eq 'XENVM' ) {
      $menu_line .= "XenServer";
    }
    elsif ( $type eq 'NUTANIXVM' ) {
      $menu_line .= "Nutanix";
    }
    elsif ( $type eq 'PROXMOXVM' ) {
      $menu_line .= "Proxmox";
    }
    elsif ( $type eq 'KUBERNETESNODE' ) {
      $menu_line .= "KubernetesNode";
    }
    elsif ( $type eq 'KUBERNETESNAMESPACE' ) {
      $menu_line .= "KubernetesNamespace";
    }
    elsif ( $type eq 'OPENSHIFTNODE' ) {
      $menu_line .= "OpenshiftNode";
    }
    elsif ( $type eq 'OPENSHIFTPROJECT' ) {
      $menu_line .= "OpenshiftProject";
    }
    elsif ( $type eq 'FUSIONCOMPUTEVM' ) {
      $menu_line .= "FusionCompute";
    }
    elsif ( $type eq 'OVIRTVM' ) {
      $menu_line .= "oVirt";
    }
    elsif ( $type =~ /SOLARISZONE|SOLARISLDOM/ ) {
      $menu_line .= "Solaris";
    }
    elsif ( $type eq 'HYPERVM' ) {
      $menu_line .= "Hyperv";
    }
    elsif ( $type eq 'LINUX' ) {
      $menu_line .= "Linux";
    }
    elsif ( $type eq 'ESXI' ) {
      $menu_line .= "ESXI";
    }
    elsif ( $type eq 'ORVM' ) {
      $menu_line .= "OracleVM";
    }
    elsif ( $type eq 'ODB' ) {
      $menu_line .= "OracleDB";
    }
    else {
      $menu_line .= "na";
    }
    $menu_line .= "&server=na";                   # skip server param
    $menu_line .= "&lpar=$group_act_url";         # group name
    $menu_line .= "&item=custom";                 # it's a custom group...
    $menu_line .= "&entitle=0&gui=1&none=none";
    $menu_line .= ":::::";                        # empty attributes for menu.txt
                                                  # the last symbol identifies the platform
    if ( $type eq 'POOL' || $type eq 'LPAR' ) {
      $menu_line .= "P";
    }
    elsif ( $type eq 'VM' ) {
      $menu_line .= "V";
    }
    elsif ( $type eq 'XENVM' ) {
      $menu_line .= "X";
    }
    elsif ( $type eq 'NUTANIXVM' ) {
      $menu_line .= "N";
    }
    elsif ( $type eq 'PROXMOXVM' ) {
      $menu_line .= "M";
    }
    elsif ( $type eq 'KUBERNETESNODE' || $type eq 'KUBERNETESNAMESPACE' ) {
      $menu_line .= "K";
    }
    elsif ( $type eq 'OPENSHIFTNODE' || $type eq 'OPENSHIFTPROJECT' ) {
      $menu_line .= "R";
    }
    elsif ( $type eq 'FUSIONCOMPUTEVM' ) {
      $menu_line .= "W";
    }
    elsif ( $type eq 'OVIRTVM' ) {
      $menu_line .= "O";
    }
    elsif ( $type =~ /SOLARISZONE|SOLARISLDOM/ ) {
      $menu_line .= "S";
    }
    elsif ( $type eq 'HYPERVM' ) {
      $menu_line .= "H";
    }
    elsif ( $type eq 'LINUX' ) {
      $menu_line .= "L";
    }
    elsif ( $type eq 'ESXI' ) {
      $menu_line .= "E";
    }
    elsif ( $type eq 'ORVM' ) {
      $menu_line .= "U";
    }
    elsif ( $type eq 'ODB' ) {
      $menu_line .= "Q";
    }
    if ( !exists $hash_lines{$menu_line} ) {
      $hash_lines{$menu_line} = 1;
      $final_menu .= "$menu_line\n";
    }

  }
  close(FHR);

  # output
  print $final_menu;

  return 0;
}

# run the code
custom_groups_cfg2menu();

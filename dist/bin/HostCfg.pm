package HostCfg;

# LPAR2RRD user management module
# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=perl
use strict;
use warnings;
use POSIX;
use Data::Dumper;
use Fcntl ':flock';    # import LOCK_* constants
use MIME::Base64 qw( decode_base64 encode_base64 );
use File::Glob qw(bsd_glob GLOB_TILDE);
use File::Copy;
use XoruxEdition;

my $basedir = $ENV{INPUTDIR};
$basedir ||= "..";

my $cfgdir     = "$basedir/etc/web_config";
my $realcfgdir = "$basedir/etc";

use JSON qw(decode_json encode_json);

my $json = JSON->new->utf8->pretty;

my %alerts;       # hash holding alerting configuration
my %emailgrps;    # hash holding e-mail groups
my %config;       # hash holding configuration
my $rawcfg;
my @rawcfg;
my $oldcfg     = 0;
my $now        = time();
my $isotime    = strftime( '%Y-%m-%dT%H:%M:%SZ', gmtime($now) );
my $URL        = "";
my $isimported = 0;
my $vmwlibdir  = "$basedir/vmware-lib/apps";
my $credstore  = "$basedir/.vmware/credstore/vicredentials.xml";
my $vmwarelist = $ENV{VMWARE_LIST} ||= "";
my $perl       = $ENV{PERL};

#if ($ENV{REQUEST_SCHEME} . $ENV{SERVER_NAME} . $ENV{SERVER_PORT}) {
#  $URL = "$ENV{REQUEST_SCHEME}://$ENV{SERVER_NAME}";
#}

#if ($ENV{VM_IMAGE}) {
#  $adminName = "monitor";
#  $adminPass = "\$apr1\$UZuWgWzB\$gk6cSafcM9F2Bl0Jl94ZB.";
#}

sub readCfg {
  my $cfgfile = "$cfgdir/hosts.json";
  my $CFG;
  if ( !open( $CFG, "<", $cfgfile ) ) {
    if ( !open( $CFG, ">", $cfgfile ) ) {
      die "Cannot open file: $cfgfile $!\n";
    }
    else {    # create empty cfg file
      flock( $CFG, LOCK_EX );

      # prepare Power hosts from etc/lpar2rrd.cfg
      use IO::Socket::INET;
      my %imported;
      my $hmclist = $ENV{HMC_LIST} ||= "";
      if ( -e $hmclist && -f _ && -r _ ) {
        $hmclist = `cat $hmclist`;
      }
      elsif ( -e "$basedir/etc/$hmclist" && -f _ && -r _ ) {
        $hmclist = `cat $basedir/etc/$hmclist`;
      }
      my $hmcuser = $ENV{HMC_USER} ||= "lpar2rrd";
      my $sshkey  = $ENV{SSH}      ||= "";
      if ( $hmclist && $hmclist ne "hmc1 sdmc1 ivm1" ) {
        foreach my $hmc ( split " ", $hmclist ) {
          my $sock = IO::Socket::INET->new(
            PeerAddr => $hmc,
            PeerPort => 22,
            Proto    => 'tcp',
            Timeout  => 5
          );

          if ($sock) {
            %{ $imported{$hmc} } = (
              "proto"      => "https",
              "username"   => "$hmcuser",
              "host"       => "$hmc",
              "ssh_port"   => "22",
              "password"   => "",
              "auth_ssh"   => \1,
              "api_port"   => "12443",
              "auth_api"   => \0,
              "ssh_key_id" => "$sshkey"
            );

            close($sock);
            $isimported = 1;
          }
        }
      }
      my $impstringpower = JSON->new->utf8(0)->pretty(1)->encode( \%imported );

      my $impstringvmware = "{}";
      if ( -e "$vmwlibdir/credstore_admin.pl" ) {
        $impstringvmware = JSON->new->utf8(0)->pretty(1)->encode( importVmware() );
      }

      print $CFG <<_MARKER_;
{
   "platforms" : {
      "IBM Power Systems": {
         "order" : 1,
         "ssh" : false,
         "api" : true,
         "aliases" : $impstringpower
      },
      "VMware": {
         "order" : 2,
         "ssh" : false,
         "api" : true,
         "aliases" : $impstringvmware
      },
      "XenServer": {
         "order" : 3,
         "ssh" : true,
         "api" : true,
         "aliases" : {}
      },
      "Hyper-V": {
         "order" : 4,
         "ssh" : false,
         "api" : true,
         "aliases" : {}
      },
      "KVM": {
         "order" : 5,
         "ssh" : true,
         "api" : false,
         "aliases" : {}
      },
      "RHV (oVirt)": {
         "order" : 6,
         "ssh" : false,
         "api" : true,
         "aliases" : {}
      },
      "OracleVM": {
         "order" : 7,
         "ssh" : false,
         "api" : true,
         "aliases" : {}
      },
      "OracleDB": {
         "order" : 8,
         "ssh" : false,
         "api" : true,
         "aliases" : {}
      },
      "Nutanix": {
         "order" : 9,
         "ssh" : false,
         "api" : true,
         "aliases" : {}
      },
      "AWS": {
         "order" : 10,
         "ssh" : false,
         "api" : true,
         "aliases" : {}
      },
      "GCloud": {
         "order" : 11,
         "ssh" : false,
         "api" : true,
         "aliases" : {}
      },
      "Azure": {
         "order" : 12,
         "ssh" : false,
         "api" : true,
         "aliases" : {}
      },
      "Kubernetes": {
         "order" : 13,
         "ssh" : false,
         "api" : true,
         "aliases" : {}
      },
      "Openshift": {
         "order" : 14,
         "ssh" : false,
         "api" : true,
         "aliases" : {}
      },
      "Cloudstack": {
         "order" : 15,
         "ssh" : false,
         "api" : true,
         "aliases" : {}
      },
      "Proxmox": {
         "order" : 16,
         "ssh" : false,
         "api" : true,
         "aliases" : {}
      },
      "PostgreSQL": {
         "order" : 17,
         "ssh" : false,
         "api" : true,
         "aliases" : {}
      },
      "SQLServer": {
         "order" : 18,
         "ssh" : false,
         "api" : true,
         "aliases" : {}
      },
      "FusionCompute": {
         "order" : 19,
         "ssh" : false,
         "api" : true,
         "aliases" : {}
      },
      "DB2": {
         "order" : 20,
         "ssh" : false,
         "api" : true,
         "aliases" : {}
      },
      "IBM Power CMC": {
         "order" : 21,
         "ssh" : false,
         "api" : true,
         "aliases" : {}
      }
    }
  }
_MARKER_

      close $CFG;
      open( $CFG, "<", $cfgfile );

    }
  }
  flock( $CFG, LOCK_SH );
  {
    local $/ = undef;    # required for re-read of encode_json pretty output
    $rawcfg = <$CFG>;
    if ($rawcfg) {
      my ( $goodjson, $count ) = $json->decode_prefix($rawcfg);
      %config = %{$goodjson};

      # print Dumper \%config;
      $rawcfg = $json->encode( \%config );
      if ( ( keys %{ $config{platforms}{VMware}{aliases} } < 1 ) && $vmwarelist ) {
        $config{platforms}{VMware}{aliases} = importVmware();
        close $CFG;
        open( $CFG, ">", $cfgfile );
        print $CFG JSON->new->utf8(0)->pretty(1)->encode( \%config );
        close $CFG;
        open( $CFG, "<", $cfgfile );
        $rawcfg = <$CFG>;
      }
    }
    close $CFG;
  }
  if ( $ENV{GATEWAY_INTERFACE} && !-o $cfgfile ) {
    warn "Can't write to the file $cfgfile, copying to my own!";
    copy( $cfgfile, "$cfgfile.bak" );
    unlink $cfgfile;
    move( "$cfgfile.bak", $cfgfile );
    chmod 0664, $cfgfile;
  }

  # print Dumper \%config;
}

sub getGroups {

  # return sorted array of defined groups
  &readCfg;
  return sort keys %emailgrps;
}

sub getConfig {

  # return configuration hash
  &readCfg;
  return %config;
}

sub getRawConfig {
  readCfg();
  return ( $rawcfg, $isimported );
}

sub getNoPassRawConfig {
  readCfg();
  foreach my $platform ( keys %{ $config{platforms} } ) {
    if ( $config{platforms}{$platform}{aliases} ) {
      foreach my $alias ( keys %{ $config{platforms}{$platform}{aliases} } ) {
        foreach my $key ( keys %{ $config{platforms}{$platform}{aliases}{$alias} } ) {
          if ( $key =~ "password" ) {
            $config{platforms}{$platform}{aliases}{$alias}{$key} = defined $config{platforms}{$platform}{aliases}{$alias}{$key} ? \1 : \0;
          }
        }
      }
    }
  }
  return ( JSON->new->utf8(0)->pretty(1)->encode( \%config ), $isimported );
}

sub getGroupMembers {

  # param: group_name
  # return sorted array of defined alerts
  my $groupName = shift;
  return $emailgrps{$groupName};
}

sub getHostConnections {

  # params: platformName
  # return: hash of hosts connections
  my $platform = shift;

  my $prem = premium();

  readCfg();

  my %hostConns;
  if ( $config{aliases} ) {
    foreach my $key ( keys %{ $config{aliases} } ) {
      my $host = $config{aliases}{$key};
      if ( ( !$platform ) || ( $host->{platform} eq $platform ) ) {
        $hostConns{$key} = $host;
        if ( $hostConns{$key}{password} ) {
          $hostConns{$key}{password} = unobscure_password( $hostConns{$key}{password} );
        }
      }
    }
  }
  else {
    if ( $config{platforms}{$platform}{aliases} ) {
      %hostConns = %{ $config{platforms}{$platform}{aliases} };
      my $cntr = 0;
      foreach my $key ( sort keys %hostConns ) {
        $cntr++;
        if ( $platform eq "IBM Power Systems" ) {
          if ( ( length($prem) != 6 || !-f "$basedir/html/.p" ) && $cntr > 4 ) {
            delete $hostConns{$key};
            next;
          }
        }
        if ( $hostConns{$key}{password} ) {
          $hostConns{$key}{password} = unobscure_password( $hostConns{$key}{password} );
        }
      }
    }
  }
  if ( $platform eq "VMware" ) {
    my @items;
    foreach my $alias ( sort keys %hostConns ) {
      push @items, "$alias|$hostConns{$alias}{host}|$hostConns{$alias}{username}";
    }
    return join( " ", @items );
  }
  else {
    return \%hostConns;
  }
}

sub getHostCfg {

  # params: platformName, hostalias
  # return: ref. hash with hostalias configuration
  my ( $platform, $alias ) = @_;

  readCfg();
  if ( $config{platforms}{$platform} && $config{platforms}{$platform}{aliases} && $config{platforms}{$platform}{aliases}{$alias} ) {
    my $hostcfg = $config{platforms}{$platform}{aliases}{$alias};
    foreach my $key ( keys %{$hostcfg} ) {
      if ( $key =~ "password" ) {
        $hostcfg->{$key} = unobscure_password( $hostcfg->{$key} );
      }
    }
    return $hostcfg;
  }
  else {
    return 0;
  }
}

sub getUnlicensed {
  my $platform = "IBM Power Systems";
  my @list;

  # my $prem = premium();
  readCfg();
  if ( $config{platforms}{$platform}{aliases} ) {
    my %hostConns = %{ $config{platforms}{$platform}{aliases} };
    my $cntr      = 0;
    foreach my $key ( sort keys %hostConns ) {
      $cntr++;

      # if ( ( length($prem) != 6 || !-f "$basedir/html/.p" ) && $cntr > 4 ) {
      if ( $cntr > 4 ) {
        push @list, $key;
      }
    }
  }
  print join "\n", @list;
}

sub getSSHKeys {
  my @keys;
  if ( $ENV{VM_IMAGE} ) {
    my @pubkeys = bsd_glob "$ENV{HOME}/.ssh/*.pub";
    foreach my $pub (@pubkeys) {
      $pub =~ s{\.[^.]+$}{};
      if ( -f $pub ) {
        push @keys, $pub;
      }
    }
  }
  return @keys;
}

sub getEmail {

  # params: group_name, group_member
  # return full name of a member
  my ( $groupName, $groupMem ) = @_;
  return $alerts{groups}{$groupName}{$groupMem}{email};
}

sub getUserDetails {

  # params: group_name, group_member
  # return hash of member details
  my ( $groupName, $groupMem ) = @_;
  return $alerts{groups}{$groupName}{$groupMem};
}

sub unobscure_password {
  my $string    = shift;
  my $unobscure = decode_base64($string);
  $unobscure = unpack( chr( ord("a") + 19 + print "" ), $unobscure );
  return $unobscure;
}

sub obscure_password {
  my $string  = shift;
  my $obscure = encode_base64( pack( "u", $string ), "" );
  return $obscure;
}

# prepare VMware hosts from etc/webconfig/vmware.cfg
sub importVmware {
  my %imported = ();
  if ($vmwarelist) {
    my @vhosts = split( " ", $vmwarelist );
    foreach my $vcfg (@vhosts) {
      my ( $alias, $host, $username ) = split( /\|/, $vcfg );
      my $passresp = `$perl $basedir/vmware-lib/apps/credstore_admin.pl get --server '$host' --username '$username' 2>&1`;
      if ( $passresp =~ /^Password: .*/ ) {
        my ( undef, $password ) = split( " ", $passresp );
        %{ $imported{$alias} } = (
          "proto"    => "https",
          "username" => "$username",
          "host"     => "$host",
          "password" => obscure_password($password),
          "auth_ssh" => \0,
          "api_port" => "443",
          "auth_api" => \1,
        );
      }
    }
  }
  return ( \%imported );
}

1;

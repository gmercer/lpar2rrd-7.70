package Users;

# LPAR2RRD user management module
# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=perl
use strict;
use warnings;
use POSIX;
use Data::Dumper;
use Fcntl ':flock';    # import LOCK_* constants
use File::Copy;

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
my $oldcfg    = 0;
my $now       = time();
my $isotime   = strftime( '%Y-%m-%dT%H:%M:%SZ', gmtime($now) );
my $adminName = $ENV{REMOTE_USER} ||= "admin";
my $adminPass = "\$apr1\$CSoXefyw\$wGe9K7Ld5ClOEozE4zC.T1";

#if ($ENV{VM_IMAGE}) {
#  $adminName = "monitor";
#  $adminPass = "\$apr1\$UZuWgWzB\$gk6cSafcM9F2Bl0Jl94ZB.";
#}

sub readCfg {
  my $force_user_list = shift;    # pass true value to force read cfg from users.json
  my $CFG;
  my $aclAdminGroup = $ENV{ACL_ADMIN_GROUP} ||= "admins";
  my $cfg_filename  = "users.json";
  if ( !$force_user_list && defined $ENV{HTTP_XORUX_APP} && $ENV{HTTP_XORUX_APP} eq "Xormon" ) {
    $cfg_filename = "users-xormon.json";
  }
  my $cfgfile = "$cfgdir/$cfg_filename";
  if ( !open( $CFG, "<", $cfgfile ) ) {
    if ( !open( $CFG, ">", $cfgfile ) ) {
      die("$!: $cfgfile");
    }
    else {                        # create empty cfg file
      flock( $CFG, LOCK_EX );
      print $CFG <<_MARKER_;
{
  "ACLimported" : false,
  "groups" : {
    "$aclAdminGroup": {
      "description": "LPAR2RRD Administrators",
      "ACL": {
        "lpars": {},
        "pools": {},
        "cgroups": ["*"],
        "vms": {},
        "solo": {}
      }
    },
    "ReadOnly": {
      "description": "Member can see everything but nothing can change."
    }
  },
  "users" : {
    "$adminName": {
      "name":            "LPAR2RRD Administrator",
      "email":           "",
      "htpassword":      "$adminPass",
      "active":          1,
      "created":         "$isotime",
      "updated":         "$isotime",
      "last_login":      "",
      "groups": [
        "$aclAdminGroup"
      ],
      "config": {
        "locale":        "en-US",
        "timezone":      "",
        "menu_width":    150,
        "db_height":     50,
        "db_width":      120,
        "db_items": [
        ]
      }
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
    }
  }
  close $CFG;
  if ( !$config{ACLimported} || $config{ACLimported} eq "false" ) {
    if ( open( my $ACL, "<", "$cfgdir/acl.cfg" ) ) {
      my %acl;
      while ( my $line = <$ACL> ) {
        chomp $line;
        next unless s/^([^|]*?)\|([^|]*?)\|([^|]*?)\|(.*)//, $line;
        my @val = split( /\|/, $line );
        for (@val) {
          &pipes($_);
        }
        my ( $group, $cgrp, $srv, $lpar ) = @val;

        my @servers = ( split /,/, $srv );
        chomp @servers;
        if (@servers) {
          $acl{$group}{servers} = [@servers];
        }

        my @customs = ( split /,/, $cgrp );
        chomp @customs;
        if (@customs) {
          $acl{$group}{cgroups} = [@customs];
        }

        if ($lpar) {
          for my $field ( split /,/, $lpar ) {
            my ( $key, $value ) = ( split /=>/, $field );
            if ($value) {
              $acl{$group}{lpars}{$key}{$value} = 1;
            }
          }
        }
      }
      close $ACL;
      foreach my $grp ( keys %acl ) {
        $config{groups}{$grp}{ACL}{lpars} = ();
        foreach my $srv ( @{ $acl{$grp}{servers} } ) {
          $config{groups}{$grp}{ACL}{lpars}{$srv} = [];
          push @{ $config{groups}{$grp}{ACL}{lpars}{$srv} }, "*";
        }
        $config{groups}{$grp}{ACL}{cgroups} = $acl{$grp}{cgroups} ||= [];
        foreach my $srv ( keys %{ $acl{$grp}{lpars} } ) {
          $config{groups}{$grp}{ACL}{lpars}{$srv} = [ keys %{ $acl{$grp}{lpars}{$srv} } ];
        }
      }

      # print STDERR Dumper \%config;
      $config{ACLimported} = \1;
      if ( open( $CFG, ">", $cfgfile ) ) {
        flock( $CFG, LOCK_EX );
        print $CFG $json->encode( \%config );
        close $CFG;
      }

    }
  }
  if ( !$config{groups}{ReadOnly} ) {
    $config{groups}{ReadOnly}{description} = "Member can see everything but nothing can change.";
    $rawcfg = $json->encode( \%config );
  }
  close $CFG;
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
  readCfg();
  return sort keys %emailgrps;
}

sub getDefinedAlerts {

  # return sorted array of defined alerts
  &readCfg;
  return sort keys %alerts;
}

sub getAlerts {

  # return sorted array of defined alerts
  &readCfg;
  return %alerts;
}

sub getConfig {
  my $force_user_list = shift;    # pass true value to force read cfg from users.json

  # return configuration hash
  readCfg($force_user_list);
  return %config;
}

sub getRawConfig {
  my $force_user_list = shift;    # pass true value to force read cfg from users.json
  readCfg($force_user_list);
  return $rawcfg;
}

sub getHTPasswords {
  readCfg();
  my $result = "";
  foreach my $user ( sort keys %{ $config{users} } ) {
    if ( $config{users}{$user}{active} && $config{users}{$user}{htpassword} ) {
      $result .= "$user:$config{users}{$user}{htpassword}\n";
    }
  }
  return $result;
}

sub getAlertDetails {

  # params: alert_name
  # return hash of alert details
  my ( $storage, $type, $name, $metric ) = shift;
  return $alerts{$storage}{$type}{$name}{$metric};
}

sub getGroupMembers {

  # param: group_name
  # return sorted array of defined alerts
  my $groupName = shift;
  return $emailgrps{$groupName};
}

sub getFullName {

  # params: group_name, group_member
  # return full name of a member
  my ( $groupName, $groupMem ) = @_;
  return $alerts{groups}{$groupName}{$groupMem}{fullname};
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

sub readDashboards {
  my $CFG;
  my $dashBoards = { users => {} };
  my $cfgfile    = "$cfgdir/dashboards.json";
  if ( !open( $CFG, "<", $cfgfile ) ) {
    if ( !open( $CFG, ">", $cfgfile ) ) {
      die("$!: $cfgfile");
    }
    else {    # create empty dashboard cfg file, import existing dashboards from users.json
      &readCfg;
      if ( $config{users} ) {
        flock( $CFG, LOCK_EX );
        foreach my $user ( keys %{ $config{users} } ) {
          if ( $config{users}{$user}{dashboard} ) {
            $dashBoards->{users}{$user}{dashboard} = delete $config{users}{$user}{dashboard};
          }
        }
        print $CFG $json->encode($dashBoards);
        close $CFG;
        warn "INFO: Users dashboards extracted from users.json, saved to dashboards.json";
        if ( open( $CFG, ">", "$cfgdir/users.json" ) ) {
          flock( $CFG, LOCK_EX );
          print $CFG $json->encode( \%config );
          close $CFG;
          warn "INFO: Removed users dashboards from users.json";
        }
      }
      open( $CFG, "<", $cfgfile );
    }
  }
  flock( $CFG, LOCK_SH );
  {
    local $/ = undef;    # required for re-read of encode_json pretty output
    $rawcfg = <$CFG>;
    if ($rawcfg) {
      my ( $goodjson, $count ) = $json->decode_prefix($rawcfg);
      %{$dashBoards} = %{$goodjson};

      # print Dumper \%config;
    }
  }
  close $CFG;
  return $dashBoards;
}

sub storeUserDashboard {

  # params: username, newdashboard
  my $username     = shift;
  my $newdashboard = shift;
  if ($username) {
    my $dashboards = readDashboards;
    $dashboards->{users}{$username}{dashboard} = $newdashboard;
    if ( open( my $CFG, ">", "$cfgdir/dashboards.json" ) ) {
      flock( $CFG, LOCK_EX );
      print $CFG $json->encode($dashboards);
      close $CFG;
    }
  }
}

sub loadUserDashboard {

  # params: username, newdashboard
  my $username = shift;
  if ($username) {
    my $dashboards = readDashboards;
    if ( $dashboards->{users}{$username} && $dashboards->{users}{$username}{dashboard} ) {
      return $dashboards->{users}{$username}{dashboard};
    }
    else {
      return {};
    }
  }
  else {
    return {};
  }
}

sub doublecoma {
  return s/===========doublecoma=========/:/g;
}

sub pipes {
  return s/===pipe===/\|/g;
}

1;

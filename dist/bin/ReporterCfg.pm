package ReporterCfg;

# LPAR2RRD user management module
# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=perl
use strict;
use warnings;
use POSIX;
use Data::Dumper;

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
my $oldcfg  = 0;
my $now     = time();
my $isotime = strftime( '%Y-%m-%dT%H:%M:%SZ', gmtime($now) );
my $URL     = "";

#if ($ENV{REQUEST_SCHEME} . $ENV{SERVER_NAME} . $ENV{SERVER_PORT}) {
#  $URL = "$ENV{REQUEST_SCHEME}://$ENV{SERVER_NAME}";
#}

#if ($ENV{VM_IMAGE}) {
#  $adminName = "monitor";
#  $adminPass = "\$apr1\$UZuWgWzB\$gk6cSafcM9F2Bl0Jl94ZB.";
#}

sub readCfg {
  my $CFG;
  my $cfgfile = "$cfgdir/reporter.json";
  if ( !open( $CFG, $cfgfile ) ) {
    if ( !open( $CFG, ">", $cfgfile ) ) {
      die("$!: $cfgfile");
    }
    else {    # create empty cfg file
      print $CFG <<_MARKER_;
{
  "global": {
    "product": "LPAR2RRD",
    "URL": "$URL"
  },
  "users": {
    "admin": {
      "groups" : {
        "admins": {
          "description": "LPAR2RRD Administrators"
        }
      },
      "reports" : {}
    }
  }
}
_MARKER_

      close $CFG;
      open( $CFG, $cfgfile );
    }
  }
  {
    local $/ = undef;    # required for re-read of encode_json pretty output
    $rawcfg = <$CFG>;
    if ($rawcfg) {
      %config = %{ decode_json($rawcfg) };
    }
  }
  close $CFG;
  if ( $ENV{GATEWAY_INTERFACE} && !-o $cfgfile ) {
    warn "Can't write to the file $cfgfile, copying to my own!";
    use File::Copy;
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

  # return configuration hash
  &readCfg;
  return %config;
}

sub getRawConfig {
  &readCfg;
  return $rawcfg;
}

sub getHTPasswords {
  &readCfg;
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

sub doublecoma {
  return s/===========doublecoma=========/:/g;
}

sub pipes {
  return s/===pipe===/\|/g;
}

1;

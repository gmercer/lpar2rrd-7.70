package Alerting;

# LPAR2RRD alerting module
# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=perl
use strict;
use warnings;

use Data::Dumper;

# use CGI::Carp qw(fatalsToBrowser);
use File::Copy;

my $basedir = $ENV{INPUTDIR};
$basedir ||= "..";

my $cfgdir     = "$basedir/etc/web_config";
my $realcfgdir = "$basedir/etc";

my %alerts;       # hash holding alerting configuration
my %emailgrps;    # hash holding e-mail groups
my %config;       # hash holding configuration
my @rawcfg;
my $oldcfg = 0;

sub readCfg {
  my $CFG;
  my $cfgfile = "$cfgdir/alerting.cfg";
  if ( !open( $CFG, "<", $cfgfile ) ) {
    if ( !open( $CFG, "<", "$realcfgdir/alert.cfg" ) ) {
      if ( !open( $CFG, ">", $cfgfile ) ) {
        die("$!: $cfgfile");
      }
      else {    # create empty cfg file
        print $CFG <<_MARKER_;
# LPAR|POOL]:server:[lpar name|pool name]:metric:limit:peak time in min:alert repeat time in min:exclude time:email group
#==================================================================================================================================
# Nagios alerting
# Call this script from nrpe.cfg: bin/check_lpar2rrd
# More details on http://www.stor2rrd.com/nagios.html
NAGIOS=1        # [0/1] on/off Nagios support for alerting

# alert history log
# ALERT_HISTORY=/home/lpar2rrd/lpar2rrd/logs/alert_history.log

# use external script for alerting
# it will be called once an alarm appears with these 7 parameters
# script.sh  <storage> <volume> <metric> <actual value> <limit>
# you can use bin/external_alert_example.sh as an example
# use the full path or relative path to the script
EXTERN_ALERT=bin/external_alert_example.sh

# include graphs into the email notification 0 - false, last 1 - X hours included in the graphs
EMAIL_GRAPH=25

# default time in minutes which says how often you should be alerted
# you can specify per volume different value in "alert repeat time" column of each ALERT
REPEAT_DEFAULT=60

# default time in minutes for length of traffic peak
# (the time when avg traffic utilization must be above of specified limit to generate an alert)
# you can change it per volume level in "time in min" column of each ALERT
# note it should not be shorter than sample rate for particular storage (usually 5 minutes)
PEAK_TIME_DEFAULT=30
_MARKER_

        close $CFG;
        open( $CFG, $cfgfile );
      }
    }
    $oldcfg = 1;
  }
  @rawcfg = ();
  while ( my $line = <$CFG> ) {
    chomp($line);
    push @rawcfg, $line;
    $line =~ s/\\:/===========doublecoma=========/g;    # workround for names with colon inside
    if ( $line =~ /^WEB_UI_URL|^JIRA_URL/ ) {
      my @val = split( /=/, $line, 2 );
      chomp @val;
      $config{ $val[0] } = $val[1];
      next;
    }
    $line =~ s/ *$//g;                                  # delete spaces at the end
    if ( $line =~ m/^$/
      || $line =~ m/^#/ )
    {
      next;
    }
    if ( $line =~ m/:/ ) {
      my @val = split( /:/, $line );

      for (@val) {
        &doublecoma($_);
      }

      # LPAR|POOL]:server:[lpar name|pool name]:metric:limit:peak time in min:alert repeat time in min:exclude time:email group
      my ( $type, $server, $name, $item, $limit, $peak, $repeat, $exclude, $mailgrp, $uuid, $cluster, $user );

      if ($oldcfg) {
        ( $type, $server, $name, $limit, undef, $peak, $repeat, $mailgrp ) = @val;
        if ( $type eq "SWAP" ) {
          ( $type, $server, $name, $limit, $peak, $repeat, $mailgrp ) = @val;
        }
        $item    = "CPU";
        $exclude = "";
      }
      else {
        ( $type, $server, $name, $item, $limit, $peak, $repeat, $exclude, $mailgrp, $uuid, $cluster, $user ) = @val;
      }
      if ( $mailgrp && $mailgrp =~ "@" ) {
        push @{ $emailgrps{Default} }, $mailgrp;
        $mailgrp = "Default";
      }
      $mailgrp ||= "";
      $server  ||= "";

      if ( $type eq "LPAR" || $type eq "POOL" ) {

        # print STDERR $line . "\n";
        # push @cfggrp, $group_name;
        # my $idx = keys %{$alerts{$storage}{$type}{$name}{$item}};
        if ( $type eq "POOL" && $name eq "all_pools" ) {
          $name = "CPU pool";
        }
        my $rule = { limit => $limit, peak => $peak, repeat => $repeat, exclude => $exclude, mailgrp => $mailgrp, user => $user };
        if ($uuid) {
          $server = $cluster;
          $rule->{uuid} = $uuid;
        }
        push @{ $alerts{$server}{$type}{$name}{$item} }, $rule;

        #$alerts{$storage}{$type}{$name}{$item}{$idx}{limit} = $limit;
        #$alerts{$storage}{$type}{$name}{$item}{$idx}{peek} = $peek;
        #$alerts{$storage}{$type}{$name}{$item}{$idx}{repeat} = $repeat;
        #$alerts{$storage}{$type}{$name}{$item}{$idx}{exclude} = $exclude;
        #$alerts{$storage}{$type}{$name}{$item}{$idx}{mailgrp} = $mailgrp;

        # print Dumper \%alerts;

      }
      elsif ( $type eq "SWAP" ) {
        if ( $server eq '.*' ) {
          $server = "";
        }
        if ( $name eq '.*' ) {
          $name = "";
        }
        if ( $server !~ /[\?\*]/ && $name !~ /[\?\*]/ ) {
          $item = "PAGING1";
          $limit /= 1000;
          my $rule = { limit => $limit, peak => $peak, repeat => $repeat, exclude => $exclude, mailgrp => $mailgrp, user => $user };
          push @{ $alerts{$server}{LPAR}{$name}{$item} }, $rule;
        }
        else {
          error("Regex are not supported in this version: $line");
        }
      }
      elsif ( $type eq "EMAIL" ) {
        my @mails;
        if ($name) {
          @mails = ( split /,/, $name );
          chomp(@mails);
          s{^\s+|\s+$}{}g foreach @mails;
          push @{ $emailgrps{$server} }, @mails;
        }
      }
      elsif ( $type eq "OracleDB" ) {
        my $rule = { limit => $limit, peak => $peak, repeat => $repeat, exclude => $exclude, mailgrp => $mailgrp, user => $user };
        push @{ $alerts{$type}{$server}{$name}{$item} }, $rule;
      }
    }
    elsif ( $line =~ m/=/ ) {
      my @val = split( /=/, $line, 2 );
      if ( $val[0] eq "PEEK_TIME_DEFAULT" ) {
        $val[0] = "PEAK_TIME_DEFAULT";
      }
      if ( $val[0] =~ "EMAIL_" ) {
        if ( $val[0] ne "EMAIL_ADMIN" && $val[0] ne "EMAIL_GRAPH" && $val[0] ne "EMAIL_EVENT" ) {
          my $mgrp  = ( split "EMAIL_", $val[0] )[1];
          my @mails = ( split /,/,      $val[1] );
          chomp(@mails);
          s{^\s+|\s+$}{}g foreach @mails;
          push @{ $emailgrps{$mgrp} }, @mails;
        }
        else {
          $config{ $val[0] } = ( split /\s+/, $val[1] )[0];
        }
      }
      else {
        $config{ $val[0] } = ( split /\s+/, $val[1] )[0];
      }
    }
  }
  close $CFG;
  if ( $ENV{GATEWAY_INTERFACE} && !-o $cfgfile ) {
    warn "Can't write to the file $cfgfile, copying to my own!";
    copy( $cfgfile, "$cfgfile.bak" );
    unlink $cfgfile;
    move( "$cfgfile.bak", $cfgfile );
    chmod 0664, $cfgfile;
  }

  # print Dumper \%emailgrps;
}

sub getDefinedGroups {

  # return sorted array of defined groups
  readCfg();
  return sort keys %emailgrps;
}

sub getDefinedAlerts {

  # return sorted array of defined alerts
  readCfg();
  return sort keys %alerts;
}

sub getAlerts {

  # return sorted array of defined alerts
  readCfg();
  return %alerts;
}

sub getConfig {

  # return configuration hash
  readCfg();
  return %config;
}

sub getConfigRef {

  # return reference to configuration hash
  readCfg();
  return \%config;
}

sub printConfig {
  readCfg();

  #warn @rawcfg;
  print join( "\n", @rawcfg );
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

# error handling
sub error {
  my $text     = shift;
  my $act_time = localtime();
  chomp($text);

  #print "ERROR          : $text : $!\n";
  print STDERR "$act_time: $text : $!\n";

  return 1;
}

1;

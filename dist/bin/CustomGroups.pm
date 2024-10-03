package CustomGroups;

use strict;
use warnings;

use CGI::Carp qw(fatalsToBrowser);
use File::Copy;

#use Data::Dumper;

my %grp;
my @rawacl;
my @cfggrp;    # array of groups from acl.cfg

my $basedir = $ENV{INPUTDIR} ||= "/home/lpar2rrd/lpar2rrd";

my $cfgdir     = "$basedir/etc/web_config";
my $realcfgdir = "$basedir/etc";
if ( defined $ENV{TMPDIR_LPAR} ) {
  my $tmpdir = $ENV{TMPDIR_LPAR};
}

sub readCfg {
  my $CFG;
  my $cfgfile = "$cfgdir/custom_groups.cfg";
  if ( !open( $CFG, $cfgfile ) ) {
    if ( !open( $CFG, "$realcfgdir/custom_groups.cfg" ) ) {
      if ( !open( $CFG, ">", $cfgfile ) ) {
        die("$!: $cfgfile");
      }
      else {
        close $CFG;
        if ( !open( $CFG, $cfgfile ) ) {
          die("$!: $cfgfile");
        }
      }
    }
  }

  while ( my $line = <$CFG> ) {
    chomp($line);
    $line =~ s/\\:/===========doublecoma=========/g;    # workround for lpars/pool/groups with double coma inside the name
    $line =~ s/ *$//g;                                  # delete spaces at the end
    if ( $line =~ m/^$/
      || ( $line !~ m/^POOL/ && $line !~ m/^LPAR/ && $line !~ m/^NUTANIXVM/ && $line !~ m/^PROXMOXVM/ && $line !~ m/^FUSIONCOMPUTEVM/ && $line !~ m/^KUBERNETESNODE/ && $line !~ m/^KUBERNETESNAMESPACE/ && $line !~ m/^OPENSHIFTNODE/ && $line !~ m/^OPENSHIFTPROJECT/ && $line !~ m/^VM/ && $line !~ m/^XENVM/ && $line !~ m/^OVIRTVM/ && $line !~ m/^SOLARISZONE/ && $line !~ m/^SOLARISLDOM/ && $line !~ m/^HYPERVM/ && $line !~ m/^LINUX/ && $line !~ m/^ORVM/ && $line !~ m/^ESXI/ && $line !~ m/^ODB/ )
      || $line =~ m/^#/
      || $line !~ m/:/
      || $line =~ m/:$/
      || $line =~ m/: *$/ )
    {
      next;
    }
    my @val = split( /:/, $line );

    for (@val) {
      &doublecoma($_);
    }

    # my ($group, $cgrp, $srv, $lpar) = @val;
    my ( $type, $server, $name, $group_name, $collection ) = @val;

    push @rawacl, $line;

    push @cfggrp, $group_name;

    push @{ $grp{"$group_name"}{"children"}{$server} }, $name;
    $grp{"$group_name"}{"type"} = $type;
    if ($collection) {
      $grp{"$group_name"}{"collection"} = $collection;
    }

    # print Dumper \%grp;
  }
  close $CFG;
  if ( $ENV{GATEWAY_INTERFACE} && !-o $cfgfile ) {
    warn "Can't write to the file $cfgfile, copying to my own!";
    copy( $cfgfile, "$cfgfile.bak" );
    unlink $cfgfile;
    move( "$cfgfile.bak", $cfgfile );
    chmod 0664, $cfgfile;
  }
}

sub getCfgGroups {
  readCfg();
  return @cfggrp;
}

sub getGrp {
  readCfg();
  return %grp;
}

sub getRawCfg {
  readCfg();
  return @rawacl;
}

sub getCollections {
  readCfg();
  my %coll;
  foreach my $cgrp ( keys %grp ) {
    my $colname = $grp{$cgrp}{"collection"};
    if ($colname) {
      $coll{collection}{$colname}{$cgrp} = 1;
    }
    else {
      $coll{nocollection}{$cgrp} = 1;
    }
  }
  return %coll;
}

sub doublecoma {
  return s/===========doublecoma=========/:/g;
}

sub pipes {
  return s/===pipe===/\|/g;
}
1;

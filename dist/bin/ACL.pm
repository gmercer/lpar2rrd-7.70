package ACL;

use strict;
use warnings;

use Data::Dumper;

my $basedir = $ENV{INPUTDIR};
$basedir ||= "..";

my $cfgdir = "$basedir/etc/web_config";
if ( defined $ENV{TMPDIR_LPAR} ) {
  my $tmpdir = $ENV{TMPDIR_LPAR};
}

use Users;

# print STDERR "ACL: $useacl\n";
# print Dumper \%ENV;

# $user ||= "tester";

#$gids = "CN=lpar2rrd-admins,CN=Users,DC=xorux,DC=com; CN=lpar2rrd-marketing,CN=Users,DC=xorux,DC=com";
sub new {
  my $self = {};
  bless $self;
  $self->{uid}            = shift if @_;
  $self->{useacl}         = 0;
  $self->{acl}            = ();
  $self->{rawacl}         = ();
  $self->{grplist}        = ();
  $self->{xm_backend_uid} = "";

  if ( $self->{uid} && !$ENV{REMOTE_USER} ) {
    $ENV{XORUX_ACCESS_CONTROL} = 1;
  }
  elsif ( !$ENV{XORUX_ACCESS_CONTROL} && $ENV{XORMON} && defined $ENV{HTTP_REMOTE_USER} ) {
    $self->{uid} = $ENV{HTTP_REMOTE_USER};
  }
  else {
    $self->{uid} = $ENV{REMOTE_USER};
  }
  $self->{aclAdminGroup} = $ENV{ACL_ADMIN_GROUP} ||= "admins";

  my $aclGrpListVar = $ENV{ACL_GRPLIST_VARNAME};
  if ( !defined $aclGrpListVar || $aclGrpListVar eq "" ) {
    $aclGrpListVar = 0;
  }

  if ( $aclGrpListVar && defined $ENV{$aclGrpListVar} && $self->{uid} ) {
    $self->{useacl} = 1;
  }
  elsif ( !$ENV{DISABLE_ACL} && ( $ENV{XORUX_ACCESS_CONTROL} || $ENV{HTTP_XORUX_ACCESS_CONTROL} ) && $self->{uid} ) {
    $self->{useacl} = 2;
  }
  $self->{cfg} = { Users::getConfig(1) };
  foreach my $group ( keys %{ $self->{cfg}{groups} } ) {
    foreach my $section ( keys %{ $self->{cfg}{groups}{$group}{ACL}{sections} } ) {
      $$self{cfg}{groups}{$group}{ACL}{sections}{$section} = $$self{cfg}{groups}{$group}{ACL}{sections}{$section} ? 1 : 0;
    }
  }

  if ( $self->{useacl} == 2 ) {
    if ( noVivDefined( $self->{cfg}{users}{ $self->{uid} }{groups} ) ) {
      @{ $self->{grplist} } = @{ $self->{cfg}{users}{ $self->{uid} }{groups} };
    }
    if ( !@_ && $ENV{XORMON} && defined $ENV{HTTP_XORMON_USER} && $self->isAdmin() ) {
      $self->{xm_backend_uid} = $self->{uid};
      $self->{uid}            = $ENV{HTTP_XORMON_USER};
      $self->{cfg}            = { Users::getConfig() };
      if ( noVivDefined( $self->{cfg}{users}{ $self->{uid} }{groups} ) ) {
        @{ $self->{grplist} } = @{ $self->{cfg}{users}{ $self->{uid} }{groups} };
      }
    }
  }
  elsif ( $self->{useacl} == 1 ) {
    my $gids = $ENV{$aclGrpListVar};
    if ( $gids =~ "=" ) {
      my @groups = split( /;/, $gids );
      chomp @groups;
      foreach my $group (@groups) {
        if ($group) {
          my $grpcn = ( split( /[=,]/, $group ) )[1];
          push @{ $self->{grplist} }, $grpcn;
        }
      }
      if ( $ENV{AUTHENTICATE_PRIMARYGROUPID} && $ENV{AUTHENTICATE_PRIMARYGROUPID} == 513 ) {    # add primary group if exists (Domain Users)
        push @{ $self->{grplist} }, "Domain Users";
      }
    }
    elsif ( $gids =~ "|" ) {
      my @groups = split( /\|/, $gids );
      chomp @groups;
      foreach my $group (@groups) {
        chomp $group;
        if ($group) {

          #	my $grpcn = (split(/\//, $group))[-1];
          push @{ $self->{grplist} }, $group;
        }
      }
    }
  }
  else {
    push @{ $self->{grplist} }, $self->{aclAdminGroup};
  }

  # warn Dumper $self->{cfg}{groups};

  return $self;
}

sub getUser {
  my $self = shift;
  return $self->{uid};
}

sub getAdminGroup {
  my $self = shift;
  return $self->{aclAdminGroup};
}

sub getGroups {
  my $self = shift;
  return $self->{grplist};
}

sub getGroupsHtml {
  my $self = shift;

  my $list = "<b>Group membership</b></br>" . join "</br>", sort @{ $self->{grplist} };
  return $list;
}

sub getAcl {
  my $self = shift;
  return $self->{acl};
}

sub getRawAcl {
  my $self = shift;
  return $self->{rawacl};
}

sub getSections {
  my $self     = shift;
  my @sections = qw/power vmware solo cgroup linux/;
  my %ret;
  foreach my $sec (@sections) {
    $ret{$sec} = 0;
  }
  foreach my $group ( @{ $self->{grplist} } ) {
    if ( !noVivDefined( $self->{cfg}{groups}{$group} ) ) {
      next;
    }
    foreach my $sec (@sections) {
      if ( noVivDefined( $self->{cfg}{groups}{$group}{ACL}{sections}{$sec} ) && $self->{cfg}{groups}{$group}{ACL}{sections}{$sec} ) {
        $ret{$sec} = 1;
      }
    }
  }
  return %ret;
}

sub getCustoms {
  my $self = shift;
  my @custgrps;
  foreach my $group ( @{ $self->{grplist} } ) {
    if ( !exists $self->{cfg}{groups}{$group} ) {
      next;
    }
    if ( noVivDefined( $self->{cfg}{groups}{$group}{ACL}{cgroups} ) ) {
      foreach ( @{ $self->{cfg}{groups}{$group}{ACL}{cgroups} } ) {
        if ( ( noVivDefined( $self->{cfg}{groups}{$group}{ACL}{sections}{cgroup} ) && $$self{cfg}{groups}{$group}{ACL}{sections}{cgroup} ) || $_ eq "*" ) {
          @custgrps = ('*');
          return @custgrps;
        }
        push @custgrps, $_;
      }
    }
  }
  return uniq(@custgrps);
}

sub isAdmin {
  my $self = shift;

  #warn "$self->{xm_backend_uid} $self->{uid}";
  if ( $self->{xm_backend_uid} ) {
    return 1;
  }
  elsif ( grep /^$self->{aclAdminGroup}$/, @{ $self->{grplist} } ) {
    return 1;
  }
}

sub isReadOnly {
  my $self = shift;
  if ( grep /^ReadOnly$/, @{ $self->{grplist} } ) {
    return 1;
  }
}

sub canShow {
  my ( $self, $platform, $subsys, $source, $item, $username ) = @_;

  if ( $self->isAdmin ) {
    return 1;
  }
  if ( $self->isReadOnly ) {
    return 8;    # maybe it will be usefull to know it's RO ACL, return specific value (8)
  }

  $source = urldecode($source);
  $item   = urldecode($item);
  $subsys ||= "";

  foreach my $group ( @{ $self->{grplist} } ) {

    # trace();
    if ( !noVivDefined( $$self{cfg}{groups}{$group} ) ) {

      # warn $group . " not found canShow";
      next;
    }

    # warn $group;
    if ( $subsys eq "CUSTOM" ) {
      if ( ( noVivDefined( $self->{cfg}{groups}{$group}{ACL}{sections}{cgroup} ) && $$self{cfg}{groups}{$group}{ACL}{sections}{cgroup} )
        || ( $source && ( grep /^$source$|\*/, @{ $self->{cfg}{groups}{$group}{ACL}{cgroups} } ) ) )
      {
        return 3;
      }
    }
    elsif ( $platform eq "POWER" ) {
      if ( noVivDefined( $$self{cfg}{groups}{$group}{ACL}{sections}{power} ) && $$self{cfg}{groups}{$group}{ACL}{sections}{power} ) {

        # warn $$self{cfg}{groups}{$group}{ACL}{sections}{power};
        return 9;
      }
      elsif ( $subsys eq "SERVER" ) {
        if ( $source
          && noVivDefined( $self->{cfg}{groups}{$group}{ACL}{lpars}{$source} )
          && noVivDefined( $self->{cfg}{groups}{$group}{ACL}{pools}{$source} )
          && ( grep( /^\*$/, @{ $self->{cfg}{groups}{$group}{ACL}{lpars}{$source} } ) || grep( /^\*$/, @{ $self->{cfg}{groups}{$group}{ACL}{pools}{$source} } ) ) )
        {
          return 2;
        }
      }
      elsif ( $subsys eq "LPAR" ) {

        # warn $self->{cfg}{groups}{$group}{ACL}{lpars}{$source};
        if ( $source
          && noVivDefined( $self->{cfg}{groups}{$group}{ACL}{lpars}{$source} )
          && ( grep( /^$item$/, @{ $self->{cfg}{groups}{$group}{ACL}{lpars}{$source} } ) || grep( /^\*$/, @{ $self->{cfg}{groups}{$group}{ACL}{lpars}{$source} } ) ) )
        {
          return 3;
        }
        if ( $self->{cfg}{options}{acl_power_server_ignore} ) {
          foreach my $srv ( keys %{ $self->{cfg}{groups}{$group}{ACL}{lpars} } ) {
            if ( grep( /^$item$/, @{ $self->{cfg}{groups}{$group}{ACL}{lpars}{$srv} } ) || grep( /^\*$/, @{ $self->{cfg}{groups}{$group}{ACL}{lpars}{$srv} } ) ) {
              return 3;
            }
          }
        }
      }
      elsif ( $subsys eq "POOL" ) {
        if ( $source
          && noVivDefined( $self->{cfg}{groups}{$group}{ACL}{pools}{$source} )
          && ( grep( /^$item$/, @{ $self->{cfg}{groups}{$group}{ACL}{pools}{$source} } ) || grep( /^\*$/, @{ $self->{cfg}{groups}{$group}{ACL}{pools}{$source} } ) ) )
        {
          return 3;
        }
      }
    }
    elsif ( $platform eq "VMWARE" ) {
      if ( noVivDefined( $self->{cfg}{groups}{$group}{ACL}{sections}{vmware} ) && $self->{cfg}{groups}{$group}{ACL}{sections}{vmware} ) {
        return 2;
      }
      elsif ( $subsys eq "VM" ) {
        if ( noVivDefined( $self->{cfg}{groups}{$group}{ACL}{vms}{$source} )
          && ( grep( /^$item$/, @{ $self->{cfg}{groups}{$group}{ACL}{vms}{$source} } ) || grep( /^\*$/, @{ $self->{cfg}{groups}{$group}{ACL}{vms}{$source} } ) ) )
        {
          return 2;
        }
      }
      elsif ( $subsys eq "CLUSTER" ) {
        if ( noVivDefined( $self->{cfg}{groups}{$group}{ACL}{vms}{$source} ) && grep( /^\*$/, @{ $self->{cfg}{groups}{$group}{ACL}{vms}{$source} } ) ) {
          return 2;
        }
      }
      elsif ( $subsys eq "ESXI" ) {
      }
      elsif ( $subsys eq "RESPOOL" ) {
      }
      elsif ( $subsys eq "DATASTORE" ) {
      }
    }
    elsif ( $platform eq "UNMANAGED" ) {
      if ( noVivDefined( $self->{cfg}{groups}{$group}{ACL}{sections}{solo} ) && $self->{cfg}{groups}{$group}{ACL}{sections}{solo} ) {
        return 2;
      }
      elsif ( $subsys eq "SERVER" ) {
        if ( noVivDefined( $self->{cfg}{groups}{$group}{ACL}{solo}{$source} )
          && ( grep( /^$item$/, @{ $self->{cfg}{groups}{$group}{ACL}{solo}{$source} } ) || grep( /^\*$/, @{ $self->{cfg}{groups}{$group}{ACL}{solo}{$source} } ) ) )
        {
          return 2;
        }
      }
    }
    elsif ( $platform eq "LINUX" ) {
      if ( noVivDefined( $self->{cfg}{groups}{$group}{ACL}{sections}{linux} ) && $self->{cfg}{groups}{$group}{ACL}{sections}{linux} ) {
        return 2;
      }
      elsif ( $subsys eq "SERVER" ) {
        if ( noVivDefined( $self->{cfg}{groups}{$group}{ACL}{linux} )
          && ( grep( /^$item$/, @{ $self->{cfg}{groups}{$group}{ACL}{linux} } ) || grep( /^\*$/, @{ $self->{cfg}{groups}{$group}{ACL}{linux} } ) ) )
        {
          return 2;
        }
      }
    }
    elsif ( $platform eq "XENSERVER" ) {
      if ( noVivDefined( $self->{cfg}{groups}{$group}{ACL}{sections}{xen} ) && $self->{cfg}{groups}{$group}{ACL}{sections}{xen} ) {
        return 2;
      }
    }
    elsif ( $platform eq "OVIRT" ) {
      if ( noVivDefined( $self->{cfg}{groups}{$group}{ACL}{sections}{ovirt} ) && $self->{cfg}{groups}{$group}{ACL}{sections}{ovirt} ) {
        return 2;
      }
    }
    elsif ( $platform eq "NUTANIX" ) {
      if ( noVivDefined( $self->{cfg}{groups}{$group}{ACL}{sections}{nutanix} ) && $self->{cfg}{groups}{$group}{ACL}{sections}{nutanix} ) {
        return 2;
      }
    }
    elsif ( $platform eq "SOLARIS" ) {
      if ( noVivDefined( $self->{cfg}{groups}{$group}{ACL}{sections}{solaris} ) && $self->{cfg}{groups}{$group}{ACL}{sections}{solaris} ) {
        return 2;
      }
    }
    elsif ( $platform eq "ORACLEVM" ) {
      if ( noVivDefined( $self->{cfg}{groups}{$group}{ACL}{sections}{oraclevm} ) && $self->{cfg}{groups}{$group}{ACL}{sections}{oraclevm} ) {
        return 2;
      }
    }
    elsif ( $platform eq "ORACLEDB" ) {
      if ( noVivDefined( $self->{cfg}{groups}{$group}{ACL}{sections}{oracledb} ) && $self->{cfg}{groups}{$group}{ACL}{sections}{oracledb} ) {
        return 2;
      }
    }
    elsif ( $platform eq "HYPERV" ) {
      if ( noVivDefined( $self->{cfg}{groups}{$group}{ACL}{sections}{hyperv} ) && $self->{cfg}{groups}{$group}{ACL}{sections}{hyperv} ) {
        return 2;
      }
    }
    elsif ( $platform eq "AWS" ) {
      if ( noVivDefined( $self->{cfg}{groups}{$group}{ACL}{sections}{aws} ) && $self->{cfg}{groups}{$group}{ACL}{sections}{aws} ) {
        return 2;
      }
    }
    elsif ( $platform eq "GCLOUD" ) {
      if ( noVivDefined( $self->{cfg}{groups}{$group}{ACL}{sections}{gcloud} ) && $self->{cfg}{groups}{$group}{ACL}{sections}{gcloud} ) {
        return 2;
      }
    }
    elsif ( $platform eq "AZURE" ) {
      if ( noVivDefined( $self->{cfg}{groups}{$group}{ACL}{sections}{azure} ) && $self->{cfg}{groups}{$group}{ACL}{sections}{azure} ) {
        return 2;
      }
    }
    elsif ( $platform eq "KUBERNETES" ) {
      if ( noVivDefined( $self->{cfg}{groups}{$group}{ACL}{sections}{kubernetes} ) && $self->{cfg}{groups}{$group}{ACL}{sections}{kubernetes} ) {
        return 2;
      }
    }
    elsif ( $platform eq "OPENSHIFT" ) {
      if ( noVivDefined( $self->{cfg}{groups}{$group}{ACL}{sections}{openshift} ) && $self->{cfg}{groups}{$group}{ACL}{sections}{openshift} ) {
        return 2;
      }
    }
    elsif ( $platform eq "CLOUDSTACK" ) {
      if ( noVivDefined( $self->{cfg}{groups}{$group}{ACL}{sections}{cloudstack} ) && $self->{cfg}{groups}{$group}{ACL}{sections}{cloudstack} ) {
        return 2;
      }
    }
    elsif ( $platform eq "PROXMOX" ) {
      if ( noVivDefined( $self->{cfg}{groups}{$group}{ACL}{sections}{proxmox} ) && $self->{cfg}{groups}{$group}{ACL}{sections}{proxmox} ) {
        return 2;
      }
    }
    elsif ( $platform eq "DOCKER" ) {
      if ( noVivDefined( $self->{cfg}{groups}{$group}{ACL}{sections}{docker} ) && $self->{cfg}{groups}{$group}{ACL}{sections}{docker} ) {
        return 2;
      }
    }
    elsif ( $platform eq "FUSIONCOMPUTE" ) {
      if ( noVivDefined( $self->{cfg}{groups}{$group}{ACL}{sections}{fusioncompute} ) && $self->{cfg}{groups}{$group}{ACL}{sections}{fusioncompute} ) {
        return 2;
      }
    }
    elsif ( $platform eq "POSTGRES" ) {
      if ( noVivDefined( $self->{cfg}{groups}{$group}{ACL}{sections}{postgres} ) && $self->{cfg}{groups}{$group}{ACL}{sections}{postgres} ) {
        return 2;
      }
    }
    elsif ( $platform eq "SQLSERVER" ) {
      if ( noVivDefined( $self->{cfg}{groups}{$group}{ACL}{sections}{sqlserver} ) && $self->{cfg}{groups}{$group}{ACL}{sections}{sqlserver} ) {
        return 2;
      }
    }
    elsif ( $platform eq "DB2" ) {
      if ( noVivDefined( $self->{cfg}{groups}{$group}{ACL}{sections}{db2} ) && $self->{cfg}{groups}{$group}{ACL}{sections}{db2} ) {
        return 2;
      }
    }
  }
  return 0;
}

sub getVMs {
  my $self = shift;
  my %hash;
  foreach my $group ( $self->{grplist} ) {
    if ( !exists $self->{cfg}{groups}{$group} ) {
      next;
    }
    if ( exists $self->{cfg}{groups}{$group}{ACL}{vmware} ) {
      while ( my ( $key, $value ) = each( %{ $self->{cfg}{groups}{$group}{ACL}{vmware} } ) ) {
        foreach my $lpar ( @{$value} ) {
          $hash{$key}{$lpar} = 1;
        }
      }
    }
  }
  return %hash;
}

sub getSolos {
  my $self = shift;
  my %hash;
  foreach my $group ( @{ $self->{grplist} } ) {
    if ( !exists $self->{cfg}{groups}{$group} ) {
      next;
    }
    if ( exists $self->{cfg}{groups}{$group}{ACL}{solo} ) {
      while ( my ( $key, $value ) = each( %{ $self->{cfg}{groups}{$group}{ACL}{solo} } ) ) {
        foreach my $lpar ( @{$value} ) {
          $hash{$key}{$lpar} = 1;
        }
      }
    }
  }
  return %hash;
}

sub hasItems {
  my $self = shift;
  my ( $type, $srv, @curLpars ) = @_;

  if ( $self->isAdmin ) {
    return 1;
  }

  if ( $self->isReadOnly ) {
    return 8;    # maybe it will be usefull to know it's RO ACL, return specific value (8)
  }

  # warn "PARS: $type : $srv";

  foreach my $group ( @{ $self->{grplist} } ) {

    # trace();
    # warn $group . Dumper $self->{cfg}{groups}{$group};
    if ( !noVivDefined( $$self{cfg}{groups}{$group} ) ) {

      # warn $group . " not found hasItems";
      next;
    }
    if ( $type eq "P" ) {

      #warn $group . Dumper $self->{cfg}{groups}{$group}{ACL};
      if ( ( noVivDefined( $$self{cfg}{groups}{$group}{ACL}{sections}{power} ) && $$self{cfg}{groups}{$group}{ACL}{sections}{power} )
        || noVivDefined( $$self{cfg}{groups}{$group}{ACL}{lpars}{"*"} )
        || noVivDefined( $$self{cfg}{groups}{$group}{ACL}{lpars}{$srv} ) )
      {
        # warn $group . " " . Dumper $self->{cfg}{groups}{$group}{ACL}{lpars};
        #warn exists $self->{cfg}{groups}{$group}{ACL}{lpars}{"*"};
        #warn "$self->{cfg}{groups}{$group}{ACL}{lpars}{$srv} " . Dumper $self->{cfg}{groups}{$group}{ACL}{lpars}{$srv};
        return 2;
      }
      if ( $self->{cfg}{options}{acl_power_server_ignore} ) {
        my @matching_lpars;
        foreach my $server ( keys %{ $self->{cfg}{groups}{$group}{ACL}{lpars} } ) {
          push( @matching_lpars, @{ $self->{cfg}{groups}{$group}{ACL}{lpars}{$server} } );
        }
        foreach my $lpar (@matching_lpars) {
          if ( $lpar eq "*" || grep( /^$lpar$/, @curLpars ) ) {
            return 2;
          }
        }
      }
    }
    if ( $type eq "O" ) {
      if ( ( noVivDefined( $$self{cfg}{groups}{$group}{ACL}{sections}{power} ) && $$self{cfg}{groups}{$group}{ACL}{sections}{power} )
        || noVivDefined( $self->{cfg}{groups}{$group}{ACL}{pools}{"*"} )
        || noVivDefined( $self->{cfg}{groups}{$group}{ACL}{pools}{$srv} ) )
      {
        return 3;
      }
    }
    elsif ( $type eq "V" ) {
      if ( $self->{cfg}{groups}{$group}{ACL}{sections}{vmware}
        || exists $self->{cfg}{groups}{$group}{ACL}{vms}{"*"}
        || exists $self->{cfg}{groups}{$group}{ACL}{vms}{$srv} )
      {
        return 4;
      }
    }
    elsif ( $type eq "U" ) {
      if ( $self->{cfg}{groups}{$group}{ACL}{sections}{solo}
        || exists $self->{cfg}{groups}{$group}{ACL}{solo}{"*"}
        || exists $self->{cfg}{groups}{$group}{ACL}{solo}{$srv} )
      {
        return 5;
      }
    }
  }
  return 0;
}

sub useACL {
  my $self = shift;
  return $self->{useacl};
}

sub collons {
  return s/===double-col===/:/g;
}

sub pipes {
  return s/===pipe===/\|/g;
}

sub uniq {
  my %seen;
  return grep { !$seen{$_}++ } @_;
}

sub urlencode {
  my $s = shift;

  # $s =~ s/ /+/g;
  $s =~ s/([^a-zA-Z0-9_.!~*()'\''-])/sprintf("%%%02X", ord($1))/ge;

  # $s =~ s/([^A-Za-z0-9\+-_])/sprintf("%%%02X", ord($1))/seg;
  return $s;
}

sub urldecode {
  my $s = shift;
  if ($s) {
    $s =~ s/\%([A-Fa-f0-9]{2})/pack('C', hex($1))/seg;
  }
  return $s;
}

sub trace {
  my $i = 1;
  print STDERR "Stack Trace:\n";
  while ( ( my @call_details = ( caller( $i++ ) ) ) ) {
    print STDERR $call_details[1] . ":" . $call_details[2] . " in function " . $call_details[3] . "\n";
  }
}

sub noVivDefined {
  my ( $x, @keys ) = @_;
  foreach my $k (@keys) {
    return unless ref $x eq 'HASH';
    return unless exists $x->{$k};
    $x = $x->{$k};
  }
  return defined $x;
}

1;

package ACLx;

# ACL module for Xormon
# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=perl
use strict;
use warnings;

use Data::Dumper;
use Fcntl ':flock';    # import LOCK_* constants
use CGI::Carp qw(fatalsToBrowser);
use File::Copy;
use JSON qw(decode_json encode_json);

my $basedir = $ENV{INPUTDIR};
$basedir ||= "..";

my $cfgdir  = "$basedir/etc/web_config";
my $cfgfile = "$cfgdir/acl.json";

my $aclAdminGroup = $ENV{ACL_ADMIN_GROUP} ||= "admins";
my @grplist;

sub new {
  my $class = shift;
  my $self  = {};
  bless $self;
  $self->{uid}    = shift if @_;
  $self->{acl}    = ();
  $self->{rawacl} = ();
  if ( !$self->{uid} ) {
    require ACL;
    my $oldacl = ACL->new();
    $self->{uid} = $oldacl->getUser();
  }
  $self->{useracl} = ();
  my $CFG;

  if ( !open( $CFG, "<", $cfgfile ) ) {
    if ( !open( $CFG, ">", $cfgfile ) ) {
      die("$!: $cfgfile");
    }
    else {    # create empty cfg file
      print $CFG "{}";

      close $CFG;
      open( $CFG, "<", $cfgfile );
    }
  }
  flock( $CFG, LOCK_SH );
  {
    local $/ = undef;    # required for re-read of encode_json pretty output
    $self->{rawacl} = <$CFG>;
    if ( $self->{rawacl} ) {
      $self->{acl} = decode_json( $self->{rawacl} );
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

  $self->{useracl} = $self->setUserACL();

  return $self;
}

sub getConfig {
  my $self = shift;
  return $self->{acl};
}

sub getRawConfig {
  my $self = shift;
  return $self->{rawacl};
}

sub getAdminGroup {
  my $self = shift;
  $aclAdminGroup;
}

sub getGroupACL {

  # parameters: array of groups
  # { groups => [] }

  my ( $self, $params ) = @_;

  if ( $params->{groups} ) {
    my $acl;
    foreach my $group ( @{ $params->{groups} } ) {
      $acl = merge( $self->{acl}{group}{$group}{acl}, $acl );
    }

    #print Dumper $config{group}{$group}{acl};
    return $acl;
  }
  else {
    return {};
  }
}

sub getUserACL {
  my $self = shift;
  return $self->{useracl};
}

sub setUserACL {
  my $self = shift;
  $self->{uid} = shift if @_;
  my $acl = {};
  if ( $self->{uid} ) {
    use Users;
    my %usercfg = Users::getConfig();
    if ( $usercfg{users} && $usercfg{users}{ $self->{uid} } ) {
      @grplist = @{ $usercfg{users}{ $self->{uid} }{groups} };
    }
    if ( grep /^$aclAdminGroup$/, @grplist ) {
      $acl = { isAdmin => \1, grantAll => \1 };
    }
    elsif ( grep /^ReadOnly$/, @grplist ) {
      $acl = { isReadOnly => \1, grantAll => \1 };
    }
    elsif (@grplist) {
      foreach my $group (@grplist) {
        $acl = merge( $self->{acl}{group}{$group}{acl}, $acl );
      }
    }
  }
  $self->{useracl} = $acl;

  return $acl;
}

sub isAdmin {
  if ( grep /^$aclAdminGroup$/, @grplist ) {
    return 1;
  }
  return 0;
}

sub isReadOnly {
  if ( grep /^ReadOnly$/, @grplist ) {
    return 1;
  }
  return 0;
}

sub merge (@);

sub merge (@) {
  shift unless ref $_[0];    # Take care of the case we're called like ACLx->merge(...)
  my ( $left, @right ) = @_;

  return $left unless @right;
  return merge( $left, merge(@right) ) if @right > 1;

  my ($right) = @right;
  my %merge = %$left;

  for my $key ( keys %$right ) {
    my ( $hr, $hl ) = map { ref $_->{$key} eq 'HASH' } $right, $left;

    if ( $hr and $hl ) {
      $merge{$key} = merge( $left->{$key}, $right->{$key} );
    }
    else {
      $merge{$key} = $right->{$key};
    }
  }

  return \%merge;
}

sub canShow {

  # parameters: scope, value
  # { scope => ( class | device | subsystem | item ), value => string }_
}

sub isGranted {

  # params: (hash) hw_type, [subsys, item_id], [match]
  # returns 0 or 1

  my $self   = shift;
  my $params = shift;

  # deny, if ACL has not been initialized
  return 0 unless ( $self->{useracl} );

  my ( $hw_type, $subsys, $item_id, $node_match ) = ( '', '', '', 'granted' );
  $hw_type = $params->{hw_type} if ( $params->{hw_type} );
  $subsys  = $params->{subsys}  if ( $params->{subsys} );
  $item_id = $params->{item_id} if ( $params->{item_id} );
  if ( exists $params->{match} && $params->{match} =~ m/^(granted|has_children|exists)$/ ) {

    # granted ~ full access to the node and if not a leaf, all its successors too
    # has_children ~ access to some successor
    # exists ~ granted or has_children
    $node_match = $params->{match};
  }

  my $found = 0;

  if ( $self->{useracl}{grantAll} ) {
    $found = 1;
  }
  elsif ( $hw_type && $hw_type eq 'CUSTOM GROUPS' && $self->{useracl}{$hw_type} ) {    # for now use "CUSTOM GROUPS" as hw_type and custom group name as item_id
    if ( ref $self->{useracl}{$hw_type} ne 'HASH' ) {
      $found = 1 if ( $node_match =~ m/^(granted|exists)$/ );
    }
    else {
      $found = searchTree( { value => $item_id, tree => $self->{useracl}{$hw_type}, match => $node_match } );
    }
  }
  elsif ( $hw_type && $self->{useracl}{$hw_type} ) {
    if ( ref $self->{useracl}{$hw_type} ne 'HASH' ) {
      $found = 1 if ( $node_match =~ m/^(granted|exists)$/ );
    }
    else {
      my $key = '';
      $key = $subsys  if ($subsys);
      $key = $item_id if ($item_id);

      # check exact match
      if ($key) {
        $found = searchTree( { value => $key, tree => $self->{useracl}{$hw_type}, match => $node_match } );
      }

      # otherwise, check item's parents in case there is a corresponding rule at a higher level
      # note that getPredecessors currently returns subsystems/items, not always exactly menu folders
      if ( $item_id && !$found && $node_match ne 'has_children' ) {
        if ( defined $ENV{XORMON} && $ENV{XORMON} ) {

          # based off SQLiteDataWrapper::getMenuPath
          require SQLiteDataWrapper;

          $subsys = SQLiteDataWrapper::getItemSubsys( { item_id => $item_id } );

          my $ancestor_subsys = SQLiteDataWrapper::getAncestorSubsys( { hw_type => $hw_type, subsys => $subsys } );
          my @ancestor_subsys = $ancestor_subsys ? @{$ancestor_subsys} : ();

          my $ancestor_items = SQLiteDataWrapper::getAncestorItems( { item_id => $item_id } );
          my @ancestor_items = $ancestor_items ? @{$ancestor_items} : ();

          my $self_subsys = SQLiteDataWrapper::getSelfSubsys( { hw_type => $hw_type, subsys => $subsys } );
          if ($self_subsys) {
            my $current_subsys = ( ref $self_subsys eq 'ARRAY' ) ? @{$self_subsys}[0] : $self_subsys;
            unless ( $current_subsys->{menu_items} =~ m/^folder_/ ) {
              my %subsys_item = ( subsystem => $subsys, parent => $item_id );
              push @ancestor_items, \%subsys_item;
            }
          }

          my $successor_recursive_folder_subsys = SQLiteDataWrapper::getSuccessorRecursiveFolderSubsys( { hw_type => $hw_type, subsys => $subsys } );
          my @successor_recursive_folder_subsys = $successor_recursive_folder_subsys ? @{$successor_recursive_folder_subsys} : ();
          foreach my $recursive_subsys (@successor_recursive_folder_subsys) {
            unshift @ancestor_subsys, $recursive_subsys if ( grep { $recursive_subsys->{subsystem} eq $_->{subsystem} } @ancestor_items );
          }

        SUBSYS: foreach my $subsys_level ( reverse @ancestor_subsys ) {
            my %subsys_hash          = %{$subsys_level};
            my $current_subsys_level = $subsys_hash{subsystem};

            my $items_found = 0;
            foreach my $ancestor_item ( reverse @ancestor_items ) {
              my %item_hash = %{$ancestor_item};
              my ( $ancestor_subsys, $ancestor_item_id ) = ( $item_hash{subsystem}, $item_hash{parent} );
              next unless ( $ancestor_subsys eq $current_subsys_level );
              $items_found++;

              my $check_value = $ancestor_item_id;
              $found = searchTree( { value => $check_value, tree => $self->{useracl}{$hw_type}, match => 'granted' } );
              last SUBSYS if ($found);
            }

            # TODO keep history to search only a subtree
            if ( $items_found == 0 ) {
              my $check_value = $current_subsys_level;
              $found = searchTree( { value => $check_value, tree => $self->{useracl}{$hw_type}, match => 'granted' } );
              last SUBSYS if ($found);
            }
          }
        }
      }

      # neither subsys, nor item_id were provided, but hw_type exists
      if ( $node_match =~ m/^(has_children|exists)$/ && $key eq '' ) {
        $found = 1;
      }
    }
  }

  return $found;
}

sub searchTree {
  my $params = shift;

  my ( $value, $tree, $node_match ) = ( '', '', 'granted' );
  $value = $params->{value} if ( $params->{value} );
  $tree  = $params->{tree}  if ( $params->{tree} );
  if ( exists $params->{match} && $params->{match} =~ m/^(granted|has_children|exists)$/ ) {

    # see params in isGranted for an explanation
    $node_match = $params->{match};
  }

  my $found = 0;
  if ( ref $tree ne 'HASH' ) {

    # trivial case, no tree to search
  }
  elsif ( exists $tree->{$value} ) {
    if ( ref $tree->{$value} eq 'HASH' ) {
      $found = 1 if ( $node_match =~ m/^(has_children|exists)$/ );
    }
    else {
      $found = 1 if ( $node_match =~ m/^(granted|exists)$/ );
    }
  }
  else {
    my @nodes = keys %{$tree};
    foreach my $node (@nodes) {
      $found = searchTree( { value => $value, tree => $tree->{$node}, match => $node_match } );
      last if $found;
    }
  }

  return $found;
}

1;

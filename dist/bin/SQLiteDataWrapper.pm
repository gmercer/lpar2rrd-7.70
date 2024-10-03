# SQLiteDataWrapper.pm
# interface for accessing SQLite data

package SQLiteDataWrapper;

use strict;
use warnings;

use JSON;
use DBI;
use Data::Dumper;
use CGI::Carp qw(fatalsToBrowser);
use Digest::MD5 qw(md5_hex);

#use Carp qw<longmess>;
use Time::HiRes qw(usleep ualarm gettimeofday tv_interval);
use List::Util 'first';
use Xorux_lib qw(error read_json urldecode urlencode parse_url_params);
use Menu;

my $basedir   = $ENV{INPUTDIR} ||= '/home/lpar2rrd/lpar2rrd';
my $wrkdir    = "$basedir/data";
my $db_file   = "$wrkdir/_DB/data.db";
my $debug_sql = $ENV{DEBUG_SQL};

# copied from STOR2RRD
#
# semantics:
#   classes:     SERVER, DB, CLOUD
#   hw_types:    XENSERVER, POWER, OVIRT,…
#   subsystems:  POOL, HOST, STORAGE, VM,…
#
# subsystems position in menu: subsystem_order & subsystem_parent
#   unlike in STOR, LPAR menu has a deeper hierarchy that varies among hw_types
#   so, subsystem_order is tree-node ID, and subsystem_parent a reference to the parent node
#
# subsystems can be recursive (indicated by flag recursive_folder): for custom item folders

# ACL usage
#
# load configuration file
#  require ACLx;
#  my $acl = ACLx->new();
#
# query (+ optional match flag with values granted|has_children|exists)
#  my $is_hwtype_granted = $acl->isGranted({hw_type => 'FOO'});
#  my $is_subsys_granted = $acl->isGranted({hw_type => 'FOO', subsys => 'BAR'});
#  my $is_object_item_granted = $acl->isGranted({hw_type => 'FOO', item_id => 'DEADBEEF'});

my $ten_days_before = time - ( 10 * 86400 );    # inactive devices will be hidden after that time

if ( $ENV{DEMO} ) {
  $ten_days_before = time - ( 3650 * 86400 );    # set 10 years back for demo site
}

sub dbConnect {
  my $params = shift;

  if ( exists $params->{db_file} && $params->{db_file} ne '' ) { $db_file = $params->{db_file}; }    # for debug/test purposes only

  # warn Dumper Time::HiRes::gettimeofday() . " " . longmess();
  if ( !-d "$wrkdir/_DB" ) {
    umask 0000;
    mkdir( "$wrkdir/_DB", 0777 ) || warn( "Cannot mkdir $wrkdir/_DB $!" . __FILE__ . ':' . __LINE__ ) && exit;
  }
  my $driver   = 'SQLite';
  my $dsn      = "DBI:$driver:dbname=$db_file";
  my $userid   = '';
  my $password = '';
  my $dbh      = DBI->connect( $dsn, $userid, $password, { RaiseError => 1 } )
    or die $DBI::errstr;
  chmod 0666, "$db_file";

  #$dbh->trace(1, "/var/tmp/dbtrace.log");
  warn "SQLite busy timeout: " . $dbh->sqlite_busy_timeout() if $debug_sql;
  $dbh->sqlite_busy_timeout(60000);    # set timeout to 60 s if default is too low (to prevent DB locks)
  my $sth = $dbh->table_info( undef, undef, 'config', 'TABLE' );
  $sth->execute();

  if ( !$sth->fetchrow_array || $params->{update} ) {
    $dbh->do('PRAGMA journal_mode=WAL');    # journal_mode is persistant, set it on DB create
    $dbh->begin_work();
    if ( !exists $params->{db_file} ) { warn $params->{update} ? 'Updating database' : 'Database not found, creating new one...'; }
    my $sqlFile = "$basedir/etc/dbinit.sql";
    open( my $SQL, "$sqlFile" )
      or die("Cannot open file $sqlFile for reading");

    # Loop though the SQL file and execute each and every one.
    $sth->finish();
    local $/ = ';';
    while ( my $sqlStatement = <$SQL> ) {
      $sth = $dbh->prepare($sqlStatement)
        or die("Can't prepare $sqlStatement");
      $sth->execute()
        or die("Can't execute $sqlStatement");
      $sth->finish();
    }
    close $SQL;
    $dbh->commit();
  }
  $sth->finish();
  return $dbh;
}

sub dbUpdate {
  my $dbh = dbConnect( { update => 1 } );
  return {};
}

##### TODO hide
sub object2db {

  # $params = {id => "73db880d-0f0d-48c4-b99f-20a805b4af9b", label => "PureStorage_405", hwtype => "PURE"};
  my $start  = [gettimeofday];
  my $params = shift;
  my $dbh    = dbConnect();
  my $now    = time;

  # should be always set in future
  if ( !$params->{class} ) {
    $params->{class} = 'SERVER';
  }
  $dbh->begin_work();

  my ($rv, $stmt);
  $stmt = qq(SELECT COUNT (*) FROM hw_types WHERE hw_type = ?);
  if ( !$dbh->selectrow_array($stmt, undef, $params->{hw_type}) ) {
    $stmt = qq(INSERT INTO hw_types (hw_type, class) VALUES (?, ?));
    $rv = $dbh->prepare($stmt);
    $rv->execute($params->{hw_type}, $params->{class})
      or die $DBI::errstr;
  }
  else {
    $rv = $dbh->prepare($stmt);
    $rv->execute($params->{hw_type})
      or die $DBI::errstr;
  }
  $stmt = qq(INSERT OR REPLACE INTO objects VALUES (?, ?, ?, ?));
  $rv   = $dbh->prepare($stmt);
  $rv->execute($params->{id}, $params->{label}, $params->{hw_type}, $now)
    or die $DBI::errstr;

  $dbh->commit();
}

sub subsys2db {

  # $params = {id => "73db880d-0f0d-48c4-b99f-20a805b4af9b", subsys => "VOLUME", data => $data->{VOLUME}};
  my $params = shift;
  my $dbh    = dbConnect();
  my $now    = time;
  my $tstart = [gettimeofday];

  my ($rv, $stmt);
  $stmt = qq(SELECT hw_type FROM objects WHERE object_id = ?);
  $params->{hw_type} = $dbh->selectrow_array($stmt, undef, $params->{id});

  $stmt = qq(SELECT COUNT (*) FROM subsystems WHERE hw_type = ? AND subsystem = ?);
  if ( !$dbh->selectrow_array($stmt, undef, $params->{hw_type}, $params->{subsys}) ) {
    $stmt = qq(INSERT INTO subsystems (hw_type, subsystem) VALUES (?, ?));
    $rv = $dbh->prepare($stmt);
    $rv->execute($params->{hw_type}, $params->{subsys})
      or die $DBI::errstr;
  }
  foreach my $key ( keys %{ $params->{data} } ) {
    my $value = $params->{data}{$key};
    $dbh->begin_work();
    $stmt = qq(INSERT OR REPLACE INTO object_items VALUES (?, ?, ?, ?, ?, ?));
    $rv   = $dbh->prepare($stmt);
    $rv->execute($key, $params->{data}{$key}{label}, $params->{id}, $params->{hw_type}, $params->{subsys}, $now)
      or die $DBI::errstr;

    # remove all $key properties before adding actual set
    $stmt = qq(DELETE FROM item_properties WHERE (item_id = ?));
    $rv   = $dbh->prepare($stmt);
    $rv->execute($key)
      or die $DBI::errstr;

    foreach my $propname ( keys %{ $params->{data}{$key} } ) {
      if ( $propname eq 'label' ) {
        next;
      }
      elsif ( $propname eq 'children' ) {
        my @childlist = @{ $params->{data}{$key}{$propname} };
        foreach my $child (@childlist) {
          $stmt = qq(INSERT OR REPLACE INTO item_relations VALUES (?, ?));
          $rv   = $dbh->prepare($stmt);
          $rv->execute($key, $child)
            or die $DBI::errstr;
        }
        next;
      }
      elsif ( $propname eq 'parents' ) {
        my @parentlist = @{ $params->{data}{$key}{$propname} };
        foreach my $parent (@parentlist) {
          $stmt = qq(INSERT OR REPLACE INTO item_relations VALUES (?, ?));
          $rv   = $dbh->prepare($stmt);
          $rv->execute($parent, $key)
            or die $DBI::errstr;
        }
        next;
      }
      elsif ( $propname eq 'mapped_agent' ) {
        my $agent = $params->{data}{$key}{$propname};
        $stmt = qq(INSERT OR REPLACE INTO agent_relations VALUES (?, ?, ?));
        $rv   = $dbh->prepare($stmt);
        $rv->execute($agent, $key, $now)
          or die $DBI::errstr;
        next;
      }
      elsif ( $propname eq 'hostcfg' ) {
        my @hostcfglist = @{ $params->{data}{$key}{$propname} };
        foreach my $hostcfg (@hostcfglist) {
          $stmt = qq(INSERT OR REPLACE INTO hostcfg_relations VALUES (?, ?));
          $rv   = $dbh->prepare($stmt);
          $rv->execute($hostcfg, $key)
            or die $DBI::errstr;
        }
        next;
      }
      my $propval = $params->{data}{$key}{$propname};
      $stmt = qq(INSERT OR REPLACE INTO properties VALUES (?));
      $rv   = $dbh->prepare($stmt);
      $rv->execute($propname)
        or die $DBI::errstr;
      $stmt = qq(INSERT OR REPLACE INTO item_properties VALUES (?, ?, ?));
      $rv   = $dbh->prepare($stmt);
      $rv->execute($key, $propname, $propval)
        or die $DBI::errstr;
    }
    $dbh->commit();
  }

  my $start = [gettimeofday];
  warn "subsys2db ( $params->{subsys} ) write time (s): " . tv_interval($tstart) if $debug_sql;

  #warn "subsys2db ( $params->{subsys} ) SQL commit time (s): " . tv_interval ($start) if $debug_sql;
}

################################################################################

sub testQuery {
  my $params = shift;
  my $result;

  #my $foo = getSuccessorRecursiveFolderSubsys({hw_type => 'VMWARE', subsys => 'VM'});
  #getAncestorSubsys({hw_type => 'VMWARE', subsys => 'VM_FOLDER'});
  #getAncestorItems({item_id  => 'eb6102a7-1fa0-4376-acbb-f67e34a2212c_28_vm_501c700f-56b0-a127-79e8-fed82513ad54'});
  #getHwTypes2({active=>0}); # ({item_id => '0c340bff-f118-4225-a34f-50b670eaf76b'});
  #warn Dumper $foo;
  #$result = $foo;

  return $result;
}

sub getClasses {

  # $params: {active => 1} # optional
  # returns array of hashes {class => 'DB', label => 'Database'}

  my $params = shift;
  my $dbh    = dbConnect();

  my $stmt        = qq(SELECT class, label FROM classes ORDER BY class_order);
  my $active_flag = exists $params->{active} ? $params->{active} : 0;
  if ($active_flag) {
    $stmt = qq(SELECT DISTINCT classes.class, classes.label
			 FROM object_items
             INNER JOIN hw_types ON hw_types.hw_type = object_items.hw_type
             INNER JOIN classes ON hw_types.class = classes.class
             WHERE object_items.item_timestamp > $ten_days_before
             ORDER BY classes.class_order);
  }
  my $result = $dbh->selectall_arrayref( $stmt, { Slice => {} } );

  my @result = @{$result} if ($result);
  return \@result;
}

# TODO swap with getHwTypes2
sub getHwTypes {
  return getHwTypes2();
}

# TODO remove (as soon as it is not used by XorMon anymore)
sub getActiveHwTypes {

  # returns array of HW types
  return getHwTypes2( { active => 1 } );
}

# TODO replacement for getHwTypes and getActiveHwTypes
sub getHwTypes2 {

  # $params: {class => 'SERVER', active => 1} # optional
  # returns array of hashes {hw_type => 'HW_TYPE', label => 'Hardware Type'}

  my $params = shift;
  my $dbh    = dbConnect();

  my $stmt  = qq(SELECT hw_type, label FROM hw_types ORDER BY hw_type_order);
  my $class = exists $params->{class} ? $params->{class} : '';
  if ($class) {
    $stmt = qq(SELECT hw_type, label FROM hw_types WHERE class = '$class' ORDER BY hw_type_order);
  }
  my $active_flag = exists $params->{active} ? $params->{active} : 0;
  if ($active_flag) {
    $stmt = qq(SELECT DISTINCT object_items.hw_type, hw_types.label
             FROM object_items
             INNER JOIN hw_types ON hw_types.hw_type = object_items.hw_type
             WHERE object_items.item_timestamp > $ten_days_before
             ORDER BY hw_types.hw_type_order);
    if ($class) {
      $stmt = qq(SELECT DISTINCT object_items.hw_type, hw_types.label
             FROM object_items
             INNER JOIN hw_types ON hw_types.hw_type = object_items.hw_type
             WHERE hw_types.class = '$class' AND object_items.item_timestamp > $ten_days_before
             ORDER BY hw_types.hw_type_order);
    }
  }
  my $result = $dbh->selectall_arrayref( $stmt, { Slice => {} } );

  my @result = @{$result} if ($result);
  return \@result;
}
##### end getHwTypes2

sub getClass {

  # $params: {hw_type => 'XENSERVER'}
  # returns hash {class => 'SERVER', label => 'Server'}

  my $params = shift;
  my $dbh    = dbConnect();

  my $hw_type = exists $params->{hw_type} ? $params->{hw_type} : '';
  my $stmt    = qq(SELECT classes.class, classes.label
              FROM classes
              INNER JOIN hw_types ON hw_types.class = classes.class
              WHERE hw_types.hw_type = '$hw_type');
  my $result = $dbh->selectall_arrayref( $stmt, { Slice => {} } );

  my @result = @{$result} if ($result);
  return $result[0];
}

# used only in isAnyParentRecursive and getPredecessors
sub getItemParents {

  # $params: {item_id => '8B043822FB71B73200011613'}
  # returns hash { 'SUBSYS' => { 'UUID' => { hash of properties } } }

  my $params = shift;
  my $dbh    = dbConnect();

  my $stmt   = qq(SELECT * FROM object_items WHERE item_id IN (SELECT parent FROM item_relations WHERE child = ?));
  my $result = $dbh->selectall_hashref( $stmt, [ 'subsystem', 'item_id' ], { Slice => {} }, $params->{item_id} );

  my %result = %{$result} if ($result);
  return \%result;
}

# unused
sub getItemChildren {

  # $params: {item_id => '0a156ddf04'}
  # returns hash { 'SUBSYS' => { 'UUID' => { hash of properties } } }

  my $params = shift;
  my $dbh    = dbConnect();

  my $stmt   = qq(SELECT * FROM object_items WHERE item_id IN (SELECT child FROM item_relations WHERE parent = ?));
  my $result = $dbh->selectall_hashref( $stmt, [ 'subsystem', 'item_id' ], { Slice => {} }, $params->{item_id} );
  return $result;
}

# used to filter items in getTree and items respectively, to be replaced by getAncestors
sub getItemParentsArray {

  # $params: {item_id  => '8B043822FB71B73200011613'}
  # returns array of item_ids

  my $params = shift;
  my $dbh    = dbConnect();

  my $stmt   = qq(SELECT parent FROM item_relations WHERE child = '$params->{item_id}');
  my $result = $dbh->selectcol_arrayref($stmt);
  return $result;
}

# unused
sub getItemChildrenArray {

  # $params: {item_id  => '8B043822FB71B73200011613'}
  # returns array of item_ids

  my $params = shift;
  my $dbh    = dbConnect();

  my $stmt   = qq(SELECT child FROM item_relations WHERE parent = '$params->{item_id}');
  my $result = $dbh->selectcol_arrayref($stmt);
  return $result;
}

sub getItemProperties {

  # $params: {item_id  => '8B043822FB71B73200011613'}
  # returns hash { property => value }

  my $params = shift;
  my $dbh    = dbConnect();

  my $stmt   = qq(SELECT property_name, property_value FROM item_properties WHERE item_id = ?);
  my $result = $dbh->selectall_arrayref( $stmt, undef, "$params->{item_id}" );
  my %res    = map { $_->[0] => $_->[1] } @$result;
  return \%res;
}

# TODO unused
sub getItemsWithChildren {

  # returns hash of object_items { 'UUID' => { hash of properties } }

  my $params = shift;
  my $dbh    = dbConnect();

  my $stmt   = qq(SELECT * FROM object_items WHERE EXISTS (SELECT child FROM item_relations WHERE parent = object_items.item_id ));
  my $result = $dbh->selectall_hashref( $stmt, 'item_id', undef );
  return $result;
}

# TODO unused
sub getItemsWithParents {

  # returns hash of object_items { 'UUID' => { hash of properties } }

  my $params = shift;
  my $dbh    = dbConnect();

  my $stmt   = qq(SELECT * FROM object_items WHERE EXISTS (SELECT parent FROM item_relations WHERE child = object_items.item_id ));
  my $result = $dbh->selectall_hashref( $stmt, 'item_id', undef );
  return $result;
}

################################################################################

# used only in isAnyParentRecursive and getPredecessors
sub getItemHwType {

  # $params: {item_id => 'DEADBEEF'}
  # returns hw_type name as a string

  my $params = shift;
  my $dbh    = dbConnect();

  my $stmt   = qq(SELECT hw_type FROM object_items WHERE item_id = '$params->{item_id}');
  my $result = $dbh->selectcol_arrayref($stmt);
  return @$result[0];
}

# used to filter items in getPredecessors, to be replaced by getAncestors, and in getMenuPath
sub getItemSubsys {

  # $params: {item_id => 'DEADBEEF'}
  # returns subsys name as a string

  my $params = shift;
  my $dbh    = dbConnect();

  my $stmt   = qq(SELECT subsystem FROM object_items WHERE item_id = '$params->{item_id}');
  my $result = $dbh->selectcol_arrayref($stmt);
  return @$result[0];
}

sub getTopSubsys {

  # $params: {hw_type => 'XENSERVER'}
  # returns array of hashes {subsystem => 'SUBSYS', label => 'Some Subsystem', menu_items => 'folder'}

  my $params = shift;
  my $dbh    = dbConnect();

  my $stmt   = qq(SELECT subsystem, label, menu_items FROM subsystems WHERE hw_type = '$params->{hw_type}' AND subsystem_order IS NOT NULL AND subsystem_parent IS NULL ORDER BY subsystem_order);
  my $result = $dbh->selectall_arrayref( $stmt, { Slice => {} } );
  return $result;
}

sub getSelfSubsys {

  # $params: {hw_type => 'XENSERVER', subsys => 'VM'}
  # returns array of hashes {subsystem => 'VM', label => 'VM', menu_items => 'folder_items'}

  my $params = shift;
  my $dbh    = dbConnect();

  my $stmt   = qq(SELECT subsystem, label, menu_items FROM subsystems WHERE hw_type = '$params->{hw_type}' AND subsystem = '$params->{subsys}');
  my $result = $dbh->selectall_arrayref( $stmt, { Slice => {} } );
  return $result;
}

# used in getTree
sub getChildSubsys {

  # $params: {hw_type => 'XENSERVER', parent_subsys => 'POOL'}
  # returns array of hashes {subsystem => 'SUBSYS', label => 'Some Subsystem', menu_items => 'folder'}

  my $params = shift;
  my $dbh    = dbConnect();

  # translate parent_subsys into subsys_order (node number in the subsystems tree)
  my $stmt_tmp = qq(SELECT subsystem_order FROM subsystems WHERE hw_type = '$params->{hw_type}' AND subsystem = '$params->{parent_subsys}');
  my @row      = $dbh->selectrow_array($stmt_tmp);
  unless (@row) { return; }
  my $parent_subsys_order = $row[0];

  # TODO perhaps add to the filter WHERE the condition 'AND recursive_folder != 1', or include the subsystem itself if recursive
  my $stmt   = qq(SELECT subsystem, label, menu_items FROM subsystems WHERE hw_type = '$params->{hw_type}' AND subsystem_parent = '$parent_subsys_order' ORDER BY subsystem_order);
  my $result = $dbh->selectall_arrayref( $stmt, { Slice => {} } );
  return $result;
}

# helper for getParentSubsysArray
sub getParentSubsys {

  # $params: {hw_type => 'XENSERVER', child_subsys => 'VM'}
  # returns subsys name as a string

  my $params = shift;
  my $dbh    = dbConnect();

  # get parent's subsys_order (node number in the subsystems tree) if it does have a parent
  my $stmt_tmp = qq(SELECT subsystem_parent FROM subsystems WHERE hw_type = '$params->{hw_type}' AND subsystem = '$params->{child_subsys}');
  my @row      = $dbh->selectrow_array($stmt_tmp);
  unless (@row) { return; }
  my $parent_subsys_order = $row[0];

  # if there is no parent, leave
  unless ($parent_subsys_order) { return; }

  # TODO perhaps reconsider the condition 'AND recursive_folder != 1', or include the subsystem itself if recursive
  my $stmt   = qq(SELECT subsystem FROM subsystems WHERE hw_type = '$params->{hw_type}' AND subsystem_order = '$parent_subsys_order' AND recursive_folder != 1 ORDER BY subsystem_order);
  my $result = $dbh->selectcol_arrayref($stmt);
  return @$result[0];
}

# used in getPredecessors
sub getParentSubsysArray {

  # $params: {hw_type => 'XENSERVER', child_subsys => 'VM'}
  # returns array of subsystems

  my $params = shift;
  my @result;

  my $current_subsys = $params->{child_subsys};
  while ($current_subsys) {
    $current_subsys = getParentSubsys( { hw_type => $params->{hw_type}, child_subsys => $current_subsys } );
    push @result, $current_subsys if ($current_subsys);
  }

  return \@result;
}

# TODO unused
sub getChildFolderSubsys {

  # $params: {hw_type => 'XENSERVER', parent_subsys => 'POOL'}
  # returns TODO

  my $params = shift;
  my $dbh    = dbConnect();

  # translate parent_subsys into subsys_order (node number in the subsystems tree)
  my $stmt_tmp = qq(SELECT subsystem_order FROM subsystems WHERE hw_type = '$params->{hw_type}' AND subsystem = '$params->{parent_subsys}');
  my @row      = $dbh->selectrow_array($stmt_tmp);
  unless (@row) { return; }
  my $parent_subsys_order = $row[0];

  # TODO perhaps add to the filter WHERE the condition 'AND recursive_folder != 1', or include the subsystem itself if recursive
  my $stmt   = qq(SELECT subsystem, menu_items FROM subsystems WHERE hw_type = '$params->{hw_type}' AND subsystem_parent = '$parent_subsys_order' AND recursive_folder == 1 ORDER BY subsystem_order);
  my $result = $dbh->selectall_arrayref( $stmt, { Slice => {} } );
  return $result;
}

sub getSubsysItems {

  # $params: {hw_type => 'XENSERVER', subsys => 'POOL'}
  # returns array of hashes {item_id => 'UUID', label => 'foo'}

  my $params = shift;
  my $dbh    = dbConnect();

  my $stmt = qq(SELECT item_id, label
                FROM object_items
                WHERE hw_type = '$params->{hw_type}'
                AND subsystem = '$params->{subsys}'
                AND item_timestamp > $ten_days_before
                ORDER BY label);
  my $result = $dbh->selectall_arrayref( $stmt, { Slice => {} } );
  return $result;
}

# TODO
sub getSubsysItemsFiltered {

  # $params: {hw_type => 'XENSERVER', subsys => 'VM', parent => 'DEADBEEF'}
  # returns array of hashes {item_id => 'UUID', label => 'foo'}

  my $params = shift;
  my $dbh    = dbConnect();

  my $stmt = qq(SELECT item_id, label
              FROM object_items
              WHERE hw_type = '$params->{hw_type}'
                AND subsystem = '$params->{subsys}'
                AND item_timestamp > $ten_days_before
                AND item_id IN (SELECT child
                               FROM item_relations
                               WHERE parent = '$params->{parent}')
              ORDER BY label);
  my $result = $dbh->selectall_arrayref( $stmt, { Slice => {} } );
  return $result;
}

sub isAnyParentRecursive {

  # $params: {item_id => 'DEADBEEF'}
  # returns 0 or 1

  my $params = shift;
  my $result = 0;

  # TODO getAncestorSubsys
  my $hw_type = getItemHwType( { item_id => $params->{item_id} } );
  my $parents = getItemParents( { item_id => $params->{item_id} } );
  foreach my $parent ( keys %{$parents} ) {
    $result = isSubsysRecursive( { hw_type => $hw_type, subsys => $parent } );
    last if $result;
  }

  return $result;
}

sub isSubsysRecursive {

  # $params: {hw_type => 'XENSERVER', subsys => 'POOL'}
  # returns 0 or 1

  my $params = shift;
  my $dbh    = dbConnect();

  my $stmt   = qq(SELECT recursive_folder FROM subsystems WHERE subsystem = '$params->{subsys}' AND hw_type = '$params->{hw_type}');
  my $result = $dbh->selectcol_arrayref($stmt);
  return @$result[0];
}

# perhaps merge with isSubsysRecursive
sub getRecursiveSubsystemItemType {

  # $params: {hw_type => 'VMWARE', subsys => 'VM_FOLDER'}
  # returns subsys name as a string

  my $params = shift;
  my $dbh    = dbConnect();

  # get parent's subsys_order (node number in the subsystems tree) if it does have a parent
  my $stmt_tmp = qq(SELECT item_subsystem FROM subsystems WHERE hw_type = '$params->{hw_type}' AND subsystem = '$params->{subsys}');
  my @row      = $dbh->selectrow_array($stmt_tmp);
  unless (@row) { return; }
  my $parent_subsys_order = $row[0];

  # if there is no parent, leave
  unless ($parent_subsys_order) { return; }

  my $stmt   = qq(SELECT subsystem FROM subsystems WHERE hw_type = '$params->{hw_type}' AND subsystem_order = '$parent_subsys_order' ORDER BY subsystem_order);
  my $result = $dbh->selectcol_arrayref($stmt);
  return @$result[0];
}

# TODO new for getMenuPath
sub getSuccessorRecursiveFolderSubsys {

  # $params: {hw_type => 'VMWARE', subsys => 'VM'}
  # returns array of hashes: [ { subsystem : 'VM_FOLDER', parent : 6, node : 9 } ]

  my $params = shift;
  my $dbh    = dbConnect();

  my $stmt = qq(SELECT subsystem, subsystem_order AS node, item_subsystem AS parent
                 FROM subsystems
                 WHERE recursive_folder = 1
                   AND hw_type = '$params->{hw_type}'
                   AND item_subsystem IN (SELECT subsystem_order
                                           FROM subsystems
                                           WHERE hw_type = '$params->{hw_type}'
                                             AND subsystem = '$params->{subsys}'));
  my $result = $dbh->selectall_arrayref( $stmt, { Slice => {} } );
  my @res    = $result ? @{$result} : ();
  return \@res;
}

sub getACLParentSubsysType {

  # $params: {hw_type => 'VMWARE', subsys => 'ESXI'}
  # returns subsys name as a string

  my $params = shift;
  my $dbh    = dbConnect();

  # get parent's subsys_order (node number in the subsystems tree) if it does have a parent
  my $stmt_tmp = qq(SELECT inherit_acl_from FROM subsystems WHERE hw_type = '$params->{hw_type}' AND subsystem = '$params->{subsys}');
  my @row      = $dbh->selectrow_array($stmt_tmp);
  unless (@row) { return; }
  my $parent_subsys_order = $row[0];

  if ( defined $parent_subsys_order ) {
    if ( $parent_subsys_order eq 0 ) {
      return $params->{hw_type};
    }
    else {
      my $stmt   = qq(SELECT subsystem FROM subsystems WHERE hw_type = '$params->{hw_type}' AND subsystem_order = '$parent_subsys_order' ORDER BY subsystem_order);
      my $result = $dbh->selectcol_arrayref($stmt);
      return @$result[0];
    }
  }

  return;
}

################################################################################

# TODO cleanup
# - delete object_items older than a timestamp (routine cleanup)
# - delete object_relations and object_properties for all object_items of a given hw_type (cleanup before updating, so that there are no leftover metadata)

sub deleteOlderItems {

  # $params: {days => 90}

  my $params = shift;
  my $days   = $params->{days} || 90;
  my $now    = time;
  my $offset = $now - ( $days * 86400 );

  my $dbh = dbConnect();
  $dbh->begin_work();

  my $stmt = qq(DELETE FROM object_items WHERE item_timestamp < $offset);
  my $rv   = $dbh->do($stmt) or die $DBI::errstr;
  $dbh->commit();
}

sub deleteItem {

  # params: {uuid => 'DEADBEEF', relations => 0} # relations flag optional

  my $params = shift;
  my $relations_flag = exists $params->{relations} ? $params->{relations} : 0;

  my $dbh = dbConnect();
  $dbh->begin_work();

  my ($stmt, $rv);
  if ($relations_flag) {
    $stmt = qq(DELETE FROM item_relations WHERE parent = ? OR child = ?);
    $rv   = $dbh->prepare($stmt);
    $rv->execute($params->{uuid}, $params->{uuid}) or die $DBI::errstr;
  }

  $stmt = qq(DELETE FROM object_items WHERE item_id = ?);
  $rv   = $dbh->prepare($stmt);
  $rv->execute($params->{uuid}) or die $DBI::errstr;

  $dbh->commit();
}

sub deleteItems {

  # params: {hw_type => 'VMWARE', subsys => 'VM_FOLDER'}

  my $params  = shift;

  my $dbh = dbConnect();
  $dbh->begin_work();

  my $stmt = qq(DELETE FROM object_items WHERE hw_type = '$params->{hw_type}');
  if ( exists $params->{subsys} ) {
     $stmt .= "AND subsystem = '$params->{subsys}'";
  }
  my $rv   = $dbh->do($stmt) or die $DBI::errstr;
  $dbh->commit();
}

# called from the Host configuration UI
sub deleteItemFromConfig {

  # params: {uuid => 'DEADBEEF'}
  # remove items associated with a given HostCfg entry (UUID)

  my $params = shift;
  return unless ( exists $params->{uuid} );

  my $dbh = dbConnect();

  # TODO if the hostcfg entry is the only one for the corresponding hw_type, delete everything

  my $stmt   = qq(SELECT item_id FROM hostcfg_relations WHERE hostcfg_id = '$params->{uuid}');
  my $result = $dbh->selectall_arrayref( $stmt, { Slice => {} } );
  if ( scalar @$result ) {
    foreach my $object_item (@$result) {
      # logging disabled (potentially re-enable with output to a custom log file):
      # warn "delete object $object_item->{item_id} for hostcfg $params->{uuid}";
      {
        # TODO delete children first
        $dbh->begin_work();
        my $stmt_children = qq(DELETE FROM object_items
                                WHERE item_id IN (SELECT child
                                                   FROM item_relations
                                                   WHERE parent = '$object_item->{item_id}'));
        my $rv_children = $dbh->do($stmt_children) or return $DBI::errstr;

        # TODO delete the root item itself
        my $stmt_object = qq(DELETE FROM object_items
                       WHERE item_id = '$object_item->{item_id}');
        my $rv_object = $dbh->do($stmt_object) or return $DBI::errstr;

        # delete the mapping
        my $stmt_map = qq(DELETE FROM hostcfg_relations WHERE item_id = '$object_item->{item_id}' AND hostcfg_id = '$params->{uuid}');
        my $rv_map   = $dbh->do($stmt_map) or return $DBI::errstr;
        $dbh->commit();
      }
    }
  }

  return 'OK';
}

################################################################################

# TODO remove when it is fully replaced by getAncestorItems and getAncestorSubsys
sub getPredecessors {

  # $params: {item_id => 'DEADBEEF'}
  # find predecessors in the (menu, ACL) tree, where nodes are item_ids or subsystems
  # returns array of subsystems and corresponding objects: [ {'SUBSYS1' => 'UUID1'}, {SUBSYS2 => undef}, {'SUBSYS3' => 'DEADBEEF'} ]

  my $params = shift;
  my @result;

  my $item_id = $params->{item_id};
  my $hw_type = getItemHwType( { item_id => $item_id } );
  my $subsys  = getItemSubsys( { item_id => $item_id } );

  #warn "getPredecessors $item_id : $hw_type : $subsys";

  # if the item's subsystem is represented as a single folder in menu ("menu_items" attribute), include it among predecessors
  my $self_subsys = getSelfSubsys( { hw_type => $hw_type, subsys => $subsys } );
  if ($self_subsys) {
    my $current_subsys = ( ref $self_subsys eq 'ARRAY' ) ? @{$self_subsys}[0] : $self_subsys;
    if ( $current_subsys->{menu_items} =~ m/^folder_/ ) {
      my %subsys_item = ( $subsys => undef );
      push @result, \%subsys_item;
    }
  }

  # how this works
  #   1. get the path as an array of subsystems
  #   2. assign a parent object_item to each corresponding subsystem (if there is any)
  my $parent_subsys = getParentSubsysArray( { hw_type => $hw_type, child_subsys => $subsys } );
  my $current_item  = $item_id;
  foreach my $parent_subsystem ( reverse @{$parent_subsys} ) {
    my $parents = getItemParents( { item_id => $current_item } );
    if ( exists $parents->{$parent_subsystem} && ref $parents->{$parent_subsystem} eq 'HASH' ) {

      # TODO account for recursive folders
      my @subsys_items = keys %{ $parents->{$parent_subsystem} };
      my %item         = ( $parent_subsystem => $subsys_items[0] );
      push @result, \%item;
      $current_item = $subsys_items[0];

      #warn "getPredecessors push $parent_subsystem - $subsys_items[0]";
    }
    else {
      my %item = ( $parent_subsystem => undef );
      push @result, \%item;

      #warn "getPredecessors push $parent_subsystem - undef";
    }
  }

  return \@result;
}

# TODO replacement for getPredecessors
sub getAncestorItems {

  # $params: {item_id  => 'eb6102a7-1fa0-4376-acbb-f67e34a2212c_28_vm_501c700f-56b0-a127-79e8-fed82513ad54'}
  # return array of hashes: [ { parent : 'UUID', subsystem : 'SUBSYS' } ]

  my $params = shift;
  my $dbh    = dbConnect();

  my $stmt = qq(WITH RECURSIVE
parent_of(parent, level) AS (
 VALUES(
  (SELECT item_relations.parent FROM item_relations WHERE item_relations.child = '$params->{item_id}'),
  0)
 UNION
 SELECT item_relations.parent, parent_of.level+1 FROM item_relations JOIN parent_of ON parent_of.parent = item_relations.child
)
SELECT parent_of.level, parent_of.parent, object_items.subsystem
 FROM parent_of JOIN object_items ON parent_of.parent = object_items.item_id
 GROUP BY parent_of.parent
 ORDER BY parent_of.level);

  my $result = $dbh->selectall_arrayref( $stmt, { Slice => {} } );
  my @res    = $result ? @{$result} : ();
  return \@res;
}

sub getAncestorSubsys {

  # $params: {hw_type => 'VMWARE', subsys => 'VM_FOLDER'}
  # returns array of hashes: [ { subsystem : 'SUBSYS1', parent : null, node : 2 } ]

  my $params = shift;
  my $dbh    = dbConnect();

  my $stmt = qq(WITH RECURSIVE
parent_of(subsystem, node, parent) AS (
 SELECT subsystems.subsystem, subsystems.subsystem_order, subsystems.subsystem_parent
 FROM subsystems
 WHERE subsystems.hw_type = '$params->{hw_type}' AND subsystems.subsystem = '$params->{subsys}'
 UNION
 SELECT subsystems.subsystem, subsystems.subsystem_order, subsystems.subsystem_parent
 FROM subsystems JOIN parent_of ON parent_of.parent = subsystems.subsystem_order
 WHERE subsystems.hw_type = '$params->{hw_type}'
)
SELECT * FROM parent_of);
  my $result = $dbh->selectall_arrayref( $stmt, { Slice => {} } );
  my @res    = $result ? @{$result} : ();
  return \@res;
}

################################################################################

sub getTree {

  # params: hw_type, [subsys, path_ids, [regexp], [is_menu, is_lazy]]
  my $params = shift;
  my @tree;

  # load params
  my ( $hw_type, $subsys, $regexp ) = ( '', '', '' );
  my @path_ids  = ();
  my $subsys_id = '';
  my $is_menu   = my $is_lazy = 0;
  $hw_type   = $params->{hw_type}       if ( exists $params->{hw_type} );
  $subsys    = $params->{subsys}        if ( exists $params->{subsys} );
  @path_ids  = @{ $params->{path_ids} } if ( exists $params->{path_ids} );
  $subsys_id = $path_ids[0]             if (@path_ids);
  $regexp    = $params->{regexp}        if ( exists $params->{regexp} );
  $is_menu   = $params->{is_menu}       if ( exists $params->{is_menu} );
  $is_lazy   = $params->{is_lazy}       if ( exists $params->{is_lazy} );

  my ( $acl, $is_granted );
  if ($is_menu) {
    require ACLx;
    $acl = ACLx->new();
  }

  if ($is_menu) {

    # check if showing this tree level is allowed
    $is_granted = 0;
    $is_granted += $acl->isGranted( { hw_type => $hw_type, subsys  => $subsys,    match => 'exists' } );
    $is_granted += $acl->isGranted( { hw_type => $hw_type, item_id => $subsys_id, match => 'exists' } );
    return \@tree unless ( $is_granted > 0 );

    # add totals: all, if showing this tree level is explicitly allowed; otherwise only the ACL-capable pages
    $is_granted = 0;
    $is_granted += $acl->isGranted( { hw_type => $hw_type, subsys  => $subsys,    match => 'granted' } );
    $is_granted += $acl->isGranted( { hw_type => $hw_type, item_id => $subsys_id, match => 'granted' } );

    my %params_totals = ( hw_type => $hw_type );
    ( $params_totals{subsys}, $params_totals{subsys_id} ) = ( $subsys, $subsys_id ) if ($subsys);
    $params_totals{acl_capable} = 1 unless ( $is_granted > 0 );
    my $menu_totals = _getMenuTotals( \%params_totals );
    push @tree, @{$menu_totals};
  }

  # get subsystems
  my $folder_level = 'subsys';
  my @subsystems;
  if ($subsys) {
    @subsystems = @{ getChildSubsys( { hw_type => $hw_type, parent_subsys => $subsys } ) };
  }
  else {
    $folder_level = 'hw_type';
    @subsystems   = @{ getTopSubsys( { hw_type => $hw_type } ) };
  }

  # if in a recursive folder, add self to subsystems and pretend to be in the parent subsystem
  my $is_subsys_recursive = isSubsysRecursive( { hw_type => $hw_type, subsys => $subsys } );
  if ($is_subsys_recursive) {
    my @subsystem_self = @{ getSelfSubsys( { hw_type => $hw_type, subsys => $subsys } ) };
    push @subsystems, @subsystem_self;
  }

  foreach my $subsystem (@subsystems) {

    # type of menu entries for this subsystem (folder(s), items)
    my $menu_items = $subsystem->{menu_items};

    if ( !$is_menu && $is_lazy ) {

      # if creating a lazy ACL tree, skip subsystems with 'inherit_acl_from' attribute, e.g., ESXi under VMware
      my $parent_subsys = getACLParentSubsysType( { hw_type => $hw_type, subsys => $subsystem->{subsystem} } );
      next if ($parent_subsys);
    }

    # get subsystem items
    my @subsystem_items;
    my %params_subsys = ( hw_type => $hw_type, subsys => $subsystem->{subsystem} );
    if ($subsys_id) {
      $params_subsys{parent} = $subsys_id;
      @subsystem_items = @{ getSubsysItemsFiltered( \%params_subsys ) };
    }
    else {
      @subsystem_items = @{ getSubsysItems( \%params_subsys ) };
    }

    if ($is_menu) {

      # if access to all items is forbidden based on ACL, skip this subsystem
      my @subsystem_filtered_items;
      foreach my $subsystem_item (@subsystem_items) {
        $is_granted = $acl->isGranted( { hw_type => $hw_type, item_id => $subsystem_item->{item_id}, match => 'exists' } );
        push @subsystem_filtered_items, $subsystem_item if ($is_granted);
      }
      next unless ( scalar @subsystem_filtered_items );
      @subsystem_items = @subsystem_filtered_items;
    }

    if ( !$is_subsys_recursive ) {

      # skip nested recursive folders in subsystems that are not recursive (inside recursive folders, path_ids take care of it)
      my $is_child_subsys_recursive = isSubsysRecursive( { hw_type => $hw_type, subsys => $subsystem->{subsystem} } );
      if ($is_child_subsys_recursive) {
        my @subsystem_filtered_items;
        foreach my $subsystem_item (@subsystem_items) {
          next if ( isAnyParentRecursive( { item_id => $subsystem_item->{item_id} } ) );
          push @subsystem_filtered_items, $subsystem_item;
        }
        next unless ( scalar @subsystem_filtered_items );
        @subsystem_items = @subsystem_filtered_items;
      }
    }

    # skip empty subsystem
    next unless ( scalar @subsystem_items );

    # create menu entries
    if ( $menu_items eq 'items' ) {
      my %params_items = ( hw_type => $hw_type, subsys => $subsystem->{subsystem}, subsys_id => $subsys_id, is_menu => $is_menu );
      $params_items{regexp} = $regexp if ($regexp);
      my $items = _getMenuItems( \%params_items );
      push @tree, @{$items};
    }
    elsif ( $menu_items eq 'folders' ) {
      my @folders;
      foreach my $subsystem_item (@subsystem_items) {
        my $label = $subsystem_item->{label};
        my $folder;
        if ($is_lazy) {
          $folder = _getFolder( { level => $folder_level, title => $label, is_lazy => 1 } );
          my $next_path_ids = join ',', ( $subsystem_item->{item_id}, @path_ids );
          $folder->{next_level} = { level => 'subsys', hw_type => $hw_type, subsys => $subsystem->{subsystem}, path_ids => $next_path_ids };
        }
        else {
          $folder = _getFolder( { level => $folder_level, title => $label } );
          my @next_path_ids = ( $subsystem_item->{item_id}, @path_ids );
          my $subtree       = getTree( { hw_type => $hw_type, subsys => $subsystem->{subsystem}, path_ids => \@next_path_ids, regexp => $regexp, is_menu => $is_menu, is_lazy => $is_lazy } );
          $folder->{children} = $subtree;
          $folder->{item_id}  = $subsystem_item->{item_id};
        }
        push @folders, $folder;
      }
      push @tree, @folders;
    }
    elsif ( $menu_items eq 'folder_items' ) {
      my $label = $subsystem->{label};
      my $folder;
      if ($is_lazy) {

        # TODO look-ahead, if the current item has children; if not, don't create the folder ($is_menu) or create only a node (!$is_menu)
        $folder = _getFolder( { level => $folder_level, title => $label ? $label : $subsystem->{subsystem}, is_lazy => 1 } );
        my $next_path_ids = join ',', @path_ids;
        $folder->{next_level} = { level => 'subsys', hw_type => $hw_type, subsys => $subsystem->{subsystem}, path_ids => $next_path_ids };
      }
      else {
        $folder = _getFolder( { level => $folder_level, title => $label ? $label : $subsystem->{subsystem} } );
        my $subtree = getTree( { hw_type => $hw_type, subsys => $subsystem->{subsystem}, path_ids => \@path_ids, regexp => $regexp, is_menu => $is_menu, is_lazy => $is_lazy } );
        $folder->{children} = $subtree;
      }
      push @tree, $folder;
    }
    elsif ( $menu_items eq 'folder_folders' ) {
      my $label = $subsystem->{label};
      my $folder_top;
      $folder_top = _getFolder( { level => $folder_level, title => $label ? $label : $subsystem->{subsystem} } );

      my @folders;
      foreach my $subsystem_item (@subsystem_items) {
        my $label = $subsystem_item->{label};
        my $folder;

        # the `&& !$is_menu` is a workaround for lazy ACL tree
        if ( $is_lazy && !$is_menu ) {

          # TODO look-ahead, if the $subsystem_item has children; if not, create only a node, not folder
          $folder = _getFolder( { level => $folder_level, title => $label, is_lazy => 1 } );
          my $next_path_ids = join ',', ( $subsystem_item->{item_id}, @path_ids );
          $folder->{next_level} = { level => 'subsys', hw_type => $hw_type, subsys => $subsystem->{subsystem}, path_ids => $next_path_ids };
        }
        else {
          $folder = _getFolder( { level => $folder_level, title => $label } );
          my @next_path_ids = ( $subsystem_item->{item_id}, @path_ids );
          my $subtree       = getTree( { hw_type => $hw_type, subsys => $subsystem->{subsystem}, path_ids => \@next_path_ids, regexp => $regexp, is_menu => $is_menu, is_lazy => $is_lazy } );
          $folder->{children} = $subtree;
          $folder->{item_id}  = $subsystem_item->{item_id};
        }
        push @folders, $folder;
      }
      $folder_top->{children} = \@folders;
      push @tree, $folder_top;
    }
  }

  # get items
  my %params_items = ( hw_type => $hw_type, subsys => $subsys, subsys_id => $subsys_id, is_menu => $is_menu );
  $params_items{regexp} = $regexp if ($regexp);
  my $items = _getMenuItems( \%params_items );
  push @tree, @{$items};

  return \@tree;
}

################################################################################

sub getLazyMenuFolder {

  # params: level => root|class|hw_type|subsys, class => SERVER|DB|CLOUD or hw_type => POWER|XENSERVER|…, [subsys, path_ids]
  my $params = shift;
  my @menu;

  if ( $params->{level} eq 'root' ) {

    # list classes
    @menu = @{ _getMenuClasses( { is_lazy => 1 } ) };
  }
  elsif ( $params->{level} eq 'class' ) {

    # list hw_types
    my $class = '';
    $class = $params->{class} if ( exists $params->{class} );
    @menu  = @{ _getMenuHwTypes( { class => $class, is_lazy => 1 } ) };
  }
  elsif ( $params->{level} eq 'hw_type' ) {

    # list totals and subsystems
    my $hw_type = '';
    $hw_type = $params->{hw_type} if ( exists $params->{hw_type} );
    @menu    = @{ getTree( { hw_type => $hw_type, is_menu => 1, is_lazy => 1 } ) };
  }
  elsif ( $params->{level} eq 'subsys' ) {

    # list totals, subsystems or items
    my ( $hw_type, $subsys, @path_ids ) = ( '', '', () );
    $hw_type  = $params->{hw_type}                if ( exists $params->{hw_type} );
    $subsys   = $params->{subsys}                 if ( exists $params->{subsys} );
    @path_ids = split( /,/, $params->{path_ids} ) if ( exists $params->{path_ids} );
    @menu     = @{ getTree( { hw_type => $hw_type, subsys => $subsys, path_ids => \@path_ids, is_menu => 1, is_lazy => 1 } ) };
  }
  return \@menu;
}

sub getACLTree {
  my @tree;

  my @hwtypes = @{ getHwTypes2( { active => 1 } ) };
  foreach my $hwtype (@hwtypes) {
    my $hw_type = $hwtype->{hw_type};
    my $folder  = _getFolder( { title => $hwtype->{label}, level => 'root' } );
    $folder->{next_level} = { level => 'hw_type', hw_type => $hw_type };
    my @subtree = @{ getTree( { hw_type => $hw_type, is_menu => 0, is_lazy => 0 } ) };
    $folder->{children} = \@subtree;
    push @tree, $folder;
  }
  return \@tree;
}

sub getLazyACLFolder {

  # params: level => root|hw_type|subsys, hw_type => POWER|XENSERVER|…, [subsys, path_ids]
  my $params = shift;
  my @tree;

  if ( $params->{level} eq 'root' ) {

    # list hw_types
    my @hwtypes = @{ getHwTypes2( { active => 1 } ) };
    foreach my $hwtype (@hwtypes) {
      my $hw_type = $hwtype->{hw_type};
      my $folder  = _getFolder( { title => $hwtype->{label}, level => 'root', is_lazy => 1 } );
      $folder->{next_level} = { level => 'hw_type', hw_type => $hw_type };
      push @tree, $folder;
    }
    my $custom_groups = getCustomGroupsACLFolder();
    push @tree, $custom_groups if ($custom_groups);
  }
  elsif ( $params->{level} eq 'hw_type' ) {

    # list totals and subsystems
    my $hw_type = '';
    $hw_type = $params->{hw_type} if ( exists $params->{hw_type} );
    @tree    = @{ getTree( { hw_type => $hw_type, is_menu => 0, is_lazy => 1 } ) };
  }
  elsif ( $params->{level} eq 'subsys' ) {

    # list totals, subsystems or items
    my ( $hw_type, $subsys, @path_ids ) = ( '', '', () );
    $hw_type  = $params->{hw_type}                if ( exists $params->{hw_type} );
    $subsys   = $params->{subsys}                 if ( exists $params->{subsys} );
    @path_ids = split( /,/, $params->{path_ids} ) if ( exists $params->{path_ids} );
    @tree     = @{ getTree( { hw_type => $hw_type, subsys => $subsys, path_ids => \@path_ids, is_menu => 0, is_lazy => 1 } ) };
  }
  return \@tree;
}

################################################################################

sub getCustomGroupsACLFolder {
  require CustomGroups;
  my %cgroups = CustomGroups::getGrp();
  my @items;
  foreach my $cgrp ( keys %cgroups ) {
    my $page;
    $page->{title} = $cgrp;
    push @items, $page;
  }

  my $folder = _getFolder( { title => uc 'Custom Groups', level => 'root' } );
  $folder->{children} = \@items;

  return $folder;
}

# copied and modified from STOR2RRD
sub getCustomGroupsMenuFolder {
  require CustomGroups;
  require ACLx;
  my $acl = ACLx->new();

  my %collections = CustomGroups::getCollections();
  my %groups      = CustomGroups::getGrp();

  if (%collections) {
    my $root = _getFolder( { title => uc 'Custom Groups', level => 'root' } );
    my @items;
    if ( $collections{collection} ) {
      for my $collname ( sort keys %{ $collections{collection} } ) {
        my $cfolder = _getFolder( { title => $collname, level => 'hw_type' } );
        my @citems;
        for my $cgrp ( sort keys %{ $collections{collection}{$collname} } ) {
          if ( $acl->isGranted( { hw_type => uc 'Custom Groups', item_id => $cgrp } ) ) {
            my $encgrp = Xorux_lib::urlencode($cgrp);
            my $type   = $groups{$cgrp}{type};
            my $href   = "/lpar2rrd-cgi/detail.sh?host=$type&server=na&lpar=$encgrp&item=custom&type=$type&name=$encgrp&storage=na";
            push @citems, { title => $cgrp, href => $href, page_type => 'custom' };
          }
        }
        if (@citems) {
          $cfolder->{children} = \@citems;
          push @items, $cfolder;
        }
      }
    }
    if ( $collections{nocollection} ) {
      for my $cgrp ( sort keys %{ $collections{nocollection} } ) {
        if ( $acl->isGranted( { hw_type => uc 'Custom Groups', item_id => $cgrp } ) ) {
          my $encgrp = Xorux_lib::urlencode($cgrp);
          my $type   = $groups{$cgrp}{type};
          my $href   = "/lpar2rrd-cgi/detail.sh?host=$type&server=na&lpar=$encgrp&item=custom&type=$type&name=$encgrp&storage=na";
          push @items, { title => $cgrp, href => $href, page_type => 'custom' };
        }
      }
    }
    $root->{children} = \@items;
    return $root;
  }
  else {
    return { title => uc 'Custom Groups', href => 'empty_cgrps.html' };
  }
}

################################################################################

sub _getMenuClasses {

  # params: [is_lazy]
  my $params = shift;
  my @menu;

  my $is_lazy = 0;
  $is_lazy = $params->{is_lazy} if ( exists $params->{is_lazy} );

  my $acl;
  require ACLx;
  $acl = ACLx->new();

  my @classes = @{ getClasses( { active => 1 } ) };
  foreach my $item_class (@classes) {
    my ( $class, $label ) = ( $item_class->{class}, $item_class->{label} );

    # check if any hw_type subfolders are allowed
    my $found   = 0;
    my @hwtypes = @{ getHwTypes2( { class => $class, active => 1 } ) };
    foreach my $item_hwtype (@hwtypes) {
      my $hw_type = $item_hwtype->{hw_type};
      if ( $acl->isGranted( { hw_type => $hw_type, match => 'exists' } ) ) {
        $found++;
        last;
      }
    }
    next unless $found;

    my $folder;
    if ($is_lazy) {
      $folder = _getFolder( { title => $label, level => 'root', is_lazy => $is_lazy } );
      $folder->{next_level} = { level => 'class', class => $class };
    }
    else {
      $folder = _getFolder( { title => $label, level => 'root' } );
    }
    push @menu, $folder;
  }

  return \@menu;
}

sub _getMenuHwTypes {

  # params: [class, is_lazy]
  my $params = shift;
  my @menu;

  my $class   = '';
  my $is_lazy = 0;
  $class   = $params->{class}   if ( exists $params->{class} );
  $is_lazy = $params->{is_lazy} if ( exists $params->{is_lazy} );

  my $acl;
  require ACLx;
  $acl = ACLx->new();

  my %params_hwtypes = ( active => 1 );
  $params_hwtypes{class} = $class if ($class);
  my @hwtypes = @{ getHwTypes2( \%params_hwtypes ) };
  foreach my $item (@hwtypes) {
    my ( $hw_type, $label ) = ( $item->{hw_type}, $item->{label} );
    next unless $acl->isGranted( { hw_type => $hw_type, match => 'exists' } );

    my $folder;
    if ($is_lazy) {
      $folder = _getFolder( { title => $label, level => 'class', is_lazy => $is_lazy } );
      $folder->{next_level} = { level => 'hw_type', hw_type => $hw_type };
    }
    else {
      $folder = _getFolder( { title => $label, level => 'class' } );
    }
    push @menu, $folder;
  }

  return \@menu;
}

sub _getMenuTotals {

  # params: hw_type, [subsys, subsys_id, [acl_capable]]
  #   if the acl_capable flag is set to 1, add *only* pages with the corresponding flag
  my $params = shift;
  my @menu;
  
  my $hw_type     = my $subsys = my $subsys_id = '';
  my $acl_capable = 0;
  $hw_type     = $params->{hw_type} if ( exists $params->{hw_type} );
  $subsys      = $hw_type;
  $subsys      = $params->{subsys}      if ( exists $params->{subsys} );
  $subsys_id   = $params->{subsys_id}   if ( exists $params->{subsys_id} );
  $acl_capable = $params->{acl_capable} if ( exists $params->{acl_capable} );

  # add totals
  my $menu   = Menu->new( lc $hw_type );
  my $totals = $menu->subsys_totals_page_types($subsys);
  
  foreach my $type ( @{$totals} ) {
    next if ( $acl_capable && !$menu->is_page_type_acl_capable($type) );
    
    if ($type eq 'pep2_all'){ 
      require PowercmcDataWrapper;
      next if (! PowercmcDataWrapper::configured());
    }

    my $page;
    my $title = $menu->page_title($type);
    $page->{title}        = $title ? $title : $type;
    $page->{page_type}    = $type;
    $page->{extraClasses} = 'menutotal';
    if ( $menu->is_page_type_folder_frontpage($type) ) {
      $page->{extraClasses} .= ' menufolderdefault';
    }
    if ($subsys_id) {
      $page->{href} = $menu->page_url( $type, $subsys_id );
    }
    else {
      $page->{href} = $menu->page_url($type);
    }
    push @menu, $page;
  }

  return \@menu;
}

sub _getMenuItems {

  # params: hw_type, subsys, subsys_id, is_menu, [regexp]
  my $params = shift;
  my @menu;

  my $hw_type = my $subsys = my $subsys_id = my $regexp = '';
  my $is_menu = 0;
  $hw_type   = $params->{hw_type}   if ( exists $params->{hw_type} );
  $subsys    = $params->{subsys}    if ( exists $params->{subsys} );
  $subsys_id = $params->{subsys_id} if ( exists $params->{subsys_id} );
  $is_menu   = $params->{is_menu}   if ( exists $params->{is_menu} );
  $regexp    = $params->{regexp}    if ( exists $params->{regexp} );

  my $acl;
  if ($is_menu) {
    require ACLx;
    $acl = ACLx->new();
  }

  # if the subsystem is recursive, its items are of the parent type
  my $is_subsys_recursive = isSubsysRecursive( { hw_type => $hw_type, subsys => $subsys } );
  if ($is_subsys_recursive) {
    my $parent_subsys = getRecursiveSubsystemItemType( { hw_type => $hw_type, subsys => $subsys } );
    $subsys = $parent_subsys if ($parent_subsys);
  }

  # get items
  my $menu      = Menu->new( lc $hw_type );
  my $page_type = $menu->subsys_items_page_type($subsys);
  unless ($page_type) { return \@menu; }

  my @subsystem_items =
    ($subsys_id)
    ? @{ getSubsysItemsFiltered( { hw_type => $hw_type, subsys => $subsys, parent => $subsys_id } ) }
    : @{ getSubsysItems( { hw_type => $hw_type, subsys => $subsys } ) };
SUBSYS_ITEMS: foreach my $subsystem_item (@subsystem_items) {

    # skip items that do not match the regexp
    next SUBSYS_ITEMS if ( $regexp && $subsystem_item->{label} !~ /$regexp/i );

    # skip items that are in nested recursive folders
    # TODO perhaps take ancestors' subsystems instead, check if any is recursive and different from the current level
    next SUBSYS_ITEMS if ( !$is_subsys_recursive && isAnyParentRecursive( { item_id => $subsystem_item->{item_id} } ) );

    # skip items that are not granted based on ACL
    if ( $is_menu && defined $acl ) {
      next SUBSYS_ITEMS unless ( $acl->isGranted( { hw_type => $hw_type, item_id => $subsystem_item->{item_id}, match => 'granted' } ) );
    }

    my $page;
    $page->{title}     = $subsystem_item->{label};
    $page->{item_id}   = $subsystem_item->{item_id};
    $page->{page_type} = $page_type;
    $page->{href}      = $menu->page_url( $page_type, $subsystem_item->{item_id} );
    push @menu, $page;
  }

  return \@menu;
}

sub _getFolder {

  # params: level, [hw_type, [subsys, path_ids]], [title], [is_lazy]
  my $params = shift;

  my %folder = ( folder => \1 );
  if ( defined $params->{level} )   { $folder{level}   = $params->{level}; }
  if ( defined $params->{hw_type} ) { $folder{hw_type} = $params->{hw_type}; }
  if ( defined $params->{subsys} )  { $folder{subsys}  = $params->{subsys}; }
  if ( defined $params->{title} )   { $folder{title}   = $params->{title}; }

  if ( $params->{is_lazy} ) {
    $folder{lazy}     = \1;
    $folder{children} = undef;
  }

  return \%folder;
}

################################################################################

sub getMenuPath {

  # params: {url => '%2Flpar2rrd-cgi%2Fdetail.sh%3Fplatform%3DXenServer%26type%3Dvm%26id%3D0c340bff-f118-4225-a34f-50b670eaf76b'}
  # return corresponding menu (parent folders etc.)
  my $params = shift;
  my @menu;
  
  # decode URL
  my $url = Xorux_lib::urldecode( $params->{url} );
  my ( $path, $query_string ) = split( /\?/, $url );
  my %url_params = %{ Xorux_lib::parse_url_params($query_string) };

  my %metadata = ( active_href => $url );
  push @menu, \%metadata;

  # new URLs created by Menu ought to have params: platform (hw_type), type (page_type), optional id (uuid)
  # old URLs have to be converted first
  if ( !defined $url_params{platform} || !defined $url_params{type} ) {
    $url = Xorux_lib::url_old_to_new($url);
    if ($url) {
      ( $path, $query_string ) = split( /\?/, $url );
      %url_params = %{ Xorux_lib::parse_url_params($query_string) };
      $menu[0]{active_href} = $url;
    }
    else {
      # unknown page type, give up
      $menu[0]{error} = 'unsupported url';
      return \@menu;
    }
  }
  
  my $hw_type   = uc $url_params{platform};

  # Not optimal solution:  
  # Powercmc is in Power menu with hwtype powercmc, both links_power.json, links_powercmc.json
  if ($hw_type eq "POWERCMC"){
    $hw_type = 'POWER';
  }

  my $page_type = $url_params{type};
  my $menu      = Menu->new( lc $hw_type );
  my $is_total  = $menu->is_page_type_singleton($page_type);
  my $class     = getClass( { hw_type => $hw_type } );

  my @menu_root     = @{ getLazyMenuFolder( { level => 'root' } ) };
  my @menu_classes  = @{ getLazyMenuFolder( { level => 'class',   class   => $class->{class} } ) };
  my @menu_hw_types = @{ getLazyMenuFolder( { level => 'hw_type', hw_type => $hw_type } ) };
  my $current_level = \@menu_root;

  # attach the hw_type folder to the menu tree
  for my $i ( 0 .. $#menu_root ) {
    if ( exists $menu_root[$i]{folder}
      && exists $menu_root[$i]{next_level}
      && exists $menu_root[$i]{next_level}{class}
      && $menu_root[$i]{next_level}{class} eq $class->{class} )
    {
      $menu_root[$i]{children} = \@menu_classes;
      $current_level = \@menu_classes;
      last;
    }
  }
  for my $i ( 0 .. $#menu_classes ) {
    if ( exists $menu_classes[$i]{folder}
      && exists $menu_classes[$i]{next_level}
      && exists $menu_classes[$i]{next_level}{hw_type}
      && $menu_classes[$i]{next_level}{hw_type} eq $hw_type )
    {
      $menu_classes[$i]{children} = \@menu_hw_types;
      $current_level = \@menu_hw_types;
      last;
    }
  }

  # figure out the subsystem
  #   the subsystem is loaded from the page type's definition
  #   but it can be an array to avoid repetition of the same page-type definitions with only different page types
  #     then if there is an item ID, look up the item's subsystem (code further below)
  #       or the page might a top-level "total" directly under the `hw_type`
  my $subsys;
  my $page_subsys = $menu->page_type_subsys($page_type);
  if ( defined $page_subsys ) {
    if ( ref $page_subsys eq 'ARRAY' ) {
      if ( !defined $url_params{id} && grep( /^$hw_type$/, @{$page_subsys} ) ) {
        $subsys = $hw_type;
      }
    }
    else {
      $subsys = $page_subsys;
    }
  }

  if ( defined $subsys && $hw_type eq $subsys ) {
    push @menu, @menu_root;
    return \@menu;
  }

  # assume that every subsys' page corresponds to some item with an id
  # (although in theory, it is possible to have an aggregated top-level folder with a totals page inside)
  if ( !defined $url_params{id} ) {
    $menu[0]{error} = 'undefined id';
    return \@menu;
  }

  my $item_id = $url_params{id};

  # getting the subsys continued
  if ( !defined $subsys ) {
    $subsys = getItemSubsys( { item_id => $item_id } );
  }

  # get the path through subsystem levels (except recursive folders, those will be added later, if applicable)
  my $ancestor_subsys = getAncestorSubsys( { hw_type => $hw_type, subsys => $subsys } );
  my @ancestor_subsys = $ancestor_subsys ? @{$ancestor_subsys} : ();

  # get ancestors
  my $ancestor_items = getAncestorItems( { item_id => $item_id } );
  my @ancestor_items = $ancestor_items ? @{$ancestor_items} : ();

  # if the item is not embedded in a single subsystem folder ('menu_items' attribute), add it to ancestors
  my $self_subsys = getSelfSubsys( { hw_type => $hw_type, subsys => $subsys } );
  if ($self_subsys) {
    my $current_subsys = ( ref $self_subsys eq 'ARRAY' ) ? @{$self_subsys}[0] : $self_subsys;
    unless ( $current_subsys->{menu_items} =~ m/^folder_/ ) {
      my %subsys_item = ( subsystem => $subsys, parent => $item_id );
      push @ancestor_items, \%subsys_item;
    }
  }

  # if the page is a "total" in a nested folder (e.g., "LAN Totals" page in "LAN" folder under a Power SERVER)
  #   and it is identified by the parent UUID, add the parent to ancestors
  my $item_subsys = getItemSubsys( { item_id => $item_id } );
  if ( $is_total && $subsys ne $item_subsys ) {
    my %subsys_item = ( subsystem => $item_subsys, parent => $item_id );
    push @ancestor_items, \%subsys_item;
  }

  # add recursive-folder subsystems to subsystem levels, if there are any such items
  my $successor_recursive_folder_subsys = getSuccessorRecursiveFolderSubsys( { hw_type => $hw_type, subsys => $subsys } );
  my @successor_recursive_folder_subsys = $successor_recursive_folder_subsys ? @{$successor_recursive_folder_subsys} : ();
  foreach my $recursive_subsys (@successor_recursive_folder_subsys) {
    unshift @ancestor_subsys, $recursive_subsys if ( grep { $recursive_subsys->{subsystem} eq $_->{subsystem} } @ancestor_items );
  }

  my @passed_parent_ids;
  foreach my $subsys_level ( reverse @ancestor_subsys ) {
    my %subsys_hash          = %{$subsys_level};
    my $current_subsys_level = $subsys_hash{subsystem};

    # is there any ancestor item for this subsystem? (ancestor items, if the subsystem is a recursive folder)
    my $items_found = 0;
    foreach my $ancestor_item ( reverse @ancestor_items ) {
      my %item_hash = %{$ancestor_item};
      my ( $ancestor_subsys, $ancestor_item_id ) = ( $item_hash{subsystem}, $item_hash{parent} );
      next unless ( $ancestor_subsys eq $current_subsys_level );
      $items_found++;

      # create folder
      unshift @passed_parent_ids, $ancestor_item_id;
      my $current_parent_ids = join ',', @passed_parent_ids;
      my %menu_params        = ( level => 'subsys', hw_type => $hw_type, subsys => $current_subsys_level );
      $menu_params{path_ids} = $current_parent_ids if ($current_parent_ids);
      my @menu_subsys = @{ getLazyMenuFolder( \%menu_params ) };

      # attach the subsystem folder to the menu tree
      my @menu_parent = @{$current_level};
      for my $i ( 0 .. $#menu_parent ) {
        if ( exists $menu_parent[$i]{folder}
          && exists $menu_parent[$i]{next_level}
          && exists $menu_parent[$i]{next_level}{subsys}
          && $menu_parent[$i]{next_level}{subsys} eq $current_subsys_level )
        {
          my $attach = 1;
          if ( exists $menu_parent[$i]{next_level}{path_ids} ) {
            my @candidate_parents = split ',', $menu_parent[$i]{next_level}{path_ids};
            $attach = 0 unless ( grep( /^$ancestor_item_id$/, @candidate_parents ) );
          }

          if ($attach) {
            $menu_parent[$i]{children} = \@menu_subsys;
            $current_level = \@menu_subsys;
            last;
          }
        }
      }
    }

    # if there is no ancestor item, this subsystem level is only a single folder
    if ( $items_found == 0 ) {

      # create folder
      my $current_parent_ids = join ',', @passed_parent_ids;
      my %menu_params        = ( level => 'subsys', hw_type => $hw_type, subsys => $current_subsys_level );
      $menu_params{path_ids} = $current_parent_ids if ($current_parent_ids);
      my @menu_subsys = @{ getLazyMenuFolder( \%menu_params ) };

      # attach the subsystem folder to the menu tree
      my @menu_parent = @{$current_level};
      for my $i ( 0 .. $#menu_parent ) {
        if ( exists $menu_parent[$i]{folder}
          && exists $menu_parent[$i]{next_level}
          && exists $menu_parent[$i]{next_level}{subsys}
          && $menu_parent[$i]{next_level}{subsys} eq $current_subsys_level )
        {
          $menu_parent[$i]{children} = \@menu_subsys;
          $current_level = \@menu_subsys;
          last;
        }
      }
    }
  }

  push @menu, @menu_root;
  return \@menu;
}

################################################################################

sub filterMenuParent {

  # $params: {hw_type => POWER|XENSERVER|…, regexp => 'regexp string to search in object/item labels'}
  my $params = shift;

  my $hw_type = $params->{hw_type};
  my $regexp  = $params->{regexp};

  my @menu = @{ getTree( { hw_type => $hw_type, regexp => $regexp, is_menu => 1, is_lazy => 0 } ) };

  return \@menu;
}

################################################################################

# TODO replace
sub getTitles {

  # params: regexp => "regexp string to search in item labels"
  # params: type => 'hw_type'

  require ACLx;
  my $acl = ACLx->new();

  my $params = shift;
  my $dbh    = dbConnect();
  my $sql    = <<'EOSQL';
SELECT label, item_id FROM object_items
WHERE label REGEXP '(?i:' || :regex || ')' AND hw_type = :type
ORDER BY label
EOSQL
  my $stm = $dbh->prepare($sql);
  $stm->bind_param( ':regex', $params->{regexp} );
  $stm->bind_param( ':type',  $params->{type} );
  $stm->execute() or die $DBI::errstr;

  my %titles;
  while ( ( my $row = $stm->fetchrow_hashref() ) && keys %titles < 9 ) {
    if ( $acl->isGranted( { hw_type => $params->{type}, item_id => $row->{item_id} } ) ) {
      $titles{ $row->{label} } = ();
    }
  }

  my @result = sort keys %titles;
  return \@result;
}

sub getCGTitles {

  # params: { topsystem: subsystem[][], subsystem: subsystem[], hw_types: hw_type[], data: {level: level, selected: true},
  #  children:
  #   [{ data: {name: regexpStorage, selected: false}, children:
  #     [{ data: {name: regexpItem, selected: false}}]
  #   }]}

  require ACLx;
  my $acl = ACLx->new();

  my $params = shift;
  my $dbh    = dbConnect();
  my $stm;
  my @hwTypes;
  for my $hwType ( @{ $params->{hw_types} } ) {
    if ( $acl->isGranted( { hw_type => $hwType, subsys => $params->{data}{subsystem} } ) ) {
      push @hwTypes, $hwType;
    }
  }

  #my @topsystem = @{$params->{topsystem}};
  my @subsystem     = @{ $params->{subsystem} };
  my $hwHolders     = join ', ', (q{?}) x @hwTypes;
  my $topJoin       = '';
  my $topConstraint = '';
  my $parentKey     = "'$hwTypes[0]'";
  # if ( $params->{topsystem} ) {
  #   $topJoin = 'INNER JOIN item_relations ir ON ir.child = oi.item_id INNER JOIN object_items oiParent ON oiParent.item_id = ir.parent';
  #   my $topHolders = join ', ', (q{?}) x @{ $params->{topsystem} };
  #   $topConstraint = "oiParent.subsystem IN ($topHolders) AND oiParent.label REGEXP '(?i:' || ? || ')' AND";
  # }
  if ( $params->{topsystem} ) {
    my $i = 0;
    for my $topsystems (@{$params->{topsystem}}) {
      my $prev = $i;
      $i++;
      $topJoin .= "INNER JOIN item_relations ir$i ON ir$i.child = oi$prev.item_id INNER JOIN object_items oi$i ON oi$i.item_id = ir$i.parent\n";
      my $topHolders = join ', ', (q{?}) x @{ $topsystems };
      $topConstraint .= "oi$i.subsystem IN ($topHolders) AND oi$i.label REGEXP '(?i:' || ? || ')' AND ";
    }
    $parentKey = "oi$i.label";
  }
  my $subHolders = join ', ', (q{?}) x @subsystem;

  if ( $params->{data}{level} == 2 ) {
    my $sql = <<"EOSQL";
SELECT oi0.label, oi0.hw_type, oi0.item_id FROM object_items oi0
$topJoin
WHERE $topConstraint oi0.subsystem IN ($subHolders) AND oi0.hw_type IN ($hwHolders) AND oi0.label REGEXP '(?i:' || ? || ')'
ORDER BY oi0.label
EOSQL
    my $selectedParent = _getSelectedCGParent( $params->{children} );
    my $selected       = _getSelectedCGItem( $params->{children} );
    if($selected->{data}{name} eq '.*' or $selected->{data}{name} eq '.') {
      return [];
    }
    $stm = $dbh->prepare($sql);
    if ( $params->{topsystem} ) {
      my @flatTopSystems = map {@$_} @{$params->{topsystem}};
      $stm->execute( @flatTopSystems, $selectedParent->{data}{name}, @subsystem, @hwTypes, $selected->{data}{name} ) or die $DBI::errstr;
    }
    else {
      $stm->execute( @subsystem, @hwTypes, $selected->{data}{name} ) or die $DBI::errstr;
    }
  }
  elsif ( $params->{data}{level} == 1 ) {
    if ( not defined $params->{topsystem} ) { return [] }
    my @flatTopSystems = map {@$_} @{$params->{topsystem}};
    my $topHolders = join ', ', (q{?}) x @flatTopSystems;
    my $sql        = <<"EOSQL";
SELECT oi.label, oi.hw_type, oi.item_id FROM object_items oi
WHERE oi.subsystem IN ($topHolders) AND oi.hw_type IN ($hwHolders) AND oi.label REGEXP '(?i:' || ? || ')'
ORDER BY oi.label
EOSQL
    my $selected = _getSelectedCGItem( $params->{children} );
    $stm = $dbh->prepare($sql);
    $stm->execute( @flatTopSystems, @hwTypes, $selected->{data}{name} ) or die $DBI::errstr;
  }

  my %labels;
  while ( ( my $row = $stm->fetchrow_hashref() ) #&& keys %labels < 9
  ) {
    if ( $acl->isGranted( { hw_type => $row->{hw_type}, item_id => $row->{item_id} } ) ) {
      $labels{ $row->{label} } = ();
    }
  }

  my @result = sort keys %labels;
  return \@result;
}

sub getCGPreview {

  # params: { topsystem: subsystem[][], subsystem: subsystem[], hw_types: hw_type[], data: {level: level, selected: true},
  #  children:
  #   [{ data: {name: regexpStorage, selected: false}, children:
  #     [{ data: {name: regexpItem, selected: false}}]
  #   }]}

  require ACLx;
  my $acl = ACLx->new();

  my $params = shift;

  my @hwTypes;
  for my $hwType ( @{ $params->{hw_types} } ) {
    if ( $acl->isGranted( { hw_type => $hwType, subsys => $params->{data}{subsystem} } ) ) {
      push @hwTypes, $hwType;
    }
  }

  my @regexps;
  if ( $params->{data}{level} == 2 ) {
    my $selectedParent = _getSelectedCGParent( $params->{children} );
    push @regexps, $selectedParent->{data}{name};
    my $selected = _getSelectedCGItem( $params->{children} );
    push @regexps, $selected->{data}{name};
  }
  elsif ( $params->{data}{level} == 1 ) {
    my $selected = _getSelectedCGItem( $params->{children} );
    push @regexps, $selected->{data}{name};
    my $joinedRegexp = join( '|', map { $_->{data}{name} } @{ $selected->{children} } );
    push @regexps, $joinedRegexp;
  }
  else {
    for my $stor ( @{ $params->{children} } ) {
      push @regexps, $stor->{data}{name};
      my $joinedRegexp = join( '|', map { $_->{data}{name} } @{ $stor->{children} } );
      push @regexps, $joinedRegexp;
    }
  }
  my $whereRegex = '(' . join( ') OR (', (q{key REGEXP '(^' || ? || '$)' AND oi0.label REGEXP '(^' || ? || '$)'}) x scalar @regexps / 2 ) . ')';

  my $dbh = dbConnect();

  # recursive requires sqlite 3.8.3, centos7 has only 3.7 -> store server object_id
  my $sql = do {
    my $holders       = join ', ', (q{?}) x @hwTypes;
    my $parentKey     = "'$hwTypes[0]'";
    my $topJoin       = '';
    my $topConstraint = '';
    if ( $params->{topsystem} ) {
      my $i = 0;
      for my $topsystems (@{$params->{topsystem}}) {
        my $prev = $i;
        $i++;
        $topJoin .= "INNER JOIN item_relations ir$i ON ir$i.child = oi$prev.item_id INNER JOIN object_items oi$i ON oi$i.item_id = ir$i.parent\n";
        my $topHolders = join ', ', (q{?}) x @{ $topsystems };
        $topConstraint .= "oi$i.subsystem IN ($topHolders) AND ";
      }
      $parentKey = "oi$i.label";
    }
    my $subHolders = join ', ', (q{?}) x @{ $params->{subsystem} };
    <<"EOSQL";
SELECT $parentKey as key, oi0.label as item, oi0.item_id, oi0.hw_type FROM object_items oi0
$topJoin
WHERE $topConstraint oi0.subsystem IN ($subHolders) AND oi0.hw_type IN ($holders) AND ($whereRegex)
ORDER BY key
EOSQL
  };

  my $stm = $dbh->prepare($sql);
  if ( $params->{topsystem} ) {
    my @flatTopSystems = map {@$_} @{$params->{topsystem}};
    $stm->execute( @flatTopSystems, @{ $params->{subsystem} }, @hwTypes, @regexps ) or die $DBI::errstr;
  }
  else {
    $stm->execute( @{ $params->{subsystem} }, @hwTypes, @regexps ) or die $DBI::errstr;
  }

  my %hash;
  while ( ( my $row = $stm->fetchrow_hashref() ) ) {
    if ( $acl->isGranted( { hw_type => $row->{hw_type}, item_id => $row->{item_id} } ) ) {
      if ( !exists $hash{ $row->{key} } ) {
        $hash{ $row->{key} } = $row->{item};
      }
      else {
        $hash{ $row->{key} } = $hash{ $row->{key} } . ', ' . $row->{item};
      }
    }
  }
  return \%hash;
}

sub _getSelectedCGParent {
  my $items = shift;

  if ( !defined $items ) {
    return;
  }
  for my $item (@$items) {
    if ( $item->{data}{selected} ) {
      return $item;
    }
    my $result = _getSelectedCGParent( $item->{children} );
    if ( defined $result ) {
      return $item;
    }
  }
  return;
}

sub _getSelectedCGItem {
  my $items = shift;
  if ( !defined $items ) {
    return;
  }
  for my $item (@$items) {
    if ( $item->{data}{selected} ) {
      return $item;
    }
    my $result = _getSelectedCGItem( $item->{children} );
    if ( defined $result ) {
      return $result;
    }
  }
  return;
}

sub searchGlobal() {

  # params: q => "global label search for containing query, no regexp support"

  my $params = shift;
  my $dbh    = dbConnect();
  my $sql    = <<"EOSQL";
select oi.item_id, oi.object_id, oi.label, oi.hw_type, oi.subsystem from object_items as oi
where label like '%'|| ? ||'%'
EOSQL

  my $stm = $dbh->prepare($sql);
  $stm->execute( $params->{q} ) or die $DBI::errstr;
  my $hash_ref = $stm->fetchall_arrayref( {} );

  return $hash_ref;
}

sub getSqliteVersion() {
  my $dbh     = dbConnect();
  my $version = $dbh->selectrow_arrayref('select sqlite_version()');
  return $version;
}

# SQL commands
# ##################
#
# get items being a child (has parent)
# SELECT * FROM objects, object_items WHERE EXISTS (SELECT parent FROM item_relations WHERE child = object_items.item_id );

1;

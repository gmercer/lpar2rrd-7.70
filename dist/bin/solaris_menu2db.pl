# store SOLARIS data from menu.txt to SQLite database

##### RUN SCRIPT WITHOUT ARGUMENTS:
######
###### . /home/lpar2rrd/lpar2rrd/etc/lpar2rrd.cfg ; $PERL bin/solaris_menu2db.pl
######

use strict;
use warnings;

use Data::Dumper;

# use JSON qw(decode_json encode_json);
use DBI;

use SQLiteDataWrapper;
use Xorux_lib;

defined $ENV{INPUTDIR} || Xorux_lib::error( " INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg " . __FILE__ . ":" . __LINE__ ) && exit 1;

# data file paths
my $inputdir = $ENV{INPUTDIR};

my $basedir     = $ENV{INPUTDIR};
my $wrkdir      = "$basedir/data";
my $tmpdir      = "$basedir/tmp";
my $solaris_dir = "$wrkdir/Solaris";
if ( defined $ENV{TMPDIR_LPAR} ) {
  $tmpdir = $ENV{TMPDIR_LPAR};
}

#my $db_filepath         = "$inputdir/data/data.db";
#my $iostats_dir         = "$inputdir/data/power_iostats";
#my $metadata_file       = "$iostats_dir/conf.json";

################################################################################

my %data_in;
my %data_out;
my $DEBUG = ( exists $ENV{DEBUG} ) ? $ENV{DEBUG} : 0;

################################################################################

# load data source:
my $menu_file = "$tmpdir/menu.txt";
my @menu;

if ( !-f $menu_file ) {
  Xorux_lib::error( "file $menu_file does not exist " . __FILE__ . ":" . __LINE__ ) && exit 1;
}
open FH, "$menu_file" or error( "can't open $menu_file: $! " . __FILE__ . ":" . __LINE__ ) && exit 1;
@menu = <FH>;
close FH;

#print "menu file \n@menu\n";

################################################################################

# fill tables

# save %data_out
#
# my $params = {id => $st_serial, label => $st_name, hw_type => "VIRTUALIZATION TYPE"};
# SQLiteDataWrapper::object2db( $params );
# $params = { id => $st_serial, subsys => "DEVICE", data => $data_out{DEVICE} };
# SQLiteDataWrapper::subsys2db( $params );

# LPAR2RRD:  SOLARIS assignment
# (TODO remove) object: hw_type => "SOLARIS", label => "Solaris", id => "DEADBEEF"
# params: id                    => "DEADBEEF", subsys => "(CDOM|LDOM|ZONE_C|ZONE_L)", data => $data_out{(CDOM|LDOM|ZONE_C|ZONE_L)}

my $object_hw_type = "SOLARIS";
my $object_label   = "Solaris";
my $object_id      = "SOLARIS";
my $last_uuid_cdom = "";

if ( -d $solaris_dir ) {
  my $params = { id => $object_id, label => $object_label, hw_type => $object_hw_type };
  SQLiteDataWrapper::object2db($params);
}

########## prepare CDOMS/LDOMS
########## L:no_hmc:CDOM1:CDOM1===double-col===CDOM1:CDOM1===double-col===CDOM1:/lpar2rrd-cgi/detail.sh?host=0&server=Solaris--unknown&lpar=CDOM1===double-col===CDOM1&item=sol-ldom&entitle=0&gui=1&none=none::CDOM1:S:L
##########
my @cdoms            = grep { $_ =~ /^L:/ && index( $_, ":S:L" ) > 0 } @menu;
my @zones            = grep { $_ =~ /^L:/ && index( $_, ":S:Z" ) > 0 } @menu;
my @standalone_ldoms = grep { $_ =~ /^L:/ && index( $_, ":S:G" ) > 0 } @menu;

#print "\@cdoms @cdoms\n";
#print "\@zones @zones\n";
#print "\@standalone_ldoms @standalone_ldoms\n";

#####################################################
####### Totals
#####################################################

if ( -d $solaris_dir ) {
  $data_in{SOLARIS}{total_solaris}{label} = 'Total';
  if ( exists $data_in{SOLARIS}{total_solaris}{label} ) { $data_out{total_solaris}{label} = $data_in{SOLARIS}{total_solaris}{label}; }
  my $params_totals = { id => $object_id, subsys => 'SOLARIS_TOTAL', data => \%data_out };
  SQLiteDataWrapper::subsys2db($params_totals);
}

#print Dumper $params_totals;

if ( -d $solaris_dir ) {
  print "solaris_menu.db - Start to generate Solaris CDOM/LDOM/ZONES to DB\n";
}
else {
  print "solaris_menu.db - Solaris is not setup\n";
  exit;
}
#####################################################
######### CDOM/LDOM/ZONES (everything under CDOM)
#####################################################

foreach (@cdoms) {
  my ( undef, undef, $ldom, undef, undef, undef, undef, $cdom ) = split( ':', $_ );

  #####################################################
  ######### CDOM
  #####################################################

  my $uuid_cdom = "";
  if ( $cdom eq $ldom ) {
    my $cdom_uuid_file = "$wrkdir/Solaris/$cdom:$ldom/uuid.txt";
    if ( -f $cdom_uuid_file ) {
      if ( open my $id1, "$cdom_uuid_file" ) {
        $uuid_cdom = <$id1>;
        chomp $uuid_cdom;
        close $id1;
      }
      else {
        error( "can't open $cdom_uuid_file : $! " . __FILE__ . ":" . __LINE__ );
      }

    }
    $last_uuid_cdom = $uuid_cdom;
    if ($uuid_cdom) { $data_in{SOLARIS}{$uuid_cdom}{label} = $cdom; }
    undef %data_out;
    if ( exists $data_in{SOLARIS}{$uuid_cdom}{label} ) { $data_out{$uuid_cdom}{label} = $data_in{SOLARIS}{$uuid_cdom}{label}; }
    my $params = { id => $object_id, subsys => 'CDOM', data => \%data_out };
    SQLiteDataWrapper::subsys2db($params);

    #print Dumper $params;
    print "\nCDOM    found:            $ldom(uuid-$uuid_cdom)\n";
    my @list_zone = grep {/$cdom/} @zones;

    #####################################################
    ######### ZONE under CDOM/LDOM
    #####################################################

    foreach (@list_zone) {
      my ( undef, undef, $cdom_test, $zone_name, undef, undef, undef, $cdom ) = split( ':', $_ );
      my $type_zone = "ZONE_C";
      if ( $cdom_test ne $cdom ) {    ### if it is not equal so zone belongs to LDOM
        $type_zone = "ZONE_L";
        my $ldom_uuid_file = "$wrkdir/Solaris/$cdom:$cdom_test/uuid.txt";

        #print "ldom_uuid_file-$ldom_uuid_file\n";
        if ( -f $ldom_uuid_file ) {
          if ( open my $id2, "$ldom_uuid_file" ) {
            $uuid_cdom = <$id2>;
            chomp $uuid_cdom;
            close $id2;
          }
          else {
            error( "can't open $cdom_uuid_file : $! " . __FILE__ . ":" . __LINE__ );
          }
        }
      }
      my $zone = $zone_name;
      $zone_name = "$uuid_cdom" . "_" . "$zone_name";
      my @last_uuid_cdoms = $uuid_cdom;
      if ($zone_name) { $data_in{SOLARIS}{$zone_name}{label}   = $zone; }
      if ($uuid_cdom) { $data_in{SOLARIS}{$zone_name}{parents} = \@last_uuid_cdoms; }
      undef %data_out;
      if ( exists $data_in{SOLARIS}{$zone_name}{label} )   { $data_out{$zone_name}{label}   = $data_in{SOLARIS}{$zone_name}{label}; }
      if ( exists $data_in{SOLARIS}{$zone_name}{parents} ) { $data_out{$zone_name}{parents} = $data_in{SOLARIS}{$zone_name}{parents}; }
      my $params_zone = { id => $object_id, subsys => $type_zone, data => \%data_out };

      #print Dumper $params_zone;
      SQLiteDataWrapper::subsys2db($params_zone);
      print "ZONE    found:            $zone_name(parrent_uuid-$uuid_cdom)\n";

      #print "GREP-ZONE:$zone_name--$cdom\n";
    }
  }

  #####################################################
  ######### LDOM under CDOM
  #####################################################

  else {
    my $uuid_ldom      = "";
    my $ldom_uuid_file = "$wrkdir/Solaris/$cdom:$ldom/uuid.txt";
    if ( -f $ldom_uuid_file ) {
      if ( open my $id2, "$ldom_uuid_file" ) {
        $uuid_ldom = <$id2>;
        chomp $uuid_ldom;
        close $id2;
      }
      else {
        error( "can't open $ldom_uuid_file : $! " . __FILE__ . ":" . __LINE__ );
      }

    }
    if ($uuid_ldom) { $data_in{SOLARIS}{$uuid_ldom}{label} = $ldom; }
    ########## save parent CDOM uuid
    my @last_uuid_cdoms = $last_uuid_cdom;
    if ($last_uuid_cdom) { $data_in{SOLARIS}{$uuid_ldom}{parents} = \@last_uuid_cdoms; }
    undef %data_out;
    if ( exists $data_in{SOLARIS}{$uuid_ldom}{label} )   { $data_out{$uuid_ldom}{label}   = $data_in{SOLARIS}{$uuid_ldom}{label}; }
    if ( exists $data_in{SOLARIS}{$uuid_ldom}{parents} ) { $data_out{$uuid_ldom}{parents} = $data_in{SOLARIS}{$uuid_ldom}{parents}; }
    my $params = { id => $object_id, subsys => 'LDOM', data => \%data_out };
    SQLiteDataWrapper::subsys2db($params);

    #print Dumper $params;
    print "LDOM    found:            $ldom(uuid-$uuid_ldom,parrent_cdom_uuid-$last_uuid_cdom)\n";
  }
}

#####################################################
######### STANDALONE LDOM
#####################################################

foreach (@standalone_ldoms) {
  my ( undef, undef, $standalone_ldom ) = split( ':', $_ );
  my $uuid_standalone_ldom;
  my $standalone_ldom_uuid_file = "$wrkdir/Solaris/$standalone_ldom/uuid.txt";
  if ( -f $standalone_ldom_uuid_file ) {
    if ( open my $id3, "$standalone_ldom_uuid_file" ) {
      $uuid_standalone_ldom = <$id3>;
      chomp $uuid_standalone_ldom;
      close $id3;
    }
    else {
      error( "can't open $standalone_ldom_uuid_file : $! " . __FILE__ . ":" . __LINE__ );
    }
    if ($uuid_standalone_ldom) { $data_in{SOLARIS}{$uuid_standalone_ldom}{label} = $standalone_ldom; }
    undef %data_out;
    if ( exists $data_in{SOLARIS}{$uuid_standalone_ldom}{label} ) { $data_out{$uuid_standalone_ldom}{label} = $data_in{SOLARIS}{$uuid_standalone_ldom}{label}; }
    my $params = { id => $object_id, subsys => 'STANDALONE_LDOM', data => \%data_out };
    SQLiteDataWrapper::subsys2db($params);

    #print Dumper $params;
    print "S_LDOM  found:            $standalone_ldom-$uuid_standalone_ldom\n";
    my @list_zone = grep {/$standalone_ldom/} @zones;

    #####################################################
    ######### ZONE under STANDALONE LDOM
    #####################################################

    foreach (@list_zone) {
      my ( undef, undef, $ldom_test, $zone_name, undef, undef, undef, $cdom ) = split( ':', $_ );
      my ( undef, $type_of_solaris ) = split( 'item=', $_ );
      ######################################
      ###### If Version Solaris11 or 10.
      my $solaris_version = "";
      $type_of_solaris =~ s/&\S+\s+//g;
      if ( $type_of_solaris =~ /sol10/ ) {
        $solaris_version = "10";
      }
      else { $solaris_version = "11"; }
      my $subsys = "STANDALONE_ZONE_L$solaris_version";
      ######################################

      my $ldom_uuid_file = "$wrkdir/Solaris/$ldom_test/uuid.txt";
      my $uuid_ldom      = "";

      #print "ldom_uuid_file-$ldom_uuid_file\n";
      if ( -f $ldom_uuid_file ) {
        if ( open my $id4, "$ldom_uuid_file" ) {
          $uuid_ldom = <$id4>;
          chomp $uuid_ldom;
          close $id4;
        }
        else {
          error( "can't open $ldom_uuid_file : $! " . __FILE__ . ":" . __LINE__ );
        }
      }
      if ( $uuid_ldom eq "" ) {next}    # if zone not have uuid (solaris10 for example)
      my $zone = $zone_name;
      $zone_name = "$uuid_ldom" . "_" . "$zone_name";
      my @last_uuid_ldoms = $uuid_ldom;
      if ($zone_name) { $data_in{SOLARIS}{$zone_name}{label}   = $zone; }
      if ($uuid_ldom) { $data_in{SOLARIS}{$zone_name}{parents} = \@last_uuid_ldoms; }
      undef %data_out;
      if ( exists $data_in{SOLARIS}{$zone_name}{label} )   { $data_out{$zone_name}{label}   = $data_in{SOLARIS}{$zone_name}{label}; }
      if ( exists $data_in{SOLARIS}{$zone_name}{parents} ) { $data_out{$zone_name}{parents} = $data_in{SOLARIS}{$zone_name}{parents}; }
      my $params_zone = { id => $object_id, subsys => $subsys, data => \%data_out };

      #print Dumper $params_zone;
      SQLiteDataWrapper::subsys2db($params_zone);
      print "ZONE    found:            $zone_name(parrent_uuid-$uuid_ldom)\n";
    }
  }
  else {    # if does not exists uuid.txt in directory Solaris
    my $uuid_standalone_ldom;
    my $standalone_ldom_uuid_file = "$wrkdir/Solaris--unknown/no_hmc/$standalone_ldom/uuid.txt";
    if ( -f $standalone_ldom_uuid_file ) {
      if ( open my $id3, "$standalone_ldom_uuid_file" ) {
        my $line = <$id3>;
        if ( $line =~ /\// ) {
          ( undef, $uuid_standalone_ldom, undef ) = split( /\//, $line );
          chomp $uuid_standalone_ldom;
          close $id3;
        }
        else {
          $uuid_standalone_ldom = $line;
          chomp $uuid_standalone_ldom;
          close $id3;
        }
      }
      else {
        error( "can't open $standalone_ldom_uuid_file : $! " . __FILE__ . ":" . __LINE__ );
      }
      if ($uuid_standalone_ldom) { $data_in{SOLARIS}{$uuid_standalone_ldom}{label} = $standalone_ldom; }
      undef %data_out;
      if ( exists $data_in{SOLARIS}{$uuid_standalone_ldom}{label} ) { $data_out{$uuid_standalone_ldom}{label} = $data_in{SOLARIS}{$uuid_standalone_ldom}{label}; }
      my $params = { id => $object_id, subsys => 'STANDALONE_LDOM', data => \%data_out };
      SQLiteDataWrapper::subsys2db($params);

      #print Dumper $params;
      print "S_LDOM  found:            $standalone_ldom-$uuid_standalone_ldom\n";
      my @list_zone = grep {/$standalone_ldom/} @zones;
      foreach (@list_zone) {
        my ( undef, undef, $ldom_test, $zone_name, undef, undef, undef, $cdom ) = split( ':', $_ );
        my ( undef, $type_of_solaris ) = split( 'item=', $_ );
        if ( $ldom_test ne "$standalone_ldom" ) {next}

        #print "$ldom_test,$zone_name,$cdom |$standalone_ldom| $type_of_solaris\n";
        ######################################
        ###### If Version Solaris11 or 10.
        my $solaris_version = "";
        $type_of_solaris =~ s/&\S+\s+//g;
        if ( $type_of_solaris =~ /sol10/ ) {
          $solaris_version = "10";
        }
        else { $solaris_version = "11"; }
        my $subsys = "STANDALONE_ZONE_L$solaris_version";
        ######################################

        my $ldom_uuid_file = "$wrkdir/Solaris--unknown/no_hmc/$ldom_test/uuid.txt";
        my $uuid_ldom      = "";

        #print "ldom_uuid_file-$ldom_uuid_file\n";
        if ( -f $ldom_uuid_file ) {
          if ( open my $id4, "$ldom_uuid_file" ) {
            my $line = <$id4>;
            if ( $line =~ /\// ) {
              ( undef, $uuid_ldom, undef ) = split( /\//, $line );
              chomp $uuid_ldom;
              close $id4;
            }
            else {
              $uuid_ldom = $line;
              chomp $uuid_ldom;
              close $id4;
            }
          }
          else {
            error( "can't open $ldom_uuid_file : $! " . __FILE__ . ":" . __LINE__ );
          }
        }
        if ( $uuid_ldom eq "" ) {next}    # if zone not have uuid (solaris10 for example)
        my $zone = $zone_name;
        $zone_name = "$uuid_ldom" . "_" . "$zone_name";
        my @last_uuid_ldoms = $uuid_ldom;
        if ($zone_name) { $data_in{SOLARIS}{$zone_name}{label}   = $zone; }
        if ($uuid_ldom) { $data_in{SOLARIS}{$zone_name}{parents} = \@last_uuid_ldoms; }
        undef %data_out;
        if ( exists $data_in{SOLARIS}{$zone_name}{label} )   { $data_out{$zone_name}{label}   = $data_in{SOLARIS}{$zone_name}{label}; }
        if ( exists $data_in{SOLARIS}{$zone_name}{parents} ) { $data_out{$zone_name}{parents} = $data_in{SOLARIS}{$zone_name}{parents}; }
        my $params_zone = { id => $object_id, subsys => $subsys, data => \%data_out };

        #print Dumper $params_zone;
        SQLiteDataWrapper::subsys2db($params_zone);
        print "ZONE    found:            $zone_name(parrent_uuid-$uuid_ldom)\n";
      }
    }
  }    # does not exists uuid.txt
}

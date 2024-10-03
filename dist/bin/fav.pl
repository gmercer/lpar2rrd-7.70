# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

use strict;
use File::Path;

# set unbuffered stdout
$| = 1;

# get cmd line params
my $version = "$ENV{version}";
my $webdir  = $ENV{WEBDIR};
my $bindir  = $ENV{BINDIR};
my $basedir = $ENV{INPUTDIR};
my $tmpdir  = "$basedir/tmp";
if ( defined $ENV{TMPDIR_LPAR} ) {
  $tmpdir = $ENV{TMPDIR_LPAR};
}
my $DEBUG      = $ENV{DEBUG};
my $upgrade    = $ENV{UPGRADE};
my $new_change = "$tmpdir/$version-run";

my $wrkdir = "$basedir/data";

print "LPAR2RRD favourites \n" if $DEBUG;

my $act_time_txt = localtime();
my $act_time     = time();

if ( !-d "$webdir" ) {
  die "fav.pl:$act_time_txt: Pls set correct path to Web server pages, it does not exist here: $webdir\n";
}

# temp
my @fav_name = "";

# defining global variables
my @cfg_list = "";

my $ret = cfg_load($basedir);
if ( $ret == 0 ) {

  # no favs are configurd, exiting
  print "No favourites are configured\n";
}

clean_fav();    # delete unused favourites

exit(0);

sub cfg_load {
  my $basedir  = shift;
  my $cfg      = "$basedir/etc/favourites.cfg";
  my $fav_indx = 0;
  my $hmc      = "";

  if ( !-f $cfg ) {

    # cfg does not exist
    error("favour : favourites cfg files does not exist: $cfg");
    exit 1;
  }

  if ( !-d "$webdir/favourites" ) {
    print "mkdir          : $webdir/favourites\n" if $DEBUG;
    mkdir( "$webdir/favourites", 0755 ) || die "$act_time: Cannot mkdir $webdir/favourites: $!";
  }

  open( FHR, "< $cfg" );

  foreach my $line (<FHR>) {
    chomp($line);
    $line =~ s/\\:/===========doublecoma=========/g;    # workround for lpars/pool/groups with double coma inside the name
    $line =~ s/ *$//g;                                  # delete spaces at the end
    if ( $line =~ m/^$/ || ( $line !~ m/^POOL/ && $line !~ m/^LPAR/ ) || $line =~ m/^#/ || $line !~ m/:/ || $line =~ m/:$/ || $line =~ m/: *$/ ) {
      next;
    }

    #print "99 $line\n";
    # --> list of favourites here
    ( my $type, my $server, my $name, my $fav_act ) = split( /:/, $line );
    if ( $fav_act eq '' ) {
      next;
    }
    if ( $type eq '' || $server eq '' || $name eq '' ) {
      error("favour : syntax issue in $cfg: $line");
      next;
    }
    $server  =~ s/===========doublecoma=========/:/g;
    $name    =~ s/===========doublecoma=========/:/g;
    $name    =~ s/\//\&\&1/g;
    $fav_act =~ s/===========doublecoma=========/:/g;

    $hmc = "";

    # get the latest used HMC
    my $host_allp    = "";
    my $atime        = 0;
    my $server_space = $server;
    if ( $server =~ m/ / ) {    # workaround for server name with a space inside, nothing else works, grrr
      $server_space = "\"" . $server . "\"";
    }

    foreach my $line_host (<$wrkdir/$server_space/*/in-m>) {
      chomp($line_host);
      my $atime_act = ( stat("$line_host") )[9];
      if ( $atime_act > $atime ) {
        $host_allp = $line_host;
        $host_allp =~ s/\/in-m$//;
        $atime = $atime_act;
      }
    }

    if ( $atime == 0 ) {
      print "favourite err  : could not found HMC for server: $server\n";
      error("favour : could not found HMC for server: $server");
      next;
    }

    # basename without direct function
    my @base = split( /\//, $host_allp );
    foreach my $m (@base) {
      $hmc = $m;
    }

    # lpars aggregated translation
    if ( $type =~ m/LPAR/ ) {
      if ( $name =~ m/^lpars_aggregated$/ ) {
        $name = "pool-multi";
      }
    }

    # pool translation
    if ( $type =~ m/POOL/ ) {
      if ( $name =~ m/all_pools/ ) {
        $name = "pool";
      }
      else {
        # open pool mapping file
        open( FHP, "< $wrkdir/$server/$hmc/cpu-pools-mapping.txt" );
        my @map = <FHP>;
        close(FHP);

        my $found = 0;
        foreach my $line (@map) {
          chomp($line);
          if ( $line !~ m/^[0-9].*,/ ) {

            #something wrong , ignoring
            next;
          }
          ( my $pool_indx_new, my $pool_name_new ) = split( /,/, $line );
          if ( $pool_name_new =~ m/^$name$/ ) {
            $name = "SharedPool$pool_indx_new";
            $found++;
            last;
          }
        }
        if ( $found == 0 ) {
          print "favourite err  :  could not found name for shared pool : $server:$name\n";
          error("favour : could not found name for shared pool : $server:$name");
          next;
        }
      }
    }

    if ( $hmc eq '' ) {
      print "favourite err  : could not find the HMC for server $server\n";
      error("favour : could not find the HMC for server $server");
      next;
    }
  }
  close(FHR);

  return $fav_indx;
}

sub clean_fav {

  # cleaning out favourites (delete those which are not being used)
  foreach my $fav_old (<$webdir/favourites/*>) {
    if ( -d "$fav_old" ) {
      my $fav_old_base = "";
      my @link_l       = split( /\//, $fav_old );
      foreach my $m (@link_l) {
        $fav_old_base = $m;
      }
      my $found = 0;
      foreach my $fav_act (@fav_name) {
        if ( $fav_act =~ m/^$fav_old_base$/ ) {
          $found = 1;
          last;
        }
      }
      if ( $found == 0 ) {

        # delete old unsed one
        print "favourite del  : $fav_old \n" if $DEBUG;
        rmtree("$fav_old");
      }
    }
  }

  return 0;
}

# error handling
sub error {
  my $text     = shift;
  my $act_time = localtime();
  chomp($text);

  print "ERROR          : $text : $!\n";
  print STDERR "$act_time: $text : $!\n";

  return 1;
}


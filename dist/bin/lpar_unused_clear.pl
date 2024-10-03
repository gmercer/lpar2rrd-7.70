use strict;
use warnings;
use POSIX;
use Time::Local;
use Getopt::Std;

defined $ENV{INPUTDIR} || error( " Not defined INPUTDIR, probably not read etc/lpar2rrd.cfg " . __FILE__ . ":" . __LINE__ ) && exit 1;
my $basedir              = $ENV{INPUTDIR};
my $actual_unix_time     = time;
my $last_ten_days        = 10 * 86400;                            ### ten days back
my $actual_last_ten_days = $actual_unix_time - $last_ten_days;    ### ten days back with actual unix time-

my $active_days = 30;
if ( defined $ENV{VMWARE_ACTIVE_DAYS} && $ENV{VMWARE_ACTIVE_DAYS} > 1 && $ENV{VMWARE_ACTIVE_DAYS} < 3650 ) {
  $active_days = $ENV{VMWARE_ACTIVE_DAYS};
}
my $last_30_days        = $active_days * 86400;                   ### 30 days back
my $actual_last_30_days = $actual_unix_time - $last_30_days;      ### 30 days back with actual unix time-
my $wrkdir              = "$basedir/data";

opendir( DIR, "$wrkdir" ) || error( " directory does not exists : $wrkdir " . __FILE__ . ":" . __LINE__ ) && exit 1;
my @wrkdir_all = grep !/^\.\.?$/, readdir(DIR);
closedir(DIR);

print "#######################################\n";
print "This script used to remove unused lpar \n";
print "#######################################\n";
getopts('f');

our $opt_f;

if ($opt_f) {
  my $i = 0;
  foreach my $server_all (@wrkdir_all) {
    $server_all = "$wrkdir/$server_all";
    my $server = basename($server_all);
    if ( $server =~ /[vV][mM][wW][aA][rR][eE]/ ) { next; }
    if ( -l $server_all )                        { next; }
    if ( -f "$server_all" )                      { next; }
    if ( $server_all =~ /--HMC--/ )              { next; }
    if ( $server_all =~ /--unknown$/ )           { next; }
    chomp $server_all;
    chomp $server;
    opendir( DIR, "$wrkdir/$server" ) || error( "can't opendir $wrkdir/$server: $! :" . __FILE__ . ":" . __LINE__ ) && next;
    my @hmcdir_all = grep !/^\.\.?$/, readdir(DIR);
    closedir(DIR);

    foreach my $hmc_all_base (@hmcdir_all) {
      my $hmc_all = "$wrkdir/$server/$hmc_all_base";
      my $hmc     = basename($hmc_all);
      opendir( DIR, "$wrkdir/$server/$hmc" ) || error( "can't opendir $wrkdir/$server/$hmc: $! :" . __FILE__ . ":" . __LINE__ ) && next;
      my @lpardir_all = grep !/^\.\.?$/, readdir(DIR);
      closedir(DIR);
      foreach my $lpar_all (@lpardir_all) {
        if ( $lpar_all =~ /vmware\.txt/ ) { next; }
        my $cpu_cfg      = "$wrkdir/$server/$hmc/cpu.cfg";
        my @lines_config = "";
        if ( -f $cpu_cfg ) {
          open( FH, "< $cpu_cfg" ) || error( "Cannot read $cpu_cfg: $!" . __FILE__ . ":" . __LINE__ ) && next;
          @lines_config = <FH>;
          close(FH);
        }

        #print "$server/$hmc/$lpar_all\n";
        if ( $lpar_all =~ /\.rrm$/ ) {
          if ( $lpar_all =~ /SharedPool\d|pool\.rrm|mem\.rrm/ ) { next; }
          my $lpar = $lpar_all;
          $lpar =~ s/\.rrm$//g;
          $lpar =~ s/&&1/\//g;
          my ($lpar_find) = grep /lpar_name=$lpar,lpar_id/, @lines_config;
          if ($lpar_find) {

            #print "find in $server/cpu.cfg,$lpar\n";
          }
          else {
            $i++;
            my $server_space = $server;
            if ( $server =~ m/ / ) {
              $server_space = "\"" . $server . "\"";    # it must be here to support space with server names
            }
            my $lpar_space = $lpar;
            if ( $lpar =~ m/ / ) {
              $lpar_space = "\"" . $lpar . "\"";        # it must be here to support space with server names
            }
            my @files = <$wrkdir/$server_space/$hmc/$lpar_space.r*>;
            print "Deleting: $wrkdir/$server/$hmc/$lpar\n";
            foreach my $file (@files) {
              print "Deleting: $file\n";
              unlink $file or warn "Problem unlinking $file: $!";
            }
          }
        }
      }
    }
  }
  if ( $i == 0 ) { print "\nNone lpars to delete...\n"; }
}

if ( not defined $opt_f ) {
  print "Script removes all LPARs which are in the GUI under \"Removed\" item\n";
  print "It prompts you before any deletion\n";
  print "When you do not want to be prompted - CTRL+C(end script) and start script with paramether -f\n";
  print "!!! Be careful when you use enterprise edition and use LPM, it might delete you r LPAR LPM history\n";
  print "Type enter to continue\n";

  my $key_y = <STDIN>;
  if ( $key_y eq "\n" ) {
    my $i = 0;
    foreach my $server_all (@wrkdir_all) {
      $server_all = "$wrkdir/$server_all";
      my $server = basename($server_all);
      if ( $server =~ /[vV][mM][wW][aA][rR][eE]/ ) { next; }
      if ( -l $server_all )                        { next; }
      if ( -f "$server_all" )                      { next; }
      if ( $server_all =~ /--HMC--/ )              { next; }
      if ( $server_all =~ /--unknown$/ )           { next; }
      chomp $server_all;
      chomp $server;
      opendir( DIR, "$wrkdir/$server" ) || error( "can't opendir $wrkdir/$server: $! :" . __FILE__ . ":" . __LINE__ ) && next;
      my @hmcdir_all = grep !/^\.\.?$/, readdir(DIR);
      closedir(DIR);

      foreach my $hmc_all_base (@hmcdir_all) {
        my $hmc_all = "$wrkdir/$server/$hmc_all_base";
        my $hmc     = basename($hmc_all);
        opendir( DIR, "$wrkdir/$server/$hmc" ) || error( "can't opendir $wrkdir/$server/$hmc: $! :" . __FILE__ . ":" . __LINE__ ) && next;
        my @lpardir_all = grep !/^\.\.?$/, readdir(DIR);
        closedir(DIR);
        foreach my $lpar_all (@lpardir_all) {
          if ( $lpar_all =~ /vmware\.txt/ ) { next; }
          my $cpu_cfg      = "$wrkdir/$server/$hmc/cpu.cfg";
          my @lines_config = "";
          if ( -f $cpu_cfg ) {
            open( FH, "< $cpu_cfg" ) || error( "Cannot read $cpu_cfg: $!" . __FILE__ . ":" . __LINE__ ) && next;
            @lines_config = <FH>;
            close(FH);
          }

          #print "$server/$hmc/$lpar_all\n";
          if ( $lpar_all =~ /\.rrm$/ ) {
            if ( $lpar_all =~ /SharedPool\d|pool\.rrm|mem\.rrm/ ) { next; }
            my $lpar = $lpar_all;
            $lpar =~ s/\.rrm$//g;
            $lpar =~ s/&&1/\//g;
            my ($lpar_find) = grep /lpar_name=$lpar,lpar_id/, @lines_config;
            if ($lpar_find) {

              #print "find in $server/cpu.cfg,$lpar\n";
            }
            else {
              $i++;
              print "$server:$hmc:$lpar : to delete it press the enter or n/N for skip it.\n";
              my $key_d = <STDIN>;
              if ( $key_d eq "\n" ) {
                my $server_space = $server;
                if ( $server =~ m/ / ) {
                  $server_space = "\"" . $server . "\"";    # it must be here to support space with server names
                }
                my $lpar_space = $lpar;
                if ( $lpar =~ m/ / ) {
                  $lpar_space = "\"" . $lpar . "\"";        # it must be here to support space with server names
                }
                my @files = <$wrkdir/$server_space/$hmc/$lpar_space.r*>;
                print "Deleting: $wrkdir/$server/$hmc/$lpar\n";
                foreach my $file (@files) {

                  #print "Deleting: $file\n";
                  unlink $file or warn "Problem unlinking $file: $!";
                }
              }
              else { next; }
            }
          }
        }
      }
    }
    if ( $i == 0 ) { print "\nNone lpars to delete...\n"; }
  }
}

print "\nRun \"./load.sh html\" and Ctrl-F5 in the GUI then\n";

sub basename {
  return ( split "\/", $_[0] )[-1];
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

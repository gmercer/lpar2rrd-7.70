
use strict;
use warnings;

my $start_time = localtime( time() );

#create hash
my %vmware = ();
my @vmotion;
defined $ENV{INPUTDIR} || error( "Not defined INPUTDIR, probably not read etc/lpar2rrd.cfg " . __FILE__ . ":" . __LINE__ ) && exit 1;
my $basedir = $ENV{INPUTDIR};
my $wrkdir  = "$basedir/data";
my $tmpdir  = "$basedir/tmp";
if ( defined $ENV{TMPDIR_LPAR} ) {
  $tmpdir = $ENV{TMPDIR_LPAR};
}

#print "$basedir\n";
#print "$wrkdir\n";

# it can be run from cmd:
# . etc/lpar2rrd.cfg; perl bin/lpar_start_counter.pl

# prepare active VMs from menu_vmware
my @menu = ();
read_menu_vmware( \@menu );
my @lpar_only = grep {/^L:/} @menu;

foreach my $vm (@lpar_only) {

  # L:cluster_New Cluster:10.22.11.8:500f7363-b0f9-559e-0f1e-3970d5c3bb0d:RedHat-dev-DC:/lpar2rrd-cgi/detail.sh?host=10.22.11.10&server=10.22.11.8&lpar=500f7363-b0f9-559e-0f1e-3970d5c3bb0d&item=lpar&entitle=0&gui=1&none=none::Hosting:V:::
  ( undef, undef, undef, my $vm_id, my $vm_name, my $ahref, undef, my $vcenter_name, undef ) = split( /:/, $vm );

  # print "# 46 \$ahref ,$ahref,\n";
  $vmware{$vm_id}{name}    = $vm_name;
  $vmware{$vm_id}{ahref}   = $ahref;
  $vmware{$vm_id}{vcenter} = $vcenter_name;
}

#open dir & find file in subdir
my $dirname = "$wrkdir";

opendir( DIR, $dirname ) or error("Error in opening dir $dirname : $!") and exit 1;
my @data = readdir(DIR);
closedir(DIR);

my $unix_time_now   = time();
my $unix_time_day   = $unix_time_now - 86400;
my $unix_time_week  = $unix_time_now - 86400 * 7;
my $unix_time_month = $unix_time_now - 86400 * 30;

foreach my $server_name (@data) {
  next if ( $server_name eq "." or $server_name eq ".." or $server_name eq "vmware_VMs" );

  #print "$item_1";
  my $server_pass = "$dirname/$server_name";
  next if not( -d $server_pass );
  next if -l $server_pass;          # strange that above line lets links as dirs ??!!
                                    # print "56 analyse $server_pass\n";
  opendir( SRV, $server_pass ) or error("Error in opening dir $server_pass : $!") and next;
  my @srvr = readdir(SRV);
  closedir(SRV);

  foreach my $hmc_name (@srvr) {
    next if ( $hmc_name eq "." or $hmc_name eq ".." );
    my $hmc_pass = "$dirname/$server_name/$hmc_name";
    if ( !-f "$hmc_pass/vmware.txt" ) {

      # print "not vmware dir $hmc_pass\n";
      next;
    }
    next if not( -d $hmc_pass );
    opendir( HMC, $hmc_pass ) or error("Error in opening dir $hmc_pass : $!") and next;
    my @hmc_2 = readdir(HMC);
    closedir(HMC);
    foreach my $file_name (@hmc_2) {
      next if ( $file_name eq "." or $file_name eq ".." );
      next if ( $file_name ne "VM_hosting.vmh" );

      #file find
      my $lpar_config = "$hmc_pass/$file_name";
      my @lpar;
      if ( -f $lpar_config ) {
        open( FC, "< $lpar_config" ) || error( "Cannot read $lpar_config: $! " . __FILE__ . ":" . __LINE__ );
        @lpar = <FC>;
        close(FC);
      }

      #split data & save to hash
      #501cff67-818b-f73c-6777-20e830c3e044:start=1501594982:end=1501596182:start=1509723782
      #501c1a53-cf7d-07cb-88e4-cf94ca6c5b0e:start=1501596182:end=1501632182:start=1502276582:end=1502292182:start=1502342582:end=1502343782

      foreach my $line (@lpar) {
        chomp $line;
        ( my $id, my @start ) = split( /:/, $line );
        next if ( !exists $vmware{$id} );    # for active VM only

        my $count_day   = 0;
        my $count_week  = 0;
        my $count_month = 0;

        my $count = grep( /start=/, @start );
        foreach my $atom (@start) {
          next if $atom !~ "start=";
          ( undef, my $start_time ) = split( "=", $atom );
          if ( $start_time > $unix_time_day ) {
            $count_day++;
            next;
          }
          if ( $start_time > $unix_time_week ) {
            $count_week++;
            next;
          }
          if ( $start_time > $unix_time_month ) {
            $count_month++;
            next;
          }
        }

        # my $name = $vmware{$id};
        if ( exists $vmware{$id}{count} ) {

          # it is necessary to prepare sum of all counts
          $count       += ( split( ";", $vmware{$id}{count} ) )[0];
          $count_day   += ( split( ";", $vmware{$id}{count} ) )[1];
          $count_week  += ( split( ";", $vmware{$id}{count} ) )[2];
          $count_month += ( split( ";", $vmware{$id}{count} ) )[3];
          $vmware{$id}{count} = "$count;$count_day;$count_week;$count_month";
        }
        else {
          $vmware{$id}{count} = "$count;$count_day;$count_week;$count_month";
        }
      }
    }
  }
}

#print lpar

print "# lpar_start_counter.pl started at $start_time\n";

foreach my $id ( keys %vmware ) {
  print "$vmware{$id}{vcenter};$vmware{$id}{name};$vmware{$id}{ahref};$vmware{$id}{count}\n";
}
my $end_time = localtime( time() );
print "# lpar_start_counter.pl finished at $end_time\n";

sub error {
  my $text     = shift;
  my $act_time = localtime();
  chomp($text);
  print STDERR "$act_time:lpar_start_counter.pl: $text \n";
}

# read tmp/menu.txt
sub read_menu_vmware {
  my $menu_ref = shift;
  open( FF, "<$tmpdir/menu_vmware.txt" ) || error( "can't open $tmpdir!menu.txt: $! :" . __FILE__ . ":" . __LINE__ ) && return 0;
  @$menu_ref = (<FF>);
  close(FF);
  return;
}


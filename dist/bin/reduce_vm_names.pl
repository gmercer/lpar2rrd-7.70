use strict;
use warnings;

# run it from cmd line
# . etc/lpar2rrd.cfg; $PERL bin/reduce_vm_names_new.pl

my $basedir = $ENV{INPUTDIR};
my $wrkdir  = $basedir . "/data";

# go through file and reduce if there are same UUID lines
# data/vmware_VMs/vm_uuid_name.txt
# necessary to test if the vms_file is not changed during run as it is possible on proxy side

my $vms_file               = "$basedir/data/vmware_VMs/vm_uuid_name.txt";
my $last_mod_time_vms_file = ( stat($vms_file) )[9];

print "reducing       : vm names : start " . localtime() . "\n";
my $file_count        = 0;
my @vm_uuid_names_arr = ();

# read
my $lines_read    = 0;
my $lines_writ    = 0;
my %vm_uuid_names = ();
if ( -f "$vms_file" ) {
  open FH, "$vms_file" or error( "can't open $vms_file: $!" . __FILE__ . ":" . __LINE__ ) && exit 0;
  binmode( FH, ":utf8" );
  while ( my $line = <FH> ) {
    chomp $line;
    ( my $word1, my $word2 ) = split /,/, $line, 2;

    # if there are two lines with same uuid, here keeps the one appended later
    $vm_uuid_names{$word1} = $word2;
    $lines_read++;
  }
  close FH;

  # transform hash arr to normal arr for easy grep
  while ( ( my $k, my $v ) = each %vm_uuid_names ) {
    push @vm_uuid_names_arr, "$k" . "," . "$v";
  }

  # find all Linux/no_hmc/*/uuid.txt & append the dir (*) name at the end of line
  my @all_uuid_files = `ls $wrkdir/Linux/no_hmc/*/uuid.txt 2>/dev/null`;
  my $uuid;
  my %uuids = ();

  foreach my $file (@all_uuid_files) {
    chomp $file;
    my $cpu_file = $file;
    $cpu_file =~ s/uuid.txt$/cpu.mmm/;
    next if !-f $cpu_file;    # dir without this file is not interesting
    open( FH, " < $file" ) || error( "Cannot open $file: $!" . __FILE__ . ":" . __LINE__ ) && next;
    $uuid = <FH>;
    close FH;
    ( !defined $uuid || $uuid eq "" ) && error( "Empty UUID file $file " . __FILE__ . ":" . __LINE__ ) && next;
    chomp $uuid;

    # e.g. D2051C42-C469-27DA-3FF6-6E508678C004
    # test if this UUID already exists
    if ( exists $uuids{$uuid} ) {
      print "61             :this \$uuid $uuid in $file already exists in $uuids{$uuid}\n";

      # choose the newer one
      my $cpu_previous_file = $uuids{$uuid};
      $cpu_previous_file =~ s/uuid.txt$/cpu.mmm/;
      my $cpu_previous_file_time = -M $cpu_previous_file;
      my $cpu_file_time          = -M $cpu_file;
      print "65             :\$cpu_previous_file_time $cpu_previous_file_time \$cpu_file_time $cpu_file_time\n";

      # $cpu_previous_file_time 0.00979166666666667 $cpu_file_time 1526.84039351852
      next if $cpu_previous_file_time <= $cpu_file_time;
      $uuids{$uuid} = $file;
    }
    else {
      $uuids{$uuid} = $file;
    }
  }

  while ( my ( $uuid_key, $file ) = each(%uuids) ) {

    my @uuid_atoms = split( "-", $uuid_key );
    next if ( !defined $uuid_atoms[3] || !defined $uuid_atoms[4] );
    my $pattern = "-$uuid_atoms[3]-$uuid_atoms[4]";
    $pattern = lc $pattern;

    # print STDERR "44 $pattern $uuid\n";

    # get proper VM line from vm_uuid_names_arr according to Uuid
    my @matches = grep {/$pattern/} @vm_uuid_names_arr;
    next if ( !defined $matches[0] );

    # will you test  or scalar @matches > 1 ?
    my $more_matches = scalar @matches;
    print "$more_matches more matches @matches for \$pattern $pattern in vm_uuid_names\n" if $more_matches > 1;
    chomp $matches[0];
    ( my $inst_uuid, my $lpar_name, my $lpar_name_url, my $uuid_old, my $agent_name ) = split( ",", $matches[0] );

    # print STDERR "56 found right uuid.txt $file\n";
    my $lpar_name_agent_found = ( split( /\//, $file ) )[-2];
    if ( !defined $agent_name || $lpar_name_agent_found ne $agent_name ) {    # new or changed name
      push @vm_uuid_names_arr, "$inst_uuid,$lpar_name,$lpar_name_url,$uuid_old,$lpar_name_agent_found";
      print "               : new pushed line $inst_uuid,$lpar_name,$lpar_name_url,$uuid_old,$lpar_name_agent_found\n";
    }
  }

  # exit; # good for debug

  # transform normal arr to hash

  %vm_uuid_names = ();
  foreach my $line (@vm_uuid_names_arr) {
    chomp $line;
    ( my $word1, my $word2 ) = split /,/, $line, 2;

    # if there are two lines with same uuid, here keeps the one appended later
    $vm_uuid_names{$word1} = $word2;
  }

  # write hash
  if ( -f "$vms_file" ) {
    if ( $last_mod_time_vms_file eq ( stat($vms_file) )[9] ) {
      open FH, ">$vms_file" or error( "can't open $vms_file: $!" . __FILE__ . ":" . __LINE__ ) && exit 0;
      binmode( FH, ":utf8" );
      my ( $k, $v );

      # Append key/value pairs from %vm_uuid_names to file, joined by ','
      while ( ( $k, $v ) = each %vm_uuid_names ) {
        print FH "$k" . "," . "$v\n";
        $lines_writ++;
      }
      close FH;
    }
    else {
      print "reducing       : file $vms_file has been changed during run, so it has not been reduced\n";
    }
  }

  print "reducing       : vm names : stop " . localtime() . " lines read:$lines_read, lines written:$lines_writ\n";

}
exit;

# error handling
sub error {
  my $text     = shift;
  my $act_time = localtime();
  chomp($text);

  print "ERROR          : $text : $!\n";
  print STDERR "$act_time: $text : $!\n";

  return 1;
}

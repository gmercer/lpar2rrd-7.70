use strict;
use warnings;

use JSON;
use Data::Dumper;

#print as JSON

#          {
#          "str" : "DataCenter1 dc-data rhel7_Disk1",
#          "href" : "/lpar2rrd-cgi/detail.sh?platform=oVirt&type=disk&id=a1d76e01-f4d1-4d73-a879-d8dbbc43934d",
#          "title" : "rhel7_Disk1"
#          }
my @power_children;
my %pep_information;

#my $datadir = "/home/lpar2rrd/lpar2rrd/data";
my $lpar2rrd_dir = $ENV{"INPUTDIR"} || Xorux_lib::error("INPUTDIR is not defined")     && exit;
my $datadir = "${lpar2rrd_dir}/data";

my $consoles_info_file = "$datadir/PEP2/console_section_id_name.json";

if ( -f "$consoles_info_file") {
  %pep_information = %{decode_json(file_to_string("$consoles_info_file"))};
}else{
  print "FILE $consoles_info_file does not exist.";
  exit;
}

sub file_to_string{
  my $filename = shift;
  my $json;
  open(FH, '<', $filename) or die $!;
  while(<FH>){
     $json .= $_;
  }
  #print "$filename \n";
  #print Dumper %{decode_json($json)};
  close(FH);
  return $json;
}

# GENERATE MENU
# 
#   |CMC
#     |Overview
#       |TABLE: HMC|Server|Tag|Pool
#     |*power_cmc_name
#       |Systems
#         |Overview
#         |*System
#           |CPU
#           |Memory 
#       |Partitions
#         |Overview
#         |*Partition
#           |CPU
#           |Memory
#       |Pools
#         |*PoolName
#           |Credits
#           |Coreminutes
#           |MemoryMinutes
my %strs = ();
my $platform = "PowerCMC";

my %general_overview;
$general_overview{"str"} = "Overview";
$general_overview{"title"} = "Overview";
$general_overview{"href"} = "/lpar2rrd-cgi/detail.sh?platform=${platform}&type=pep2_overview";

push(@power_children, \%general_overview);

# TOTAL OVERVIEW
my @cmc_names = keys %pep_information;

my %cmc_total;
if (scalar(@cmc_names)){
  $cmc_total{"str"} = "Total";
  $cmc_total{"title"} = "Total";
  $cmc_total{"href"} = "/lpar2rrd-cgi/detail.sh?platform=${platform}&type=pep2_all";
  #$cmc_total{"href"} .= "&console=${cmc_name}";
    
  push(@power_children, \%cmc_total);
}
#my %tags;
#$tags{"str"} = "Tags";
#$tags{"title"} = "Tags";
#$tags{"href"} = "/lpar2rrd-cgi/detail.sh?platform=${platform}&type=pep2_tags";
#
#push(@power_children, \%tags);


my @sorted_cmc_names = sort {lc($pep_information{$a}{Alias}) cmp lc($pep_information{$b}{Alias})} @cmc_names;

for my $cmc_name (@sorted_cmc_names){
  
  my %cmc = ();
  my @cmc_children;
  # OVERVIEW
  my %cmc_overview;
  $cmc_overview{"str"} = "Configuration";
  $cmc_overview{"title"} = "Configuration";
  $cmc_overview{"href"} = "/lpar2rrd-cgi/detail.sh?platform=${platform}&type=pep2_cmc_overview";
  #$cmc_overview{"href"} .= "&console=${cmc_name}";
  $cmc_overview{"href"} .= "&id=____${cmc_name}";
  
  push(@cmc_children, \%cmc_overview);

  ## HMCs
  #my $current_group = "HMCs";
  #if (defined $pep_information{$cmc_name}{$current_group}){
  #my %cmc_child_hmc = ();

  #my @hmc_children;
  #for my $uuid (keys %{$pep_information{$cmc_name}{$current_group}}){

  #  my %hmc = ();

  #  my $hmc_name  = $pep_information{$cmc_name}{$current_group}{$uuid}{Name};
  #  $hmc_name  = $pep_information{$cmc_name}{$current_group}{$uuid}{Configuration}{host};
  #  my $hmc_title = $pep_information{$cmc_name}{$current_group}{$uuid}{Name};
  #  $hmc_title  = $pep_information{$cmc_name}{$current_group}{$uuid}{Configuration}{host};
  #  my $hmc_href  = "/lpar2rrd-cgi/detail.sh?platform=${platform}&type=pep2_hmc&id=$uuid";

  #  $hmc{"str"} = $hmc_name;
  #  $hmc{"title"} = $hmc_title;
  #  $hmc{"href"} = $hmc_href;
  #  $hmc{"href"} .= "&console=${cmc_name}";

  #  push(@hmc_children, \%hmc);

  #}

  #$cmc_child_hmc{"str"} = "HMC Totals";
  #$cmc_child_hmc{"title"} = "HMC Totals";
  #$cmc_child_hmc{"folder"} = "true";
  #$cmc_child_hmc{"children"} = \@hmc_children;
  #push(@cmc_children, \%cmc_child_hmc);
  #}

  # POOL 
  my %cmc_child_pool;
  
  %cmc_child_pool = ();
  #$cmc_child_pool{"str"} = "PEP 2.0";
  #$cmc_child_pool{"title"} = "PEP 2.0";
  $cmc_child_pool{"str"} = "Pool";
  $cmc_child_pool{"title"} = "Pool";
  $cmc_child_pool{"folder"} = "true";
  
  my @pool_children;
  my @pool_ids = keys %{$pep_information{$cmc_name}{Pools}};

  my @sorted_pool_ids = sort {lc($pep_information{$cmc_name}{Pools}{$a}{Name}) cmp lc($pep_information{$cmc_name}{Pools}{$b}{Name})} @pool_ids;
  for my $pool_id (@sorted_pool_ids){

    my %pool = ();
    
    my $pool_name  = $pep_information{$cmc_name}{Pools}{$pool_id}{Name};
    my $pool_title = $pep_information{$cmc_name}{Pools}{$pool_id}{Name};
    my $pool_href  = "/lpar2rrd-cgi/detail.sh?platform=${platform}&type=pep2_pool&id=$pool_id";

    $pool{"str"} = $pool_name;
    $pool{"title"} = $pool_title;
    $pool{"href"} = $pool_href;
    #$pool{"href"} .= "&console=${cmc_name}";
    $pool{"href"} .= "____${cmc_name}";
 
    push(@pool_children, \%pool);

  }
  $cmc_child_pool{"children"} = \@pool_children;
  push(@cmc_children, \%cmc_child_pool);

  # SYSTEM
  my %cmc_child_sys = ();
  
  my @sys_children;
  my @server_uuids = keys %{$pep_information{$cmc_name}{Systems}};

  my @sorted_server_uuids = sort {lc($pep_information{$cmc_name}{Systems}{$a}{Name}) cmp lc($pep_information{$cmc_name}{Systems}{$b}{Name})} @server_uuids;
  for my $uuid ( @sorted_server_uuids ){

    my %sys = ();
    
    my $sys_name  = $pep_information{$cmc_name}{Systems}{$uuid}{Name};
    my $sys_title = $pep_information{$cmc_name}{Systems}{$uuid}{Name};
    my $sys_href  = "/lpar2rrd-cgi/detail.sh?platform=${platform}&type=pep2_system&id=$uuid";

    $sys{"str"} = $sys_name;
    $sys{"title"} = $sys_title;
    $sys{"href"} = $sys_href;
    #$sys{"href"} .= "&console=${cmc_name}";
    $sys{"href"} .= "____${cmc_name}";
 
    push(@sys_children, \%sys);

  }
  
  $cmc_child_sys{"str"} = "Server";
  $cmc_child_sys{"title"} = "Server";
  $cmc_child_sys{"folder"} = "true";
  $cmc_child_sys{"children"} = \@sys_children;
  push(@cmc_children, \%cmc_child_sys);

  ## PARTITIONS
  #if (defined $pep_information{$cmc_name}{Partitions}){
  #my %cmc_child_partition = ();

  #my @partition_children;
  #for my $uuid (keys %{$pep_information{$cmc_name}{Partitions}}){

  #  my %partition = ();

  #  my $partition_name  = $pep_information{$cmc_name}{Partitions}{$uuid}{Name};
  #  my $partition_title = $pep_information{$cmc_name}{Partitions}{$uuid}{Name};
  #  my $partition_href  = "/lpar2rrd-cgi/detail.sh?platform=${platform}&type=pep2_partition&id=$uuid";

  #  $partition{"str"} = $partition_name;
  #  $partition{"title"} = $partition_title;
  #  $partition{"href"} = $partition_href;
  #  $partition{"href"} .= "&console=${cmc_name}";

  #  push(@partition_children, \%partition);

  #}

  #$cmc_child_partition{"str"} = "Partitions";
  #$cmc_child_partition{"title"} = "Partitions";
  #$cmc_child_partition{"folder"} = "true";
  #$cmc_child_partition{"children"} = \@partition_children;
  #push(@cmc_children, \%cmc_child_partition);
  #}


  # Pools, Systems -> CMC

  #$cmc_name (keys %pep_information){
  $cmc{"str"} = "$pep_information{$cmc_name}{Alias}";
  $cmc{"title"} = "$pep_information{$cmc_name}{Alias}";
  $cmc{"folder"} = "true";
  $cmc{"children"} = \@cmc_children;

  push(@power_children, \%cmc);

}


my %power;
$power{"str"} = "CMC";
$power{"title"} = "CMC";
$power{"folder"} = "true";
$power{"children"} = \@power_children;

#$menu_tree->{children} = [ \%power ];


my $json      = JSON->new->utf8->pretty;
my $json_data = $json->encode(\%power);
print $json_data;



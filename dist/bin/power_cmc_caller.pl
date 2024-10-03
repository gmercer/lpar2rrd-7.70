use strict;
use warnings;
use Data::Dumper;
use JSON;
use Time::Local;
use FindBin;
use Xorux_lib;
use HostCfg;


my $lpar2rrd_dir;
$lpar2rrd_dir = $ENV{"INPUTDIR"} || Xorux_lib::error("INPUTDIR is not defined")     && exit;

my $datadir = "${lpar2rrd_dir}/data";
my $PEPdir = $datadir . "/PEP2";
my $consoles_file = $PEPdir . "/console_section_id_name.json";

sub dir_treat{
  my $dir_path = shift;
  if (! -d "$dir_path") {
    mkdir( "$dir_path", 0755 ) || Xorux_lib::error("Cannot mkdir $dir_path: $!") && exit;
  }
}

dir_treat($datadir);
dir_treat($PEPdir);
#system(. "${lpar2rrd_dir}/etc/lpar2rrd.cfg");


my ( $proxy_url, $protocol, $username, $password, $api_port, $host);

my %host_hash = %{HostCfg::getHostConnections("IBM Power CMC")};
#%host_hash = HostCfg::getHostConnections("IBM Power Systems");
#print Dumper HostCfg::getHostConnections("IBM Power CMC");
my @console_list = sort keys %host_hash;

print "Configured CMCs: \n";
for my $conf_alias (@console_list){
  print " $conf_alias\n";
}

# find hmc uuid match: CMC <-> configured HMCs
my %console_checker;
my %console_alias;
my $proxy_protocol;

for my $alias (keys %{host_hash}){
  my %subhash = %{$host_hash{$alias}};

  $host     = $subhash{host};
  $username = $subhash{username};
  $password = $subhash{password};

  $proxy_url = "";

  if ( defined $subhash{proxy_url} && $subhash{proxy_url} && defined $subhash{proto} && $subhash{proto} ) {
    $proxy_url = "$subhash{proto}".'://'."$subhash{proxy_url}";
  }
  print "PROXY: $proxy_url\n";    

  my $output = qx(perl ${lpar2rrd_dir}/bin/power_cmc.pl $host $username $password $proxy_url); 
  print $output;   
  
  $console_checker{$host} = 1;
  $console_alias{$host} = $alias;

}
# CHECK: Create menu only for active consoles

my %console_id_name = ();
if ( -f "$consoles_file") {
  %console_id_name = %{decode_json(file_to_string("$consoles_file"))};
  #print "\n CONSOLE ID NAME from $consoles_file\n";
  #print Dumper %console_id_name;
}

#print "\n CONSOLE CHECKER\n";
#print Dumper %console_checker;

for my $console_name (keys %console_id_name){
  if (! defined $console_checker{$console_name}){
    delete $console_id_name{$console_name};
  }else{
    $console_id_name{$console_name}{Alias} = $console_alias{$console_name}; 
  }
}

# PRINT CONFIGURATION JSON
print "\n\nCONSOLE DATA: \n";
my $json      = JSON->new->utf8->pretty;
my $json_data = $json->encode(\%console_id_name);

my $json_p      = JSON->new->utf8;
my $json_data_p = $json_p->encode(\%console_id_name);

print "$json_data_p \n";

qx(touch $consoles_file);
write_to_file($consoles_file, $json_data);

qx(perl ${lpar2rrd_dir}/bin/power_cmc_genmenu.pl > ${lpar2rrd_dir}/tmp/menu_powercmc.json);
use PowercmcDataWrapper;

my $power = PowercmcDataWrapper::power_configured();
if ( defined $ENV{XORMON} && $ENV{XORMON} ) {
  if ($power){
    my $out = qx(perl ${lpar2rrd_dir}/bin/cmc-json2db.pl);
    print " \n $out";
  }
}

exit 0;

sub file_to_string{
  my $filename = shift;
  my $json;
  #print "$filename \n";
  open(FH, '<', $filename) or die $!;
  while(<FH>){
     $json .= $_;
  }
  #print "$filename \n";
  #print Dumper \%{decode_json($json)};
  close(FH);
  return $json;
}

sub write_to_file{
  my $file_path = shift;
  my $data_to_write = shift;
  open(FH, '>', "$file_path") || Xorux_lib::error( " Can't open: $file_path : $!" . __FILE__ . ":" . __LINE__ ) && return 0;
  print FH $data_to_write;
  close(FH);
}


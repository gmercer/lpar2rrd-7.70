use 5.008_008;

use strict;
use warnings;

use Data::Dumper;
use JSON qw(decode_json encode_json);

use SQLiteDataWrapper;
use PowercmcDataWrapper;
use Xorux_lib;
use DatabasesWrapper;

defined $ENV{INPUTDIR} || warn('INPUTDIR undefined, probably have not read etc/lpar2rrd.cfg ') && exit 1;

if (! PowercmcDataWrapper::power_configured()){
  exit 0;
}

# data file paths
my $inputdir = $ENV{INPUTDIR};

my %data_in;
my %data_out;

my %console_section_id_name;  

my $consoles_file = "${inputdir}/data/PEP2/console_section_id_name.json";
if ( -f $consoles_file ){
  %console_section_id_name = PowercmcDataWrapper::console_structure("$inputdir/data");
}
else{
  %console_section_id_name = ();
}

#if (! -f "$inputdir/data/PEP2/console_section_id_name.json") {
#  warn "Console JSON not found.";
#  exit;
#}

my $object_hw_type = "POWER";
my $object_label   = "CMC";
my $object_id      = "POWER";

# SUBSYSTEMS:
# CMC CMCCONSOLE CMCPOOL CMCSERVER
my @subsystems = ( 'CMCCONSOLE', 'CMCPOOL', 'CMCSERVER');

# Do not delete CMC folder (subsystem CMC)
for my $cmc_subsystem (@subsystems){
  SQLiteDataWrapper::deleteItems({ hw_type => $object_hw_type, 'subsys' => $cmc_subsystem});
}
#exit 0;

my $params;

# CMC: FOLDER
%data_out = (
  'CMC' => {
    'label' => 'CMC',
    'parents' => [
    ]
  }
);

$params = { id => 'POWER', subsys => "CMC", data => \%data_out };

SQLiteDataWrapper::subsys2db($params);


# CONSOLE
for my $console (sort keys %console_section_id_name){
  my $alias = $console_section_id_name{$console}{Alias};

   # undef %data_out;
  %data_out = (
    "$console" => {
      'label' => "$alias",
      'parents' => [ 'CMC' ]
    }
  );
  $params = { id => 'POWER', subsys => "CMCCONSOLE", data => \%data_out };
  
  #print Dumper %data_out; 
  print "cmc-json2db.pl : ${console}:FOLDER:$alias\n";
  SQLiteDataWrapper::subsys2db($params);
}

# POOLS
for my $console (sort keys %console_section_id_name){
  for my $pool_id (sort keys %{$console_section_id_name{$console}{Pools}}){

    my $pool_name = $console_section_id_name{$console}{Pools}{$pool_id}{Name};

    %data_out = (
      "${pool_id}____$console" => {
        'label' => "$pool_name",
        'parents' => [ "$console" , 'CMC' ]
      }
    );
    $params = { id => 'POWER', subsys => "CMCPOOL", data => \%data_out };
    
    #print Dumper %data_out; 
    print "cmc-json2db.pl : ${console}:CMCPOOL:$pool_name\n";
    SQLiteDataWrapper::subsys2db($params);
  }
}

# SYSTEMS
for my $console (sort keys %console_section_id_name){
  for my $uuid (sort keys %{$console_section_id_name{$console}{Systems}}){

    my $server_name = $console_section_id_name{$console}{Systems}{$uuid}{Name};

    %data_out = (
      "${uuid}____$console" => {
        'label' => "$server_name",
        'parents' => [ "$console", 'CMC' ]
      }
    );
    $params = { id => 'POWER', subsys => "CMCSERVER", data => \%data_out };
    
    #print Dumper %data_out; 
    print "cmc-json2db.pl : ${console}:CMCSERVER:$server_name\n";
    SQLiteDataWrapper::subsys2db($params);
  }
}

exit 0;

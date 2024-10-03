package PowercmcDataWrapper;

use strict;
use warnings;

use Data::Dumper;
use Xorux_lib qw(error read_json);
use Digest::MD5 qw(md5 md5_hex md5_base64);
use JSON;
use HostCfg;

defined $ENV{INPUTDIR} || warn("INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ") && exit 1;

my $inputdir = $ENV{INPUTDIR};
my $home_dir = "$inputdir/data/PEP2";
my $tmpdir   = "$inputdir/tmp";
my $wrkdir = "$inputdir/data";

# Lists to return:
# consoles
# servers per all/console/hmc
# rrd
# menu
sub power_configured{
  my %host_hash = %{HostCfg::getHostConnections("IBM Power Systems")};
  my @console_list = sort keys %host_hash;

  if (scalar @console_list){
    return 1;
  }
  else{
    return 0;
  }
}
 
sub configured{
  my %host_hash = %{HostCfg::getHostConnections("IBM Power CMC")};
  my @console_list = sort keys %host_hash;

  if (scalar @console_list){
    return 1;
  }
  else{
    return 0;
  }
}
 
sub make_html_table{
    # @table_keys: list of table_KEYs to identify     
    # %table_header: PAIRS { table_KEY : header_name } 
    # @table_body: ARRAY OF HASHES WITH PAIRS { table_KEY : table_value }
    
    my $table_keys_ref    = shift;
    my $table_header_ref  = shift;
    my $table_body_ref    = shift;
    my $sort_by           = shift;
  
    my @table_keys   = @{$table_keys_ref};
    my %table_header = %{$table_header_ref};
    my @table_body   = @{$table_body_ref};

    my $table = "";
    
    $table .= ' <table class="tabconfig tablesorter powersrvcfg" data-sortby="'."$sort_by".'" >';
    
    # HEAD
    $table .= ' <thead>';
    $table .= '  <tr>';

    for my $table_key (@table_keys){
      $table .= qq(   <th align="left" class="sortable" valign="center">$table_header{$table_key}</th>);
    }

    $table .= '  </tr> ';
    $table .= ' </thead>';
    
    # BODY
    $table .= ' <tbody>';

    for my $row_hash_reference (@table_body){
      $table .= '  <tr role="row">';
      my %row_hash = %{$row_hash_reference};
      for my $table_key (@table_keys){
        if (defined $row_hash{$table_key}){
          $table .= qq(   <td align="left" valign="center">$row_hash{$table_key}</td>);
        }
        else{ 
          $table .= qq(   <td align="left" valign="center"></td>);
        }
      }
      $table .= '  </tr>';
    }

    $table .= " </tbody>\n";
    $table .= " </table>\n";
    
    return $table;
}

sub table_data_console_overview {
  my $console = shift;

  my %console_section_id_name = console_structure($wrkdir);

  my @table_keys   = ('system_name', 'pool_name', 'hmc_name',
                      'state', 'number_of_partitions', 'proc_available', 'base_cores',
                      'proc_installed', 'mem_available', 'mem_installed');
  my %table_header = (
    'hmc_uuid'=>'HMC UUID', 
    'hmc_name'=>'HMCs',
    'system_uuid'=>'System UUID', 
    'system_name'=> 'System', 
    'pool_id'=> 'PEP2 ID', 
    'pool_name' => 'PEP2', 
    'tag_id' => 'Tag ID', 
    'tag_name' => 'Tag',
    'number_of_lpars' => 'Number of LPARs',
    'proc_installed' => 'Installed Processor Units', 
    'proc_available' => 'Available Entitled Processor Units', 
    'mem_installed' => 'Installed Memory [TB]', 
    'mem_available' => 'Available Memory [TB]', 
    'state' => 'State',
    'base_cores' => 'Base Processor Units', 
    'number_of_partitions' => 'Number of Partitions'
  );
  my @table_body;
  
  #----------------------------------------------------------------------------------------------  
  # BUILD TABLE BODY -> TODO: MOVE TO PowercmcGraph.pm
  #----------------------------------------------------------------------------------------------  
  # hmc_uuid hmc_name 
  for my $id (sort keys %{$console_section_id_name{$console}{Pools}}){
    for my $system_uuid (keys %{$console_section_id_name{$console}{Pools}{$id}{Systems}}){
      my %row_hash;

      $row_hash{pool_id}    = $id;        
      $row_hash{pool_name}  = $console_section_id_name{$console}{Pools}{$id}{Name};        
      
      my %server_data = %{$console_section_id_name{$console}{Systems}{$system_uuid}};
      
      $row_hash{system_uuid} = $system_uuid;        
      $row_hash{system_name} = $server_data{Name};        
      
        
      $row_hash{base_cores} = $server_data{Configuration}{base_anyoscores};
      $row_hash{number_of_vioss} = $server_data{Configuration}{NumberOfVIOSs};
             
    
      $row_hash{hmc_uuid} = "";       
      $row_hash{hmc_name} = "";        

      for my $hmc_uuid (sort keys %{$server_data{HMCs}}){ 
        $row_hash{hmc_uuid}.= "$hmc_uuid ";       
        my $hmc_name = $server_data{HMCs}{$hmc_uuid}; 
        $row_hash{hmc_name}.= "$hmc_name ";        
      }

      $row_hash{tag_id}    = "";        
      $row_hash{tag_name}  = "";        
      
      for my $tag_id (sort keys %{$server_data{Tags}}){ 
        $row_hash{tag_id}    .= "$tag_id ";        
        $row_hash{tag_name}  .= "$server_data{Tags}{$tag_id}{Name} ";        
      }

      $row_hash{state} = $server_data{Configuration}{State};        
      $row_hash{number_of_lpars} = $server_data{Configuration}{NumberOfLPARs};        
      $row_hash{number_of_partitions} = $server_data{Configuration}{NumberOfLPARs} + $server_data{Configuration}{NumberOfVIOSs};        
      $row_hash{proc_installed} = $server_data{Configuration}{proc_installed};        
      $row_hash{proc_available} = $server_data{Configuration}{proc_available};        
      $row_hash{mem_installed} = $server_data{Configuration}{mem_installed};        
      $row_hash{mem_available} = $server_data{Configuration}{mem_available};        

     # warn "VIOS: $row_hash{number_of_vioss} LPAR: $row_hash{number_of_lpars}";
      push (@table_body, \%row_hash);
    }
  }
  #----------------------------------------------------------------------------------------------  
  return (\@table_keys, \%table_header, \@table_body); 
}


sub table_pep_configuration {
  my $console = shift;

  my %console_section_id_name = console_structure($wrkdir);

  my @table_keys   = ('pool_name',  'CurrentRemainingCreditBalance', 
                      'number_of_partitions',  'base_anyoscores',  'proc_available', 
                      'proc_installed', 'mem_available', 'mem_installed');
  my %table_header = (
    'hmc_uuid'=>'HMC UUID', 
    'hmc_name'=>'HMC',
    'CurrentRemainingCreditBalance' => 'Current Remaining Credit Balance',
    'base_anyoscores' => 'Base Processor Units', 
    'system_uuid'=>'System UUID', 
    'system_name'=> 'System', 
    'pool_id'=> 'PEP2 ID', 
    'pool_name' => 'PEP2', 
    'tag_id' => 'Tag ID', 
    'tag_name' => 'Tag',
    'number_of_lpars' => 'Number of LPARs',
    'proc_installed' => 'Installed Processor Units', 
    'proc_available' => 'Available Entitled Processor Units', 
    'mem_installed' => 'Installed Memory [TB]', 
    'mem_available' => 'Available Memory [TB]', 
    'number_of_partitions' => 'Number of Partitions',
  );
  my @table_body;
  
  #----------------------------------------------------------------------------------------------  
  # BUILD TABLE BODY -> TODO: MOVE TO PowercmcGraph.pm
  #----------------------------------------------------------------------------------------------  
  # hmc_uuid hmc_name 
  for my $id (keys %{$console_section_id_name{$console}{Pools}}){
    my %row_hash;

    my $pool_name = $console_section_id_name{$console}{Pools}{$id}{Name};

    $row_hash{pool_name}=$pool_name;        
    
    my %pool_data = %{$console_section_id_name{$console}{Pools}{$id}};
    
    $row_hash{system_name} = $pool_data{Name};        
    
    $row_hash{CurrentRemainingCreditBalance} = $pool_data{Configuration}{CurrentRemainingCreditBalance};        
    $row_hash{base_anyoscores} = $pool_data{Configuration}{base_anyoscores};        
    $row_hash{number_of_systems} = $pool_data{Configuration}{NumberOfLPARs};        
    $row_hash{number_of_lpars} = $pool_data{Configuration}{NumberOfLPARs};        
    $row_hash{proc_installed} = $pool_data{Configuration}{proc_installed};        
    $row_hash{proc_available} = $pool_data{Configuration}{proc_available};        
    $row_hash{mem_installed} = $pool_data{Configuration}{mem_installed};        
    $row_hash{mem_available} = $pool_data{Configuration}{mem_available};        
    $row_hash{number_of_vioss} = $pool_data{Configuration}{NumberOfVIOSs};
    $row_hash{number_of_partitions} = $pool_data{Configuration}{NumberOfLPARs} + $pool_data{Configuration}{NumberOfVIOSs};        
    #warn "VIOS: $row_hash{number_of_vioss} LPAR: $row_hash{number_of_lpars}";
    #for my $keyword (keys %row_hash){
    #  if (! $row_hash{$keyword}){
    #    $row_hash{$keyword}='NA';
    #  }
    #}
    push (@table_body, \%row_hash);
  }
  #----------------------------------------------------------------------------------------------  
  return (\@table_keys, \%table_header, \@table_body); 
}


sub console_structure {
  my $wrkdir = shift;
  my $consoles_file = "${wrkdir}/PEP2/console_section_id_name.json";
  my $json;
  #print "$filename \n";
  my %console_id_name;
  open(FH, '<', $consoles_file) or die $!;
  while(<FH>){
     $json .= $_;
  }
  #print Dumper \%{decode_json($json)};
  close(FH);
  
  if ( -f "$consoles_file") {
    %console_id_name = %{decode_json($json)};
  }
  return %console_id_name;
  
}

sub console_history {
  my $wrkdir = shift;
  my $console_name = shift;

  #warn "Console name: $console_name";
  my $hist_file = "${wrkdir}/PEP2/${console_name}/history.json";
  my $json;
  #print "$filename \n";
  my %console_history;
  open(FH, '<', $hist_file) or die $!;
  while(<FH>){
     $json .= $_;
  }
  #print Dumper \%{decode_json($json)};
  close(FH);
  
  if ( -f "$hist_file") {
    %console_history = %{decode_json($json)};
  }

  return %console_history;
  
}

sub consoles_uuid_rrd {
  # ALL EXISTING OR ALL ACTIVE?
  my $console = shift;
  
  my %uuid_rrdfile = ();
  my @uuid_list;
  my @file_list = ();
  # Systems_(.+).rrd
  for my $filename (@file_list){
    if ( $filename =~ /Systems_(.+).rrd/ ){
      $uuid_rrdfile{$1} = $filename;
    }
  }

  return %uuid_rrdfile;

}

sub list_rrd_dir{

}

sub list_rrd_console{

}

sub listofrom {
  my $list_of = shift;
  my $list_from = shift;
    
  my $datadir;

  my @source;
  # list_of: rrd systems 
}

#sub rrd_filepath {
#  my $params = shift;
#
#  my $type      = $params->{type};
#  my $host      = $params->{id};
#
#  my $filepath  = "";
#
#  $filepath = "${wrkdir}/PEP2/${type}_${host}.rrd";
#
#  return $filepath;
#}
sub isdigit {
  my $digit = shift;

  my $digit_work = $digit;

  $digit_work =~ s/[0-9]//g;
  $digit_work =~ s/\.//;
  
  if ( length($digit_work) == 0 ) {
    return 1;
  }

  return 0;
}

sub basename {
  my $full      = shift;
  my $separator = shift;
  my $out       = "";

  #my $length = length($full);
  if ( defined $separator and defined $full and index( $full, $separator ) != -1 ) {
    $out = substr( $full, length($full) - index( reverse($full), $separator ), length($full) );
    return $out;
  }
  return $full;
}


sub graph_legend {
  my $page = shift;

  #This defines rules for graphs in each tab
  my %legend = (
    'default' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'not_defined',
      'value'      => 'Total',
      'rrd_vname'  => '',
      'graph_type' => 'LINE1',
      'v_label'    => 'not_defined',
      'decimals'   => '1'
    },
    'cmc_pools' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => '',
      'value'      => 'Total',
      'rrd_vname'  => '',
      'graph_type' => 'LINE1',
      'v_label'    => 'Memory',
      'decimals'   => '1'
    },
    'cmc_system' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'System CPU',
      'value'      => 'Total',
      'rrd_vname'  => '',
      'graph_type' => 'LINE1',
      'v_label'    => 'CPU',
      'decimals'   => '1'
    },

  );

  if ( $legend{$page} ) {
    return $legend{$page};
  }
  else {
    return $legend{default};
  }
}

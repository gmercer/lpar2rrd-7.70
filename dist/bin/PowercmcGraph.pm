package PowercmcGraph;

use strict;
use warnings;

use PowercmcDataWrapper;
use Data::Dumper;
use Xorux_lib qw(error read_json);
use Xorux_lib;
use JSON;

defined $ENV{INPUTDIR} || warn("INPUTDIR undefined, config etc/lpar2rrd.cfg probably has not been loaded ") && exit 1;

my $inputdir      = $ENV{INPUTDIR};
my $bindir        = $ENV{BINDIR};
my $main_data_dir = "$inputdir/data/PEP2";
my $wrkdir = "${inputdir}/data";

my $instance_names;
my $can_read;
my $ref;
my $del = "XORUX";    # delimiter, this is for rrdtool print lines for clickable legend

my @_colors = get_colors();

#sub signpost {
#  my $acl_check = shift;
#  my $host      = shift;
#  my $server    = shift;
#  my $lpar      = shift;
#  my $item      = shift;
#  my $colors    = shift;
#  my $dunno     = shift;
#  #warn "$acl_check, $host, $server, $lpar, $item, $dunno";
#  if ( $item =~ /_a_/ ) {
#    return graph_default( $acl_check, $host, $server, $lpar, $item, $dunno );
#  }
#  elsif ( $item =~ m/^powercmc/ ) {
#    return graph_views( $acl_check, $host, $server, $lpar, $item, \@_colors );
#  }
#  else {
#    return 0;
#  }
#}

sub signpost_new {
  my $acl_check = shift;
  my $host      = shift;
  my $server    = shift;
  my $lpar      = shift;
  my $item      = shift;
  my $colors    = shift;
  my $time_type = shift;
  #warn "$time_type";
  #warn "$acl_check, $host, $server, $lpar, $item, ";
  
  my $cmd_def          = '';
  my $cmd_cdef         = '';
  my $cmd_legend       = '';
  my $cmd_params       = '';

  $cmd_params = " --lower-limit=0.00";
  $cmd_params .= " --units-exponent=1.00";

  $cmd_legend = " COMMENT:\" \"";

  #---------------------------------------------------------------
  #warn "SIGNPOST::::CURRENT ITEM: $item, host $host, server $server, lpar $lpar, console $acl_check";
  # SIGNPOST::::CURRENT ITEM: powercmc_pep2_pool__cmc_system, host 0254, server PowerCMC, lpar pep2_pool, console cmc_example
  my $graph_entry;
  if ( $item =~ /pool__cmc_system/ ) {
    $graph_entry = graph_stacked("Pools", $acl_check, $host, $server, $lpar, $item, \@_colors, $time_type );
  }
  elsif ( $item =~ /pool__cmc_credit/ ) {
    $graph_entry = graph_views("Pools", $acl_check, $host, $server, $lpar, $item, \@_colors );
  }
  elsif ( $lpar =~ m/pep2_all/ ) {

    # sum: total, installed
    # aggregate: utilized
    #warn "HERE:::::::::::::::::::::::::";
    # get console -> get servers under console -> send their uuids to GRAPH

    #$graph_entry = graph_total( $acl_check, $host, $server, $lpar, $item, \@_colors );
    #warn "STACKING .>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>";ii
    #warn "$item";
    $graph_entry = graph_all_total("Systems", $acl_check, $host, $server, $lpar, $item, \@_colors, $time_type );
 

  }
  elsif ( $item =~ m/^powercmc/ ) {
    $graph_entry = graph_views( $acl_check, $host, $server, $lpar, $item, \@_colors );
  
  }
  else {
    $graph_entry = 0;
  }

  #---------------------------------------------------------------

  #warn "PowercmcGraph::signpost ENTRY: ";
  #warn "acl_check $acl_check, server $server, host $host, lpar $lpar, item $item";
  #warn "GRAPH ENTRY: ";
  #warn Dumper $graph_entry;
  my $vertical_label   = '';

  $cmd_def    .= $graph_entry->{cmd_def};
  $cmd_cdef   .= $graph_entry->{cmd_cdef};
  $cmd_legend .= $graph_entry->{cmd_legend};
  $vertical_label = " --vertical-label=\" $graph_entry->{cmd_vlabel} \"";

  my $filepath = $graph_entry->{filename};
  if ( !-f $filepath ) {
    
    warn( "$filepath does not exist " . __FILE__ . ":" . __LINE__ );
  }

  my $last_update_time = 0;
  
  my $rrd_update_time;

  if (defined $filepath){
    $rrd_update_time = ( stat($filepath) )[9] ;
  }
  else{
    $rrd_update_time = 0;
  }

  if ( $rrd_update_time > $last_update_time ) {
    $last_update_time = $rrd_update_time;
  }

  my $cmd_custom_part_r;

  $cmd_custom_part_r .= $cmd_params;
  $cmd_custom_part_r .= $cmd_def;
  $cmd_custom_part_r .= $cmd_cdef;
  $cmd_custom_part_r .= $cmd_legend;

  return ($cmd_custom_part_r, $graph_entry);
}

sub cmd_start {

}

sub get_formatted_label {

  my $label_space = shift;

  $label_space .= " " x ( 30 - length($label_space) );

  return $label_space;
}

sub get_formatted_label_val {
  my $label_space = shift;
  if (length($label_space) < 25){
    $label_space .= " " x ( 25 - length($label_space) );
  }
  return $label_space;
}

sub get_color {
  my $colors_ref = shift;
  my $col        = shift;
  my @colors     = @{$colors_ref};
  my $color;
  my $next_index = $col % $#colors;
  $color = $colors[$next_index];
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
      'header'     => 'Pool',
      'value'      => 'Total',
      'rrd_vname'  => '',
      'graph_type' => 'LINE1',
      'v_label'    => 'Memory [Memory.Minutes]',
      'decimals'   => '1'
    },
    'total_cpu' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'Total CPU utilization',
      'value'      => 'Total',
      'rrd_vname'  => '',
      'graph_type' => 'LINE1',
      'v_label'    => 'CPU Cores',
      'decimals'   => '1'
    },
    'total_credit' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'Total credit consumption',
      'value'      => 'Total',
      'rrd_vname'  => '',
      'graph_type' => 'LINE1',
      'v_label'    => 'Credits',
      'decimals'   => '1'
    },
    'memory_credit' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'Pool credit consumption',
      'value'      => 'Total',
      'rrd_vname'  => '',
      'graph_type' => 'STACK',
      'v_label'    => 'Credits',
      'decimals'   => '1'
    },
    'metered_core_minutes' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'Pool metered core minutes',
      'value'      => 'Total',
      'rrd_vname'  => '',
      'graph_type' => 'STACK',
      'v_label'    => 'Metered Core Minutes',
      'decimals'   => '1'
    },
    'metered_memory_minutes' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'Pool metered memory minutes',
      'value'      => 'Total',
      'rrd_vname'  => '',
      'graph_type' => 'STACK',
      'v_label'    => 'Metered Memory Minutes',
      'decimals'   => '1'
    },
    'credit' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'Pool credit consumption',
      'value'      => 'Total',
      'rrd_vname'  => '',
      'graph_type' => 'STACK',
      'v_label'    => 'Credit',
      'decimals'   => '1'
    },
    'cmc_pools_c' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => '',
      'value'      => 'Total',
      'rrd_vname'  => '',
      'graph_type' => 'LINE1',
      'v_label'    => 'CPU [Core.Minutes]',
      'decimals'   => '1'
    },
    'cmc_system' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'Server CPU',
      'value'      => 'Total',
      'rrd_vname'  => '',
      'graph_type' => 'LINE1',
      'v_label'    => 'CPU [cores]',
      'decimals'   => '1'
    },
    'cmc_system_memory' => {
      'denom'      => '1',
      'brackets'   => '',
      'header'     => 'Server Memory',
      'value'      => 'Total',
      'rrd_vname'  => '',
      'graph_type' => 'LINE1',
      'v_label'    => 'Memory [GB]',
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

#          'Available' => 'proc_available',
#          'Installed' => 'proc_installed',
#          'Total'     => 'totalProcUnits',

sub give_type_tab_name_metric{
  my %type_tab_name_metric;

  %type_tab_name_metric = (

    'total' => {
      'total' => {
          'Utilized'  => 'utilizedProcUnits', 
          'Base'     => 'base_anyoscores',
          'Installed' => 'proc_installed',
      }
    },

    'pep2_all' => {
      'total_cpu' => {
          'Utilized'  => 'utilizedProcUnits', 
      },
      'total_credit' => {
          'Total' => 'reserve_1',
      }
    },
    'pep2_cmc_total' => {
      'cmc_total' => {
        'Available' => 'proc_available',
        'Installed' => 'proc_installed',
       }
    },


    'pep2_pool' => {
      'credit' => {
        "AIX" => 'cmc_aix',
        "IBMi" => 'cmc_ibmi',
        "RHELCoreOS" => 'cmc_rhelcoreos',
        "RHEL" => 'cmc_rhel',
        "SLES" =>  'cmc_sles',
        "LinuxVIOS" => 'cmc_linuxvios',
        #"VIOS" => 'cmc_vios',
        #"AnyOS" => 'cmc_anyos',
        #"Total" => 'cmc_total',
        "Memory" => 'mm_credits',
      },
      'metered_core_minutes' => {
        "AIX" => 'cmm_aix',
        "IBMi" => 'cmm_ibmi',
        "RHELCoreOS" => 'cmm_rhelcoreos',
        "RHEL" => 'cmm_rhel',
        "SLES" =>  'cmm_sles',
        "LinuxVIOS" => 'cmm_linuxvios',
        #"AnyOS" => 'cmc_anyos',
        #"Total" => 'cmc_total',
      },
      'metered_memory_minutes' => {
        "Memory" => 'mm_minutes',
      },
      'cmc_system' => {
        'Utilized'  => 'utilizedProcUnits', 
        'Base'     => 'base_anyoscores',
        'Installed' => 'proc_installed',
      },
      'cmc_pools' => {
        'AIX' =>'mm_aix',
        'SLES' =>'mm_sles',
        'VIOS' =>'mm_vios',
        'IBMi' =>'mm_ibmi',
        'RHEL' =>'mm_rhel',
        'RhelCoreOS' =>'mm_rhelcoreos',
        'Total' =>'mm_total',
        'Other Linux' =>'mm_otherlinux',
      },

      'cmc_pools_c' => {
        'AIX' =>'cm_aix',
        'SLES' =>'cm_sles',
        'VIOS' =>'cm_vios',
        'IBMi' =>'cm_ibmi',
        'RHEL' =>'cm_rhel',
        'RHELCoreOS' =>'cm_rhelcoreos',
        'Total' =>'cm_total',
        'Other Linux' =>'cm_total',
       }
    },

    'pep2_system' => {

      'cmc_system' => {
        'Utilized'  => 'utilizedProcUnits', 
        'Base'     => 'base_anyoscores',
        'Installed' => 'proc_installed',

      },

      'cmc_system_memory' => {
        'Available' => 'mem_available',
        'Installed' => 'mem_installed',
      },

    },

  );

  return %type_tab_name_metric
}

sub file_to_string{
  my $filename = shift;
  my $json;
  #print "$filename \n";
  open(FH, '<', $filename) or die $!;
  while(<FH>){
     $json .= $_;
  }
  close(FH);
  return $json;
}
 
# SUM ALL METRICS IN LIST
sub rrd_sum_to {
  my $to_sum_reference = shift;
  my $sum_result  = shift;
  
  my $rrd_command = 'CDEF';
  my @metrics_to_sum = @{$to_sum_reference};

  $" = ',';
  my $pluses = '';
  if (scalar(@metrics_to_sum) gt 1){
    $pluses = ',+'x int((scalar @metrics_to_sum) - 1);
  }

  my $cmd = " ${rrd_command}:${sum_result}=@{metrics_to_sum}${pluses}";
  $" = ' ';

  return $cmd;
} 

sub get_console_type_uuids{
  my $console = shift;
  my $sec     = shift;

  #my $main_data_dir = "$inputdir/data/PEP2";
  opendir my $dir, "$main_data_dir/$console" or die $!;
  my @files = readdir $dir;

  my @all_saved = ();

  for my $file (@files){
    if ($file =~ /${sec}_(.*)\.rrd/){
      push (@all_saved, $1);
    }
  }

  return @all_saved;
}

sub get_console_type_history{
  my $console = shift;
  my $sec     = shift;

  
}

sub rrd_last_update{
  my $filepath = shift;
  #my $rrdtool = $ENV{RRDTOOL};
  #RRDp::start "$rrdtool";
  my $last_time = ${Xorux_lib::rrd_last_update($filepath)};
  #RRDp::end;
  return $last_time;
}

sub group_latest_update{
  # Nearest latest update from group
  my @rrds = @_;
  my $latest_update = 0;
  my $save_rrd = $rrds[0];

  for my $rrd (@rrds){
    my $last_time = rrd_last_update($rrd);
    if ($last_time gt $latest_update){
      $latest_update = $last_time;
      $save_rrd = $rrd;
    }

  }

  return ($latest_update, $save_rrd);
}

sub rrd_group_time_in_range{
  # Check if nearest last update is in d/w/m/(y) range
  my $range = shift;
  my $rrds_ref = shift;

  my @rrds = @{$rrds_ref};

  my ($latest_group_time, $latest_rrd) = group_latest_update(@rrds);

  if (time_in_range($range, $latest_group_time)){
    return 1;
  }
  else{
    return 0;
  }  

}

sub time_in_range{
  my $range = shift;
  my $rrd_time   = shift;

  my $now_time = time();
  #warn $range;
  my $range_time;

  if ( "$range" eq 'd' ) {
    $range_time = $now_time - 86400;
  }
  if ( "$range" eq "w" ) {
    $range_time = $now_time - 604800;
  }
  if ( "$range" eq "m" ) {
    $range_time = $now_time - 2764800;
  }
  if ( "$range" eq "y" ) {
    return 1
  }
  #warn "now: $now_time RANGE: $range_time";  
  if ($rrd_time gt $range_time){
    return 1;
  }
  else{
    return 0;
  }

}

sub rrd_time_in_range{
  my $range = shift;
  my $rrd   = shift;

  my $now_time = time();

  my $rrd_time = rrd_last_update($rrd);
  #my $rrd_time = ( stat($rrd) )[9];

  my $range_time;

  if ( "$range" eq 'd' ) {
    $range_time = $now_time - 86400;
  }
  if ( "$range" eq "w" ) {
    $range_time = $now_time - 604800;
  }
  if ( "$range" eq "m" ) {
    $range_time = $now_time - 2764800;
  }
  if ( "$range" eq "y" ) {
    return 1
  }
  #warn $range;
  #warn "now: $now_time rrd: $rrd_time RANGE: $range_time";  
  if ($rrd_time gt $range_time){
    return 1;
  }
  else{
    return 0;
  }

}

sub get_console_type_rrds{
  # NOT USED
  # ls to array
  my $console = shift;
  my $sec     = shift;

  #my $main_data_dir = "$inputdir/data/PEP2";
  opendir my $dir, "$main_data_dir/$console" or die $!;
  my @files = readdir $dir;

  my @all_saved = ();

  for my $file (@files){
    if ($file =~ /${sec}_(.*)\.rrd/){
      push (@all_saved, $file);
    }
  }

  return @all_saved;
}

sub graph_all_total {
  my $data_section = shift; 
  my $acl_check  = shift;
  my $host       = shift;
  my $server     = shift;
  my $type       = shift;
  my $item       = shift;
  my $colors_ref = shift;
  my $time_type  = shift; 
 
  my $console_name = "$host";
  my $filename = "${inputdir}/data/PEP2/console_section_id_name.json";
  my %console_section_id_name = PowercmcDataWrapper::console_structure($wrkdir);
  
  my %console_history; 
  #-----------------------------------------------------------------------------------------------
 
  my $color;
  my $metric_counter = 0;
  my $color_counter = 0; 
  #warn "INPUT PARAMETERS: acl_check $acl_check HOST $host server $server type $type item $item colors_ref $colors_ref";

  my $rrd;
  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = "";

  # 
  my %type_tab_name_metric = give_type_tab_name_metric();
    
  #-----------------------------------------------------------------------------------------------
  #warn "GRAPGING_______________________________"; 
  # additional translation type -> Section
  # -> Overarching structure
  my %translate_type = (
      "total_credit" => "Pools",
      "total_cpu" => "Systems");
  # for now: all comes from Systems rrds
  #$type = 'pep2_system';
  
  if ($item =~ /(.+)__(.+)$/){
    $type = $2;
  }
  
  my $type_use = $translate_type{$type};  
  #warn "ITEM: $item"; 
  #warn "HERE TYPE USE: $type $type_use"; 
  
  my @system_uuids;

  my @console_names = sort keys %console_section_id_name;

  my %pool_rrds;

  my @pool_ids;  
  for my $console_name (@console_names){
    %console_history = PowercmcDataWrapper::console_history($wrkdir, $console_name); 

    if ($type_use eq "Pools"){
      my @IDS;
      @IDS = sort keys %{$console_history{Pools}};
      for my $ID (@IDS){
        my @rrd_list = ();
        push(@pool_ids, $ID);
        push (@rrd_list, "${inputdir}/data/PEP2/${console_name}/${type_use}_${ID}.rrd");
        
        $rrd       = $rrd_list[0];
        my $lapdate;
        ( $lapdate , $rrd ) = group_latest_update(@rrd_list);
        
        $pool_rrds{$console_name}{$ID} = \@rrd_list; 
      }
    }
    elsif($type_use eq "Systems"){
      %console_history = PowercmcDataWrapper::console_history($wrkdir, $console_name); 
      
      for my $pool_id (sort keys %{$console_history{Pools}}){
        my @rrd_list = ();
        my @IDS;
        for my $system_uuid (keys %{$console_history{Pools}{$pool_id}{Systems}}){
          push (@IDS, $system_uuid);
        }
        for my $ID (@IDS){
          push (@rrd_list, "${inputdir}/data/PEP2/${console_name}/${type_use}_${ID}.rrd");
        }
        
        $rrd       = $rrd_list[0];
        my $lapdate;
        ( $lapdate , $rrd ) = group_latest_update(@rrd_list);
        
        $pool_rrds{$console_name}{$pool_id} = \@rrd_list; 
        push(@pool_ids, $pool_id);
      }
    }

  }
  
  #warn "POOL RRD TRANSLATE";
  #warn Dumper %pool_rrds;
  #-----------------------------------------------------------------------------------------------
  # connection to tabs
  my $tab_code;
  
  if ($item =~ /(.+)__(.+)$/){
    $tab_code = $2;
  }
  else{
    $tab_code = "";
  }
  #$tab_code = 'cmc_system'; 
  
  my @named_metrics;
  @named_metrics = keys %{ $type_tab_name_metric{$type}{$tab_code} };
  @named_metrics = sort { lc($a) cmp lc($b) } @named_metrics;

  my $legend = graph_legend($tab_code);
  
  #-----------------------------------------------------------------------------------------------
  
  $cmd_params .= " --lower-limit=0.00";
  $cmd_params .= " --alt-y-grid";
  $cmd_legend .= " COMMENT:\\n";

  my $clean_tab_code = $tab_code;
  $clean_tab_code =~ s/ /_/g;

  my %type_metric = (
      "total_credit" => 'reserve_1',
      "total_cpu" => 'utilizedProcUnits');

  my $pool_counter = 0;
  for my $console_name (sort keys %pool_rrds) {

    for my $pool_id (sort keys %{$pool_rrds{$console_name}}) {
      $pool_counter++;
      
      # check time and kill here
      # rrd time check
      #sub rrd_time_in_range{
      my @rrd_group_to_check = @{$pool_rrds{$console_name}{$pool_id}};
      next if (! rrd_group_time_in_range( $time_type, \@rrd_group_to_check ));
 

      my $command = "";
      $cmd_def .= "\n";
    
      my @rrd_list = @{$pool_rrds{$console_name}{$pool_id}}; 
     
      my $rrd_metricname = $type_metric{$type};
      my @rrd_metrics_to_sum = ();

      for $rrd (@rrd_list){ 
        $cmd_def .= " DEF:name-$metric_counter-$rrd_metricname=\"$rrd\":$rrd_metricname:AVERAGE";
        $cmd_def .= "\n";
        push (@rrd_metrics_to_sum, "name-$metric_counter-$rrd_metricname");
        $metric_counter++;
      }
      #warn "@rrd_metrics_to_sum";    

      ## CDEF: metrics -> clean metrics
      my @checked_metrics_to_sum = ();
      for my $metric_to_sum (@rrd_metrics_to_sum){
        my $clean_metric_name = "clean-${metric_to_sum}";
        $command .= " CDEF:${clean_metric_name}=${metric_to_sum},UN,0,${metric_to_sum},IF";
        push (@checked_metrics_to_sum, "$clean_metric_name");
      }    
      
      # CDEF: UN checker: 0 => all UN | !=0 => at least one is not UN
      my @u_checked_metrics;
      for my $metric_to_sum (@rrd_metrics_to_sum){
        my $ucheck_metric_name = "u_check-${metric_to_sum}";
        $command .= " CDEF:${ucheck_metric_name}=${metric_to_sum},UN,0,1,IF";
        push (@u_checked_metrics, "$ucheck_metric_name");
      }

      $command .= rrd_sum_to(\@u_checked_metrics, "sum-u_check-${rrd_metricname}_${pool_counter}");
      $command .= rrd_sum_to(\@{rrd_metrics_to_sum}, "x_sum-${rrd_metricname}_${pool_counter}");
      
      $command .= " CDEF:sum-${rrd_metricname}_${pool_counter}=sum-u_check-${rrd_metricname}_${pool_counter},0,EQ,UNKN,x_sum-${rrd_metricname}_${pool_counter},IF";
      
      #$command .= " CDEF:sum-${rrd_metricname}_${pool_counter}=x_sum-${rrd_metricname}_${pool_counter},0,EQ,UNKN,x_sum-${rrd_metricname}_${pool_counter},IF";
      
      $cmd_cdef .= $command;     
      #warn $command; 
      $cmd_cdef .= "\n";
      #print $command;

    }
  }
  $pool_counter = 0;

  for my $console_name (sort keys %pool_rrds) {
    %console_history = PowercmcDataWrapper::console_history($wrkdir, $console_name); 

    for my $pool_id (sort keys %{$pool_rrds{$console_name}}) {
      $pool_counter++;
      my $rrd_metricname = $type_metric{$type};
      
      $color = get_color( $colors_ref, $color_counter );
      $color_counter++;
 
      # check time and kill here
      # rrd time check
      #sub rrd_time_in_range{
      my @rrd_group_to_check = @{$pool_rrds{$console_name}{$pool_id}};
      next if (! rrd_group_time_in_range( $time_type, \@rrd_group_to_check ));
 
 
      my $pool_name = $console_history{Pools}{$pool_id}{Name};
      my $console_alias = $console_section_id_name{$console_name}{Alias}; 
      my $label   = get_formatted_label_val("$console_alias\\:$pool_name");

      #-----------------------------------------------------------------------------------------------
      my $cmd_printer = "";
      #warn "Metric: $named_metric";
      $cmd_printer .= " LINE1:sum-${rrd_metricname}_${pool_counter}" . "$color:\" $label\"";
      $cmd_printer .= "\n";
  
      $cmd_printer .= " GPRINT:sum-${rrd_metricname}_${pool_counter}:AVERAGE:\" %6.".$legend->{decimals}."lf\"";
      $cmd_printer .= "\n";
      $cmd_printer .= " GPRINT:sum-${rrd_metricname}_${pool_counter}:MAX:\" %6.".$legend->{decimals}."lf\"";
      $cmd_printer .= "\n";
      $cmd_printer .= " PRINT:sum-${rrd_metricname}_${pool_counter}:AVERAGE:\" %6.".$legend->{decimals}."lf $del $item $del $label $del $color $del $clean_tab_code\""; 
      $cmd_printer .= "\n";
      $cmd_printer .= " PRINT:sum-${rrd_metricname}_${pool_counter}:MAX:\" %6.".$legend->{decimals}."lf $del asd $del $label $del cur_hos\"";
      $cmd_printer .= "\n";
      $cmd_printer .= " COMMENT:\\n";
      $cmd_printer .= "\n";
      #-----------------------------------------------------------------------------------------------
      $cmd_legend .= $cmd_printer;
  
      $metric_counter++;
    }
  } 

  my %command_hash = (
    filename        => $rrd,     
    header          => "$legend->{header}", 
    reduced_header  => "$legend->{header}", 
    cmd_params      => $cmd_params,
    cmd_def         => $cmd_def, 
    cmd_cdef        => $cmd_cdef,           
    cmd_legend      => $cmd_legend,        
    cmd_vlabel      => "$legend->{v_label}"
  );

  return \%command_hash;

}
sub graph_stacked {
  my $data_section = shift; 
  my $acl_check  = shift;
  my $host       = shift;
  my $server     = shift;
  my $type       = shift;
  my $item       = shift;
  my $colors_ref = shift;
  my $time_type  = shift; 
  
  #-----------------------------------------------------------------------------------------------
  my $console_name = "$host";
  
  # load console structure from json
  my $filename = "${inputdir}/data/PEP2/console_section_id_name.json";
  my %console_section_id_name = PowercmcDataWrapper::console_structure($wrkdir);
  # REMOVE WRKDIR FROM CALL 
  my %console_history; 
  # from console structure get list of uuids of servers (Systems)
  #-----------------------------------------------------------------------------------------------
  my @system_uuids;

  # get uuid list by section -> move to PowercmcDataWrapper 

  # Historical console structure
  if ($data_section eq "Systems"){
    $console_name = "$host";

    %console_history = PowercmcDataWrapper::console_history($wrkdir, $console_name); 
    for my $system_uuid (keys %{$console_history{Systems}}){
      push (@system_uuids, $system_uuid);
    }
  }elsif ($data_section eq "Pools"){
    $console_name = "$acl_check";

    %console_history = PowercmcDataWrapper::console_history($wrkdir, $console_name); 
    #warn "GRAPH STACKED VARIABLES: CONSOLE NAME $console_name , HOST $host";
    #warn Dumper %{$console_section_id_name{$console_name}{Pools}{$host}};
    for my $system_uuid (keys %{$console_history{Pools}{$host}{Systems}}){
      push (@system_uuids, $system_uuid);
    }

  }
  #-----------------------------------------------------------------------------------------------
 
  my $color;
  my $metric_counter = 0;
  my $color_counter = 0; 
  #warn "INPUT PARAMETERS: acl_check $acl_check HOST $host server $server type $type item $item colors_ref $colors_ref";

  my $rrd;
  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = "";

  # 
  my %type_tab_name_metric = give_type_tab_name_metric();
    
  #-----------------------------------------------------------------------------------------------
  
  # additional translation type -> Section
  # -> Overarching structure
  my %translate_type = (
      "pep2_pool" => "Pools",
      "pep2_system" => "Systems");
  # for now: all comes from Systems rrds
  $type = 'pep2_system';
  
  my $type_use = $translate_type{$type};  
  
  #-----------------------------------------------------------------------------------------------
  
  my @rrd_list = ();
  
  # ALL RRDS IN FOLDER
  #@rrd_list = get_console_type_rrds($console_name, "Systems");
  #@system_uuids = get_console_type_uuids($console_name, "Systems");

  #warn @system_uuids;
  
  for my $system_uuid (sort @system_uuids){
    push (@rrd_list, "${inputdir}/data/PEP2/${console_name}/Systems_${system_uuid}.rrd");
  }
  
  $rrd       = $rrd_list[0];
  my $lapdate;
  ( $lapdate , $rrd ) = group_latest_update(@rrd_list);

  #-----------------------------------------------------------------------------------------------
  # connection to tabs
  my $tab_code;
  
  if ($item =~ /(.+)__(.+)$/){
    $tab_code = $2;
  }
  else{
    $tab_code = "";
  }
  $tab_code = 'cmc_system'; 
  
  my @named_metrics;
  @named_metrics = keys %{ $type_tab_name_metric{$type}{'cmc_system'} };
  @named_metrics = sort { lc($a) cmp lc($b) } @named_metrics;

  #my @named_metrics_to_sum = ('Available', 'Installed', 'Total', 'Base'); 
  my @named_metrics_to_sum = ( 'Base', 'Installed'); 
  my @named_metrics_to_stack = ('Utilized'); 
          #'Installed' => 'proc_installed',
          #'Utilized'  => 'utilizedProcUnits', 
          #'Total'     => 'totalProcUnits'
  my $legend = graph_legend($tab_code);
  
  #-----------------------------------------------------------------------------------------------
  
  $cmd_params .= " --lower-limit=0.00";
  $cmd_params .= " --alt-y-grid";
  $cmd_legend .= " COMMENT:\\n";
  my $clean_tab_code = $tab_code;
  $clean_tab_code =~ s/ /_/g;


  for my $named_metric (@named_metrics_to_sum) {
    
    my $command = "";
    $cmd_def .= "\n";
    
    my $rrd_metricname = $type_tab_name_metric{$type}{$tab_code}{$named_metric};
    # DEF: metrics + RRDs
    # rrd1 => metric_list_1
    # rrd2 => metric_list_2
    my @rrd_metrics_to_sum = ();
    for $rrd (@rrd_list){ 
      $cmd_def .= " DEF:name-$metric_counter-$rrd_metricname=\"$rrd\":$rrd_metricname:AVERAGE";
      $cmd_def .= "\n";
      push (@rrd_metrics_to_sum, "name-$metric_counter-$rrd_metricname");
      $metric_counter++;
    }

    # CDEF: metrics -> clean metrics
    my @checked_metrics_to_sum = ();
    for my $metric_to_sum (@rrd_metrics_to_sum){
      my $clean_metric_name = "clean-${metric_to_sum}";
      $command .= " CDEF:${clean_metric_name}=${metric_to_sum},UN,0,${metric_to_sum},IF";
      push (@checked_metrics_to_sum, "$clean_metric_name");
    }    
    
    # CDEF: UN checker: 0 => all UN | !=0 => at least one is not UN
    my @u_checked_metrics;
    for my $metric_to_sum (@rrd_metrics_to_sum){
      my $ucheck_metric_name = "u_check-${metric_to_sum}";
      $command .= " CDEF:${ucheck_metric_name}=${metric_to_sum},UN,0,1,IF";
      push (@u_checked_metrics, "$ucheck_metric_name");
    }

    $command .= rrd_sum_to(\@u_checked_metrics, "sum-u_check-${rrd_metricname}");
    $command .= rrd_sum_to(\@{checked_metrics_to_sum}, "x_sum-${rrd_metricname}");
    
    $command .= " CDEF:sum-${rrd_metricname}=sum-u_check-${rrd_metricname},0,EQ,UNKN,x_sum-${rrd_metricname},IF";
    
    $cmd_cdef .= $command;     
    $cmd_cdef .= "\n";
    #print $command;

  }

  my %named_metric_color = (
    'Available' => '#00FF00', 
    'Base' => '#000000', 
    'Installed' => '#00008B', 
    'Total' => '#808080',
  );

  for my $named_metric (@named_metrics_to_sum) {
      my $rrd_metricname = $type_tab_name_metric{$type}{$tab_code}{$named_metric};
      
      if (defined $named_metric_color{$named_metric}){
        $color = $named_metric_color{$named_metric};
      }else{
        $color = get_color( $colors_ref, $color_counter );
        $color_counter++;
      }  
  
      my $label   = get_formatted_label_val("$named_metric");

      #-----------------------------------------------------------------------------------------------
      my $cmd_printer = "";
      #warn "Metric: $named_metric";
      if ( "$named_metric" eq 'Installed' ){
        #warn "LABEL: $label"; 
        $cmd_printer .= " LINE2:sum-$rrd_metricname" . "#FFFFFF:\" $label\":skipscale";
        $cmd_printer .= "\n";
        $cmd_printer .= " GPRINT:sum-$rrd_metricname:AVERAGE:\" %6.".$legend->{decimals}."lf\"";
        $cmd_printer .= "\n";
        $cmd_printer .= " GPRINT:sum-$rrd_metricname:MAX:\" %6.".$legend->{decimals}."lf\"";
        $cmd_printer .= "\n";
        $cmd_printer .= " PRINT:sum-$rrd_metricname:AVERAGE:\" %6.".$legend->{decimals}."lf $del $item $del $label $del  $del $clean_tab_code\""; 
        $cmd_printer .= "\n";
        $cmd_printer .= " PRINT:sum-$rrd_metricname:MAX:\" %6.".$legend->{decimals}."lf $del asd $del $label $del cur_hos\"";
      }
      else{
        $cmd_printer .= " LINE2:sum-$rrd_metricname" . "$color:\" $label\"";
        $cmd_printer .= "\n";
        $cmd_printer .= " GPRINT:sum-$rrd_metricname:AVERAGE:\" %6.".$legend->{decimals}."lf\"";
        $cmd_printer .= "\n";
        $cmd_printer .= " GPRINT:sum-$rrd_metricname:MAX:\" %6.".$legend->{decimals}."lf\"";
        $cmd_printer .= "\n";
        $cmd_printer .= " PRINT:sum-$rrd_metricname:AVERAGE:\" %6.".$legend->{decimals}."lf $del $item $del $label $del $color $del $clean_tab_code\""; 
        $cmd_printer .= "\n";
        $cmd_printer .= " PRINT:sum-$rrd_metricname:MAX:\" %6.".$legend->{decimals}."lf $del asd $del $label $del cur_hos\"";
      }
  
      $cmd_printer .= "\n";
      $cmd_printer .= " COMMENT:\\n";
      $cmd_printer .= "\n";
      #-----------------------------------------------------------------------------------------------
      $cmd_legend .= $cmd_printer;
  
      $metric_counter++;
  }
 

  for my $named_metric (@named_metrics_to_stack) {
    my $number_to_stacking = $metric_counter;
    
    # rrds of all servers
    for $rrd (sort @rrd_list){ 
      my $rrd_metricname = $type_tab_name_metric{$type}{$tab_code}{$named_metric};
      my $uid;
   
      if ( $rrd =~ /Systems_(.+)\.rrd/ ) {
        $uid = $1;
      }

      my $name = $console_history{Systems}{$uid};

      # color counted per every server == unique in all graphs
      $color = get_color( $colors_ref, $color_counter );
      $color_counter++;
        
      # rrd time check
      #sub rrd_time_in_range{
      #warn "TEST IN STACKING START $rrd";
      #warn "res:";
      #warn  rrd_time_in_range( $time_type, $rrd ); 
      next if (! rrd_time_in_range( $time_type, $rrd ));
      #warn "TEST IN STACKING END $rrd"; 
      # possibly add activity check, if not active in time-range of graph -> next rrd looped here
      my $label   = get_formatted_label_val("$name");
       
      my $clean_tab_code = $tab_code;
      $clean_tab_code =~ s/ /_/g;
      
      
      $cmd_def .= " DEF:name-$metric_counter-$rrd_metricname=\"$rrd\":$rrd_metricname:AVERAGE";
      $cmd_def .= "\n";
    
      $cmd_cdef .= " CDEF:view-$metric_counter-$rrd_metricname=name-$metric_counter-$rrd_metricname,$legend->{denom},/";
      $cmd_cdef .= "\n";
      

      #-----------------------------------------------------------------------------------------------
      my $cmd_printer = "";
     # if ( $legend->{graph_type} eq "LINE1" ) {
     #   $cmd_printer .= " LINE1:view-$metric_counter-$rrd_metricname" . "$color:\" $label\"";
     # $cmd_printer .= "\n";
     # }
     # else {
        if ( $metric_counter == $number_to_stacking ) {
          $cmd_printer .= " AREA:view-$metric_counter-$rrd_metricname" . "$color:\" $label\"";
          $cmd_printer .= "\n";
        }
        else {
          $cmd_printer .= " STACK:view-$metric_counter-$rrd_metricname" . "$color:\" $label\"";
          $cmd_printer .= "\n";
        }
     # }
    
      $cmd_printer .= " GPRINT:view-$metric_counter-$rrd_metricname:AVERAGE:\" %6.".$legend->{decimals}."lf\"";
      $cmd_printer .= "\n";
      $cmd_printer .= " GPRINT:view-$metric_counter-$rrd_metricname:MAX:\" %6.".$legend->{decimals}."lf\"";
      $cmd_printer .= "\n";
      $cmd_printer .= " PRINT:view-$metric_counter-$rrd_metricname:AVERAGE:\" %6.".$legend->{decimals}."lf $del $item $del $label $del $color $del $clean_tab_code\""; 
      $cmd_printer .= "\n";
      $cmd_printer .= " PRINT:view-$metric_counter-$rrd_metricname:MAX:\" %6.".$legend->{decimals}."lf $del asd $del $label $del cur_hos\"";
      $cmd_printer .= "\n";
      $cmd_printer .= " COMMENT:\\n";
      $cmd_printer .= "\n";
      #-----------------------------------------------------------------------------------------------
      $cmd_legend .= $cmd_printer;
    
      $metric_counter++;
    
    }
  }
  
  $rrd       = $rrd_list[0];
  ( $lapdate , $rrd ) = group_latest_update(@rrd_list);
  
  my %command_hash = (
    filename        => $rrd,     
    header          => "$legend->{header}", 
    reduced_header  => "$legend->{header}", 
    cmd_params      => $cmd_params,
    cmd_def         => $cmd_def, 
    cmd_cdef        => $cmd_cdef,           
    cmd_legend      => $cmd_legend,        
    cmd_vlabel      => "$legend->{v_label}"
  );

  return \%command_hash;

}



sub graph_views {
  my $acl_check  = shift;
# change to list
  my $host       = shift;
  my $server     = shift;
  my $type       = shift;
  my $item       = shift;
  my $colors_ref = shift;
  
  my $color;
  my $metric_counter = 0;
  
  my $console_name = "$acl_check";
  #warn "INPUT PARAMETERS GVIEWS: acl_check $acl_check HOST $host server $server type $type item $item colors_ref $colors_ref";

  my $rrd;
  my $cmd_params = my $cmd_legend = my $cmd_cdef = my $cmd_def = "";

  # PAGES
  my %type_tab_name_metric = give_type_tab_name_metric();
    
  #-----------------------------------------------------------------------------------------------
  
  my %translate_type = (
      "pep2_pool" => "Pools",
      "pep2_system" => "Systems");
  #$type = 'pep2_system';
  
  my $type_use = $translate_type{$type}; 
  
  my @rrd_list = ("${inputdir}/data/PEP2/$console_name/${type_use}_${host}.rrd"); 
  $rrd       = $rrd_list[0];
  my $lapdate;
  ( $lapdate , $rrd ) = group_latest_update(@rrd_list);

  #-----------------------------------------------------------------------------------------------
  
  my $tab_code;
  
  if ($item =~ /(.+)__(.+)$/){
    $tab_code = $2;
  }
  else{
    $tab_code = "";
  }
  #$tab_code = 'cmc_system'; 
  
  my @named_metrics;
  @named_metrics = keys %{ $type_tab_name_metric{$type}{$tab_code} };
  @named_metrics = sort { lc($a) cmp lc($b) } @named_metrics;
  #warn "LEGEND TAB CODE: $tab_code"; 
  my $legend = graph_legend($tab_code);
  
  #-----------------------------------------------------------------------------------------------
  
  $cmd_params .= " --lower-limit=0.00";
  $cmd_params .= " --alt-y-grid";
  $cmd_legend .= " COMMENT:\\n";
  
  my %named_metric_color = (
    'Available' => '#00FF00', 
    'Base' => '#000000', 
    'Installed' => '#00008B', 
    'Total' => '#808080',
    'Utilized' => '#FF0000',
  );
  my $color_counter = 0;

  for $rrd (@rrd_list){ 
    for my $named_metric (@named_metrics) {
      my $rrd_metricname = $type_tab_name_metric{$type}{$tab_code}{$named_metric};
      
      if (defined $named_metric_color{$named_metric}){
        $color = $named_metric_color{$named_metric};
      }else{
        $color = get_color( $colors_ref, $color_counter );
        $color_counter++;
      }
      
      my $label   = get_formatted_label_val("$named_metric");
       
      my $clean_tab_code = $tab_code;
      $clean_tab_code =~ s/ /_/g;
      
      
      $cmd_def .= " DEF:name-$metric_counter-$rrd_metricname=\"$rrd\":$rrd_metricname:AVERAGE";
      $cmd_def .= "\n";
    
      $cmd_cdef .= " CDEF:view-$metric_counter-$rrd_metricname=name-$metric_counter-$rrd_metricname,$legend->{denom},/";
      $cmd_cdef .= "\n";
      

      #-----------------------------------------------------------------------------------------------
      my $cmd_printer = "";
      
      if ( "$named_metric" eq 'Installed' && $item =~ /pep2_system/ && !($item =~ /memory/)){
          $cmd_printer .= " LINE1:view-$metric_counter-$rrd_metricname" . "#FFFFFF:\" $label\":skipscale";
          $cmd_printer .= "\n";
    
      }
      else{
      
        if ( $legend->{graph_type} eq "LINE1" ) {
          $cmd_printer .= " LINE1:view-$metric_counter-$rrd_metricname" . "$color:\" $label\"";
          $cmd_printer .= "\n";
        }
        else {
          if ( $metric_counter == 0 ) {
            $cmd_printer .= " AREA:view-$metric_counter-$rrd_metricname" . "$color:\" $label\"";
            $cmd_printer .= "\n";
          }
          else {
            $cmd_printer .= " STACK:view-$metric_counter-$rrd_metricname" . "$color:\" $label\"";
            $cmd_printer .= "\n";
          }
        }
      }
    
      $cmd_printer .= " GPRINT:view-$metric_counter-$rrd_metricname:AVERAGE:\" %6.".$legend->{decimals}."lf\"";
      $cmd_printer .= "\n";
      $cmd_printer .= " GPRINT:view-$metric_counter-$rrd_metricname:MAX:\" %6.".$legend->{decimals}."lf\"";
      $cmd_printer .= "\n";
      if ( "$named_metric" eq 'Installed' && $item =~ /pep2_system/ && !($item =~ /memory/) ){
        $cmd_printer .= " PRINT:view-$metric_counter-$rrd_metricname:AVERAGE:\" %6.".$legend->{decimals}."lf $del  $del $label $del $del $clean_tab_code\""; 
        $cmd_printer .= "\n";
      }
      else{
        $cmd_printer .= " PRINT:view-$metric_counter-$rrd_metricname:AVERAGE:\" %6.".$legend->{decimals}."lf $del $item $del $label $del $color $del $clean_tab_code\""; 
        $cmd_printer .= "\n";
      }
      $cmd_printer .= " PRINT:view-$metric_counter-$rrd_metricname:MAX:\" %6.".$legend->{decimals}."lf $del asd $del $label $del cur_hos\"";
      $cmd_printer .= "\n";
      $cmd_printer .= " COMMENT:\\n";
      $cmd_printer .= "\n";
      #-----------------------------------------------------------------------------------------------
      $cmd_legend .= $cmd_printer;
    
      $metric_counter++;
    
    }
  }
  $rrd       = $rrd_list[0];
  ( $lapdate , $rrd ) = group_latest_update(@rrd_list);
  my %command_hash = (
    filename        => $rrd,     
    header          => "$legend->{header}", 
    reduced_header  => "$legend->{header}", 
    cmd_params      => $cmd_params,
    cmd_def         => $cmd_def, 
    cmd_cdef        => $cmd_cdef,           
    cmd_legend      => $cmd_legend,        
    cmd_vlabel      => "$legend->{v_label}"
  );

  return \%command_hash;

}

sub get_colors {
  
  my @colors = ( "#FF0000", "#0000FF", "#FFFF00", "#00FFFF", "#FFA500", "#00FF00", "#808080", "#1CE6FF", "#FF34FF", "#FF4A46", "#008941", "#006FA6", "#A30059", "#7A4900", "#0000A6", "#63FFAC", "#B79762", "#004D43", "#8FB0FF", "#997D87", "#5A0007", "#809693", "#1B4400", "#4FC601", "#3B5DFF", "#4A3B53", "#FF2F80", "#61615A", "#BA0900", "#6B7900", "#00C2A0", "#FFAA92", "#FF90C9", "#B903AA", "#D16100", "#000035", "#7B4F4B", "#A1C299", "#300018", "#0AA6D8", "#013349", "#00846F", "#372101", "#FFB500", "#C2FFED", "#A079BF", "#CC0744", "#C0B9B2", "#C2FF99", "#001E09", "#00489C", "#6F0062", "#0CBD66", "#EEC3FF", "#456D75", "#B77B68", "#7A87A1", "#788D66", "#885578", "#FAD09F", "#FF8A9A", "#D157A0", "#BEC459", "#456648", "#0086ED", "#886F4C", "#34362D", "#B4A8BD", "#00A6AA", "#452C2C", "#636375", "#A3C8C9", "#FF913F", "#938A81", "#575329", "#00FECF", "#B05B6F", "#8CD0FF", "#3B9700", "#04F757", "#C8A1A1", "#1E6E00", "#7900D7", "#A77500", "#6367A9", "#A05837", "#6B002C", "#772600", "#D790FF", "#9B9700", "#549E79", "#FFF69F", "#201625", "#72418F", "#BC23FF", "#99ADC0", "#3A2465", "#922329", "#5B4534", "#FDE8DC", "#404E55", "#0089A3", "#CB7E98", "#A4E804", "#324E72", "#6A3A4C", "#83AB58", "#001C1E", "#D1F7CE", "#004B28", "#C8D0F6", "#A3A489", "#806C66", "#222800", "#BF5650", "#E83000", "#66796D", "#DA007C", "#FF1A59", "#8ADBB4", "#1E0200", "#5B4E51", "#C895C5", "#320033", "#FF6832", "#66E1D3", "#CFCDAC", "#D0AC94", "#7ED379", "#012C58", "#7A7BFF", "#D68E01", "#353339", "#78AFA1", "#FEB2C6", "#75797C", "#837393", "#943A4D", "#B5F4FF", "#D2DCD5", "#9556BD", "#6A714A", "#001325", "#02525F", "#0AA3F7", "#E98176", "#DBD5DD", "#5EBCD1", "#3D4F44", "#7E6405", "#02684E", "#962B75", "#8D8546", "#9695C5", "#E773CE", "#D86A78", "#3E89BE", "#CA834E", "#518A87", "#5B113C", "#55813B", "#E704C4", "#00005F", "#A97399", "#4B8160", "#59738A", "#FF5DA7", "#F7C9BF", "#643127", "#513A01", "#6B94AA", "#51A058", "#A45B02", "#1D1702", "#E20027", "#E7AB63", "#4C6001", "#9C6966", "#64547B", "#97979E", "#006A66", "#391406", "#F4D749", "#0045D2", "#006C31", "#DDB6D0", "#7C6571", "#9FB2A4", "#00D891", "#15A08A", "#BC65E9", "#FFFFFE", "#C6DC99", "#203B3C", "#671190", "#6B3A64", "#F5E1FF", "#FFA0F2", "#CCAA35", "#374527", "#8BB400", "#797868", "#C6005A", "#3B000A", "#C86240", "#29607C", "#402334", "#7D5A44", "#CCB87C", "#B88183", "#AA5199", "#B5D6C3", "#A38469", "#9F94F0", "#A74571", "#B894A6", "#71BB8C", "#00B433", "#789EC9", "#6D80BA", "#953F00", "#5EFF03", "#E4FFFC", "#1BE177", "#BCB1E5", "#76912F", "#003109", "#0060CD", "#D20096", "#895563", "#29201D", "#5B3213", "#A76F42", "#89412E", "#1A3A2A", "#494B5A", "#A88C85", "#F4ABAA", "#A3F3AB", "#00C6C8", "#EA8B66", "#958A9F", "#BDC9D2", "#9FA064", "#BE4700", "#658188", "#83A485", "#453C23", "#47675D", "#3A3F00", "#061203", "#DFFB71", "#868E7E", "#98D058", "#6C8F7D", "#D7BFC2", "#3C3E6E", "#D83D66", "#2F5D9B", "#6C5E46", "#D25B88", "#5B656C", "#00B57F", "#545C46", "#866097", "#365D25", "#252F99", "#00CCFF", "#674E60", "#FC009C", "#92896B" );
  return @colors;
}

1;

package Power_cmc_Power;

use strict;
use warnings;

use HTTP::Request::Common;
use LWP;
use Data::Dumper;
use JSON;
use POSIX qw(strftime ceil);
use Date::Parse;
use Time::Local;
use JSON qw(decode_json);
use Power_cmc_Xormon;

require "xml.pl";

my $hw_type = 'power';

# For debug purpouses, NG can simulate a big environment by duplicating the current environment LPARs. If set to 100, it will create 100 copies of all current LPARs.
my $lpar_multiplicator = 1;

my $convertValues ={
  'ConfigurableSystemMemory' => 1048576,
  'ConfiguredMirroredMemory' => 1048576,
  'CurrentAvailableMirroredMemory' => 1048576,
  'CurrentAvailableSystemMemory' => 1048576,
  'CurrentMirroredMemory' => 1048576,
  'DeconfiguredSystemMemory' => 1048576,
  'InstalledSystemMemory' => 1048576,
  'MemoryUsedByHypervisor' => 1048576,
  'PendingAvailableSystemMemory' => 1048576,
  'assignedMem' => 1048576,
  'configurableMem' => 1048576,
  'assignedMemToLpars' => 1048576,
  'availableMem' => 1048576,
  'totalMem' => 1048576,
  'mappedIOMemToLpars' => 1048576,
  'totalIOMem' => 1048576,
  'assignedMemToLpars' => 1048576,
  'assignedMemToSysFirmware' => 1048576,
  'logicalMem' => 1048576,
  'backedPhysicalMem' => 1048576,
};

sub ManagedSystemPerformanceToData {
  my ($self, $sample, $server_uid, $architecture, $status, $architecture_lpar_check, $sharedMemoryPools, $sharedProcessorPools) = @_;
  my $link  = $sample->{'link'};
  my $processedJsonContent = $self->getJsonContent ($link);

  my $bundle_size = 100;

  my $data_out = {};
  
  if (!%{$processedJsonContent}){
    Power_cmc_Xormon::error("API Error : " . "No SERVERs processed metrics JSONs found for $server_uid");
  }

  for (@{ $processedJsonContent->{'systemUtil'}{'utilSamples'} }){
    my $serverSample = $_;
    my $timeStamp = str2time ( $serverSample->{'sampleInfo'}{'timeStamp'} );
    
    #ManagedSystem Performnace
    my $serverUtil = $serverSample->{'serverUtil'};
    my $systemFirmwareUtil = $serverSample->{'systemFirmwareUtil'};
    my $serverProcessor = $serverUtil->{'processor'};
    my $serverMemory = $serverUtil->{'memory'};
    my $serverSharedMemoryPool = $serverUtil->{'sharedMemoryPool'};
    my $serverSharedProcessorPool = $serverUtil->{'sharedProcessorPool'};
    my $serverNetwork = $serverUtil->{'network'};
    #my $serverPhysicalProcessorPool = $serverUtil->{'physicalProcessorPool'};

    # Server Physical Processor Pool
    #$data_out->{$hw_type}{'server'}{$server_uid}{$timeStamp}{'assignedProcUnitsPhysicalProcessor'} = defined $serverPhysicalProcessorPool->{'assignedProcUnits'}[0] ? $serverPhysicalProcessorPool->{'assignedProcUnits'}[0] : undef;
    #$data_out->{$hw_type}{'server'}{$server_uid}{$timeStamp}{'utilizedProcUnitsPhysicalProcessor'} = defined $serverPhysicalProcessorPool->{'utilizedProcUnits'}[0] ? $serverPhysicalProcessorPool->{'utilizedProcUnits'}[0] : undef;
    #$data_out->{$hw_type}{'server'}{$server_uid}{$timeStamp}{'availableProcUnitsPhysicalProcessor'} = defined $serverPhysicalProcessorPool->{'availableProcUnits'}[0] ? $serverPhysicalProcessorPool->{'availableProcUnits'}[0] : undef;
    #$data_out->{$hw_type}{'server'}{$server_uid}{$timeStamp}{'configuredProcUnitsPhysicalProcessor'} = defined $serverPhysicalProcessorPool->{'configuredProcUnits'}[0] ? $serverPhysicalProcessorPool->{'configuredProcUnits'}[0] : undef;
    #$data_out->{$hw_type}{'server'}{$server_uid}{$timeStamp}{'borrowedProcUnitsPhysicalProcessor'} = defined $serverPhysicalProcessorPool->{'borrowedProcUnits'}[0] ? $serverPhysicalProcessorPool->{'borrowedProcUnits'}[0] : undef;

    # Server Processor
    $data_out->{$hw_type}{'server'}{$server_uid}{$timeStamp}{'systemFirmwareUtilUtilizedProcUnits'} = defined $systemFirmwareUtil->{'utilizedProcUnits'}[0] ? $systemFirmwareUtil->{'utilizedProcUnits'}[0] : undef;
    $data_out->{$hw_type}{'server'}{$server_uid}{$timeStamp}{'utilizedProcUnits'} = defined $serverProcessor->{'utilizedProcUnits'}[0] ? $serverProcessor->{'utilizedProcUnits'}[0] : undef;
    $data_out->{$hw_type}{'server'}{$server_uid}{$timeStamp}{'configurableProcUnits'} = defined $serverProcessor->{'configurableProcUnits'}[0] ? $serverProcessor->{'configurableProcUnits'}[0] : undef;
    $data_out->{$hw_type}{'server'}{$server_uid}{$timeStamp}{'availableProcUnits'} = defined $serverProcessor->{'availableProcUnits'}[0] ? $serverProcessor->{'availableProcUnits'}[0] : undef;
    $data_out->{$hw_type}{'server'}{$server_uid}{$timeStamp}{'totalProcUnits'} = defined $serverProcessor->{'totalProcUnits'}[0] ? $serverProcessor->{'totalProcUnits'}[0] : undef;
    # create these metrics manually and store to DB. They are not present in the HMC API.
    $data_out->{$hw_type}{'server'}{$server_uid}{$timeStamp}{'assignedProcUnits'} = defined $serverProcessor->{'configurableProcUnits'}[0] ? $serverProcessor->{'configurableProcUnits'}[0] - $serverProcessor->{'availableProcUnits'}[0] : undef;
    $data_out->{$hw_type}{'server'}{$server_uid}{$timeStamp}{'assignedProcUnitsPercent'} = defined $data_out->{$hw_type}{'server'}{$server_uid}{$timeStamp}{'assignedProcUnits'} ? sprintf("%d", 100 * ( $serverProcessor->{'utilizedProcUnits'}[0] / $data_out->{$hw_type}{'server'}{$server_uid}{$timeStamp}{'assignedProcUnits'} ) ) : undef;
    $data_out->{$hw_type}{'server'}{$server_uid}{$timeStamp}{'totalProcUnitsPercent'} = defined $serverProcessor->{'totalProcUnits'}[0] ? sprintf("%d", 100 * ( $serverProcessor->{'utilizedProcUnits'}[0] / $serverProcessor->{'totalProcUnits'}[0] ) ) : undef;
    # Server Memory
    # convert MiB to bytes to be stored in DB.
    $data_out->{$hw_type}{'server'}{$server_uid}{$timeStamp}{'systemFirmwareUtilAssignedMem'} = defined $systemFirmwareUtil->{'assignedMem'}[0] ? sprintf("%d", $systemFirmwareUtil->{'assignedMem'}[0] * $convertValues->{'assignedMem'}) : undef;
    $data_out->{$hw_type}{'server'}{$server_uid}{$timeStamp}{'configurableMem'} = defined $serverMemory->{'configurableMem'}[0] ? sprintf("%d", $serverMemory->{'configurableMem'}[0] * $convertValues->{'configurableMem'}) : undef;
    $data_out->{$hw_type}{'server'}{$server_uid}{$timeStamp}{'assignedMemToLpars'} = defined $serverMemory->{'assignedMemToLpars'}[0] ? sprintf("%d", $serverMemory->{'assignedMemToLpars'}[0] * $convertValues->{'assignedMemToLpars'}) : undef;
    $data_out->{$hw_type}{'server'}{$server_uid}{$timeStamp}{'availableMem'} = defined $serverMemory->{'availableMem'}[0] ? sprintf("%d", $serverMemory->{'availableMem'}[0] * $convertValues->{'availableMem'}) : undef;
    $data_out->{$hw_type}{'server'}{$server_uid}{$timeStamp}{'totalMem'} = defined $serverMemory->{'totalMem'}[0] ? sprintf("%d", $serverMemory->{'totalMem'}[0] * $convertValues->{'totalMem'}) : undef;

    # MAX 
    $data_out->{$hw_type}{'server'}{$server_uid}{$timeStamp}{'utilizedProcUnitsMax'} = defined $serverProcessor->{'utilizedProcUnits'}[0] ? $serverProcessor->{'utilizedProcUnits'}[0] : undef;
    $data_out->{$hw_type}{'server'}{$server_uid}{$timeStamp}{'totalProcUnitsMax'} = defined $serverProcessor->{'totalProcUnits'}[0] ? $serverProcessor->{'totalProcUnits'}[0] : undef;
    $data_out->{$hw_type}{'server'}{$server_uid}{$timeStamp}{'totalProcUnitsPercentMax'} = defined $serverProcessor->{'totalProcUnits'}[0] ? sprintf("%d", 100 * ( $serverProcessor->{'utilizedProcUnits'}[0] / $serverProcessor->{'totalProcUnits'}[0] ) ) : undef;
    

    for (@{$serverNetwork->{'headapters'}}){
      my $adapter = $_;
      for (@{$adapter->{'physicalPorts'}}){
        my $port = $_;
        my $port_uid = $port->{'physicalLocation'};
        $data_out->{$hw_type}{'hea'}{$port_uid}{$timeStamp}{'sentBytes'} = sprintf("%d", $port->{'sentBytes'}[0]);
        $data_out->{$hw_type}{'hea'}{$port_uid}{$timeStamp}{'receivedBytes'} = sprintf("%d", $port->{'receivedBytes'}[0]);
        $data_out->{$hw_type}{'hea'}{$port_uid}{$timeStamp}{'sentPackets'} = sprintf("%d", $port->{'sentPackets'}[0]);
        $data_out->{$hw_type}{'hea'}{$port_uid}{$timeStamp}{'receivedPackets'} = sprintf("%d", $port->{'receivedPackets'}[0]);
        #$data_out->{$hw_type}{'hea'}{$port_uid}{$timeStamp}{'id'} = $port->{'id'};
        #$data_out->{$hw_type}{'hea'}{$port_uid}{$timeStamp}{'type'} = $port->{'type'};

        #architecture hea
        if (!defined $architecture_lpar_check->{$port_uid}){
          my $label = $port_uid;
          my (@physLoc) = split('\.', $port->{'physicalLocation'});
          $label    = $physLoc[-1] ? "$label ($physLoc[-1])" : $label;
          my %port_arch = (
              "item_id" => $port_uid,
              "label" => $label,
              "hw_type" => $hw_type,
              "subsystem" => "hea",
              "parents" => [ $server_uid ],
              "hostcfg_id" => $self->{'hostcfg_id'}
          );
          push(@{$architecture}, \%port_arch);
          $architecture_lpar_check->{$port_uid} = 1;
        }
      }
    }

    for (@{$serverNetwork->{'sriovAdapters'}}){
      my $adapter = $_;
      for (@{$adapter->{'physicalPorts'}}){
        my $port = $_;
        my $port_uid = $port->{'physicalLocation'};
        $data_out->{$hw_type}{'sriovphysical'}{$port_uid}{$timeStamp}{'sentBytes'} = sprintf("%d", $port->{'sentBytes'}[0]);
        $data_out->{$hw_type}{'sriovphysical'}{$port_uid}{$timeStamp}{'receivedBytes'} = sprintf("%d", $port->{'receivedBytes'}[0]);
        $data_out->{$hw_type}{'sriovphysical'}{$port_uid}{$timeStamp}{'sentPackets'} = sprintf("%d", $port->{'sentPackets'}[0]);
        $data_out->{$hw_type}{'sriovphysical'}{$port_uid}{$timeStamp}{'receivedPackets'} = sprintf("%d", $port->{'receivedPackets'}[0]);
        #$data_out->{$hw_type}{'sriovphysical'}{$port_uid}{$timeStamp}{'id'} = $port->{'id'};

        #architecture sriov physical
        if (!defined $architecture_lpar_check->{$port_uid}){
          my %port_arch = (
              "item_id" => $port_uid,
              "label" => $port_uid,
              "hw_type" => $hw_type,
              "subsystem" => "sriovphysical",
              "parents" => [ $server_uid ],
              "hostcfg_id" => $self->{'hostcfg_id'}
          );
          push(@{$architecture}, \%port_arch);
          $architecture_lpar_check->{$port_uid} = 1;
        }
      }
    }

    # Server Shared Memory Pool
    # convert MiB to bytes to be stored in DB.
    
    for (@{$serverSharedMemoryPool}){
      next;
      my $smp = $_;
      my $smp_id = $smp->{'id'};

      my $PoolUID = $sharedMemoryPools->{$server_uid}{'SharedMemoryPool'}{$smp_id}{'uid'};
      my $PoolID  = $smp_id;

      if ( ! defined $PoolUID ){ next; }

      $data_out->{$hw_type}{'mempool'}{$PoolUID}{$timeStamp}{'mappedIOMemToLpars'} = defined $smp->{'mappedIOMemToLpars'}[0] ? $smp->{'mappedIOMemToLpars'}[0] * $convertValues->{'mappedIOMemToLpars'} : undef;
      $data_out->{$hw_type}{'mempool'}{$PoolUID}{$timeStamp}{'totalMem'} = defined $smp->{'totalMem'}[0] ?  $smp->{'totalMem'}[0] * $convertValues->{'totalMem'} : undef;
      $data_out->{$hw_type}{'mempool'}{$PoolUID}{$timeStamp}{'totalIOMem'} = defined $smp->{'totalIOMem'}[0] ?  $smp->{'totalIOMem'}[0] * $convertValues->{'totalIOMem'} : undef;
      $data_out->{$hw_type}{'mempool'}{$PoolUID}{$timeStamp}{'assignedMemToLpars'} = defined $smp->{'assignedMemToLpars'}[0] ?  $smp->{'assignedMemToLpars'}[0] * $convertValues->{'assignedMemToLpars'} : undef;
      $data_out->{$hw_type}{'mempool'}{$PoolUID}{$timeStamp}{'assignedMemToSysFirmware'} = defined $smp->{'assignedMemToSysFirmware'}[0] ?  $smp->{'assignedMemToSysFirmware'}[0] * $convertValues->{'assignedMemToSysFirmware'} : undef;

      if (!defined $architecture_lpar_check->{$PoolUID}){
        #architecture shared memory pool
        my %smp_arch = (
            "item_id" => $PoolUID,
            "label" => "Shared Memory Pool",
            "hw_type" => $hw_type,
            "subsystem" => "mempool",
            "parents" => [$server_uid],
            "hostcfg_id" => $self->{'hostcfg_id'}
        );
        $architecture_lpar_check->{$PoolUID} = 1;
        push(@{$architecture}, \%smp_arch);
      }
    }

    ## Server Shared Processor Pool
    #for (@{$serverSharedProcessorPool}){ 
    #  my $spp = $_;
    #  my $spp_id = $spp->{'id'};

    #  my $PoolUID = $sharedProcessorPools->{$server_uid}{'SharedProcessorPool'}{$spp_id}{'uid'};
    #  my $PoolName = $sharedProcessorPools->{$server_uid}{'SharedProcessorPool'}{$spp_id}{'label'};
    #  my $PoolID  = $spp_id;

    #          
    #  #$data_out->{$hw_type}{'pool'}{$PoolUID}{$timeStamp}{'id'} = defined $spp->{'id'} ? $spp->{'id'} : undef;
    #  $data_out->{$hw_type}{'pool'}{$PoolUID}{$timeStamp}{'configuredProcUnits'} = defined $spp->{'configuredProcUnits'}[0] ? $spp->{'configuredProcUnits'}[0] : undef;
    #  $data_out->{$hw_type}{'pool'}{$PoolUID}{$timeStamp}{'borrowedProcUnits'} = defined $spp->{'borrowedProcUnits'}[0] ? $spp->{'borrowedProcUnits'}[0] : undef;
    #  $data_out->{$hw_type}{'pool'}{$PoolUID}{$timeStamp}{'assignedProcUnits'} = defined $spp->{'assignedProcUnits'}[0] ? $spp->{'assignedProcUnits'}[0] : undef;
    #  $data_out->{$hw_type}{'pool'}{$PoolUID}{$timeStamp}{'utilizedProcUnits'} = defined $spp->{'utilizedProcUnits'}[0] ? $spp->{'utilizedProcUnits'}[0] : undef;
    #  $data_out->{$hw_type}{'pool'}{$PoolUID}{$timeStamp}{'availableProcUnits'} = defined $spp->{'availableProcUnits'}[0] ? $spp->{'availableProcUnits'}[0] : undef;
    #  $data_out->{$hw_type}{'pool'}{$PoolUID}{$timeStamp}{'totalUtilizedProcUnitsPercent'} = (defined $data_out->{$hw_type}{'pool'}{$PoolUID}{$timeStamp}{'utilizedProcUnits'} && $data_out->{$hw_type}{'pool'}{$PoolUID}{$timeStamp}{'assignedProcUnits'} != 0) ? sprintf("%d", (100 * $data_out->{$hw_type}{'pool'}{$PoolUID}{$timeStamp}{'utilizedProcUnits'} / $data_out->{$hw_type}{'pool'}{$PoolUID}{$timeStamp}{'assignedProcUnits'})): undef;
    #  
    #  #MAX 
    #  $data_out->{$hw_type}{'pool'}{$PoolUID}{$timeStamp}{'utilizedProcUnitsMax'} = defined $spp->{'utilizedProcUnits'}[0] ? $spp->{'utilizedProcUnits'}[0] : undef;
    #  $data_out->{$hw_type}{'pool'}{$PoolUID}{$timeStamp}{'totalUtilizedProcUnitsPercentMax'} = (defined $data_out->{$hw_type}{'pool'}{$PoolUID}{$timeStamp}{'utilizedProcUnits'} && $data_out->{$hw_type}{'pool'}{$PoolUID}{$timeStamp}{'assignedProcUnits'} != 0) ? sprintf("%d", (100 * $data_out->{$hw_type}{'pool'}{$PoolUID}{$timeStamp}{'utilizedProcUnits'} / $data_out->{$hw_type}{'pool'}{$PoolUID}{$timeStamp}{'assignedProcUnits'})): undef;
    #  
    #  if (!defined $architecture_lpar_check->{$PoolUID}){
    #    #architecture shared processor pool
    #    my $label = $PoolName ? $PoolName : $PoolUID;
    #    my %spp_arch = (
    #        "item_id" => $PoolUID,
    #        "label" => $label,
    #        "hw_type" => $hw_type,
    #        "subsystem" => "pool",
    #        "parents" => [$server_uid],
    #        "hostcfg_id" => $self->{'hostcfg_id'}
    #    );
    #    $architecture_lpar_check->{$PoolUID} = 1;
    #    push(@{$architecture}, \%spp_arch);
    #  }
    #}
    
    #ViosUtil Performance
    my $viosUtil = $serverSample->{'viosUtil'};

    for (@{$viosUtil}){
      my $lpar = $_;
      my $lpar_uid = $lpar->{'uuid'};
      my $lpar_label = $lpar->{'name'};
      my $proc = $lpar->{'processor'};
      my $mem = $lpar->{'memory'};
      my $stor = $lpar->{'storage'};    
      my $netw = $lpar->{'network'};    
   

      # Cores assigned to the VM.
      # Tricky one is the currentVirtualProcessors - if the currentVirtualProcessor is not defined (or 0), then the LPAR is dedicated, so the entitledProcUnits = currentVirtualProcessors
      #$data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'currentVirtualProcessors'} = defined $proc->{'currentVirtualProcessors'}[0] && $proc->{'currentVirtualProcessors'}[0] > 0 ? sprintf("%d", $proc->{'currentVirtualProcessors'}[0]) : sprintf("%d", $proc->{'entitledProcUnits'}[0]);
      $data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'maxVirtualProcessors'} = defined $proc->{'maxVirtualProcessors'}[0] ? sprintf("%d", $proc->{'maxVirtualProcessors'}[0]) : undef;
      
      $data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'entitledProcUnits'} = defined $proc->{'entitledProcUnits'}[0] ? $proc->{'entitledProcUnits'}[0] : undef;
      $data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'utilizedProcUnits'} = defined $proc->{'utilizedProcUnits'}[0] ? $proc->{'utilizedProcUnits'}[0] : undef;
      $data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'maxProcUnits'} = defined $proc->{'maxProcUnits'}[0] ? defined $proc->{'maxProcUnits'}[0] : undef;
      $data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'logicalMem'} = defined $mem->{'logicalMem'}[0] ? sprintf("%d", $mem->{'logicalMem'}[0] * $convertValues->{'logicalMem'}) : undef;
      $data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'backedPhysicalMem'} = defined $mem->{'backedPhysicalMem'}[0] ? sprintf("%d", $mem->{'backedPhysicalMem'}[0]* $convertValues->{'backedPhysicalMem'}) : undef;
      #create these metric for xormon
      $data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'totalProcUnitsPercent'} = (defined $data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'maxVirtualProcessors'} && $data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'maxVirtualProcessors'} != 0) ? sprintf("%d", (100 * $data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'utilizedProcUnits'} / $data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'maxVirtualProcessors'})) : undef;
      $data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'entitledProcUnitsPercent'} = (defined $data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'entitledProcUnits'} && $data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'entitledProcUnits'} != 0) ? sprintf("%d", (100 * $data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'utilizedProcUnits'} / $data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'entitledProcUnits'})) : undef;

      # MAX
      $data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'utilizedProcUnitsMax'} = defined $proc->{'utilizedProcUnits'}[0] ? $proc->{'utilizedProcUnits'}[0] : undef;
      $data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'totalProcUnitsPercentMax'} = (defined $data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'maxVirtualProcessors'} && $data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'maxVirtualProcessors'} != 0) ? sprintf("%d", (100 * $data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'utilizedProcUnits'} / $data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'maxVirtualProcessors'})) : undef;    

      # Do not store there metrics for now. it can be useful in future
      #$data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'utilizedCappedProcUnits'} = $proc->{'utilizedCappedProcUnits'}[0];
      #$data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'utilizedUncappedProcUnits'} = $proc->{'utilizedUncappedProcUnits'}[0];
      #$data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'idleProcUnits'} = $proc->{'idleProcUnits'}[0];
      #$data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'donatedProcUnits'} = $proc->{'donatedProcUnits'}[0];
      #$data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'timeSpentWaitingForDispatch'} = $proc->{'timeSpentWaitingForDispatch'}[0];
      #$data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'timePerInstructionExecution'} = $proc->{'timePerInstructionExecution'}[0];
      
      # sea 
      for (@{ $netw->{'sharedAdapters'} }){
        my $sea_adapter = $_;
        my $sea_adapter_uid = $sea_adapter->{'physicalLocation'};
        $data_out->{$hw_type}{'sea'}{$sea_adapter_uid}{$timeStamp}{'sentBytes'} = sprintf("%d", $sea_adapter->{'sentBytes'}[0]);
        $data_out->{$hw_type}{'sea'}{$sea_adapter_uid}{$timeStamp}{'receivedBytes'} = sprintf("%d", $sea_adapter->{'receivedBytes'}[0]);
        $data_out->{$hw_type}{'sea'}{$sea_adapter_uid}{$timeStamp}{'sentPackets'} = sprintf("%d", $sea_adapter->{'sentPackets'}[0]);
        $data_out->{$hw_type}{'sea'}{$sea_adapter_uid}{$timeStamp}{'receivedPackets'} = sprintf("%d", $sea_adapter->{'receivedPackets'}[0]);
        #$data_out->{$hw_type}{'sea'}{$sea_adapter_uid}{$timeStamp}{'id'} = $sea_adapter->{'id'};
        #$data_out->{$hw_type}{'sea'}{$sea_adapter_uid}{$timeStamp}{'type'} = $sea_adapter->{'type'};
        #$data_out->{$hw_type}{'sea'}{$sea_adapter_uid}{$timeStamp}{'transferredBytes'} = $sea_adapter->{'transferredBytes'}[0];
        #$data_out->{$hw_type}{'sea'}{$sea_adapter_uid}{$timeStamp}{'droppedPackets'} = $sea_adapter->{'droppedPackets'}[0];

        #architecture sea
        if (!defined $architecture_lpar_check->{$sea_adapter_uid}){
          my $label = $sea_adapter->{'id'} ? $sea_adapter->{'id'} : $sea_adapter_uid;
          my (@physLocParts) = split('\.', $sea_adapter->{'physicalLocation'});
          $label    = $physLocParts[-1] ? "$label ($physLocParts[-1])" : $label;
          
          my %sea_arch = (
              "item_id" => $sea_adapter_uid,
              "label" => $label,
              "hw_type" => $hw_type,
              "subsystem" => "sea",
              "parents" => [ $server_uid ],
              "hostcfg_id" => $self->{'hostcfg_id'}
          );
          push(@{$architecture}, \%sea_arch);
          $architecture_lpar_check->{$sea_adapter_uid} = 1;
        
        }
      }
      # genericAdapters
      for (@{ $netw->{'genericAdapters'} }){
        my $generic_adapter = $_;
        my $generic_adapter_uid = $generic_adapter->{'physicalLocation'};
        $data_out->{$hw_type}{'generic'}{$generic_adapter_uid}{$timeStamp}{'sentBytes'} = sprintf("%d", $generic_adapter->{'sentBytes'}[0]);
        $data_out->{$hw_type}{'generic'}{$generic_adapter_uid}{$timeStamp}{'receivedBytes'} = sprintf("%d", $generic_adapter->{'receivedBytes'}[0]);
        $data_out->{$hw_type}{'generic'}{$generic_adapter_uid}{$timeStamp}{'sentPackets'} = sprintf("%d", $generic_adapter->{'sentPackets'}[0]);
        $data_out->{$hw_type}{'generic'}{$generic_adapter_uid}{$timeStamp}{'receivedPackets'} = sprintf("%d", $generic_adapter->{'receivedPackets'}[0]);
        #$data_out->{$hw_type}{'generic'}{$generic_adapter_uid}{$timeStamp}{'id'} = $generic_adapter->{'id'};
        #$data_out->{$hw_type}{'generic'}{$generic_adapter_uid}{$timeStamp}{'type'} = $generic_adapter->{'type'};
        #$data_out->{$hw_type}{'generic'}{$generic_adapter_uid}{$timeStamp}{'transferredBytes'} = $generic_adapter->{'transferredBytes'}[0];
        #$data_out->{$hw_type}{'generic'}{$generic_adapter_uid}{$timeStamp}{'droppedPackets'} = $generic_adapter->{'droppedPackets'}[0];

        #architecture generic adapters
        if (!defined $architecture_lpar_check->{$generic_adapter_uid}){
          my $label = $generic_adapter->{'id'} ? $generic_adapter->{'id'} : $generic_adapter_uid;
          my (@physLoc) = split('\.', $generic_adapter->{'physicalLocation'});
          $label    = $physLoc[-1] ? "$label ($physLoc[-1])" : $label;
          my %generic_arch = (
              "item_id" => $generic_adapter_uid,
              "label" => $label,
              "hw_type" => $hw_type,
              "subsystem" => "generic",
              "parents" => [ $server_uid ],
              "hostcfg_id" => $self->{'hostcfg_id'}
          );
          push(@{$architecture}, \%generic_arch);
          $architecture_lpar_check->{$generic_adapter_uid} = 1;        
        }
      }
      # sriovLogicalPorts
      for (@{ $netw->{'sriovLogicalPorts'} }){
        my $port = $_;
        my $port_uid = $port->{'physicalLocation'};
        $data_out->{$hw_type}{'sriovlogical'}{$port_uid}{$timeStamp}{'sentBytes'} = sprintf("%d", $port->{'sentBytes'}[0]);
        $data_out->{$hw_type}{'sriovlogical'}{$port_uid}{$timeStamp}{'receivedBytes'} = sprintf("%d", $port->{'receivedBytes'}[0]);
        $data_out->{$hw_type}{'sriovlogical'}{$port_uid}{$timeStamp}{'sentPackets'} = sprintf("%d", $port->{'sentPackets'}[0]);
        $data_out->{$hw_type}{'sriovlogical'}{$port_uid}{$timeStamp}{'receivedPackets'} = sprintf("%d", $port->{'receivedPackets'}[0]);
        #architecture sriov logical ports
        if (!defined $architecture_lpar_check->{$port_uid}){
          my $label = $port->{'id'} ? $port->{'id'} : $port_uid;
          my (@physLoc) = split('\.', $port_uid);
          $label    = $physLoc[-1] ? "$label ($physLoc[-1])" : $label;
          my %arch = (
              "item_id" => $port_uid,
              "label" => $label,
              "hw_type" => $hw_type,
              "subsystem" => "sriovlogical",
              "parents" => [ $server_uid ],
              "hostcfg_id" => $self->{'hostcfg_id'}
          );
          push(@{$architecture}, \%arch);
          $architecture_lpar_check->{$port_uid} = 1;
        
        }
      }
      # virtualEthernetAdapters
      for (@{ $netw->{'virtualEthernetAdapters'} }){
        my $adapter = $_;
        my $adapter_uid = $adapter->{'physicalLocation'};
        $data_out->{$hw_type}{'virtualethernet'}{$adapter_uid}{$timeStamp}{'sentBytes'} = sprintf("%d", $adapter->{'sentBytes'}[0]);
        $data_out->{$hw_type}{'virtualethernet'}{$adapter_uid}{$timeStamp}{'receivedBytes'} = sprintf("%d", $adapter->{'receivedBytes'}[0]);
        $data_out->{$hw_type}{'virtualethernet'}{$adapter_uid}{$timeStamp}{'sentPackets'} = sprintf("%d", $adapter->{'sentPackets'}[0]);
        $data_out->{$hw_type}{'virtualethernet'}{$adapter_uid}{$timeStamp}{'receivedPackets'} = sprintf("%d", $adapter->{'receivedPackets'}[0]);

        $data_out->{$hw_type}{'virtualethernet'}{$adapter_uid}{$timeStamp}{'sentPhysicalBytes'} = sprintf("%d", $adapter->{'sentPhysicalBytes'}[0]);
        $data_out->{$hw_type}{'virtualethernet'}{$adapter_uid}{$timeStamp}{'receivedPhysicalBytes'} = sprintf("%d", $adapter->{'receivedPhysicalBytes'}[0]);
        $data_out->{$hw_type}{'virtualethernet'}{$adapter_uid}{$timeStamp}{'sentPhysicalPackets'} = sprintf("%d", $adapter->{'sentPhysicalPackets'}[0]);
        $data_out->{$hw_type}{'virtualethernet'}{$adapter_uid}{$timeStamp}{'receivedPhysicalPackets'} = sprintf("%d", $adapter->{'receivedPhysicalPackets'}[0]);

        #architecture virtual ethernet adapters
        if (!defined $architecture_lpar_check->{$adapter_uid}){
          my $label = $adapter->{'id'} ? $adapter->{'id'} : $adapter_uid;
          my (@physLoc) = split('\.', $adapter->{'physicalLocation'});
          $label    = $physLoc[-1] ? "$label ($physLoc[-1])" : $label;
          my %arch = (
              "item_id" => $adapter_uid,
              "label" => $adapter->{'id'},
              "hw_type" => $hw_type,
              "subsystem" => "virtualethernet",
              "parents" => [ $server_uid ],
              "hostcfg_id" => $self->{'hostcfg_id'}
          );
          push(@{$architecture}, \%arch);
          $architecture_lpar_check->{$adapter_uid} = 1;
        
        }
      }
      #fiberChannelAdapters
      for (@{ $stor->{'fiberChannelAdapters'} }){
        my $adapter = $_;
        my $adapter_uid = $adapter->{'physicalLocation'};
        $data_out->{$hw_type}{'fiber'}{$adapter_uid}{$timeStamp}{'readBytes'} = sprintf("%d", $adapter->{'readBytes'}[0]);
        $data_out->{$hw_type}{'fiber'}{$adapter_uid}{$timeStamp}{'writeBytes'} = sprintf("%d", $adapter->{'writeBytes'}[0]);
        $data_out->{$hw_type}{'fiber'}{$adapter_uid}{$timeStamp}{'numOfReads'} = sprintf("%d", $adapter->{'numOfReads'}[0]);
        $data_out->{$hw_type}{'fiber'}{$adapter_uid}{$timeStamp}{'numOfWrites'} = sprintf("%d", $adapter->{'numOfWrites'}[0]);
        #$data_out->{$hw_type}{'fiber'}{$adapter_uid}{$timeStamp}{'id'} = $adapter->{'id'};

        #architecture fiber adapters
        if (!defined $architecture_lpar_check->{$adapter_uid}){
          my (@physLoc) = split ('\.', $adapter->{'physicalLocation'});
          my $label = $adapter->{'id'} ? $adapter->{'id'} : $adapter_uid;
          $label    = $physLoc[-1] ? "$label ($physLoc[-1])" : $label;
          my %adapter_arch = (
              "item_id" => $adapter_uid,
              "label" => $label,
              "hw_type" => $hw_type,
              "subsystem" => "fiber",
              "parents" => [ $server_uid ],
              "hostcfg_id" => $self->{'hostcfg_id'}
          );

          push(@{$architecture}, \%adapter_arch);
          $architecture_lpar_check->{$adapter_uid} = 1;
        
        }
      }
      # genericPhysicalAdapters
      for (@{ $stor->{'genericPhysicalAdapters'} }){
        my $adapter = $_;
        my $adapter_uid = $adapter->{'physicalLocation'};
        $data_out->{$hw_type}{'genericphysical'}{$adapter_uid}{$timeStamp}{'readBytes'} = sprintf("%d", $adapter->{'readBytes'}[0]);
        $data_out->{$hw_type}{'genericphysical'}{$adapter_uid}{$timeStamp}{'writeBytes'} = sprintf("%d", $adapter->{'writeBytes'}[0]);
        $data_out->{$hw_type}{'genericphysical'}{$adapter_uid}{$timeStamp}{'numOfReads'} = sprintf("%d", $adapter->{'numOfReads'}[0]);
        $data_out->{$hw_type}{'genericphysical'}{$adapter_uid}{$timeStamp}{'numOfWrites'} = sprintf("%d", $adapter->{'numOfWrites'}[0]);
        #$data_out->{$hw_type}{'genericphysical'}{$adapter_uid}{$timeStamp}{'id'} = $adapter->{'id'};
        #$data_out->{$hw_type}{'genericphysical'}{$adapter_uid}{$timeStamp}{'type'} = $adapter->{'type'};
        #$data_out->{$hw_type}{'genericphysical'}{$adapter_uid}{$timeStamp}{'transmittedBytes'} = $adapter->{'transmittedBytes'}[0];
        #$data_out->{$hw_type}{'genericphysical'}{$adapter_uid}{$timeStamp}{'runningSpeed'} = $adapter->{'runningSpeed'}[0];
        #$data_out->{$hw_type}{'genericphysical'}{$adapter_uid}{$timeStamp}{'wwpn'} = $adapter->{'wwpn'};
        #$data_out->{$hw_type}{'genericphysical'}{$adapter_uid}{$timeStamp}{'numOfPorts'} = $adapter->{'numOfPorts'};

        #architecture fiber adapters
        if (!defined $architecture_lpar_check->{$adapter_uid}){
          my $label = $adapter->{'id'} ? $adapter->{'id'} : $adapter_uid;
          my (@physLoc) = split('\.', $adapter->{'physicalLocation'});
          $label    = $physLoc[-1] ? "$label ($physLoc[-1])" : $label;
          my %adapter_arch = (
              "item_id" => $adapter_uid,
              "label" => $label,
              "hw_type" => $hw_type,
              "subsystem" => "genericphysical",
              "parents" => [ $server_uid ],
              "hostcfg_id" => $self->{'hostcfg_id'}
          );
          push(@{$architecture}, \%adapter_arch);
          $architecture_lpar_check->{$adapter_uid} = 1;
        }
      }
      # genericVirtualAdapters
      for (@{ $stor->{'genericVirtualAdapters'} }){
        my $adapter = $_;
        my $adapter_uid = $adapter->{'physicalLocation'};
        $data_out->{$hw_type}{'genericvirtual'}{$adapter_uid}{$timeStamp}{'readBytes'} = sprintf("%d", $adapter->{'readBytes'}[0]);
        $data_out->{$hw_type}{'genericvirtual'}{$adapter_uid}{$timeStamp}{'writeBytes'} = sprintf("%d", $adapter->{'writeBytes'}[0]);
        $data_out->{$hw_type}{'genericvirtual'}{$adapter_uid}{$timeStamp}{'numOfReads'} = sprintf("%d", $adapter->{'numOfReads'}[0]);
        $data_out->{$hw_type}{'genericvirtual'}{$adapter_uid}{$timeStamp}{'numOfWrites'} = sprintf("%d", $adapter->{'numOfWrites'}[0]);
        #$data_out->{$hw_type}{'genericvirtual'}{$adapter_uid}{$timeStamp}{'id'} = $adapter->{'id'};
        #$data_out->{$hw_type}{'genericvirtual'}{$adapter_uid}{$timeStamp}{'type'} = $adapter->{'type'};
        #$data_out->{$hw_type}{'genericvirtual'}{$adapter_uid}{$timeStamp}{'transmittedBytes'} = $adapter->{'transmittedBytes'}[0];
        #$data_out->{$hw_type}{'genericvirtual'}{$adapter_uid}{$timeStamp}{'runningSpeed'} = $adapter->{'runningSpeed'}[0];
        #$data_out->{$hw_type}{'genericvirtual'}{$adapter_uid}{$timeStamp}{'wwpn'} = $adapter->{'wwpn'};
        #$data_out->{$hw_type}{'genericvirtual'}{$adapter_uid}{$timeStamp}{'numOfPorts'} = $adapter->{'numOfPorts'};

        #architecture fiber adapters
        if (!defined $architecture_lpar_check->{$adapter_uid}){
          my $label = $adapter->{'id'} ? $adapter->{'id'} : $adapter_uid;
          my (@physLocParts) = split('\.', $adapter->{'physicalLocation'});
          $label    = $physLocParts[-1] ? "$label ($physLocParts[-1])" : $label;
          my %adapter_arch = (
              "item_id" => $adapter_uid,
              "label" => $label,
              "hw_type" => $hw_type,
              "subsystem" => "genericvirtual",
              "parents" => [ $server_uid ],
              "hostcfg_id" => $self->{'hostcfg_id'}
          );
          push(@{$architecture}, \%adapter_arch);
          $architecture_lpar_check->{$adapter_uid} = 1;
        
        }
      }
      # shared storage pools
      for (@{ $stor->{'sharedStoragePools'} }){
        my $pool = $_;
        my $pool_uid = $pool->{'id'};
        $data_out->{$hw_type}{'sharedstoragepool'}{$pool_uid}{$timeStamp}{'numOfReads'} = sprintf("%d", $pool->{'numOfReads'}[0]);
        $data_out->{$hw_type}{'sharedstoragepool'}{$pool_uid}{$timeStamp}{'numOfWrites'} = sprintf("%d", $pool->{'numOfWrites'}[0]);
        $data_out->{$hw_type}{'sharedstoragepool'}{$pool_uid}{$timeStamp}{'readBytes'} = sprintf("%d", $pool->{'readBytes'}[0]);
        $data_out->{$hw_type}{'sharedstoragepool'}{$pool_uid}{$timeStamp}{'writeBytes'} = sprintf("%d", $pool->{'writeBytes'}[0]);
        #$data_out->{$hw_type}{'sharedstoragepool'}{$pool_uid}{$timeStamp}{'id'} = $pool->{'id'};

        #architecture shared storage pools
        if (!defined $architecture_lpar_check->{$pool_uid}){
          my %pool_arch = (
              "item_id" => $pool_uid,
              "label" => $pool_uid,
              "hw_type" => $hw_type,
              "subsystem" => "sharedstoragepool",
              "parents" => [ $server_uid ],
              "hostcfg_id" => $self->{'hostcfg_id'}
          );
          push(@{$architecture}, \%pool_arch);
          $architecture_lpar_check->{$pool_uid} = 1;
        
        }
      }
      #architecture lpar
      if (!defined $architecture_lpar_check->{$lpar_uid}){  
        my $label = $lpar_label ? $lpar_label : $lpar_uid;
        my %lpar_arch = (
            "item_id" => $lpar_uid,
            "label" => $label,
            "hw_type" => $hw_type,
            "subsystem" => "vm",
            "parents" => [ $server_uid ],
            "hostcfg_id" => $self->{'hostcfg_id'}
        );
        push(@{$architecture}, \%lpar_arch);
        $architecture_lpar_check->{$lpar_uid} = 1;
      }
    }
  }

  # Send data to backend - if there are too many samples, Power_cmc_Xormon.pm will split them into multiple data bundles
  return $data_out; 
  return 0;
}
sub LparPerformanceToData {
  my ($self, $sample, $server_uid, $architecture, $status, $architecture_lpar_check, $xormon) = @_;
  my $link  = $sample->{'link'};
  my $sample2 = $self->getServerProcessedSample($link);
  my $processedJsonLink = $sample2->{'link'};
  my $processedJsonContent = $self->getJsonContent ($processedJsonLink);
  my $utilSamples = $processedJsonContent->{'systemUtil'}{'utilSamples'};

  if (!%{$processedJsonContent}){
    Power_cmc_Xormon::error("API Error : " . "No LPARs processed metrics JSONs found for $server_uid");
  }

  #send data in bundles of at least 100 samples
  my $bundle_size = 100;

  my $data_out = {};
  my $data_out_index = 0;

  for (@{$utilSamples}){
    my $sample = $_;
    my $timeStamp = str2time ( $sample->{'sampleInfo'}{'timeStamp'} );
    

    #lpar performance data
    # convert MiB to bytes to be stored in DB.
    my $lparsUtil = $sample->{'lparsUtil'};
    for (my $i=0; $i<$lpar_multiplicator; $i++){
      for (@{$lparsUtil}){
        my $lpar = $_;
        
        my $proc = $lpar->{'processor'};
        
        my $mem = $lpar->{'memory'};
        my $lpar_uid = $lpar->{'uuid'};
        my $lpar_label = $lpar->{'name'};
        if ($i>0){
          $lpar_uid = "$lpar_uid$i";
          $lpar_label = "$lpar_label-copy-$i";
        }

        #Power_cmc_Xormon::log("API sample : $timeStamp - $lpar_label ($lpar_uid)");

        $data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'maxVirtualProcessors'} = $proc->{'maxVirtualProcessors'}[0] ? sprintf("%d", $proc->{'maxVirtualProcessors'}[0]) : undef;
        #$data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'currentVirtualProcessors'} = $proc->{'currentVirtualProcessors'}[0] > 0 ? sprintf("%d", $proc->{'currentVirtualProcessors'}[0]) : sprintf("%d", $proc->{'entitledProcUnits'}[0]);
        $data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'entitledProcUnits'} = defined $proc->{'entitledProcUnits'}[0] ? $proc->{'entitledProcUnits'}[0] : undef;
        $data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'utilizedProcUnits'} = defined $proc->{'utilizedProcUnits'}[0] ? $proc->{'utilizedProcUnits'}[0] : undef;
        $data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'maxProcUnits'} = defined $proc->{'maxProcUnits'}[0] ? defined $proc->{'maxProcUnits'}[0] : undef;
        $data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'logicalMem'} = defined $mem->{'logicalMem'}[0] ? sprintf("%d", $mem->{'logicalMem'}[0] * $convertValues->{'logicalMem'}) : undef;
        $data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'backedPhysicalMem'} = defined $mem->{'backedPhysicalMem'}[0] ? sprintf("%d", $mem->{'backedPhysicalMem'}[0]* $convertValues->{'backedPhysicalMem'}) : undef;
        
        #create these metric for xormon
        $data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'totalProcUnitsPercent'} = (defined $data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'maxVirtualProcessors'} && $data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'maxVirtualProcessors'} != 0) ? sprintf("%d", (100 * $data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'utilizedProcUnits'} / $data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'maxVirtualProcessors'})) : undef;
        $data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'entitledProcUnitsPercent'} = (defined $data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'entitledProcUnits'} && $data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'entitledProcUnits'} != 0) ? sprintf("%d", (100 * $data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'utilizedProcUnits'} / $data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'entitledProcUnits'})) : undef;

        # MAX
        $data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'utilizedProcUnitsMax'} = defined $proc->{'utilizedProcUnits'}[0] ? $proc->{'utilizedProcUnits'}[0] : undef;
        $data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'totalProcUnitsPercentMax'} = (defined $data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'maxVirtualProcessors'} && $data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'maxVirtualProcessors'} != 0) ? sprintf("%d", (100 * $data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'utilizedProcUnits'} / $data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'maxVirtualProcessors'})) : undef;
        
        # Do not store there metrics for now. it can be useful in future
        #$data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'utilizedCappedProcUnits'} = $proc->{'utilizedCappedProcUnits'}[0];
        #$data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'utilizedUncappedProcUnits'} = $proc->{'utilizedUncappedProcUnits'}[0];
        #$data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'idleProcUnits'} = $proc->{'idleProcUnits'}[0];
        #$data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'donatedProcUnits'} = $proc->{'donatedProcUnits'}[0];
        #$data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'timeSpentWaitingForDispatch'} = $proc->{'timeSpentWaitingForDispatch'}[0];
        #$data_out->{$hw_type}{'vm'}{$lpar_uid}{$timeStamp}{'timePerInstructionExecution'} = $proc->{'timePerInstructionExecution'}[0];

        #architecture lpar
        if (!defined $architecture_lpar_check->{$lpar_uid}){
          my $label = $lpar_label ? $lpar_label : $lpar_uid;
          my %lpar_arch = (
              "item_id" => $lpar_uid,
              "label" => $label,
              "hw_type" => $hw_type,
              "subsystem" => "vm",
              "parents" => [ $server_uid ],
              "hostcfg_id" => $self->{'hostcfg_id'}
          );
          push(@{$architecture}, \%lpar_arch);
          $architecture_lpar_check->{$lpar_uid} = 1;
        }
      }
    }
  }
  # Send data to backend - if there are too many samples, Power_cmc_Xormon.pm will split them into multiple data bundles

  return 0;
}

sub getServerConfigurationDetail {
  my ($self, $server_uid, $conf_out, $configurationMetricsServer, $architecture, $status, $architecture_lpar_check) = @_;

  my $different_units = {
    'CurrentMemory' => 'MiB',
    'MinimumMemory' => 'MiB',
    'MaximumMemory' => 'MiB',
    'CurrentAvailableSystemMemory' => 'MiB',
    'CurrentMinimumMemory' => 'MiB',
    'CurrentMaximumMemory' => 'MiB',
    'DesiredMemory' => 'MiB',
    'RuntimeMemory' => 'MiB',
    'RuntimeMinimumMemory' => 'MiB'
  };

  for (keys %{ $configurationMetricsServer }){
    my $metric = $_;
    eval {
        if ($metric eq "SystemTime"){
          $conf_out->{$server_uid}{$metric} = $configurationMetricsServer->{$metric}{'content'} / 1000  if ( ref($configurationMetricsServer->{$metric}) eq "HASH" && defined $configurationMetricsServer->{$metric}{'content'});
        } else {
          $conf_out->{$server_uid}{$metric} = $configurationMetricsServer->{$metric}{'content'}  if ( ref($configurationMetricsServer->{$metric}) eq "HASH" && defined $configurationMetricsServer->{$metric}{'content'});
        }
    };
  }

  my $details = [ 
    'AssociatedSystemProcessorConfiguration', 
    'AssociatedIPLConfiguration',
    'AssociatedIPLConfiguration' ,
    'AssociatedLogicalPartitions' ,
    'AssociatedReservedStorageDevicePool' ,
    'AssociatedSystemCapabilities' ,
    'AssociatedSystemIOConfiguration' ,
    'AssociatedSystemMemoryConfiguration' ,
    'AssociatedSystemProcessorConfiguration' ,
    'AssociatedSystemSecurity' ,
    'AssociatedVirtualIOServers' ,
    'EnergyManagementConfiguration' ,
    'MachineTypeModelAndSerialNumber' ,
    'MergedReferenceCode' ,
    'Metadata' ,
    'ReferenceCode' ,
    'ServicePartition' ,
    'SystemMigrationInformation', 
  ];

  
  # server details
  for ( @{ $details } ){
    my $detail = $_;
    for (keys %{ $configurationMetricsServer->{$detail} }){
        my $metric = $_;
        my $value = $configurationMetricsServer->{$detail}{$metric}{'content'} if (ref ($configurationMetricsServer->{$detail}{$metric}) eq "HASH" && defined $configurationMetricsServer->{$detail}{$metric}{'content'});
        if ( defined $convertValues->{$metric} ){
          $value *= $convertValues->{$metric};
        }
        
        $conf_out->{$server_uid}{$metric} = $value if ( defined $value );
    }
  }

  # lpar details
  Power_cmc_Xormon::log("API       : " . "Fetch Configuration data from lpars on server $server_uid");
  my $configurationMetricsLpars = $self->getLparsConfiguration($server_uid);
  my $lpars_array;
  if (defined $configurationMetricsLpars->{'id'}){
    my $lpar_uid = $configurationMetricsLpars->{'id'};
    my $lpar = $configurationMetricsLpars->{'content'}{'LogicalPartition:LogicalPartition'};
    $lpars_array->{$lpar_uid} = $lpar;

  } else {
    for (keys %{ $configurationMetricsLpars }){
      my $lpar_uid = $_;
      my $v = $configurationMetricsLpars->{$lpar_uid}{'content'}{'LogicalPartition:LogicalPartition'};
      $lpars_array->{$lpar_uid} = $v;
    }
  }
  for (keys %{ $lpars_array }){
    my $lpar_uid = $_;
    my $lpar = $lpars_array->{$lpar_uid};

    #health status lpar
    my $partitionState = $lpar->{'PartitionState'}{'content'} ? $lpar->{'PartitionState'}{'content'} : 'unknown';
    my $health_status;
    my $health_data;

    if ($partitionState eq "running"){
        $health_status = "ok"
    } else {
        $health_status = "warning";
        push @{$health_data}, "LPAR State : $partitionState";
    }

    my %lpar_status = (
        "item_id" => $lpar_uid,
        "status" => $health_status,
        "updated" => "".localtime()."",
        "data" => $health_data
    );
    push @{$status}, \%lpar_status;

    
    for (keys %{ $lpar }){
        my $metric = $_;
        eval {
          if (defined $different_units->{$metric}){
            $conf_out->{$lpar_uid}{$metric} = Power_cmc_Xormon::returnBytes($lpar->{$metric}{'content'}, $different_units->{$metric}) if ( ref($lpar->{$metric}) eq "HASH" && defined $lpar->{$metric}{'content'});
          }
          else {
            $conf_out->{$lpar_uid}{$metric} = $lpar->{$metric}{'content'}  if ( ref($lpar->{$metric}) eq "HASH" && defined $lpar->{$metric}{'content'});
          }
        };
    }

    my $details = [ 
      'AssociatedManagedSystem',
      'AssociatedPartitionProfile',
      'ClientNetworkAdapters',
      'HostEthernetAdapterLogicalPorts',
      'Metadata',
      'PartitionCapabilities',
      'PartitionIOConfiguration',
      'PartitionMemoryConfiguration',
      'PartitionProcessorConfiguration',
      'PartitionProfiles',
      'PrimaryPagingServicePartition',
      'ProcessorPool',
      'ReferenceCode',
      'VirtualSCSIClientAdapters',
    ];
    my $details2 = [
      'CurrentSharedProcessorConfiguration',
      'SharedProcessorConfiguration',
      'DedicatedProcessorConfiguration',
      'CurrentDedicatedProcessorConfiguration',
      'TaggedIO',
      'CurrentPagingServicePartition',
      'PrimaryPagingServicePartition',

    ];
    for ( @{ $details } ){
      my $detail = $_;
      for (keys %{ $lpar->{$detail} }){
        my $metric = $_;
        my $value = $lpar->{$detail}{$metric}{'content'} if (ref ($lpar->{$detail}{$metric}) eq "HASH" && defined $lpar->{$detail}{$metric}{'content'});
        if (defined $different_units->{$metric}){
          $conf_out->{$lpar_uid}{$metric} = Power_cmc_Xormon::returnBytes($value, $different_units->{$metric})  if ( defined $value );
        } else {
          $conf_out->{$lpar_uid}{$metric} = $value if ( defined $value );
        }
        for ( @{ $details2 } ){
          my $detail2 = $_;
          for (keys %{ $lpar->{$detail}{$detail2} }){
            my $metric2 = $_;
            my $value2 = $lpar->{$detail}{$detail2}{$metric2}{'content'} if (ref ($lpar->{$detail}{$detail2}{$metric2}) eq "HASH" && defined $lpar->{$detail}{$detail2}{$metric2}{'content'});
            if (defined $different_units->{$metric2}){
              $conf_out->{$lpar_uid}{$metric2} = Power_cmc_Xormon::returnBytes($value2, $different_units->{$metric2})  if ( defined $value2 );
            } else {
              $conf_out->{$lpar_uid}{$metric2} = $value2 if ( defined $value2 );
            }
          }
        }
      }
    }
  }

  # vios details (vioses, adapter, storage, target, trunk, backing sea, physical volumes, )
  Power_cmc_Xormon::log("API       : " . "Fetch Configuration data from vioses on server $server_uid");
  
  my $configurationMetricsVioses = $self->getViosesConfiguration($server_uid);
  my $vioses_array;
  if (defined $configurationMetricsVioses->{'id'}){
    my $vios_uid = $configurationMetricsVioses->{'id'};
    my $vios = $configurationMetricsVioses->{'content'}{'VirtualIOServer:VirtualIOServer'};
    $vioses_array->{$vios_uid} = $vios;

  } else {
    for (keys %{ $configurationMetricsVioses }){
      my $vios_uid = $_;
      my $v = $configurationMetricsVioses->{$vios_uid};
      $vioses_array->{$vios_uid} = $v;
    }
  }
  for (keys %{ $vioses_array }){
    my $vios_uid = $_;
    my $vios = $vioses_array->{$vios_uid};

    #health status vios
    my $partitionState = $vios->{'PartitionState'}{'content'} ? $vios->{'PartitionState'}{'content'} : 'unknown';
    my $health_status;
    my $health_data;
    if ($partitionState eq "running"){
        $health_status = "ok"
    } else {
        $health_status = "warning";
        push @{$health_data}, "VIOS State : $partitionState";
    }
    

    my %vios_status = (
        "item_id" => $vios_uid,
        "status" => $health_status,
        "updated" => "".localtime()."",
        "data" => $health_data
    );
    push @{$status}, \%vios_status;

    my $mappings = $vios->{'VirtualSCSIMappings'}{'VirtualSCSIMapping'};
    for (@{ $mappings }){
      my $mapping = $_;
      my $server = $mapping->{'ServerAdapter'};
      my $client = $mapping->{'ClientAdapter'};
      my $target = $mapping->{'TargetDevice'};
      my $storage = $mapping->{'Storage'};
      my $associated_lpar = $mapping->{'AssociatedLogicalPartition'};

      #server adapter
      my $server_adapter_uid = $server->{'LocationCode'}{'content'};
      for (keys %{$server}){
        my $metric = $_;
        eval{
          $conf_out->{$server_adapter_uid}{$metric} = $server->{$metric}{'content'} if (defined $server->{$metric}{'content'});
        }
      }

      #client adapter
      my $client_adapter_uid = $client->{'LocationCode'}{'content'};
      for (keys %{$client}){
        my $metric = $_;
        eval{
          $conf_out->{$server_adapter_uid}{$metric} = $client->{$metric}{'content'} if (defined $client->{$metric}{'content'});
        }
      }

      #storage
      for (keys %{$storage}){
        my $type = $_;
        eval{
          my $storage_uid = $storage->{$type}{'UniqueDeviceID'}{'content'};
          
          for (keys %{$storage->{$type}}){
            if (!defined $storage_uid) { next; }
            my $metric = defined $_ ? $_ : "undefined";
            if ( $metric eq "DiskCapacity"){
              $conf_out->{$server_adapter_uid}{$metric} = Power_cmc_Xormon::returnBytes($storage->{$type}{$metric}{'content'}, "GiB") if (defined $storage->{$type}{$metric}{'content'});
            }
            else {
              $conf_out->{$server_adapter_uid}{$metric} = $storage->{$type}{$metric}{'content'} if (defined $storage->{$type}{$metric}{'content'});
            }
          }
        }
      }

      #target
      for (keys %{$target}){
        my $type = $_;
        eval{
          my $target_uid = $target->{$type}{'UniqueDeviceID'}{'content'};
          for (keys %{$target->{$type}}){
            if (!defined $target_uid) { next; }
            my $metric = $_;
            $conf_out->{$server_adapter_uid}{$metric} = $target->{$type}{$metric}{'content'} if (defined $target->{$type}{$metric}{'content'});
          }
        }
      }
      if (defined $associated_lpar->{'href'}){
        my $associated_lpar_uid = $associated_lpar->{'href'};
        $associated_lpar_uid =~ s/^.*\///g;
        $conf_out->{$server_adapter_uid}{'AssociatedLogicalPartition'} = $associated_lpar_uid;
      }
    }

    my $trunks = $vios->{'TrunkAdapters'}{'TrunkAdapter'};
    for (@{ $trunks }){
      my $trunk = $_;
      my $trunk_uid = $trunk->{'LocationCode'}{'content'};
      #architecture trunk adapter
      if (!defined $architecture_lpar_check->{$trunk_uid}){
        my %arch = (
            "item_id" => $trunk_uid,
            "label" => $trunk_uid,
            "hw_type" => $hw_type,
            "subsystem" => "trunk",
            "parents" => [ $server_uid ],
            "hostcfg_id" => $self->{'hostcfg_id'},
        );
        push(@{$architecture}, \%arch);
        $architecture_lpar_check->{$trunk_uid} = 1;
      }
      for (keys %{ $trunk }){
        my $metric = $_;
        eval {
          $conf_out->{$trunk_uid}{$metric} = $trunk->{$metric}{'content'} if ( ref($trunk->{$metric}) eq "HASH" && defined $trunk->{$metric}{'content'});
          
        };
      }
    }

    my $FreeEthenetBackingDevicesForSEA = $vios->{'FreeEthenetBackingDevicesForSEA'}{'IOAdapterChoice'};
    for (@{ $FreeEthenetBackingDevicesForSEA }){
      my $IOAdapter = $_;
      my $EthernetBackingDevice = $IOAdapter->{'EthernetBackingDevice'};
      my $device_uid = $EthernetBackingDevice->{'PhysicalLocation'}{'content'};
      #architecture backing for sea
      if (!defined $architecture_lpar_check->{$device_uid}){
        my %arch = (
            "item_id" => $device_uid,
            "label" => $EthernetBackingDevice->{'DeviceName'}{'content'},
            "hw_type" => $hw_type,
            "subsystem" => "backingsea",
            "parents" => [ $server_uid ],
            "hostcfg_id" => $self->{'hostcfg_id'},
        );
        push(@{$architecture}, \%arch);
        $architecture_lpar_check->{$device_uid} = 1;
      }
      for (keys %{ $EthernetBackingDevice }){
        my $metric = $_;
        eval {
            $conf_out->{$device_uid}{$metric} = $EthernetBackingDevice->{$metric}{'content'} if ( ref($EthernetBackingDevice->{$metric}) eq "HASH" && defined $EthernetBackingDevice->{$metric}{'content'});
        };
        for (keys %{ $EthernetBackingDevice->{'IPInterface'} }){
          my $metric2  = $_;
          eval {
            $conf_out->{$device_uid}{$metric2} = $EthernetBackingDevice->{'IPInterface'}{$metric2}{'content'} if ( ref($EthernetBackingDevice->{'IPInterface'}{$metric2}) eq "HASH" && defined $EthernetBackingDevice->{'IPInterface'}{$metric2}{'content'});
          };
        }
      }
    }

    my $PhysicalVolumes = $vios->{'PhysicalVolumes'}{'PhysicalVolume'};
    for (@{ $PhysicalVolumes }){
      my $PhysicalVolume = $_;
      my $device_uid = $PhysicalVolume->{'VolumeUniqueID'}{'content'};
      #architecture physical volumes
      if (!defined $architecture_lpar_check->{$device_uid}){
        my %arch = (
            "item_id" => $device_uid,
            "label" => $PhysicalVolume->{'VolumeName'}{'content'},
            "hw_type" => $hw_type,
            "subsystem" => "physicalvolume",
            "parents" => [ $server_uid ],
            "hostcfg_id" => $self->{'hostcfg_id'},
        );
        push(@{$architecture}, \%arch);
        $architecture_lpar_check->{$device_uid} = 1;
      }
      for (keys %{ $PhysicalVolume }){
        my $metric = $_;
        eval {

            if ( $metric eq "VolumeCapacity"){
              $conf_out->{$device_uid}{$metric} = Power_cmc_Xormon::returnBytes($PhysicalVolume->{$metric}{'content'}, "MiB") if (defined $PhysicalVolume->{$metric}{'content'});
            } else {
              $conf_out->{$device_uid}{$metric} = $PhysicalVolume->{$metric}{'content'} if ( ref($PhysicalVolume->{$metric}) eq "HASH" && defined $PhysicalVolume->{$metric}{'content'});
            }
        };
      }
    }
      
    for (keys %{ $vios }){
        my $metric = $_;
        eval {
            $conf_out->{$vios_uid}{$metric} = $vios->{$metric}{'content'} if ( ref($vios->{$metric}) eq "HASH" && defined $vios->{$metric}{'content'});
        };
    }

    my $details = [ 
      'AssociatedManagedSystem',
      'AssociatedPartitionProfile',
      'ClientNetworkAdapters',
      'HostEthernetAdapterLogicalPorts',
      'Metadata',
      'PartitionCapabilities',
      'PartitionIOConfiguration',
      'PartitionMemoryConfiguration',
      'PartitionProcessorConfiguration',
      'PartitionProfiles',
      'PrimaryPagingServicePartition',
      'ProcessorPool',
      'ReferenceCode',
      'VirtualSCSIClientAdapters',
    ];

    my $details2 = [
      'CurrentSharedProcessorConfiguration',
      'SharedProcessorConfiguration',
      'DedicatedProcessorConfiguration',
      'CurrentDedicatedProcessorConfiguration',
      'TaggedIO',
      'CurrentPagingServicePartition',
      'PrimaryPagingServicePartition',
    ];
    for ( @{ $details } ){
      my $detail = $_;
      for (keys %{ $vios->{$detail} }){
        my $metric = $_;
        my $value = $vios->{$detail}{$metric}{'content'} if (ref ($vios->{$detail}{$metric}) eq "HASH" && defined $vios->{$detail}{$metric}{'content'});
        $conf_out->{$vios_uid}{$metric} = $value if ( defined $value );
        for ( @{ $details2 } ){
          my $detail2 = $_;
          for (keys %{ $vios->{$detail}{$detail2} }){
            my $metric2 = $_;
            my $value2 = $vios->{$detail}{$detail2}{$metric2}{'content'} if (ref ($vios->{$detail}{$detail2}{$metric2}) eq "HASH" && defined $vios->{$detail}{$detail2}{$metric2}{'content'});
            $conf_out->{$vios_uid}{$metric2} = $value2 if ( defined $value2 );

          }
        }
      }
    }
  }
  return 0;
}

sub getServerSharedMemoryPool {
  my ($self, $uid) = @_;
  my $url = "/rest/api/uom/ManagedSystem/$uid/SharedMemoryPool";
  my $resp = $self->apiRequest("GET", 'application/xml', $url);

  if (!defined $resp->{'entry'}{'content'}{'SharedMemoryPool:SharedMemoryPool'}){
    Power_cmc_Xormon::error("API Error : " . "Shared Memory Pool not found for $uid");
    Power_cmc_Xormon::error("API Error : " . $url);
    return [];
  }

  my $smp = $resp->{'entry'}{'content'}{'SharedMemoryPool:SharedMemoryPool'};
  my $arr_out = [];
  if (ref ($smp) eq "HASH" ){
    push @{ $arr_out }, $smp;
  } elsif (ref ($smp) eq "HASH" ){
    $arr_out = $smp;
  }
  return $arr_out ? $arr_out : [];
}

sub getServerSharedProcessorPool {
  my ($self, $uid) = @_;
  my $url = "/rest/api/uom/ManagedSystem/$uid/SharedProcessorPool";
  my $resp = $self->apiRequest("GET", 'application/xml', $url);

  my $out = [];
  for (keys %{ $resp->{'entry'} }){
    my $PoolUID = $_;
    my $pool = $resp->{'entry'}{$PoolUID};
    my $pool_det = $pool->{'content'}{'SharedProcessorPool:SharedProcessorPool'};
    push @{$out}, $pool_det;
  }
  return $out ? $out : [];
}

sub getHmcs {
  my ($self) = @_;
  my $url = "/rest/api/uom/ManagementConsole";
  my $resp = $self->apiRequest("GET", 'application/xml', $url);
  my $hmcs = $resp->{'entry'}{'content'}{'ManagementConsole:ManagementConsole'} ? $resp->{'entry'}{'content'}{'ManagementConsole:ManagementConsole'} : [];
  if (ref($hmcs) eq "HASH"){
    $hmcs = [ $hmcs ];
  }
  return $hmcs ? $hmcs : [];
}

sub getServers {
  my ($self) = @_;
  my $url = "/rest/api/pcm/preferences";
  my $resp = $self->apiRequest("GET", 'application/xml', $url);
  my $out = [];
  my $servers = $resp->{'entry'}{'content'}{'ManagementConsolePcmPreference:ManagementConsolePcmPreference'}{'ManagedSystemPcmPreference'} ? $resp->{'entry'}{'content'}{'ManagementConsolePcmPreference:ManagementConsolePcmPreference'}{'ManagedSystemPcmPreference'} : [];
  
  if (ref($servers) eq "HASH"){
    $servers = [ $servers ];
  }
  if (scalar @{$servers} <= 0){
    Power_cmc_Xormon::error ("API Error : Couldn't get any ManagedSystems from rest/api/pcm/preferences at ".__FILE__.":".__LINE__);
  }

  # To eliminate getting any information from powered off managed systems, check its status and if it is not operating, skip it and do not include in the response
  for (@{$servers}){
    my $managed_system_link = $_->{'AssociatedManagedSystem'}{'href'};
    my $resp = $self->apiRequest("GET", 'application/xml', $managed_system_link);
    my $server_state = $resp->{'content'}{'ManagedSystem:ManagedSystem'}{'State'}{'content'} ? $resp->{'content'}{'ManagedSystem:ManagedSystem'}{'State'}{'content'} : 'unknown';
    if ($server_state eq "operating"){
      push @{$out}, $_;
      Power_cmc_Xormon::log ("API       : Server $_->{'SystemName'}{'content'} is in '$server_state' state.");
    } else {
      Power_cmc_Xormon::error ("API Error : Server $_->{'SystemName'}{'content'} is in '$server_state' state. Do not provide any of its configuration or performance data.");
    }
  }
  return $out ? $out : [];
}
sub getServerConfiguration {
  my ($self, $uid) = @_;
  my $url = "/rest/api/uom/ManagedSystem/$uid";
  my $resp = $self->apiRequest("GET", 'application/xml', $url);
  return $resp->{'content'}{'ManagedSystem:ManagedSystem'} ? $resp->{'content'}{'ManagedSystem:ManagedSystem'} : {};
}
sub getLparsConfiguration {
  my ($self, $uid) = @_;
  my $url = "/rest/api/uom/ManagedSystem/$uid/LogicalPartition";
  my $resp = $self->apiRequest("GET", 'application/xml', $url);
  return $resp->{'entry'} ? $resp->{'entry'} : {};
}
sub getViosesConfiguration {
  my ($self, $uid) = @_;
  my $url = "/rest/api/uom/ManagedSystem/$uid/VirtualIOServer";
  my $resp = $self->apiRequest("GET", 'application/xml', $url);
  return $resp->{'entry'} ? $resp->{'entry'} : {};
}
sub getServerProcessed {
  my ($self, $uid) = @_;
  my $url = "/rest/api/pcm/ManagedSystem/$uid/ProcessedMetrics";
  my $resp = $self->apiRequest("GET", 'application/xml', $url);
  return $resp->{'entry'} ? $resp->{'entry'} : {};
}
sub getServerProcessedSample {
  my ($self, $link) = @_;
  my $url = $link->{'href'};
  my $resp = $self->apiRequest("GET", $link->{'type'}, $url);
  return $resp->{'entry'} ? $resp->{'entry'} : {};  
}
sub getServerAggregated {
  my ($self, $uid) = @_;
  my $url = "/rest/api/pcm/ManagedSystem/$uid/AggregatedMetrics";
  my $resp = $self->apiRequest("GET", 'application/xml', $url);
  return $resp->{'entry'} ? $resp->{'entry'} : {};
}
sub getServerLTM {
  my ($self, $uid) = @_;
  my $url = "/rest/api/pcm/ManagedSystem/$uid/RawMetrics/LongTermMonitor";
  my $resp = $self->apiRequest("GET", 'application/xml', $url);
  return $resp->{'entry'} ? $resp->{'entry'} : {};
}
sub getEvents {
  my ($self) = @_;
  my $url = "/rest/api/uom/Event";
  my $resp = [];
  $resp = $self->apiRequest("GET", 'application/xml', $url);
  my $events = $resp->{'entry'}{'content'}{'Event:Event'} ? $resp->{'entry'}{'content'}{'Event:Event'} : [];
  if (ref($events) eq "HASH"){
    $events = [ $events ];
  }
  return $events ? $events : [];
}
sub getOperations {
  my ($self, $uid) = @_;
  my $url = "/rest/api/uom/$uid/operations";
  my $resp = $self->apiRequest("GET", 'application/xml', $url);
  my $operations = $resp->{'entry'}{'content'}{'OperationSet:OperationSet'}{'DefinedOperations'}{'Operation'};
  if (ref($operations) eq "HASH"){
    $operations = [ $operations ];
  }
  return $operations ? $operations : [];
}

# Expects : [string]  - URL to a JSON file
# Returns : [hash]    - Decoded JSON as a hash or array
sub getJsonContent {
  my ($self, $link) = @_;
  if (!defined $link->{'href'} || $link->{'href'} eq "" ) {
    Power_cmc_Xormon::error("API Error : " . "Cannot get the JSON content. The JSON file link is an empty string.");
    return {};
  }
  my $url = $link->{'href'};
  my $resp = $self->apiRequest("GET", $link->{'type'}, $url);
  return $resp ? $resp : {};
}

# Use regex to get rid of e.g. https://127.0.0.1:12443 in the URL. Subroutine apiRequest expects e.g. "/rest/api/pcm/prefernces" and adds e.g. "https://hmc_ip:12443" at the begginning.
sub chop_link {
  my $link = shift;
  $link =~ s/^.*rest\/api/\/rest\/api/g;
  return $link;
}

# HMC Requests as Login, API Request, Logout
# accepts params : (method, type, url) and returns output in hash
sub apiRequest {
  my ($self, $method, $type, $url) = @_;
  my $ua = LWP::UserAgent->new(
    timeout => 30,
    ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0 },
  );
  $url = chop_link($url);
  my $req_url = $self->{protocol}."://".$self->{ip}.":".$self->{port}. $url;
  my $req = HTTP::Request->new( $method, $req_url );
  $req->content_type( $type );
  $req->header( 'Accept'=>'*/*' );
  $req->header( 'X-API-Session' => $self->{'APISession'} );

  my $response = $ua->request($req);
  if ( ! $response->is_success ){
    Power_cmc_Xormon::error("API Error : The response is not success at " . $req_url );
    #warn Dumper $req;
    return {};
  }
  my $content = {};
  if ($type eq 'application/xml' || $type eq 'application/atom+xml'){
    eval {
      if ($response->content eq ''){ 
        Power_cmc_Xormon::error("API Error : " . "Cannot get content of XML file at " . $req_url );
        return {};
      }
      #print Dumper $response->content;
      $content = XMLin( $response->content );
    };
    if ($@){
      Power_cmc_Xormon::error("Eval Error : Cannot get XML content of file at " . $req_url );
      Power_cmc_Xormon::error("$content");
    }
  } elsif ($type eq 'application/vnd.ibm.powervm.pcm.json' || $type eq 'application/json') {
      eval {
        $content = (decode_json ($response->content));
      };
      if ($@){
        Power_cmc_Xormon::error("Eval Error : Cannot decode JSON file at " . $req_url);
        Power_cmc_Xormon::error("$content");
      }
    
  }

  if (defined $content->{'HTTPStatus'}{'content'}){
    if ($content->{'HTTPStatus'}{'content'} == 401){
      Power_cmc_Xormon::error("API Error : " . $req_url );
      Power_cmc_Xormon::error("API Error : " . "$content->{'HTTPStatus'}{'content'} | $content->{'ReasonCode'}{'content'} : $content->{'Message'}{'content'}")      
    } else {
      Power_cmc_Xormon::error("API Error : " . "$content->{'HTTPStatus'}{'content'} | $content->{'ReasonCode'}{'content'} : $content->{'Message'}{'content'}")  
    }
  }

  return $content ? $content : {};
}

#accepts params : (username, password) and returns session token string
sub authCredentials {
  my ($self) = @_;
  my $url = $self->{protocol}."://".$self->{ip}.":".$self->{port}."/rest/api/web/Logon";

  Power_cmc_Xormon::log("API       : " . "Login as $self->{username} : " . $url );

  my $token = getToken($self, $url, $self->{username}, $self->{password} );

  return $token ? $token : "invalid_session_token";
}

#login request
sub getToken {
  my ($self, $url, $username, $password) = @_;

  my $session = "invalid_session_token";

  if (!defined $username || !defined $password ){
    return $session;
  }
  
  my $ua = LWP::UserAgent->new(
    timeout => 30,
    ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0 },
  );

  my $request_body = <<_REQUEST_;
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<LogonRequest xmlns="http://www.ibm.com/xmlns/systems/power/firmware/web/mc/2012_10/" schemaVersion="V1_0">
  <UserID kb="CUR" kxe="false">$username</UserID>
  <Password kb="CUR" kxe="false">$password</Password>
</LogonRequest>
_REQUEST_

  my $req = HTTP::Request->new( "PUT" => $url );

  $req->content_type('application/vnd.ibm.powervm.web+xml');
  $req->content_length( length($request_body) );
  $req->header( 'Accept' => '*/*' );
  $req->content($request_body);
  my $response = $ua->request($req);
  
  if ($response->is_success){
    #print Dumper $response->content;
    my $ref = XMLin( $response->content );
    $session = defined $ref->{'X-API-Session'}{'content'} ? $ref->{'X-API-Session'}{'content'} : "invalid_session_token";
    Power_cmc_Xormon::log("API       : " . "Login as $username : " . $response->{_rc} . " : " . $response->{_msg} . " at $url");
  }
  else {
    #warn Dumper $response;
    Power_cmc_Xormon::error("API Error : " . "Login as $username was not successful. " . $response->{_rc} . " : " . $response->{_msg} . " at $url");
  }
  return $session ? $session : "invalid_session_token";
}

#logout one hmc api session
sub logout {
  my ($self, $session) = @_;
  my $ua = LWP::UserAgent->new(
    timeout => 30,
    ssl_opts => { SSL_cipher_list => 'DEFAULT:!DH', verify_hostname => 0, SSL_verify_mode => 0 },
  );
  my $url = $self->{'protocol'}."://".$self->{ip}.":".$self->{port}."/rest/api/web/Logon";
  my $req_del = HTTP::Request->new( "DELETE" => $url );
  $req_del->header( 'X-API-Session' => $session );
  my $data = $ua->request($req_del);
  return $data->{_rc};
}

#create power object and use it in the code
sub new {
  my($self, $protocol, $ip, $port, $backup_host, $username, $password, $hostcfg_id) = @_;
  my $o = {};
  $o->{'protocol'} = $protocol;
  $o->{'ip'} = $ip;
  $o->{'port'} = $port;
  $o->{'username'} = $username;
  $o->{'password'} = $password;
  $o->{'hostcfg_id'} = $hostcfg_id;

  if (defined $backup_host) {
    $o->{'backup_host'} = $backup_host;
  }
  bless $o;
  return $o;
}

1;

#!/bin/ksh
##VCENTER_CLEAR removes all files,dirs related to given vCenter and blind softlinks in data dir
# !!! Be sure to have valid backup of data/ directory !!!!
##### RUN SCRIPT WITH ARGUMENTS     FOR EXAMPLE  ./bin/vcenter_clear.sh IBM

##### Alias
if [ ! "$1"x = "x" ]; then
  Alias="$1"
else
  echo "No given Alias on cmd line!"
  exit
fi
echo "Finding $Alias"

for Alias2 in `ls data/vmware_*/vmware_alias_name`
do
  Alias4=`grep "|$Alias$" $Alias2 | sed 's/.*|//'`
  Alias3=`echo $Alias4 | sed 's/|//'`
  if [ "$Alias3" == "$Alias" ]; then
    Alias_name=$Alias3
    break
  fi
done

if [ "$Alias_name"x = "x" ]; then
  echo "vCenter not found"
  exit
else
  # echo "Found vCenter $Alias"
  echo "Do you really want to remove vCenter: $Alias ?    (Enter yes/no) : "
  read answer
  if [ "$answer"x != "yes"x ]; then
    echo "Nothing has been deleted, script has been finished"
    exit
  fi
fi

vmware_vcenterUuid=`echo $Alias2|sed 's/[^\/]*\/\([^\/]*\).*/\1/'`
echo $vmware_vcenterUuid

##### VM_HOSTING
echo VM_HOSTING
echo Deleting.....
vm_files_deleted="tmp/vm_files_deleted.txt"
rm $vm_files_deleted 2>/dev/null

# cycle through all clusters in vcenter
for hosts_in_cluster in `ls data/$vmware_vcenterUuid/cluster_*/hosts_in_cluster`
do
  # echo hosts_in_cluster $hosts_in_cluster
  Hosts_in_cluster=`echo "$hosts_in_cluster"`
  for server_line in `cat "$Hosts_in_cluster"`
    # server_line example: 192.168.1.74XORUXpavel.lpar2rrd.com
  do
    echo server_line $server_line ------------------------------------------------------------
    server=`echo "$server_line" | sed 's/XORUX.*//'`
    rename_old="tmp/vm_uuid_replaced.txt"
    rm $rename_old 2>/dev/null
    # cycle through all vmware servers in this vcenter
    for Delete in `cat data/$server/*/my_vcenter_name 2>/dev/null`
    # cycle through all vmware servers (not only in this vcenter)
    #for Delete in `cat data/$server/*/my_vcenter_name 2>/dev/null`
      # example: pavel.lpar2rrd.com|vCenter-60U3
    do
      vm_hosting=`echo $Delete | sed 's/^[0-9A-Za-z_ .]*//'`
      VM_HOSTING=`echo $vm_hosting | sed 's/|//'`
      # take only servers under this vcenter
      echo VM_HOSTING $VM_HOSTING Delete $Delete server $server
      if [ "$VM_HOSTING" == "$Alias" ]; then
        for Server_Hosting in `cat data/$server/*/VM_hosting.vmh | sed 's/:.*//' 2>/dev/null`
        do
          # delete all VMs rrd files, that have been anytime on this server
          if [ -f data/vmware_VMs/"$Server_Hosting.rrm" ]; then
            echo // rm data/vmware_VMs/"$Server_Hosting.rrm" 2>/dev/null
            rm data/vmware_VMs/"$Server_Hosting.rrm" 2>/dev/null
            echo // rm data/vmware_VMs/"$Server_Hosting.last" 2>/dev/null
            rm data/vmware_VMs/"$Server_Hosting.last" 2>/dev/null

            grep -v $Server_Hosting data/vmware_VMs/vm_uuid_name.txt >> $rename_old
            grep $Server_Hosting data/vmware_VMs/vm_uuid_name.txt >> $vm_files_deleted
            echo // mv "$rename_old" data/vmware_VMs/vm_uuid_name.txt
            mv "$rename_old" data/vmware_VMs/vm_uuid_name.txt
          fi
        done
      #else
        # echo Empty
      fi
    done
  done
done
rm $vm_files_deleted 2>/dev/null


##### DELETED SERVERS
echo DELETED SERVERS
for deleted_servers in `cat "$Hosts_in_cluster" | sed 's/XORUX.*//'`
do
  #echo "$deleted_servers"
  echo // rm -rf data/$deleted_servers 2>/dev/null
  rm -rf data/$deleted_servers 2>/dev/null
done
echo "DELETED vCenter"
echo // rm -rf data/"$vmware_vcenterUuid"
rm -rf data/"$vmware_vcenterUuid"

##### SYMBOLIC LINKS
echo SYMBOLIC LINKS
for symbolic_link in `find -L data -maxdepth 1 -xtype l`
do
  if [[ -d "$symbolic_link" ]]; then
    echo living Symbolic Link: "$symbolic_link" remains
  else
    echo empty Symbolic Link: "$symbolic_link" is being deleted
    echo // rm "$symbolic_link"
    rm "$symbolic_link"
  fi
done
echo "Empty links deleted"
rm -f $INPUTDIR/tmp/menu_vmware.txt
rm -f $INPUTDIR/tmp/menu.txt


















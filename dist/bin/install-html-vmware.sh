#!/bin/ksh

#set -x

#
### separated vmware part creates only vmware lines
#

# Main loop for creating of menu

premium=0
if [ -f "$INPUTDIR/bin/premium.sh" ];  then
  premium=1
fi

# workaround for sorting
HLIST=`for m in $INPUTDIR/data/*; do if [ -L "$m" ]; then continue; fi; echo "$m"|sed -e 's/ /=====space=====/g'; done|sort -fr|xargs -n 1024`
for dir1 in $HLIST
do

  # workaround for managed names with a space inside
  dir1_space=`echo "$dir1"|sed 's/=====space=====/ /g'`
  #managedname_space=`basename "$dir1"`
  managedname=`basename $TWOHYPHENS "$dir1_space"`
  managedname_space="$managedname"
  # echo "xxxxxxxxxxxxxxxxxxxxxxxxxxx working for server $managedname_space"
  #date
  # exclude sym links
  # exclusion must be done above in HLIST to avoid a problem with server name like model-serial (that match sym link model*serial)!!
  #if [ -L "$dir1" -o -f "$dir1" ]; then
  #  continue
  #fi

  # exclude folder with VMware VMs
  if [ `echo "$managedname"|egrep "^vmware_VMs"|wc -l` -eq 1 ]; then
     continue
  fi
  # exclude folder with Hyper-V VMs
  if [ `echo "$managedname"|egrep "^hyperv_VMs"|wc -l` -eq 1 ]; then
     continue
  fi

  # Exclude excluded systems
  eval 'echo "$MANAGED_SYSTEMS_EXCLUDE" | egrep "^$managedname:|:$managedname:|:$managedname$|^$managedname$" >/dev/null 2>&1'
  if [ $? -eq 0 ]; then
    if [ $DEBUG -eq 1 ]; then echo "Excluding      : $managedname"; fi
    continue
  fi

  # workaround for sorting
  MLIST=`for m in $INPUTDIR/data/"$managedname"/*; do echo "$m"|sed -e 's/ /=====space=====/g' ; done|sort -f|xargs -n 1024`

  vcenter_printed=0

  for dir2 in $MLIST
  do
    # workaround for managed names with a space inside
    dir2_space=`echo "$dir2"|sed 's/=====space=====/ /g'`
    if [ ! -d "$dir2_space" ]; then
      continue # is not HMC, some trash
    fi

    # echo "ooooooooooooooooooooooo working for hmc $dir2_space"
    #date
    hmc=`basename $TWOHYPHENS "$dir2_space"`
    #hmc_space=`basename "$dir2"`
    hmc_space="$hmc"

    server_menu=$type_smenu # must be used $server_menu since now instead of $type_smenu as it says if the server is dead or not
    is_alive `echo "$hmc"|sed 's/ /\\\\\\_/g'`  `echo "$managedname" |sed 's/ /\\\\\\_/g'`
    if [ $? -eq 1 ] ; then
      # avoid systems not being updated
      #continue
      server_menu=$type_dmenu # continue, just sight it as "dead", this brings it into menu.txt and is further used only for global hostorical reporting of already dead servers
    fi

    if [ ! -d "$WEBDIR/$hmc" ]; then
      mkdir "$WEBDIR/$hmc"
    fi
    if [ ! -d "$WEBDIR/$hmc/$managedname" ]; then
      mkdir "$WEBDIR/$hmc/$managedname"
    fi


    # find out server type
    type_server=$type_server_power
    if [ -f $INPUTDIR/data/"$managedname"/vmware.txt -o -f $INPUTDIR/data/"$managedname"/"$hmc"/vmware.txt ]; then
      type_server=$type_server_vmware
    fi
    if [ -f $INPUTDIR/data/"$managedname"/kvm.txt -o -f $INPUTDIR/data/"$managedname"/"$hmc"/kvm.txt ]; then
      type_server=$type_server_kvm
    fi
    if [ -f $INPUTDIR/data/"$managedname"/hyperv.txt -o -f $INPUTDIR/data/"$managedname"/"$hmc"/hyperv.txt ]; then
      type_server=$type_server_hyperv
    fi
    if [ "$type_server" = "$type_server_power" ]; then
      continue
    fi
    # global menu is created only once
    if [ $vmenu_created -eq 0 -a "$type_server" = "$type_server_vmware" ]; then
      # super menu
      if [ $smenu_created -eq 0 ]; then
        # menu "$type_gmenu" "cgroups" "CUSTOM GROUPS" "custom/$group_first/gui-index.html" # only for Powers
        smenu_created=1 # only once
      fi
      # VMware global menu
      menu "$type_gmenu" "heatmapvm" "Heatmap" "heatmap-vmware.html"
      menu "$type_gmenu" "advisorvm" "Resource Configuration Advisor" "gui-cpu_max_check_vm.html"
      menu "$type_gmenu" "datastoretop" "Datastores TOP" "/$CGI_DIR/detail.sh?host=&server=&lpar=&item=dstr-table-top&entitle=0&none=none"
      menu "$type_gmenu" "gtop10vm" "Top 10 global" "/$CGI_DIR/detail.sh?host=&server=&lpar=cod&item=topten_vm&entitle=0&none=none"
      # here create vmware global menu
      vmenu_created=1 # only once
    fi

    # Add others managed systems into the menu
    hmc_url=`$PERL -e '$s=shift;$s=~s/([^a-zA-Z0-9_.!:~*()'\''-])/sprintf("%%%02X", ord($1))/ge;print "$s\n";' "$hmc"`
    hmc_url_hash=`echo "$hmc_url"|sed -e 's/\#/\%23/g'` # for support hashes in the server name
    managedname_url=`$PERL -e '$s=shift;$s=~s/([^a-zA-Z0-9_.!:~*()'\''-])/sprintf("%%%02X", ord($1))/ge;print "$s\n";' "$managedname"`
    managedname_url_hash=`echo "$managedname_url"|sed -e 's/\#/\%23/g'` # for support hashes in the server name

    # vmware clusters and resourcepools, datacenters and datastores
    time_old="-30"
    if [ ! "$DEMO"x = "x" ]; then
      time_old="-3000" # do not expire on demo
    fi

    if [ `echo $managedname|egrep "^vmware_"|wc -l` -eq 1 -a `find $INPUTDIR/data/"$managedname"/"vmware_alias_name" -type f -mtime $time_old 2>/dev/null|wc -l` -gt 0 ]; then

      # echo "------------------------------------------------------------------------------------------------ $managedname $hmc ----------------------------"
      # for sure
      type_server=$type_server_vmware
      CLUSTER_NAME=`for cn in "$INPUTDIR"/data/"$managedname"/"$hmc"/cluster_name_*; do echo "$cn" |sed 's/ /\\\\\\\\_/g'; done|sort -f|xargs -n 1024` # must be only one name
      # echo "$CLUSTER_NAME"
      for cn in $CLUSTER_NAME
      do
        cname=`echo "$cn" |sed 's/cluster_name_//'`
      done
      cn_file_nem=`basename $TWOHYPHENS "$cname"`

      vmware_path=`for vn in "$INPUTDIR"/data/"$managedname"/"$hmc"/vcenter_name_*; do echo "$vn" |sed 's/ /\\\\\\\\_/g'; done|sort -f|xargs -n 1024` # must be only one name
      # echo "-------------------- $vmware_path $hmc"
      for vn in "$vmware_path"
      do
        vname=`echo "$vn" |sed 's/vcenter_name_//'`
      done
      # echo "------------------------$vname"
      vn_file_nem=`basename $TWOHYPHENS "$vname"`

      if [ "$vcenter_printed" -eq 0 ]; then   # -a "$a_type" = "$type_gmenu" -a $gmenu_created -eq 1 ]; then
         # vmware enter must public its alias name
         alias_name=""
         if [ -f $INPUTDIR/data/"$managedname"/vmware_alias_name ]; then
           alias_name=`sed 's/^[^|]*|//' "$INPUTDIR/data/"$managedname"/vmware_alias_name"`
         fi
         if [ $DEBUG -eq 1 ]; then echo "add to menu $type_vmenu  : $vn_file_nem:$managedname:$alias_name"; fi
         menu "$type_vmenu" "$vn_file_nem" "Totals" "/$CGI_DIR/detail.sh?host=$vn_file_nem&server=$managedname&lpar=nope&item=hmctotals&entitle=$ENTITLEMENT_LESS&gui=1&none=none" "" "" "$alias_name"
         # hist reports & Top10 vcenter
         if [ $premium -eq 1 ]; then
           if [ $DEBUG -eq 1 ]; then echo "add to menu $type_vmenu  : $vn_file_nem:$alias_name:Hist reports "; fi
           menu "$type_vmenu" "$vn_file_nem" "Historical reports" "/$CGI_DIR/histrep.sh?mode=vcenter" "" "" "$alias_name"
         fi
         if [ $DEBUG -eq 1 ]; then echo "add to menu $type_vmenu  : $vn_file_nem:$alias_name:Top 10       "; fi
         menu "$type_vmenu" "$vn_file_nem" "Top10" "/$CGI_DIR/detail.sh?host=$hmc_url_hash&server=$alias_name&lpar=cod&item=topten_vm&entitle=0&none=none"

         vcenter_printed=1
      fi

      # type_amenu_printed=0

      # cluster is printed without viewing if it has resourcepools or not even if it has not own data  'cluster.rrc', since 4.96 rule 30 days !!!
      if [ "$cn_file_nem" != "*" ]; then # cus of globbing returns this
        echo "testing update : cluster file $dir2/cluster.rrc"
        file_alive "$dir2/cluster.rrc"
         if [ $? -eq 1 ] ; then
           # avoid systems not being updated
           continue
           # echo "$dir2/cluster.rrc"
         fi

        if [ $DEBUG -eq 1 ]; then echo "add to menu $type_amenu  : CLUST TOT $vn_file_nem:$cn_file_nem:$managedname"; fi
        menu "$type_amenu" "$vn_file_nem" "$cn_file_nem" "Cluster totals" "/$CGI_DIR/detail.sh?host=$hmc_url&server=$managedname_url&lpar=nope&item=cluster&entitle=0&gui=1&none=none"
      fi

      # cluster has resourcepools
      RRC="rrc"
      RPLIST=`for rp in "$INPUTDIR"/data/"$managedname"/"$hmc"/*$RRC; do echo "$rp" |sed 's/ /\\\\\\\\_/g'; done|sort -f|xargs -n 1024`
      # echo "RPLIST ,$RPLIST,"
      for rp in $RPLIST
      do
        if [ `echo $rp|egrep "\*rrc$"|wc -l` -eq 1 ]; then # workaround against nullglob
          continue
        fi
        if [ `echo $rp|egrep "cluster.rrc$"|wc -l` -eq 1 ]; then
#          if [ $DEBUG -eq 1 ]; then echo "add to menu $type_amenu  : CLUST TOT $vn_file_nem:$cn_file_nem:$managedname"; fi
#          menu "$type_amenu" "$vn_file_nem" "$cn_file_nem" "Cluster totals" "/$CGI_DIR/detail.sh?host=$hmc_url&server=$managedname_url&lpar=nope&item=cluster&entitle=0&gui=1&none=none"
          continue
        fi
#        if [ "$type_amenu_printed" -eq 0 ]; then
#          if [ $DEBUG -eq 1 ]; then echo "add to menu $type_amenu  : CLUST TOT $vn_file_nem:$cn_file_nem:$managedname"; fi
#          menu "$type_amenu" "$vn_file_nem" "$cn_file_nem" "Cluster totals" "/$CGI_DIR/detail.sh?host=$hmc_url&server=$managedname_url&lpar=nope&item=cluster&entitle=0&gui=1&none=none"
#          type_amenu_printed=1
#        fi
        rp_file=`basename $TWOHYPHENS "$rp"`
        rp=`echo "$rp_file"|sed 's/\\\\_/ /g'|sed 's/\.rrc$//'`
        donottake=""
        if [ "$rp" == "Resources" ]; then # this is printed as Unregistered VMs
          continue # since 4.95-7 do not care about Resources
          donottake="donottake"
        fi
        # echo "rp basename $rp_file"
        rp_url=`$PERL -e '$s=shift;$s=~s/([^a-zA-Z0-9_.!:~*()'\''-])/sprintf("%%%02X", ord($1))/ge;print "$s\n";' "$rp"`

        # if the name is filename 'name.moref'
        if [ `ls "$INPUTDIR"/data/"$managedname"/"$hmc"/*.$rp 2>/dev/null |grep "$rp$"|wc -l` -eq 1 ]; then
          rp_name=`ls "$INPUTDIR"/data/"$managedname"/"$hmc"/*.$rp |grep "$rp$"`
          rp_name=`basename $TWOHYPHENS "$rp_name"`
          # file name is like 'Test respool5.9.resgroup-95'
          rp_menu=`echo $rp_name|sed 's/\.[^.]*$//'`
          if [ "$rp_menu" == "Resources" ]; then # this is printed as Unregistered VMs, not since 4.95-7
            continue
          fi
        fi

        echo "testing update : resourcepool file $dir2/$rp.rrc"
        file_alive "$dir2/$rp.rrc"
         if [ $? -eq 1 ] ; then
           # avoid systems not being updated
           continue
         fi

        if [ $DEBUG -eq 1 ]; then echo "add to menu $type_bmenu  : RESC POOL $vn_file_nem:$cn_file_nem:$managedname:$rp_menu"; fi
        menu "$type_bmenu" "$vn_file_nem" "$donottake$cn_file_nem" "$rp_menu" "/$CGI_DIR/detail.sh?host=$hmc_url&server=$managedname_url&lpar=$rp_url&item=resourcepool&entitle=0&gui=1&none=none"
      done

      # testing if datacenter !! care that dir has name 'datastore_'
      if [ `echo $hmc|egrep "^datastore_"|wc -l` -eq 1 ]; then
        if [ `ls "$INPUTDIR"/data/"$managedname"/"$hmc" |grep "dcname$"|wc -l` -eq 1 ]; then
          datacenter_name=`ls "$INPUTDIR"/data/"$managedname"/"$hmc" |grep "dcname$"`
          datacenter_name=`echo $datacenter_name|sed 's/\.dcname//'`
        else
          datacenter_name=$hmc
        fi

        echo "testing update : datacenter file $dir2/$datacenter_name.dcname"
         file_alive "$dir2/$datacenter_name.dcname"
         if [ $? -eq 1 ] ; then
           # avoid systems not being updated
           echo "avoiding       : "`ls -l "$dir2/$datacenter_name.dcname"`
           continue
         fi

        # echo "found datacenter:$datacenter_name $managedname $hmc in vcenter $vn_file_nem"
        # datacenter has datastores
        RRC="rrt"
        DSLIST=`for ds in "$INPUTDIR"/data/"$managedname"/"$hmc"/*$RRC; do echo "$ds" |sed 's/ /\\\\\\\\_/g'; done|sort -f|xargs -n 1024`
        # echo "DSLIST ,$DSLIST,"
        # to be sure
        vn_file_nem=`echo $vn_file_nem|sed 's/^vcenter_name_//'`
        for ds_orig in $DSLIST
        do
          ds_file=`basename $TWOHYPHENS "$ds_orig"`
          ds=`echo "$ds_file"|sed 's/\\\\_/ /g'|sed 's/\.rrt$//'`
          # echo "ds basename $ds_file"
          ds_url=`$PERL -e '$s=shift;$s=~s/([^a-zA-Z0-9_.!:~*()'\''-])/sprintf("%%%02X", ord($1))/ge;print "$s\n";' "$ds"`

          # if the name is filename 'name.uuid'
          if [ `ls "$INPUTDIR"/data/"$managedname"/"$hmc"/*.$ds 2>/dev/null |grep "$ds$"|wc -l` -eq 1 ]; then
            ds_name=`ls "$INPUTDIR"/data/"$managedname"/"$hmc"/*.$ds |grep "$ds$"`
            ds_name=`basename $TWOHYPHENS "$ds_name"`
            ds=`echo $ds_name|sed 's/\.[^\.]*$//'`
          fi

          echo "testing update : datastore file is $ds_orig"
          file_alive "$ds_orig"
           if [ $? -eq 1 ] ; then
             # avoid systems not being updated
             continue
           fi

          if [ $DEBUG -eq 1 ]; then echo "add to menu $type_zmenu  : DATASTORE $managedname:$hmc:$ds"; fi
          menu "$type_zmenu" "$vn_file_nem" "$datacenter_name" "$ds" "/$CGI_DIR/detail.sh?host=$hmc_url&server=$managedname_url&lpar=$ds_url&item=datastore&entitle=0&gui=1&none=none"
        done
        continue
      fi
    fi

    # vmware ESXi & hyperv servers but no power
    if [ `echo "$managedname"|egrep -- "--unknown$"|wc -l` -eq 0  -a `echo "$hmc"|egrep "^no_hmc$"|wc -l` -eq 0 ]; then
      # exclude that for non HMC based lpars
      if [ -f "$INPUTDIR"/data/"$managedname"/"$hmc"/pool.rrm -o -f "$INPUTDIR"/data/"$managedname"/"$hmc"/pool.rrh ]; then
        # exclude servers where is not pool.rrm/h --> but include their lpars below

        # CPU pool
        last_time=0 # servers with newer timestamp will be defaulty displayed in servers menu
        if [ -f $INPUTDIR/data/"$managedname"/"$hmc"/pool.rrh ]; then
          last_time=`$RRDTOOL last $INPUTDIR/data/"$managedname"/"$hmc"/pool.rrh`
        fi
        if [ -f "$INPUTDIR"/data/"$managedname"/"$hmc"/pool.rrm ]; then
          last_time=`$RRDTOOL last $INPUTDIR/data/"$managedname"/"$hmc"/pool.rrm`
        fi

        if [ ! -f "$INPUTDIR"/data/"$managedname"/"$hmc"/vmware.txt -a ! -f $INPUTDIR/data/"$managedname"/"$hmc"/hyperv.txt ]; then
#           menu "$server_menu" "$hmc_space" "$managedname_space" "CPUpool-pool" "CPU pool" "/$CGI_DIR/detail.sh?host=$hmc_url_hash&server=$managedname_url_hash&lpar=pool&item=pool&entitle=$ENTITLEMENT_LESS&gui=1&none=none" "" $last_time
          continue
        else
           # case: user moved esxi from one cluster/vcenter to another and later returned -> esxi was printed under both
           # the dir structure was the same as with two hmcs
           # trick to find the newest pool.rrm and only this to print
           unset -v latest
           for filen in $INPUTDIR/data/$managedname/*/pool.rrm; do
             [[ $filen -nt $latest ]] && latest=$filen
           done
           filex="$INPUTDIR/data/$managedname/$hmc/pool.rrm"
           # echo "309 $filen $filex"
           if [ "$filen" != "$filex" ]; then
             continue
           fi

           # vmware vcenter server must public its cluster name
           # if not in cluster then public its vcenter name

           cluster_name=""
           if [ -f $INPUTDIR/data/"$managedname"/"$hmc"/my_cluster_name ]; then
              cluster_name=`sed 's/|.*//' "$INPUTDIR/data/"$managedname"/"$hmc"/my_cluster_name"`
           else
              if [ -f $INPUTDIR/data/"$managedname"/"$hmc"/my_vcenter_name ]; then
                cluster_name=`sed 's/|.*//' "$INPUTDIR/data/"$managedname"/"$hmc"/my_vcenter_name"`
              fi
           fi
           # vmware server must public its alias name if non vcenter
           alias_name=""
           if [ -f "$INPUTDIR/data/$managedname/$hmc/vmware_alias_name" ]; then
              alias_name=`sed 's/^[^|]*|//' "$INPUTDIR/data/$managedname/$hmc/vmware_alias_name"`
           fi

           echo "testing update : esxi pool file $INPUTDIR/data/$managedname/$hmc/pool.rrm"
           file_alive "$INPUTDIR/data/$managedname/$hmc/pool.rrm"
           if [ $? -eq 1 ] ; then
             continue
           else
             if [ $DEBUG -eq 1 ]; then echo "add to menu $server_menu  : ESXi $managedname:$hmc"; fi
             menu "$server_menu" "$cluster_name" "$managedname_space" "CPUpool-pool" "CPU pool" "/$CGI_DIR/detail.sh?host=$hmc_url_hash&server=$managedname_url_hash&lpar=pool&item=pool&entitle=$ENTITLEMENT_LESS&gui=1&none=none" "$alias_name" $last_time
             hmc_space=$cluster_name # change it for all menu items
           fi
        fi

        if [ $DEBUG -eq 1 ]; then echo "add to menu $server_menu  : $hmc:$managedname:memory"; fi
        menu "$server_menu" "$hmc_space" "$managedname_space" "mem" "Memory" "/$CGI_DIR/detail.sh?host=$hmc_url_hash&server=$managedname_url_hash&lpar=cod&item=memalloc&entitle=$ENTITLEMENT_LESS&gui=1&none=none"

        if [ -f "$INPUTDIR/data/$managedname/$hmc/vmware.txt" ]; then # disk and net
          file_pool=`echo "$INPUTDIR/data/$managedname/$hmc/pool.rrm"|sed 's/:/\\\:/g'`
          disk_val=`rrdtool graph test.png --start -1d DEF:disk_R="$file_pool":Disk_read:AVERAGE PRINT:disk_R:AVERAGE:%lf`
          disk_res=`echo $disk_val|grep -e nan -e NaN|wc -l`
          if [ $disk_res -eq 0 ]; then
            if [ $DEBUG -eq 1 ]; then echo "add to menu $server_menu  : $hmc:$managedname:vmdiskrw  "; fi
            menu "$server_menu" "$hmc_space" "$managedname_space" "Disk" "Disk" "/$CGI_DIR/detail.sh?host=$hmc_url_hash&server=$managedname_url_hash&lpar=cod&item=vmdiskrw&entitle=$ENTITLEMENT_LESS&gui=1&none=none"
          else
            # disk_val=`rrdtool graph test.png --start -1m DEF:disk_R="$INPUTDIR/data/$managedname/$hmc/pool.rrm":Disk_usage:AVERAGE PRINT:disk_R:AVERAGE:%lf`
            # disk_res=`echo $disk_val|grep -e nan -e NaN|wc -l`
            # if [ $disk_res -eq 0 ]; then
              if [ $DEBUG -eq 1 ]; then echo "add to menu $server_menu  : $hmc:$managedname:vmdisk  "; fi
              menu "$server_menu" "$hmc_space" "$managedname_space" "Disk" "Disk" "/$CGI_DIR/detail.sh?host=$hmc_url_hash&server=$managedname_url_hash&lpar=cod&item=vmdisk&entitle=$ENTITLEMENT_LESS&gui=1&none=none"
            # fi
          fi
          net_val=`rrdtool graph test.png --start -1d DEF:net_R="$file_pool":Network_received:AVERAGE PRINT:net_R:AVERAGE:%lf`
          net_res=`echo $net_val|grep -e nan -e NaN|wc -l`
          if [ $net_res -eq 0 ]; then
            if [ $DEBUG -eq 1 ]; then echo "add to menu $server_menu  : $hmc:$managedname:vmnetrw   "; fi
            menu "$server_menu" "$hmc_space" "$managedname_space" "Net" "Net" "/$CGI_DIR/detail.sh?host=$hmc_url_hash&server=$managedname_url_hash&lpar=cod&item=vmnetrw&entitle=$ENTITLEMENT_LESS&gui=1&none=none"
          else
            # net_val=`rrdtool graph test.png --start -1m DEF:net_R="$INPUTDIR/data/$managedname/$hmc/pool.rrm":Network_usage:AVERAGE PRINT:net_R:AVERAGE:%lf`
            # net_res=`echo $net_val|grep -e nan -e NaN|wc -l`
            # if [ $net_res -eq 0 ]; then
              if [ $DEBUG -eq 1 ]; then echo "add to menu $server_menu  : $hmc:$managedname:vmnet  "; fi
              menu "$server_menu" "$hmc_space" "$managedname_space" "Net" "Net" "/$CGI_DIR/detail.sh?host=$hmc_url_hash&server=$managedname_url_hash&lpar=cod&item=vmnet&entitle=$ENTITLEMENT_LESS&gui=1&none=none"
            # fi
          fi
        fi

        if [ -f "$INPUTDIR/data/$managedname/$hmc/hyperv.txt" ]; then # disk and net
            if [ $DEBUG -eq 1 ]; then echo "add to menu $server_menu  : $hmc:$managedname:vmdiskrw  "; fi
            menu "$server_menu" "$hmc_space" "$managedname_space" "Disk" "Disk" "/$CGI_DIR/detail.sh?host=$hmc_url_hash&server=$managedname_url_hash&lpar=cod&item=vmdiskrw&entitle=$ENTITLEMENT_LESS&gui=1&none=none"
            if [ $DEBUG -eq 1 ]; then echo "add to menu $server_menu  : $hmc:$managedname:vmnetrw   "; fi
            menu "$server_menu" "$hmc_space" "$managedname_space" "Net" "Net" "/$CGI_DIR/detail.sh?host=$hmc_url_hash&server=$managedname_url_hash&lpar=cod&item=vmnetrw&entitle=$ENTITLEMENT_LESS&gui=1&none=none"
        fi

        mode="esxi"
        if [ "$hmc_space" = "" ]; then # if esxi soliter
          mode="solo_esxi"
        fi

        if [ $premium -eq 1 ]; then
          if [ $DEBUG -eq 1 ]; then echo "add to menu $server_menu  : $hmc:$managedname:Hist reports "; fi
          menu "$server_menu" "$hmc_space" "$managedname_space" "hreports" "Historical reports" "/lpar2rrd-cgi/histrep.sh?mode=$mode&host=$hmc_url_hash"
        fi

        # add VIEWs
        if [ $DEBUG -eq 1 ]; then echo "add to menu $server_menu  : $hmc:$managedname:Views"; fi

        #echo "----------- ------- -      ------- $hmc:$managedname:Views"
        #date

        menu "$server_menu" "$hmc_space" "$managedname_space" "view" "VIEW" "/$CGI_DIR/detail.sh?host=$hmc_url_hash&server=$managedname_url_hash&lpar=cod&item=view&entitle=$ENTITLEMENT_LESS&gui=1&none=none"

        # even soliter ESXi can have datacenters & datastores
        DCLIST=`for dc in "$INPUTDIR"/data/"$managedname"/datastore_*; do echo "$dc"|grep -v "datastore_\*" |sed 's/ /\\\\\\\\_/g'; done|sort -f|xargs -n 1024`
        # echo "found datacenters in soliter ESXi: DCLIST ,$DCLIST,"
        for dc in $DCLIST
        do
          if [ `ls "$dc" |grep "dcname$"|wc -l` -eq 1 ]; then
            datacenter_name=`ls "$dc" |grep "dcname$"`
            datacenter_name=`echo $datacenter_name|sed 's/\.dcname//'`
          else
            echo "datacenter name not found in soliter ESXi $dc"
            continue
          fi
          # echo "found datacenter:$datacenter_name in soliter ESXi: $managedname in soliter ESXi"
          # datacenter has datastores
          RRC="rrs"
          DSLIST=`for ds in "$dc"/*$RRC; do echo "$ds" |sed 's/ /\\\\\\\\_/g'; done|sort -f|xargs -n 1024`
          # echo "DSLIST ,$DSLIST,"
          # to be sure
          #vn_file_nem=`echo $vn_file_nem|sed 's/^vcenter_name_//'`
          for ds in $DSLIST
          do
            ds_file=`basename $TWOHYPHENS "$ds"`
            ds=`echo "$ds_file"|sed 's/\\\\_/ /g'|sed 's/\.rrs$//'`
            # echo "ds basename $ds_file"
            ds_url=`$PERL -e '$s=shift;$s=~s/([^a-zA-Z0-9_.!:~*()'\''-])/sprintf("%%%02X", ord($1))/ge;print "$s\n";' "$ds"`

            # if the name is filename 'name.uuid'
            if [ `ls "$dc"/*.$ds 2>/dev/null |grep "$ds$"|wc -l` -eq 1 ]; then
              ds_name=`ls "$dc"/*.$ds |grep "$ds$"`
              ds_name=`basename $TWOHYPHENS "$ds_name"`
              ds=`echo $ds_name|sed 's/\..*$//'`
            fi

            if [ $DEBUG -eq 1 ]; then echo "add to menu $type_zmenu  : DATASTORE ESXi:$managedname:$ds"; fi
            menu "$type_zmenu" "" "$datacenter_name" "$ds" "/$CGI_DIR/detail.sh?host=$datacenter_name&server=$managedname_url&lpar=$ds_url&item=datastore&entitle=0&gui=1&none=none"

          done
        done
      fi  # for not pool.rrm.h based server
    fi  # not for HMC managed lpar --> --unknown server suffix

    managedname_print=`echo "$managedname"|sed 's/--unknown$//'`

  done
done


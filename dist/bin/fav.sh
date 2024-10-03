#################################################
# Favourites graphs
#################################################


print_fav_body  () {
new_gui=$2


if [ "$1"x = "x" ]; then
  #no group defined
  cat << END 
<br>
Favourites feature allows you choice typically most important or most often viewed CPU pools or lpars and place them into separated menu for quick access.
<br>
You can assign them aliases which then appear under "favourites" menu.
<br>
<br>
<b>How to start?</b><br>
<ul>
<li>Create configuration file<br>
(upgrade process creates configuration file automatically, so you might skip this)<br>
<b>$ cd $INPUTDIR<br>
$ ./scripts/update_cfg_favourites.sh <br></b>
it creates this configuration file: <b>./etc/favourites.cfg</b> <br>
</li>
<li> edit <b>./etc/favourites.cfg</b> and assign lpars or pools to your favourite names <br><br></li>
<li>
when you want to refresh list of servers/pools/lpars within favourites.cfg then just run again:<br>
<b>$ ./scripts/update_cfg_favourites.sh <br></b>
</li>
</ul>
<br>
For more details and configuration examples visit <b><a href="http://www.lpar2rrd.com/favourites.html" target="_blank">Favourites</a></b><br>
You can also try this functionality on <b><a href="http://www.lpar2rrd.com/live_demo.html" target="_blank">LPAR2RRD live demo</a></b>
END
fi

}

favourite () {
new_gui=$1


  # POOL:ASRV11:all_pools:ASRV11 POOL
  # LPAR:p710:lpars_aggregated:aggregated
  # POOL:p710:demo:demo pool
  # LPAR:p710:nim:ja

  # CPU pool: /lpar2rrd-cgi/detail.sh?host=sdmc&server=p710&lpar=SharedPool1&item=shpool&entitle=0&gui=1&none=none::
  # main CPU pool : /lpar2rrd-cgi/detail.sh?host=sdmc&server=p710&lpar=pool&item=pool&entitle=0&gui=1&none=none:

# go through all favourites
number_fav=0

for fav_space in `egrep -v "#" $INPUTDIR/etc/favourites.cfg 2>/dev/null|sed 's/ /+====space======+/g'`
do
  fav=`echo $fav_space|sed 's/+====space======+/ /g'`
  fav_name=`echo $fav|cut -d":" -f "4-100"|sed 's/. $//'` # use 4th - 100th column to allow users use :

  if [ "$fav_name"x = "x" ]; then
    continue
  fi

  echo "favourite      : $fav_name"

  type=`echo $fav|cut -d":" -f1`
  server_fav=`echo $fav|cut -d":" -f2`
  lpar_fav=`echo $fav|cut -d":" -f3`
  fav_nbsp=`echo $fav|sed 's/ /\&nbsp;/g'`

  if [ ! -d "$INPUTDIR/data/$server_fav" ]; then
    echo "favourite error: $fav_name : $server_fav:$lpar_fav : server dir does not exist: $INPUTDIR/data/$server_fav"
    continue
  fi
  hmc_most_fresh_time=0
  cd "$INPUTDIR/data/$server_fav"
  for hmc_find  in `ls */pool.rrm 2>/dev/null`
  do
    hmc_time_act=`$PERL -e '$inp=shift;$v = (stat("$inp"))[9]; print "$v\n";' $hmc_find`
    if [ $hmc_time_act -gt $hmc_most_fresh_time ]; then 
      hmc_most_fresh_time=$hmc_time_act
      hmc_fav=`dirname $hmc_find`
    fi
  done
  cd - >/dev/null
  if [ $hmc_most_fresh_time -eq 0 ]; then
     echo "favourite error: $fav_name : $server_fav:$lpar_fav no HMC has been found"
     continue
  fi

  #echo "001  $hmc_fav $server_fav $lpar_fav "

  hmc_fav_url=`$PERL -e '$s=shift;$s=~s/([^A-Za-z0-9\+-_])/sprintf("%%%02X",ord($1))/seg;print "$s\n";' "$hmc_fav"`
  server_fav_url=`$PERL -e '$s=shift;$s=~s/([^A-Za-z0-9\+-_])/sprintf("%%%02X",ord($1))/seg;print "$s\n";' "$server_fav"`
  lpar_fav_url=`$PERL -e '$s=shift;$s=~s/([^A-Za-z0-9\+-_])/sprintf("%%%02X",ord($1))/seg;print "$s\n";' "$lpar_fav"`
  item_fav="lpar"
  if [ `echo "$lpar_fav"|egrep "^lpars_aggregated$"|wc -l` -eq 1 ]; then
    item_fav="lparagg"
    # aggregated are canceled, show pool instead
    lpar_fav_url="pool"
    item_fav="pool"
  fi
  if [ `echo "$lpar_fav"|egrep "^all_pools$"|wc -l` -eq 1 ]; then
    # main pool
    lpar_fav_url="pool"
    item_fav="pool"
  fi
  if [  `echo "$type"|egrep "^POOL$"|wc -l` -eq 1 -a `echo "$lpar_fav"|egrep -v "^all_pools$"|wc -l` -eq 1 ]; then
    # CPU shared pool
    item_fav="shpool"
    if [ ! -f "$INPUTDIR/data/$server_fav/$hmc_fav/cpu-pools-mapping.txt" ]; then
      echo "favourite error: $fav_name : $server_fav:$lpar_fav : CPU pool mapping file does not exist: $INPUTDIR/data/$server_fav/$hmc_fav/cpu-pools-mapping.txt"
      continue
    fi
    pool_id=`egrep ",$lpar_fav$" "$INPUTDIR/data/$server_fav/$hmc_fav/cpu-pools-mapping.txt"|cut -d"," -f1`
    lpar_fav_url="SharedPool$pool_id"
  fi

  # echo "host=$hmc_fav_url&server=$server_fav_url&lpar=$lpar_fav_url&item=$item_fav"

  menu "$type_fmenu" "$fav_name" "$fav_name" "/lpar2rrd-cgi/detail.sh?host=$hmc_fav_url&server=$server_fav_url&lpar=$lpar_fav_url&item=$item_fav&entitle=$ENTITLEMENT_LESS&gui=1&none=none"
 
  (( number_fav = number_fav + 1 ))

done

if [ $number_fav -eq 0 ]; then
  # no favourites defined yet, place there just default template
  echo "favourites     : no defined yet, placing default"
  print_fav_body  "" $new_gui > "$WEBDIR/favourites/gui-cpu.html"
  #menu "$type_fmenu" "fav" "no favourite defined" "favourites/gui-cpu.html"
fi

} # end of favourite()


#################################################
# End of favourites graphs
#################################################


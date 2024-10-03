"use strict";

var cgiPath = $.cookie('cgi-path-lpar') ? $.cookie('cgi-path-lpar') : '/lpar2rrd-cgi';

var urlMenu, progressDialog, dbHash, newPos, lparPart, newPart, lta, pta, cta, dta, rta, vta, selectedGrp, mailGroups, params, alrtCfg, cb, match, gmatch, vals, title,
		n, tdc, $tree, urlTab, parr, sortArray, ts, header, element, c1, c2, c3, col, tips, credForm, alertForm, allFields, $type, user, repFormDiv, repRuleStr,
		repRuleObj, itemList, $opt, metricCategory, da, selNodes, list, hrtype, flag, tabimg, name, count, imgarr, src, dbfilename,
		available_regions, available_namespaces;

var curLoad, curNode, curTab = 0, $window, inXormon = false, xormonReady = jQuery.Deferred(), xormonVars = {vc: null, reload: null, user: null},
	extensions,
	lastTabName = "",
	setDbTabByName = "",
	forceTab,
	jumpTo, storedUrl, zoomedUrl, storedObj, timeoutHandle,
	loaded = 0,
	browserNavButton = false,
	emailRegex = /^[a-zA-Z0-9.!#$%&'*+\/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$/,
	hostNameOrIpRegex = /^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$|^(([a-zA-Z_]|[a-zA-Z][a-zA-Z0-9_\-]*[a-zA-Z0-9_])\.)*([A-Za-z0-9_]|[A-Za-z0-9_][A-Za-z0-9_\-]*[A-Za-z0-9_])$/,
	hashTable = {},
	prodName = "LPAR2RRD - ",
	grpJSON = {},
	submetrics = {},
	fleet = {},
	metrics = {},
	cgroups = {},
	sysInfo = {},
	urlItems = {
		lpar: [ "CPU", "xa" ],
		ams: [ "AMS", "xb" ],
		oscpu: [ "CPU OS", "xc" ],
		mem: [ "Memory", "xd" ],
		pg1: [ "Paging", "xe" ],
		pg2: [ "Paging Space", "xf" ],
		lan: [ "ETH", "xg" ],
		sea: [ "SEA", "xh" ],
		san1: [ "FCS ", "xi" ],
		san2: [ "IOPS", "xj" ],
		pool: [ "CPU pool", "xk" ],
		lparagg: [ "LPARs aggregated", "xl" ],
		pagingagg: [ "Paging aggregated", "xm" ],
		shpool: [ "Shared pool", "xn", "CPU shared pool CPU" ],
		custom: [ "Custom group", "xo", "CPU" ],
		custommem: [ "Allocated Memory | Custom group", "xp", "Allocated Memory" ],
		customosmem: [ "Used Memory | Custom group", "xq", "Used Memory" ],
		customoslan: [ "LAN | Custom group", "xr", "LAN" ],
		customossan1: [ "SAN | Custom group", "xs", "SAN" ],
		customossan2: [ "SAN IOPS | Custom group", "xt", "SAN IOPS" ],
		memalloc: [ "Memory Allocation", "xu", "Allocation" ],
		memaggreg: [ "Memory Aggregated", "xv", "Aggregated" ],
		memams: [ "Active Memory Sharing", "xw" ],
		hea: [ "HEA", "xx" ],
		slan: [ "ETH SUM", "xy" ],
		ssan1: [ "FCS SUM", "xz" ],
		ssan2: [ "IOPS SUM", "xA" ],
		cluster: [ "Cluster CPU", "xB" ],
		vmdisk: [ "VM disk", "xC" ],
		vmnet: [ "VM network", "xD" ],
		'vmw-mem': [ "VM MEM", "xE" ],
		'vmw-diskrw': [ "VM disk", "xF" ],
		'vmw-netrw': [ "VM network", "xG" ],
		'vmw-swap': [ "VM swap", "xH" ],
		'vmw-comp': [ "VM compression", "xI" ],
		vmdiskrw: [ "VM disk RW", "xJ" ],
		vmnetrw: [ "VM network RW", "xK" ],
		'vmw-vmotion': [ "vMotion", "xL" ],
		'vmw-proc': [ "CPU", "xM", "CPU %" ],
		'vmw-ready': [ "Ready", "xN" ],
		'multicluster': [ "CPU clusters", "xO" ],
		san_resp: [ "SAN resp", "xP" ],
		'vmw-disk': [ "VM disk", "xQ" ],
		'vmw-net': [ "VM network", "xR" ],
		'ssea': [ "SEA sum", "xS" ],
		'poolagg': [ "Pool agg", "xT", "Pool aggregated" ],
		'S0200ASPJOB': [ "JOBS", "xU" ],
		'job_cpu': [ "CPUTOP", "xV" ],
		'waj': [ "WRKACTJOB", "xW" ],
		'disk_io': [ "IOTOP", "xX" ],
		'ASP': [ "ASP", "xY" ],
		'size': [ "POOL SIZE", "xZ" ],
		'res': [ "POOL RES", "x0" ],
		'threads': [ "THREADS", "x1" ],
		'faults': [ "FAULTS", "x2" ],
		'pages': [ "PAGES", "x3" ],
		'ADDR': [ "ADDR", "x4" ],
		'cap_used': [ "ASP used", "x5" ],
		'cap_free': [ "ASP free", "x6" ],
		'data_as': [ "ASP data", "x7" ],
		'iops_as': [ "ASP IOPS", "x8" ],
		'pool-max': [ "CPU pool max", "x9" ],  // end of short dashboard hashes
		'dstrag_iopsr': [ "IOPS read", "aa" ],
		'dstrag_iopsw': [ "IOPS write", "ab" ],
		'dstrag_datar': [ "Data read", "ac" ],
		'dstrag_dataw': [ "Data write", "ad" ],
		'dstrag_used': [ "Used space", "ae" ],
		'disk_busy': [ "Disk Busy", "af" ],
		'disks': [ "Disk IO", "ag" ],
		'data_ifcb': [ "Data IFCB", "ah" ],
		'paket_ifcb': [ "Packets IFCB", "ai" ],
		'dpaket_ifcb': [ "Packets Discarded IFCB", "aj" ],
		'multihmc': [ "Servers aggregated", "ak" ],
		'multihmclpar': [ "VMs aggregated", "al" ],
		'clustcpu': [ "Cluster CPU", "am" ],
		'clustlpar': [ "Cluster CPU VMs", "an" ],
		'clustmem': [ "Cluster Memory", "ao" ],
		'clustser': [ "Cluster Servers", "ap" ],
		'clustpow': [ "Cluster Power", "aq" ],
		'dsmem': [ "Datastore Space", "ar" ],
		'dsrw': [ "Datastore Data", "as" ],
		'rpcpu': [ "Resource pool CPU", "at" ],
		'rpmem': [ "Resource pool Memory", "au" ],
		'rplpar': [ "Resource pool VMs CPU", "av" ],
		'wpar_cpu': [ "WPAR CPU", "aw" ],
		'wpar_mem': [ "WPAR MEM", "ax" ],
		'packets': [ "LAN packets", "ay" ],
		'shpool-max': [ "Shared pool CPU max", "az", "CPU shared pool max" ],
		'cap_proc': [ "Used memory %", "b0" ],
		'vmw-iops': [ "VM IOPS", "b1" ],
		'jobs': [ "JOB CPU", "b2" ],
		'jobs_mem': [ "JOB MEM", "b3" ],
		'customvmmem': [ "Memory", "b4" ],
		'customdisk': [ "Disk", "b5" ],
		'customnet': [ "Network", "b6" ],
		'packets_lan': [ "LAN packets", "b7" ],
		'packets_sea': [ "SEA packets", "b8" ],
		'clustlpardy': [ "Cluster CPU ready", "b9" ],
		'hyp_clustsercpu': ["Cluster CPU", "ba"],
		'hyp_clustservms': ["Cluster VMs", "bb"],
		'hyp_clustsermem': ["Cluster memory", "bc"],
		'hyp_clustser': ["Cluster nodes", "bd"],
		'hyp-cpu': ["CPU", "be"],
		'hyp-mem': ["Memory", "bf"],
		'hyp-disk': ["Disk", "bg"],
		'hyp-vmotion': ["vMotion", "bh"],
		'trend': ["CPU trend", "bi"],
		'trendpool': ["CPU pool trend", "bj"],
		'trendpool-max': ["CPU pool max trend", "bk"],
		'trendshpool': ["CPU shared pool trend", "bl"],
		'trendshpool-max': ["CPU shared pool max trend", "bm"],
		'trendmemalloc': ["Memory allocation trend", "bn"],
		'custom_cpu_trend': ["CPU trend", "bo"],
		'lparmemalloc': ["Memory allocation", "bp"],
		'dsarw': ["IOPS", "bq"],
		'ds-vmiops': ["IOPS/VM", "br"],
		'dslat': ["Latency", "bs"],
		'customvmmemactive': ["MEM Active", "bt"],
		'customvmmemconsumed': ["MEM Granted", "bu"],
		'ovirt_host_cpu_core': ["Host CPU core", "bv"],
		'ovirt_host_cpu_percent': ["Host CPU percent", "bw"],
		'ovirt_host_mem': ["Host MEM", "bx"],
		'ovirt_host_nic_aggr_net' : ["Host LAN aggregated", "by"],
		'ovirt_host_nic_net' : ["LAN", "bz"],
		'ovirt_vm_cpu_core': ["VM CPU core", "c0"],
		'ovirt_vm_cpu_percent': ["VM CPU percent", "c1"],
		'ovirt_vm_mem': ["VM MEM", "c2"],
		'ovirt_vm_aggr_net': ["VM LAN aggregated", "c3"],
		'ovirt_storage_domain_space' : ["Storage domain Space", "c4"],
		'ovirt_storage_domain_aggr_data' : ["Disk data aggregated", "c5"],
		'ovirt_storage_domain_aggr_latency' : ["Disk latency aggregated", "c6"],
		'ovirt_disk_data' : ["Disk data", "c7"],
		'ovirt_disk_latency' : ["Disk latency", "c8"],
		'ovirt_cluster_aggr_host_cpu_core' : ["Host CPU core aggregated", "c9"],
		'ovirt_cluster_aggr_host_cpu_percent' : ["Host CPU percent", "ca"],
		'ovirt_cluster_aggr_host_mem_used' : ["Host mem used aggregated", "cb"],
		'ovirt_cluster_aggr_host_mem_free' : ["Host mem free aggregated", "cc"],
		'ovirt_cluster_aggr_host_mem_used_percent' : ["Host mem percent", "cd"],
		'ovirt_cluster_aggr_vm_cpu_core' : ["VM CPU core aggregated", "ce"],
		'ovirt_cluster_aggr_vm_cpu_percent' : ["VM CPU percent", "cf"],
		'ovirt_cluster_aggr_vm_mem_used' : ["VM mem used aggregated", "cg"],
		'ovirt_cluster_aggr_vm_mem_free' : ["VM mem free aggregated", "ch"],
		'ovirt_cluster_aggr_vm_mem_used_percent' : ["VM mem percent", "ci"],
		'ovirt_storage_domains_total_aggr_data' : ["Storage domain data aggregated", "cj"],
		'ovirt_storage_domains_total_aggr_latency' : ["Storage domain latency aggregated", "ck"],
		"ovirt_vm_aggr_data" : ["VM disk data aggregated", "cl"],
		"ovirt_vm_aggr_latency" : ["VM disk latency aggregated", "cm"],

		"custom_ovirt_vm_cpu_percent" : ["VM CPU percent", "cn"],
		"custom_ovirt_vm_cpu_core" : ["VM CPU core aggregated", "co"],
		"custom_ovirt_vm_memory_used" : ["VM mem used aggregated", "cp"],
		"custom_ovirt_vm_memory_free" : ["VM mem free aggregated", "cq"],
		"custom-xenvm-cpu-percent" : ["VM CPU percent aggregated", "cr"],
		"custom-xenvm-cpu-cores" : ["VM CPU cores aggregated", "cs"],
		"custom-xenvm-memory-used" : ["VM MEM used aggregated", "ct"],
		"custom-xenvm-memory-free" : ["VM MEM free aggregated", "cu"],
		"custom-xenvm-vbd" : ["VM Disk data aggregated", "cv"],
		"custom-xenvm-vbd-iops" : ["VM Disk IOPS aggregated", "cw"],
		"custom-xenvm-vbd-latency" : ["VM Disk latency aggregated", "cx"],
		"custom-xenvm-lan" : ["VM LAN aggregated", "cy"],
		"custom-nutanixvm-cpu-percent" : ["VM CPU percent aggregated", "cr"],
		"custom-nutanixvm-cpu-cores" : ["VM CPU cores aggregated", "cs"],
		"custom-nutanixvm-memory-used" : ["VM MEM used aggregated", "ct"],
		"custom-nutanixvm-memory-free" : ["VM MEM free aggregated", "cu"],
		"custom-nutanixvm-vbd" : ["VM Disk data aggregated", "cv"],
		"custom-nutanixvm-vbd-iops" : ["VM Disk IOPS aggregated", "cw"],
		"custom-nutanixvm-vbd-latency" : ["VM Disk latency aggregated", "cx"],
		"custom-nutanixvm-lan" : ["VM LAN aggregated", "cy"],

		"xen-host-cpu-percent" : ["Host CPU percent", "cz"],
		"xen-host-cpu-cores" : ["Host CPU cores", "d0"],
		"xen-host-memory" : ["Host MEM", "d1"],
		"xen-disk-vbd" : ["Storage data", "d2"],
		"xen-disk-vbd-iops" : ["Storage IOPS", "d3"],
		"xen-disk-vbd-latency" : ["Storage latency", "d4"],
		"xen-lan" : ["Host LAN", "d5"],
		"xen-vm-cpu-percent" : ["VM CPU percent", "d6"],
		"xen-vm-cpu-cores" : ["VM CPU cores", "d7"],
		"xen-vm-memory" : ["VM MEM", "d8"],
		"xen-vm-vbd" : ["VM Disk data", "d9"],
		"xen-vm-vbd-iops" : ["VM Disk IOPS", "da"],
		"xen-vm-vbd-latency" : ["VM Disk latency", "db"],
		"xen-vm-lan" : ["VM LAN", "dc"],
		"xen-host-cpu-percent-aggr" : ["Host CPU percent aggregated", "dd"],
		"xen-host-cpu-cores-aggr" : ["Host CPU cores aggregated", "de"],
		"xen-host-memory-free-aggr" : ["Host MEM free aggregated", "df"],
		"xen-host-memory-used-aggr" : ["Host MEM used aggregated", "dg"],
		"xen-host-vm-cpu-percent-aggr" : ["VM CPU percent aggregated", "dh"],
		"xen-host-vm-cpu-cores-aggr" : ["VM CPU cores aggregated", "di"],
		"xen-host-vm-memory-free-aggr" : ["VM MEM free aggregated", "dj"],
		"xen-host-vm-memory-used-aggr" : ["VM MEM used aggregated", "dk"],
		"xen-vm-cpu-percent-aggr" : ["VM CPU percent aggregated", "dl"],
		"xen-vm-cpu-cores-aggr" : ["VM CPU cores aggregated", "dm"],
		"xen-vm-memory-free-aggr" : ["VM MEM free aggregated", "dn"],
		"xen-vm-memory-used-aggr" : ["VM MEM used aggregated", "do"],
		"xen-disk-vbd-aggr" : ["Storage data aggregated", "dp"],
		"xen-disk-vbd-iops-aggr" : ["Storage IOPS aggregated", "dq"],
		"xen-disk-vbd-latency-aggr" : ["Storage latency aggregated", "dr"],
		"xen-pool-vbd-aggr" : ["Storage data aggregated", "ds"],
		"xen-pool-vbd-iops-aggr" : ["Storage IOPS aggregated", "dt"],
		"xen-pool-vbd-latency-aggr" : ["Storage latency aggregated", "du"],
		"xen-lan-traffic-aggr" : ["Host LAN aggregated", "dv"],

		"nutanix-host-cpu-percent" : ["Host CPU percent", "cz"],
		"nutanix-host-cpu-cores" : ["Host CPU cores", "d0"],
		"nutanix-host-memory" : ["Host MEM", "d1"],
		"nutanix-disk-vbd" : ["Storage data", "d2"],
		"nutanix-disk-vbd-iops" : ["Storage IOPS", "d3"],
		"nutanix-disk-vbd-latency" : ["Storage latency", "d4"],
		"nutanix-lan" : ["Host LAN", "d5"],
		"nutanix-vm-cpu-percent" : ["VM CPU percent", "d6"],
		"nutanix-vm-cpu-cores" : ["VM CPU cores", "d7"],
		"nutanix-vm-memory" : ["VM MEM", "d8"],
		"nutanix-vm-vbd" : ["VM Disk data", "d9"],
		"nutanix-vm-vbd-iops" : ["VM Disk IOPS", "da"],
		"nutanix-vm-vbd-latency" : ["VM Disk latency", "db"],
		"nutanix-vm-lan" : ["VM LAN", "dc"],
		"nutanix-host-cpu-percent-aggr" : ["Host CPU percent aggregated", "dd"],
		"nutanix-host-cpu-cores-aggr" : ["Host CPU cores aggregated", "de"],
		"nutanix-host-memory-free-aggr" : ["Host MEM free aggregated", "df"],
		"nutanix-host-memory-used-aggr" : ["Host MEM used aggregated", "dg"],
		"nutanix-host-vm-cpu-percent-aggr" : ["VM CPU percent aggregated", "dh"],
		"nutanix-host-vm-cpu-cores-aggr" : ["VM CPU cores aggregated", "di"],
		"nutanix-host-vm-memory-free-aggr" : ["VM MEM free aggregated", "dj"],
		"nutanix-host-vm-memory-used-aggr" : ["VM MEM used aggregated", "dk"],
		"nutanix-vm-cpu-percent-aggr" : ["VM CPU percent aggregated", "dl"],
		"nutanix-vm-cpu-cores-aggr" : ["VM CPU cores aggregated", "dm"],
		"nutanix-vm-memory-free-aggr" : ["VM MEM free aggregated", "dn"],
		"nutanix-vm-memory-used-aggr" : ["VM MEM used aggregated", "do"],
		"nutanix-disk-vbd-aggr" : ["Storage data aggregated", "dp"],
		"nutanix-disk-vbd-iops-aggr" : ["Storage IOPS aggregated", "dq"],
		"nutanix-disk-vbd-latency-aggr" : ["Storage latency aggregated", "dr"],
		"nutanix-pool-vbd-aggr" : ["Storage data aggregated", "ds"],
		"nutanix-pool-vbd-iops-aggr" : ["Storage IOPS aggregated", "dt"],
		"nutanix-pool-vbd-latency-aggr" : ["Storage latency aggregated", "du"],
		"nutanix-lan-traffic-aggr" : ["Host LAN aggregated", "dv"],

		'ovirt_host_aggr_vm_cpu_core': ["Host VM CPU core", "dw"],
		'ovirt_host_aggr_vm_mem_used': ["Host VM MEM used", "dx"],
		'ovirt_host_aggr_vm_mem_free': ["Host VM MEM free", "dy"],

		's_ldom_c': ["LDOM CPU", "dz"],
		's_ldom_m': ["LDOM Memory", "e0"],
		's_ldom_n': ["LDOM Net", "e1"],
		's_ldom_sum': ["LDOM sum of transferred Bytes", "e2"],
		's_ldom_pack': ["LDOM NET packets", "e3"],
		's_ldom_vnet': ["LDOM VNet", "e4"],
		's_ldom_san1': ["LDOM SAN", "e5"],
		's_ldom_san2': ["LDOM SAN IOPS", "e6"],
		's_ldom_san_resp': ["LDOM SAN response time", "e7"],

		'custom_solaris_cpu': ["LDOM CPU", "e8"],
		'custom_solaris_mem': ["LDOM Memory", "e9"],

		'rep_cpu': ["CPU load", "e9"],
		'rep_saniops': ["SAN IOPS", "ea"],
		'rep_san': ["SAN", "eb"],
		'rep_lan': ["LAN", "ec"],
		'rep_iops': ["IOPS", "ed"],
		'rep_disk': ["Disk", "ee"],
		'rep_mem': ["Memory", "ef"],
		'rep_iowait': ["Memory", "eg"],
		's_ldom_agg_c': ["LDOM CPU aggregated", "eh"],
		's_ldom_agg_m': ["LDOM Memory aggregated", "ei"],
		'solaris_zone_cpu': ["ZONE CPU", "ej"],
		'solaris_zone_os_cpu': ["ZONE CPU percent", "ek"],
		'solaris_zone_mem': ["ZONE MEM", "el"],
		'solaris_zone_net': ["ZONE NET", "em"],
		'hyppg1': ["Paging", "en"],
		'hyp-net': ["LAN", "eo"],
		'lfd_cat_': ["Capacity", "ep"],
		'lfd_dat_': ["Data", "eq"],
		'lfd_io_': ["IO", "er"],
		'lfd_lat_': ["Latency", "es"],
		'hdt_data': ["Data", "et"],
		'hdt_io': ["IO", "eu"],
		'clustlan': [ "Cluster LAN", "ev" ],
		'queue_cpu': [ "CPU QUEUE", "ew" ],
		"nutanix-disk-vbd-sp-aggr": [ "Storage Pool data aggregated", "ex" ],
		"nutanix-disk-vbd-iops-sp-aggr": [ "Storage Pool IOPS aggregated", "ey" ],
		"nutanix-disk-vbd-latency-sp-aggr": [ "Storage Pool latency aggregated", "ez" ],
		"nutanix-disk-vbd-sc-aggr": [ "Storage Containers data aggregated", "fa" ],
		"nutanix-disk-vbd-iops-sc-aggr": [ "Storage Containers IOPS aggregated", "fb" ],
		"nutanix-disk-vbd-latency-sc-aggr": [ "Storage Containers latency aggregated", "fc" ],
		"nutanix-disk-vbd-vd-aggr": [ "Volume Groups data aggregated", "fd" ],
		"nutanix-disk-vbd-iops-vd-aggr": [ "Volume Groups IOPS aggregated", "fe" ],
		"nutanix-disk-vbd-latency-vd-aggr": [ "Volume Groups latency aggregated", "ff" ],
		"nutanix-disk-vbd-sr-aggr": [ "Disk data aggregated", "fg" ],
		"nutanix-disk-vbd-iops-sr-aggr": [ "Disk IOPS aggregated", "fh" ],
		"nutanix-disk-vbd-latency-sr-aggr": [ "Disk latency aggregated", "fi" ],
		"nutanix-vm-vbd-aggr": [ "VM data aggregated", "fj" ],
		"nutanix-vm-vbd-iops-aggr": [ "VM IOPS aggregated", "fk" ],
		"nutanix-vm-vbd-latency-aggr": [ "VM latency aggregated", "fl" ],
		"nutanix-vm-lan-aggr": [ "VM LAN aggregated", "fm" ],
		"pool-total": [ "CPU total", "fn" ],
		"pool-total-max": [ "CPU total max", "fo" ],
		"custom_esxi_cpu": [ "CPU cores", "fp" ],
		"oracledb_cpu": ["CPU Used Per Sec", "fq"],
		"custom_hyperv_cpu": ["CPU cores", "fr"],
		"custom_linux_cpu": ["CPU", "fs"],
		"custom_linux_mem": ["MEM", "ft"],
		"custom_linux_lan": ["LAN", "fu"],
		"custom_linux_san1": ["SAN", "fv"],
	},
	usercfg = {},
	hostcfg = {},
	repcfg = {},
	repcfgusr = {},
	userName = "",
	aclAdminGroup = "admins",
	backendSupportsPDF = false,
	backendSupportsZIP = false,
	lessVars = {},
	isAdmin = false;

var metricTitle = {
	CPU:		 'CPU [cores|%]',
	OSCPU:		 'CPU OS [%]',
	MEM:		 'Memory [%]',
	PAGING1:	 'Paging 1 [MB/sec]',
	PAGING2:	 'Paging 2 [%]',
	LAN:		 'LAN [MB/sec]',
	SAN:		 'SAN [MB/sec]',
	SAN_IOPS:	 'SAN IOPS',
	SAN_RESP:	 'SAN RESP [ms]',
	SEA:	     'SEA [MB/sec]',
	FS:          'FS usage [%]',
	CLC:	 	 'Current Logons Count',
	TBSU_P:	 	 'Tablespace Used [%]',
	ARCHL:		 'ARCHIVE LOG enabled [1/0]',
	STATUS:		 'Database available [1/0]',
};

var vmMetrics = {
	A: ['CPU', 'OSCPU', 'MEM', 'PAGING1', 'PAGING2', 'LAN', 'SAN', 'SAN_IOPS', 'SAN_RESP', 'FS'],    // AIX or Linux on Power or VIOS without SEA
	B: ['CPU', 'OSCPU', 'MEM', 'PAGING1', 'PAGING2', 'LAN', 'FS'],                                   // AIX or Linux on Power or VIOS without SEA without SAN
	C: ['CPU'],                                                                                // AIX or Linux on Power without OS agent
	L: ['OSCPU', 'MEM', 'PAGING1', 'PAGING2', 'LAN', 'SAN', 'SAN_IOPS', 'SAN_RESP', 'FS'],           // Linux OS agent or AIX without HMC CPU
	M: ['OSCPU', 'MEM', 'PAGING1', 'PAGING2', 'LAN', 'FS'],                                          // Linux OS agent or AIX or without HMC CPU & SAN
	// I: ['CPU', 'OSCPU', 'MEM', 'PAGING1', 'PAGING2', 'LAN', 'SAN', 'SAN_IOPS'], // AS400 (not implemented yet)
	S: ['OSCPU', 'MEM', 'PAGING1', 'PAGING2', 'LAN', 'FS'],                                          // Solaris (no HMC CPU, no SAN)
	V: ['CPU', 'OSCPU', 'MEM', 'PAGING1', 'PAGING2', 'LAN', 'SAN', 'SAN_IOPS', 'SAN_RESP', 'SEA', 'FS'],    // VIOS with SEA
	U: ['CPU', 'OSCPU', 'MEM', 'PAGING1', 'PAGING2', 'LAN', 'SEA', 'FS'],                                   // VIOS with SEA without SAN
	W: ['OSCPU', 'MEM', 'PAGING1', 'PAGING2', 'FS'],                                                 // WPAR (cpu,mem,pg only)
	X: ['CPU', 'OSCPU', 'MEM', 'PAGING1', 'PAGING2', 'LAN', 'SAN', 'SAN_IOPS', 'SAN_RESP', 'FS'],    // VMware VM
	Y: ['CPU', 'OSCPU', 'MEM', 'PAGING1', 'PAGING2', 'LAN', 'SAN', 'SAN_IOPS', 'FS'],                // AIX or Linux on Power without SAN_RESP
	Q: ['TBSU_P', 'CLC', 'ARCHL', 'STATUS'],
	pool: ['CPU'],                                                                                   // pool
	shpool: ['CPU'],                                                                                 // shared pool
};

var platforms = {
	power: {longname: "IBM Power Systems"},
	cmc: {longname: "IBM Power CMC" },
	vmware: {longname: "VMware"},
	xen: {longname: "XenServer"},
	nutanix: {longname: "Nutanix"},
	aws: {longname: "AWS"},
	gcloud: {longname: "GCloud"},
	docker: {longname: "Docker"},
	azure: {longname: "Azure"},
	kubernetes: {longname: "Kubernetes"},
	openshift: {longname: "Openshift"},
	cloudstack: {longname: "Cloudstack"},
	proxmox: {longname: "Proxmox"},
	fusioncompute: {longname: "FusionCompute"},
	hyperv: {longname: "Hyper-V"},
	kvm: {longname: "KVM"},
	ovirt: {longname: "RHV (oVirt)"},
	oraclevm: {longname: "OracleVM"},
	oracledb: {longname: "OracleDB"},
	postgres: {longname: "PostgreSQL"},
	sqlserver: {longname: "SQLServer"},
	db2: {longname: "DB2"},
	solaris: {longname: "Solaris"},
	custom: {longname: "Custom Group"},
	top: {longname: "Top (n)"},
	rca: {longname: "Resource Config Advisor"}
};

var customGroups = {
	LPAR:    "IBM Power LPAR",
	POOL:    "IBM Power pool",
	VM:      "VMware VM",
	XENVM:   "XenServer VM",
	NUTANIXVM:   "Nutanix VM",
	FUSIONCOMPUTEVM:   "FusionCompute VM",
	PROXMOXVM:   "Proxmox VM",
	KUBERNETESNODE:   "Kubernetes NODE",
	KUBERNETESNAMESPACE:   "Kubernetes NAMESPACE",
	OPENSHIFTNODE:   "OpenShift NODE",
	OPENSHIFTPROJECT:   "OpenShift PROJECT",
	OVIRTVM: "oVirt VM",
	SOLARISZONE: "Solaris Zone",
	SOLARISLDOM: "Solaris LDOM",
	HYPERVM: "Hyper-V VM",
	LINUX: "Linux",
	ORVM: "OracleVM",
	ESXI: "VMware ESXi",
	ODB: "OracleDB"
};
var curPlatform;
var dashBoard;

var hrepinfo = '<div><p>Historical reports are not available in LPAR2RRD Free Edition or in Enterprise Edition without a license for this platform.</p><p>Consider the <a href="https://lpar2rrd.com/support.htm#benefits" target="_blank"><b>Enterprise Edition</b></a>.</p><p>You can test this feature on our <a href="https://demo.lpar2rrd.com" target="_blank">demo site</a>.</p></div>';
if (!Object.keys) { // IE8 hack
	Object.keys = function(obj) {
		var keys = [];

		for (var i in obj) {
			if (obj.hasOwnProperty(i)) {
				keys.push(i);
			}
		}

		return keys;
	};
}

// https://tc39.github.io/ecma262/#sec-array.prototype.findindex
if (!Array.prototype.findIndex) {
	Object.defineProperty(Array.prototype, 'findIndex', {
		value: function(predicate) {
			// 1. Let O be ? ToObject(this value).
			if (this == null) {
				throw new TypeError('"this" is null or not defined');
			}

			var o = Object(this);

			// 2. Let len be ? ToLength(? Get(O, "length")).
			var len = o.length >>> 0;

			// 3. If IsCallable(predicate) is false, throw a TypeError exception.
			if (typeof predicate !== 'function') {
				throw new TypeError('predicate must be a function');
			}

			// 4. If thisArg was supplied, let T be thisArg; else let T be undefined.
			var thisArg = arguments[1];

			// 5. Let k be 0.
			var k = 0;

			// 6. Repeat, while k < len
			while (k < len) {
				// a. Let Pk be ! ToString(k).
				// b. Let kValue be ? Get(O, Pk).
				// c. Let testResult be ToBoolean(? Call(predicate, T, « kValue, k, O »)).
				// d. If testResult is true, return k.
				var kValue = o[k];
				if (predicate.call(thisArg, kValue, k, o)) {
					return k;
				}
				// e. Increase k by 1.
				k++;
			}

			// 7. Return -1.
			return -1;
		},
		configurable: true,
		writable: true
	});
}

jQuery.extend({ alert: function (message, title, status) {
	title += (status ? " - SUCCESS" : " - FAILURE");
	$("<div></div>").dialog( {
		buttons: { "OK": function () { $(this).dialog("close"); } },
		close: function (event, ui) { $(this).remove(); },
		resizable: false,
		title: title,
		minWidth: 700,
		modal: true
	}).html("<pre>" + message + "</pre>");
	}
});

// Create a jquery style modal confirm dialog
// Usage:
//    $.confirm(
//        "message",
//        "title",
//        function() { /* Ok action here*/
//        });
jQuery.extend({ confirm: function(message, title, okAction) {
	$("<div></div>").dialog({
		// Remove the closing 'X' from the dialog
		open: function(event, ui) {
			$(this).find(".ui-dialog-titlebar-close").hide();
		},
		buttons: {
			"OK": function() {
				$(this).dialog("close");
				okAction();
			},
			"Cancel": function() {
				$(this).dialog("close");
			}
		},
		close: function(event, ui) {
			$(this).remove();
		},
		resizable: false,
		minWidth: 700,
		title: title,
		modal: true
	}).html(message);
}
});

jQuery.extend({ message: function (message, title) {
	$("<div></div>").dialog({
		buttons: { "OK": function () { $(this).dialog("close"); } },
		close: function (event, ui) { $(this).remove(); },
		resizable: false,
		title: title,
		minWidth: 700,
		modal: true
	}).html(message);
	}
});

jQuery.extend({
	getQueryParameters : function(str) {
		if (! str) {
			str = document.location.search;
		}
		str = decodeURI(str);
		return str.replace(/^[^\?]*\?/,'').split("&").map(function(n){
			return n = n.split("="), this[n[0]] = n[1], this;
		}.bind({}))[0];
	}
});

var intervals = {
	d: "Last day",
	w: "Last week",
	m: "Last month",
	y: "Last year"
};

$(function() {
  inXormon = $('#side-menu').length !== 1;
});

$.getJSON(cgiPath + "/genjson.sh?jsontype=env", function(data) {
	$( document ).ready(function() {
		$.each(data, function(key, val) {
			sysInfo[key] = val;
		});
		var d = new Date(),
		n = d.getFullYear(),
		free = "";
		if (sysInfo.free == 1) {
			free = " <span class='edition'> <a href='https://www.lpar2rrd.com/support.htm' target='_blank'>Free Edition</a></span>";
		}
		$("#copyright").html('<a href="https://www.xorux.com" target="_blank">XORUX</a> apps family' + free).show();
		if (sysInfo.listbyhmc) {
			$( "#ms2" ).trigger("click");
		}
		if (sysInfo.sideMenuWidth) {
		lessVars.sideBarWidth = sysInfo.sideMenuWidth + 'px';
		less.modifyVars( lessVars );
		}
		if ($.cookie('sideBarWidth')) {
		lessVars.sideBarWidth = $.cookie('sideBarWidth') + 'px';
		less.modifyVars( lessVars );
		}
		if (sysInfo.guidebug == 1) {
			$("#savecontent input:submit").button();
			$("#savecontent").show();
		}
		var logo = "<a href='https://lpar2rrd.com/' class='logo' target='_blank'><img src='css/images/logo_lpar_dark.png' alt='LPAR2RRD website' title='LPAR2RRD website'></a>";

		// white labeling
		if (sysInfo.wlabel) {
			prodName = sysInfo.wlabel;
			switch(prodName) {
				case "Dark":
					prodName = "LPAR2RRD - ";
					logo = "<a href='https://lpar2rrd.com/' id='logo' target='_blank'><img src='css/images/logo_lpar_dark.png' alt='LPAR2RRD website' title='LPAR2RRD website' style='float: left; margin-top: 0px; margin-left:27px; width: 164px; border: 0; opacity: 0.8;'></a>";
					lessVars.headerBg = "#262626";
					lessVars.headerFg = "#fff";
					lessVars.sideBarBg = "#6a6a6a";
					lessVars.paneSepLine = "#666";
					lessVars.dialogTitleBarBg = "#262626";
					lessVars.contentBg = "#" + sysInfo.picture_color;
					// $( "#footer" ).hide();
					// $( "#menusw" ).css("bottom", 0);
					// lessVars.sideBarBottom = 0;
					less.modifyVars( lessVars );
				break;
				case "DATAEXPERTS":
					prodName = "DATA EXPERTS - ";
					logo = "<a href='http://www.dataexperts.pl' class='logo' target='_blank'><img src='css/images/logo_de.png' style='margin-top: 18px; margin-left:2px; width: 220px'</a>";
					$( "#footer" ).hide();
					$( "#menusw" ).css("bottom", 0);
					lessVars.sideBarWidth = "240px";
					lessVars.sideBarBottom = "0";
					less.modifyVars( lessVars );
				break;
				case "TERAKOM":
					prodName = "Terakom - ";
					logo = "<a href='http://www.terakom.com' class='logo' target='_blank'><img src='css/images/logo_terakom.png' style='margin-top: 4px; margin-left:-8px; width: 140px'</a>";
					$( "#footer" ).hide();
					$( "#menusw" ).css("bottom", 0);
					lessVars.sideBarWidth = "200px";
					lessVars.sideBarBottom = "0";
					less.modifyVars( lessVars );
				break;
				case "BREAKPOINT":
					logo = "<a href='https://breakpoint.co.za' class='logo' target='_blank'><img src='css/images/logo_photon.png' style='margin-top: -2px; margin-left:-10px; width: 106px'</a>";
					lessVars.logoBg = "#f8f8f8";
					lessVars.logoSepLine = "#ccc";
					lessVars.headerBg = "#e3e3e3";
					lessVars.toolbarBorder = "#ccc";
					// lessVars.toolbarIcons = "url(images/ui-icons_ffffff_256x240.png)";
					lessVars.headerFg = "#333";
					lessVars.sideBarBg = "#eee";
					lessVars.sideBarFg = "#444";
					lessVars.activeMenuBackground = "#aaa";
					lessVars.paneSepLine = "#ccc";
					lessVars.dialogTitleBarBg = "#EE4444";
					lessVars.contentBg = "#" + sysInfo.picture_color;
					lessVars.sideBarBottom = "29px";
					lessVars.switchbg = "#EE4444";
					lessVars.switchfg = "#fff";
					lessVars.menuGlyphColor = "#ee4444";
					lessVars.fieldsetBackground = "unset";
					lessVars.scrollbarThumb = "#aaa";
					lessVars.scrollbarTrack = "#ddd";
					lessVars.fontFamily = "'Montserrat', sans-serif";
					lessVars.titleFg = "#444";
					var footerlogo = "<a href='https://breakpoint.co.za' target='_blank'><img src='css/images/logo_breakpoint.png' style='margin-top: 0px; margin-left: 0; width: 172px'</a>";
					$( "#footer" ).css( {"height": 62, "background" : "#EE4444"}).html(footerlogo);
					$( "#footer img" ).css("background-color", "unset");
					$( "#menusw" ).css("bottom", 58);
					$( "#side-menu .fancytree-plain span.fancytree-node.fancytree-active" ).css("background-color", "#888");
					less.modifyVars( lessVars );
					$( "#menu-filter" ).css("background-color", "#e3e3e3");
					$( "#menu-filter" ).css("color", "#333");
					$( "#adminmenu a" ).css("color", "#444");
				break;
				case "MON2POWER":
					logo = "<a href='https://asnetworks.asia/Solutions/Mon2Power' title='MON2POWER' class='logo' target='_blank'><img src='css/images/logo_mon2power.png' style='margin-top: 0px; width: 118px;'</a>";
					$( "#footer" ).hide();
					lessVars.logoSepLine = "#2b4f60";
					lessVars.sideBarBottom = "0";
					less.modifyVars( lessVars );
				break;
			}
			$(document).attr("title", prodName);
		}
		if (!inXormon) {
			$( logo ).insertBefore( "#toolbar" );
		}
		if (! sysInfo.vmImage) {
			$( ".imageonly").remove();
		}
		$( "#adminmenu" ).menu({
			items: "> :not(.ui-widget-header)",
			create: function( event, ui ) {
				if (! sysInfo.isAdmin) {
					$(".nobfu").hide();
				}
				if (sysInfo.free != 1) {
					$(".notinfull").hide();
				}
				$('#adminmenu li.ui-menu-item').on("click", function() {
					var link = $(this).find("a");
					if (link.hasClass("about")) {
						about();
						return false;
					} else if (link.hasClass("feedback")) {
						$.message("Use this link <a href=https://lpar2rrd.com/contact.php#feedback target='_blank'>lpar2rrd.com/contact.php#feedback</a> if you want to pass us any feedback.<br><br>Thanks", "Feedback form");
						return false;
					} else if (link.hasClass("ng-info")) {
						var msg = "<h4>What's new</h4><p>We are building a next generation of our infrastructure monitoring tool.</p><p>It will bring a new level of infrastructure monitoring by relying on a modern technology stack.</p><p>In particular, reporting, exporting, alerting and presentation capabilities are far ahead of our current tools.</p><p><a href='https://xormon.com/Xormon-Next-Generation.php' target='_blank'>Read more...</a></p>";
						$.message(msg, "XorMon Next Generation (NG)");
						return false;
					} else {
						var url = link.attr('href'),
						title = link.attr('title'),
						abbr = link.data('abbr'),
						activeNode = $('#side-menu').fancytree('getActiveNode');
						if (activeNode) {
							activeNode.setActive(false);
						}
						$('#content').empty();
						$('#content').append("<div style='width: 100%; height: 100%; text-align: center'><img src='css/images/sloading.gif' style='margin-top: 200px'></div>");
						$('#content').load(url, function() {
							imgPaths();
							myreadyFunc();
							var tabName = "";
							if ($('#tabs').length) {
								tabName = " [" + $('#tabs li.ui-tabs-active').text() + "]";
							}
							History.pushState({
								amenu: abbr,
								url: url,
								tab: curTab
							}, prodName + title + tabName, '?amenu=' + abbr + "&tab=" + curTab);
							browserNavButton = false;
							if (timeoutHandle) {
								clearTimeout(timeoutHandle);
							}
						});
						$('#title').html(title).show();
						$( "#adminmenu" ).hide();
					}
					return false;
				});
			}
		}).menu( "collapseAll", null, true );
		$( "#amenu" ).on("click", function() {
			$( "#adminmenu" ).off("mouseleave");
			$( "#adminmenu" ).show().on("mouseleave", function() {
				$( "#adminmenu" ).hide(400);
			});
		});
		$( "#gsearch" ).on("mouseenter", function() {
			$( "#globalSearchbox" ).off("mouseleave");
			$( "#globalSearchbox" ).show().on("mouseleave", function() {
				$( "#globalSearchbox" ).hide(200);
			});
		});
		$( "#globalSearchbox" ).on("change", function() {
		});
		if (sysInfo.useACL) {
			var lhtml = '<b>Click to log out!<br><br>User name</b><br>' + sysInfo.uid + '<br><br>' + sysInfo.gid;
			$( "#uid" ).prop("title", lhtml).tooltip ({
				position: {
					my: "left top",
					at: "left bottom+5"
				},
				open: function(event, ui) {
					if (typeof(event.originalEvent) === 'undefined') {
						return false;
					}
					var $id = $(ui.tooltip).attr('id');
					// close any lingering tooltips
					$('div.ui-tooltip').not('#' + $id).remove();
					// ajax function to pull in data and add it to the tooltip goes here
				},
				close: function(event, ui) {
					ui.tooltip.on("mouseenter mouseleave", function() {
						$(this).stop(true).fadeTo(400, 1);
					},
						function() {
							$(this).fadeOut('400', function() {
								$(this).remove();
							});
						});
				},
				content: function () {
					return $(this).prop('title');
				}
			});
			// $( "#uid" ).html(lhtml);
			$('#uid').on('click', function(e) {
				e.preventDefault();
				$.confirm(
					"Are you sure you want to log out?",
					"Log out user confirmation",
					function() { /* Ok action here*/
						dashBoard.length = 0;
						sysInfo.length = 0;
						if (navigator.userAgent.indexOf('Chrome') >= 0) {
							document.location = document.location.protocol + "//reset:reset@" + document.location.hostname + document.location.pathname;
						}
						// HTTPAuth Logout code based on: http://tom-mcgee.com/blog/archives/4435
						try {
							// This is for Firefox
							$.ajax({
								// This can be any path on your same domain which requires HTTPAuth
								url: document.location.origin + document.location.pathname,
								username: 'reset',
								password: 'reset',
								// If the return is 401, refresh the page to request new details.
								statusCode: { 401: function() {
									document.location = document.location;
								}
								}
							});
						} catch (exception) {
							// Firefox throws an exception since we didn't handle anything but a 401 above
							// This line works only in IE
							if (!document.execCommand("ClearAuthenticationCache")) {
								// exeCommand returns false if it didn't work (which happens in Chrome) so as a last
								// resort refresh the page providing new, invalid details.
								document.location = document.location.protocol + "//reset:reset@" + document.location.hostname + document.location.pathname;
							}
						}
					}
				);
			});
		} else {
			$("#uid").hide();
		}
		if (sysInfo.isAdmin) {
			isAdmin = true;
		}
		if (sysInfo.aclAdminGroup) {
			aclAdminGroup = sysInfo.aclAdminGroup;
		}

		if(!inXormon) {
			var postdata = {cmd: "loaddashboard", user: sysInfo.uid};
			$.getJSON('/lpar2rrd-cgi/users.sh', postdata, function(data) {
				dashBoard = data;
				if (! dashBoard.tabs || dashBoard.tabs.length < 1) {
					dashBoard.tabs = [];
					if (dashBoard.groups && dashBoard.groups.length) {
						dashBoard.tabs[0] = {name: "Default", groups: dashBoard.groups};
						delete dashBoard.groups;
					} else {
						dashBoard.tabs[0] = {name: "Default", groups: []};
					}
				}
			});
		}
		whenReady();
		if(sysInfo.xormonUIonly) {
			$( "#amenu" ).prop("disabled", true).off();
			$( "#adminmenu" ).menu( "disable" );
			$( "#side-menu" ).hide();
			$( "#gsearch" ).prop("disabled", true).off();
			$( "#ms1" ).prop("disabled", true).off();
			$( "#uid" ).prop("disabled", true).off("click");
			$( "#toolbar" ).hide();
		}
		xormonReady.resolve();
	});
}).fail(function () {
  xormonReady.reject();
});

function whenReady() {
	$window = $(window);
	var d = new Date(),
	n = d.getFullYear();
	// $("#copyright").hide().html('&copy; ' + n + ' <a href="http://www.xorux.com" target="_blank">XORUX</a>').show();
	$.ajaxSetup({
		traditional: true,
		cache: false
	});
	if (sysInfo.custom_page_title) {
		prodName = sysInfo.custom_page_title + " - " + prodName;
		document.title = prodName;
	}
	// Bind to StateChange Event
	History.Adapter.bind(window, 'statechange', function() { // Note: We are using statechange instead of popstate
		var state = History.getState(); // Note: We are using History.getState() instead of event.state
		var menuTree = $("#side-menu").fancytree("getTree");
		if (state.data.amenu && state.internal) {
			$('#adminmenu a[data-abbr="' + state.data.amenu + '"]').trigger( "click" );
		} else if (state.data.menu && state.internal) {
			curTab = state.data.tab;
			browserNavButton = true;
			if (state.data.form) {
				var data = restoreData(state.data.form);
				$("#content").html(data.html);
				myreadyFunc();
				$("#content").scrollTop(data.scroll);
				$("#title").html(data.title);
			} else if (state.data.menu == menuTree.getActiveNode().key) {
				menuTree.reactivate();
			} else {
				menuTree.activateKey(state.data.menu);
			}
		}
	});

	// $("#beta-notice").dialog({
	$("#cgcfg-help").dialog({
		dialogClass: "info",
		minWidth: 700,
		maxHeight: 600,
		position: {
			my: "right",
			at: "right top",
			of: "#content"
		},
		modal: false,
		autoOpen: false,
		show: {
			effect: "fadeIn",
			duration: 500
		},
		hide: {
			effect: "fadeOut",
			duration: 200
		}
		/*buttons: {
			OK: function() {
				$(this).dialog("close");
			}
		}*/
	});

	var mUrl = (sysInfo.listbyhmc) ? '/lpar2rrd-cgi/genjson.sh?jsontype=menuh' : '/lpar2rrd-cgi/genjson.sh?jsontype=menu';
	var mSource = {url: mUrl};
	if (sysInfo.xormonUIonly) {
		mSource = [{"key": "dashboard", "title": "DASHBOARD", "hash": "ea7021f", "href": "dashboard.html"}];
	}
	$("#side-menu").fancytree({
		extensions: ["filter", "glyph"],
		source: mSource,
		filter: {
			mode: "hide",
			highlight: true
		},
		persist: {
			expandLazy: true
		},
		glyph: {
			preset: "awesome5"
		},
		icon: false,
		checkbox: false,
		selectMode: 1,
		clickFolderMode: 2,
		activate: function(event, data) {
			if (curNode != data.node) {
				if (curNode && !browserNavButton) {
					curTab = 0;
					if (forceTab != "") {
						curTab = forceTab;
					}
				}
				curNode = data.node;
			}
			if (curNode.data.href) {
				autoRefresh();
				var url = curNode.data.href;
				url = url.replace(/:([^:]*[^\/]*)(.*)/, "%3A$1$2");
				/*
				*if (url.indexOf(':') >= 0) {
				*    url = document.location.origin + document.location.pathname + url;
				*}
				*/
				if (curLoad) {
					curLoad.ajaxStop(); //cancel previous load
				}
				$('#content').empty();
				$('#content').append("<div style='width: 100%; height: 100%; text-align: center'><img src='css/images/sloading.gif' style='margin-top: 200px'></div>");
				$('#subheader fieldset').hide();
				curLoad = $('#content').load(url, function() {
					imgPaths();
					setTimeout(function() {
						myreadyFunc();
						setTitle(curNode);
						var tabName = "";
						if ($('#tabs').length) {
							tabName = " [" + $('#tabs li.ui-tabs-active').text() + "]";
						}
						if (curNode.data.hash) {
							urlMenu = curNode.data.hash;
						} else {
							urlMenu = curNode.key.replace(/^_/, '');
						}
						History.pushState({
							menu: curNode.key,
							tab: curTab
						}, prodName + $('#title').text() + tabName, '?menu=' + urlMenu + "&tab=" + curTab);
						browserNavButton = false;
					}, 10);
				});
			}
		},
		click: function(event, data) { // allow re-loads
			var node = data.node;
			if (node.folder && node.data.href ) {
				event.preventDefault;
				if (!node.isActive()) {
					node.setActive();
				}
				return;
			}
			if (node.data.href == "logout.html") {
				event.preventDefault;
				$( "#uid a" ).trigger("click");
				return;
			}
			if (!node.isExpanded()) { // jump directly to CPU pool when opening server
				if (node.getFirstChild()) {
					var firstChild = node.getFirstChild().title;
					if (firstChild == "CPU" || firstChild == "Totals" || firstChild == "Cluster totals") {
						node.getFirstChild().setActive();
						node.setExpanded();
						return false;
					}
				}
				var toReturn;
				$.each(node.getChildren(), function(idx, child) {
					if (child.hasClass("jumphere")) {
						toReturn = child;
					}
				});
				if (toReturn) {
					node.setExpanded();
					toReturn.setActive();
					return false;
				}
			}
			if (node.isActive() && node.data.href) {
				data.tree.reactivate();
			}
		},
		/*
		create: function() {
			var tabPos = getUrlParameter('tab');
			if (tabPos) {
				forceTab = tabPos;
			}
		},
		*/
		init: function() {
			var $tree = $(this).fancytree("getTree");
			var menuPos = getUrlParameter('menu');
			var amenu = getUrlParameter('amenu');
			var tabPos = getUrlParameter('tab');
			var serverPos = getUrlParameter('server');
			var lparPos = getUrlParameter('lpar');
			var savedDashBoard = getUrlParameter('dashboard');
			var fakeUrl = "";
			checkStatus(["OracleDB", "Nutanix", "PostgreSQL","SQLServer", "DB2"]);

			hashTable = [];
			$tree.visit(function(node) {
				if (sysInfo.guidebug == 1) {
					node.tooltip = node.data.href;
					node.renderTitle();
				}
				node.data.noalias = node.title ? node.title.replace(/ \[.*\]/g, "") : "";
				if (node.data.hash) {
					var lpar = "";
					if (node.data.altname) {
						lpar = node.data.altname;
					} else {
						lpar = node.data.noalias;
					}
					hashTable[node.data.hash] = {
						"hmc": node.data.hmc,
						"srv": node.data.srv,
						"lpar": lpar,
						"parent": node.data.parent
					};
				} else {
					if (node.data.href) {
						var urlparams = getParams(node.data.href);
						if (urlparams.platform) {
							var hash;
							if (urlparams.platform == "OracleDB" || urlparams.platform == "PostgreSQL" || urlparams.platform == "SQLServer" || urlparams.platform == "DB2") {
								hash = hex_md5(urlparams.platform + urlparams.type + urlparams[urlparams.type] + urlparams.server).substring(0, 7);
							} else {
								hash = hex_md5(urlparams.platform + urlparams.type + urlparams[urlparams.type]).substring(0, 7);
							}
							node.data.hash = hash;
							hashTable[hash] = urlparams;
							hashTable[hash].parent = node.getParent().getParent().title;
							if (node.data.agent) {
								hashTable[hash].agent = node.data.agent;
							}
						}
					}
				}
			});

			if (tabPos) {
				curTab = tabPos;
			}
			if (amenu) {
				$('#adminmenu a[data-abbr="' + amenu + '"]').trigger( "click" );
				return false;
			} else if (savedDashBoard) {
				var postdata = {load: "db_" + savedDashBoard};
				$.ajax({
					url: "/lpar2rrd-cgi/dashboard.sh",
					dataType: "json",
					data: postdata,
					async: false,
					success: function (data) {
						if ( data.status == "success" && data.cookie) {
							$.cookie('dbHashes', data.cookie, {
								expires: 60
							});
							$("#side-menu").fancytree("getTree").getFirstChild().setActive();
						}
					}
				});
				return false;
			} else if (serverPos) {
				if (lparPos) {
					fakeUrl = "?item=lpar&server=" + serverPos + "&lpar=" + lparPos;
				} else {
					fakeUrl = "?item=pool&server=" + serverPos + "&lpar=pool";
				}
				backLink(fakeUrl);
				return false;
			} else if (menuPos) {
				if (menuPos == "extnmon") {
					var href = window.location.href;
					var qstr = href.slice(href.indexOf('&start-hour') + 1);
					var hashes = qstr.split('&');
					// var txt = hashes[13].split("=")[1];
					var txt = decodeURIComponent(hashes[14].split("=")[1]);

					txt = txt.replace("--unknown","");
					txt = txt.replace("--NMON--","");
					$("#content").load("/lpar2rrd-cgi/lpar2rrd-external-cgi.sh?" + qstr, function(){
						imgPaths();
						$('#title').text(txt);
						$('#title').show();
						myreadyFunc();
						// loadImages('#content img.lazy');
						if (timeoutHandle) {
							clearTimeout(timeoutHandle);
						}
					});
				} else if (menuPos == "dashboard" && tabPos != "") { // ea7021f is the hash of DASHBOARD menu item
					$tree.visit(function(node) {
						if (node.title && node.title == "DASHBOARD") {
							setDbTabByName = tabPos;
							node.setActive();
							return false;
						}
					});
				} else {
					$tree.visit(function(node) {
						if ((node.data.hash && node.data.hash == menuPos) || node.key == menuPos) {
							node.setExpanded(true);
							node.setActive();
							return false;
						}
					});
				}
			} else if (!$tree.activeNode) {
				$tree.getFirstChild().setActive();
			}
				if (sysInfo.xormonUIonly && !inXormon) {
					$("#side-menu").fancytree("getTree").getNodeByKey("dashboard").setActive();
				}
		},
		loadError: function(e,d) {
			var errMsg = "<h2>There was an error on menu JSON generation</h2>";
			errMsg += "<h3>" + d.details + "</h3>";
			errMsg += "<p>Please collect logs and send that file to developers via <a href='https://upload.lpar2rrd.com'>secured upload service</a>.</p>";
			errMsg += "<pre>" + d.error.responseText + "</pre>";
			$('#content').append(errMsg);
		}
	});

	var $tree = $("#side-menu").fancytree("getTree");

	$("#globalSearchbox").on("change", function(event) {
		globalSearch(event);
	});
	$("#gsearch").on("click", function(event) {
		globalSearch(event);
	});

	function globalSearch(event) {
		var searchTitle = "Search results";

		if (timeoutHandle) {
			clearTimeout(timeoutHandle);
		}
		$('#content').empty();

		$('#content').append("<div style='width: 100%; height: 100%; text-align: center'><img src='css/images/sloading.gif' style='margin-top: 200px'></div>");
		$('#title').text(searchTitle);
		var postData = $.param({"LPAR": $("#globalSearchbox").val()});
		if (sysInfo.guidebug == 1) {
			copyToClipboard(postData);
		}
		$('#content').load(cgiPath + "/lpar-search.sh", postData, function() {
			if (curNode.data.hash) {
				urlMenu = curNode.data.hash;
			} else {
				urlMenu = curNode.key.substring(1);
			}
			History.pushState({
				menu: curNode.key,
				tab: curTab,
				form: "lparsrch"
			}, prodName + "LPAR/VM Search Form Results", '?menu=' + urlMenu + "&tab=" + curTab);
			imgPaths();
			myreadyFunc();
			saveData("lparsrch"); // save when page loads

		});
	}

	/* BUTTONS */

	$("#collapseall").button({
		text: false,
		icons: {
			primary: "ui-icon-minus"
		}
	})
		.on("click", function() {
			$tree.visit(function(node) {
				node.setExpanded(false, {
					noAnimation: true,
					noEvents: true
				});
			});
		});
	$("#expandall").button({
		text: false,
		icons: {
			primary: "ui-icon-plus"
		}
	})
		.on("click", function() {
			$tree.visit(function(node) {
				node.setExpanded(true, {
					noAnimation: true,
					noEvents: true
				});
			});
		});
	$("#filter").button({
		text: false,
		icons: {
			primary: "ui-icon-search"
		}
	})
		.on("click", function() {
			// Pass text as filter string (will be matched as substring in the node title)
			var match = $("#menu-filter").val();
			if ($.trim(match) !== "") {
				var re = new RegExp(match, "i");
				var n = $tree.filterNodes(function(node) {
					var parentTitle = node.parent.title;
					var matched = re.test(node.data.str);
					if (matched) {
						node.setExpanded(true, {
							noAnimation: true,
							noEvents: true
						});
						if (parentTitle != "Removed") {
							if ((parentTitle != "LPAR") || ((parentTitle = "LPAR") && (new RegExp(match, "i").test(node.title)))) {
								node.makeVisible({
									noAnimation: true,
									noEvents: true,
									scrollIntoView: false
								});
							}
						}
					}
					return matched;
				});
				// $("#expandall").click();
				$("#clrsrch").button("enable");
			}
		});

	$("#clrsrch").button({
		text: false,
		disabled: true,
		icons: {
			primary: "ui-icon-close"
		}
	})
		.on("click", function() {
			$("#menu-filter").val("");
			$tree.clearFilter();
			$(this).button("disable");
		});

	/*
	* Event handlers for menu filtering
	*/
	$("#menu-filter").on("keypress", function(event) {
		var match = $(this).val();
		if (event.which == 13) {
			event.preventDefault();
			if (match > "") {
				$("#filter").trigger("click");
			}
		}
		if (event.which == 27 || $.trim(match) === "") {
			$("#clrsrch").trigger("click");
		}
	}).trigger("focus");

	if (navigator.userAgent.indexOf('MSIE') >= 0) { // MSIE
		placeholder();
		$("input[type=text]").focusin(function() {
			var phvalue = $(this).attr("placeholder");
			if (phvalue == $(this).val()) {
				$(this).val("");
			}
		});
		$("input[type=text]").focusout(function() {
			var phvalue = $(this).attr("placeholder");
			if ($(this).val() === "") {
				$(this).val(phvalue);
			}
		});
		$("#menu-filter").trigger("blur");
	}

	$("#savecontent").on("submit", function(event) {
		var conf = confirm("This will generate file named <debug.txt> containing HTML code of main page. Please save it to disk and attach to the bugreport");
		if (conf === true) {
			var postDataObj = {
				html: "<!-- " + navigator.userAgent + "-->\n" + $("#content").html()
			};
			var postData = "<!-- " + navigator.userAgent + "-->\n" + $("#content").html();
			$("#tosave").val(postData);
			return;
		} else {
			event.preventDefault();
		}

	});

	$("#envdump").button().on("click", function() {
		$.get("/lpar2rrd-cgi/genjson.sh?jsontype=test", function(data) {
			alert(data);
		});
	});

	$("#switchstyle").on("change", function() {
		if ($(this).is(":checked")) {
			$('#style[rel=stylesheet]').attr("href", "css/darkstyle.css");
		} else {
			$('#style[rel=stylesheet]').attr("href", "css/style.css");
		}
	});
	/*
	$("#nmonsw input").checkboxradio();
	$("#nmonsw input").on("click", function() {
		sections();
		var newTabHref = '';
		var activeTab = $('#tabs li.ui-tabs-active.tabagent,#tabs li.ui-tabs-active.tabnmon').text();
		showHideSwitch();
		if (activeTab) {
			if ($("#nmr1").is(":checked")) {
				newTabHref = $('#tabs li.tabagent a:contains("' + activeTab + '")').attr("href");
			} else {
				newTabHref = $('#tabs li.tabnmon a:contains("' + activeTab + '")').attr("href");
			}
			$("[href='" + newTabHref + "']").trigger("click");
		}
	});
	*/

	$("#confsw input").checkboxradio();
	$("#confsw input").on("click", function(event) {
		var newTabHref = '';
		var activeTab = $('#tabs li.ui-tabs-active.hmcsum,#tabs li.ui-tabs-active.hmcdet').text();
		showHideCfgSwitch();
		if (activeTab) {
			if ($("#cfg1").is(":checked")) {
				newTabHref = $('#tabs li.hmcsum a:contains("' + activeTab + '")').attr("href");
			} else {
				newTabHref = $('#tabs li.hmcdet a:contains("' + activeTab + '")').attr("href");
			}
			$("[href='" + newTabHref + "']").trigger("click");
		}
	});

	if(!inXormon) {
		setInterval(function () {
			checkStatus(["OracleDB", "Nutanix", "PostgreSQL", "SQLServer", "DB2"]);
		}, 600000);
	}

	$("#pdf").on("click", function(event) {
		genPdf(img2pdf());
	});
	$("#xls").on("click", function(event) {
		genXls(img2pdf());
	});

	$("#resizer").draggable({
		// animate: true,
		axis: "x",
		cursor: "move",
		stop: function( event, ui ) {
			var newWidth = ui.position.left;
			if (newWidth < 50) {
				newWidth = 50;
				$(this).offset({ left: newWidth });
			}
			lessVars.sideBarWidth = newWidth + 'px';
			less.modifyVars( lessVars );
			$.cookie('sideBarWidth', newWidth, {
				expires: 360
			});
		}
	});

	$(document).off("click", "a.savetofile").on("click", "a.savetofile", function(ev) {
		ev.preventDefault();
		$("body").css("cursor", "progress");
		$(ev.target).css("cursor", "progress");
		$.ajax({
			type: "GET",
			url: ev.currentTarget.href,
			dataType: 'binary',
			xhrFields: {
				responseType: 'binary' // to avoid binary data being mangled on charset conversion
			},
			success: function(data, status, xhr) {
				$("body").css("cursor", "default");
				$(ev.target).css("cursor", "pointer");
				// check for a filename
				var filename = "";
				var disposition = xhr.getResponseHeader('Content-Disposition');
				if (disposition && disposition.indexOf('attachment') !== -1) {
					var filenameRegex = /filename[^;=\n]*=((['"]).*?\2|[^;\n]*)/;
					var matches = filenameRegex.exec(disposition);
					if (matches != null && matches[1]) {
						filename = matches[1].replace(/['"]/g, '');
					}
				}

				if (typeof window.navigator.msSaveBlob !== 'undefined') {
					// IE workaround for "HTML7007: One or more blob URLs were revoked by closing the blob for which they were created. These URLs will no longer resolve as the data backing the URL has been freed."
					window.navigator.msSaveBlob(data, filename);
				} else {
					var URL = window.URL || window.webkitURL;
					var blob = new Blob([data], {type: 'application/pdf'});
					var downloadUrl = URL.createObjectURL(blob);

					if (filename) {
						// use HTML5 a[download] attribute to specify filename
						var a = document.createElement("a");
						// safari doesn't support this yet
						if (typeof a.download === 'undefined') {
							window.location.href = downloadUrl;
						} else {
							a.href = downloadUrl;
							a.download = filename;
							document.body.appendChild(a);
							a.click();
						}
					} else {
						window.location.href = downloadUrl;
					}
					setTimeout(function () { URL.revokeObjectURL(downloadUrl); }, 100); // cleanup
				}
			}
		});
	});

	/*
	var show_menu = document.querySelector('.show_menu_btn');

	if (show_menu) {
		show_menu.addEventListener('click', function(event) {
			var target = document.querySelector(show_menu.getAttribute('data-target'));

			if (target.style.display == "none") {
				// target.style.display = "block";
				$("#toolbar,#menusw,#footer,#side-menu").show();
				show_menu.innerHTML = show_menu.getAttribute('data-shown-text');
				if ($.cookie('sideBarWidth')) {
					less.modifyVars({ sideBarWidth : $.cookie('sideBarWidth') + 'px' });
				}
			} else {
				// target.style.display = "none";
				$("#toolbar,#menusw,#footer,#side-menu").hide();
				show_menu.innerHTML = show_menu.getAttribute('data-hidden-text');
				if ($("#resizer").offset().left > 0) {
					$.cookie('sideBarWidth', $("#resizer").offset().left, {
						expires: 360
					});
				}
				less.modifyVars({ sideBarWidth : 0 + 'px' });
			}
		});
	}
	*/

}

function imgPaths() {
	$('#content img').each(function() { /* subpage without tabs */
		var imgsrc = $(this).attr("src");
		if (/loading\.gif$/.test(imgsrc)) {
			$(this).attr("src", 'css/images/sloading.gif');
		} else if (!/\//.test(imgsrc)) {
			var n = $('#side-menu').fancytree('getActiveNode');
			var url = n.data.href;

			$(this).attr("src", url.substr(0, url.lastIndexOf('/') + 1) + imgsrc);
		}
	});
}

function autoRefresh() {
	if (timeoutHandle) {
		clearTimeout(timeoutHandle);
	}
	if (inXormon) {
		return;
	}
	timeoutHandle = setTimeout(function() {
		$("#side-menu").fancytree("getTree").reactivate();
		autoRefresh();
	}, 300000); /* 300000 = 5 minutes */
}

/********* Execute after new content load */

function myreadyFunc() {
	var val;

	if (sysInfo.demo) {
		$("#demo-notice").removeClass("hidden");
	}
	if(sysInfo.xormonUIonly) {
		$("#demo-notice").html("Application UI is disabled, please use Xormon UI instead").removeClass("hidden");
	}

	var dbHashes = $.cookie('dbHashes');
	$("div.zoom").uniqueId();
	$("#pdf").hide();
	$("#xls").hide();

	if (!dbHashes) {
		dbHash = [];
	} else {
		dbHash = dbHashes.split(":");
		$.each(dbHash, function(index, value) {
			if (value.length == 11) {
				dbHash[index] = value.substr(0, 7) + "x" + value.substr(7);
			}
		});
	}

	$('#tabs').tabs({
		overflowTabs: true,
		tabPadding: 23,
		containerPadding: 40,
		create: function( event, ui ) {
			var tabTitles = $( "#tabs li a" ).map(function(i, el) {
				return $(el).text();
			}).get();
			if (forceTab != "") {
				curTab = forceTab;
				forceTab = "";
			} else {
				var tabPos = jQuery.inArray( lastTabName, tabTitles );
				if (tabPos !== -1) {
					curTab = tabPos;
				} else {
					var lastTabNmon = lastTabName.substring(0, lastTabName.length - 2);
					tabPos = jQuery.inArray( lastTabNmon, tabTitles );
					if (tabPos !== -1) {
						curTab = tabPos;
					}
					//else {
					//	curTab = 0;
					//}
				}
			}
			$( "#tabs" ).tabs( "option", "active", curTab );
			// if (!$(".regroup").length && curNode.data.obj && (curNode.data.obj == "P" || curNode.data.obj == "L" || curNode.data.obj == "VM")) {
			if (!$(".regroup").length && $("#content img.lazy").length && curNode.title != "Historical reports" && ! curNode.hasClass("noregroup")) {
				$("#content").append("<div class='regroup fwd'><a href='' alt='Regroup' title='Regroup'></a></div>");
			}
			//*************** NMON Tabs
			$("li.tabnmon a").text(function(i, val) {
				return val.replace('-N', '');
			});
		},
		beforeLoad: function( event, ui ) {
			ui.panel.html('<img src="css/images/sloading.gif" style="display: block; margin-left: auto; margin-right: auto; margin-top: 10em" />');
			if (curNode && curNode.data.href == "overview_power.html") {
				$(ui.panel).siblings('.ui-tabs-panel').empty();
				$("#overviewdiv").empty();
			}
			if ( $(event.target).hasClass('tabbed_cfg') ) {
				$(ui.panel).siblings('.ui-tabs-panel').empty();
			}
		},
		activate: function(event, ui) {
			curTab = ui.newTab.index();
			lastTabName = $('#tabs li.ui-tabs-active').text();
			if ( $('#tabs li.ui-tabs-active').hasClass("tabnmon") && lastTabName.slice(-2) != "-N" ) {
				lastTabName += "-N";
			}
			var tabName = "";
			if ($("#tabs").length) {
				tabName = " [" + $('#tabs li.ui-tabs-active').text() + "]";
			}
			if (curNode) {
				if (curNode.data.hash) {
					urlMenu = curNode.data.hash;
				} else {
					urlMenu = curNode.key.substring(1);
				}
				History.pushState({
					menu: curNode.key,
					tab: curTab
				}, prodName + $("#title").text() + tabName, '?menu=' + urlMenu + "&tab=" + curTab);
			}
			setTitle(curNode);

			if ($("#emptydash").length) {
				// genDashboard();
				autoRefresh();
			} else {
				autoRefresh();
				loadImages("#" + ui.newPanel.attr('id') + " img.lazy");
				// if (!$(".regroup").length && $("#content img.lazy").length && curNode.title != "Historical reports") {
				// 	$("#content").append("<div class='regroup fwd'><a href='' alt='Regroup' title='Regroup'></a></div>");
				//}
				hrefHandler();
				// showHideSwitch();
				showHideCfgSwitch();
				sections();
			}
		},
		load: function(event, ui) {
			//if (!$(".regroup").length && $("#content img.lazy").length && curNode.title != "Historical reports") {
			//	$("#content").append("<div class='regroup fwd'><a href='' alt='Regroup' title='Regroup'></a></div>");
			//}
			if ( $(event.target).hasClass('tabbed_cfg') ) {
				myreadyFunc();
				return;
			}
			hrefHandler();
			var $t = ui.panel.find('table.tablesorter');
			if ($t.length) {
				tableSorter($t);
			}
			if ($("#aclgrptree").length) {
				if (timeoutHandle) {
					clearTimeout(timeoutHandle);
				}
				ACLcfg();
			}
			$("#rephistory").tablesorter({
				widgets : [ "group" ],
				theme: "ice",
				ignoreCase: false,
				sortList: [[0,0]],
				// initialized: function(table) {
				//	$("#mirroring").find(".group-name:empty()").parents("tr").trigger('toggleGroup');
				//},
				textExtraction : function(node, table, cellIndex) {
					n = $(node);
					return n.attr('data-sortValue') || n.text();
				},
				widgetOptions : {
					//group_collapsed: false,
					//group_saveGroups: false,
					// group_forceColumn: [0],
					group_callback : function($cell, $rows, column, table) {
						var colspan = $cell.find('.group-name').parent().prop("colspan");
						$cell.find('.group-name').parent().prop("colspan", colspan - 1);
						$cell.find('.group-name').parent().after("<td class='remrepgr'><div class='delete group'></div></td>");
					}
				},
				headers: {
					2: { sorter: 'metric' }
				}
			});
			$("#rephistory div.delete").on("click", function(event) {
				var isGroup = $(this).hasClass("group");
				var cstr = isGroup ? "Are you sure you want to delete all history of this report?" : "Are you sure you want to delete this report?";
				$.confirm(
					cstr,
					"Report delete confirmation",
					function() {
						var repname, repfile, cmd;
						if (isGroup) {
							repname = $(event.target).parent().siblings().find(".group-name").text();
							cmd = "remdir";
						} else {
							repname = $(event.target).parent().parent().find(".repname").text();
							repfile = $(event.target).parent().parent().find(".repfile").text();
							cmd = "remrep";
						}
						var postdata = {cmd: cmd, repfile: repfile, repname: repname};

						$.getJSON(cgiPath + '/reporter.sh', postdata, function(data) {
							if (data.success) {
								$("#side-menu").fancytree("getTree").reactivate();
							} else {
								alert(data.log);
							}
						});
					}
				);
			});
			$("#table-multipath").tablesorter({
				widgets : [ "group" ],
				theme: "ice",
				ignoreCase: false,
				sortList: [[5,1]],
				// initialized: function(table) {
				//	$("#mirroring").find(".group-name:empty()").parents("tr").trigger('toggleGroup');
				//},
				//
				/*
				textExtraction : function(node, table, cellIndex) {
					n = $(node);
					return n.attr('data-sortValue') || n.text();
				}
				*/
				widgetOptions : {
					//group_collapsed: false,
					//group_saveGroups: false,
					// group_forceColumn: [0],
					group_callback : function($cell, $rows, column, table) {
						if (column === 5) {
							$rows.each(function() {
								var grpName = $(this).find("td").eq(5).text();
								$cell.find('.group-name').text( grpName );
								return false;
							});
						}
					}
				},
			});
			overview_handler();
		}
	});

	setTimeout(function() {
		if ($("#tabs").length) {
			loadImages("div[aria-hidden=false] img.lazy");
		} else {
			loadImages('#content img.lazy');
		}
	}, 100);

	$("table.tablesorter").each(function() {
		tableSorter(this);
	});

	hrefHandler();

	$("#subheader fieldset").hide();


	$("#radio").buttonset();
	$("#radiosrc").hide();

	$("input[type=checkbox][name=lparset]").on("change", function() {
		if ($("#radios2").is(':checked')) {
			$("#lpartree").fancytree("getTree").reload({
				url: '/lpar2rrd-cgi/genjson.sh?jsontype=hmcsel'
			});
			$("#lparfieldset legend span").html("HMC | Server | LPAR");
		} else {
			$("#lpartree").fancytree("getTree").reload({
				url: '/lpar2rrd-cgi/genjson.sh?jsontype=lparselest'
			});
			$("#lparfieldset legend span").html("Server | LPAR");
		}
	});

	$("#radio1").on("click", function() {
		$("#pooltree").fancytree("enable");
		$("#treetable").fancytree("disable");
	});
	$("#radio2").on("click", function() {
		$("#pooltree").fancytree("disable");
		$("#treetable").fancytree("enable");
	});

	fancyBox();

	var now = new Date();
	var twoWeeksBefore = new Date();
	var yesterday = new Date();
	var nowPlusHour = new Date();
	yesterday.setDate(now.getDate() - 1);
	twoWeeksBefore.setDate(now.getDate() - 14);
	nowPlusHour.setHours(now.getHours() + 1);

	$("#from").datetimepicker({
		defaultDate: '-2w',
		dateFormat: "yy-mm-dd",
		maxDate: "0",
		changeMonth: true,
		changeYear: true,
		showButtonPanel: true,
		showOtherMonths: true,
		selectOtherMonths: true,
		showTimepicker: false,
		onClose: function(selectedDate) {
			$("#to").datetimepicker("option", "minDate", selectedDate);
		}
	});
	if ($("#from").length) {
		var from = new Date(parseInt($.cookie('fromField')));
		if ( !isNaN(from) ) {
			$("#from").datetimepicker("setDate", from);
		} else {
			$("#from").datetimepicker("setDate", twoWeeksBefore);
		}
	}

	$("#to").datetimepicker({
		defaultDate: 0,
		dateFormat: "yy-mm-dd",
		maxDate: '0',
		changeMonth: true,
		changeYear: true,
		showButtonPanel: true,
		showOtherMonths: true,
		selectOtherMonths: true,
		showTimepicker: false,
		onClose: function(selectedDate) {
			$("#from").datetimepicker("option", "maxDate", selectedDate);
		}
	});
	if ($("#to").length) {
		var to = new Date(parseInt($.cookie('toField')));
		if ( !isNaN(to) ) {
			$("#to").datetimepicker("setDate", to);
		} else {
			$("#to").datetimepicker("setDate", now);
		}
	}

	var startDateTextBox = $('#fromTime'),
	endDateTextBox = $('#toTime');

	$("#fromTime").datetimepicker({
		defaultDate: '-1d',
		dateFormat: "yy-mm-dd",
		timeFormat: "HH:00",
		maxDate: nowPlusHour,
		changeMonth: true,
		changeYear: true,
		showButtonPanel: true,
		showOtherMonths: true,
		selectOtherMonths: true,
		showMinute: false,
		onClose: function(dateText, inst) {
			if (endDateTextBox.val() !== '') {
				var testStartDate = startDateTextBox.datetimepicker('getDate');
				var testEndDate = endDateTextBox.datetimepicker('getDate');
				if (testStartDate > testEndDate) {
					endDateTextBox.datetimepicker('setDate', testStartDate);
				}
			} else {
				endDateTextBox.val(dateText);
			}
		},
		onSelect: function(selectedDateTime) {
			endDateTextBox.datetimepicker('option', 'minDate', startDateTextBox.datetimepicker('getDate'));
		}
	});
	if ($("#fromTime").length) {
		var fromTime = new Date(parseInt($.cookie('fromTimeField')));
		if ( !isNaN(fromTime) ) {
			$("#fromTime").datetimepicker("setDate", fromTime);
		} else {
			$("#fromTime").datetimepicker("setDate", yesterday);
		}
	}

	$("#toTime").datetimepicker({
		defaultDate: 0,
		dateFormat: "yy-mm-dd",
		timeFormat: "HH:00",
		maxDate: nowPlusHour,
		changeMonth: true,
		changeYear: true,
		showButtonPanel: true,
		showOtherMonths: true,
		selectOtherMonths: true,
		showMinute: false,
		onClose: function(dateText, inst) {
			if (startDateTextBox.val() !== '') {
				var testStartDate = startDateTextBox.datetimepicker('getDate');
				var testEndDate = endDateTextBox.datetimepicker('getDate');
				if (testStartDate > testEndDate) {
					startDateTextBox.datetimepicker('setDate', testEndDate);
				}
			} else {
				startDateTextBox.val(dateText);
			}
		},
		onSelect: function(selectedDateTime) {
			startDateTextBox.datetimepicker('option', 'maxDate', endDateTextBox.datetimepicker('getDate'));
		}
	});
	if ($("#toTime").length) {
		var toTime = new Date(parseInt($.cookie('toTimeField')));
		if ( !isNaN(toTime) ) {
			$("#toTime").datetimepicker("setDate", toTime);
		} else {
			$("#toTime").datetimepicker("setDate", now);
		}
	}

	if ($("#srcfix").length) {
		val = $.cookie('srcFix');
		if ( val ) {
			$("#srcfix").prop("checked", val);
		}
	}

	if ($("#dstfix").length) {
		val = $.cookie('dstFix');
		if ( val ) {
			$("#dstfix").prop("checked", val);
		}
	}

	$("#formestimator").on("submit", function(event) {
		var lt, pt, nt;
		if ($("#lpartree").fancytree("getTree").getSelectedNodes().length === 0) {
			alert("Select at least one LPAR for migration");
			return false;
		} else if ($("#radio1").is(':checked') && !$("#pooltree").fancytree("getActiveNode")) {
			alert("Select an existing server/pool for migration");
			return false;
		} else if ($("#radio2").is(':checked') && !$("#treetable").fancytree("getActiveNode")) {
			alert("Select new target server for migration");
			return false;
		} else if (sysInfo.free == 1 && $('select[name=yaxis] option:selected').val() != "c") {
			var ttmp = '<div><p>rPerf and CPW based estimations are not available in LPAR2RRD Free Edition.</p>' +
						'<p>Consider the <a href="https://lpar2rrd.com/support.htm#benefits" target="_blank"><b>Enterprise Edition</b></a> or use CPU core based estimation.</p>' +
						'<p>Note that comparing of CPU load based on CPU cores for different IBM Power systems models is only informative.</p></div>';
			$( ttmp ).dialog({
				dialogClass: "info",
				minWidth: 500,
				modal: true,
				title: "Free Edition notice",
				show: {
					effect: "fadeIn",
					duration: 500
				},
				hide: {
					effect: "fadeOut",
					duration: 200
				},
				buttons: {
					OK: function() {
						$(this).dialog("close");
					}
				}
			});
			return false;
		}
		$("#lpartree").fancytree("getTree").generateFormElements(true, false, { stopOnParents: false });
		lt = '&ft_' + $("#lpartree").fancytree("getTree")._id + '(_active)?=';
		if ($("#radio1").is(':checked')) {
			$("#pooltree").fancytree("getTree").generateFormElements(true, true);
			pt = '&ft_' + $("#pooltree").fancytree("getTree")._id + '_active=';
		} else {
			$("#treetable").fancytree("getTree").generateFormElements(true, true);
			nt = '&ft_' + $("#treetable").fancytree("getTree")._id + '_active=';
		}

		var fromDate = $("#from").datepicker("getDate");
		var toDate = $("#to").datepicker("getDate");
		$.cookie('fromField', fromDate.valueOf(), {
			expires: 0.04
		});
		$.cookie('toField', toDate.valueOf(), {
			expires: 0.04
		});
		$.cookie('srcFix', $("#srcfix").prop('checked'), {
			expires: 0.04
		});
		$.cookie('dstFix', $("#dstfix").prop('checked'), {
			expires: 0.04
		});

		$("#start-hour").val(now.getHours());
		$("#start-day").val(fromDate.getDate());
		$("#start-mon").val(fromDate.getMonth() + 1);
		$("#start-yr").val(fromDate.getFullYear());

		$("#end-hour").val(now.getHours());
		$("#end-day").val(toDate.getDate());
		$("#end-mon").val(toDate.getMonth() + 1);
		$("#end-yr").val(toDate.getFullYear());

		var postData = $('select,input[name!=lparset]', this).serialize().replace(/\+/g, "%20");
		postData = postData.replace(/%5B%5D/g, '');

		var re = new RegExp(lt, "g");
		postData = postData.replace(re, "&LPAR=");
		postData = postData.replace(/&LPAR=_[^&]+/g, '');
		var lparPos = postData.indexOf('&LPAR');
		var firstPart = postData.slice(0, lparPos);

		if ($("#radio1").is(':checked')) {
			postData = postData.replace(pt, "&POOL=");
			newPos = postData.indexOf('&POOL=');
			lparPart = postData.slice(lparPos, newPos);
			newPart = postData.slice(newPos);
		} else {
			postData = postData.replace(nt, "&NEW=");
			newPos = postData.indexOf('&NEW=');
			lparPart = postData.slice(lparPos, newPos);
			newPart = postData.slice(newPos);
		}

		postData = firstPart + newPart + lparPart;

		if (sysInfo.guidebug == 1) {
			copyToClipboard(postData);
		}
		var postObj = queryStringToHash(postData),
		posting = $.post(this.action, postObj);

		posting.done(function(data) {
			$('#content').empty().append(data);
			if (curNode.data.hash) {
				urlMenu = curNode.data.hash;
			} else {
				urlMenu = curNode.key.substring(1);
			}
			History.pushState({
				menu: curNode.key,
				tab: curTab,
				form: "cwe"
			}, prodName + "CPU Workload Estimator Form Results", '?menu=' + urlMenu + "&tab=" + curTab);
			imgPaths();
			myreadyFunc();
			saveData("cwe"); // save when page loads
		});
		event.preventDefault();
		if (timeoutHandle) {
			clearTimeout(timeoutHandle);
		}
	});

	// Global history reports form submit
	$("#histrepg").on("submit", function(event) {
		event.preventDefault();
		if (sysInfo.basename || sysInfo.variant.indexOf('p') == -1) {
			$.message(hrepinfo, "Edition limitation");
		} else {
			if ($("#lpartree").fancytree("getTree").getSelectedNodes().length === 0 &&
				$("#hpooltree").fancytree("getTree").getSelectedNodes().length === 0 &&
					$("#custompowertree").fancytree("getTree").getSelectedNodes().length === 0) {
				alert("Select at least one LPAR, CPU pool or Custom Group");
			return false;
			}
			$("#lpartree").fancytree("getTree").generateFormElements(true, false, { stopOnParents: false });
			lta = 'ft_' + $("#lpartree").fancytree("getTree")._id + "[]";
			$("#hpooltree").fancytree("getTree").generateFormElements(true, true, { stopOnParents: false });
			pta = 'ft_' + $("#hpooltree").fancytree("getTree")._id + "[]";
			$("#custompowertree").fancytree("getTree").generateFormElements(true, false, false);
			cta = 'ft_' + $("#custompowertree").fancytree("getTree")._id + "[]";

			var fromDate = $("#fromTime").datetimepicker("getDate"),
			toDate = $("#toTime").datetimepicker("getDate");

			$.cookie('fromTimeField', fromDate.valueOf(), {
				expires: 0.04
			});
			$.cookie('toTimeField', toDate.valueOf(), {
				expires: 0.04
			});

			$("#start-hour").val(fromDate.getHours());
			$("#start-day").val(fromDate.getDate());
			$("#start-mon").val(fromDate.getMonth() + 1);
			$("#start-yr").val(fromDate.getFullYear());

			$("#end-hour").val(toDate.getHours());
			$("#end-day").val(toDate.getDate());
			$("#end-mon").val(toDate.getMonth() + 1);
			$("#end-yr").val(toDate.getFullYear());

			// remove parent items if whole branch checked
			var postArray = $(this).not(".allcheck").serializeArray();
			for (var i = 0; i < postArray.length; i++) {
				if (postArray[i].value.indexOf('_') === 0) {
					postArray.splice(i, 1);
					i--;
				}
			}
			// replace fancytree fieldnames ft_...
			$.each(postArray, function(index, value) {
				if (value.name == lta) {
					value.name = 'LPAR';
				} else if (value.name == pta) {
					value.name = 'POOL';
				} else if (value.name == cta) {
					value.name = 'CGROUP';
				}
			});

			var qString = $.param(postArray).replace(/\+/g, "%20");

			if (sysInfo.guidebug == 1) {
				copyToClipboard(qString);
			}
			postArray = queryStringToHash(qString);

			if (inXormon) {
				return postArray;
			}

			var posting = $.post(this.action, postArray);

			posting.done(function(data) {
				$('#content').empty().append(data);
				if (curNode.data.hash) {
					urlMenu = curNode.data.hash;
				} else {
					urlMenu = curNode.key.substring(1);
				}
				History.pushState({
					menu: curNode.key,
					tab: curTab,
					form: "hrepg"
				}, prodName + "Global History Form Results", '?menu=' + urlMenu + "&tab=" + curTab);
				imgPaths();
				myreadyFunc();
				$("#pdf").show();
				$("#xls").show();
				saveData("hrepg"); // save when page loads
			});
		}
		if (timeoutHandle) {
			clearTimeout(timeoutHandle);
		}
	});

	// Custom group history reports form submit
	$("#histrepcustom").on("submit", function(event) {
		event.preventDefault();
		if (sysInfo.basename) {
			$.message(hrepinfo, "Free Edition limitation");
		} else {
			if ($("#customtree").fancytree("getTree").getSelectedNodes().length === 0) {
				alert("Select at least one Custom Group");
				return false;
			}
			$("#customtree").fancytree("getTree").generateFormElements(true, false, false);
			cta = 'ft_' + $("#customtree").fancytree("getTree")._id + "[]";

			var fromDate = $("#fromTime").datetimepicker("getDate"),
			toDate = $("#toTime").datetimepicker("getDate");

			$.cookie('fromTimeField', fromDate.valueOf(), {
				expires: 0.04
			});
			$.cookie('toTimeField', toDate.valueOf(), {
				expires: 0.04
			});

			$("#start-hour").val(fromDate.getHours());
			$("#start-day").val(fromDate.getDate());
			$("#start-mon").val(fromDate.getMonth() + 1);
			$("#start-yr").val(fromDate.getFullYear());

			$("#end-hour").val(toDate.getHours());
			$("#end-day").val(toDate.getDate());
			$("#end-mon").val(toDate.getMonth() + 1);
			$("#end-yr").val(toDate.getFullYear());

			// remove parent items if whole branch checked
			var postArray = $(this).not(".allcheck").serializeArray();
			for (var i = 0; i < postArray.length; i++) {
				if (postArray[i].value.indexOf('_') === 0) {
					postArray.splice(i, 1);
					i--;
				}
			}
			// replace fancytree fieldnames ft_...
			$.each(postArray, function(index, value) {
				if (value.name == lta) {
					value.name = 'LPAR';
				} else if (value.name == pta) {
					value.name = 'POOL';
				} else if (value.name == cta) {
					value.name = 'CGROUP';
				}
			});

			var qString = $.param(postArray).replace(/\+/g, "%20");

			if (sysInfo.guidebug == 1) {
				copyToClipboard(qString);
			}
			postArray = queryStringToHash(qString);

			if (inXormon) {
				return postArray;
			}

			var posting = $.post(this.action, postArray);

			posting.done(function(data) {
				$('#content').empty().append(data);
				if (curNode.data.hash) {
					urlMenu = curNode.data.hash;
				} else {
					urlMenu = curNode.key.substring(1);
				}
				History.pushState({
					menu: curNode.key,
					tab: curTab,
					form: "hrepcustom"
				}, prodName + "Custom Group History Form Results", '?menu=' + urlMenu + "&tab=" + curTab);
				imgPaths();
				myreadyFunc();
				$("#pdf").show();
				$("#xls").show();
				saveData("hrepcustom"); // save when page loads
			});
		}
		if (timeoutHandle) {
			clearTimeout(timeoutHandle);
		}
	});

	// Linux History reports form submit
	$("#histrepl").on("submit", function(event) {
		event.preventDefault();
		if (sysInfo.basename || sysInfo.variant.indexOf('l') == -1) {
			$.message(hrepinfo, "Edition limitation");
		} else {
			if ($("#linuxtree").fancytree("getTree").getSelectedNodes().length === 0) {
				alert("Select at least one item for report");
				return false;
			}
			$("#linuxtree").fancytree("getTree").generateFormElements(true, false, false);
			lta = 'ft_' + $("#linuxtree").fancytree("getTree")._id + "[]";

			var fromDate = $("#fromTime").datetimepicker("getDate");
			var toDate = $("#toTime").datetimepicker("getDate");

			$.cookie('fromTimeField', fromDate.valueOf(), {
				expires: 0.04
			});
			$.cookie('toTimeField', toDate.valueOf(), {
				expires: 0.04
			});

			$("#start-hour").val(fromDate.getHours());
			$("#start-day").val(fromDate.getDate());
			$("#start-mon").val(fromDate.getMonth() + 1);
			$("#start-yr").val(fromDate.getFullYear());

			$("#end-hour").val(toDate.getHours());
			$("#end-day").val(toDate.getDate());
			$("#end-mon").val(toDate.getMonth() + 1);
			$("#end-yr").val(toDate.getFullYear());

			// get HMC & server name from menu url
			// var serverPath = $("#side-menu").fancytree('getActiveNode').data.href.split('/');
			$("#hmc").val("no_hmc");
			$("#mname").val("Linux--unknown");


			// remove parent items if whole branch checked
			var postArray = $(this).serializeArray();
			for (var i = 0; i < postArray.length; i++) {
				if (postArray[i].value.indexOf('_') === 0) {
					postArray.splice(i, 1);
					i--;
				}
			}
			// replace fancytree fieldnames ft_...
			$.each(postArray, function(index, value) {
				if (value.name == lta) {
					value.name = 'LPAR';
				}
			});
			var postData = $.param(postArray).replace(/\+/g, "%20");

			if (sysInfo.guidebug == 1) {
				copyToClipboard(postData);
				// alert("POST data:\n" + postData);
			}

			if (inXormon) {
				return postData;
			}

			$('#content').load(this.action, postData, function() {
				if (curNode.data.hash) {
					urlMenu = curNode.data.hash;
				} else {
					urlMenu = curNode.key.substring(1);
				}
				History.pushState({
					menu: curNode.key,
					tab: curTab,
					form: "hrep"
				}, prodName + "History Form Results", '?menu=' + urlMenu + "&tab=" + curTab);
				imgPaths();
				myreadyFunc();
				$("#pdf").show();
				$("#xls").show();
				saveData("hrep"); // save when page loads
			});
		}
		if (timeoutHandle) {
			clearTimeout(timeoutHandle);
		}
	});

	// Solaris History reports form submit
	$("#histrepsol").on("submit", function(event) {
		event.preventDefault();
		if (sysInfo.basename || sysInfo.variant.indexOf('s') == -1) {
			$.message(hrepinfo, "Edition limitation");
		} else {
			if ($("#histreptree-solaris").fancytree("getTree").getSelectedNodes().length === 0) {
				alert("Select at least one item for report");
				return false;
			}
			$("#histreptree-solaris").fancytree("getTree").generateFormElements(true, false, false);
			lta = 'ft_' + $("#histreptree-solaris").fancytree("getTree")._id + "[]";

			var fromDate = $("#fromTime").datetimepicker("getDate");
			var toDate = $("#toTime").datetimepicker("getDate");

			$.cookie('fromTimeField', fromDate.valueOf(), {
				expires: 0.04
			});
			$.cookie('toTimeField', toDate.valueOf(), {
				expires: 0.04
			});

			$("#start-hour").val(fromDate.getHours());
			$("#start-day").val(fromDate.getDate());
			$("#start-mon").val(fromDate.getMonth() + 1);
			$("#start-yr").val(fromDate.getFullYear());

			$("#end-hour").val(toDate.getHours());
			$("#end-day").val(toDate.getDate());
			$("#end-mon").val(toDate.getMonth() + 1);
			$("#end-yr").val(toDate.getFullYear());

			// get HMC & server name from menu url
			// var serverPath = $("#side-menu").fancytree('getActiveNode').data.href.split('/');
			$("#hmc").val("no_hmc");
			$("#mname").val("Solaris--unknown");


			// remove parent items if whole branch checked
			var postArray = $(this).serializeArray();
			for (var i = 0; i < postArray.length; i++) {
				if (postArray[i].value.indexOf('_') === 0) {
					postArray.splice(i, 1);
					i--;
				}
			}
			// replace fancytree fieldnames ft_...
			$.each(postArray, function(index, value) {
				if (value.name == lta) {
					value.name = 'LPAR';
				}
			});
			var postData = $.param(postArray).replace(/\+/g, "%20");

			if (sysInfo.guidebug == 1) {
				copyToClipboard(postData);
				// alert("POST data:\n" + postData);
			}

			if (inXormon) {
				return postData;
			}

			var posting = $.post(this.action, postArray);

			posting.done(function(data) {
				$('#content').empty().append(data);
				if (curNode.data.hash) {
					urlMenu = curNode.data.hash;
				} else {
					urlMenu = curNode.key.substring(1);
				}
				History.pushState({
					menu: curNode.key,
					tab: curTab,
					form: "hrepg"
				}, prodName + "Global History Form Results", '?menu=' + urlMenu + "&tab=" + curTab);
				imgPaths();
				myreadyFunc();
				$("#pdf").show();
				$("#xls").show();
				saveData("hrepg"); // save when page loads
			});
		}
		if (timeoutHandle) {
			clearTimeout(timeoutHandle);
		}
	});

	// Hyper-V History report form submit
	$("#histrephyperv").on("submit", function(event) {
		event.preventDefault();
		if (sysInfo.basename || sysInfo.variant.indexOf('h') == -1) {
			$.message(hrepinfo, "Edition limitation");
		} else {
			if ($("#histreptree-hyperv-server").fancytree("getTree").getSelectedNodes().length === 0 &&
				$("#histreptree-hyperv-vm").fancytree("getTree").getSelectedNodes().length === 0 ) {
				alert("Select at least one item for report");
				return false;
			}
			$("#histreptree-hyperv-server").fancytree("getTree").generateFormElements(true, false, false);
			var srv = 'ft_' + $("#histreptree-hyperv-server").fancytree("getTree")._id + "[]";
			$("#histreptree-hyperv-vm").fancytree("getTree").generateFormElements(true, false, false);
			var vm = 'ft_' + $("#histreptree-hyperv-vm").fancytree("getTree")._id + "[]";

			var fromDate = $("#fromTime").datetimepicker("getDate");
			var toDate = $("#toTime").datetimepicker("getDate");

			$.cookie('fromTimeField', fromDate.valueOf(), {
				expires: 0.04
			});
			$.cookie('toTimeField', toDate.valueOf(), {
				expires: 0.04
			});

			$("#start-hour").val(fromDate.getHours());
			$("#start-day").val(fromDate.getDate());
			$("#start-mon").val(fromDate.getMonth() + 1);
			$("#start-yr").val(fromDate.getFullYear());

			$("#end-hour").val(toDate.getHours());
			$("#end-day").val(toDate.getDate());
			$("#end-mon").val(toDate.getMonth() + 1);
			$("#end-yr").val(toDate.getFullYear());

			// get HMC & server name from menu url
			// var serverPath = $("#side-menu").fancytree('getActiveNode').data.href.split('/');
			$("#hmc").val("no_hmc");
			$("#mname").val("hyperv");


			// remove parent items if whole branch checked
			var postArray = $(this).serializeArray();
			for (var i = 0; i < postArray.length; i++) {
				if (postArray[i].value.indexOf('_') === 0) {
					postArray.splice(i, 1);
					i--;
				}
			}
			// replace fancytree fieldnames ft_...
			$.each(postArray, function(index, value) {
				if (value.name == srv || value.name == vm) {
					value.name = 'LPAR';
				}
			});
			var postData = $.param(postArray).replace(/\+/g, "%20");

			if (sysInfo.guidebug == 1) {
				copyToClipboard(postData);
				// alert("POST data:\n" + postData);
			}

			if (inXormon) {
				return postData;
			}

			var posting = $.post(this.action, postArray);

			posting.done(function(data) {
				$('#content').empty().append(data);
				if (curNode.data.hash) {
					urlMenu = curNode.data.hash;
				} else {
					urlMenu = curNode.key.substring(1);
				}
				History.pushState({
					menu: curNode.key,
					tab: curTab,
					form: "hrepg"
				}, prodName + "Global History Form Results", '?menu=' + urlMenu + "&tab=" + curTab);
				imgPaths();
				myreadyFunc();
				$("#pdf").show();
				$("#xls").show();
				saveData("hrepg"); // save when page loads
			});
		}
		if (timeoutHandle) {
			clearTimeout(timeoutHandle);
		}
	});

	// OracleVM history report form submit
	$("#histreporaclevm").on("submit", function(event) {
		event.preventDefault();
		if (sysInfo.basename || sysInfo.variant.indexOf('m') == -1) {
			$.message(hrepinfo, "Edition limitation");
		} else {
			if ($("#histreptree-oraclevm-server").fancytree("getTree").getSelectedNodes().length === 0 &&
				$("#histreptree-oraclevm-vm").fancytree("getTree").getSelectedNodes().length === 0 ) {
				alert("Select at least one item for report");
				return false;
			}
			$("#histreptree-oraclevm-server").fancytree("getTree").generateFormElements(true, false, false);
			var srv = 'ft_' + $("#histreptree-oraclevm-server").fancytree("getTree")._id + "[]";
			$("#histreptree-oraclevm-vm").fancytree("getTree").generateFormElements(true, false, false);
			var vm = 'ft_' + $("#histreptree-oraclevm-vm").fancytree("getTree")._id + "[]";

			var fromDate = $("#fromTime").datetimepicker("getDate");
			var toDate = $("#toTime").datetimepicker("getDate");

			$.cookie('fromTimeField', fromDate.valueOf(), {
				expires: 0.04
			});
			$.cookie('toTimeField', toDate.valueOf(), {
				expires: 0.04
			});

			$("#start-hour").val(fromDate.getHours());
			$("#start-day").val(fromDate.getDate());
			$("#start-mon").val(fromDate.getMonth() + 1);
			$("#start-yr").val(fromDate.getFullYear());

			$("#end-hour").val(toDate.getHours());
			$("#end-day").val(toDate.getDate());
			$("#end-mon").val(toDate.getMonth() + 1);
			$("#end-yr").val(toDate.getFullYear());

			// get HMC & server name from menu url
			// var serverPath = $("#side-menu").fancytree('getActiveNode').data.href.split('/');
			$("#hmc").val("no_hmc");
			$("#mname").val("oraclevm");


			// remove parent items if whole branch checked
			var postArray = $(this).serializeArray();
			for (var i = 0; i < postArray.length; i++) {
				if (postArray[i].value.indexOf('_') === 0) {
					postArray.splice(i, 1);
					i--;
				}
			}
			// replace fancytree fieldnames ft_...
			$.each(postArray, function(index, value) {
				if (value.name == srv || value.name == vm) {
					value.name = 'LPAR';
				}
			});
			var postData = $.param(postArray).replace(/\+/g, "%20");

			if (sysInfo.guidebug == 1) {
				copyToClipboard(postData);
				// alert("POST data:\n" + postData);
			}

			if (inXormon) {
				return postData;
			}

			var posting = $.post(this.action, postArray);

			posting.done(function(data) {
				$('#content').empty().append(data);
				if (curNode.data.hash) {
					urlMenu = curNode.data.hash;
				} else {
					urlMenu = curNode.key.substring(1);
				}
				History.pushState({
					menu: curNode.key,
					tab: curTab,
					form: "hrepg"
				}, prodName + "Global History Form Results", '?menu=' + urlMenu + "&tab=" + curTab);
				imgPaths();
				myreadyFunc();
				$("#pdf").show();
				$("#xls").show();
				saveData("hrepg"); // save when page loads
			});
		}
		if (timeoutHandle) {
			clearTimeout(timeoutHandle);
		}
	});

	// History reports form submit
	$("#histrep").on("submit", function(event) {
		if (sysInfo.basename) {
			$.message(hrepinfo, "Edition limitation");
		} else {
			if ($("#histreptree").fancytree("getTree").getSelectedNodes().length === 0) {
				alert("Select at least one item for report");
				return false;
			}
			$("#histreptree").fancytree("getTree").generateFormElements(true, false, false);
			lta = 'ft_' + $("#histreptree").fancytree("getTree")._id + "[]";

			var fromDate = $("#fromTime").datetimepicker("getDate");
			var toDate = $("#toTime").datetimepicker("getDate");

			$.cookie('fromTimeField', fromDate.valueOf(), {
				expires: 0.04
			});
			$.cookie('toTimeField', toDate.valueOf(), {
				expires: 0.04
			});

			$("#start-hour").val(fromDate.getHours());
			$("#start-day").val(fromDate.getDate());
			$("#start-mon").val(fromDate.getMonth() + 1);
			$("#start-yr").val(fromDate.getFullYear());

			$("#end-hour").val(toDate.getHours());
			$("#end-day").val(toDate.getDate());
			$("#end-mon").val(toDate.getMonth() + 1);
			$("#end-yr").val(toDate.getFullYear());

			// get HMC & server name from menu url
			// var serverPath = $("#side-menu").fancytree('getActiveNode').data.href.split('/');
			$("#hmc").val(curNode.data.hmc);
			$("#mname").val(curNode.data.srv);


			// remove parent items if whole branch checked
			var postArray = $(this).serializeArray();
			for (var i = 0; i < postArray.length; i++) {
				if (postArray[i].value.indexOf('_') === 0) {
					postArray.splice(i, 1);
					i--;
				}
			}
			// replace fancytree fieldnames ft_...
			$.each(postArray, function(index, value) {
				if (value.name == lta) {
					value.name = 'LPAR';
				}
			});
			var postData = $.param(postArray).replace(/\+/g, "%20");

			if (sysInfo.guidebug == 1) {
				copyToClipboard(postData);
				// alert("POST data:\n" + postData);
			}

			$('#content').load(this.action, postData, function() {
				if (curNode.data.hash) {
					urlMenu = curNode.data.hash;
				} else {
					urlMenu = curNode.key.substring(1);
				}
				History.pushState({
					menu: curNode.key,
					tab: curTab,
					form: "hrep"
				}, prodName + "History Form Results", '?menu=' + urlMenu + "&tab=" + curTab);
				imgPaths();
				myreadyFunc();
				$("#pdf").show();
				$("#xls").show();
				saveData("hrep"); // save when page loads
			});
		}
		event.preventDefault();
		if (timeoutHandle) {
			clearTimeout(timeoutHandle);
		}
	});

	// VMware Historical reports form submit
	$("#histrepv").on("submit", function(event) {
		event.preventDefault();
		if (sysInfo.basename || sysInfo.variant.indexOf('v') == -1) {
			$.message(hrepinfo, "Edition limitation");
		} else {
			if ($("#clstrtree").fancytree("getTree").getSelectedNodes().length === 0 &&
				$("#dstree").fancytree("getTree").getSelectedNodes().length === 0 &&
					$("#respooltree").fancytree("getTree").getSelectedNodes().length === 0 &&
						$("#vmtree").fancytree("getTree").getSelectedNodes().length === 0) {
				alert("Select at least one item for report");
			return false;
			}
			$("#clstrtree").fancytree("getTree").generateFormElements(true, false, false);
			cta = 'ft_' + $("#clstrtree").fancytree("getTree")._id + "[]";
			$("#dstree").fancytree("getTree").generateFormElements(true, false, { stopOnParents: false });
			dta = 'ft_' + $("#dstree").fancytree("getTree")._id + "[]";
			$("#respooltree").fancytree("getTree").generateFormElements(true, false, { stopOnParents: false });
			rta = 'ft_' + $("#respooltree").fancytree("getTree")._id + "[]";
			$("#vmtree").fancytree("getTree").generateFormElements(true, false, { stopOnParents: false });
			vta = 'ft_' + $("#vmtree").fancytree("getTree")._id + "[]";

			var fromDate = $("#fromTime").datetimepicker("getDate");
			var toDate = $("#toTime").datetimepicker("getDate");

			$.cookie('fromTimeField', fromDate.valueOf(), {
				expires: 0.04
			});
			$.cookie('toTimeField', toDate.valueOf(), {
				expires: 0.04
			});

			$("#start-hour").val(fromDate.getHours());
			$("#start-day").val(fromDate.getDate());
			$("#start-mon").val(fromDate.getMonth() + 1);
			$("#start-yr").val(fromDate.getFullYear());

			$("#end-hour").val(toDate.getHours());
			$("#end-day").val(toDate.getDate());
			$("#end-mon").val(toDate.getMonth() + 1);
			$("#end-yr").val(toDate.getFullYear());

			// get HMC & server name from current node
			$("#vcenter").val(getCurrentVcenter());


			// remove parent items if whole branch checked
			var postArray = $(this).serializeArray();
			for (var i = 0; i < postArray.length; i++) {
				if (postArray[i].value.indexOf('_') === 0) {
					postArray.splice(i, 1);
					i--;
				}
			}
			// replace fancytree fieldnames ft_...
			$.each(postArray, function(index, value) {
				if (value.name == cta) {
					value.name = 'CLUSTER';
				} else if (value.name == dta) {
					value.name = 'DATASTORE';
				} else if (value.name == rta) {
					value.name = 'RESPOOL';
				} else if (value.name == vta) {
					value.name = 'VM';
				}
			});
			var postData = $.param(postArray).replace(/\+/g, "%20");

			if (sysInfo.guidebug == 1) {
				copyToClipboard(postData);
				// alert("POST data:\n" + postData);
			}

			if (inXormon) {
				return postData;
			}

			$('#content').load(this.action, postData, function() {
				if (curNode.data.hash) {
					urlMenu = curNode.data.hash;
				} else {
					urlMenu = curNode.key.substring(1);
				}
				History.pushState({
					menu: curNode.key,
					tab: curTab,
					form: "hrep"
				}, prodName + "History Form Results", '?menu=' + urlMenu + "&tab=" + curTab);
				imgPaths();
				myreadyFunc();
				$("#pdf").show();
				if (/vMotion/i.test($('#tabs ul.ui-tabs-nav li a').text())) {
					$("#xls").show();
				}
				saveData("hrep"); // save when page loads
			});
		}
		if (timeoutHandle) {
			clearTimeout(timeoutHandle);
		}
	});

	// VMware Historical reports form submit
	$("#histrepesxi").on("submit", function(event) {
		if (sysInfo.basename || sysInfo.variant.indexOf('v') == -1) {
			$.message(hrepinfo, "Edition limitation");
		} else {
			if ($("#histreptree-esxi").fancytree("getTree").getSelectedNodes().length === 0) {
				alert("Select at least one item for report");
				return false;
			}
			$("#histreptree-esxi").fancytree("getTree").generateFormElements(true, false, { stopOnParents: false });
			vta = 'ft_' + $("#histreptree-esxi").fancytree("getTree")._id + "[]";

			var fromDate = $("#fromTime").datetimepicker("getDate");
			var toDate = $("#toTime").datetimepicker("getDate");

			$.cookie('fromTimeField', fromDate.valueOf(), {
				expires: 0.04
			});
			$.cookie('toTimeField', toDate.valueOf(), {
				expires: 0.04
			});

			$("#start-hour").val(fromDate.getHours());
			$("#start-day").val(fromDate.getDate());
			$("#start-mon").val(fromDate.getMonth() + 1);
			$("#start-yr").val(fromDate.getFullYear());

			$("#end-hour").val(toDate.getHours());
			$("#end-day").val(toDate.getDate());
			$("#end-mon").val(toDate.getMonth() + 1);
			$("#end-yr").val(toDate.getFullYear());

			// get HMC & server name from current node
			$("#vcenter").val(curNode.parent.parent.parent.parent.data.uuid);
			$("#esxi").val(curNode.parent.data.noalias);


			// remove parent items if whole branch checked
			var postArray = $(this).serializeArray();
			for (var i = 0; i < postArray.length; i++) {
				if (postArray[i].value.indexOf('_') === 0) {
					postArray.splice(i, 1);
					i--;
				}
			}
			// replace fancytree fieldnames ft_...
			$.each(postArray, function(index, value) {
				if (value.name == vta) {
					if ($.inArray(value.value, ['multiview','pool','mem','disk','net']) > -1) {
						value.name = value.value;
					} else {
						value.name = 'VM';
					}
				}
			});
			var postData = $.param(postArray).replace(/\+/g, "%20");

			if (sysInfo.guidebug == 1) {
				copyToClipboard(postData);
				// alert("POST data:\n" + postData);
			}

			$('#content').load(this.action, postData, function() {
				if (curNode.data.hash) {
					urlMenu = curNode.data.hash;
				} else {
					urlMenu = curNode.key.substring(1);
				}
				History.pushState({
					menu: curNode.key,
					tab: curTab,
					form: "hrep"
				}, prodName + "History Form Results", '?menu=' + urlMenu + "&tab=" + curTab);
				imgPaths();
				myreadyFunc();
				saveData("hrep"); // save when page loads
			});
		}
		event.preventDefault();
		if (timeoutHandle) {
			clearTimeout(timeoutHandle);
		}
	});

	$("form").has("input[value=pagingagg]").on("submit", function(event) { //paging agg form
		event.preventDefault();
		var postData = $(this).serialize();
		$('#content').load(this.action, postData, function() {
			imgPaths();
			myreadyFunc();
		});
	});

	//*************** Remove unwanted parent classes
	$('#content table.tabsyscfg').has('table').removeClass('tabsyscfg');
	$('#content table.tabtop10').has('table').removeClass('tabtop10');

	// showHideSwitch();
	showHideCfgSwitch();
	sections();

	if (navigator.userAgent.indexOf('MSIE 8.0') < 0) {
		$('#content a:not(.nowrap):contains("How it works")').wrap(function() {
			var url = this.href;
			return "<div id='hiw'><a href='" + url + "' target='_blank'><img src='css/images/help-browser.gif' alt='How it works?' title='How it works?'></a></div>";
		});
	}


	/*
		$("div.csvexport").click(function() {
			$(this).children("a").click();
		});
	*/

	extensions = ["persist", "filter"];
	if(!inXormon){
		extensions.push("glyph");
	}
	$("#lpartree").fancytree({
		extensions: extensions,
		persist: {
			cookiePrefix: "lpartree-"
		},
		filter: {
			mode: "hide",
			autoApply: true
		},
		glyph: {
			preset: "awesome5"
		},
		checkbox: true,
		selectMode: 3,
		click: function (event, data) {
			if (! data.node.folder && data.targetType !== 'checkbox') {
				data.node.toggleSelected();
			}
		},
		select: function(ev, data) {
			if (data.node.hasChildren()) {
				var status = data.node.selected;
				data.node.visit(function(node) {
					node.setSelected(status);
				});
			}
		},
		icon: false,
		clickFolderMode: 2,
		source: function(ev, data) {
			if ( $("#side-menu").fancytree('getActiveNode').title == "CPU Workload Estimator" ) {
				return {url: '/lpar2rrd-cgi/genjson.sh?jsontype=lparselest'};
			} else {
				return {url: '/lpar2rrd-cgi/genjson.sh?jsontype=lparsel'};
			}
		}
	});
	$("#srvlparfilter").on("keypress", function(e){
		var match = $(this).val();
		var $ltree = $("#lpartree").fancytree("getTree");

		if (e.which === 27 || $.trim(match) === "") {
			$ltree.clearFilter();
			return;
		}
		if (e && e.which === 13) {
			e.preventDefault();
			var n = $ltree.filterNodes(function (node) {
				return new RegExp(match, "i").test(node.title);
			}, true);
			$ltree.visit(function(node){
				if (!$(node.span).hasClass("fancytree-hide")) {
					node.setExpanded(true);
				}
			});
		}
	}).trigger("focus");
	$("#vmfilter").on("keypress", function(e){
		var match = $(this).val();
		var $ltree = $("#vmtree").fancytree("getTree");

		if (e.which === 27 || $.trim(match) === "") {
			$ltree.clearFilter();
			return;
		}
		if (e && e.which === 13) {
			e.preventDefault();
			var n = $ltree.filterNodes(function (node) {
				return new RegExp(match, "i").test(node.title);
			}, true);
			$ltree.visit(function(node){
				if (!$(node.span).hasClass("fancytree-hide")) {
					node.setExpanded(true);
				}
			});
		}
	}).trigger("focus");
	$("#dsfilter").on("keypress", function(e){
		var match = $(this).val();
		var $ltree = $("#dstree").fancytree("getTree");

		if (e.which === 27 || $.trim(match) === "") {
			$ltree.clearFilter();
			return;
		}
		if (e && e.which === 13) {
			e.preventDefault();
			var n = $ltree.filterNodes(function (node) {
				return new RegExp(match, "i").test(node.title);
			}, true);
			$ltree.visit(function(node){
				if (!$(node.span).hasClass("fancytree-hide")) {
					node.setExpanded(true);
				}
			});
		}
	}).trigger("focus");
	if ($("#histreptree").length) {
		$("#histreptree").fancytree({
			extensions: ["persist", "glyph"],
			persist: {
				cookiePrefix: "histreptree-"
			},
			glyph: {
				preset: "awesome5"
			},
			checkbox: true,
			selectMode: 2,
			click: function (event, data) {
				if (! data.node.folder && data.targetType !== 'checkbox') {
					data.node.toggleSelected();
				}
			},
			select: function(ev, data) {
				if (data.node.hasChildren()) {
					var status = data.node.selected;
					data.node.visit(function(node) {
						node.setSelected(status);
					});
				}
			},
			icon: false,
			clickFolderMode: 2,
			autoCollapse: true,
			source: {
				url: '/lpar2rrd-cgi/genjson.sh?' + histRepQueryString()
			}
		});
	}
	if ($("#histreptree-esxi").length) {
		$("#histreptree-esxi").fancytree({
			extensions: ["persist", "glyph"],
			persist: {
				cookiePrefix: "histreptree-esxi-"
			},
			glyph: {
				preset: "awesome5"
			},
			checkbox: true,
			selectMode: 2,
			click: function (event, data) {
				if (! data.node.folder && data.targetType !== 'checkbox') {
					data.node.toggleSelected();
				}
			},
			select: function(ev, data) {
				if (data.node.hasChildren()) {
					var status = data.node.selected;
					data.node.visit(function(node) {
						node.setSelected(status);
					});
				}
			},
			icon: false,
			clickFolderMode: 2,
			autoCollapse: false,
			source: {
				url: '/lpar2rrd-cgi/genjson.sh?' + histRepQueryString()
			}
		});
	}
	if ($("#histreptree-solaris").length) {
		$("#histreptree-solaris").fancytree({
			extensions: ["persist", "glyph"],
			persist: {
				cookiePrefix: "histreptree-solaris-"
			},
			glyph: {
				preset: "awesome5"
			},
			checkbox: true,
			selectMode: 2,
			click: function (event, data) {
				if (! data.node.folder && data.targetType !== 'checkbox') {
					data.node.toggleSelected();
				}
			},
			select: function(ev, data) {
				if (data.node.hasChildren()) {
					var status = data.node.selected;
					data.node.visit(function(node) {
						node.setSelected(status);
					});
				}
			},
			icon: false,
			clickFolderMode: 2,
			autoCollapse: false,
			source: {
				url: '/lpar2rrd-cgi/genjson.sh?jsontype=solaris_histrep_ldom'
			}
		});
	}
	if ($("#histreptree-hyperv-server").length) {
		$("#histreptree-hyperv-server").fancytree({
			extensions: ["persist", "glyph"],
			persist: {
				cookiePrefix: "histreptree-hyperv-server"
			},
			glyph: {
				preset: "awesome5"
			},
			checkbox: true,
			selectMode: 2,
			click: function (event, data) {
				if (! data.node.folder && data.targetType !== 'checkbox') {
					data.node.toggleSelected();
				}
			},
			select: function(ev, data) {
				if (data.node.hasChildren()) {
					var status = data.node.selected;
					data.node.visit(function(node) {
						node.setSelected(status);
					});
				}
			},
			icon: false,
			clickFolderMode: 2,
			autoCollapse: false,
			source: {
				url: '/lpar2rrd-cgi/genjson.sh?jsontype=hyperv_histrep_server'
			}
		});
	}
	if ($("#histreptree-hyperv-vm").length) {
		$("#histreptree-hyperv-vm").fancytree({
			extensions: ["persist", "glyph"],
			persist: {
				cookiePrefix: "histreptree-hyperv-vm"
			},
			glyph: {
				preset: "awesome5"
			},
			checkbox: true,
			selectMode: 2,
			click: function (event, data) {
				if (! data.node.folder && data.targetType !== 'checkbox') {
					data.node.toggleSelected();
				}
			},
			select: function(ev, data) {
				if (data.node.hasChildren()) {
					var status = data.node.selected;
					data.node.visit(function(node) {
						node.setSelected(status);
					});
				}
			},
			icon: false,
			clickFolderMode: 2,
			autoCollapse: false,
			source: {
				url: '/lpar2rrd-cgi/genjson.sh?jsontype=hyperv_histrep_vms'
			}
		});
	}
	if ($("#histreptree-oraclevm-server").length) {
		$("#histreptree-oraclevm-server").fancytree({
			extensions: ["persist", "glyph"],
			persist: {
				cookiePrefix: "histreptree-oraclevm-server"
			},
			glyph: {
				preset: "awesome5"
			},
			checkbox: true,
			selectMode: 2,
			click: function (event, data) {
				if (! data.node.folder && data.targetType !== 'checkbox') {
					data.node.toggleSelected();
				}
			},
			select: function(ev, data) {
				if (data.node.hasChildren()) {
					var status = data.node.selected;
					data.node.visit(function(node) {
						node.setSelected(status);
					});
				}
			},
			icon: false,
			clickFolderMode: 2,
			autoCollapse: false,
			source: {
				url: '/lpar2rrd-cgi/genjson.sh?jsontype=oraclevm_histrep_server'
			}
		});
	}
	if ($("#histreptree-oraclevm-vm").length) {
		$("#histreptree-oraclevm-vm").fancytree({
			extensions: ["persist", "glyph"],
			persist: {
				cookiePrefix: "histreptree-oraclevm-vm"
			},
			glyph: {
				preset: "awesome5"
			},
			checkbox: true,
			selectMode: 2,
			click: function (event, data) {
				if (! data.node.folder && data.targetType !== 'checkbox') {
					data.node.toggleSelected();
				}
			},
			select: function(ev, data) {
				if (data.node.hasChildren()) {
					var status = data.node.selected;
					data.node.visit(function(node) {
						node.setSelected(status);
					});
				}
			},
			icon: false,
			clickFolderMode: 2,
			autoCollapse: false,
			source: {
				url: '/lpar2rrd-cgi/genjson.sh?jsontype=oraclevm_histrep_vms'
			}
		});
	}
	$("#pooltree").fancytree({
		extensions: ["persist", "glyph"],
		persist: {
			cookiePrefix: "pooltree-"
		},
		glyph: {
			preset: "awesome5"
		},
		clickFolderMode: 2,
		icon: false,
		autoCollapse: false,
		source: {
			url: '/lpar2rrd-cgi/genjson.sh?jsontype=estpools'
		},
		disabled: true,
		init: function() {
			var thistree = $(this).fancytree("getTree");
			var toremove = [];
			thistree.visit(function(node) {
				if (node.title == "CPU Total") {
					toremove.push(node.key);
				}
			});
			for (var i = 0; i < toremove.length; i++) {
				var node = thistree.getNodeByKey(toremove[i]);
				node.remove();
			}
		}
	});
	extensions = ["persist"];
	if(!inXormon){
		extensions.push("glyph");
	}
	$("#hpooltree").fancytree({
		extensions: extensions,
		persist: {
			cookiePrefix: "hpooltree-"
		},
		glyph: {
			preset: "awesome5"
		},
		checkbox: true,
		selectMode: 3,
			click: function (event, data) {
				if (! data.node.folder && data.targetType !== 'checkbox') {
					data.node.toggleSelected();
				}
			},
		select: function(ev, data) {
			if (data.node.hasChildren()) {
				var status = data.node.selected;
				data.node.visit(function(node) {
					node.setSelected(status);
				});
			}
		},
		icon: false,
		clickFolderMode: 2,
		autoCollapse: false,
		source: {
			url: '/lpar2rrd-cgi/genjson.sh?jsontype=estpools'
		},
	});
	extensions = ["persist"];
	if(!inXormon){
		extensions.push("glyph");
	}
	$("#customtree").fancytree({
		extensions: extensions,
		persist: {
			cookiePrefix: "customtree-"
		},
		glyph: {
			preset: "awesome5"
		},
		checkbox: true,
		click: function (event, data) {
			if (! data.node.folder && data.targetType !== 'checkbox') {
				data.node.toggleSelected();
			}
		},
		clickFolderMode: 2,
		icon: false,
		autoCollapse: false,
		source: {
			url: '/lpar2rrd-cgi/genjson.sh?jsontype=cust'
		},
		disabled: false
	});
	$("#custompowertree").fancytree({
		extensions: extensions,
		persist: {
			cookiePrefix: "customtree-"
		},
		glyph: {
			preset: "awesome5"
		},
		checkbox: true,
		click: function (event, data) {
			if (! data.node.folder && data.targetType !== 'checkbox') {
				data.node.toggleSelected();
			}
		},
		clickFolderMode: 2,
		icon: false,
		autoCollapse: false,
		source: {
			url: '/lpar2rrd-cgi/genjson.sh?jsontype=custpower'
		},
		disabled: false
	});
	$("#treetable").fancytree({
		extensions: ["table", "persist", "glyph" ],
		persist: {
			cookiePrefix: "treetable-"
		},
		glyph: {
			preset: "awesome5"
		},
		clickFolderMode: 2,
		icon: false,
		autoCollapse: true,
		source: {
			url: '/lpar2rrd-cgi/genjson.sh?jsontype=powersel'
		},
		renderColumns: function(event, data) {
			var node = data.node,
				$tdList = $(node.tr).find(">td");
			// (index #0 is rendered by fancytree by adding the checkbox)
			$tdList.eq(1).text(node.data.hwtype);
			$tdList.eq(2).text(node.data.cpu);
			$tdList.eq(3).text(node.data.ghz);
			$tdList.eq(4).text(node.data.fix);
		}
	});

	$("#pooltree").fancytree("disable");

	// VMware historical reports
	$("#clstrtree").fancytree({
		extensions: extensions,
		persist: {
			cookiePrefix: "clstrtree-"
		},
		glyph: {
			preset: "awesome5"
		},
		checkbox: true,
		clickFolderMode: 2,
		click: function (event, data) {
			if (! data.node.folder && data.targetType !== 'checkbox') {
				data.node.toggleSelected();
			}
		},
		icon: false,
		source: {
			url: '/lpar2rrd-cgi/genjson.sh?jsontype=clusters&vc=' + getCurrentVcenter()
		},
		disabled: true
	});
	$("#respooltree").fancytree({
		extensions: extensions,
		persist: {
			cookiePrefix: "respooltree-"
		},
		glyph: {
			preset: "awesome5"
		},
		checkbox: true,
		selectMode: 3,
		click: function (event, data) {
			if (! data.node.folder && data.targetType !== 'checkbox') {
				data.node.toggleSelected();
			}
		},
		clickFolderMode: 2,
		icon: false,
		source: {
			url: '/lpar2rrd-cgi/genjson.sh?jsontype=respools&vc=' + getCurrentVcenter()
		},
		disabled: true
	});
	extensions.push("filter");
	$("#dstree").fancytree({
		extensions: extensions,
		persist: {
			cookiePrefix: "dstree-"
		},
		filter: {
			mode: "hide",
			autoApply: true
		},
		glyph: {
			preset: "awesome5"
		},
		checkbox: true,
		selectMode: 3,
		click: function (event, data) {
			if (! data.node.folder && data.targetType !== 'checkbox') {
				data.node.toggleSelected();
			}
		},
		clickFolderMode: 2,
		icon: false,
		source: {
			url: '/lpar2rrd-cgi/genjson.sh?jsontype=datastores&vc=' + getCurrentVcenter()
		},
		disabled: true
	});
	$("#vmtree").fancytree({
		extensions: extensions,
		persist: {
			cookiePrefix: "vmtree-"
		},
		filter: {
			mode: "hide",
			autoApply: true
		},
		glyph: {
			preset: "awesome5"
		},
		checkbox: true,
		selectMode: 3,
		clickFolderMode: 2,
		click: function (event, data) {
			if (! data.node.folder && data.targetType !== 'checkbox') {
				data.node.toggleSelected();
			}
		},
		icon: false,
		source: {
			url: '/lpar2rrd-cgi/genjson.sh?jsontype=vms&vc=' + getCurrentVcenter()
		},
		disabled: true
	});
	$("#linuxtree").fancytree({
		extensions: extensions,
		persist: {
			cookiePrefix: "linuxtree-"
		},
		filter: {
			mode: "hide",
			autoApply: true
		},
		glyph: {
			preset: "awesome5"
		},
		clickFolderMode: 2,
		checkbox: true,
		selectMode: 2,
		click: function (event, data) {
			if (! data.node.folder && data.targetType !== 'checkbox') {
				data.node.toggleSelected();
			}
		},
		icon: false,
		autoCollapse: true,
		source: {
			url: '/lpar2rrd-cgi/genjson.sh?jsontype=linux'
		}
	});

	$(".relpos").each(function() {
		var url, hash, lparstr;
		if (sysInfo.useOldDashboard) {
			url = $(this).find('a.detail').attr('href');
			var favstar = $(this).find('.favs');
			var urlObj = itemDetails(url, true);
			if (curNode.data.agent || (urlObj.host && (urlObj.host =="oVirt" || urlObj.host =="XenServer" || urlObj.host =="Nutanix"))) {
				hash = curNode.data.hash;
				urlObj.type_sam = "m";
			} else {
				if (urlObj.host != curNode.data.hmc) {  // for VMware cluster level
					urlObj.host = curNode.data.hmc;
				}
				var rootEl = curNode.getParentList();
				if (rootEl.length) {
					rootEl = curNode.getParentList()[0].title;
					if (rootEl == "VMware" && urlObj.host != curNode.data.hmc) {  // for VMware cluster level
						if (urlObj.host == "no_hmc") {
							urlObj.server = curNode.data.srv;
							urlObj.lpar = curNode.data.altname;
						}
						urlObj.host = curNode.data.hmc;
					}
				}
				lparstr = urlObj.lpar;
				if (urlObj.item == "lparagg") {
					lparstr = "pool";
				}
				if (urlObj.server) {
					urlObj.server = urlObj.server.replace(/--unknown$/, "");  // remove --unknown from the end of server name
				}

				hash = urlObj.host + urlObj.server + lparstr;
				if (urlObj.item.match("^dstrag_")) {
					hash = "datastoretop";
				}
				hash = hex_md5(hash).substring(0, 7);
			}
			var dSrc = "a";
			if (urlObj.lpar.indexOf("--NMON--") >= 0) {
				lparstr = lparstr.replace("--NMON--", "");
				dSrc = "n";
			} else if (urlObj.lpar.indexOf("--WPAR--") >= 0) {
				lparstr = lparstr.replace("--WPAR--", "/");
				dSrc = "w";
			}
			hash = hash + urlObj.itemcode + urlObj.time + urlObj.type_sam + dSrc;
			favstar.data("gid", hash);

			if ($.inArray(hash, dbHash) >= 0) {
				favstar.removeClass("favoff far fa-star"); /* Add item */
				favstar.addClass("favon fas fa-star");
				favstar.attr("title", "Remove this graph from Dashboard");
			} else {
				favstar.removeClass("favon fas fa-star");
				favstar.addClass("favoff far fa-star");
				favstar.attr("title", "Add this graph to Dashboard");
			}
		} else {
			var alink = $(this).find('a.detail');
			url = decodeURIComponent(alink.attr("href"));
			url = url.replace(/&none=.*/g, '');
			url = replaceUrlParam(url, "detail", 2);
			hash = hex_md5(url).substring(0, 7);
			var exists = false;

			if (dashBoard) {
				$.each(dashBoard.tabs, function(ti, tab) {
					$.each(tab.groups, function(gi, group) {
						$.each(group.tree, function(ii, item) {
							if (item.hash == hash) {
								exists = true;
								return false;
							}
						});
						if (exists) {
							return false;
						}
					});
				});
			}

			var $favstar = $(this).find('.favs');
			if (! $favstar.length) {
				$(this).find(".g_title").prepend("<div class='favs'></div>");
				$favstar = $(this).find('.favs');
			}

			if (exists) { /* Remove item */
				$favstar.removeClass("favoff far fa-star");
				$favstar.addClass("favon fas fa-star");
				$favstar.attr("title", "Remove this graph from Dashboard");
			} else { /* Add item */
				$favstar.removeClass("favon fas fa-star");
				$favstar.addClass("favoff far fa-star");
				$favstar.attr("title", "Add this graph to Dashboard");
			}
		}
		$("div.favs").off("click").on("click", function(ev) {
			var hash;
			var star = $(this);
			if (sysInfo.useOldDashboard) {
				hash = $(this).data("gid");
				if ($(this).hasClass("favon")) { /* Remove item */
					$(this).removeClass("favon fas fa-star");
					$(this).addClass("favoff far fa-star");
					$(this).attr("title", "Add this graph to Dashboard");
					var toRemove = $.inArray(hash, dbHash);
					if (toRemove >= 0) {
						dbHash.splice(toRemove, 1);
						saveCookies();
					}
				} else {
					$(this).removeClass("favoff far fa-star"); /* Add item */
					$(this).addClass("favon fas fa-star");
					$(this).attr("title", "Remove this graph from Dashboard");
					dbHash.push(hash);
					saveCookies();
				}
			} else {
				var alink = $(this).parent().siblings('a.detail');
				var url = decodeURIComponent(alink.attr("href"));
				url = url.replace(/&none=.*/g, '');
				url = replaceUrlParam(url, "detail", 2);
				hash = hex_md5(url).substring(0, 7);
				if ($(this).hasClass("favon")) { /* Remove item */
					$(this).removeClass("favon fas fa-star");
					$(this).addClass("favoff far fa-star");
					$(this).attr("title", "Add this graph to Dashboard");
					$.each(dashBoard.tabs, function(ti, tab) {
						$.each(tab.groups, function(gi, group) {
						group.tree = $.grep(group.tree, function(e){ return e.hash != hash; });
					});
					});
					var postdata = {cmd: "savedashboard", user: sysInfo.uid, acl: JSON.stringify(dashBoard)};
					$.post( "/lpar2rrd-cgi/users.sh", postdata, function( data ) {});
				} else {
					var cmenu = $("<ul id='dbpopup'></ul>");
					cmenu.append("<li class='ui-widget-header ui-state-disable'><div>Dashboard Tab/Group</div></li>");
					if (dashBoard.tabs && dashBoard.tabs.length) {
						$.each(dashBoard.tabs, function(ti, tab) {
							if (tab.groups.length) {
								var submenu = $("<ul></ul>");
								$.each(tab.groups, function(gi, group) {
									submenu.append("<li data-tabname='" + tab.name + "'><div>" + group.name + "</div></li>");
								});
								var listItem = $("<li><div>" + tab.name + "</div></li>");
								listItem.append(submenu);
								cmenu.append(listItem);
							}
						});
					}
					cmenu.append("<li>---</li><li class='createdbgrp'><div>Create new group</div></li>");
					// cmenu.css("display", "none");

					$("body").append(cmenu);
					var el = $(this).parents(".relpos");
					var blurTimer;
					var blurTimeAbandoned = 300;
					$("#dbpopup").menu({
						items: "> :not(.ui-widget-header)",
						focus: function( event, ui ) {
							clearTimeout(blurTimer);
						},
						blur: function( event, ui ) {
							if ( event.originalEvent.type != "click") {
								blurTimer = setTimeout(function() {
								$("#dbpopup").off().remove();
								}, blurTimeAbandoned);
							}
						},
						select: function( event, ui ) {
							var groupSelected = function(tname, gname) {
								var tab = $.grep(dashBoard.tabs, function( ttab ) {
									return ttab.name == tname;
								});
								if (tab.length < 1) {
									return false;
								}
								var group = $.grep(tab[0].groups, function( grp ) {
									return grp.name == gname;
								});
								if (group.length < 1) {
									return false;
								}
								var dbItem = $.getQueryParameters(url);
								var topTitle = curNode.data.srv ? curNode.data.srv : curNode.data.noalias;
								if (/^custom.*/.test(dbItem.item) || dbItem.host == "no_hmc") {
									topTitle = dbItem.lpar;
								}
								if (dbItem.host == "nope") {
									topTitle = "";
								}
								if (/^clust.*/.test(dbItem.item)) {
									topTitle = curNode.data.parent;
									if (/^cluster_.*/.test(topTitle)) {
										topTitle = topTitle.replace(/^cluster_/, "");
									}
								}
								var item = {title: topTitle, url: url, hash: hash, width: 170, height: 110, menukey: curNode.data.hash, tab: curTab};
								group[0].tree.push(item);
								// dashBoard.hashes.push(hash);
								star.removeClass("favoff far fa-star"); /* Add item */
								star.addClass("favon fas fa-star");
								star.attr("title", "Remove this graph from Dashboard");
								var postdata = {cmd: "savedashboard", user: sysInfo.uid, acl: JSON.stringify(dashBoard)};
								$.post( "/lpar2rrd-cgi/users.sh", postdata, function( data ) {});
								$("#dbpopup").off().remove();
							};
							if (ui.item.hasClass("createdbgrp")) {
								$("<div id='favselect'></div>").dialog({
									// Remove the closing 'X' from the dialog
									open: function(event, ui) {
										$("#dbpopup").off().remove();
										$(".ui-dialog-titlebar-close").hide();
										$('.ui-widget-overlay').addClass('custom-overlay');
										var tabfields = $("<fieldset><legend>Dashboard Tab</legend></fieldset>");
										if (dashBoard.tabs && dashBoard.tabs.length) {
											var selected = " selected";
											var options = "";
											$.each(dashBoard.tabs, function(ti, tab) {
												options += "<option" + selected + ">" + tab.name + "</option>";
												selected = "";
										});
											tabfields.append("<label for='dbtabselect'>Pick existing</label><select id='dbtabselect'>" + options + "</select><span> or </span><br>");
										}
										tabfields.append("<label for='newtabname'>Create new</label><input id='newtabname' />");
										$(this).append(tabfields);
										$(this).append("<br><label for='dbgrpedit'>Group name</label><input id='dbgrpedit' autofocus /><br><br>");
										$("#dbtabselect").selectmenu();
										$('#dbgrpedit').focus().on("change keyup", function(ev) {
											if (ev.target.value) {
												$('.ok-button').button("enable");
												} else {
												$('.ok-button').button("disable");
											}
										});
										$('.ok-button').button("disable");
									},
									buttons: {
										"OK": {
											text: "OK",
											class: 'ok-button',
											click: function() {
												groupname = $("#dbgrpedit").val();
												if (groupname.length) {
													var tabname;
													if ( $('#newtabname').val() ) {
														tabname = $('#newtabname').val();
													} else if (dashBoard.tabs && dashBoard.tabs.length == 1) {
														tabname = dashBoard.tabs[0].name;
													} else {
														tabname = $("#dbtabselect").val();
													}
													if (tabname != "") {
														var etab = $.grep(dashBoard.tabs, function( tab ) {
															return tab.name == tabname;
														});
														if (etab.length) {
															etab = etab[0];
														} else {
															var idx = dashBoard.tabs.push({name: tabname, groups: []});
															etab = dashBoard.tabs[idx - 1];
														}
														if (!etab.groups) {
															etab.groups = [];
														}
														var egroup = $.grep(etab.groups, function( grp ) {
															return grp.name == groupname;
														});
														if (egroup.length < 1) {
															etab.groups.push({name: groupname, tree: []});
														}
													}
													groupSelected(tabname, groupname);
												}
												$(this).dialog("close");
											}
										},
										"Cancel": function() {
											$(this).dialog("close");
											return false;
										}
									},
									close: function(event, ui) {
										$(this).remove();
									},
									resizable: false,
									// position: { my: 'left', at: 'right', of: $(this) },
									minWidth: 380,
									title: "Create new Dashboard group",
									modal: true
								});
							} else {
								var tabname = ui.item.data("tabname");
								var groupname = ui.item.text();
								groupSelected(tabname, groupname);
							}
						}
					}).position({ my: 'left top', at: 'left top', of: star }).focus();

				}
			}
		});
	});

	$("div.refresh").each(function() {
		$(this).attr("title", "HMC data refresh");
	});
	$(".g_title").each(function() {
		var grtitle = this.data;
		$(this).html();
	});

	$("div.refresh").on("click", function() {
		var pURL = $(this).children("a").attr("href") + "&nonerf=" + Math.floor(new Date().getTime() / 1000);
		$('#content').load(pURL, function() {
			imgPaths();
			myreadyFunc();
		});
	});
	$("div.popdetail").each(function() {
		$(this).attr("title", "ZOOM reset").addClass("fas fa-ban");
	});

	$("div.popdetail").on("click", function() {
		resetZoom(this);
	});

	$('.preddiv').each(function(idx, pdiv) {
		$(pdiv).lazy({
			bind: 'event',
			visibleOnly: true,
			appendScroll: $("div#econtent"),
			predictionLoader: function(element) {
				showPrediction(pdiv);
			}
		});
	});


	if (!areCookiesEnabled()) {
		$("#nocookies").show();
	} else {
		$("#nocookies").hide();
		if (dbHash.length === 0) {
			$("#emptydash").show();
		} else {
			$("#emptydash").hide();
		}
	}

	if ($("#emptydash").length) {
		$( "#tabs > ul li" ).hide();
		genDashboard();
	} else {
		// $("#title").text("");
		$("#conttitle").show();
	}

	$("#dashfooter button").button();

	if ($.cookie('flatDB')) {
		$( "#dbstyle" ).button({ label: "Switch to Tabbed Style" });
	}

	$("#clrcookies").on("click", function() {
		var conf = confirm("Are you sure you want to remove all DashBoard items?");
		if (conf === true) {
			dbHash.length = 0;
			saveCookies();
			$("#side-menu").fancytree("getTree").reactivate();
		}
	});
	$("#wipecookies").button().on("click", function() {
		var conf = confirm("Are you sure you want to wipe all LPAR2RRD cookies for this host.domain/path?");
		if (conf === true) {
			for (var it in $.cookie()) {
				$.removeCookie(it);
			}
		}
	});

	$("#filldash").on("click", function() {
		var conf = confirm("This will append predefined items: Custom groups, Totals for all servers and LPARs aggregates. Are you sure?");
		if (conf === true) {
			$.getJSON("/lpar2rrd-cgi/genjson.sh?jsontype=pre", function(data) {
				$.each(data, function(key, val) {
					if ($.inArray(val, dbHash) < 0) {
						dbHash.push(val);
					}
				});
				saveCookies();
				$("#side-menu").fancytree("getTree").reactivate();
			});
		}
	});
	$("#filldashlink").on("click", function(event) {
		event.preventDefault();
		$("#filldash").trigger("click");
	});

	var bar = $('.bar');
	var percent = $('.percent');
	var status = $('#status');
	$(status).hide();

	$('#upload').ajaxForm({
		beforeSend: function() {
			status.empty();
			var percentVal = '0%';
			bar.width(percentVal);
			percent.html(percentVal);
			document.body.style.cursor = 'wait';
			status.html("<b>Please wait, your file is being processed...</b>");
			status.show();
		},
		uploadProgress: function(event, position, total, percentComplete) {
			var percentVal = percentComplete + '%';
			bar.width(percentVal);
			percent.html(percentVal);
		},
		success: function(data, textStatus, jqXHR) {
			var percentVal = '100%';
			bar.width(percentVal);
			percent.html(percentVal);
			$(status).show(200);
			document.body.style.cursor = 'auto';
		},
		complete: function(xhr) {
			status.html(xhr.responseText);
			$("#nmon-link").on("click", function (event) {
				event.preventDefault();
				var qstr = this.href.slice(this.href.indexOf('&start-hour') + 1);
				var hashes = qstr.split('&');
				// var txt = hashes[13].split("=")[1];
				var txt = decodeURIComponent(hashes[14].split("=")[1]);

				txt = txt.replace("--unknown","");
				txt = txt.replace("--NMON--","");
				$("#content").load("/lpar2rrd-cgi/lpar2rrd-external-cgi.sh?" + qstr, function(){
					imgPaths();
					$('#title').text(txt);
					$('#title').show();
					myreadyFunc();
					loadImages('#content img.lazy');
					if (timeoutHandle) {
						clearTimeout(timeoutHandle);
					}
				});
			});
		}
	});

	$( "#dbstyle" ).on("click", function() {
		if ($.cookie('flatDB')) {
			$.removeCookie('flatDB');
		} else {
			$.cookie('flatDB', true, {
				expires: 365
			});
		}
		$("#side-menu").fancytree("getTree").reactivate();
	});

	$("ul.ui-tabs-nav").on("mouseenter mouseleave", function() {
		if (!$("#emptydash").length) {
			$("#tabgroups").fadeIn(200);
		}
	}, function() {
		$("#tabgroups").fadeOut(100);
	});

	$('form[action="/lpar2rrd-cgi/virtual-wrapper.sh"]').on("submit", function(event) {
		event.preventDefault();
		if (timeoutHandle) {
			clearTimeout(timeoutHandle);
		}
		$('#content').empty();

		$('#content').append("<div style='width: 100%; height: 100%; text-align: center'><img src='css/images/sloading.gif' style='margin-top: 200px'></div>");
		// $('#title').text("Accounting results");
		var postData = $(this).serialize();
		if (sysInfo.guidebug == 1) {
			copyToClipboard(postData);
		}
		$('#content').load(this.action, postData, function() {
			imgPaths();
			myreadyFunc();
		});
	});

	if ( $(" #extnmon ").length ) {
		var extNmonPrereq = "";

		$.ajax({
			url: "/lpar2rrd-cgi/ext-nmon-check.sh",
			dataType: "json",
			async: false,
			success: function (data) {
				extNmonPrereq = data;
			}
		});
		if (extNmonPrereq) {
			if ( extNmonPrereq.agent && extNmonPrereq.agent >= "4.60" && extNmonPrereq.daemon) {
				$(" #extnmon ").show();
			} else {
				var newContent = "<h3>Your installation is not able to run NMON file grapher:</h3><ul>";
				if (!extNmonPrereq.daemon) {
					newContent += "<li>LPAR2RRD daemon must be running</li>";
				}
				if (extNmonPrereq.agent === false) {
					newContent += "<li>LPAR2RRD agent must be installed</li>";
				} else if (extNmonPrereq.agent <= "4.60") {
					newContent += "<li>LPAR2RRD agent v4.60 or higher must be installed locally<br />" +
						sysInfo.ostype + ": <code>rpm -Uvh " + sysInfo.rpm + "</code></li>";
				}
				newContent += "</ul><p>It uses functionality of the OS agent and the OS daemon for data processing. Install the OS agent and run the daemon (all locally) to get it working.<br /><a href='https://lpar2rrd.com/agent.htm'>https://lpar2rrd.com/agent.htm</a></p>";
				$(" #status ").html(newContent);
				$(" #status ").show();
			}
		}
	}

	$( "div.csvexport" ).each(function() {
		var title = $(this).text();
		$(this).attr("title", title);
		$(this).text("");
	});

	$( "a.csvfloat" ).each(function() {
		var title = $(this).text();
		$(this).attr("title", title);
		$(this).text("");
		$(this).append("<img src='css/images/csv.png'>");
	});
	$( "a.pdffloat" ).each(function() {
		var title = $(this).text();
		$(this).attr("title", title);
		$(this).text("");
		$(this).append("<img src='css/images/pdf.png'>");
	});

	$( "input.allcheck" ).on("click", function() {
		var isChecked = this.checked;
		$(this).parents('fieldset').find('div').fancytree("getTree").visit(function(node) {
			if (!node.hasChildren()) {
				if (!$(node.span).hasClass("fancytree-hide")) {
					node.setSelected(isChecked);
				}
			}
		});
	});

	$("#custgrpstree").fancytree({
		extensions: ["persist", "glyph"],
		persist: {
			cookiePrefix: "customtree-"
		},
		glyph: {
			preset: "awesome5"
		},
		icon: false,
		source: {
			url: '/lpar2rrd-cgi/genjson.sh?jsontype=cust'
		},
		disabled: false,
		create: function() {
			$.getJSON( "/lpar2rrd-cgi/custgrps.sh?type=json", function( data ) {
				grpJSON = data;
			});
			$.getJSON( "/lpar2rrd-cgi/genjson.sh?jsontype=fleet", function( data ) {
				fleet = JSON.stringify(data);
			});
		},
		activate: function() {
			selectedGrp = $( "#custgrpstree" ).fancytree("getTree").activeNode.title;
			if (grpJSON[selectedGrp]) {
				$( "#gentable tbody tr" ).remove();
				var type = Object.keys(grpJSON[selectedGrp])[0];
				$( "#itemtype" ).text(type);
				var servers = Object.keys(grpJSON[selectedGrp][type]);
				$.each(servers, function( index, server) {
					var tItems = grpJSON[selectedGrp][type][server];
					$.each(tItems, function( index, item) {
						$( "#gentable" ).append('<tr><td>' + type + '</td><td>' + server + '</td><td>' + item + '</td><td><button class="grptestbtn">Show</button></tr>');
					});
				});
				//groupTable($('#gentable tr:has(td)'),0,2);
				redrawTable($('#gentable tr:has(td)'), 0, 2);
				//$('#gentable .deleted').remove();

				$( "button.grptestbtn" ).on("click", function() {
					var vals = [];
					$(this).parent().siblings().each(function (i, n){
						vals.push(n.textContent);
					});
					alert (vals.join(":"));
				});
			}
		}
	});
	$("#alrttree").fancytree({
		icon: false,
		clickFolderMode: 2,
		autoCollapse: false,
		create: function () {
			if (timeoutHandle) {
				clearTimeout(timeoutHandle);
			}
			$.getJSON( "/lpar2rrd-cgi/genjson.sh?jsontype=alrtgrptree", function( data ) {
				mailGroups = data;
			});
			$.getJSON( "/lpar2rrd-cgi/genjson.sh?jsontype=fleetalrt", function( data ) {
				fleet = data;
			});
		},
		init: function () {
			loaded += 1;
			if (loaded > 1) {
				$(".savealrtcfg").button().prop( "disabled", false);
				$("#testalrtcfg").button().prop( "disabled", false);
			}
			var $alrttree = $( "#alrttree").fancytree("getTree");
			if (sysInfo.free == 1 && $alrttree.getRootNode().countChildren(false) >= 3) {
				$.each($alrttree.getRootNode().getChildren(), function(i, node) {
					if (i > 2) {
						node.visit(function(child) {
							$(child.tr).find(":input").prop("disabled", true);
							$(child.tr).find(".removeme").prop("disabled", false);
						});
					}
				});
			}
			if (sysInfo.free == 1) {
				$("#freeinfo").show();
			}
			filterAlertTree();
		},
		extensions: ["persist", "edit", "table", "gridnav", "glyph", "filter"],
		persist: {
			cookiePrefix: "alerttree-"
		},
		source: {
			url: cgiPath + '/genjson.sh?jsontype=alrttree'
		},
		glyph: {
			preset: "awesome5"
		},
		filter: {
			mode: 'hide'
		},
		renderColumns: function(event, data) {
			var $alrttree = $( "#alrttree").fancytree("getTree"),
			node = data.node,
			$select = $("<select class='alrtcol' name='metric'></select>"),
			$selectSubmetric = $("<select class=' alrtcol alrtSubmetric' name='submetric'></select>"),
			$tdList = $(node.tr).find(">td"),
			selItems = ['CPU'];
			$tdList.eq(0).addClass('d-none');
			$tdList.eq(1).addClass('d-none');
			if( node.getLevel() == 2 ) {
				$tdList.eq(3).html("<b>" + node.data.subsys + "</b>");
			}
			if( node.getLevel() == 3 ) {
				var mSet = node.data && node.data.hwtype;
				if (mSet) {
					selItems = vmMetrics[mSet];
				}

				//generating select boxes "metric" for other supported platforms and "submetric" for OracleDB("submetric" box should show up only for metric TBSU_P)
				if (node.data.hwtype == "Q"){
					$.each(selItems, function(i, val) {
						var arr = node.data.metric.split("__");
						node.data.metric = arr[0];

						$("<option />", {text: metricTitle[val], value: val, selected: (node.data.metric == val)}).appendTo($select);
						if (arr[1] != undefined && i == 0){
							$("<option />", {text: arr[1], value: arr[1], selected: arr[1]}).appendTo($selectSubmetric);
						}
					});
					if(node.data.metric == undefined || node.data.metric.length === 0 ){
						node.data.metric = "TBSU_P";
					}
					if(node.data.metric == "TBSU_P"){
						//WiP should find better placement for getting info
						$.getJSON( "/lpar2rrd-cgi/genjson.sh?jsontype=alrtSubmetrics", function( data ) {
							submetrics = data;

							var currentSubmetrics = submetrics[node.data.instance];
							$.each(currentSubmetrics, function(i, val) {
								$("<option />", {text: val, value: val, selected: (node.data.submetric == val)}).appendTo($selectSubmetric);
							});
						});

						$tdList.eq(4).html($selectSubmetric);
						if ($tdList.eq(4).children("select").val() != node.data.submetric) {
							node.data.submetric = $tdList.eq(4).children("select").val();
						}
					}
				} else {
			        $.each(selItems, function(i, val) {
						$("<option />", {text: metricTitle[val], value: val, selected: (node.data.metric == val)}).appendTo($select);
					});
				}
				// (index #0 is rendered by fancytree by adding the checkbox)
				// (index #2 is rendered by fancytree)

				$tdList.eq(3).html($select);
				// if not selected select first
				if ($tdList.eq(3).children("select").val() != node.data.metric) {
					node.data.metric = $tdList.eq(3).children("select").val();
					// $tdList.eq(3).children("select option:first-child").attr("selected", "selected");
				}

				// Position index is changed from this point onwards(+1) as there is new select box for "submetric" which only shows up for OracleDB TBSU_P metric
				var errmax = node.data.limit != "" ? "" : " ui-state-error";
				$tdList.eq(5).html("<input type='text' size='5' class='alrtcol" +  errmax + "' name='limit' value='" + node.data.limit + "'>");
				$tdList.eq(6).html("<input type='checkbox' size='5' class='chkbox' name='percent' " + (node.data.percent ? "checked" : "") + ">");
				if (node.data.metric != "CPU") {
					$tdList.eq(6).children("input").prop('disabled', true);
				}
				if (node.data.metric == "OSCPU") {
					$tdList.eq(6).children("input").prop('checked', true);
				} else if (node.data.metric != "CPU") {
					$tdList.eq(6).children("input").prop('checked', false);
				}
				$tdList.eq(7).html("<input type='text' size='5' class='alrtcol' name='peak' value='" + node.data.peak + "'>");
				$tdList.eq(8).html("<input type='text' size='5' class='alrtcol' name='repeat' value='" + node.data.repeat + "'>");
				$tdList.eq(9).html("<input type='text' size='5' class='alrtcol' name='exclude' value='" + node.data.exclude + "'>");
				$select = $("<select class='alrtcol' name='mailgrp'></select>"),
				$("<option />", {text: "---" , value: "", selected: true}).appendTo($select);
				$.each(mailGroups, function(i, val) {
					$("<option />", {text: val.title, value: val.title, selected: (node.data.mailgrp == val.title)}).appendTo($select);
				});
				$tdList.eq(10).html($select);
				$tdList.eq(11).html("<button class='removeme' title='Remove rule'>X</button>");

				if (sysInfo.free == 1 && $alrttree.getRootNode().countChildren(false) >= 3) {
					$.each($alrttree.getRootNode().getChildren(), function(i, node) {
						if (i > 2) {
							node.visit(function(child) {
								$(child.tr).find(":input").prop("disabled", true);
								$(child.tr).find(".removeme").prop("disabled", false);
							});
						}
					});
				}
			}
		},
		table: {
			indentation: 20,
			nodeColumnIdx: 2,
			checkboxColumnIdx: 0
		},
		gridnav: {
			autofocusInput: false,
			handleCursorKeys: true
		}
	});

	// Set FT data to currently selected option
	$( "#alrttree" ).on('change', "select.alrtcol", function(event, data) {
		$.ui.fancytree.getNode(event.target).data[event.target.name] = event.target.value;
		if (event.target.name == "metric") {
			if (event.target.value == "CPU") {
				$(event.target).parent().siblings().find(".chkbox").prop('disabled', false);
			} else {
				$(event.target).parent().siblings().find(".chkbox").prop('disabled', true);
			}
			if (event.target.value == "OSCPU") {
				$(event.target).parent().siblings().find(".chkbox").prop('checked', true);
			} else if (event.target.value != "CPU") {
				$(event.target).parent().siblings().find(".chkbox").prop('checked', false);
			}
			if (event.target.value == "TBSU_P") {
				$(event.target).parent().siblings().find(".alrtSubmetric").show();
			} else {
				$(event.target).parent().siblings().find(".alrtSubmetric").hide();
			}
		}
	});

	$( "#alrttree" ).on('change', "select.alrtSubmetric", function(event, data) {
		$.ui.fancytree.getNode(event.target).data[event.target.name] = event.target.value;
	});
	$( "#alrttree" ).on('change', "input.chkbox", function(event, data) {
		$.ui.fancytree.getNode(event.target).data[event.target.name] = $(this).is(":checked");
	});
	$( "#alrttree" ).on('click', "select.alrtcol", function(event, data) {
		event.stopPropagation();
	});
	$( "#alrttree" ).on('blur', "input.alrtcol", function(event, data) {
		var valid = false;

		switch (event.target.name) {
			case "limit":
				var regexp = /^\d+(?:\.\d+)?$/;
				valid = event.target.value.match(/^[0-9]+$/);
				valid = regexp.test(event.target.value);
				if ($(event.target).parent().siblings().find(".chkbox").is(":checked")) {
					if (event.target.value && (event.target.value > 100)) {
						event.target.value = 100;
					}
				}
				// checkRegexp( event.target.value, /[0-9]*/, "This doesn't look like valid e-mail address" );
			break;
			case "peak":
				valid = event.target.value.match(/^[0-9]*$/);
				if (event.target.value && (event.target.value < 10)) {
					event.target.value = 10;
				}
				/*
				*if (event.target.value && (event.target.value > 120)) {
				*    event.target.value = 120;
				*}
				*/
			break;
			case "repeat":
				valid = event.target.value.match(/^[0-9]*$/);
				if (event.target.value && (event.target.value < 10)) {
					event.target.value = 10;
				}
				/*
				*if (event.target.value && (event.target.value > 168)) {
				*    event.target.value = 168;
				*}
				*/
			break;
			case "exclude":
				valid = (event.target.value == "") || event.target.value.match(/^([01]?[0-9]|^2[0-4])\-([01]?[0-9]|2[0-4])$/);
			break;
		}
		if (valid) {
			$.ui.fancytree.getNode(event.target).data[event.target.name] = event.target.value;
			$(event.target).removeClass( "ui-state-error" );
		} else {
			$(event.target).trigger("focus");
			$(event.target).addClass( "ui-state-error" );
		}
	});

	$( "#optform" ).on('blur', "input.alrtoption", function(event, data) {
		var valid = false;
		switch (event.target.name) {
			case "NAGIOS":
				valid = event.target.value.match(/^[01]$/);
				// checkRegexp( event.target.value, /[0-9]*/, "This doesn't look like valid e-mail address" );
			break;
			case "EXTERN_ALERT":
				valid = (event.target.value == "") || event.target.value.match(/^bin\/.+$/);
				// checkRegexp( event.target.value, /[0-9]*/, "This doesn't look like valid e-mail address" );
			break;
			case "EMAIL_GRAPH":
				valid = event.target.value.match(/^[0-9]*$/);
				if (event.target.value && (event.target.value > 256)) {
					event.target.value = 256;
				}
			break;
			case "REPEAT_DEFAULT":
				valid = event.target.value.match(/^[0-9]*$/);
				if (event.target.value && (event.target.value < 5)) {
					event.target.value = 5;
				}
				if (event.target.value && (event.target.value > 168)) {
					event.target.value = 168;
				}
			break;
			case "PEAK_TIME_DEFAULT":
				valid = event.target.value.match(/^[0-9]*$/);
				if (event.target.value && (event.target.value < 15)) {
					event.target.value = 15;
				}
				if (event.target.value && (event.target.value > 120)) {
					event.target.value = 120;
				}
			break;
			case "TRAP":
				valid = (event.target.value == "") || event.target.value.match(hostNameOrIpRegex);
			break;
			case "MAILFROM":
				valid = (event.target.value == "") || event.target.value.match(emailRegex);
			break;
			case "ALERT_HISTORY":
			case "COMM_STRING":
			case "WEB_UI_URL":
				valid = true;
			break;
		}
		if (valid) {
			$(event.target).removeClass( "ui-state-error" );
		} else {
			$(event.target).trigger("focus");
			$(event.target).addClass( "ui-state-error" );
		}
	});

	$( "#alrttree,#alrtgrptree" ).on('click', "button.removeme", function(event, data) {
		$.ui.fancytree.getNode(event.target).remove();
		mailGroups = $("#alrtgrptree").fancytree("getTree").toDict();
	});
	$( "#addnewalrt" ).button().off().on( "click", function() {
			var $alrttree = $( "#alrttree").fancytree("getTree");
			if (sysInfo.free == 1 && $alrttree.getRootNode().countChildren(false) >= 3) {
				$.message("You are using LPAR2RRD Free Edition, only 3 top items are allowed. Consider upgrade to the <a href='https://lpar2rrd.com/support.htm' target='_blank'><b>Enterprise Edition</b></a>.", "Free Edition limitation");
			} else {
				// if (mailGroups) {
				var node = $alrttree.getActiveNode();
				if (! node) {
					node = $alrttree.getRootNode();
				}
				params = {};
				if (node.getLevel() == 1) {
					params.storage = node.title;
				} else if (node.getLevel() == 2) {
					params.storage = node.parent.title;
					params.subsys = node.data.subsys;
					params.volume = node.title;
				} else if (node.getLevel() == 3) {
					params.storage = node.parent.parent.title;
					params.subsys = node.parent.data.subsys;
					params.volume = node.parent.title;
				}

				addNewAlrtForm("Create new alerting rule", params);
			}
		// } else {
		// 	$.alert("You have no E-mail groups defined, please create some first!", "Add new alert rule result", false);
		// 	}
	});

	$("#alrtgrptree").fancytree({
		icon: false,
		clickFolderMode: 1,
		autoCollapse: false,
		extensions: ["persist", "edit", "table", "gridnav", "glyph"],
		source: {
			url: '/lpar2rrd-cgi/genjson.sh?jsontype=alrtgrptree'
		},
		glyph: {
			preset: "awesome5"
		},
		init: function () {
			loaded += 1;
			if (loaded > 1) {
				$(".savealrtcfg").button().prop( "disabled", false);
			}
		},
		renderColumns: function(event, data) {
			var node = data.node,
			$tdList = $(node.tr).find(">td");
			// (index #0 is rendered by fancytree by adding the checkbox)
			$tdList.eq(0).addClass('d-none');
			$tdList.eq(1).addClass('d-none');
			// (index #2 is rendered by fancytree)
			$tdList.eq(2).text(node.data.email);
			$tdList.eq(3).html("<button class='removeme' title='Remove line'>X</button>");
		},
		table: {
			indentation: 20,
			nodeColumnIdx: 2,
			checkboxColumnIdx: 0
		},
		gridnav: {
			autofocusInput: false,
			handleCursorKeys: true
		}
	});
	$( "#addalrtgrp" ).button().off().on( "click", function() {
		var node = $( "#alrtgrptree").fancytree("getTree").getActiveNode();
		if (! node) {
			node = $( "#alrtgrptree").fancytree("getTree").getRootNode();
		}
		params = {};
		if (node.getLevel() == 1) {
			params.storage = node.title;
		} else if (node.getLevel() == 2) {
			params.storage = node.parent.title;
			params.volume = node.title;
		}
		addNewAgrpForm("Create new mail group", params);
	});
	$( "#optform" ).off('load').on("load", function() {
		$.getJSON( "/lpar2rrd-cgi/genjson.sh?jsontype=alrtcfg", function( data ) {
			alrtCfg = data;
		});
	});
	$( ".passfield" ).each(function() {
		var el = $(this);
		el.data("ofpw", el.val());
		el.val("");
		el.attr("placeholder", "Don't fill to keep current");
	});
	$( "#toggle" ).button().off().on( "click", function() {
		$("#alrttree").fancytree("getRootNode").visit(function(node){
			node.toggleExpanded();
		});
	});

	$("#cgtree").fancytree({
		icon: false,
		// autoCollapse: true,
		clickFolderMode: 1,
		titlesTabbable: true,     // Add all node titles to TAB chain
		quicksearch: true,        // Jump to nodes when pressing first character
		source: {url: '/lpar2rrd-cgi/genjson.sh?jsontype=custgrps'},

		// extensions: ["edit", "table", "gridnav"],
		extensions: ["persist", "edit", "table", "gridnav", "glyph"],
		glyph: {
			preset: "awesome5"
		},

		create: function() {
			$.getJSON( "/lpar2rrd-cgi/genjson.sh?jsontype=fleetall", function( data ) {
				fleet = data;
			});
			if (timeoutHandle) {
				clearTimeout(timeoutHandle);
			}
			$("#addcgrp").on("click", function () {
				var child = {
					"title": "",
					"folder": true,
					"expanded": true,
					"children": [{
						"expanded": true,
						"folder": true,
						"title": ".*",
						"children": [{
							"title": ".*"
						}]
					}]
				};
				if ($("#cgtree").fancytree("getRootNode").getFirstChild()) {
					$("#cgtree").fancytree("getRootNode").getFirstChild().editCreateNode("before", child);
				} else {
					$("#cgtree").fancytree("getRootNode").editCreateNode("child", child);
				}
			});

		},

		edit: {
			triggerStart: ["f2", "dblclick", "shift+click", "mac+enter"],
			edit: function(event, data) {
				var acData = [];
				var type;
				switch (data.node.getLevel()) {
				case 1:
					data.input.attr("placeholder", "Type group name");
					break;
				case 2:
					data.input.attr("placeholder", "Type server name");
					break;
				case 3:
					data.input.attr("placeholder", "Type " + data.node.parent.parent.data.cgtype + " name");
					break;
				default:
				}
				if (data.node.getLevel() == 2) {
					acData = [];
					type = data.node.parent.data.cgtype;
					if (type == "XENVM" || type == "OVIRTVM" || type == "NUTANIXVM" || type == "FUSIONCOMPUTEVM" || type == "PROXMOXVM") {
						type = "VM";
					} else if (type == "OPENSHIFTNODE" || type == "KUBERNETESNODE") {
                        type = "NODE";
					} else if (type == "OPENSHIFTPROJECT" || type == "KUBERNETESNAMESPACE") {
                        type = "NAMESPACE";
                    }
					jQuery.each(fleet, function(i, val) {
						if (fleet[i][type] && fleet[i][type].length) {
							acData.push(i);
						}
					});
					acData = jQuery.uniqueSort( acData );
					data.input.autocomplete({
						autoFocus: false,
						source: acData,
						select: function( event, ui ) {
							// data.input.value =
							window.console && console.log(ui);
						},
						focus: function( event, ui ) {
							data.input.val( ui.item.value );
						}
					});
				} else if (data.node.getLevel() == 3) {
					acData = [];
					type = data.node.parent.parent.data.cgtype;
					if (type == "XENVM" || type == "OVIRTVM" || type == "NUTANIXVM" || type == "FUSIONCOMPUTEVM" || type == "PROXMOXVM") {
						type = "VM";
					} else if (type == "OPENSHIFTNODE" || type == "KUBERNETESNODE") {
                        type = "NODE";
                    } else if (type == "KUBERNETESNAMESPACE") {
                        type = "NAMESPACE";
                    } else if (type == "OPENSHIFTPROJECT") {
                        type = "PROJECT";
                    }
					jQuery.each(fleet, function(i, val) {
						var re = new RegExp("^" + data.node.parent.title + "$", "");
						if (re.test(i)) {
							if (fleet[i][type] && fleet[i][type].length) {
								$.merge(acData, fleet[i][type]);
							}
						}
					});

					// var acData = fleet[data.node.parent.title][data.node.parent.parent.data.type];
					acData = jQuery.uniqueSort( acData );
					data.input.autocomplete({
						autoFocus: false,
						source: acData,
						focus: function( event, ui ) {
							data.input.val( ui.item.value );
						}
					});
				}
			},
			beforeClose: function(event, data) {
				if (data.input.autocomplete("instance")) {
					data.input.autocomplete("close");
				}
				if (data.save) {
					var type = data.node.parent.data.cgtype;
					/*
					*if (type == "VIMS") {
					*    var $select = $("<select class='vcentersel' />");
					*    jQuery.each(acData, function(ii, vc) {
					*        $("<option />", {text: vc, value: vc, selected: (node.data.type == vc)}).appendTo($select);
					*    });
					*}
					*/
					try {
						var re = new RegExp(data.input.val(), "");
					} catch(exception) {
						alert(exception);
						return false;
					}
					if (data.isNew) {
						if (data.node.getLevel() == 1) {
							if (sysInfo.hasPower) {
								data.node.data.cgtype = "LPAR";
							} else if (sysInfo.hasVMware) {
								data.node.data.cgtype = "VM";
							} else if (sysInfo.hasXen) {
								data.node.data.cgtype = "XENVM";
							} else if (sysInfo.hasNutanix) {
								data.node.data.cgtype = "NUTANIXVM";
							} else if (sysInfo.hasFusionCompute) {
								data.node.data.cgtype = "FUSIONCOMPUTEVM";
						    } else if (sysInfo.hasProxmox) {
								data.node.data.cgtype = "PROXMOXVM";
						    } else if (sysInfo.hasOpenshift) {
                                data.node.data.cgtype = "OPENSHIFTNODE";
							} else if (sysInfo.hasKubernetes) {
                                data.node.data.cgtype = "KUBERNETESNODE";
							} else if (sysInfo.hasOVirt) {
								data.node.data.cgtype = "OVIRTVM";
							} else if (sysInfo.hasSolaris) {
								data.node.data.cgtype = "SOLARISZONE";
							} else if (sysInfo.hasHyperV) {
								data.node.data.cgtype = "HYPERVM";
							} else if (sysInfo.hasLinux) {
								data.node.data.cgtype = "LINUX";
							} else if (sysInfo.hasOracleVM) {
								data.node.data.cgtype = "ORVM";
							} else if (sysInfo.hasOracleDB) {
								data.node.data.cgtype = "ODB";
							}
						}
					}
				}
			},
			close: function (event, data) {
					// Editor was removed.
					// data.node.render();
					if (data.node && data.node.getLevel() != 3) {
						data.node.folder = true;
					}
					data.node && $(data.node.tr).find("button").trigger("click");
				}
				// triggerStart: ["f2", "shift+click", "mac+enter"],
				// close: function(event, data) {
				//	if( data.save && data.isNew ){
				//	// Quick-enter: add new nodes until we hit [enter] on an empty title
				//	$("#cgtree").trigger("nodeCommand", {cmd: "addSibling"});
				//	}
				// }
		},
		table: {
			indentation: 20,
			nodeColumnIdx: 2,
			checkboxColumnIdx: 0
		},
		gridnav: {
			autofocusInput: false,
			handleCursorKeys: true
		},
		renderColumns: function(event, data) {
			var node = data.node,
				$select = $("<select class='grptypesel'></select>"),
				$tdList = $(node.tr).find(">td");
			// (Index #0 is rendered by fancytree by adding the checkbox)
			// $tdList.eq(1).text(node.getIndexHier()).addClass("alignRight");
			// Index #2 is rendered by fancytree, but we make the title cell
			// span the remaining columns if it is a folder:
			if( node.isTopLevel() ) {
				/*
				$tdList.eq(4)
				.prop("colspan", 3)
				.nextAll().remove();
				*/
				if (node.data.loaded) {
					$tdList.eq(3).text(customGroups[node.data.cgtype]);
					// $select.prop('disabled', true);
					// $(data.node.tr).find("select").prop('disabled', true);
				} else {
					if (sysInfo.hasPower) {
						$("<option />", {text: customGroups.LPAR, value: "LPAR", selected: (node.data.type == 'LPAR')}).appendTo($select);
						$("<option />", {text: customGroups.POOL, value: "POOL", selected: (node.data.type == 'POOL')}).appendTo($select);
					}
					if (sysInfo.hasVMware) {
						$("<option />", {text: customGroups.VM, value: "VM", selected: (node.data.type == 'VM')}).appendTo($select);
						$("<option />", {text: customGroups.ESXI, value: "ESXI", selected: (node.data.type == 'ESXI')}).appendTo($select);
					}
					if (sysInfo.hasXen) {
						$("<option />", {text: customGroups.XENVM, value: "XENVM", selected: (node.data.type == 'XENVM')}).appendTo($select);
					}
					if (sysInfo.hasNutanix) {
						$("<option />", {text: customGroups.NUTANIXVM, value: "NUTANIXVM", selected: (node.data.type == 'NUTANIXVM')}).appendTo($select);
					}
					if (sysInfo.hasProxmox) {
						$("<option />", {text: customGroups.PROXMOXVM, value: "PROXMOXVM", selected: (node.data.type == 'PROXMOXVM')}).appendTo($select);
					}
					if (sysInfo.hasFusionCompute) {
						$("<option />", {text: customGroups.FUSIONCOMPUTEVM, value: "FUSIONCOMPUTEVM", selected: (node.data.type == 'FUSIONCOMPUTEVM')}).appendTo($select);
					}
					if (sysInfo.hasKubernetes) {
                        $("<option />", {text: customGroups.KUBERNETESNODE, value: "KUBERNETESNODE", selected: (node.data.type == 'KUBERNETESNODE')}).appendTo($select);
						$("<option />", {text: customGroups.KUBERNETESNAMESPACE, value: "KUBERNETESNAMESPACE", selected: (node.data.type == 'KUBERNETESNAMESPACE')}).appendTo($select);
                    }
					if (sysInfo.hasOpenshift) {
                        $("<option />", {text: customGroups.OPENSHIFTNODE, value: "OPENSHIFTNODE", selected: (node.data.type == 'OPENSHIFTNODE')}).appendTo($select);
                        $("<option />", {text: customGroups.OPENSHIFTPROJECT, value: "OPENSHIFTPROJECT", selected: (node.data.type == 'OPENSHIFTPROJECT')}).appendTo($select);
					}
					if (sysInfo.hasOVirt) {
						$("<option />", {text: customGroups.OVIRTVM, value: "OVIRTVM", selected: (node.data.type == 'OVIRTVM')}).appendTo($select);
					}
					if (sysInfo.hasSolaris) {
						$("<option />", {text: customGroups.SOLARISZONE, value: "SOLARISZONE", selected: (node.data.type == 'SOLARISZONE')}).appendTo($select);
						$("<option />", {text: customGroups.SOLARISLDOM, value: "SOLARISLDOM", selected: (node.data.type == 'SOLARISLDOM')}).appendTo($select);
					}
					if (sysInfo.hasHyperV) {
						$("<option />", {text: customGroups.HYPERVM, value: "HYPERVM", selected: (node.data.type == 'HYPERVM')}).appendTo($select);
					}
					if (sysInfo.hasLinux) {
						$("<option />", {text: customGroups.LINUX, value: "LINUX", selected: (node.data.type == 'LINUX')}).appendTo($select);
					}
					if (sysInfo.hasOracleVM) {
						$("<option />", {text: customGroups.ORVM, value: "ORVM", selected: (node.data.type == 'ORVM')}).appendTo($select);
					}
					if (sysInfo.hasOracleDB) {
						$("<option />", {text: customGroups.ODB, value: "ODB", selected: (node.data.type == 'ODB')}).appendTo($select);
					}
					$tdList.eq(3).html($select);
					if ($select.find("option").length == 1) {
						$select.find("option").prop('selected', true);
					}
				}
				var collValue = "";
				if (node.data.collection) {
					collValue = node.data.collection;
				}
				$tdList.eq(4).html("<input type='text' placeholder='Enter set of groups name' class='collname' value='" + collValue + "'>");
			}
			$tdList.eq(5).html("<button class='grptestbtn'>S</button>");
		},
		activate: function(event, data) {
			var node = data.node;
			// var tree = $(this).fancytree("getTree");
			$(node.tr).find("button").trigger("click");
		}
	}).on("nodeCommand", function(event, data){
		// Custom event handler that is triggered by keydown-handler and
		// context menu:
		var refNode, moveMode,
		tree = $(this).fancytree("getTree"),
		node = tree.getActiveNode();

		switch( data.cmd ) {
		case "rename":
		node.editStart();
		break;
		case "remove":
		refNode = node.getNextSibling() || node.getPrevSibling() || node.getParent();
		node.remove();
		if( refNode ) {
			refNode.setActive();
		}
		break;
		case "addGroup":
		node.editCreateNode("after", "");
		break;
		case "addServer":
		var child = {"expanded": true,"folder": true,"title":".*","children": [{"title":".*"}]};
		if (node.isTopLevel()) {
			node.editCreateNode("child", child);
		} else {
			node.editCreateNode("after", child);
		}
		break;
		case "addRule":
		if (node.getLevel() == 2) {
			node.editCreateNode("child", "");
		} else {
			node.editCreateNode("after", "");
		}
		break;
		case "addSibling":
		node.editCreateNode("after", "");
		break;
		default:
		alert("Unhandled command: " + data.cmd);
		return;
		}

	// }).on("click dblclick", function(e){
	//   console.log( e, $.ui.fancytree.eventToString(e) );

	}).on("keydown", function(e){
		var cmd = null;

		// console.log(e.type, $.ui.fancytree.eventToString(e));
		switch( $.ui.fancytree.eventToString(e) ) {
		case "del":
		case "meta+backspace": // mac
		cmd = "remove";
		break;
		// case "f2":  // already triggered by ext-edit pluging
		//   cmd = "rename";
		//   break;
		}
		if( cmd ){
		$(this).trigger("nodeCommand", {cmd: cmd});
		// e.preventDefault();
		// e.stopPropagation();
		return false;
		}
	});

		/*
	* Context menu (https://github.com/mar10/jquery-ui-contextmenu)
	*/
	$("#cgtree").contextmenu({
		delegate: "span.fancytree-node",
		menu: [
		{title: "Edit <kbd>[F2]</kbd>", cmd: "rename"},
		{title: "Delete <kbd>[Del]</kbd>", cmd: "remove"},
		{title: "----"},
		/* {title: "New Group <kbd>[Ctrl+G]</kbd>", cmd: "addGroup", disabled: true}, */
		{title: "New Server", cmd: "addServer", disabled: true},
		{title: "New LPAR", cmd: "addRule", disabled: true}
		],
		beforeOpen: function(event, ui) {
			var node = $.ui.fancytree.getNode(ui.target);
			// $("#cgtree").contextmenu("enableEntry", "addGroup", node.isTopLevel());
			$("#cgtree").contextmenu("enableEntry", "addServer", node.getLevel() == 1);
			var cType = node.getParentList(false,true)[0].data.cgtype;
			if (cType  == "POOL") {
				$("#cgtree").contextmenu("setEntry", "addRule", {title: "New POOL"});
			} else if (cType  == "LPAR") {
				$("#cgtree").contextmenu("setEntry", "addRule", {title: "New LPAR"});
			} else if (cType  == "VM" || cType  == "XENVM"  || cType  == "NUTANIXVM" || cType  == "FUSIONCOMPUTEVM" || cType  == "PROXMOXVM" || cType  == "OVIRTVM" || cType  == "HYPERVM") {
				$("#cgtree").contextmenu("setEntry", "addRule", {title: "New VM"});
			} else if (cType  == "OPENSHIFTNODE" || cType  == "KUBERNETESNODE") {
                $("#cgtree").contextmenu("setEntry", "addRule", {title: "New Node"});
		     } else if (cType  == "KUBERNETESNAMESPACE") {
                $("#cgtree").contextmenu("setEntry", "addRule", {title: "New Namespace"});
			} else if (cType  == "OPENSHIFTPROJECT") {
                $("#cgtree").contextmenu("setEntry", "addRule", {title: "New Project"});
			} else if (cType  == "SOLARISZONE") {
				$("#cgtree").contextmenu("setEntry", "addRule", {title: "New Zone"});
			} else if (cType  == "SOLARISLDOM") {
				$("#cgtree").contextmenu("setEntry", "addRule", {title: "New LDOM"});
			} else if (cType  == "LINUX") {
				$("#cgtree").contextmenu("setEntry", "addRule", {title: "New Linux"});
			} else if (cType  == "ESXI") {
				$("#cgtree").contextmenu("setEntry", "addRule", {title: "New ESXi"});
			} else if (cType  == "ODB") {
				$("#cgtree").contextmenu("setEntry", "addServer", {title: ""});
				$("#cgtree").contextmenu("setEntry", "addRule", {title: "New DB"});
			}
			$("#cgtree").contextmenu("enableEntry", "addRule", node.getLevel() != 1);
			node.setActive();
		},
		select: function(event, ui) {
			var that = this;
			// delay the event, so the menu can close and the click event does
			// not interfere with the edit control
			setTimeout(function(){
				$(that).trigger("nodeCommand", {cmd: ui.cmd});
			}, 100);
		}
	});

	$( "#cgtree" ).on('dblclick', "button.grptestbtn", function(event, data) {
		event.stopPropagation();
	});
	function parentLevelName (nvals) {
		if (nvals.type == "POOL" || nvals.type == "LPAR") {
			return "Server";
		} else if (/VM|ESXI|XENVM|NUTANIXVM|FUSIONCOMPUTEVM|PROXMOXVM|KUBERNETESNODE|OVIRTVM|ORVM/.test(nvals.type)) {
			return "Cluster";
		} else {
			return "Parent level";
		}
	}
	$( "#cgtree" ).on('click', "button.grptestbtn", function(event, data) {
		event.stopPropagation();
		var cgnode = $("#cgtree").fancytree("getActiveNode");
		var match = [];
		var gmatch = {};
		var vals = {};
		var count = 0;
		var dupsFound;
		if( cgnode.getLevel() == 3 ) { // lowest level
			vals.lpar = cgnode.title;
			vals.srv = cgnode.parent.title;
			vals.type = cgnode.parent.parent.data.cgtype;
			//if (vals.type == "POOL" && vals.lpar == "all_pools") {
			//	vals.lpar = "CPU pool";
			//}
			if (vals.type == "ODB"){
				vals.srv  = ".*";
				vals.lpar = ".*";
			}
			jQuery.each(fleet, function(i, val) {
				var re = new RegExp("^" + vals.srv + "$", "");
				if (re.test(i)) {
					if (fleet[i][vals.type]) {
						var grepped = jQuery.grep(fleet[i][vals.type], function( a ) {
							var regex = new RegExp("^" + vals.lpar + "$", "");
							return regex.test(a);
						});
						if (grepped.length) {
							var newHTML = [];
							$.each(grepped, function(index, value) {
								newHTML.push('<span class="cgel">' + value + '</span>');
								count += 1;
							});
							if (!gmatch[i]) {
								gmatch[i] = [];
							}
							gmatch[i].push(newHTML.join(" "));
						}
					}
				}
			});
			$("#cgtest").html("<b>" + vals.type + " level rule live preview:</b> <span class='cgel'>" + cgnode.parent.parent.title + "</span><span class='rarrow'>&nbsp;&rArr;&nbsp;</span><span class='cgel'>" + cgnode.parent.title + "</span><span class='rarrow'>&nbsp;&rArr;&nbsp;</span><span class='cgel'>" + cgnode.title + "</span><hr><table>");
			if (count > 0) {
				var parentLevel = parentLevelName(vals);
				$("#cgtest").append("<tr><th> " + parentLevel + "</th><th></th><th>" + vals.type + "</th></tr>");
				jQuery.each(gmatch, function(i,val) {
					$("#cgtest").append("<tr><td><span class='cgel'>" + i + "</span></td><td class='rarrow'>&nbsp;&rArr;&nbsp;</td><td>" + val.join(" ") + "</td></tr>");
				});
			} else {
				$("#cgtest").append("<tr><td>-- empty list --</td></tr>");
			}
			$("#cgtest").append("</table>").show();

		} else if( cgnode.isTopLevel() ) { // Top level
			vals.type = cgnode.data.cgtype;
			cgnode.visit(function(tnode) {
				if( tnode.getLevel() == 3 ) { // lowest level
					vals.lpar = tnode.title;
					vals.srv = tnode.parent.title;
					if (vals.type == "POOL" && vals.lpar == "all_pools") {
						vals.lpar = "CPU pool";
					}else if (vals.type == "ODB"){
						vals.srv  = ".*";
						vals.lpar = ".*";
					}
					jQuery.each(fleet, function(i, val) {
						var re = new RegExp("^" + vals.srv + "$", "");
						if (re.test(i)) {
							if (fleet[i][vals.type]) {
								var grepped = jQuery.grep(fleet[i][vals.type], function( a ) {
									var regex = new RegExp("^" + vals.lpar + "$", "");
									return regex.test(a);
								});
								if (grepped.length) {
									var newHTML = [];
									$.each(grepped, function(index, value) {
										newHTML.push('<span class="cgel">' + value + '</span>');
										count += 1;
										if (!gmatch[i]) {
											gmatch[i] = {};
										}
										if (gmatch[i][value]) {
										gmatch[i][value] += 1;
										} else {
											gmatch[i][value] = 1;
										}
									});
								}
							}
						}
					});
				}
			});
			$("#cgtest").html("<b>" + vals.type + " group live preview:</b> <span class='cgel'>" + cgnode.title + "</span>&nbsp;&nbsp;<span style='display: none' class='cgel dupe' id='dupsfound'></span><hr><table>");
			dupsFound = 0;
			if (count > 0) {
				var parentLevel = parentLevelName(vals);
				$("#cgtest").append("<tr><th>" + parentLevel + "</th><th></th><th>" + vals.type + "</th></tr>");
				jQuery.each(gmatch, function(i,val) {
					var tItems = [];
					jQuery.each(val, function(ii,ival) {
						if (ival == 1) {
							tItems.push('<span class="cgel">' + ii + '</span>');
						} else {
							tItems.push('<span class="cgel dupe" title="occurrences found: ' + ival +'">' + ii + '</span>');
							dupsFound += 1;
						}
					});
					$("#cgtest").append("<tr><td><span class='cgel'>" + i + "</span></td><td class='rarrow'>&nbsp;&rArr;&nbsp;</td><td>" + tItems.join(" ") + "</td></tr>");
				});
			} else {
				$("#cgtest").append("<tr><td>-- empty list --</td></tr>");
			}
			$("#cgtest").append("</table>").show();
			if (dupsFound) {
				$("#dupsfound").text("some duplicates found").show();
			}
			if (sysInfo.free == 1 && count > 4) {
				$("#cgtest").append( "<hr>Due to the limitation of free LPAR2RRD edition only the first 4 lpars/pools per group will be graphed. Unlimited number of lpars/pools in one custom group is one of the benefits of Enterprise Edition which comes with support subscription. <a href='https://lpar2rrd.com/support.htm#benefits'>More info...</a>");
			}

		} else {  // server level
			vals.type = cgnode.parent.data.cgtype;
			cgnode.visit(function(tnode) {
				if( tnode.getLevel() == 3 ) {
					vals.lpar = tnode.title;
					vals.srv = tnode.parent.title;
					if (vals.type == "POOL" && vals.lpar == "all_pools") {
						vals.lpar = "CPU pool";
					}else if (vals.type == "ODB"){
						vals.srv  = ".*";
						vals.lpar = ".*";
					}
					jQuery.each(fleet, function(i, val) {
						var re = new RegExp("^" + vals.srv + "$", "");
						if (re.test(i)) {
							if (fleet[i][vals.type]) {
								var grepped = jQuery.grep(fleet[i][vals.type], function( a ) {
									var regex = new RegExp("^" + vals.lpar + "$", "");
									return regex.test(a);
								});
								if (grepped.length) {
									var newHTML = [];
									$.each(grepped, function(index, value) {
										newHTML.push('<span class="cgel">' + value + '</span>');
										count += 1;
										if (!gmatch[i]) {
											gmatch[i] = {};
										}
										if (gmatch[i][value]) {
										gmatch[i][value] += 1;
										} else {
											gmatch[i][value] = 1;
										}
									});
								}
							}
						}
					});
				}
			});
			var parentLevel = parentLevelName(vals);
			$("#cgtest").html("<b>" + parentLevel + " level rule live preview:</b> <span class='cgel'>" + cgnode.parent.title + "</span><span class='rarrow'>&nbsp;&rArr;&nbsp;</span><span class='cgel'>" + cgnode.title + "</span> <span style='display: none' class='cgel dupe' id='dupsfound'></span><hr><table>");
			if (count > 0) {
				$("#cgtest").append("<tr><th>" + parentLevel + "</th><th></th><th>" + vals.type + "</th></tr>");
				dupsFound = 0;
				jQuery.each(gmatch, function(i,val) {
					var tItems = [];
					jQuery.each(val, function(ii,ival) {
						if (ival == 1) {
							tItems.push('<span class="cgel">' + ii + '</span>');
						} else {
							tItems.push('<span class="cgel dupe" title="occurrences found: ' + ival +'">' + ii + '</span>');
							dupsFound += 1;
						}
					});
					$("#cgtest").append("<tr><td><span class='cgel'>" + i + "</span></td><td class='rarrow'>&nbsp;&rArr;&nbsp;</td><td>" + tItems.join(" ") + "</td></tr>");
				});
			} else {
				$("#cgtest").append("<tr><td>-- empty list --</td></tr>");
			}
			$("#cgtest").append("</table>").show();
			if (dupsFound) {
				$("#dupsfound").text("some duplicates found").show();
			}
		}
	});

	// Set FT data to currently selected option
	$( "#cgtree" ).on('change', "select.grptypesel", function(event, data) {
		$.ui.fancytree.getNode(event.target).data.cgtype = event.target.value;
		if (event.target.value == 'LINUX') {
			$( $.ui.fancytree.getNode(event.target).tr ).next().find("td:nth-child(3) span.fancytree-title").text("Linux");
		}
		if (event.target.value == 'NUTANIXVM') {
			$( $.ui.fancytree.getNode(event.target).tr ).next().find("td:nth-child(3) span.fancytree-title").text("Nutanix");
		}
		if (event.target.value == 'PROXMOXVM') {
			$( $.ui.fancytree.getNode(event.target).tr ).next().find("td:nth-child(3) span.fancytree-title").text("Proxmox");
		}
		if (event.target.value == 'OPENSHIFTNODE'  || event.target.value == 'OPENSHIFTPROJECT') {
            $( $.ui.fancytree.getNode(event.target).tr ).next().find("td:nth-child(3) span.fancytree-title").text("Openshift");
        }
		if (event.target.value == 'KUBERNETESNODE' || event.target.value == 'KUBERNETESNAMESPACE') {
            $( $.ui.fancytree.getNode(event.target).tr ).next().find("td:nth-child(3) span.fancytree-title").text("Kubernetes");
        }
		if (event.target.value == 'FUSIONCOMPUTEVM') {
			$( $.ui.fancytree.getNode(event.target).tr ).next().find("td:nth-child(3) span.fancytree-title").text("FusionCompute");
		}
		if (event.target.value == 'ODB') {
			$( $.ui.fancytree.getNode(event.target).tr ).next().find("td:nth-child(3) span.fancytree-title").text("OracleDB");
		}

		$( $.ui.fancytree.getNode(event.target).tr ).find("button").trigger("click");
	});
	$( "#cgtree" ).on('click', "select.grptypesel", function(event, data) {
		event.stopPropagation();
	});
	$( "#cgtree" ).on('change', "input.collname", function(event, data) {
		$.ui.fancytree.getNode(event.target).data.collection = event.target.value;
	});
	$( "#cgtree" ).on('click', "input.collname", function(event, data) {
		var acData = $('#cgtree td:nth-child(5) input').map(function(){
				return $(this).val();
			}).get();
		acData = jQuery.uniqueSort(acData);
		var field = $(event.target);
		field.autocomplete({
			autoFocus: false,
			source: acData,
			select: function( event, ui ) {
				// data.input.value =
				window.console && console.log(ui);
			},
			focus: function( event, ui ) {
				field.val( ui.item.value );
				$.ui.fancytree.getNode(event.target).data.collection = ui.item.value;
			}
		});
	});

	$("#savegrp").on("click", function(event) {
		event.preventDefault();
		$("#aclfile").text("");
		var delimiter = "\\:";
		var acltxt = "# This file is GUI generated, modifying is not recommended!\n";
		var atxt = [];
		$("#cgtree").fancytree("getTree").visit(function(node) {
			if (node.getLevel() == 3) {
				var line = [];
				var type = node.parent.parent.data.cgtype;
				var col = node.parent.parent.data.collection;
				var rule = unescapeHtml(node.title).replace(/\:/g, delimiter);
				var srv = unescapeHtml(node.parent.title).replace(/\:/g, delimiter);
				var grp = unescapeHtml(node.parent.parent.title).replace(/\:/g, delimiter);
				//if (type == "POOL" && rule == "CPU pool") {
				//	rule = "all_pools";
				//}
				line.push(type, srv, rule, grp);
				if (col) {
					line.push(col.replace(/\:/g, delimiter));
				}

				atxt.push(line.join(":"));
				acltxt += line.join(":") + "\n";
			}
		});

		var postdata = {'acl': acltxt};

		$.post( "/lpar2rrd-cgi/cgrps-save-cgi.sh", postdata, function( data ) {
			var returned = JSON.parse(data);
			if ( returned.status == "success" ) {
				$("#aclfile").text(returned.cfg).show();
			}
			$(returned.msg).dialog({
				dialogClass: "info",
				title: "Custom group configuration save - " + returned.status,
				minWidth: 600,
				modal: true,
				show: {
					effect: "fadeIn",
					duration: 500
				},
				hide: {
					effect: "fadeOut",
					duration: 200
				},
				buttons: {
					OK: function() {
						$(this).dialog("destroy");
					}
				}
			});
		});
	});

	$("#savedash").on("click", function(event) {
		event.preventDefault();
		var ttmp = '<div id="dialog-form">' +
					'<p class="validateTips">File name is required.</p>' +
					'<form>' +
						'<div id="existing" style="display: none"><select name="name" id="dbfilecombo" class="text ui-widget-content ui-corner-all"></select><br></div>' +
						'<!--label for="name">File name</label>&nbsp;&nbsp;-->' +
						'<input type="text" name="name" id="dbfilename" placeholder="Type filename..." class="text ui-widget-content ui-corner-all">' +
						'<!-- Allow form submission with keyboard without duplicating the dialog button -->' +
						'<input type="submit" tabindex="-1" style="position:absolute; top:-1000px">' +
					'</form>' +
					'</div>';
		$.getJSON("/lpar2rrd-cgi/dashboard.sh?list", function(jsonData){
			cb = '';
			$.each(jsonData.sort(), function(i,data){
				var woprefix = data.substring(3);
				cb += '<option value="' + woprefix + '">' + woprefix +'</option>';
			});
			$("#dbfilecombo").html('');
			$("#dbfilecombo").append(cb).show();
			if (jsonData.length) {
				$("#existing").show();
				$("#existing").change(function(e) {
					$("#dbfilename").val(e.target.value);
				});
			}
		});
		$( ttmp ).dialog({
			dialogClass: "info",
			title: "Save DashBoard status",
			minWidth: 600,
			modal: true,
			show: {
				effect: "fadeIn",
				duration: 500
			},
			hide: {
				effect: "fadeOut",
				duration: 200
			},
			create: function( e, ui ) {
				$( this ).find( "form" ).on( "submit", function( event ) {
					event.preventDefault();
					saveDbState();
				});
			},
			buttons: {
				Save: saveDbState,
				Cancel: function() {
					$( this ).dialog( "destroy" );
					return;
				}
			}
		});
	});
	$("#loaddash").on("click", function(event) {
		event.preventDefault();
		var ttmp = '<div id="dialog-form">' +
					'<p class="validateTips">Your current DashBoard items will be lost!</p>' +
					'<form>' +
						'<label for="name">Select saved state name</label>&nbsp;&nbsp;' +
						'<select name="name" id="dbfilename" class="text ui-widget-content ui-corner-all"></select>' +
						'<!-- Allow form submission with keyboard without duplicating the dialog button -->' +
						'<input type="submit" tabindex="-1" style="position:absolute; top:-1000px">' +
					'</form>' +
					'</div>';
		$.getJSON("/lpar2rrd-cgi/dashboard.sh?list", function(jsonData){
			cb = '';
			$.each(jsonData.sort(), function(i,data){
				var woprefix = data.substring(3);
				cb += '<option value="' + woprefix + '">' + woprefix +'</option>';
			});
			$("#dbfilename").html('');
			$("#dbfilename").append(cb);
		});
		$( ttmp ).dialog({
			dialogClass: "info",
			title: "Restore DashBoard status",
			minWidth: 600,
			modal: true,
			show: {
				effect: "fadeIn",
				duration: 500
			},
			hide: {
				effect: "fadeOut",
				duration: 200
			},
			create: function( e, ui ) {
				$( this ).find( "form" ).on( "submit", function( event ) {
					event.preventDefault();
					restoreDbState();
				});
			},
			buttons: {
				Restore: restoreDbState,
				Cancel: function() {
					$( this ).dialog( "destroy" );
					return;
				}
			}
		});
	});
	$(".savealrtcfg").button().prop( "disabled", true ).off().on("click", function(event) {
		event.preventDefault();
		if ($( "input.alrtcol.ui-state-error" ).length) {
			$.alert("Correct all marked fields before saving!", "Configuration check result", false);
			return;
		}
		$("#aclfile").text("");
		var delimiter = "\\:";
		var alertext = "";
		var alrtxt = [];
		var line = [];
		if ($('#servicenowform input.alrtoption').filter(function() { return $(this).val() != ''; }).length > 0) {
			if ($('#servicenowform input.required ').filter(function() { return $(this).val() == ''; }).length > 0) {
				$.alert("All required fields must be filled to get Service Now working!\n(or clear all Service Now form fields to avoid this warning)", "Save alerting configuration", false);
				$( "#tabs" ).tabs( "option", "active", 7 );
				return;
			}
		}
		if ($('#jiraform input.alrtoption').filter(function() { return $(this).val() !== ''; }).length > 0) {
			if ($('#jiraform input.required ').filter(function() { return $(this).val() === ''; }).length > 0) {
				$.alert("All required fields must be filled to get Jira Cloud working!\n(or clear all Jira Cloud form fields to avoid this warning)", "Save alerting configuration", false);
				$( "#tabs" ).tabs( "option", "active", 8 );
				return;
			}
		}
		$( ".passfield" ).each(function() {
			var el = $(this);
			if (! el.val() ) {
				if (el.data("ofpw")) {
					el.val(el.data("ofpw"));
				}
			} else {
				el.val(Base64.encode(uuencode(el.val())));
				el.data("ofpw", el.val());
			}

		});
		$.each($('#optform, #moreoptform, #smtpoptform, #servicenowform, #jiraform, #opsgenieform').serializeArray(), function(i, field) {
			line = [field.name, field.value].join("=");
			alrtxt.push(line);
		});
		alrtxt.push("");
		$("#alrtgrptree").fancytree("getTree").visit(function(node) {
			if (node.getLevel() == 1) {
				var grp = node.title.replace(/\:/g, delimiter),
				emails = [];
				node.visit(function(tnode) {
					emails.push(tnode.title);
				});
				alrtxt.push( ['EMAIL', grp, emails.join(",")].join(":") );
			}
		});
		alrtxt.push("");
		$("#alrttree").fancytree("getTree").visit(function(node) {
			if (node.getLevel() == 2) {
				var subsys = node.data.subsys,
				storage = node.parent.title;
				if (storage == "IBM Power - all servers") {
					storage = "";
				}
				match = [],
				gmatch = {},
				vals = {};
				node.visit(function(tnode) {
					title = tnode.parent.title;
					if (subsys == "POOL" && title == "CPU pool") {
						title = "all_pools";
					}
					if (title == "--- ALL LPARS ---") {
						title = "";
					}
					if (tnode.data.percent && tnode.data.metric == "CPU") {
						tnode.data.limit += "%";
					}
					if (tnode.data.fakeserver) {
						storage = tnode.data.fakeserver;
					}
					if (storage == "OracleDB"){
						var metric = tnode.data.metric;
						if (tnode.data.metric == "TBSU_P"){
							var subm = (tnode.data.submetric != undefined) ? tnode.data.submetric : "total";
							metric = metric + "__" + subm;
						}
						line = [storage.replace(/:/g, "\\:"),subsys, title.replace(/:/g, "\\:"), metric, tnode.data.limit, tnode.data.peak, tnode.data.repeat, tnode.data.exclude, tnode.data.mailgrp, tnode.data.uuid, tnode.data.cluster, tnode.data.user].join(":");
					}else{
						line = [subsys, storage.replace(/:/g, "\\:"), title.replace(/:/g, "\\:"), tnode.data.metric, tnode.data.limit, tnode.data.peak, tnode.data.repeat, tnode.data.        exclude, tnode.data.mailgrp, tnode.data.uuid, tnode.data.cluster, tnode.data.user].join(":");
					}
					alrtxt.push(line);
				});
			}
		});
		alertext = alrtxt.join("\n");
		var postdata = {cmd: "save", acl: alertext};
		$('.passfield').val("");

		$.post( "/lpar2rrd-cgi/alcfg.sh", postdata, function( data ) {
			var returned = JSON.parse(data);
			if ( returned.status == "success" ) {
				// $("#aclfile").text(returned.cfg).show();
				$("#alrttree").fancytree("getTree").reload();
			}
			$(returned.msg).dialog({
				dialogClass: "info",
				title: "Alerting configuration save - " + returned.status,
				minWidth: 600,
				modal: true,
				show: {
					effect: "fadeIn",
					duration: 500
				},
				hide: {
					effect: "fadeOut",
					duration: 200
				},
				buttons: {
					OK: function() {
						$(this).dialog("close");
					}
				}
			});
		});
		//if (! $("#aclfile").length ) {
		////	$(this).after("<br><pre><div id='aclfile' style='text-align: left; margin: auto; background: #fcfcfc; border: 1px solid #c0ccdf; border-radius: 10px; padding: 15px; display: none; overflow: auto'></div></pre>");
		////}
		////$("#aclfile").html(alertext).show();
	});

	$("#testalrtcfg").button().off().on("click", function(event) {
		if (confirm ("Save configuration at first, only saved configuration will be tested!\n\nAlerting configuration will be tested.\nAll alerts will be raised even if no thresholds are reached.\n\nDo you want to continue?")) {
			document.body.style.cursor = 'wait';
			$.get("/lpar2rrd-cgi/alert-test.sh", function(data) {
				if (data) {
					document.body.style.cursor = 'default';
					$("<div></div>").dialog( {
						close: function (event, ui) { $(this).remove(); },
						resizable: false,
						title: "Alerting test results",
						dialogClass: "testresult",
						height: "auto",
						width: "auto",
						position: {
							my: "left top",
							at: "left+100 top+50",
						},
						open: function(event, ui) {
							$(this).css({'max-height': $(document).height()-200, 'max-width': $(document).width()-200, 'overflow': 'auto'});
						},
						modal: true
					}).html("<pre>" + data + "</pre>");
				}
			});
		}
	});

	$("#smtptest").button().off().on("click", function(event) {
		event.preventDefault();
		if (confirm ("Save the settings first, only saved configuration will be tested!\n\nSMTP configuration will be tested.\nDo you want to continue?")) {
			var sendto = "<label>E-mail <input type='text' id='sendto' title='Valid e-mail address expected'></label>";
			$("<div>" + sendto + "</div>").dialog({
				dialogClass: "info",
				title: "E-mail address to send test message to",
				minWidth: 440,
				modal: true,
				show: {
					effect: "fadeIn",
					duration: 500
				},
				hide: {
					effect: "fadeOut",
					duration: 200
				},
				open: function() {
					$('.ui-widget-overlay').addClass('custom-overlay');
					$("#sendto").tooltipster({
						trigger: 'custom',
						position: 'bottom',
					});
					$("#sendto").on("blur", function( event ) {
						if(event.relatedTarget && event.relatedTarget.textContent != "Cancel") {
							if (emailRegex.test( $("#sendto").val())) {
								$(this).tooltipster("close");
								$(event.target).removeClass( "ui-state-error" );
							} else {
								$(this).tooltipster("open");
								$(event.target).trigger("focus");
								$(event.target).addClass( "ui-state-error" );
							}
						}
					});
				},
				buttons: {
					OK: function() {
						if ( $("#sendto").hasClass( "ui-state-error" ) ) {
							return;
						}
						document.body.style.cursor = 'wait';
						var postdata = {cmd: "smtptest", sendto: $("#sendto").val()};
						$.getJSON( cgiPath + "/alcfg.sh", postdata, function( data ) {
							document.body.style.cursor = 'default';
							var title = "Send test message - " + (data.success ? "succeed" : "fail");
							$("<div>" + data.message + "</div>").dialog({
								dialogClass: "info",
								title: title,
								minWidth: 600,
								modal: true,
								show: {
									effect: "fadeIn",
									duration: 500
								},
								hide: {
									effect: "fadeOut",
									duration: 200
								},
								open: function() {
									$('.ui-widget-overlay').addClass('custom-overlay');
								},
								buttons: {
									OK: function() {
										$(this).dialog("close");
									}
								}
							});
						});
						$(this).dialog("destroy");
					},
					Cancel: function() {
						$("#sendto").tooltipster("destroy");
						$(this).dialog("destroy");
					}
				}
			});
		}
	});

	$( "#create-new-cred" ).button().on( "click", function() {
		vmCredForm("Create new credendtials for vCenter");
	});

	$( "button.testvmconn" ).button().on( "click", function() {
		$('body *').css("cursor", "progress");
		// $(this).css("cursor", "progress");
		var srv = $(this).parent().siblings().eq(1).html();
		var usr = $(this).parent().siblings().eq(2).html();
		var params = { cmd: "test", server: srv, username: usr };

		$.post("/lpar2rrd-cgi/vmwcfg.sh", params, function(jsonData) {
			$('body *').css("cursor", "default");
			//$( "button.testvmconn" ).css("cursor", "default");
			$.alert(jsonData.message, "Connection test result", jsonData.success);
		}, 'json');
	});

	$( "button.remvmconn" ).button().on( "click", function() {
		var ali = $(this).parent().siblings().eq(0).html(),
		srv = $(this).parent().siblings().eq(1).html(),
		usr = $(this).parent().siblings().eq(2).html(),
		params = { cmd: "remove", alias: "", server: srv, username: usr };
		var conftxt = "Do you really want to remove selected credential?";
		/*
		*if (ali) {
		*    conftxt = "For now only alias name will be removed, do you want to continue?";
		*}
		*/
		if (confirm(conftxt)) {
			$.post("/lpar2rrd-cgi/vmwcfg.sh", params, function(jsonData) {
				$.alert(jsonData.message, "Credential remove result", jsonData.success);
				if (jsonData.success) {
					$("#side-menu").fancytree("getTree").reactivate();
				}
			}, 'json');
		}
	});

	$( "button.editvmconn" ).button().on( "click", function() {
		var ali = $(this).parent().siblings().eq(0).html(),
		srv = $(this).parent().siblings().eq(1).html(),
		usr = $(this).parent().siblings().eq(2).html(),
		params = { alias: ali, server: srv, username: usr };
		vmCredForm("Edit existing credentials", params);
	});

	$( "#run-data-load" ).button().on( "click", function() {
		params = { cmd: "load" };
		$.post("/lpar2rrd-cgi/vmwcfg.sh", params, function(jsonData) {
			$.alert(jsonData.message, "Data load launched", jsonData.success);
		}, 'json');
	});

	$( '#sdk-install' ).ajaxForm({
		beforeSend: function() {
			status.empty();
			var percentVal = '0%';
			bar.width(percentVal);
			percent.html(percentVal);
			document.body.style.cursor = 'wait';
		},
		uploadProgress: function(event, position, total, percentComplete) {
			var percentVal = percentComplete + '%';
			bar.width(percentVal);
			percent.html(percentVal);
		},
		success: function(data, textStatus, jqXHR) {
			var percentVal = '100%';
			bar.width(percentVal);
			percent.html(percentVal);
			status.html("<b>Please wait, your file is being processed...</b>");
			$(status).show(200);
		},
		complete: function(xhr) {
			document.body.style.cursor = 'auto';
			status.html(xhr.responseJSON.log);
			$.alert(xhr.responseJSON.message, "SDK install result", xhr.responseJSON.success);
			if (xhr.responseJSON.success) {
				if(inXormon){
					xormonVars.reload();
				} else {
					$("#side-menu").fancytree("getTree").reactivate();
				}
			}
		}
	});

	$( '#upgrade-form' ).ajaxForm({
		beforeSend: function() {
			status.empty();
			var percentVal = '0%';
			bar.width(percentVal);
			percent.html(percentVal);
			document.body.style.cursor = 'wait';
		},
		uploadProgress: function(event, position, total, percentComplete) {
			var percentVal = percentComplete + '%';
			bar.width(percentVal);
			percent.html(percentVal);
		},
		success: function(data, textStatus, jqXHR) {
			var percentVal = '100%';
			bar.width(percentVal);
			percent.html(percentVal);
			status.html("<b>Please wait, your file is being processed...</b>");
			$(status).show(200);
		},
		complete: function(xhr) {
			document.body.style.cursor = 'auto';
			status.html(xhr.responseJSON.log);
			$.alert(xhr.responseJSON.message, "Upgrade install result", xhr.responseJSON.success);
			if (xhr.responseJSON.success) {
				$("#side-menu").fancytree("getTree").reload();
				$("#side-menu").fancytree("getTree").reactivate();
			}
		}
	});
	$('#upload-odb').ajaxForm({
		beforeSend: function() {
			status.empty();
			var percentVal = '0%';
			bar.width(percentVal);
			percent.html(percentVal);
			document.body.style.cursor = 'wait';
			status.html("<b>Please wait, your file is being processed...</b>");
			status.show();
		},
		uploadProgress: function(event, position, total, percentComplete) {
			var percentVal = percentComplete + '%';
			bar.width(percentVal);
			percent.html(percentVal);
		},
		success: function(data, textStatus, jqXHR) {
			var percentVal = '100%';
			bar.width(percentVal);
			percent.html(percentVal);
			$(status).show(200);
			document.body.style.cursor = 'auto';
		},
		complete: function(xhr) {
			document.body.style.cursor = 'auto';
			status.html(xhr.responseJSON.log);
			$.alert(xhr.responseJSON.message, "OracleDB status ", xhr.responseJSON.success);
			if (xhr.responseJSON.success) {
				$("#side-menu").fancytree("getTree").reload();
				$("#side-menu").fancytree("getTree").reactivate();
			}
		}
	});
	$('#odb-iconhelp').button().on("click", function() {
		document.body.style.cursor = 'auto';
		//status.html(xhr.responseJSON.log);
		$.alert('Header:\nlpar2rrd alias;Service;Menu Group;subgroup;DB type;username;password;port;hosts(separated by",");pdb services(separated by",")\n\nFile example:\nExample1;XE;Maingroup;subgroup;Standalone;lpar2rrd;password;port;192.168.1.1;\nExample2;XE;Maingroup;subgroup;RAC;lpar2rrd;password;port;192.168.1.1,192.168.1.2;\nExample3;XE;Maingroup;subgroup;Multitenant;lpar2rrd;password;port;192.168.1.1;XEPDB1,XEPDB2;',"Multiple DB help",1);
	});
	var tooltips = $( ".optform [title]" ).tooltip ({
		position: {
			my: "left top",
			at: "right+5 top-5"
		},
		open: function(event, ui) {
			if (typeof(event.originalEvent) === 'undefined') {
				return false;
			}
			var $id = $(ui.tooltip).attr('id');
			// close any lingering tooltips
			$('div.ui-tooltip').not('#' + $id).remove();
			// ajax function to pull in data and add it to the tooltip goes here
		},
		close: function(event, ui) {
			ui.tooltip.hover(function() {
				$(this).stop(true).fadeTo(400, 1);
			},
			function() {
				$(this).fadeOut('400', function() {
					$(this).remove();
				});
			});
		},
		content: function () {
			return $(this).prop('title');
		}
	});


	$("#hrepselcol :radio").on("change", function(e) {
		var radioButtons = $("#hrepselcol input:radio[name='radio']");
		var selectedIndex = radioButtons.index(radioButtons.filter(':checked'));
		$( "div.stree" ).each(function( index ) {
			if (selectedIndex == index) {
				$( this ).children().prop('disabled',false).css('opacity', 1);
				$( this ).find( "input.allcheck" ).prop('disabled',false);
				$( this ).find( ":ui-fancytree" ).fancytree("enable");
			} else {
				$( this ).children().prop('disabled',true).css('opacity', 0.3);
				$( this ).find( "input.allcheck" ).prop('disabled',true);
				$( this ).find( ":ui-fancytree" ).fancytree("disable");
			}
		});
		$.cookie('vHistRepCol', selectedIndex, {
			expires: 0.04
		});

		/* Do stuff with the element that fired the event */
	});

	$( "#hrepselcol" ).buttonset({
		create: function( event, ui ) {
			// $( "div.stree" ).each(function( index ) {
				$( "div.stree" ).children().prop('disabled',true).css('opacity', 0.3);
				$( "input.allcheck" ).prop('disabled',true);
				if ($.cookie('vHistRepCol') != null) {
					var column = $.cookie('vHistRepCol');
					$( "#hrepselcol label" ).eq(column).trigger("click");
				} else {
					$( "#hrepselcol label" ).eq(0).trigger("click");
				}
			// });
		}
	});

	$( "#dstr-top" ).on("submit", function(event) {
		// /stor2rrd-cgi/detail-graph.sh?host=IBM-Storwize&type=VOLUME&name=top&item=avrg&time=w&detail=0&none=1473792347
		var postData = [];
		postData.push ({name: "host", value: ""});
		postData.push ({name: "server", value: ""});
		postData.push ({name: "lpar", value: ""});
		postData.push ({name: "item", value: "dstr-top"});
		postData.push ({name: "entitle", value: ""});
		postData.push ({name: "gui", value: ""});
		postData.push ({name: "referer", value: ""});
		postData.push ({name: "sunix", value: $("#fromTime").datetimepicker("getDate").getTime() / 1000});
		postData.push ({name: "eunix", value: $("#toTime").datetimepicker("getDate").getTime() / 1000});
		// postData.push ({name: "avgmax", value: $(this).children("select").val().toLowerCase()});

		$.cookie('fromTimeField', $("#fromTime").datetimepicker("getDate").valueOf(), {
			expires: 0.04
		});
		$.cookie('toTimeField', $("#toTime").datetimepicker("getDate").valueOf(), {
			expires: 0.04
		});

		event.preventDefault();
		if (timeoutHandle) {
			clearTimeout(timeoutHandle);
		}

		$('#volresults').empty();

		$('#volresults').append("<div style='width: 100%; height: 100%; text-align: center'><img src='css/images/sloading.gif' style='margin-top: 200px'></div>");
		// $('#title').text("Accounting results");
		// var postData = $(this).serialize();
		if (sysInfo.guidebug == 1) {
			copyToClipboard(postData);
		}
		$('#volresults').load(this.action, $.param(postData), function() {
			imgPaths();
			var $t = $(this).find('table.tablesorter');
			if ($t.length) {
				tableSorter($t);
			}
			hrefHandler();
		//  myreadyFunc();
		});

	});

	$window.on("resize", function(e) {
		var newDimensions = {
			width: $window.width(),
			height: $window.height()
		};
		var w = $window.width();
		var show_menu = document.querySelector('.show_menu_btn');
		if (show_menu) {
			if (w > 800) {
				$(show_menu).hide();
				$("#toolbar,#menusw,#footer,#side-menu").show();
				show_menu.innerHTML = show_menu.getAttribute('data-shown-text');
				if ($.cookie('sideBarWidth')) {
					less.modifyVars({ sideBarWidth : $.cookie('sideBarWidth') + 'px' });
				}
			} else {
				$(show_menu).show();
				$("#toolbar,#menusw,#footer,#side-menu").hide();
				show_menu.innerHTML = show_menu.getAttribute('data-hidden-text');
				if ($("#resizer").offset().left > 0) {
					$.cookie('sideBarWidth', $("#resizer").offset().left, {
						expires: 360
					});
				}
				less.modifyVars({ sideBarWidth : 0 + 'px' });
			}
		}
	});
	if ( $("#usertable").length ) {
		$.getJSON('/lpar2rrd-cgi/users.sh?cmd=json', function(data) {
			usercfg = data;
			var isAdmin = false;
			if (usercfg.users[sysInfo.uid]) {
				isAdmin = $.inArray(aclAdminGroup, usercfg.users[sysInfo.uid].groups) > -1;
			}
			if (!isAdmin) {
				$("#adduser").prop('disabled', true);
			}
			$.each(Object.keys(usercfg.users).sort(), function(x, i) {
				var val = usercfg.users[i];
				var row = "<tr>";
				var adminRow = $.inArray(aclAdminGroup, val.groups) > -1;
				var isInMyGroups = false;
				//uncomment 'each' cycle if you want to show group members to non-admin users
				//$.each(val.groups, function (gx, gr) {
				//	if ($.inArray(gr, usercfg.users[sysInfo.uid].groups) > -1) {
				//		isInMyGroups = true;
				//	};
				//});
				if (isAdmin || sysInfo.uid == i || isInMyGroups) {
					if (isAdmin || sysInfo.uid == i) {
						if (adminRow) {
							row += "<td><b><a href='#' class='userlink'>" + i + "</a></b></td>";
						} else {
							row += "<td><a href='#' class='userlink'>" + i + "</a></td>";
						}
					} else {
						row += "<td>" + i + "</td>";
					}
					row += "<td>" + val.name + "</td>";
					row += "<td><a href='mailto:" + val.email + "'>" + val.email + "</a></td>";
					if ((isAdmin && !adminRow ) || sysInfo.uid == i) {
						row += "<td style='text-align: center;'><a href='#' class='passlink'>change</a></td>";
					} else {
						row += "<td style='text-align: center;'></td>";
					}
					// row += "<td>" + ShowDate(val.created) + "</td>";
					// row += "<td>" + ShowDate(val.changed) + "</td>";
					if (val.groups) {
						row += "<td>" + val.groups.join( ', ') + "</td>";
					} else {
						row += "<td></td>";
					}
					if (i != sysInfo.uid && isAdmin) {
						row += "<td><div class='delete' title='Delete user'></div></td>";
					} else {
						row += "<td></td>";
					}
					row += "</tr>";
					$("#usertable tbody").append(row);
				}
			});
			$("#usertable a.userlink").on("click", function(event) {
				var curUser = $(event.target).text();
				userDetailForm(curUser);
			});

			$("#adduser").button().on("click", function() {
				userDetailForm(false);
			});

			$("#usertable a.passlink").on("click", function(event) {
				var user = $(event.target).parent().parent().find(".userlink").text();
				var notMe = (sysInfo.uid != user);
				changePasswordForm(user, notMe);
			});

			$("#usertable .delete").on("click", function(event) {
				$.confirm(
					"Are you sure you want to remove this user?",
					"User delete confirmation",
					function() { /* Ok action here*/
						var user = $(event.target).parent().parent().find(".userlink").text();
						$(event.target).parent().parent().remove();
						delete usercfg.users[user];
						SaveUsrCfg();
					}
				);
			});
		});
	}
	if ( $("#grptable").length ) {
		$.getJSON('/lpar2rrd-cgi/users.sh?cmd=json', function(data) {
			usercfg = data;
			var isAdmin = sysInfo.isAdmin;
			//if (usercfg.users[sysInfo.uid]) {
			//	isAdmin = $.inArray(aclAdminGroup, usercfg.users[sysInfo.uid].groups) > -1;
			//}
			if (!isAdmin) {
				$("#addgrp").prop('disabled', true);
			}
			$.each(Object.keys(usercfg.groups).sort(), function(x, i) {
				var val = usercfg.groups[i];
				var row = "<tr>";
				if (isAdmin && i != "admins" && i != "ReadOnly") {
					row += "<td><a href='#' class='grplink'>" + i + "</a></td>";
				} else {
					row += "<td>" + i + "</td>";
				}
				row += "<td>" + val.description + "</td>";
				if (isAdmin && i != aclAdminGroup && i != "ReadOnly") {
					row += "<td><div class='delete'></div></td>";
				} else {
					row += "<td></td>";
				}
				row += "</tr>";
				$("#grptable tbody").append(row);
			});
			$("#grptable a.grplink").on("click", function() {
				var curGroup = $(event.target).text();
				newGroupForm(curGroup);
			});

			$("#addgrp").button().on("click", function() {
				newGroupForm(false);
			});

			$("#grptable a.passlink").on("click", function() {
				var user = $(event.target).parent().parent().find(".userlink").text();
				var notMe = (sysInfo.uid != user);
				changePasswordForm(usercfg.users[user], notMe);
			});

			$("#grptable .delete").on("click", function(event) {
				$.confirm(
					"Are you sure you want to remove this group?",
					"Group delete confirmation",
					function() { /* Ok action here*/
						var grp = $(event.target).parent().parent().find(".grplink").text();
						$(event.target).parent().parent().remove();
						delete usercfg.groups[grp];
						SaveUsrCfg();
					}
				);
			});
		});
	}
	// ################################################################################
	// Host configuration begin

	if ( $("#hosttable").length ) {
		if (timeoutHandle) {
			clearTimeout(timeoutHandle);
		}
		curPlatform = platforms[$("#hosttable").data("platform")].longname;
		// if ( curPlatform == "OracleDB" && ! sysInfo.oracleEnabled ) {
		// 	$("#addnewhost").prop('disabled', true);
		// }

		$.getJSON('/lpar2rrd-cgi/hosts.sh?cmd=json', function(data, textStatus, jqXHR) {
			var header = jqXHR.getResponseHeader('X-Hosts-Imported');
			if (header) {
				var title = "HMC configuration has been loaded";
				var message = "Use this application only for HMC management since now. <br><b>HMC_LIST</b> parameter in etc/lpar2rrd.cfg <b>is ignored</b>.";
				$("<div></div>").dialog( {
					buttons: { "OK": function () { $(this).dialog("close"); } },
					close: function (event, ui) { $(this).remove(); },
					resizable: false,
					title: title,
					minWidth: 600,
					modal: true
				}).html(message);
			}
			hostcfg = {};
			// check for the old format, if true, make conversion
			if (data.aliases) {
				hostcfg.platforms = {};
				$.each(data.platforms, function(idx, val) {
					hostcfg.platforms[val.id] = val;
					hostcfg.platforms[val.id].aliases = {};
					delete hostcfg.platforms[val.id].id;
				});
				$.each(data.aliases, function(idx, val) {
					if (hostcfg.platforms[val.platform]) {
						hostcfg.platforms[val.platform].aliases[idx] = val;
						delete hostcfg.platforms[val.platform].aliases[idx].platform;
					}
				});

			} else {
				hostcfg = data;
			}
			/*
			*$.getJSON( cgiPath + "/genjson.sh?jsontype=fleet", function( data ) {
			*    fleet = data;
			*});
			*$.getJSON( cgiPath + "/genjson.sh?jsontype=metrics", function( data ) {
			*    metrics = data;
			*});
			*$.getJSON( cgiPath + "/genjson.sh?jsontype=custgrps", function( data ) {
			*    cgroups = data;
			*});
			*/
			var isAdmin = sysInfo.isAdmin;
			userName = sysInfo.uid;
			if (! userName) {
				userName = "admin";
				isAdmin = true;
			}
			CheckDeviceCfg(hostcfg);
			$("#hosttable tbody").empty();
			if (! hostcfg.platforms[curPlatform]) {
				hostcfg.platforms[curPlatform] = {};
				hostcfg.platforms[curPlatform].aliases = {};
			}
			$.each(Object.keys(hostcfg.platforms[curPlatform].aliases).sort(), function(x, i) {
				var val = hostcfg.platforms[curPlatform].aliases[i];
				var row = "<tr>";
				if (val.disabled) {
					row = "<tr class='disabled'>";
				}
				if (sysInfo.variant.indexOf('p') == -1 && val.unlicensed) {
					row = "<tr class='unlicensed'>";
					if ($.trim($("#cfgcomment").html() == '')) {
						$("#cfgcomment").html("<p style='font-style: italic'><span style='color: red'>Warning:</span> You are using LPAR2RRD Free Edition, a maximum of 4 active HMC devices and one active CMC device is allowed.<br> Consider upgrade to the <a href='https://lpar2rrd.com/support.htm' target='_blank'><b>Enterprise Edition</b></a>.");
					}
				}
				row += "<td><b><a href='#' class='hostlink'>" + i + "</a></b></td>";
				row += "<td style='text-align: center'><a href='#' class='hostlink' title='Edit host' data-device='" + i + "'><span class='ui-icon ui-icon-pencil'></span></a></td>";
				if (curPlatform == "OracleDB") {
					$("#hosttable .hideme").show();
					row += "<td style='text-align: center'><a href='#' class='clonehost' title='Clone host' data-device='" + i + "'><span class='ui-icon ui-icon-copy'></span></a></td>";
					if (! val.host ) {
						val.host = val.hosts[0];
					}
				}
				row += "<td style='text-align: center'><div class='delete' title='Delete host definition'></div></td>";
				// row += "<td>" + val.platform + "</td>";
				row += "<td>" + val.host + "</td>";
				// row += "<td>" + val.ssh_key_id + "</td>";
				if (val.proxy) {
					row += "<td></td>";
				} else {
					row += "<td style='text-align: center'><button class='contest' title='Test connection'></button></td>";
				}
				row += "</tr>";
				$("#hosttable tbody").append(row);
			});
			$("#hosttable a.hostlink").off().on("click", function(event) {
				event.preventDefault();
				var curID = $(event.target).parents("tr").children().first().find("a").text();
				if (curPlatform == "IBM Power Systems") {
					if ($(event.target).parents("tr").hasClass('unlicensed')) {
						$.message("You are using LPAR2RRD Free Edition, a maximum of 4 active HMC devices are allowed. Consider upgrade to the <a href='https://lpar2rrd.com/support.htm' target='_blank'><b>Enterprise Edition</b></a>.", "Free edition limitation");
					} else {
						hostDetailFormPower(curID);
					}
				} else if (curPlatform == "IBM Power CMC") {
					if ($(event.target).parents("tr").hasClass('unlicensed')) {
						$.message("You are using LPAR2RRD Free Edition, only 1 active CMC device is allowed. Consider upgrade to the <a href='https://lpar2rrd.com/support.htm' target='_blank'><b>Enterprise Edition</b></a>.", "Free edition limitation");
					} else {
						hostDetailFormCMC(curID);
					}
				} else if (curPlatform == "VMware") {
					hostDetailFormVmware(curID);
				} else if (curPlatform == "RHV (oVirt)") {
					hostDetailFormOvirt(curID);
				} else if (curPlatform == "OracleVM") {
					hostDetailFormOracleVM(curID);
				} else if (curPlatform == "OracleDB") {
					hostDetailFormOracleDB(curID);
				} else if (curPlatform == "PostgreSQL") {
					hostDetailFormPostgres(curID);
				} else if (curPlatform == "SQLServer") {
					hostDetailFormSQLServer(curID);
				} else if (curPlatform == "DB2") {
					hostDetailFormDb2(curID);
				} else if (curPlatform == "Nutanix") {
					hostDetailFormNutanix(curID);
				} else if (curPlatform == "AWS") {
					hostDetailFormAWS(curID);
				} else if (curPlatform == "GCloud") {
					hostDetailFormGCloud(curID);
				} else if (curPlatform == "Azure") {
					hostDetailFormAzure(curID);
				} else if (curPlatform == "Kubernetes") {
					hostDetailFormKubernetes(curID);
				} else if (curPlatform == "Openshift") {
					hostDetailFormKubernetes(curID);
				} else if (curPlatform == "Cloudstack") {
					hostDetailFormCloudstack(curID);
		        } else if (curPlatform == "Proxmox") {
					hostDetailFormProxmox(curID);
			    } else if (curPlatform == "FusionCompute") {
					hostDetailFormFusionCompute(curID);
				} else {
					hostDetailForm(curID);
				}
				// create new fn
			});
			$("#hosttable .contest").button({
				icon: 'ui-icon-play'
			}).off().on("click", function(event) {
				var alias = $(event.target).parents("tr").find(".hostlink").text(),
				hParams = hostcfg.platforms[curPlatform].aliases[alias];
				testConnection(alias, hParams);
			});
			$("#hosttable a.clonehost").on("click", function(event) {
				var host = $(event.target).parent().parent().parent().find(".hostlink").text();
				var d = new Date();
				var cloned = host + " - cloned " + d.toLocaleTimeString();
				hostcfg.platforms[curPlatform].aliases[cloned] = $.extend(true, {}, hostcfg.platforms[curPlatform].aliases[host]);
				hostcfg.platforms[curPlatform].aliases[cloned].created = d.toISOString();
				hostcfg.platforms[curPlatform].aliases[cloned].updated = d.toISOString();
				hostcfg.platforms[curPlatform].aliases[cloned].uuid = generateUUID();
				hostcfg.platforms[curPlatform].aliases[cloned].password = "";
				if (curPlatform == "OracleDB") {
					hostDetailFormOracleDB(cloned, true);
				} else {
					hostDetailForm(cloned);
				}
			});

			$(".addnewhost").button().off().on("click", function() {
				if (curPlatform == "IBM Power Systems") {
					var activeDevices = $("#hosttable tbody tr").length;
					if (sysInfo.variant.indexOf('p') == -1 && activeDevices >= 4) {
						$.message("You are using LPAR2RRD Free Edition, a maximum of 4 active HMC devices are allowed. Consider upgrade to the <a href='https://lpar2rrd.com/support.htm' target='_blank'><b>Enterprise Edition</b></a>.", "Free edition limitation");
					} else {
						hostDetailFormPower(false);
					}
				} else if (curPlatform == "IBM Power CMC") {
					var activeDevices = $("#hosttable tbody tr").length;
					if (sysInfo.variant.indexOf('p') == -1 && activeDevices >= 1) {
						$.message("You are using LPAR2RRD Free Edition, only one active CMC device is allowed. Consider upgrade to the <a href='https://lpar2rrd.com/support.htm' target='_blank'><b>Enterprise Edition</b></a>.", "Free edition limitation");
					} else {
						hostDetailFormCMC(false);
					}
				} else if (curPlatform == "VMware") {
					hostDetailFormVmware(false);
				} else if (curPlatform == "RHV (oVirt)") {
					hostDetailFormOvirt(false);
				} else if (curPlatform == "OracleVM") {
					hostDetailFormOracleVM(false);
				} else if (curPlatform == "OracleDB") {
					hostDetailFormOracleDB(false);
				} else if (curPlatform == "PostgreSQL") {
					hostDetailFormPostgres(false);
				} else if (curPlatform == "SQLServer") {
					hostDetailFormSQLServer(false);
				} else if (curPlatform == "DB2") {
					hostDetailFormDb2(false);
				} else if (curPlatform == "Nutanix") {
					hostDetailFormNutanix(false);
				} else if (curPlatform == "AWS") {
					hostDetailFormAWS(false);
				} else if (curPlatform == "GCloud") {
					hostDetailFormGCloud(false);
				} else if (curPlatform == "Azure") {
					hostDetailFormAzure(false);
				} else if (curPlatform == "Kubernetes") {
					hostDetailFormKubernetes(false);
				} else if (curPlatform == "Openshift") {
					hostDetailFormKubernetes(false);
				} else if (curPlatform == "Cloudstack") {
					hostDetailFormCloudstack(false);
			    } else if (curPlatform == "Proxmox") {
					hostDetailFormProxmox(false);
			    } else if (curPlatform == "FusionCompute") {
					hostDetailFormFusionCompute(false);
				} else {
					hostDetailForm(false);
				}
			});

			$("#hosttable .delete").off().on("click", function(event) {
				$.confirm(
					"Are you sure you want to delete this host definition?",
					"Host delete confirmation",
					function() { /* Ok action here*/
						var alias = $(event.target).parent().parent().find(".hostlink").text();
						var parameters = hostcfg.platforms[curPlatform].aliases[alias];
						if (curPlatform == "VMware") {
							$.post('/lpar2rrd-cgi/hosts.sh', {
								cmd: "vmwareremovecreds",
								platform: curPlatform,
								alias: alias,
								server: parameters.host,
								username: parameters.username
							}, function(data) {
							});
						}
						$(event.target).parent().parent().remove();
						var uuid = hostcfg.platforms[curPlatform].aliases[alias].uuid;
						delete hostcfg.platforms[curPlatform].aliases[alias];
						var platform = $("#hosttable").data("platform").toUpperCase();
						SaveHostsCfg(false, alias, platform, parameters.host, uuid);                      // create new fn
						$('#adminmenu a[data-abbr="hosts-' + $("#hosttable").data("platform") + '"]').trigger( "click" );
					}
				);
			});
			if (sysInfo.basename && ! $.isEmptyObject(hostcfg.reports)) {
				$("#addrep").button("disable");
			}
		});
		if (sysInfo.free == 1) {
			$("#freeinfo").show();
		}
		if (sysInfo.demo) {
			$("#repexamples").show();
		}
	}
	//  Host configuration end
	/// ##########################################################################################


	// ################################################################################
	// Reporter start

	if ( $("#reptable").length || $("#repgrptable").length) {
		if (timeoutHandle) {
			clearTimeout(timeoutHandle);
		}
		$.getJSON(cgiPath + '/genpdf.sh?cmd=test', function(data) {
			if (data.success) {
				backendSupportsPDF = true;
			} else {
				var info = "<p style='font-style: italic'><span style='color: red'>Warning:</span> You cannot use PDF format for reporting, please install the <a href='https://lpar2rrd.com/pdf-install.htm' target='_blank'>required pre-requisites</a>.";
				info += "&nbsp;&nbsp;&nbsp;<a href='#' id='dbgpdf' title='" + data.log + "'>Debug info...</a>";
				$("#moderr").append(info);
				$("#dbgpdf").on("click", function() {
					var dlg = "<p>Error message follows:</p>";
					$("<div></div>").dialog( {
						buttons: { "OK": function () { $(this).dialog("close"); } },
						close: function (event, ui) { $(this).remove(); },
						resizable: false,
						title: "PDF test failed",
						minWidth: 800,
						modal: true
					}).html(dlg + "<pre>" + data.log + "</pre>");
				});
			}
		});
		$.getJSON(cgiPath + '/reporter.sh?cmd=modtest', function(data) {
			if (data.success) {
				backendSupportsZIP = true;
			} else {
				var info = "<p style='font-style: italic'><span style='color: red'>Warning:</span> You cannot use ZIP reports, your host system cannot find required Perl module: IO::Compress::Zip. Install the <a href='https://lpar2rrd.com/zip-install.htm' target='_blank'>required pre-requisites</a>.";
				info += "&nbsp;&nbsp;&nbsp;<a href='#' id='dbgzip' title='" + data.log + "'>Debug info...</a>";
				$("#moderr").append(info);
				$("#dbgzip").on("click", function() {
					var dlg = "<p>Error message follows:</p>";
					$("<div></div>").dialog( {
						buttons: { "OK": function () { $(this).dialog("close"); } },
						close: function (event, ui) { $(this).remove(); },
						resizable: false,
						title: "ZIP module test failed",
						minWidth: 800,
						modal: true
					}).html(dlg + "<pre>" + data.log + "</pre>");
				});
			}
		});
		$.getJSON(cgiPath + '/reporter.sh?cmd=json', function(data) {
			repcfg = data;
			$.getJSON( cgiPath + "/genjson.sh?jsontype=fleetrpt", function( data ) {
				fleet = data;
			});
			$.getJSON( cgiPath + "/genjson.sh?jsontype=metrics", function( data ) {
				metrics = data;
			});
			$.getJSON( cgiPath + "/genjson.sh?jsontype=custgrps", function( data ) {
				cgroups = data;
			});
			if (! repcfg.users) {
				repcfg.users = {};
				repcfg.users.admin = {};
				repcfg.users.admin.reports = repcfg.reports;
				repcfg.users.admin.groups = repcfg.groups;
				delete repcfg.reports;
				delete repcfg.groups;
			}
			var isAdmin = sysInfo.isAdmin;
			userName = sysInfo.uid;
			if (! userName) {
				userName = "admin";
				isAdmin = true;
			}
			if (! repcfg.users[userName]) {
				repcfg.users[userName] = {};
				repcfg.users[userName].reports = {};
				repcfg.users[userName].groups = {};
			}

			repcfgusr = repcfg.users[userName];
			$("#reptable tbody").empty();
			$.each(Object.keys(repcfgusr.reports).sort(), function(x, i) {
				var val = repcfgusr.reports[i];
				var row = "<tr>";
				if (val.disabled) {
					row = "<tr class='disabled'>";
				}
				row += "<td><b><a href='#' class='replink'>" + i + "</a></b></td>";
				row += "<td style='text-align: center'><a href='#' class='replink' title='Edit report definition' data-repname='" + i + "'><span class='ui-icon ui-icon-pencil'></span></a></td>";
				if (sysInfo.free == 1) {
					row += "<td style='text-align: center'><a title='Clone report not available in the Free Edition' class='clonerep'><span class='ui-icon ui-icon-copy'></span></a></td>";
				} else {
					row += "<td style='text-align: center'><a href='#' class='clonerep' title='Clone this report' data-repname='" + i + "'><span class='ui-icon ui-icon-copy'></span></a></td>";
				}
				row += "<td style='text-align: center'><a href='#' class='testrep' title='Test report' data-repname='" + i + "'><span class='ui-icon ui-icon-play'></span></a></td>";
				row += "<td style='text-align: center'><div class='delete' title='Delete report'></div></td>";
				row += "<td>" + val.format + "</td>";
				row += "<td>" + (val.mode && val.mode == "timerange" ? "N/A" : rrToText(val.rrule)) + "</td>";
				row += "<td>" + (sysInfo.basename ? "N/A" : val.disabled ? "disabled" : ShowDate(nextRuleRun(val.rrule), true)) + "</td>";
				row += "<td>" + val.recipients.join( ', ') + "</td>";
				row += "</tr>";
				$("#reptable tbody").append(row);
			});
			$("#reptable a.replink").on("click", function(event) {
				event.preventDefault();
				var curID = $(event.target).parents("tr").children().first().find("a").text();
				repDetailForm(curID);                      // create new fn
			});
			$("#reptable .testrep").on("click", function(event) {
				event.preventDefault();
				var repName = $(event.target).parents("tr").find(".replink").text();
				if (repcfgusr.reports[repName].items && repcfgusr.reports[repName].items.length) {
					document.body.style.cursor = 'wait';
					generateReport(repName, userName);
				} else {
					$.alert("Nothing to report, please select some content for this report!", "Empty report detected", false);
				}
			});

			$("#addrep").button().off().on("click", function() {
				repDetailForm(false);                      // create new fn
			});

			$("#reptable .delete").on("click", function(event) {
				event.preventDefault();
				$.confirm(
					"Are you sure you want to delete this report?",
					"Report delete confirmation",
					function() { /* Ok action here*/
						var rep = $(event.target).parent().parent().find(".replink").text();
						$(event.target).parent().parent().remove();
						delete repcfgusr.reports[rep];
						SaveRepCfg();                      // create new fn
						if (sysInfo.basename && $.isEmptyObject(repcfgusr.reports)) {
							$("#addrep").button("enable");
						}
					}
				);
			});

			$("#reptable a.clonerep").on("click", function(event) {
				event.preventDefault();
				if (sysInfo.free == 1) {
					return;
				}
				var rep = $(event.target).parent().parent().parent().find(".replink").text();
				var d = new Date();
				var cloned = rep + " - cloned " + d.toLocaleTimeString();
				repcfgusr.reports[cloned] = repcfgusr.reports[rep];
				SaveRepCfg();
				$( "#side-menu" ).fancytree( "getTree" ).reactivate();
			});

			if (sysInfo.basename && ! $.isEmptyObject(repcfgusr.reports)) {
				$("#addrep").button("disable");
			}
			$("#repgrptable tbody").empty();
			$.each(Object.keys(repcfgusr.groups).sort(), function(i, j) {
				var val = repcfgusr.groups[j];
				var row = "<tr>";
				row += "<td><a href='#' class='grplink'>" + j + "</a></td>";
				row += "<td style='text-align: center'><a href='#' class='grplink' title='Edit group'><span class='ui-icon ui-icon-pencil'></span></a></td>";
				row += "<td style='text-align: center'><div class='delete' title='Delete group'></div></td>";
				row += "<td>" + val.description + "</td>";
				if (!val.emails) {
					val.emails = [];
				}
				row += "<td>" + val.emails.join( ', ') + "</td>";
				row += "</tr>";
				$("#repgrptable tbody").append(row);
			});
			$("#repgrptable a.grplink").on("click", function(event) {
				event.preventDefault();
				var curGrp = $(event.target).parents("tr").children().first().find("a").text();
				newRepGroupForm(curGrp);
			});

			$("#addgrp").button().off().on("click", function() {
				newRepGroupForm(false);
			});
			$("#repgrptable .delete").on("click", function(event) {
				$.confirm(
					"Are you sure you want to remove this group?",
					"Group delete confirmation",
					function() { /* Ok action here*/
						var grp = $(event.target).parent().parent().find(".grplink").text();
						$(event.target).parent().parent().remove();
						delete repcfgusr.groups[grp];
						SaveRepCfg();
					}
				);
			});
		});
		$(".saverepcfg").button().on("click", function(event) {
			if ($("#csv_delim").val()) {
				repcfgusr.csvDelimiter = $("#csv_delim").val();
			} else {
				delete repcfgusr.csvDelimiter;
			}
			SaveRepCfg(true);
		});
		if (sysInfo.free == 1) {
			$("#freeinfo").show();
		}
		if (sysInfo.demo) {
			$("#repexamples").show();
		}
	}

	//  Reporter end
	/// ##########################################################################################
	$("a.server_quick").html('<span class="ui-icon ui-icon-info"></span>');
	$("a.server_overview").html('<span class="ui-icon ui-icon-comment"></span>');
	$("a.server_detail").html('<span class="ui-icon ui-icon-search"></span>');
	$("a.server_interface").html('<span class="ui-icon ui-icon-transfer-e-w"></span>');

	$('#fullscreendb').on('click', function(ev) {
		if (!window.screenTop && !window.screenY) {
			if (document.exitFullscreen) {
				document.exitFullscreen();
			} else if (document.mozCancelFullScreen) { /* Firefox */
				document.mozCancelFullScreen();
			} else if (document.webkitExitFullscreen) { /* Chrome, Safari and Opera */
				document.webkitExitFullscreen();
			} else if (document.msExitFullscreen) { /* IE/Edge */
				document.msExitFullscreen();
			}
		} else {
			var elem = document.getElementById("inner");
			if (elem.requestFullscreen) {
				elem.requestFullscreen();
			} else if (elem.mozRequestFullScreen) { /* Firefox */
				elem.mozRequestFullScreen();
			} else if (elem.webkitRequestFullscreen) { /* Chrome, Safari and Opera */
				elem.webkitRequestFullscreen();
			} else if (elem.msRequestFullscreen) { /* IE/Edge */
				elem.msRequestFullscreen();
			}
		}
	});
	$('#dbexport').on('click', function(ev) {
		var content = JSON.stringify(dashBoard);
		var filename = "LPAR2RRD-dashboard-" + sysInfo.uid + ".json";
		//var blob = new Blob([content], {
		//	type: "application/json;charset=utf-8"
		//});
		download(filename, content);
		// saveAs(blob, filename);
	});

	$('#dbimport').on('click', function(ev) {
		var input = document.createElement('input');
		input.type = 'file';
		input.multiple = false;
		input.accept = "application/json";


		input.onchange = function(e) {
			var file = e.target.files[0];
			var reader = new FileReader();
			reader.readAsText(file,'UTF-8');
			reader.onload = function (readerEvent) {
				var content = JSON.parse(readerEvent.target.result); // this is the content!
				if (content && content.tabs) {
					dashBoard = content;
					var postdata = {cmd: "savedashboard", user: sysInfo.uid, acl: JSON.stringify(dashBoard)};
					$.post( cgiPath + "/users.sh", postdata, function( data ) {
						genDashboard();
					});
				} else {
					$.message("File " + file.name + " doesn't look like dashboard content definition, import was canceled!", "Dashboard file check result");
				}
			};
		};

		input.click();
		// saveAs(blob, filename);
	});
	$("#health_status").tablesorter({
		theme: "ice",
		ignoreCase: false,
		sortList: [[0,0]],
		textExtraction : function(node, table, cellIndex) {
			n = $(node);
			return n.attr('data-sortValue') || n.text();
		}
	});
	if(sysInfo.xormonUIonly && !inXormon) {
		$("#side-menu").fancytree("getTree").getNodeByKey("dashboard").setActive();
	}

	if ($("#vmhistrepsrc").length) {
		if (! $("#vmhistrepsrc option").length) {
			$("<option />", {text: "--- choose one ---" , value: ""}).appendTo($( "#vmhistrepsrc"));
			$.getJSON(cgiPath + "/genjson.sh?jsontype=histrepsrcvm", function( data ) {
				$.each(data, function(mi, member) {
					var option = $("<option></option>");
					option.text(member.alias);
					option.val(member.vcenter);
					$("#vmhistrepsrc").append(option);
				});
				$("#vmhistrepsrc").multipleSelect('destroy').multipleSelect({
					single: true,
					filter: true,
					onClick: function(view) {
						// $("#histrepsrc").trigger("change");
					}
				});
				$("#vmhistrepsrc").on('change', function() {
					var label = $(this).find(":selected").text();
					if (label) {
						var url = cgiPath + "/histrep.sh?mode=vcenter&source=" + label;
						$('#vmhistrepdiv').load(url, function() {
							// imgPaths();
							myreadyFunc();
							return false;
						});
						$.cookie('vmhistrepsource', label, {
							expires: 60
						});
					} else {
						$("#vmhistrepdiv").empty();
					}
				});
				if ($.cookie('vmhistrepsource')) {
					$("#vmhistrepsrc option").filter(function() {
						return $(this).text() == $.cookie('vmhistrepsource');
					}).prop('selected', true);
					$("#vmhistrepsrc").multipleSelect('refresh').trigger("change");
				}
			});
		}
	}
	/*
	if ($("#overview_platform").length) {
		$("#overview_platform").multipleSelect('destroy').multipleSelect({
			single: true,
			filter: false,
			onClick: function(view) {
				// $("#histrepsrc").trigger("change");
			}
		});
		$("#overview_src").multipleSelect('destroy').multipleSelect({
			single: true,
			filter: true,
			hideOptgroupCheckboxes: false,
			onClick: function(view) {
				// $("#histrepsrc").trigger("change");
			}
		});
		var getOverview = function() {
			var platform = $("#overview_platform").find(":selected").val();
			var source = $("#overview_src").find(":selected").val();
			var srctype = $("#overview_src").find(":selected").data("srctype");
			if (platform && source && $("#overview_time").val()) {
				$("#overviewdiv").html("<div style='width: 100%; height: 100%; text-align: center'><img src='css/images/sloading.gif' style='margin-top: 100px'></div>");
				var data = {platform: platform, source: source, srctype: srctype, timerange:  $("#overview_time").val(), format: "html"};
				var url = cgiPath + "/overview.sh";
				$('#overviewdiv').load(url, data, function() {
					// imgPaths();
					myreadyFunc();
					return false;
				});
				$.cookie('histrepsource', $("#overview_src").find(":selected").text(), {
					expires: 60
				});
			} else {
				$("#overviewdiv").empty();
			}
		}
		$("#overview_src").off().on('change', function() {
			getOverview();
		});
		if ($.cookie('histrepsource')) {
			$("#overview_src option").filter(function() {
				return $(this).text() == $.cookie('histrepsource');
			}).prop('selected', true);
			// $("#overview_src").multipleSelect('refresh').trigger("change");
			$("#overview_src").multipleSelect('refresh');
		}
		if (! $("#overview_src option").length) {
			$("<option />", {text: "--- choose one ---" , value: ""}).appendTo($( "#overview_src"));
			$("<option />", {text: "Totals" , value: "totals"}).appendTo($( "#overview_src"));
			$.getJSON(cgiPath + "/genjson.sh?jsontype=overviewsources", function( data ) {
				$.each(data.groups, function(idx, group) {
					var optgroup = $('<optgroup></optgroup>');
					optgroup.attr('label', group.name);
					$.each(group.members, function (mi, member) {
						var option = $("<option></option>");
						option.attr("data-srctype", member.srctype);
						option.text(member.name);
						optgroup.append(option);
					});
					$("#overview_src").append(optgroup);
				});
				$.each(data.nogroup, function(mi, member) {
					var option = $("<option></option>");
					option.attr("data-hwtype", member.hwtype);
					option.text(member.name);
					$("#overview_src").append(option);
				});
				$("#overview_src").multipleSelect('refresh');
			});
		}
	}
	*/

}

function getOverview () {
	var platform = $("#overview_src").data( "platform" );
	var source = $("#overview_src").find(":selected").val();
	var srctype = $("#overview_src").find(":selected").data("srctype");
	if (platform && source && $("#overview_time").val()) {
		$("#overviewdiv").html("<div style='width: 100%; height: 100%; text-align: center'><img src='css/images/sloading.gif' style='margin-top: 100px'></div>");
		var data = {platform: platform, source: source, srctype: srctype, timerange:  $("#overview_time").val(), format: "html"};
		if (platform == "vmware") {
			data.vcenter = $("#overview_src").find(":selected").data("vcenter");
		}
		var url = cgiPath + (platform == "vmware" ? "/overview_vmware.sh" : "/overview.sh");
		$('#overviewdiv').load(url, data, function() {
			// imgPaths();
			loadImages('#content img.lazy');
			// myreadyFunc();
			if (timeoutHandle) {
				clearTimeout(timeoutHandle);
			}
			return false;
		});
		$.cookie('histrepsource', $("#overview_src").find(":selected").text(), {
			expires: 60
		});
	} else {
		$("#overviewdiv").empty();
	}
}

function overview_handler() {
	if ($(".overview_form").length) {
		$("#overview_src").multipleSelect('destroy').multipleSelect({
			single: true,
			filter: true,
			hideOptgroupCheckboxes: false,
			onClick: function(view) {
				// $("#histrepsrc").trigger("change");
			}
		});
		$("#overview_src").off().on('change', function() {
			getOverview();
		});
		if ($.cookie('histrepsource')) {
			$("#overview_src option").filter(function() {
				return $(this).text() == $.cookie('histrepsource');
			}).prop('selected', true);
			// $("#overview_src").multipleSelect('refresh').trigger("change");
			$("#overview_src").multipleSelect('refresh');
		}
		if (! $("#overview_src option").length) {
			$("<option />", {text: "--- choose one ---" , value: ""}).appendTo($( "#overview_src"));
			/* $("<option />", {text: "Totals" , value: "totals"}).appendTo($( "#overview_src")); */
			var platform = $("#overview_src").data( "platform" );
			if (platform == "power") {
				$.getJSON(cgiPath + "/genjson.sh?jsontype=overviewsources", function( data ) {
					var optgroup;
					$.each(data.groups, function(idx, group) {
						if (group.name == "SERVERS") {
							optgroup = $('<optgroup></optgroup>');
							optgroup.attr('label', group.name);
							$.each(group.members, function (mi, member) {
								var option = $("<option></option>");
								option.attr("data-srctype", member.srctype);
								option.text(member.name);
								optgroup.append(option);
							});
							$("#overview_src").append(optgroup);
						} else {
							optgroup = '';
							var cursrv = '';
							$.each(group.members, function (mi, member) {
								if (member.server != cursrv) {
									if (optgroup) {
										$("#overview_src").append(optgroup);
									}
									cursrv = member.server;
									optgroup = $('<optgroup></optgroup>');
									optgroup.attr('label', "LPARs: " + cursrv);
								}
								var option = $("<option></option>");
								option.attr("data-srctype", member.srctype);
								option.text(member.name);
								optgroup.append(option);
							});
							$("#overview_src").append(optgroup);
						}
					});
					$.each(data.nogroup, function(mi, member) {
						var option = $("<option></option>");
						option.attr("data-hwtype", member.hwtype);
						option.text(member.name);
						$("#overview_src").append(option);
					});
					$("#overview_src").multipleSelect('refresh');
				});
			} else if (platform == "ibmi") {
				$.getJSON(cgiPath + "/genjson.sh?jsontype=ibmilist", function( data ) {
					$.each(data, function(idx, host) {
						var option = $("<option></option>");
						option.attr("data-srctype", "lpar");
						option.text(host);
						$("#overview_src").append(option);
					});
					$("#overview_src").multipleSelect('refresh');
				});
			} else if (platform == "vmware") {
				$.getJSON(cgiPath + "/genjson.sh?jsontype=overview_vmware_clusters", function( data ) {
					$.each(data, function(idx, cluster) {
						var option = $("<option></option>");
						option.attr("data-srctype", "vcluster");
						option.attr("data-vcenter", cluster.vcenter);
						option.text(cluster.name);
						$("#overview_src").append(option);
					});
					$("#overview_src").multipleSelect('refresh');
				});
			}

		}
	}

	$("#customoverview").button().off().on("click", function() {
		if ($("#overview_src").val() && $("#fromRange").val() && $("#toRange").val()) {
			$("#overviewdiv").html("<div style='width: 100%; height: 100%; text-align: center'><img src='css/images/sloading.gif' style='margin-top: 100px'></div>");
			var platform = $("#overview_src").data( "platform" );
			var source = $("#overview_src").find(":selected").val();
			var srctype = $("#overview_src").find(":selected").data("srctype");
			var data = {platform: platform, source: source, srctype: srctype, sunix: $("#fromRange").datetimepicker("getDate").getTime() / 1000, eunix: $("#toRange").datetimepicker("getDate").getTime() / 1000, format: "html"};
			if (platform == "vmware") {
				data.vcenter = $("#overview_src").find(":selected").data("vcenter");
			}
			var url = cgiPath + (platform == "vmware" ? "/overview_vmware.sh" : "/overview.sh");
			$('#overviewdiv').load(url, data, function() {
				// imgPaths();
				loadImages('#content img.lazy');
				// myreadyFunc();
				return false;
			});
			$.cookie('histrepsource', $("#overviewsrc").find(":selected").text(), {
				expires: 60
			});
		}
	});

	if ($("#overview_time").length) {
		$("#overview_time").multipleSelect('destroy').multipleSelect({
			single: true,
			onClick: function(view) {
				if (view.value) {
					if (view.value == "custom") {
						$(".customrange").show().children().show();
						var now = new Date();
						var twoWeeksBefore = new Date();
						var yesterday = new Date();
						var nowPlusHour = new Date();
						yesterday.setDate(now.getDate() - 1);
						twoWeeksBefore.setDate(now.getDate() - 14);
						nowPlusHour.setHours(now.getHours() + 1);
						var startDateTextBox = $('#fromRange');
						var endDateTextBox = $('#toRange');
						var cookieFrom = yesterday;
						var cookieTo = now;
						var fromTime = $.cookie('fromTimeField');
						var toTime = $.cookie('toTimeField');
						if ( fromTime ) {
							cookieFrom = fromTime;
						}
						if ( toTime ) {
							cookieTo = toTime;
						}

						$("#fromRange").datetimepicker({
							// defaultDate: '-1d',
							dateFormat: "yy-mm-dd",
							timeFormat: "HH:00",
							maxDate: nowPlusHour,
							changeMonth: true,
							changeYear: true,
							// defaultValue: cookieFrom,
							showButtonPanel: true,
							showOtherMonths: true,
							selectOtherMonths: true,
							showMinute: false,
							onClose: function(dateText, inst) {
								if (endDateTextBox.val() !== '') {
									var testStartDate = startDateTextBox.datetimepicker('getDate');
									var testEndDate = endDateTextBox.datetimepicker('getDate');
									if (testStartDate > testEndDate) {
										endDateTextBox.datetimepicker('setDate', testStartDate);
									}
								} else {
									endDateTextBox.val(dateText);
								}
							},
							onSelect: function(selectedDateTime) {
								endDateTextBox.datetimepicker('option', 'minDate', startDateTextBox.datetimepicker('getDate'));
							}
						}).datetimepicker('setDate', cookieFrom);

						$("#toRange").datetimepicker({
							// defaultDate: 0,
							dateFormat: "yy-mm-dd",
							timeFormat: "HH:00",
							maxDate: nowPlusHour,
							changeMonth: true,
							changeYear: true,
							// defaultValue: cookieTo,
							showButtonPanel: true,
							showOtherMonths: true,
							selectOtherMonths: true,
							showMinute: false,
							onClose: function(dateText, inst) {
								if (startDateTextBox.val() !== '') {
									var testStartDate = startDateTextBox.datetimepicker('getDate');
									var testEndDate = endDateTextBox.datetimepicker('getDate');
									if (testStartDate > testEndDate) {
										startDateTextBox.datetimepicker('setDate', testEndDate);
									}
								} else {
									startDateTextBox.val(dateText);
								}
							},
							onSelect: function(selectedDateTime) {
								startDateTextBox.datetimepicker('option', 'maxDate', endDateTextBox.datetimepicker('getDate'));
							}
						}).datetimepicker('setDate', cookieTo);
					} else {
						$(".customrange").hide();
						getOverview();
					}
				} else {
					$("#overviewdiv").empty();
					$(".customrange").hide();
				}
			}
		});
	}
}

function fancyBox() {
	$('a.detail').colorbox({
		photo: true,
		speed: 100,
		fadeOut: 100,
		scalePhotos: true, // images won't be scaled to fit to browser's height
		maxWidth: "95%",
		initialWidth: 1326,
		initialHeight: 700,
		opacity: 0.4,
		onOpen: function(obj) {
			if (storedUrl) {
				obj.href = zoomedUrl;
			} else {
				var tUrl = obj.href;
				tUrl += "&nonefb=" + Math.floor(new Date().getTime() / 1000);
				obj.href = tUrl;
			}

			var tData = $(this).find("div.zoom").data();
			if (tData && tData.detail_url) {
				obj.href = tData.detail_url;
			}

			return true;
		},
		onComplete: function() {
			$('.cboxPhoto').off().on("click", $.colorbox.close);
		},
		onClosed: function() {
			if (storedUrl) {
				$(storedObj).attr("href", zoomedUrl);
				storedUrl = "";
				storedObj = {};
			}
		}
	});
}

function saveCookies() {
	var hashes = dbHash.join(":");
	$.cookie('dbHashes', hashes, {
		expires: 60
	});
}

function dbColorBox(img) {
	var tUrl = $(img).data("baseurl");
	/*
	$('#dbcontent .crop').on("click", function(ev) {
	if (ev.target.className == "lazydb") {
	return true;
	}
	var tUrl = $(this).find("img").data("baseurl");
	*/
	tUrl = tUrl.replace("detail=2", "detail=1");
	tUrl += "&none=" + Math.floor(new Date().getTime() / 1000);
	if(tUrl.indexOf("oracledb") !== -1){
		tUrl += "&dashboard=1";
	}
	$.colorbox({
		photo: true,
		href: tUrl,
		speed: 100,
		fadeOut: 100,
		scalePhotos: true,
		maxWidth: "95%",
		initialWidth: 1326,
		initialHeight: 700,
		opacity: 0.4,
		onComplete: function() {
			$('.cboxPhoto').off().on("click", $.colorbox.close);
		}
	});
}

function genOldDashboard() {
	$("ul.dashlist li").remove();
	if ($.cookie('flatDB')) {
		$( "#tabs" ).tabs( "destroy" );
		$( "#tabs > ul" ).hide();
		$( "#tabs div" ).hide();
		$( ".dashlist p" ).show();
	}
	if (dbHash.length) {
		var entitle = (sysInfo.entitle == 1) ? "1" : "0";
		var serverItemsArr = [ "pool", "lparagg", "pagingagg", "memalloc", "memaggreg", "memams", "vmdiskrw", "vmnetrw", "vmdisk", "vmnet", "poolagg", "pool-max", "shpool-max", 'ovirt_host_cpu_core', 'ovirt_host_cpu_percent', 'ovirt_host_mem', 'ovirt_host_nic_aggr_net', 'ovirt_host_nic_net' ];
		var as400ItemsArr = [ 'S0200ASPJOB', 'job_cpu', 'waj', 'disk_io', 'ASP', 'size', 'res', 'threads', 'faults', 'pages', 'ADDR', 'cap_used', 'cap_free', 'data_as', 'iops_as', 'disk_busy', 'disks', 'data_ifcb', 'paket_ifcb', 'dpaket_ifcb', 'cap_proc' ];
		var datastoreArr = [ 'dstrag_iopsr', 'dstrag_iopsw', 'dstrag_datar', 'dstrag_dataw', 'dstrag_used', 'dsmem', 'dsrw', 'dsarw', 'ds-vmiops', 'dslat'];
		var respoolArr = [ 'dstrag_iopsr', 'dstrag_iopsw', 'dstrag_datar', 'dstrag_dataw', 'dstrag_used'];
		$.each(dbHash, function(i, val) {
			var dbItem = hashRestore(val);
			if (jQuery.isEmptyObject(dbItem) || ! dbItem.item) {
				return true;
			}
			var complHref = urlQstring(dbItem, 1, entitle);
			var complUrl = urlQstring(dbItem, 2, entitle) + "&nonedb=" + Math.floor(new Date().getTime() / 1000);
			var title = "";
			if (dbItem.item == "shpool") {
				title = urlItems[dbItem.item][0] + ": " + dbItem.lpar + " | ";
			} else if ( $.inArray(dbItem.item, serverItemsArr) >= 0 ) {
				title = urlItems[dbItem.item][0] + ": " + dbItem.server + " | ";
			} else {
				var lparstr = dbItem.lpar;
				if (lparstr) {
					lparstr = lparstr.replace("--WPAR--", "/");
					lparstr = lparstr.replace("--NMON--", " (NMON)");
					title = urlItems[dbItem.item][0] + ": " + lparstr + " | ";
				}
			}
			title += intervals[dbItem.time];

			var topTitle = dbItem.server;
			if (dbItem.item.lastIndexOf("custom", 0) === 0 || dbItem.host == "no_hmc") {
				topTitle = dbItem.lpar;
			}
			if (/^ovirt_.*/.test(dbItem.item) || /^xen-.*/.test(dbItem.item) || /^nutanix-.*/.test(dbItem.item)) {
				topTitle = dbItem.parent;
			}
			if (dbItem.host == "nope") {
				topTitle = "";
			}
			if (/^clust.*/.test(dbItem.item)) {
				topTitle = dbItem.parent;
				if (/^cluster_.*/.test(topTitle)) {
					topTitle = topTitle.replace(/^cluster_/, "");
				}
			}

			var flat = $.cookie('flatDB');

			if (dbItem.item) {
				if (dbItem.item.lastIndexOf("custom", 0) === 0) {
					$( "#tabs > ul li:eq( 0 )" ).show();
					if (flat) {
						$( "#tabs-1" ).show();
					}
					$("#dashboard-cust").append("<li><a href='" + complHref + "' class='detail'><span class='dbitemtitle'>" + topTitle + "</span></br><img class='lazy' src='css/images/sloading.gif' data-src='" + complUrl + "' title='" + title + "' alt='" + val + "'></a><div class='dash' title='Remove this item from DashBoard'></div></li>");
				} else if ($.inArray(dbItem.item, serverItemsArr) >=0 || dbItem.item == "shpool" || /^xen-host.*/.test(dbItem.item) || /^nutanix-host.*/.test(dbItem.item)) {
					$( "#tabs > ul li:eq( 1 )" ).show();
					if (flat) {
						$( "#tabs-2" ).show();
					}
					$("#dashboard-srv").append("<li><a href='" + complHref + "' class='detail'><span class='dbitemtitle'>" + topTitle + "</span></br><img class='lazy' src='css/images/sloading.gif' data-src='" + complUrl + "' title='" + title + "' alt='" + val + "'></a><div class='dash' title='Remove this item from DashBoard'></div></li>");
				} else if ($.inArray(dbItem.item, as400ItemsArr) >=0) {
					$( "#tabs > ul li:eq( 3 )" ).show();
					if (flat) {
						$( "#tabs-4" ).show();
					}
					$("#dashboard-as400").append("<li><a href='" + complHref + "' class='detail'><span class='dbitemtitle'>" + topTitle + "</span></br><img class='lazy' src='css/images/sloading.gif' data-src='" + complUrl + "' title='" + title + "' alt='" + val + "'></a><div class='dash' title='Remove this item from DashBoard'></div></li>");
				} else if (($.inArray(dbItem.item, datastoreArr) >=0) || /^ovirt_storage.*/.test(dbItem.item) || /^xen-pool.*/.test(dbItem.item) || /^nutanix-pool.*/.test(dbItem.item)) {
					$( "#tabs > ul li:eq( 4 )" ).show();
					if (flat) {
						$( "#tabs-5" ).show();
					}
					$("#dashboard-dstr").append("<li><a href='" + complHref + "' class='detail'><span class='dbitemtitle'>" + topTitle + "</span></br><img class='lazy' src='css/images/sloading.gif' data-src='" + complUrl + "' title='" + title + "' alt='" + val + "'></a><div class='dash' title='Remove this item from DashBoard'></div></li>");
				} else if ((dbItem.item.lastIndexOf("clust", 0) === 0) || /^ovirt_cluster.*/.test(dbItem.item)) {
					$( "#tabs > ul li:eq( 5 )" ).show();
					if (flat) {
						$( "#tabs-6" ).show();
					}
					$("#dashboard-clstr").append("<li><a href='" + complHref + "' class='detail'><span class='dbitemtitle'>" + topTitle + "</span></br><img class='lazy' src='css/images/sloading.gif' data-src='" + complUrl + "' title='" + title + "' alt='" + val + "'></a><div class='dash' title='Remove this item from DashBoard'></div></li>");
				} else {
					$( "#tabs > ul li:eq( 2 )" ).show();
					if (flat) {
						$( "#tabs-3" ).show();
					}
					$("#dashboard-lpar").append("<li><a href='" + complHref + "' class='detail'><span class='dbitemtitle'>" + topTitle + "</span></br><img class='lazy' src='css/images/sloading.gif' data-src='" + complUrl + "' title='" + title + "' alt='" + val + "'></a><div class='dash' title='Remove this item from DashBoard'></div></li>");
				}
			}
		});

		if ( $("#tabs > ul li:visible").length == 1) {
			$("#tabs > ul li:visible a").trigger("click");
		}

		$(".dashlist li").css({
			"width": Number(sysInfo.dashb_rrdwidth) + 75 + "px",
			"height": Number(sysInfo.dashb_rrdheight) + 60 + "px"
			//	"line-height": Number(sysInfo.dashb_rrdheight) + 60 + "px"
		});
		loadImages('#content img.lazy');
		fancyBox();

		$("div.dash").on("click", function() {
			var hash = $(this).parent().find('img').attr('alt');
			if (! hash) {
				hash = $(this).parent().find('div.error_placeholder').attr('alt');
			}
			var toRemove = $.inArray(hash, dbHash);
			if (toRemove >= 0) {
				dbHash.splice(toRemove, 1);
				saveCookies();
				$(this).parent().hide("slow");
			}
		});
		$("ul.dashlist").sortable({
			dropOnEmpty: false
		});

		$("ul.dashlist").on("sortupdate", function(event, ui) {
			dbHash.length = 0;
			$("ul.dashlist li").find('img').each(function() {
				var hash = $(this).attr('alt');
				dbHash.push(hash);
			});
			saveCookies();
		});
	}
}

function genDashboard() {
	if(sysInfo.xormonUIonly) {
		$("#emptydash").hide();
		return;
	}
	if (sysInfo.demo) {
		$( "#stor2rrd" ).attr("onclick", "window.location.href = '//demo.stor2rrd.com'");
		$( "#xormon" ).attr("onclick", "window.location.href = '//demo.xormon.com'");
	} else if (sysInfo.vmImage) {
		$( "#stor2rrd" ).attr("onclick", "window.location.href = '/stor2rrd'");
		$( "#xormon" ).attr("onclick", "window.location.href = '/xormon'");
	}
	if (prodName == "LPAR2RRD - ") {
		$( "#stor2rrd" ).show();
		$( "#xormon" ).show();
	}
	if (sysInfo.useOldDashboard) {
		$('#dbcontent').show();
		$('.olddbbutton').show();
		$('.newdbbutton').hide();
		genOldDashboard();
	} else {
		$('#dbcontent').empty().show();
		$('.olddbbutton').hide();
		$('.newdbbutton').show();
		if (!sysInfo.demo) {
			$("#conttitle").hide();
		}

		var lazyDashboard = function (div) {
			div.addClass("lazy_enough");
			div.each(function( i ) {
				$(this).find('img.lazydb').lazy({
					bind: 'event',
					effect: 'fadeIn',
					effectTime: 400,
					threshold: 100,
					visibleOnly: true,
					appendScroll: $("div#econtent"),
					lazyLoader: function(element, resolve) {
						element.parents(".crop").css("vertical-align", "middle");
						var jqXHR = new XMLHttpRequest();
						jqXHR.open("GET", $(element).attr("data-src"), true);
						jqXHR.responseType = "arraybuffer";

						jqXHR.onreadystatechange = function(oEvent) {
							if (this.readyState == 4 && this.status == 200) {
								var error = jqXHR.getResponseHeader('X-XoruX-Error');
								if (error) {
									var baseurl = $(element).data("baseurl");
									$(element).replaceWith("<div class='db_error_placeholder' data-baseurl='"+ baseurl +"'>" + Base64.decode(error) + "</div><div class='dash' title='Remove this item from DashBoard'></div>");
								} else {
									var arrayBuffer = jqXHR.response; // Note: not oReq.responseText
									if (arrayBuffer) {
										var byteArray = new Uint8Array(arrayBuffer);
										$(element).attr("src", "data:image/png;base64," + btoa(String.fromCharCode.apply(null, new Uint8Array(byteArray))));
									}
								}
								resolve(true);
							}
							// element.data("imgurl", element.data("src"));
						};
						jqXHR.send(null);
					},
					afterLoad: function(element) {
						$(element).removeClass('load');
						$(element).parents(".crop").css("vertical-align", "top");
					}
				});
			});
		};

		var dashboardClickInit = function () {
			$('#dbcontent img.lazydb').on("click", function(ev) {
				dbColorBox(this);
			});
			$('.grpname_edicon').off().on("click", function(ev) {
				var $span = $(this).siblings('.grpname');
				var name = $span.text();
				if (name == "Unclassified" ) {

				}
				$("<div></div>").dialog({
					// Remove the closing 'X' from the dialog
					open: function(event, ui) {
						$(".ui-dialog-titlebar-close").hide();
						$(this).append("<input id='dbgrpedit' value='" + name + "'/>");
						$("#dbgrpedit").width("18em");
					},
					buttons: {
						"OK": function() {
							var newtext = $("#dbgrpedit").val();
							$(this).dialog("close");
							$span.text(newtext);
							saveFlexiDashboard();
						},
						"Cancel": function() {
							$(this).dialog("close");
						}
					},
					close: function(event, ui) {
						$(this).remove();
					},
					resizable: false,
					position: { my: 'left', at: 'right', of: $(this) },
					minWidth: 340,
					title: "Rename dashboard group",
					modal: true
				});
			});
		};
		if ($.isEmptyObject(dashBoard) || dashBoard.tabs.length <1) {
			$("ul.dashlist li").remove();
			if ($.cookie('flatDB')) {
				$( "#tabs" ).tabs( "destroy" );
				$( "#tabs > ul" ).hide();
				$( "#tabs div" ).hide();
				$( ".dashlist p" ).show();
			}
			if (dbHash.length) {
				var entitle = (sysInfo.entitle == 1) ? "1" : "0";
				var serverItemsArr = [ "pool", "lparagg", "pagingagg", "memalloc", "memaggreg", "memams", "vmdiskrw", "vmnetrw", "vmdisk", "vmnet", "poolagg", "pool-max", "shpool-max", 'ovirt_host_cpu_core', 'ovirt_host_cpu_percent', 'ovirt_host_mem', 'ovirt_host_nic_aggr_net', 'ovirt_host_nic_net' ];
				var as400ItemsArr = [ 'S0200ASPJOB', 'job_cpu', 'waj', 'disk_io', 'ASP', 'size', 'res', 'threads', 'faults', 'pages', 'ADDR', 'cap_used', 'cap_free', 'data_as', 'iops_as', 'disk_busy', 'disks', 'data_ifcb', 'paket_ifcb', 'dpaket_ifcb', 'cap_proc' ];
				var datastoreArr = [ 'dstrag_iopsr', 'dstrag_iopsw', 'dstrag_datar', 'dstrag_dataw', 'dstrag_used', 'dsmem', 'dsrw', 'dsarw', 'ds-vmiops', 'dslat'];
				var respoolArr = [ 'dstrag_iopsr', 'dstrag_iopsw', 'dstrag_datar', 'dstrag_dataw', 'dstrag_used'];
				$.each(dbHash, function(i, val) {
					var dbItem = hashRestore(val);
					if (jQuery.isEmptyObject(dbItem) || ! dbItem.item) {
						return true;
					}
					if (dbItem.host == "no_hmc" && dbItem.server == "Linux") {
						dbItem.server = "Linux--unknown";
					}
					var complHref = urlQstring(dbItem, 1, entitle);
					var complUrl = urlQstring(dbItem, 2, entitle); // + "&nonedb=" + Math.floor(new Date().getTime() / 1000);
					var title = "";
					if (dbItem.item == "shpool") {
						title = urlItems[dbItem.item][0] + ": " + dbItem.lpar + " | ";
					} else if ( $.inArray(dbItem.item, serverItemsArr) >= 0 ) {
						title = urlItems[dbItem.item][0] + ": " + dbItem.server + " | ";
					} else {
						var lparstr = dbItem.lpar;
						if (lparstr) {
							lparstr = lparstr.replace("--WPAR--", "/");
							lparstr = lparstr.replace("--NMON--", " (NMON)");
							title = urlItems[dbItem.item][0] + ": " + lparstr + " | ";
						}
					}
					title += intervals[dbItem.time];

					var topTitle = dbItem.server;
					if (dbItem.item.lastIndexOf("custom", 0) === 0 || dbItem.host == "no_hmc") {
						topTitle = dbItem.lpar;
					}
					if (/^ovirt_.*/.test(dbItem.item) || /^xen-.*/.test(dbItem.item) || /^nutanix-.*/.test(dbItem.item)) {
						topTitle = dbItem.parent;
					}
					if (dbItem.host == "nope") {
						topTitle = "";
					}
					if (/^clust.*/.test(dbItem.item)) {
						topTitle = dbItem.parent;
						if (/^cluster_.*/.test(topTitle)) {
							topTitle = topTitle.replace(/^cluster_/, "");
						}
					}

					var flat = $.cookie('flatDB');

					var dbGroupAdd = function(dbclass, dbtitle) {
						var group = $("<div class='dashgroup " + dbclass +"'><div><div class='dashgroup-header'><span class='grpname'>" + dbtitle + "</span><span class='grpname_edicon ui-icon ui-icon-pencil'></span></div><div class='grid'></div></div></div>");
						$("#dbcontent").append(group);
					};

					if (dbItem.item) {
						var menukey = "data-menukey='" + val.substring(0, 7) + "'";
						var el = "<div class='grid-item'" + menukey + "><div class='grid-item-content'><div class='crop'><span class='dbitemtitle'>" + topTitle + "</span><br><img class='lazydb load' src='css/images/sloading.gif' data-src='" + complUrl + "' data-baseurl='" + complHref + "' title='" + title + "' alt='" + val + "'></div><div class='jumptopage ui-icon ui-icon-arrowthickstop-1-e' title='Jump to related page'></div><div class='rmdbitem' title='Remove this item from DashBoard'></div></div></div>";
						if (dbItem.item.lastIndexOf("custom", 0) === 0) {
							if ($(".dashgroup.custom .grid").length <1) {
								dbGroupAdd("custom", "Custom Groups");
							}
							$(".dashgroup.custom .grid").append(el);
						} else if ($.inArray(dbItem.item, serverItemsArr) >=0 || dbItem.item == "shpool" || /^xen-host.*/.test(dbItem.item) || /^nutanix-host.*/.test(dbItem.item)) {
							if ($(".dashgroup.server .grid").length <1) {
								dbGroupAdd("server", "Server");
							}
							$(".dashgroup.server .grid").append(el);
						} else if ($.inArray(dbItem.item, as400ItemsArr) >=0) {
							if ($(".dashgroup.as400 .grid").length <1) {
								dbGroupAdd("as400", "AS/400");
							}
							$(".dashgroup.as400 .grid").append(el);
						} else if (($.inArray(dbItem.item, datastoreArr) >=0) || /^ovirt_storage.*/.test(dbItem.item) || /^xen-pool.*/.test(dbItem.item) || /^nutanix-pool.*/.test(dbItem.item)) {
							if ($(".dashgroup.storage .grid").length <1) {
								dbGroupAdd("storage", "Storage");
							}
							$(".dashgroup.storage .grid").append(el);
						} else if ((dbItem.item.lastIndexOf("clust", 0) === 0) || /^ovirt_cluster.*/.test(dbItem.item)) {
							if ($(".dashgroup.cluster .grid").length <1) {
								dbGroupAdd("cluster", "Cluster");
							}
							$(".dashgroup.cluster .grid").append(el);
						} else {
							if ($(".dashgroup.lpar .grid").length <1) {
								dbGroupAdd("lpar", "LPAR/VM");
							}
							$(".dashgroup.lpar .grid").append(el);
						}
					}
				});
				gridInit();
				saveFlexiDashboard();
				dashboardClickInit();
				dbHash.length = 0;
				saveCookies();
			}
		} else {
			$("#dbcontent").empty();
			$("#emptydash").hide();
			var postdata = {cmd: "loaddashboard", user: sysInfo.uid};
			if(!inXormon){
				$.getJSON('/lpar2rrd-cgi/users.sh', postdata, function(data) {
					if (! $.isEmptyObject(data)) {
					dashBoard = data;
					if (! dashBoard.tabs || dashBoard.tabs.length < 1) {
						dashBoard.tabs = [];
						if (dashBoard.groups && dashBoard.groups.length) {
							dashBoard.tabs[0] = {name: "Default", groups: dashBoard.groups};
							delete dashBoard.groups;
						} else {
							dashBoard.tabs[0] = {name: "Default", groups: []};
						}
					}
				}
				if (dashBoard.tabs.length > 0) {
					var dbTabs = $("<div id='dbtabs'><ul></ul></div>");
					$("#dbcontent").append(dbTabs);
					$.each(dashBoard.tabs, function(ti, tab) {
						var tabIdx = 'tabs-' + ti;
						var tabLink = "<li><input class='txt' type='text' /><a href='#" + tabIdx + "'>" + tab.name + "<span class='rmdbtab' title='Remove this tab'></span></a></li>";
						$('#dbtabs').find("ul").append(tabLink);
						var tabDiv = $("<div id='" + tabIdx + "'></div>");
						$.each(tab.groups, function(gi, group) {
							$(tabDiv).append(genDbGroup(group));
						});
						$('#dbtabs').append(tabDiv);
						if (tab.groups.length) {
							gridInit( ti );
						} else if (dashBoard.tabs.length == 1) {
							$("#emptydash").show();
						}
					});
					var activeTab;
					if (setDbTabByName) {
						var tabTitles = $( "#dbtabs li a" ).map(function(i, el) {
							return $(el).text();
						}).get();
						var tabPos = jQuery.inArray( setDbTabByName, tabTitles );
						setDbTabByName = "";
						if (tabPos !== -1) {
							activeTab = tabPos;
						} else {
							activeTab = 0;
						}
					} else {
						activeTab = $.cookie('dbActiveTab') ? $.cookie('dbActiveTab') : 0;
					}

					$('#dbtabs').tabs({
						overflowTabs: true,
						tabPadding: 23,
						containerPadding: 40,
							hasButtons: true,
						active: activeTab,
						create: function( event, ui ) {
							lazyDashboard(ui.panel);
						},
						activate: function( event, ui ) {
							$.cookie('dbActiveTab', ui.newTab.index(), {
								expires: 60
							});
								if (! ui.newPanel.hasClass("lazy_enough")) {
									lazyDashboard(ui.newPanel);
								}
						}
					}).find( ".ui-tabs-nav" ).sortable({
						axis: "x",
						stop: function() {
							$('#dbtabs').tabs( "refresh" );
							saveFlexiDashboard();
						}
					});
					$('#dbtabs').off("click", ".rmdbtab").on('click', ".rmdbtab", function(ev) {
						ev.stopPropagation;
						var tabtoremove = $(ev.target).parent().text();
							var conf = confirm("Do you really want to remove tab [" + tabtoremove + "] and all it's content from Dashboard?");
						if (conf === true) {
							var panelId = $( this ).closest( "li" ).remove().attr( "aria-controls" );
							$( "#" + panelId ).remove();
							$('#dbtabs').tabs( "refresh" );
							saveFlexiDashboard();
							/*
				$.each(dashBoard.groups, function(i, group) {
								if (group.name == grpname) {
									dashBoard.groups.splice(i, 1);
									return false;
								}
							})
							*/
						}
					});
					$('.tab').off().on('dblclick', function() {
						$(this).find('input').toggle().val($(this).find('a').html()).focus();
						$(this).find('a').toggle();
					});
					$('.tab').on('keydown blur dblclick','input',function(e) {
						if (e.type=="keydown") {
							if (e.which==13) {
								$(this).toggle();
								$(this).siblings('a').toggle().html($(this).val());
								saveFlexiDashboard();
							}
							if (e.which==38 || e.which==40 || e.which==37 || e.which==39) {
								e.stopPropagation();
							}
						} else if (e.type=="focusout") {
							if($(this).css('display')=="inline-block") {
								$(this).toggle();
								$(this).siblings('a').toggle().html($(this).val());
								saveFlexiDashboard();
							}
						} else {
							e.stopPropagation();
						}
					});
				} else {
					$.each(dashBoard.tabs[0].groups, function(i, group) {
						$("#dbcontent").append(genDbGroup(group));
					});
					gridInit();
				}
					dashboardClickInit();
				});
			}
		}
	}
}
function genDbGroup (group) {
	var divgrid = $("<div class='grid'></div>");
	$.each(group.tree, function(j, item) {
		var iw = item.width ? item.width : 220;
		var ih = item.height ? item.height : 170;
		iw -= 50;
		ih -= 60;
		var imgurl = item.url + "&width=" + iw.toString() + "&height=" + ih.toString() + "&nonefb=" + Math.floor(new Date().getTime() / 1000);
		imgurl = replaceUrlParam(imgurl, "detail", 2);
		var menukey = item.menukey ? "data-menukey='" + item.menukey + "'" : "";
		var hash = item.hash ? "data-hash='" + item.hash + "'" : "";
		var tab = item.tab ? " data-tab='" + item.tab + "'" : "";
		var metric = getUrlParameters("item", item.url);
		var datastoreArr = [ 'dstrag_iopsr', 'dstrag_iopsw', 'dstrag_datar', 'dstrag_dataw', 'dstrag_used', 'dsmem', 'dsrw', 'dsarw', 'ds-vmiops', 'dslat'];
		if (metric && ($.inArray(metric, datastoreArr) >=0)) {
			item.title = item.title.replace(/^datastore_/, "");
		}
		var el = $("<div class='grid-item'" + menukey + tab + hash + "><div class='crop'><span class='dbitemtitle'>" + item.title + "</span><br><img class='lazydb load' src='css/images/sloading.gif' data-loader='lazyLoader' data-src='" + imgurl + "' data-baseurl='" + item.url + "' title='" + "' alt='" + "'><div class='jumptopage ui-icon ui-icon-arrowthickstop-1-e' title='Jump to related page'></div><div class='rmdbitem' title='Remove this item from DashBoard'></div></div></div>");
		el.width(item.width);
		el.height(item.height);
		divgrid.append(el);
	});
	var grpicon = "<span class='grpname_edicon ui-icon ui-icon-pencil' title='Edit group name'></span><div class='dbgrpremove' title='Remove this group from DashBoard'></div>";
	var dgroup = $("<div class='dashgroup'><div><div class='dashgroup-header'><span class='grpname' title='" + group.name + "'>" + group.name + "</span>" + grpicon + "</div></div></div>");
	if (group.width) {
		dgroup.width(group.width);
	}
	if (group.height) {
		// dgroup.height(group.height);
	}
	dgroup.find(".dashgroup-header").after(divgrid);
	return dgroup;
}

function gridInit(tab) {
	var grids = [],
	mainGrid,
	mainGridSelector;
	if (tab > -1) {
		mainGridSelector = "#tabs-" + tab;
	} else {
		mainGridSelector = '#dbcontent';
	}
	// var images = document.querySelectorAll('.grid-item img, .grid-item a');
	// var itemContainers = [].slice.call(document.querySelectorAll('.grid'));
	// var isIE = detectIE();
	$(mainGridSelector + ' .grid').each(function(i) {
		var $grid = $(this);
		var grid = new Muuri(this, {
			dragEnabled: true,
			dragContainer: document.body,
			items: '.grid-item',
			dragPlaceholder: {
				enabled: true
			},
			dragSort: function () {
				return grids;
			},
			dragStartPredicate: {
				handle: '.crop',
				distance: 10,
				delay: 50
			}
		});
		$grid.on('click', "div.rmdbitem", function(ev) {
			var item = $(this).parents(".grid-item")[0];
			var hashtoremove = $(item).data("hash");
			grid.remove(item, {removeElements: true});
			$.each(dashBoard.tabs, function(ti, tab) {
				$.each(tab.groups, function(i, group) {
					$.each(group.tree, function(j, gritem) {
						if (gritem.hash == hashtoremove) {
							group.tree.splice(j, 1);
							return false;
						}
					});
				});
			});
			// grid.synchronize();
			saveFlexiDashboard();
		});
		$grid.on('click', "div.jumptopage", function(ev) {
			var item = $(this).parents(".grid-item")[0];
			var menukey = $(item).data("menukey");
			if (menukey) {
				var $tree = $("#side-menu").fancytree("getTree");
				var jumpToNode = $tree.findFirst(function(node) {
					return node.data.hash === menukey;
				});
				if ($(item).data("tab")) {
					forceTab = $(item).data("tab");
				}
				if (jumpToNode) {
				jumpToNode.setActive();
			}
			}
		});
		grid.on('dragReleaseStart', function (item) {
			$(item.getElement()).find("img").off("click"); // dirty hack for FF firing click event on drag stop
		});
		grid.on("dragReleaseEnd", function (item) {
			$(item.getElement()).find("img").on("click", function(ev) {
				dbColorBox(this);
			});
			grid.synchronize();
			saveFlexiDashboard();
		});

		// get item elements, jQuery-ify them
		var $itemElems = $grid.find(".grid-item");

		// make item elements resizable
		$itemElems.resizable({
			grid: [87, 57],
			handles: "se",
			minWidth: 170,
			minHeight: 110,
			// autoHide: true,
			start: function( event, ui ) {
			},
			stop: function( event, ui ) {
				var crop = $(event.target).find("div.crop");
				crop.css("width", ui.size.width);
				crop.css("height", ui.size.height);
				var img = crop.find("img");
				var src = img.data("src");
				src = replaceUrlParam(src, "width", ui.size.width - 50);
				src = replaceUrlParam(src, "height", ui.size.height - 60);
				img.attr("src", src);
				grid.refreshItems().layout();
				saveFlexiDashboard();
			}
		});
		$itemElems.on( 'resize', function( event, ui ) {
			mainGrid.refreshItems().layout();
			grid.refreshItems().layout();
		});
		grids.push(grid);
	});
	mainGrid = new Muuri(mainGridSelector, {
		layoutDuration: 400,
		items: '.dashgroup',
		dragPlaceholder: {
			enabled: true
		},
		dragContainer: document.querySelector(mainGridSelector),
		dragEnabled: true,
		dragSortInterval: 0,
		dragStartPredicate: {
			handle: '.dashgroup-header'
		},
		dragReleaseDuration: 400,
		dragReleaseEasing: 'ease'
	});
	mainGrid.on("dragReleaseEnd", function (item) {
		mainGrid.synchronize();
		saveFlexiDashboard();
	});
	$(mainGridSelector + ' .dbgrpremove').on("click", function(ev) {
		ev.stopPropagation;
		var conf = confirm("Do you really want to remove this group and all it's items from DashBoard?");
		if (conf === true) {
			var item = $(this).parents('.dashgroup')[0];
			var tabname = $("#dbtabs .ui-tabs-active").text();
			var grpname = $(item).find(".grpname").text();
			mainGrid.remove(item, {removeElements: true});
			saveFlexiDashboard();
			var etab = $.grep(dashBoard.tabs, function( tab ) {
				return tab.name == tabname;
			});
			$.each(etab.groups, function(i, group) {
				if (group.name == grpname) {
					dashBoard.groups.splice(i, 1);
					return false;
				}
			});
		}

	});

	var $items = $(mainGridSelector + " .dashgroup");

	$items.resizable({
		grid: [87, 57],
		handles: "se",
		minWidth: 170,
		minHeight: 110,
		autoHide: true,
		stop: function( event, ui ) {
			grids.forEach(function (container) {
				container.refreshItems().layout();
			});
			mainGrid.refreshItems().layout();
			saveFlexiDashboard();
		}
	});
	// handle resizing
	$items.on( 'resize', function( event, ui ) {
		mainGrid.refreshItems().layout();
	});
}

function saveFlexiDashboard () {
	var dbTree = {};
	dbTree.tabs = [];
	if ( $("#dbtabs").length ) {
		// var parentTab = $("#tabs .ui-tabs-active").text();
		$.each($("#dbtabs ul li"), function(tabidx, tab) {
			var tabObj = {};
			tabObj.name = $(tab).find("a").text();
			tabObj.groups = [];
			var panel = $(tab).find("a").attr("href");
			var tabGroups = $(panel).find(".dashgroup");
			tabGroups.each(function(gi, grobj) {
		var grpname = $(grobj).find(".grpname").text();
		if (! grpname) {
					grpname = $(grobj).find(".dash-group-header").text();
		}
		var grptree = [];
		var grid = $(grobj).find(".grid");
		if ($(grid).find("img.lazydb")) {
			$.each($(grid).find('.grid-item'), function(item, itemobj) {
				var dbobj = {};
				var img = $(itemobj).find("img.lazydb");
				if (! img.length) {
					img = $(itemobj).find(".db_error_placeholder");
				}
				var url = img.data("baseurl");
				if (url) {
					url = url.replace(/&none=.*/g, '');
					url = replaceUrlParam(url, "detail", 2);
					var hash = hex_md5(url).substring(0, 7);
					// dbTree.hashes.push(hash);
					// dbobj.url = img.data("revert_url");
					dbobj.url = url;
					dbobj.title = img.siblings(".dbitemtitle").text();
					dbobj.hash = hash;
					dbobj.menukey = $(itemobj).data("menukey");
					dbobj.tab = $(itemobj).data("tab");
					dbobj.width = $(itemobj).width();
					dbobj.height = $(itemobj).height();
					grptree.push(dbobj);
				}
			});
			var dbGroup = {};
			dbGroup.name = grpname;
			dbGroup.tree = grptree;
			dbGroup.width = $(grobj).width();
			dbGroup.height = $(grobj).height();
					tabObj.groups.push(dbGroup);
		}
	});
			dbTree.tabs.push(tabObj);
		});
	}
	var postdata = {cmd: "savedashboard", user: sysInfo.uid, acl: JSON.stringify(dbTree)};
	$.post( "/lpar2rrd-cgi/users.sh", postdata, function( data ) {
		var returned = JSON.parse(data);
		if ( returned.status != "success" ) {
			// $("#aclfile").text(returned.cfg).show();
		}
	});
	if ($.isEmptyObject(dashBoard)) {
		dashBoard = dbTree;
	}
/*
	var postdata = "save=db_" + dbfilename.val() + "&cookie=" + $.cookie('dbHashes');

	$.ajax( { method: "GET" , url: "/lpar2rrd-cgi/dashboard.sh", data: postdata} ).done( function( data ) {
		$(data.msg).dialog({
			dialogClass: "info",
			title: "DashBoard save - " + data.status,
			minWidth: 600,
			modal: true,
			show: {
				effect: "fadeIn",
				duration: 500
			},
			hide: {
				effect: "fadeOut",
				duration: 200
			},
			buttons: {
				OK: function() {
					$(this).dialog("destroy");
				}
			}
		});
	});
	*/
}

function saveDbState() {
	var valid = true;
	dbfilename = $("#dbfilename");
	dbfilename.removeClass( "ui-state-error" );

	valid = valid && checkLength( dbfilename, "filename", 1, 160 );
	valid = valid && checkRegexp( dbfilename, /^([0-9a-zA-Z_\s])+$/i, "File name may consist of A-Z, a-z, 0-9, underscores and spaces." );
	if ( $('#dbfilecombo option[value="' + dbfilename.val() + '"]').length ) {
		valid = valid && confirm ("File '" + dbfilename.val() + "' already exists, do you want to overwrite");
	}

	if ( valid ) {
	// var postdata = { "save": "db_websave", "cookie" : $.cookie('dbHashes')};
	var postdata = "save=db_" + dbfilename.val() + "&cookie=" + $.cookie('dbHashes');

	$.ajax( { method: "GET" , url: "/lpar2rrd-cgi/dashboard.sh", data: postdata} ).done( function( data ) {
		$(data.msg).dialog({
			dialogClass: "info",
			title: "DashBoard save - " + data.status,
			minWidth: 600,
			modal: true,
			show: {
				effect: "fadeIn",
				duration: 500
			},
			hide: {
				effect: "fadeOut",
				duration: 200
			},
			buttons: {
				OK: function() {
					$(this).dialog("destroy");
				}
			}
		});
	});
	$("#dialog-form").dialog("destroy");
	}
	return valid;
}

function restoreDbState() {
	dbfilename = $("#dbfilename");
	dbfilename.removeClass( "ui-state-error" );

	// var postdata = { "save": "db_websave", "cookie" : $.cookie('dbHashes')};
	var postdata = "load=db_" + dbfilename.val();

	$.get( "/lpar2rrd-cgi/dashboard.sh?" + postdata, function( data ) {
		if ( data.status == "success" && data.cookie) {
			$.cookie('dbHashes', data.cookie, {
				expires: 60
			});
			$("#side-menu").fancytree("getTree").reactivate();
			$("<p>DashBoard has been successfully restored from " + data.filename + "</p>").dialog({
				dialogClass: "info",
				title: "DashBoard restore - " + data.status,
				minWidth: 600,
				modal: true,
				show: {
					effect: "fadeIn",
					duration: 500
				},
				hide: {
					effect: "fadeOut",
					duration: 200
				},
				buttons: {
					OK: function() {
						$(this).dialog("destroy");
					}
				}
			});
		}
	});
	$("#dialog-form").dialog("destroy");
//		genDashboard;
	return true;
}

function itemDetails(pURL, decode) {
	var host = getUrlParameters("host", pURL, decode);
	var server = getUrlParameters("server", pURL, decode);
	var lpar = getUrlParameters("lpar", pURL, decode);
	var item = getUrlParameters("item", pURL, false);

	if (lpar == "cod" && item.substring(0, 3) == "hea" ) {
		lpar = item;
		item = "hea";
	}
	if (item && item.match("^dstrag_")) {
		host = "nope";
		server = "nope";
		lpar = "nope";
	}

	// var itemcode = String.fromCharCode(97 + $.inArray(item, itemKeys));
	var itemcode = "";
	try {
		itemcode = urlItems[item][1];
	} catch (exception) {
		window.console && console.log("Unknown URL item type: " + item);
	}
	var time = getUrlParameters("time", pURL, false);
	var sam = getUrlParameters("type_sam", pURL, false).substring(0, 1);


	return {
		"host": host,
		"server": server,
		"lpar": lpar,
		"item": item,
		"time": time,
		"type_sam": sam,
		"itemcode": itemcode
	};
}

function hashRestore(hash) {
	var params = {};
	var i = hashTable[hash.substring(0, 7)];
	if (i) {
		var indexChars = hash.substring(7, 9);
		var itemIndex = jQuery.map(urlItems, function (item, index) {
			return item[1] == indexChars ? index : null;
		});
		var item = itemIndex[0];
		var time = hash.substring(9, 10);
		var sam = hash.substring(10, 11);
		var src = hash.substring(11, 12);
		if (i.platform) {
			if (i.agent && !(/^ovirt_.*/.test(item) || /^xen-.*/.test(item) || /^nutanix-.*/.test(item))) {
				params = {
					"host": "no_hmc",
					"server": "Linux",
					"lpar": i.agent,
					"item": item,
					"time": time,
					"type_sam": sam,
					"parent": i.parent
				};
			} else {
				var lparname = i.type;
				var server = "nope";
				if (i.platform == "XenServer") {
					if (/^xen-host.*/.test(item)) {
						if (i[lparname]) {
							server = i[lparname];
						} else if (i.pool) {
							server = i.pool;
						} else if (i.storage) {
							server = i.storage;
						}
					}
				} else if (i.platform == "Nutanix") {
					if (/^nutanix-host.*/.test(item)) {
						if (i[lparname]) {
							server = i[lparname];
						} else if (i.pool) {
							server = i.pool;
						} else if (i.storage) {
							server = i.storage;
						}
					}
				} else {
					if (i.type == "host_nic") {
						lparname = "nic";
						server = i.host;
					} else if (i.type == "cluster_aggr") {
						lparname = "cluster";
					} else if (i.type == "storage_domains_total_aggr") {
						i.parent = "oVirt";
						lparname = "nope";
					}
				}
				params = {
					"platform": i.platform,
					"parent": i.parent,
					"type": i.type,
					"host": i.platform,
					"server": server,
					"lpar": i[lparname],
					"item": item,
					"time": time,
				};
				if (!params.lpar) {
					params.lpar = i.host ? i.host : "nope";
				}
			}
		} else {
			var lpar = i.lpar;
			if (src == "n") {
				lpar += "--NMON--";
			}
			if (src == "w") {
				lpar = lpar.replace("/", "--WPAR--");
			}
			if (item == "lparagg") {
				lpar = "pool-multi";
			}
			if (i.parent && lpar != "nope") {
				i.hmc = i.parent;
			}
			if (item.match("^dstrag_")) {
				i.hmc = "nope";
				i.srv = "nope";
				lpar = "nope";
			}
			params = {
				"host": i.hmc,
				"server": i.srv,
				"lpar": lpar,
				"item": item,
				"time": time,
				"type_sam": sam,
				"parent": i.parent
			};
		}
	}
	return params;
}

function urlQstring(p, det, ent) {
	var qstring = [];
	qstring.push({
		name: "host",
		value: p.host
	});
	qstring.push({
		name: "server",
		value: p.server
	});
	qstring.push({
		name: "lpar",
		value: p.lpar
	});
	qstring.push({
		name: "item",
		value: p.item
	});
	qstring.push({
		name: "time",
		value: p.time
	});
	qstring.push({
		name: "type_sam",
		value: p.type_sam
	});
	qstring.push({
		name: "detail",
		value: det
	});
	qstring.push({
		name: "entitle",
		value: ent
	});
	return "/lpar2rrd-cgi/detail-graph.sh?" + $.param(qstring, true);
}


function loadImages(selector) {
	$(selector).each(function( index, element) {
		if (! $(element).data("revert_url")) {
			$(element).data("revert_url", $(element).data("src"));
			var urlparams = getParams($(element).data("src"));
			if (urlparams.sunix) {
				$(element).data("revert_timefrom", urlparams.sunix * 1000);
				$(element).data("revert_timeto", urlparams.eunix * 1000);
			}
			$(element).attr("data-src", $(element).data("src") + "&none=" + Date.now());
		}
		if (! $(element).attr("data-loader")) {
			$(element).attr("data-loader", "lazyLoader");
		}
	});
	$(selector).lazy({
		bind: 'event',
		/*        delay: 0, */
		effect: 'fadeIn',
		effectTime: 400,
		threshold: 100,
		visibleOnly: true,
		appendScroll: $("div#econtent"),
		lazyLoader: function(element, response) {
			getImageData(element, response);
			element.parents("td").css("vertical-align", "middle");
			element.parents("td").css("text-align", "center");
			$(element).addClass('load');
		},
		afterLoad: function(element) {
			$(element).removeClass('load');
			$(element).parents("td.relpos").css("vertical-align", "top");
			$(element).parents("td.relpos").css("text-align", "left");
				$(element).parents("td.relpos").find("div.favs").show();
			$(element).parents("td.relpos").find("div.dash").show();
			// $(element).parents("td.relpos").find("div.popdetail").show();
			if (curNode.data.hwtype == "power") {
				$("div.refresh").show();
			}
		}
	});
}

function getImageTitle(dataSrc){
	var title = "<span class='tt_subsys'>" + dataSrc.type;
	if (dataSrc.item == 'sum') {
		dataSrc.item = dataSrc.name;
	}
	var itemTitle = "";
	try {
		itemTitle = urlItems[dataSrc.item][0];
	} catch (exception) {
		window.console && console.log("Unknown URL item type: " + dataSrc.item);
		itemTitle = "<span style='color:red;font-weight:bold'>" + dataSrc.item + "</span>";
	}
	if (dataSrc.item == "sum") {
		title += " aggregated</span> <span class='tt_item'>" + itemTitle + "</span>:";
	} else {
		title += "</span> <span class='tt_item'>" + itemTitle + "</span>:";
	}
	return title;
}

function getImagePeriod(dataSrc){
	var period;
	switch (dataSrc.time) {
		case 'd':
			period = "last day";
		break;
		case 'w':
			period = "last week";
		break;
		case 'm':
			period = "last 4 weeks";
		break;
		case 'y':
			period = "last year";
		break;
	}
	return " <span class='tt_range'>" + period + "</span>";
}

function getImageData(element, response) {
	var dataSrc = getParams(element.attr("data-src"));
	var hashstr = $(element).attr("alt");
	var zoomTitle;
	if (dataSrc.detail == 8 || dataSrc.detail == 9) {
		var title = getImageTitle(dataSrc);
		$(element).data("title", title);
		var period = getImagePeriod(dataSrc);
		$(element).data("period", period);
		var alink = $(element).parents("a.detail");
		// $(alink).parent().find("span.tt_span").html(title + period).attr("title", $(title + period).text());
	}
	if ( $(element).hasClass("nolegend") ) {
		jQuery.ajax({
			url: $(element).attr("data-src"),
			success: function(data, textStatus, jqXHR) {
				var error = jqXHR.getResponseHeader('X-XoruX-Error');
				if (error) {
					$(element).parents("a.detail").replaceWith( "<div class='error_placeholder' alt='" + hashstr + "'>" + Base64.decode(error) + "</div><div class='dash' title='Remove this item from DashBoard'></div>" );
				} else {
					var header = jqXHR.getResponseHeader('X-RRDGraph-Properties');
					if (header) {
						if (sysInfo.guidebug == 1) {
							$(element).parent().attr("title", header);
						}
						var h = splitWithTail(header, ":", 6);
						var frame = $(element).siblings("div.zoom");
						if (frame.length) {
							$(frame).imgAreaSelect({
								remove: true
							});
							if (dataSrc.detail == 9) {
								var title = Base64.decode(h[6]);
								zoomTitle = title;
								if (h[2] > 600 && !$(element).parents().hasClass("regrp")) {
									zoomTitle = "<b>" + $.format.date(h[4] * 1000, 'H:mm') + "</b> " + $.format.date(h[4] * 1000, 'd-MMM-yyyy') +
									" &xrarr; " + "<b>" + $.format.date(h[5] * 1000, 'H:mm') + "</b> " + $.format.date(h[5] * 1000, 'd-MMM-yyyy');
									zoomTitle = title + "&nbsp;&nbsp;&nbsp;" + zoomTitle;
									if (!$(element).data("histrep_title")) {
										$(element).data("histrep_title", zoomTitle);
									}
								}
								var alink = $(element).parents("a.detail");
								$(alink).parent().find("span").html(zoomTitle).attr("title", title);
								$(element).data("title", title);
							}
							$(frame).data("graph_start", h[4]);
							$(frame).data("graph_end", h[5]);
							$(frame).data("title", h[6]);
							$(frame).css("left", h[0] + "px");
							$(frame).css("top", h[1] + "px");
							$(frame).css("width", h[2] + "px");
							$(frame).css("height", h[3] + "px");
							if (h[2] && h[3]) {
								betterZoom($(frame).attr("id"), h[2], h[3]);
							}
							frame.show();
							// console.log(h);
						}
					}
					element.attr("src", data.img);
					if (data.table) {
						legendTable(element, data.table);
					}
				response(true);
				}
				// loadImages(curImg);
			}
		});
	} else {
		var jqXHR = new XMLHttpRequest();
		jqXHR.open("GET", $(element).attr("data-src"), true);
		jqXHR.responseType = "arraybuffer";

		jqXHR.onreadystatechange = function(oEvent) {
			if (this.readyState == 4 && this.status == 200) {
				var error = jqXHR.getResponseHeader('X-XoruX-Error');
				if (error) {
					if ($(element).parents("a.detail").length) {
						$(element).parents("a.detail").replaceWith( "<div class='error_placeholder' alt='" + hashstr + "'>" + Base64.decode(error) + "</div><div class='dash' title='Remove this item from DashBoard'></div>" );
					} else {
						$(element).replaceWith( "<div class='error_placeholder'>" + Base64.decode(error) + "</div><div class='dash' title='Remove this item from DashBoard'></div>" );
					}
				} else {
					var arrayBuffer = jqXHR.response; // Note: not oReq.responseText
					if (arrayBuffer) {
						var byteArray = new Uint8Array(arrayBuffer);
						$(element).attr("src", "data:image/png;base64," + btoa(String.fromCharCode.apply(null, new Uint8Array(byteArray))));
					var header = jqXHR.getResponseHeader('X-RRDGraph-Properties');
					if (header) {
						if (sysInfo.guidebug == 1) {
							$(element).parent().attr("title", header);
						}
						var h = splitWithTail(header, ":", 6);
						var frame = $(element).siblings("div.zoom");
						if (frame.length) {
							$(frame).imgAreaSelect({
								remove: true
							});
							if (dataSrc.detail == 9) {
								var title = Base64.decode(h[6]);
								var zoomTitle = title;
								if (h[2] > 600 && !$(element).parents().hasClass("regrp")) {
									zoomTitle = "<b>" + $.format.date(h[4] * 1000, 'H:mm') + "</b> " + $.format.date(h[4] * 1000, 'd-MMM-yyyy') +
									" &xrarr; " + "<b>" + $.format.date(h[5] * 1000, 'H:mm') + "</b> " + $.format.date(h[5] * 1000, 'd-MMM-yyyy');
									zoomTitle = title + "&nbsp;&nbsp;&nbsp;" + zoomTitle;
									if (!$(element).data("histrep_title")) {
										$(element).data("histrep_title", zoomTitle);
									}
								}
								var alink = $(element).parents("a.detail");
								$(alink).parent().find("span").html(zoomTitle).attr("title", title);
								$(element).data("title", title);
							}
							$(frame).data("graph_start", h[4]);
							$(frame).data("graph_end", h[5]);
							$(frame).data("title", h[6]);
							$(frame).css("left", h[0] + "px");
							$(frame).css("top", h[1] + "px");
							$(frame).css("width", h[2] + "px");
							$(frame).css("height", h[3] + "px");
							if (h[2] && h[3]) {
								betterZoom($(frame).attr("id"), h[2], h[3]);
							}
							frame.show();
							// console.log(h);
						}
					}
				}
			}
				response(true);
			}
		};
		jqXHR.send(null);
	}
}

function setTitle(menuitem) {
	if (sysInfo.demo && menuitem && menuitem.title == "DASHBOARD") {
		$("#title").html("DASHBOARD - demo site doesn't save changes (<a href='https://www.lpar2rrd.com/dashboard.php' style='color: unset' target='_blank'>more info...</a>)").show();
		return;
	}
	var activeNode = $('#side-menu').fancytree('getActiveNode');
	if (! activeNode) {
		return;
	}
	var item = '';
	var path = '';
	var parents = menuitem.getParentList(false, true);
	var delimiter = '<span class="delimiter">&nbsp;&nbsp;|&nbsp;&nbsp;</span>';

	$.each(parents, function(key, part) {
		item = part.title;
		if (item.indexOf("LPAR2RRD <span") >= 0) {
			item = "LPAR2RRD";
		}
		if (jQuery.inArray(item, ['LPAR', 'Totals', "IBM Power", "HMC", "ESXi", "VM", "VMware", "non vCenter"]) == -1) {
			if (path === '') {
				path = item;
			} else {
				path += delimiter + item;
			}
		}
	});

	$('#title').html(path);
	if (curNode.data && curNode.data.hwtype) {
		if (curNode.data.hwtype == "power") {
			if (curNode.getLevel() >= 3) {
				var eSrv, eLpar;
				if (curNode.getLevel() == 3) { // server level
					eSrv  = curNode.data.srv;
					eLpar = curNode.data.altname || curNode.title;
					if (eLpar == "pool") {
						eLpar = "";
					}
				} else {
					eSrv  = curNode.data.srv;
					eLpar = curNode.data.noalias || curNode.title;
				}
				var eLink = location.origin + location.pathname + "?" + $.param({ server: eSrv, lpar: eLpar, tab: curTab || 0}, true);
				$('#title').append("<a href='" + eLink + "'><span class='extlink' title='Direct link'></span></a>");
			}
		}
	}
	$('#title').show();

	/*
	if ($( "#cgtree" ).length) {
		// $( "#title" ).append("&nbsp;&nbsp;<span id='cgcfg-help-button' style='cursor: pointer'><img src='css/images/help-browser.gif' alt='Help' title='Help'></span>");
		$( "#title" ).append("<div id='hiw'><a href='http://www.lpar2rrd.com/custom_groups.html' target='_blank'><img src='css/images/help-browser.gif' alt='Custom groups' title='Custom groups'></a></div>");
		$( "#cgcfg-help-button").on("click", function(event) {
//			event.stopPropagation;
//			event.preventDefault;
			$("#cgcfg-help").load("https://lpar2rrd.com/custom_groups.php");
			$("#cgcfg-help").dialog("open");
		});

	}
	*/
}

function hrefHandler() {
	$('#content a:not(.ui-tabs-anchor, .detail, .userlink, .replink, .grplink)').off().on("click", function(ev) {
		var url = $(this).attr('href');
		if ((url.substring(0, 7) != "http://") && (url.substring(0, 8) != "https://") && (!/\.csv$/.test(url)) && (!/lpar-list-rep\.sh/.test(url)) && ($(this).text() != "CSV") && (url.substring(0, 7) != "mailto:")) {
			backLink(url, ev);
			return false;
		}
	});
}

function backLink(pURL, event) {
	var splitted, server, pool, lpar;
	if (pURL == "#") {
		return false;
	}
	if (event && $(event.target).parent().hasClass("regroup")) {
		event.preventDefault();
		if ($(event.target).parent().hasClass("fwd")) {
			var newContent = $("<div id='tabs'>");
			var tabs = "<div id='tabs'> \
			<ul>\
			<li class='tabfrontend'><a href='#tabs-0'>daily</a></li>\
			<li class='tabfrontend'><a href='#tabs-1'>weekly</a></li>\
			<li class='tabfrontend'><a href='#tabs-2'>monthly</a></li>\
			<li class='tabfrontend'><a href='#tabs-3'>yearly</a></li>\
			</ul> \
			</div>";

			newContent.append(tabs);
			newContent.append("<div class='regroup bck'><a href='' alt='Back' title='Back'></a></div>");
			var i;
			for (i = 0; i < 4; i++) {
				var tabDiv = "<div id='tabs-" + i + "'><center> \
				<table align='center' class='regrp'> \
				</table> \
				</div>";
				newContent.find("#tabs").append(tabDiv);
				$(".ui-tabs-tab").each(function( index ) {
					var tabPanel = "#" + $(this).attr('aria-controls');
					var td = $(tabPanel).find(".relpos:eq( " + i + " )");
					if (td) {
						var tdc = td.clone();
						var img = tdc.find("img.lazy");
						var src = img.data("src") ? img.data("src") : img.attr("src");
						if (src) {
							var sunix;
							var eunix = Math.round(new Date().getTime() / 1000);
							switch (i) {
								case 0 :
									sunix = eunix - 60 * 60 * 24;
									break;
								case 1 :
									sunix = eunix - 60 * 60 * 24 * 7;
									break;
								case 2 :
									sunix = eunix - 60 * 60 * 24 * 31;
									break;
								case 3 :
									sunix = eunix - 60 * 60 * 24 * 365;
									break;
							}
							src += "&height=150&width=900";
							img.attr("data-src", src);
							var revurl = src;
							// revurl = revurl.replace(/&none=.*/g, '');
							img.attr("data-revert_url", revurl);
							img.attr("src", "css/images/sloading.gif");
						}
						var tabRow = $("<tr>");
						tabRow.append(tdc);
						newContent.find("#tabs-" + i).find("table.regrp").append(tabRow);
					}
				});
			}
			$("#content").off().html(newContent);
			myreadyFunc();
			// hrefHandler();
		} else {
			$( "#side-menu" ).fancytree( "getTree" ).reactivate();
		}
		return false;
	}
	if (event && $(event.target).parent().hasClass("csvfloat")) {
		location.href = pURL;
		return false;
	}
	if (event && $(event.target).parent().hasClass("pdffloat")) {
		window.open(pURL, "_blank");
		return false;
	}
	if (pURL.indexOf("?") >= 0) {
		var params = getParams(pURL, true),
		itemType = params.item,
		host = params.host,
		platform = params.platform,
		menuHash = params.menu;
		if (params.tab) {
			forceTab = params.tab;
		}
		$tree = $("#side-menu").fancytree("getTree");
		if (platform && platform != "VMware" && platform != "Linux") {
			if (platform == "hyperv") {
				var rootnode = $tree.getRootNode();
				var hvtree;
				rootnode.visit(function(node) {
					if (node.title == "Windows / Hyper-V") {
						hvtree = node;
						return false;
					}
				});
				if (hvtree) {
					if (params.item == "host") {
						hvtree.visit(function(node) {
							if (node.data.srv == params.name) {
								node.setExpanded(true);
								node.setActive();
								return false;
							}
						});
					} else if (params.item == "vm" || params.item == "volume") {
						var parent = params.cluster ? params.cluster : params.host;
						hvtree.visit(function(node) {
							if (node.title == params.name && parent == node.data.srv) {
								node.setExpanded(true);
								node.setActive();
								return false;
							}
						});
					}
				}
			} else {
				$tree.visit(function(node) {
					if (node.data.href == pURL) {
						node.setExpanded(true);
						node.setActive();
						return false;
					}
				});
			}
		} else if (itemType) {
			if (itemType == "lpar" || itemType == "vmw-cpu" || itemType == "vmw-diskrw" || itemType == "vmw-netrw" || itemType == "vmw-iops") {
				server = params.server,
				lpar = params.lpar;
				$tree.visit(function(node) {
					if (node.data.noalias == lpar) {
						if (node.data.obj == "VM") {
							var parents = node.getParentList();
							$.each(parents, function( index, value ) {
								if (value.data.altname && value.data.altname == host) {
									node.setExpanded(true);
									if (node.isActive()) {
										$tree.reactivate();
									} else {
										node.setActive();
									}
									return false;
								}
							});
							return false;
						}
						var par1 = node.getParent(); // skip LPARs level
						if (par1.title == "Removed") { // skip one more level if Removed
							par1 = par1.getParent();
						}
						if (node.data.obj != "U") {
							par1 = par1.getParent();
						}
						var isOnEsxi = par1.findFirst("ESXi") ? par1.findFirst("ESXi").findFirst(server) : false;
						if (par1.title == "SERVER" && par1.getLevel() == 1) {
							par1 = node.getParent();
						}
						if (par1.title == server || par1.data.altname == server || isOnEsxi) {
							if (itemType == "vmw-cpu") {
								lastTabName = "CPU";
							} else if (itemType == "vmw-diskrw") {
								lastTabName = "DISK";
							} else if (itemType == "vmw-netrw") {
								lastTabName = "LAN";
							} else if (itemType == "vmw-iops") {
								lastTabName = "IOPS";
							}
							node.setExpanded(true);
							if (node.isActive()) {
								$tree.reactivate();
							} else {
								node.setActive();
							}
							return false;
						}
					}
				});
				return false;
			} else if (itemType == "pool" || itemType == "shpool") {
				server = params.server,
				pool = params.lpar;
				$tree.visit(function(node) {
					if (node.data.altname == pool) {
						var par1 = node.getParent();
						if (itemType == "shpool") {
							par1 = par1.getParent();
						}
						if (par1.title == server || par1.data.altname == server) {
							node.setExpanded(true);
							node.setActive();
							return false;
						}
					}
				});
			} else if (itemType == "cluster") {
				server = params.server,
				pool = "Cluster totals";
				$tree.visit(function(node) {
					if (node.title == pool) {
						var par1 = node.getParent();
						if (par1.data.altname == host) {
							node.setExpanded(true);
							node.setActive();
							return false;
						}
					}
				});
			} else if (itemType == "vtop10") {
				host = params.vcenter;
				$tree.visit(function(node) {
					if (node.title == "Totals" && node.parent.title == host) {
						node.setExpanded(true);
						node.setActive();
						return false;
					}
				});
			} else if (itemType == "vm_cluster_totals") {
				host = "cluster_" + params.cluster;
				$tree.visit(function(node) {
					if (node.title == "Totals" && node.data.parent && node.data.parent == host) {
						node.setExpanded(true);
						node.setActive();
						return false;
					}
				});
			} else if (itemType == "oscpu" && host == "no_hmc") {
				lpar = params.lpar;
				$tree.visit(function(node) {
					if (node.title == lpar) {
						node.setExpanded(true);
						node.setActive();
						return false;
					}
				});
			} else if (itemType == "datastore") {
				host = params.host,
				lpar = params.lpar;
				$tree.visit(function(node) {
					// if (node.data.altname == host && node.getLevel() == 3) {
					if (node.data.altname == host) {
						node = node.findFirst(lpar);
						if (node) {
							node.setExpanded(true);
							node.setActive();
							return false;
						}
					}
				});
			} else if (/^power_.*/.test(itemType)) {
				$tree.visit(function(node) {
					if (node.data.altname == params.lpar) {
						if (node.data.srv == params.server) {
							node.setExpanded(true);
							node.setActive();
							return false;
						}
					}
				});
			}
		} else if (params.source) {
			var link = $(event.target).parents("td").find("a");
			var cls = "." + link.attr("class");
			if (cls) {
				var srvname = link.parents("tr").find("td").first().text();
				var idx = link.parents("td").index();
				var title = link.parents("table").find("th").eq(idx).text();
				var dwidth = (cls == ".server_interface") ? "950" : "650";
				$.get(pURL, function(data) {
					var html = $.parseHTML( data );
					var div = "<div id='srvdetail'>" + $(html).find(cls).html() + "</div>";
					$( div ).dialog({
						height: 750,
						width: dwidth,
						modal: true,
						title: srvname + " - " + title,
						buttons: {
							Close: function() {
								$(this).dialog("close");
							}
						},
						create: function() {
							tableSorter($('#srvdetail table.tablesorter, #srvdetail table.tabcfgsum'));
							$('#srvdetail a').off().on("click", function(ev) {
								ev.preventDefault();
								var url = $(this).attr('href');
								backLink(url, ev);
								$('#srvdetail').dialog("close");
								return false;
							});
						},
						close: function() {
							$(this).dialog("destroy");
						}
					});
				});
			}
		} else if (pURL.indexOf("lpar2rrd-realt.sh") >= 0) {
			$('#content').load(pURL, function() {
				imgPaths();
				myreadyFunc();
			});
		} else if (pURL.indexOf("print-config.sh") >= 0) {
			splitted = pURL.split("#");
			if (splitted[1]) {
				jumpTo = splitted[1];
			} else {
				jumpTo = "";
			}
			$('#content').load(pURL, function() {
				if (jumpTo) {
					jumpTo = decodeURI(jumpTo);
					location.hash = jumpTo;
				}
				imgPaths();
				myreadyFunc();
			});
		} else if (menuHash) {
			urlTab = getUrlParameters("tab", pURL, true);
			if (urlTab == 0) {
				lastTabName = "Run time";
			} else if (urlTab == 1) {
				lastTabName = "Error";
			} else if (urlTab == 3) {
				lastTabName = "Apache error";
			}
			$tree = $("#side-menu").fancytree("getTree");
			$tree.visit(function(node) {
				if (node.data.hash == menuHash) {
					browserNavButton = true;
					node.setExpanded(true);
					node.setActive();
					return false;
				}
			});
		} else {
			location.href = pURL;
		}
	} else if (pURL.indexOf("gui-cpu.html") >= 0) {
		splitted = pURL.split("/");
		server = splitted[1];
		$tree = $("#side-menu").fancytree("getTree");
		$tree.visit(function(node) {
			if (node.title == "Totally for all CPU pools" || node.title == "CPU pool") {
				var par1 = node.getParent(); // skip LPARs level
				if (par1.title == server) {
					node.setExpanded(true);
					node.setActive();
					return false;
				}
			}
		});
	} else {
		splitted = pURL.split("#");
		if (splitted[1]) {
			jumpTo = splitted[1];
		} else {
			jumpTo = "";
		}

		$('#content').load(pURL, function() {
			if (jumpTo) {
				jumpTo = decodeURI(jumpTo);
				location.hash = jumpTo;
			}
			imgPaths();
			myreadyFunc();
		});
	}
}


function getUrlParameters(parameter, url, decode) {
	var parArr = url.split("?")[1].split("&"),
		returnBool = true;

	for (var i = 0; i < parArr.length; i++) {
		parr = parArr[i].split("=");
		if (parr[0] == parameter) {
			// return (decode) ? decodeURIComponent(parr[1].replace(/\+/g, " ")) : parr[1];
			return (decode) ? decodeURIComponent(parr[1]) : parr[1];
		} else {
			returnBool = false;
		}
	}
	if (!returnBool) {
		return false;
	}
}

function areCookiesEnabled() {
	var cookieEnabled = (navigator.cookieEnabled) ? true : false;

	if (typeof navigator.cookieEnabled == "undefined" && !cookieEnabled) {
		document.cookie = "testcookie";
		cookieEnabled = (document.cookie.indexOf("testcookie") != -1) ? true : false;
	}
	return (cookieEnabled);
}

function copyToClipboard(text) {
	window.prompt("GUI DEBUG: Please copy following content to the clipboard (Ctrl+C), then paste it to the bugreport (Ctrl-V)", text);
}

/*
function showHideSwitch() {
	var dataSources = "hmc";
	if ($("ul.ui-tabs-nav").has("li.tabagent").length) {
		dataSources = "agent";
	}
	if ($("ul.ui-tabs-nav").has("li.tabnmon").length) {
		if (dataSources == "agent") {
			dataSources = "all"; // both OS agent and NMON data present
		} else {
			dataSources = "nmon"; // just NMON data present
		}
	}
	if (dataSources == "all") {
		var activeTab = $('#tabs li.ui-tabs-active.tabagent,#tabs li.ui-tabs-active.tabnmon').text();
		if (activeTab) {
			$("#nmonsw").show();
		} else {
			$("#nmonsw").hide();
		}
	} else {
		$("#nmonsw").hide();
	}
	if (dataSources == "all") {
		if ($("#nmr1").is(":checked")) {
			dataSources = "agent";
		} else {
			dataSources = "nmon";
		}
	}
	agentNmonToggle(dataSources);
}
*/

function showHideCfgSwitch() {
	var activeTab = $('#tabs li.ui-tabs-active.hmcsum, #tabs li.ui-tabs-active.hmcdet').text();
	if (activeTab) {
		$("#confsw").show();
	} else {
		$("#confsw").hide();
	}
	if (($("#cfg1").is(':checked'))) {
		$("ul.ui-tabs-nav li.hmcdet").css("display", "none");
		$("ul.ui-tabs-nav li.hmcsum").css("display", "inline-block");
	} else if (($("#cfg2").is(':checked'))) {
		$("ul.ui-tabs-nav li.hmcsum").css("display", "none");
		$("ul.ui-tabs-nav li.hmcdet").css("display", "inline-block");
	}

}

//*************** Toggle agent/nmon data
/*
function agentNmonToggle(src) {
	if (src == "agent") {
		$("ul.ui-tabs-nav li.tabnmon").css("display", "none");
		$("ul.ui-tabs-nav li.tabagent").css("display", "inline-block");
		$("#fsa").show();
		$("#fsn").hide();
	} else if (src == "nmon") {
		$("ul.ui-tabs-nav li.tabnmon").css("display", "inline-block");
		$("ul.ui-tabs-nav li.tabagent").css("display", "none");
		$("#fsn").show();
		$("#fsa").hide();
	}
}
*/

function histRepQueryString() {
	// get HMC & server name from active menu
	if (curNode) {
		var queryArr = [{
			name: 'jsontype',
			value: 'histrep'
		}, {
			name: 'hmc',
			value: curNode.data.hmc
		}, {
			name: 'managedname',
			value: curNode.data.srv
		}, {
			name: 'type',
			value: curNode.data.hwtype
		}, {
			name: 'hostname',
			value: curNode.data.parent
		}];
		if (/mode=solo_esxi/i.test(curNode.data.href)) {
			queryArr[4].value = queryArr[1].value;
			queryArr[1].value = "solo_esxi";
		}
		return $.param(queryArr).replace( /\+/g, '%20' );
	}
}

function getCurrentVcenter () {
	// get vCenter name from menu url
	if ($("#vmhistrepsrc").val()) {
		return $("#vmhistrepsrc").val();
	}
	else if (inXormon) {
		return xormonVars.vc;
	}
	else if ($("#side-menu").fancytree('getActiveNode')) {
		var node = $("#side-menu").fancytree('getActiveNode');
		return node.parent.data.altname;
	}
}

function sections() {
	// return;
	if (sysInfo.demo == "10") {
		var allSources = $("ul.ui-tabs-nav").has("li.tabnmon", "li.tabagent").length;
		if ($("li.tabhmc").length > 0) {
			$("#fsh").width(function() {
				var sectWidth = 0;
				$("li.tabhmc").each(function() {
					sectWidth += $(this).outerWidth() + 1;
				});
				return sectWidth - 1;
			});
			$("#fsh").show();
		} else {
			$("#fsh").hide();
		}

		if ($("li.tabagent").length > 0) {
			$("#fsa").width(function() {
				var sectWidth = 0;
				$("li.tabagent").each(function() {
					sectWidth += $(this).outerWidth() + 1;
				});
				return sectWidth - 1;
			});
			if (allSources === 0) {
				$("#fsa").show();
			} else if ($("#nmr1").is(':checked')) {
				$("#fsa").show();
			} else {
				$("#fsa").hide();
			}
		} else {
			$("#fsa").hide();
		}

		if ($("li.tabnmon").length > 0) {
			$("#fsn").width(function() {
				var sectWidth = 0;
				$("li.tabnmon").each(function() {
					sectWidth += $(this).outerWidth() + 1;
				});
				return sectWidth - 1;
			});
			if (allSources === 0) {
				$("#fsn").show();
			} else if ($("#nmr2").is(':checked')) {
				$("#fsn").show();
			} else {
				$("#fsn").hide();
			}
		} else {
			$("#fsn").hide();
		}
	} else {
		$("#subheader fieldset").hide();
	}
}

function tableSorter(tabletosort) {
	var sortList = {};
	$(tabletosort).find("th").each(function(i, header) {
		if (!$(header).hasClass('sortable')) {
			sortList[i] = {
				"sorter": false
			};
		} else if ( $(header).text().match( /^av.?g|^max/i ) ) {
			sortList[i] = {
				"sorter": "digit"
			};
		}
	});
	sortArray = [];
	if ($(tabletosort).data("sortby")) {
		var sortcols = $(tabletosort).data("sortby").toString();
		var arr = sortcols.split(" ");
		$.each(arr, function( index, value ) {
			if (value < 0) {
				sortArray.push([Math.abs(value) - 1, -1]);
			} else {
				sortArray.push([value - 1, 1]);
			}

		});
	}
	$(tabletosort).tablesorter({
		sortInitialOrder: 'desc',
		widgets : [ "filter" ],
		sortList: sortArray,
		stringTo: 'bottom',
		"headers": sortList,
		theme: "ice",
		textExtraction : function(node, table, cellIndex) {
			n = $(node);
			return n.attr('data-sortValue') || n.attr('data-text') || n.text();
		},
		widgetOptions : {
			// filter_anyMatch options was removed in v2.15; it has been replaced by the filter_external option

			// If there are child rows in the table (rows with class name from "cssChildRow" option)
			// and this option is true and a match is found anywhere in the child row, then it will make that row
			// visible; default is false
			filter_childRows : false,

			// if true, filter child row content by column; filter_childRows must also be true
			filter_childByColumn : false,

			// if true, include matching child row siblings
			filter_childWithSibs : true,

			// if true, a filter will be added to the top of each table column;
			// disabled by using -> headers: { 1: { filter: false } } OR add class="filter-false"
			// if you set this to false, make sure you perform a search using the second method below
			filter_columnFilters : true,

			// if true, allows using "#:{query}" in AnyMatch searches (column:query; added v2.20.0)
			filter_columnAnyMatch: true,

			// extra css class name (string or array) added to the filter element (input or select)
			filter_cellFilter : '',

			// extra css class name(s) applied to the table row containing the filters & the inputs within that row
			// this option can either be a string (class applied to all filters) or an array (class applied to indexed filter)
			filter_cssFilter : '', // or []

			// add a default column filter type "~{query}" to make fuzzy searches default;
			// "{q1} AND {q2}" to make all searches use a logical AND.
			filter_defaultFilter : {},

			// filters to exclude, per column
			filter_excludeFilter : {},

			// jQuery selector (or object) pointing to an input to be used to match the contents of any column
			// please refer to the filter-any-match demo for limitations - new in v2.15
			filter_external : '',

			// class added to filtered rows (rows that are not showing); needed by pager plugin
			filter_filteredRow : 'filtered',

			// add custom filter elements to the filter row
			// see the filter formatter demos for more specifics
			filter_formatter : null,

			// add custom filter functions using this option
			// see the filter widget custom demo for more specifics on how to use this option
			filter_functions : null,

			// hide filter row when table is empty
			filter_hideEmpty : true,

			// if true, filters are collapsed initially, but can be revealed by hovering over the grey bar immediately
			// below the header row. Additionally, tabbing through the document will open the filter row when an input gets focus
			filter_hideFilters : true,

			// Set this option to false to make the searches case sensitive
			filter_ignoreCase : true,

			// if true, search column content while the user types (with a delay)
			filter_liveSearch : true,

			// a header with a select dropdown & this class name will only show available (visible) options within that drop down.
			filter_onlyAvail : 'filter-onlyAvail',

			// default placeholder text (overridden by any header "data-placeholder" setting)
			filter_placeholder : { search : '', select : '' },

			// jQuery selector string of an element used to reset the filters
			filter_reset : 'button.reset',

			// Reset filter input when the user presses escape - normalized across browsers
			filter_resetOnEsc : true,

			// Use the $.tablesorter.storage utility to save the most recent filters (default setting is false)
			filter_saveFilters : false,

			// Delay in milliseconds before the filter widget starts searching; This option prevents searching for
			// every character while typing and should make searching large tables faster.
			filter_searchDelay : 300,

			// allow searching through already filtered rows in special circumstances; will speed up searching in large tables if true
			filter_searchFiltered: true,

			// include a function to return an array of values to be added to the column filter select
			filter_selectSource  : null,

			// if true, server-side filtering should be performed because client-side filtering will be disabled, but
			// the ui and events will still be used.
			filter_serversideFiltering : false,

			// Set this option to true to use the filter to find text from the start of the column
			// So typing in "a" will find "albert" but not "frank", both have a's; default is false
			filter_startsWith : false,

			// Filter using parsed content for ALL columns
			// be careful on using this on date columns as the date is parsed and stored as time in seconds
			filter_useParsedData : false,

			// data attribute in the header cell that contains the default filter value
			filter_defaultAttrib : 'data-value',

			// filter_selectSource array text left of the separator is added to the option value, right into the option text
			filter_selectSourceSeparator : '|'
		}
	});
}

function queryStringToHash(query) {
	var query_string = {};
	var vars = query.split("&");
	for (var i = 0; i < vars.length; i++) {
		var pair = vars[i].split("=");
		pair[0] = decodeURIComponent(pair[0]);
		pair[1] = decodeURIComponent(pair[1]);
		// If first entry with this name
		if (typeof query_string[pair[0]] === "undefined") {
			query_string[pair[0]] = pair[1];
			// If second entry with this name
		} else if (typeof query_string[pair[0]] === "string") {
			var arr = [query_string[pair[0]], pair[1]];
			query_string[pair[0]] = arr;
			// If third or later entry with this name
		} else {
			query_string[pair[0]].push(pair[1]);
		}
	}
	return query_string;
}

/*
* Returns a map of querystring parameters
*
* Keys of type <fieldName>[] will automatically be added to an array
*
* @param String url
* @return Object parameters
*/
function getParams(url, decode) {
	var regex = /([^=&?]+)=([^&#]*)/g,
		params = {},
		parts, key, value;

	while ((parts = regex.exec(url)) != null) {

		key = parts[1];
		value = parts[2];
		if (decode) {
			value = decodeURIComponent(value);
		}
		var isArray = /\[\]$/.test(key);

		if (isArray) {
			params[key] = params[key] || [];
			params[key].push(value);
		} else {
			params[key] = value;
		}
	}

	return params;
}

function ShowDate(ts, short) {
	var then = "never";
	if (ts) {
		ts = new Date(ts);
		var pad = function pad(n) {
			return n<10 ? '0'+n : n;
		};
		then = pad(ts.getFullYear()) + '-' + pad((ts.getMonth() + 1)) + '-' + pad(ts.getDate());
		if ( short ) {
			var days = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"];
			then = days[ts.getDay()] + ", " + then;
		} else {
		then += ' ' + pad(ts.getHours()) + ':' + pad(ts.getMinutes());
	}
	}
	return (then);
}

function TimeStamp() {
	ts = new Date($.now());
	function pad(n) {
		return n<10 ? '0'+n : n;
	}
	var then = pad(ts.getUTCFullYear()) + '-' + pad((ts.getUTCMonth() + 1)) + '-' + pad(ts.getUTCDate());
	then += 'T' + pad(ts.getUTCHours()) + ':' + pad(ts.getUTCMinutes()) + ':' + pad(ts.getUTCSeconds()) + "Z";
	return (then);
}

function betterZoom(zoomID, width, height) {
	$("#" + zoomID).imgAreaSelect({
		handles: false,
		maxHeight: height,
		minHeight: height,
		maxWidth: width,
		parent: "#content",
		// parent: $("#" + zoomID).parent(),
		fadeSpeed: 500,
		autoHide: true,
		onSelectEnd: function(img, selection) {
			selectEnd(img, selection, null, function() {
				if ($(img).parents().hasClass("regrp")) {
					var instance = $(img).parents(".regrp").find('.lazy').data("plugin_lazy");
					instance.destroy();
					$(img).parents(".regrp").find(".zoom").each(function(i, zoom) {
						if (zoom.id != img.id) {
							var deferredObject = $.Deferred();
							selectEnd(zoom, selection, img, function() {
								deferredObject.resolve();
							});
							// return deferredObject.promise();
						}
					});
				}
			});
		}
	});
}

function selectEnd(img, selection, sync, callback) {
	if (selection.width) {
		$(img).addClass("wait");
		var imgEl = $(img).parent().children("img"),
			selFrom, selTo;
		if (sync) {
			selFrom = new Date($(sync).data().graph_start * 1000);
			selTo = new Date($(sync).data().graph_end * 1000);
		} else {
			var from = new Date($(img).data().graph_start * 1000);
			var to = new Date($(img).data().graph_end * 1000);
			var timePerPixel = (to - from) / $(img).width();
			selFrom = new Date(+from + selection.x1 * timePerPixel);
			selTo = new Date(+selFrom + selection.width * timePerPixel);
		}
		// console.log("From: " + from + " To: " + to);
		var zoomTitle = "<b>" + $.format.date(selFrom, 'H:mm') + "</b> " + $.format.date(selFrom, 'd-MMM-yyyy') +
		" &xrarr; " + "<b>" + $.format.date(selTo, 'H:mm') + "</b> " + $.format.date(selTo, 'd-MMM-yyyy'); // + "&nbsp;&nbsp;&nbsp; Název půjde z headeru";
		if (imgEl.width() > 600 || imgEl.parents().hasClass("regrp")) {
			if (imgEl.data("title")) {
				zoomTitle = imgEl.data("title") + "&nbsp;&nbsp;" + zoomTitle;
			}
		}
		var alink = $(img).parents("a.detail");
		$(alink).parent().find("span.tt_span").html(zoomTitle);
		var ahref = ($(imgEl).data("revert_url")) ? $(imgEl).data("revert_url") : $(imgEl).data("src") ? $(imgEl).data("src") : $(imgEl).attr("src");
		if (! $(alink).parent().find("div.popdetail").length) {
			$("<div class='popdetail'></div>").insertBefore( $(alink) );
		}
		$(alink).parent().find("div.popdetail").off().show().on("click", function() {
			resZoom(this);
		});
		if (!$(alink).data("basehref")) {
			$(alink).data("basehref", $(alink).attr("href"));
		}
		var nonePos = ahref.indexOf('?');
		var params = getParams(ahref, 1);
		var paramsDetail = getParams($(alink).data("basehref"), 1);

		delete params.none;
		delete paramsDetail.none;
		var zUrl = ahref.slice(0, nonePos);
		params.sunix = parseInt(selFrom.getTime() / 1000);
		params.eunix = parseInt(selTo.getTime() / 1000);
		paramsDetail.sunix = params.sunix;
		paramsDetail.eunix = params.eunix;
		var zoomedUrl = zUrl + "?" + jQuery.param(params).replace(/\+/g, "%20");
		var zoomedUrlDetail = zUrl + "?" + jQuery.param(paramsDetail).replace(/\+/g, "%20");
		var dt = 'binary';
		$(alink).attr("href", zoomedUrlDetail);
		if ($(imgEl).hasClass('nolegend')) {
			dt = 'json';
		}
		jQuery.ajax({
			// url: $(element).attr("data-src") + "&nonelazy=" + new Date().getTime(),
			url: zoomedUrl,
			cache: true,
			dataType: dt,
			// responseType: 'blob',
			processData: false,
			//   complete: function (jqXHR, textStatus) {
			success: function(data, textStatus, jqXHR) {
				// console.log("Title: " + zoomedUrl);
				// console.log(imgEl);
				header = jqXHR.getResponseHeader('X-RRDGraph-Properties');
				if (header) {
					if (sysInfo.guidebug == 1) {
						$(element).parent().attr("title", header);
					}
					$(img).removeClass("wait");
					//var image = new Image();
					//image.src = URL.createObjectURL(data);

					if ($(imgEl).hasClass('nolegend')) {
						$(imgEl).attr("src", data.img);
						legendTable(imgEl, data.table);
					} else {
						$(imgEl).attr("src", URL.createObjectURL(data));
					}
					var h = header.split(":");
					$(img).imgAreaSelect({
						remove: true
					});
					if (imgEl.width() > 600 || imgEl.parents().hasClass("regrp")) {
						if (!imgEl.data("title")) {
							var title = Base64.decode(h[6]);
							zoomTitle = title + "&nbsp;&nbsp;" + zoomTitle;
							$(img).parents("a.detail").parent().find("span.tt_span").html(zoomTitle);
						}
					}
					$(img).data("graph_start", h[4]);
					$(img).data("graph_end", h[5]);
					$(img).css("left", h[0] + "px");
					$(img).css("top", h[1] + "px");
					$(img).css("width", h[2] + "px");
					$(img).css("height", h[3] + "px");
					if (h[2] && h[3]) {
						betterZoom($(img).attr("id"), h[2], h[3]);
					}
					if (callback) {
						callback();
					}
					// frame.show();
					// console.log(h);
				}
			}
		});
		// $(storedObj).trigger("click");
	}
}

function resZoom(resButton) {
	if ($(resButton).parents().hasClass("regrp")) {
		$(resButton).parents(".regrp").find("div.popdetail").each(function() {
			resetZoom(this);
		});
	} else {
		resetZoom(resButton);
	}
}

function resetZoom(resButton) {
	var alink = $(resButton).parents().siblings("a.detail");
	var imgEl = $(alink).parent().find("img");
	var frame = $(alink).find("div.zoom");
	$(frame).addClass("wait");
	var title = $(imgEl).data("title");
	var period = $(imgEl).data("period");

	$(alink).parent().find("span.tt_span").html(title);
	if ($(imgEl).data("revert_timefrom")) {
		var timerange = "<b>" + $.format.date($(imgEl).data("revert_timefrom"), 'H:mm') + "</b> " + $.format.date($(imgEl).data("revert_timefrom"), 'd-MMM-yyyy') +
		" &xrarr; " + "<b>" + $.format.date($(imgEl).data("revert_timeto"), 'H:mm') + "</b> " + $.format.date($(imgEl).data("revert_timeto"), 'd-MMM-yyyy');
		$(alink).parent().find("span.tt_span").html(title + timerange);
	}

	if ($(alink).data("basehref")) {
		$(alink).attr("href", $(alink).data("basehref"));
		$(alink).parents(".relpos").find("div.popdetail").hide();
	}
	var dt = 'binary';
	if ($(imgEl).hasClass('nolegend')) {
		dt = 'json';
	}
	jQuery.ajax({
		// url: $(element).attr("data-src") + "&nonelazy=" + new Date().getTime(),
		url: $(imgEl).data("revert_url"),
		dataType: dt,
		cache: true,
		// responseType: 'blob',
		processData: false,
		//   complete: function (jqXHR, textStatus) {
		success: function(data, textStatus, jqXHR) {
			$(frame).removeClass("wait");
			var header = jqXHR.getResponseHeader('X-RRDGraph-Properties');
			if (header) {
				if (sysInfo.guidebug == 1) {
					$(element).parent().attr("title", header);
				}

				if ($(imgEl).hasClass('nolegend')) {
					$(imgEl).attr("src", data.img);
					legendTable(imgEl, data.table);
				} else {
					$(imgEl).attr("src", URL.createObjectURL(data));
				}
				var h = header.split(":");
				$(frame).imgAreaSelect({
					remove: true
				});
				$(imgEl).data("graph_start", h[4]);
				$(imgEl).data("graph_end", h[5]);
				$(frame).data("graph_start", h[4]);
				$(frame).data("graph_end", h[5]);
				$(frame).css("left", h[0] + "px");
				$(frame).css("top", h[1] + "px");
				$(frame).css("width", h[2] + "px");
				$(frame).css("height", h[3] + "px");
				if (h[2] && h[3]) {
					betterZoom(frame.attr("id"), h[2], h[3]);
				}
				frame.show();
				// console.log(h);
			}
		}
	});
}

/* placeholder for input fields */
function placeholder() {
	$("input[type=text]").each(function() {
		var phvalue = $(this).attr("placeholder");
		$(this).val(phvalue);
	});
}

function CheckExtension(file) {
	/*global document: false */
	var validFilesTypes = ["nmon", "csv"];
	var filePath = file.value;
	var ext = filePath.substring(filePath.lastIndexOf('.') + 1).toLowerCase();
	var isValidFile = false;

	for (var i = 0; i < validFilesTypes.length; i++) {
		if (ext == validFilesTypes[i]) {
			isValidFile = true;
			break;
		}
	}

	if (!isValidFile) {
		file.value = null;
		alert("Invalid File. Valid extensions are:\n\n" + validFilesTypes.join(", "));
	}

	return isValidFile;
}

function getUrlParameter(sParam) {
	var sPageURL = window.location.search.substring(1);
	var sURLVariables = sPageURL.split('&');
	for (var i = 0; i < sURLVariables.length; i++) {
		var sParameterName = sURLVariables[i].split('=');
		if (sParameterName[0] == sParam) {
			return sParameterName[1];
		}
	}
}

function saveData (id) {
	if (!sessionStorage) {
		return;
	}
	var data = {
		id: id,
		scroll: $("#content").scrollTop(),
		title: $("#title").html(),
		html: $("#content").html()
	};
	sessionStorage.setItem(id,JSON.stringify(data));
}

function restoreData(id) {
	if (!sessionStorage) {
		return;
	}
	var data = sessionStorage.getItem(id);
	if (!data) {
		return null;
	}
	return JSON.parse(data);
}

function detectIE() {
	var ua = window.navigator.userAgent;
	var msie = ua.indexOf('MSIE ');
	var trident = ua.indexOf('Trident/');
	var edge = ua.indexOf('Edge');

	if (msie > 0) {
		// IE 10 or older => return version number
		return parseInt(ua.substring(msie + 5, ua.indexOf('.', msie)), 10);
	}

	if (trident > 0) {
		// IE 11 (or newer) => return version number
		var rv = ua.indexOf('rv:');
		return parseInt(ua.substring(rv + 3, ua.indexOf('.', rv)), 10);
	}
	if (edge > 0) {
		return true;
	}

	// other browser
	return false;
}

// Create Base64 Object
var Base64={_keyStr:"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=",encode:function(e){var t="";var n,r,i,s,o,u,a;var f=0;e=Base64._utf8_encode(e);while(f<e.length){n=e.charCodeAt(f++);r=e.charCodeAt(f++);i=e.charCodeAt(f++);s=n>>2;o=(n&3)<<4|r>>4;u=(r&15)<<2|i>>6;a=i&63;if(isNaN(r)){u=a=64;}else if(isNaN(i)){a=64;}t=t+this._keyStr.charAt(s)+this._keyStr.charAt(o)+this._keyStr.charAt(u)+this._keyStr.charAt(a);}return t;},decode:function(e){var t="";var n,r,i;var s,o,u,a;var f=0;e=e.replace(/[^A-Za-z0-9\+\/\=]/g,"");while(f<e.length){s=this._keyStr.indexOf(e.charAt(f++));o=this._keyStr.indexOf(e.charAt(f++));u=this._keyStr.indexOf(e.charAt(f++));a=this._keyStr.indexOf(e.charAt(f++));n=s<<2|o>>4;r=(o&15)<<4|u>>2;i=(u&3)<<6|a;t=t+String.fromCharCode(n);if(u!=64){t=t+String.fromCharCode(r);}if(a!=64){t=t+String.fromCharCode(i);}}t=Base64._utf8_decode(t);return t;},_utf8_encode:function(e){e=e.replace(/\r\n/g,"\n");var t="";for(var n=0;n<e.length;n++){var r=e.charCodeAt(n);if(r<128){t+=String.fromCharCode(r);}else if(r>127&&r<2048){t+=String.fromCharCode(r>>6|192);t+=String.fromCharCode(r&63|128);}else{t+=String.fromCharCode(r>>12|224);t+=String.fromCharCode(r>>6&63|128);t+=String.fromCharCode(r&63|128);}}return t;},_utf8_decode:function(e){var t="";var n=0;var r=c1=c2=0;while(n<e.length){r=e.charCodeAt(n);if(r<128){t+=String.fromCharCode(r);n++;}else if(r>191&&r<224){c2=e.charCodeAt(n+1);t+=String.fromCharCode((r&31)<<6|c2&63);n+=2;}else{c2=e.charCodeAt(n+1);c3=e.charCodeAt(n+2);t+=String.fromCharCode((r&15)<<12|(c2&63)<<6|c3&63);n+=3;}}return t;}};

var converterEngine = function (input) { // fn BLOB => Binary => Base64 ?
	var uInt8Array = new Uint8Array(input),
	i = uInt8Array.length;
	var biStr = []; //new Array(i);
	while (i--) { biStr[i] = String.fromCharCode(uInt8Array[i]);  }
	var base64 = window.btoa(biStr.join(''));
	return base64;
};

function arrayBufferToString(buffer) {
	var bufView = new Uint16Array(buffer);
	var length = bufView.length;
	var result = '';
	var addition = Math.pow(2,16)-1;

	for (var i = 0;i<length;i+=addition) {
		if (i + addition > length) {
			addition = length - i;
		}
		result += String.fromCharCode.apply(null, bufView.subarray(i,i+addition));
	}

	return result;

}

function groupTable($rows, startIndex, total) {
	if (total === 0) {
		return;
	}
	var i , currentIndex = startIndex, count=1, lst=[];
	var tds = $rows.find('td:eq('+ currentIndex +')');
	var ctrl = $(tds[0]);
	lst.push($rows[0]);
	for (i=1;i<=tds.length;i++) {
		if (ctrl.text() ==  $(tds[i]).text()) {
			count++;
			$(tds[i]).addClass('deleted');
			lst.push($rows[i]);
		} else {
			if (count>1) {
				ctrl.attr('rowspan',count);
				groupTable($(lst),startIndex+1,total-1);
			}
			count=1;
			lst = [];
			ctrl=$(tds[i]);
			lst.push($rows[i]);
		}
	}
}

function redrawTable($rows, startIndex, total) {
	if (total === 0) {
		return;
	}
	var i , currentIndex = startIndex, count=1, lst=[];
	for (col=startIndex; col<=(startIndex + total); col++) {
		var tds = $rows.find('td:eq('+ col +')');
		var ctrl = $(tds[0]);
		for (i=1; i<=tds.length; i++) {
			if (ctrl.text() ==  $(tds[i]).text()) {
				count++;
				$(tds[i]).addClass('invisible');
			} else {
				count=1;
				ctrl=$(tds[i]);
			}
		}
	}
}

function unique(array) {
	return $.grep(array, function(el, index) {
		return index === $.inArray(el, array);
	});
}

function checkLength( o, n, min, max ) {
	if ( o.val().length > max || o.val().length < min ) {
		o.addClass( "ui-state-error" );
		updateTips( "Length of " + n + " must be between " +
		min + " and " + max + "." );
		return false;
	} else {
		return true;
	}
}

function checkRegexp( o, regexp, n ) {
	if ( !( regexp.test( o.val() ) ) ) {
		o.addClass( "ui-state-error" );
		updateTips( n );
		return false;
	} else {
		return true;
	}
}

function updateTips( t ) {
	tips = $( ".validateTips" );
	tips
		.text( t )
		.addClass( "ui-state-highlight" );
	setTimeout(function() {
		tips.removeClass( "ui-state-highlight", 1500 );
	}, 500 );
}

function checkStatus(platform_array) {
	var rootNode = $("#side-menu").fancytree("getTree").getRootNode();
	if ($("img.redpoint").length) {
		$("img.redpoint").remove();
	}
	$.each(platform_array, function(idx, platform) {
		$.getJSON(cgiPath + "/health-status.sh?cmd=isok&platform=" + platform, function(data) {
			if (data.status == "NOK") {
				var hsnode;
				var platformRoot;
				var redPoint = '<img src="css/images/wrench-red-icon.png" class="redpoint" style="margin-left: 8px; height: 13px;" title="Problem detected on some device...">';
				$.each(rootNode.getChildren(), function(idx, node) {
					if (node.title == platform) {
						platformRoot = node;
						platformRoot.visit(function(subnode) {
							if (subnode.title == "Health Status") {
								hsnode = subnode;
								return false;
							}
						});
					}
				});
				if (platform == "Nutanix") {
					if (hsnode && data.bad_central) {
						$(hsnode.span).append(redPoint);
					}
					$.each(data.bad_clusters, function(ix, cluster) {
						if (platformRoot) {
							$.each(platformRoot.getChildren(), function(idx, platformChild) {
								if (platformChild.title == cluster) {
									platformChild.visit(function(clusterChild) {
										if (clusterChild.title == "Health Status") {
											$(clusterChild.span).append(redPoint);
										}
									});
								}
							});
						}
					});

				} else {
					if (hsnode) {
						$(hsnode.span).append(redPoint);
					}
				// var redPoint = '<span id="redpoint" class="fa fa-wrench" style="padding-left: 6px; padding-top: 1px; color: #f77; margin-left: 2px; font-size: 14px;" title="Problem detected on some device...">';
				}
			}
		});
	});
}

var credFormDiv = '<div id="cred-dialog-form"> \
<p class="validateTips">All form fields are required.</p> \
<form autocomplete="off"> \
	<fieldset> \
	<label for="alias">Alias</label> \
	<input type="text" name="alias" id="alias" class="text ui-widget-content ui-corner-all"> \
	<label for="host">Hostname/IP</label> \
	<input type="text" name="host" id="host" class="text ui-widget-content ui-corner-all"> \
	<label for="user">User name (read-only role)</label> \
	<input type="text" name="user" id="user" class="text ui-widget-content ui-corner-all"> \
	<label for="password">Password</label> \
	<input type="password" name="password" id="password" class="text ui-widget-content ui-corner-all"> \
	<!-- Allow form submission with keyboard without duplicating the dialog button --> \
	<input type="submit" tabindex="-1" style="position:absolute; top:-1000px"> \
	</fieldset> \
</form> \
</div>';

function vmCredForm (title, oParams) {
	$( credFormDiv ).dialog({
		height: 450,
		width: 550,
		modal: true,
		title: title,
		buttons: {
			"Save credentials": addCred,
			Cancel: function() {
				$(this).dialog("close");
			}
		},
		create: function() {
			credForm = $(this).find( "form" ).on( "submit", function( event ) {
				event.preventDefault();
				addCred();
			});
			if (oParams) {
				$( "#alias" ).val(oParams.alias);
				$( "#host" ).val(oParams.server);
				$( "#user" ).val(oParams.username);
			}
		},
		close: function() {
			$(this).find( "form" ).trigger('reset');
			var alias = $( "#alias" ),
			host = $( "#host" ),
			user = $( "#user" ),
			password = $( "#password" ),
			allFields = $( [] ).add( alias ).add( host ).add( user );
			allFields.removeClass( "ui-state-error" );
			$(this).dialog("destroy");
		}
	});
}

function addCred() {
	var valid = true,
	alias = $( "#alias" ),
	host = $( "#host" ),
	user = $( "#user" ),
	password = $( "#password" ),
	allFields = $( [] ).add( alias ).add( host ).add( user );
	allFields.removeClass( "ui-state-error" );
	valid = valid && checkLength( alias, "alias", 1, 64 );
	valid = valid && checkLength( host, "hostname", 2, 80 );
	valid = valid && checkLength( user, "username", 2, 64 );
	valid = valid && checkLength( password, "password", 2, 64 );

	valid = valid && checkRegexp( alias, /^[0-9a-z_\-]+$/i, "Alias may consist of a-z, 0-9, dashes and underscores." );
	valid = valid && checkRegexp( user, /^[0-9a-z_\-\.\\@]+$/i, "Username may consist of a-z, 0-9, underscores, dots, dashes, backslash and @." );
	valid = valid && checkRegexp( host, /^[0-9a-z_\-\.:]+$/, "Host name may consist of a-z, 0-9, underscores, dots, dashes and colon." );
	// valid = valid && checkRegexp( password, /^([0-9a-z])+$/i, "Password field only allow: a-z 0-9" );

	if ( valid ) {
		var params = { cmd: "add", alias: alias.val(), server: host.val(), username: user.val(), password: password.val() };
		$.post("/lpar2rrd-cgi/vmwcfg.sh", params, function(jsonData) {
			$( "#cred-dialog-form" ).dialog( "close" );
			$.alert(jsonData.message, "Credentials creation result", jsonData.success);
			valid = valid && jsonData.success;
			if (jsonData.success) {
				$( "#cred-dialog-form" ).dialog( "destroy" );
				$( "#side-menu" ).fancytree( "getTree" ).reactivate();
			}
		}, 'json');
	}
	return valid;
}

function genPdf(tpm) {
	var topost = {};
	var grcnt = 0;
	var hr = "p";
	if (curNode && curNode.data.href.match("mode=vcenter")) {
		hr = "v";
	}
	topost.sections = [];
	topost.graphs = [];
	var rnd = Math.random().toString(36).substring(7);
	$.each(tpm, function(index, value) {
		topost.sections.push(index + ":" + value.length);
		$.each(value, function(i, url) {
			url = url.replace("detail=9", "detail=7");
			topost.graphs.push(url);
			grcnt++;
		});
	});

	topost.title = "LPAR2RRD-report";
	if ( sysInfo.basename ) {
		topost.free = 1;
	}
	topost.id = rnd;
	topost.cmd= "gen";
	$.getJSON("/lpar2rrd-cgi/genpdf.sh?cmd=test", function( data ) {
		if (data.success) {
			var ttt = "<div id='progressDialog'><div id='pdfprogressbar'><div class='progress-label'>Please wait...</div></div><input type='button' value='Cancel' id='terminate' data-id='" + rnd + "'></div>";
			progressDialog = $( ttt ).dialog({
				dialogClass: "no-close",
				minWidth: 400,
				height: 136,
				modal: true,
				title: "PDF export - processing graphs...",
				show: {
					effect: "fadeIn",
					duration: 500
				},
				hide: {
					effect: "fadeOut",
					duration: 200
				},
				open: function( event, ui ) {
					$( "#pdfprogressbar" ).progressbar({
						"max": grcnt
					});
					$( "#terminate" ).on("click", function(e) {
						$.getJSON("/lpar2rrd-cgi/genpdf.sh?cmd=stop&id=" + this.dataset.id, function(data) {
							if(data.status=="terminated") {
							}
						});
					});
				}
			});
			$.ajax( {
				method: "POST" ,
				url: "/lpar2rrd-cgi/genpdf.sh",
				data: topost
			}).done( function( data ) {
			});
			setTimeout(function() {
				getPDFstatus(rnd);
			}, 100);
		} else {
			var info = "<p>Install the <a href='https://lpar2rrd.com/pdf-install.htm' target='_blank'>required pre-requisites</a>.</p>";
			info += "<p>Error message follows:</p>";
			$("<div></div>").dialog( {
				buttons: { "OK": function () { $(this).dialog("close"); } },
				close: function (event, ui) { $(this).remove(); },
				resizable: false,
				title: "PDF export failed",
				minWidth: 800,
				modal: true
			}).html(info + "<pre>" + data.log + "</pre>");
		}
	});
}

function getPDFstatus(id){
	$.getJSON("/lpar2rrd-cgi/genpdf.sh?cmd=status&id=" + id, function(data) {
		$('#statusmessage').html(data.message);
		if(data.status=="pending") {
			$( "#pdfprogressbar" ).progressbar( "value", data.done )
			.children(".progress-label").text(data.done + " of " + data.total);
			setTimeout(function() {
				getPDFstatus(id);
			}, 500);
		} else if (data.status=="done") {
			var path = "/lpar2rrd-cgi/genpdf.sh?cmd=get&id=" + id;
			if (inXormon) {
				path = xormonPrefix + path;
			}
			window.location = path;
			$( "#progressDialog" ).dialog( "destroy" );
		} else if (data.status=="terminated") {
			$( "#progressDialog" ).dialog( "destroy" );
		} else {
			setTimeout(function() {
				getPDFstatus(id);
			}, 500);
		}
	});
}

function genXls(tpm){
	var topost = {};
	var grcnt = 0;
	var hr = "p";
	if (curNode && curNode.data.href.match("mode=vcenter")) {
		hr = "v";
	}
	topost.sections = [];
	topost.graphs = [];
	var rnd = Math.random().toString(36).substring(7);
	$.each(tpm, function(index, value) {
		topost.sections.push(index + ":" + value.length);
		$.each(value, function(i, url) {
			topost.graphs.push(url);
			grcnt++;
		});
	});

	topost.title = "LPAR2RRD-report";
	var free = sysInfo.free;
	if (free == 0 || free == hr) {
		topost.free = 0;
	} else {
		topost.free = free;
	}
	topost.id = rnd;
	topost.cmd= "gen";
	$.getJSON("/lpar2rrd-cgi/genxls.sh?cmd=test", function( data ) {
		if (data.success) {
			var ttt = "<div id='progressDialog'><div id='pdfprogressbar'><div class='progress-label'>Please wait...</div></div><input type='button' value='Cancel' id='terminate' data-id='" + rnd + "'></div>";
			progressDialog = $( ttt ).dialog({
				dialogClass: "no-close",
				minWidth: 400,
				height: 136,
				modal: true,
				title: "XLS export - processing data...",
				show: {
					effect: "fadeIn",
					duration: 500
				},
				hide: {
					effect: "fadeOut",
					duration: 200
				},
				open: function( event, ui ) {
					$( "#pdfprogressbar" ).progressbar({
						"max": grcnt
					});
					$( "#terminate" ).on("click", function(e) {
						$.getJSON("/lpar2rrd-cgi/genxls.sh?cmd=stop&id=" + this.dataset.id, function(data) {
							if(data.status=="terminated") {
							}
						});
					});
				}
			});
			$.ajax( {
				method: "POST" ,
				url: "/lpar2rrd-cgi/genxls.sh",
				data: topost
			}).done( function( data ) {
			});
			setTimeout(function() {
				getXLSstatus(rnd);
			}, 100);
		} else {
			var info = "<p>Install the <a href='https://lpar2rrd.com/xls-install.htm' target='_blank'>required pre-requisites</a>.</p>";
			info += "<p>Error message follows:</p>";
			$("<div></div>").dialog( {
				buttons: { "OK": function () { $(this).dialog("close"); } },
				close: function (event, ui) { $(this).remove(); },
				resizable: false,
				title: "XLS export failed",
				minWidth: 800,
				modal: true
			}).html(info + "<pre>" + data.log + "</pre>");
		}
	});
}

function getXLSstatus(id){
	$.getJSON("/lpar2rrd-cgi/genxls.sh?cmd=status&id=" + id, function(data) {
		$('#statusmessage').html(data.message);
		if(data.status=="pending") {
			$( "#pdfprogressbar" ).progressbar( "value", data.done )
			.children(".progress-label").text(data.done + " of " + data.total);
			setTimeout(function() {
				getXLSstatus(id);
			}, 500);
		} else if (data.status=="done") {
			var path = "/lpar2rrd-cgi/genxls.sh?cmd=get&id=" + id;
			if (inXormon) {
				path = xormonPrefix + path;
			}
			window.location = path;
			$( "#progressDialog" ).dialog( "destroy" );
		} else if (data.status=="terminated") {
			$( "#progressDialog" ).dialog( "destroy" );
		} else {
			setTimeout(function() {
				getXLSstatus(id);
			}, 500);
		}
	});
}
function unescapeHtml(safe) {
	return $('<div>').html(safe).text();
}
var addNewAlertDiv = '<div id="alert-dialog-form"> \
<p class="validateTips">All form fields are required.</p> \
<form autocomplete="off"> \
	<fieldset> \
		<label for="level0" class="lev0">Platform</label> \
		<select class="alrtcol lev0" name="platform" id="level0"></select><br> \
		<label for="level1" class="lev1">Subsystem</label> \
		<select class="alrtcol lev1" name="subsys" id="level1" ></select><br> \
		<label for="level2" class="lev2" id="lablevel2">Server</label> \
		<select class="alrtcol lev2" name="storage" id="level2" ></select><br> \
		<label for="level3" class="lev3" id="lablevel3">LPAR</label> \
		<select class="alrtcol lev3" name="volume" id="level3" ></select> \
		<!-- Allow form submission with keyboard without duplicating the dialog button --> \
		<input type="submit" tabindex="-1" style="position:absolute; top:-1000px"> \
	</fieldset> \
</form> \
</div>';

function addNewAlrtForm (title, oParams) {
	$( addNewAlertDiv ).dialog({
		height: 360,
		width: 420,
		modal: true,
		title: title,
		buttons: {
			"Add new alerting rule": addNewAlert,
			Cancel: function() {
				$(this).dialog("close");
			}
		},
		create: function() {
			alertForm = $(this).find( "form" ).on( "submit", function( event ) {
				event.preventDefault();
				addNewAlert();
			});
			$("<option />", {text: "--- choose one ---" , value: ""}).appendTo($( "#level0"));
			if (sysInfo.hasPower) {
				$('<option value="P">IBM Power</option>').appendTo($( "#level0"));
			}
			if (sysInfo.hasVMware) {
				$('<option value="V">VMware (agent data only)</option>').appendTo($( "#level0"));
			}
			if (false && sysInfo.hasSolaris) { // disable for now
				$('<option value="S">Solaris</option>').appendTo($( "#level0"));
			}
			if (false && sysInfo.hasHyperV) {
				$('<option value="H">HyperV</option>').appendTo($( "#level0"));
			}
			if (sysInfo.hasLinux) {
				$('<option value="L">Linux</option>').appendTo($( "#level0"));
			}
			if (sysInfo.hasOracleDB) {
				$('<option value="Q">OracleDB</option>').appendTo($( "#level0"));
			}
			if (sysInfo.hasUnmanaged) {
				$('<option value="U">Unmanaged</option>').appendTo($( "#level0"));
			}

			if (false && oParams.subsys) {
				$( "#level1" ).val(oParams.subsys);
				$('#level2').prop('disabled', false);
				if (oParams.subsys == "LPAR") {
					$("<option />", {text: "IBM Power - all servers" , value: "IBM Power - all servers"}).appendTo($( "#level2"));
				} else {
					$("<option />", {text: "--- choose one ---" , value: ""}).appendTo($( "#level2"));
				}
				$.each(fleet, function(i, val) {
					if (val[oParams.subsys]) {
						$("<option />", {text: i , value: i}).appendTo($( "#level2"));
					}
				});
				if (oParams.storage) {
					$( "#level2" ).val(oParams.storage);
					$( "#level3" ).show();
					$( "#lablevel3" ).show();
					if (oParams.subsys == "LPAR") {
						$("<option />", {text: "--- ALL LPARS ---" , value: "--- ALL LPARS ---", selected: true}).appendTo($( "#level3"));
					} else {
						$("<option />", {text: "--- choose one ---" , value: "", selected: true}).appendTo($( "#level3"));
					}
					if ($("#level2").val() == "IBM Power - all servers") {
						$.each(fleet, function(key) {
							$.each(fleet[key][$("#level1").val()], function(i, val) {
								$("<option />", {text: val[0], value: val[0], hwtype: val[1], uuid: val[3]}).appendTo($( "#level3"));
							});
							$( "#level3").sort_select_box();
						});
					} else {
						$.each(fleet[$( "#level2" ).val()][$("#level1").val()], function(i, val) {
							$("<option />", {text: val[0], value: val[0], hwtype: val[1], uuid: val[3]}).appendTo($( "#level3"));
						});
						$( "#level3").sort_select_box();
					}
					if (oParams.volume) {
						$( "#level3" ).val(oParams.volume);
					}
					$('#level3').prop('disabled', false);
				}
			} else {
				$('#level1').prop('disabled', true);
				$('#level2').prop('disabled', true);
				$('#level3').prop('disabled', true);
				$( ".lev1" ).hide();
				$( ".lev2" ).hide();
				$( ".lev3" ).hide();
			}

			$( "#level0" ).change(function(event, data) {
				if (event.target.value) {
					// $( "#level1" ).empty();
					$( ".validateTips" ).text("All form fields are required.");
					$( "#lablevel2" ).text("Server");
					$( "#level1" ).prop("disabled", false);
					$( "#level1").empty();
					$( ".lev1" ).show();
					$( ".lev2" ).hide();
					$( ".lev3" ).hide();
					$( "#level1").empty();
					$( "#level2").empty();
					$( "#level3").empty();
					switch (event.target.value) {
						case "P":
							$("<option />", {text: "--- choose one ---" , value: ""}).appendTo($( "#level1"));
							$('<option value="LPAR">LPAR / WPAR</option>').appendTo($( "#level1"));
							$('<option value="POOL">POOL</option>').appendTo($( "#level1"));
						break;
						case "V":
							if (sysInfo.hasVMwareAgent) {
								$( "#lablevel2" ).text("Cluster");
								$('<option value="LPAR">VM</option>').appendTo($( "#level1"));
								$( "#level2" ).prop("disabled", false);
								$( ".lev2" ).show();
								$( "#level1" ).trigger( "change" );
							} else {
								$( ".lev1" ).hide();
								updateTips("No agent data from virtual machines!");
							}
						break;
						case "S":
							$("<option />", {text: "--- choose one ---" , value: ""}).appendTo($( "#level1"));
							$('<option value="LPAR">ZONE</option>').appendTo($( "#level1"));
							$('<option value="POOL">POOL</option>').appendTo($( "#level1"));
						break;
						case "U":
							$( "#lablevel2" ).text("Operating system");
							$('<option value="LPAR">Machine</option>').appendTo($( "#level1"));
							$( "#level2" ).prop("disabled", false);
							$( ".lev2" ).show();
							$( "#level1" ).trigger( "change" );
						break;
						case "L":
							$('<option value="LPAR">Machine</option>').appendTo($( "#level1"));
							$('<option value="Linux">Linux</option>').appendTo($( "#level2"));
							$( "#lablevel3" ).text("Server");
							$( "#level2" ).trigger( "change" );
							// $( ".lev3" ).hide();
						break;
						case "Q":
							$( ".lev1" ).text( "DB" );
							$("<option />", {text: "--- choose one ---" , value: "--- choose one ---"}).appendTo($( "#level1"));
							$.each(fleet, function(i, val) {
								var platform = fleet[i].platform;
								if ($('#level0').val() == platform) {
									$("<option />", {text: i , value: i}).appendTo($( "#level1"));
								}
							});
							$("<option />", {text: "OracleDB" , value: "OracleDB"}).appendTo($( "#level2"));
							$('<option />', {text: "OracleDB" , value: "DB",hwtype: "Q", selected: "selected"}).appendTo($( "#level3"));
							//$('#level3').attr('hwtype','session');
							//$('#level3').attr('selected','selected');
						break;
					}
				} else {
					$('#level1').prop('disabled', true);
					$('#level2').prop('disabled', true);
					$('#level3').prop('disabled', true);
					$( ".lev1" ).hide();
					$( ".lev2" ).hide();
					$( ".lev3" ).hide();
				}
			});

			$( "#level1" ).change(function(event, data) {
				if (event.target.value) {
					if ( $('#level0').val() != "Q" ){
						$( ".lev2" ).show();
						$( "#level2" ).prop("disabled", false);
						$( "#level2" ).empty();
						$( "#lablevel3" ).text(event.target.value);
					}else if ($('#level0').val() == "Q") {
						//$("<option />", {text: "IBM Power - all servers" , value: $('#level1').val()}).appendTo($( "#level3"));
					}

					if (event.target.value == "LPAR") {
						if ($('#level0').val() == "P") {
							$("<option />", {text: "IBM Power - all servers" , value: "IBM Power - all servers"}).appendTo($( "#level2"));
						}
						$( "#level3" ).empty();
						$("<option />", {text: "--- ALL LPARS ---" , value: "--- ALL LPARS ---", selected: true}).appendTo($( "#level3"));
						$.each(fleet, function(key) {
							var platform = fleet[key].platform;
							if ($('#level0').val() == platform && fleet[key].subsys.LPAR) {
								$.each(fleet[key].subsys.LPAR, function(i, val) {
									$("<option />", {text: val[0], value: val[0], hwtype: val[1], uuid: val[2], cluster: val[3]}).appendTo($( "#level3"));
								});
								$( "#level3").sort_select_box();
							}
						});
						$( ".lev3" ).show();
						$( "#level3" ).prop("disabled", false);
					} else {
						if ($('#level0').val() != "Q"){
							$("<option />", {text: "--- choose one ---" , value: ""}).appendTo($( "#level2"));
							$( "#level3").empty();
						}
					}
					$.each(fleet, function(i, val) {
						var platform = fleet[i].platform;
						if ($('#level0').val() == platform && val.subsys[event.target.value]) {
							$("<option />", {text: i , value: i}).appendTo($( "#level2"));
						}
						$( "#level2").sort_select_box();
					});
					if ($('#level0').val() != "Q"){
						$( "#level2" ).val("");
						$( "#level2" ).trigger( "change" );
					}
				} else {
					$('#level2').prop('disabled', true);
					$('#level3').prop('disabled', true);
					$( ".lev2" ).hide();
					$( ".lev3" ).hide();
				}
			});
			$( "#level2" ).change(function(event, data) {
				if (event.target.value) {
					var selPlatform = $('#level0').val();
					$( "#level3" ).prop("disabled", false);
					$( ".lev3" ).show();
					$( "#level3").empty();
					if ($("#level1").val() == "LPAR") {
						$("<option />", {text: "--- ALL LPARS ---" , value: "--- ALL LPARS ---", selected: true}).appendTo($( "#level3"));
					} else {
						$("<option />", {text: "--- choose one ---" , value: "", selected: true}).appendTo($( "#level3"));
						if ($("#level1").val() == "POOL") {
							$("<option />", {text: "Totals" , value: "POOL-TOTALS"}).appendTo($( "#level3"));
						}
					}
					if ($("#level1").val()) {
						if ($("#level2").val() == "IBM Power - all servers") {
							$.each(fleet, function(key) {
								if (key.platform == selPlatform && fleet[key].subsys[$("#level1").val()]) {
									$.each(fleet[key].subsys[$("#level1").val()], function(i, val) {
										$("<option />", {text: val[0], value: val[0], hwtype: val[1], uuid: val[2], cluster: val[3]}).appendTo($( "#level3"));
									});
								$( "#level3").sort_select_box();
								}
							});
						} else {
							$.each(fleet[$( "#level2" ).val()].subsys[$("#level1").val()], function(i, val) {
								$("<option />", {text: val[0], value: val[0], hwtype: val[1], uuid: val[2], cluster: val[3]}).appendTo($( "#level3"));
							});
							// $( "#level3").sort_select_box();
						}
					}
					$( "#level3" ).val("");
					$( "#level3" ).trigger( "change" );
				} else {
					$( "#level3" ).hide();
					$( "#varlabel" ).hide();
				}
			});
		},
		close: function() {
			$(this).find( "form" ).trigger('reset');
			var storage = $( "#storage" ),
			volume = $( "#volume" );
			allFields = $( [] ).add( storage ).add( volume );
			allFields.removeClass( "ui-state-error" );
			$(this).dialog("destroy");
		}
	});
}

function filterAlertTree() {
	if (xormonVars.user) {
		var $alrttree = $("#alrttree").fancytree("getTree");
		if ($alrttree.count() > 1) {
			$alrttree.filterNodes(function(node) {
				var i, child;
				if (node.getLevel()===1) {
					if (!node.children) {
						return false;
					}
					for (i=0; i<node.children.length; i++) {
						var sub = node.children[i];
						for (var j=0; j<sub.children.length; j++) {
							child = sub.children[j];
							if (!child.data.user || child.data.user===xormonVars.user) {
								return true;
							}
						}
					}
					return 'skip';
				} else if (node.getLevel()===2) {
					if (!node.children) {
						return false;
					}
					for (i=0; i<node.children.length; i++) {
						child = node.children[i];
						if (!child.data.user || child.data.user===xormonVars.user) {
							return true;
						}
					}
					return 'skip';
				} else if (node.getLevel()===3) {
					return !node.data.user || node.data.user===xormonVars.user;
				}
			});
		}
		$alrttree.setOption('clickFolderMode', 3);
	}
}

function addNewAlert(title, oParams) {
	var valid= true,
	platform = $( "#level0" ).val(),
	stor = $( "#level2" ).val(),
	subsys = $( "#level1" ).val(),
	vol = $( "#level3" ).val(),
	type = $("#level3").find('option:selected').attr("hwtype"),
	uuid = $("#level3").find('option:selected').attr("uuid"),
	cluster = $("#level3").find('option:selected').attr("cluster"),
	instance = "",
	fakeserver = "";

	if (! stor) {
		valid = false;
		updateTips("Server has to be selected!");
	} else if (! subsys) {
		valid = false;
		updateTips("Subsystem has to be selected!");
	} else if (! vol ) {
		valid = false;
		updateTips($( "#lablevel3" ).text() + " has to be selected!");
	}
	if (subsys == "POOL-ALL") {
		vol = "All pools";
	}
	if(platform == "OracleDB"){
		type = "Q";
	}
	if (vol == "--- ALL LPARS ---") {
		type = "L";
	}
	if (platform == "V") {
		if (type = "M") {
			fakeserver = "Linux";
		}
		else if ( $type = "S" ) {
			fakeserver = "Solaris";
		}
	}

	if (valid) {
		$( "#alert-dialog-form" ).dialog( "close" );
		var $tree = $("#alrttree").fancytree("getTree");
		var newStore = {
			"title": stor,
			"folder": true,
			"expanded": true
		};
		var newVolume = {
			"title": vol,
			"folder": true,
			"expanded": true,
			"subsys" : subsys
		};
		var child = {
			title: "",
			metric: "",
			limit: "",
			percent: "",
			peak: "",
			repeat: "",
			exclude: "",
			mailgrp: "",
			hwtype: type,
			instance: subsys,
			uuid: uuid,
			cluster: cluster,
			fakeserver: fakeserver,
			user: xormonVars.user
		};
		var rootNode = $tree.getRootNode();
		var storNode, volNode;
		// storNode = rootNode.findFirst(stor);
		$tree.visit(function(node) {
			if (node.getLevel() == 1 && node.title == stor) {
				storNode = node;
				return false;
			}
		});

		if (storNode) {
			storNode.visit(function(node) {
				if (node.getLevel() == 2) {
					if (node.title == vol) {
						if (node.data.subsys == subsys) {
							volNode = node;
							return false;
						}
					}
				}
			});
		} else {
			storNode = rootNode.addNode(newStore, "child");
		}
		// var volNode = storNode.findFirst(vol);
		if (! volNode) {
			volNode = storNode.addNode(newVolume, "child");
		}
		var newChild = volNode.addNode(child, "child");
		filterAlertTree();
		newChild.setActive();
	}
	return valid;
}

var addNewAgrpDiv = '<div id="algrp-dialog-form"> \
<p class="validateTips">All form fields are required.</p> \
<form> \
<fieldset> \
<label for="mailgrpinp">E-mail group</label> \
<input type="text" class="alrtcol" name="mailgrpinp" id="mailgrpinp" /><br> \
<label for="mailinp" style="margin-top: 4px">E-mail</label> \
<input type="text" class="alrtcol" name="mailinp" id="mailinp" style="margin-top: 4px" /> \
<!-- Allow form submission with keyboard without duplicating the dialog button --> \
<input type="submit" tabindex="-1" style="position:absolute; top:-1000px"> \
</fieldset> \
</form> \
</div>';

function addNewAgrpForm (title, oParams) {
	$( addNewAgrpDiv ).dialog({
		height: 280,
		width: 420,
		modal: true,
		title: title,
		buttons: {
			"Add new e-mail": addNewAlertMail,
			Cancel: function() {
				$(this).dialog("close");
			}
		},
		create: function() {
			alertForm = $(this).find( "form" ).on( "submit", function( event ) {
				event.preventDefault();
				addNewAlertMail();
			});
			if (oParams.storage) {
				$( "#mailgrpinp" ).val(oParams.storage);
			}
		},
		close: function() {
			$(this).find( "form" ).trigger('reset');
			var storage = $( "#mailgrpinp" ),
			volume = $( "#mailinp" );
			allFields = $( [] ).add( storage ).add( volume );
			allFields.removeClass( "ui-state-error" );
			$(this).dialog("destroy");
		}
	});
}

function addNewAlertMail(title, oParams) {
	var valid= true,
		mgrp = $( "#mailgrpinp" ),
		mgrpval = $( mgrp ).val(),
		mail = $( "#mailinp" ),
		mailval = $( mail ).val();

	valid = valid && checkLength( mgrp, "E-mail group", 1, 32 );
	valid = valid && checkLength( mail, "mail", 3, 80 );

	valid = valid && checkRegexp( mgrp, /^[0-9a-z_\-]+$/i, "E-mail group name may consist of a-z, 0-9, dashes and underscores." );
	valid = valid && checkRegexp( mail, emailRegex, "This doesn't look like valid e-mail address" );

	if (valid) {
		$( "#algrp-dialog-form" ).dialog( "close" );
		var $tree = $("#alrtgrptree").fancytree("getTree");
		var newGrp = {
			"title": mgrpval,
			"folder": true,
			"expanded": true
		};
		var rootNode = $tree.getRootNode(),
		grpNode = rootNode.findFirst(mgrpval);
		if (! grpNode) {
			grpNode = rootNode.addNode(newGrp, "child");
		}
		var mailNode = grpNode.findFirst(mailval);
		if (! mailNode) {
			mailNode = grpNode.addChildren({ title: mailval });
			mailNode.setActive();
			mailGroups = $tree.toDict();
			if (!inXormon) {
				$("#alrttree").fancytree("getTree").reload();
			}
		}
	}
	return valid;
}

function saveUser(user, pass) {
	var form = $("#user-dialog-form form");
	var valid= true;

	if (pass) {
		if ($("input.ui-state-error").length) {
			valid = false;
		}
	} else {
		var login = $( "#login" ),
		mail = $( "#mailinp" ),
		fullname = $( "#fullname" ),
		groupmem = $( "#groupmem" );

		valid = valid && checkLength( login, "login", 2, 40 );
		valid = valid && checkLength( mail, "mailinp", 3, 80 );
		valid = valid && checkLength( fullname, "fullname", 2, 80 );
		valid = valid && checkRegexp( mail, emailRegex, "This doesn't look like valid e-mail address" );
	}

	if (valid) {
		if (!user) {
			user = $( "#login" ).val();
			usercfg.users[user] = {};
			usercfg.users[user].name = $( "#fullname" ).val();
			usercfg.users[user].email = $( "#mailinp" ).val();
			usercfg.users[user].htpassword = htpasswd($("#pass1").val());
			usercfg.users[user].groups = $( "#groupmem" ).val();
			usercfg.users[user].created = TimeStamp();
			usercfg.users[user].active = true;
		} else {
			if (pass) {
				usercfg.users[user].htpassword = htpasswd($("#pass1").val());
			} else {
				usercfg.users[user].name = fullname.val();
				usercfg.users[user].email = mail.val();
				usercfg.users[user].groups = groupmem.val();
			}
			usercfg.users[user].changed = TimeStamp();
		}
		$( "#user-dialog-form" ).dialog( "close" );
		var postdata = {cmd: "saveuser", user: user, acl: JSON.stringify(usercfg.users[user], null, 2)};
		// usercfg = "";

		$.post( "/lpar2rrd-cgi/users.sh", postdata, function( data ) {
			var returned = JSON.parse(data);
			if ( returned.status == "success" ) {
				$('#adminmenu a[data-abbr="users"]').trigger( "click" );
				// $("#aclfile").text(returned.cfg).show();
			}
			$(returned.msg).dialog({
				dialogClass: "info",
				title: "User configuration save - " + returned.status,
				minWidth: 600,
				modal: true,
				show: {
					effect: "fadeIn",
					duration: 500
				},
				hide: {
					effect: "fadeOut",
					duration: 200
				},
				buttons: {
					OK: function() {
						$(this).dialog("close");
					}
				}
			});
		});
	}
}
function SaveUsrCfg (showResult) {
	if (! usercfg.options) {
		usercfg.options = {};
	}
	usercfg.options.acl_power_server_ignore = $("#acl_power_server_ignore").prop("checked");
	var postdata = {cmd: "saveall", acl: JSON.stringify(usercfg, null, 2)};
	$.post( "/lpar2rrd-cgi/users.sh", postdata, function( data ) {
		if (showResult) {
		var returned = JSON.parse(data);
		if ( returned.status == "success" ) {
			// $("#aclfile").text(returned.cfg).show();
		}
		$(returned.msg).dialog({
			dialogClass: "info",
			title: "Configuration saved - " + returned.status,
			minWidth: 600,
			modal: true,
			show: {
				effect: "fadeIn",
				duration: 500
			},
			hide: {
				effect: "fadeOut",
				duration: 200
			},
			buttons: {
				OK: function() {
					$(this).dialog("close");
				}
			}
		});
		}
	});
}

function SaveRepCfg (showResult, callback) {
	var o = repcfgusr.reports;
	var $repname = $("#repname");
	if ($repname.val() != $repname.data("oldvalue")) {
		o[$repname.val()] =  o[$repname.data("oldvalue")];
		delete o[$repname.data("oldvalue")];
	}
	var postdata = {cmd: "saveall", acl: JSON.stringify(repcfg, null, 2), user: userName};
	$.post( cgiPath + "/reporter.sh", postdata, function( data ) {
		var returned = JSON.parse(data);
		if (showResult || returned.status == "fail") {
			$(returned.msg).dialog({
				dialogClass: "info",
				title: "Configuration save - " + returned.status,
				minWidth: 600,
				modal: true,
				show: {
					effect: "fadeIn",
					duration: 500
				},
				hide: {
					effect: "fadeOut",
					duration: 200
				},
				buttons: {
					OK: function() {
						$(this).dialog("close");
					}
				}
			});
		}
		if (typeof callback === 'function') {
			callback();
		}
		if (inXormon) {
	  setTimeout(function() {
		myreadyFunc();
	  });
		}
	});
}

function userDetailForm (user) {
	var userFormDiv = '<div id="user-dialog-form"> \
	<form autocomplete="off"> \
	<fieldset> \
	<label for="login">Login</label> \
	<input type="text" name="login" id="login" title="User already exists!" /><br> \
	<label for="fullname">Full name</label> \
	<input name="fullname" id="fullname" /><br> \
	<label for="mailinp">E-mail</label> \
	<input type="text" class="alrtcol" name="mailinp" id="mailinp" title="This doesn\'t look like valid e-mail address"/><br> \
	<label for="groupmem">Group</label> \
	<select class="multisel" name="groupmem" id="groupmem" multiple></select><br> \
	</fieldset> \
	<!-- Allow form submission with keyboard without duplicating the dialog button --> \
	<input type="submit" tabindex="-1" style="position:absolute; top:-1000px"> \
	</form> \
	</div>';

	$( userFormDiv ).dialog({
		height: 440,
		width: 440,
		modal: true,
		title: "User details",
		buttons: {
			"Save user": {
				click: function() {
				saveUser(user);
			},
				text: "Save user",
				class: 'savecontrol'
			},
			Cancel: function() {
				$(this).dialog("close");
			}

		},
		create: function() {
			var isAdmin = false;
			if (usercfg.users[sysInfo.uid]) {
				isAdmin = $.inArray(aclAdminGroup, usercfg.users[sysInfo.uid].groups) > -1;
			}
			alertForm = $(this).find( "form" ).on( "submit", function( event ) {
				event.preventDefault();
				saveUser(user);
			});
			$.each(usercfg.groups, function(grp, val) {
				var isIn = (usercfg.users[user] !== undefined && ($.inArray(grp, usercfg.users[user].groups) >= 0));
				$("<option />", {text: grp, value: grp, selected: isIn}).appendTo($("#groupmem"));
			});
			if (user) {
				$("#login").val(user).prop('disabled', true);
				$("#fullname").val(usercfg.users[user].name);
				$("#mailinp").val(usercfg.users[user].email);
			} else {
				var passfields = '<br><fieldset><label for="pass1">Password</label> \
				<input type="password" name="pass1" id="pass1" title="Passwords don\'t match!" autocomplete="off" /><br> \
				<label for="pass2">Confirm</label> \
				<input type="password" name="pass2" id="pass2" title="Passwords don\'t match!" autocomplete="off" /></fieldset>';
				$(this).find("fieldset").after(passfields);
				$("#pass1, #pass2").tooltipster({
					trigger: 'custom',
					position: 'right',
				});

				$("#pass1,#pass2").on("blur", function( event ) {
					var pass1 = $("#pass1").val();
					var pass2 = $("#pass2").val();
					if (pass1 == "" || pass2 == "" || pass1 == pass2) {
						$(this).tooltipster("close");
						$(event.target).removeClass( "ui-state-error" );
						if (pass1 && (pass1 == pass2)) {
							$(".ui-dialog-buttonpane button:contains('password')").prop("disabled", false).css("cursor" , "pointer");
							$("button.savecontrol").button("enable");
						} else {
							$(".ui-dialog-buttonpane button:contains('password')").prop("disabled", 'disabled').css("cursor" , "auto");
							$("button.savecontrol").button("disable");
						}
					} else {
						$(this).tooltipster("open");
						$(event.target).trigger("focus");
						$(event.target).addClass( "ui-state-error" );
						$("button.savecontrol").button("disable");
					}
				});

				$("#pass1, #pass2").tooltipster({
					trigger: 'custom',
					position: 'right',
					//	theme: 'tooltipster-punk'
				});
			}
			$("#login").tooltipster({
				trigger: 'custom',
				position: 'right',
			});
			$('#login').keypress(function( e ) {
				if(!/[0-9a-zA-Z-:_\.]/.test(String.fromCharCode(e.which))) {
					return false;
				}
			});
			$("#login").on("blur", function( event ) {
				if ($("#login")) {
					if ((usercfg.users[$("#login").val()] !== undefined)) {
						$(this).tooltipster("open");
						$(event.target).addClass( "ui-state-error" );
						$("button.savecontrol").button("disable");
					} else {
						$(this).tooltipster("close");
						$(event.target).removeClass( "ui-state-error" );
						$("button.savecontrol").button("enable");
					}

				}
			});
			$("#mailinp").tooltipster({
				trigger: 'custom',
				position: 'right',
			});
			$("#mailinp").on("blur", function( event ) {
				if(event.relatedTarget && event.relatedTarget.textContent != "Cancel") {
					if (emailRegex.test( $("#mailinp").val())) {
						$(this).tooltipster("close");
						$(event.target).removeClass( "ui-state-error" );
					} else {
						$(this).tooltipster("open");
						$(event.target).trigger("focus");
						$(event.target).addClass( "ui-state-error" );
					}
				}
			});

			if (isAdmin) {
				$('select.multisel').multipleSelect();
			} else {
				$('select.multisel').multipleSelect("disable");
			}
		},
		close: function() {
			$(this).find( "form" ).trigger('reset');
			$("#oldpass, #pass1, #pass2").tooltipster("destroy");
			$(this).dialog("destroy");
		}
	});
}

function changePasswordForm (user, notMe) {
	var changePasswordFormDiv = '<div id="user-dialog-form"> \
	<form autocomplete="off"> \
	<fieldset>';
	if (!notMe) {
		changePasswordFormDiv += '<label for="oldpass">Old password</label> \
		<input type="password" name="oldpass" id="oldpass" title="Invalid password" autocomplete="off" /><br>';
	}
	changePasswordFormDiv += '<label for="pass1">New password</label> \
	<input type="password" name="pass1" id="pass1" title="Passwords don\'t match!" autocomplete="off" /><br> \
	<label for="pass2">Confirm</label> \
	<input type="password" name="pass2" id="pass2" title="Passwords don\'t match!" autocomplete="off" /> \
	</fieldset> \
	<!-- Allow form submission with keyboard without duplicating the dialog button --> \
	<input type="submit" tabindex="-1" style="position:absolute; top:-1000px"> \
	</form> \
	</div>';

	$( changePasswordFormDiv ).dialog({
		height: 250,
		width: 440,
		modal: true,
		title: "Change password",
		buttons: {
			"Save new password": function() {
				saveUser(user, true);
			},
			Cancel: function() {
				$(this).dialog("close");
			}
		},
		create: function() {
			$("#oldpass, #pass1, #pass2").tooltipster({
				trigger: 'custom',
				position: 'right',
			});
			alertForm = $(this).find( "form" ).on( "submit", function( event ) {
				event.preventDefault();
				saveUser(user, true);
			});
			if (!notMe) {
				// $("#pass1,#pass2").prop('disabled', 'disabled');
			}
			if (user) {
				$("#login").prop('disabled', true);
			}
			$(".ui-dialog-buttonpane button:contains('password')").prop("disabled", 'disabled').css("cursor" , "auto");
			$("#oldpass").on("blur", function( event ) {
				if(event.relatedTarget && event.relatedTarget.textContent != "Cancel"){
					var passTest = htpasswd(event.target.value, usercfg.users[user].htpassword);
					if (passTest != usercfg.users[user].htpassword) {
						event.preventDefault();
						event.stopPropagation();
						$("#oldpass").tooltipster("open");
						event.target.trigger("focus");
						$(event.target).addClass( "ui-state-error" );
						return false;
						// $("#pass1,#pass2").prop('disabled', 'disabled');
					} else {
						$("#oldpass").tooltipster('close');
						$(event.target).removeClass( "ui-state-error" );
						// $("#pass1,#pass2").prop('disabled', false);
						$("#pass1").trigger("focus");
					}
				}
			});
			$("#pass1,#pass2").on("blur", function( event ) {
				var pass1 = $("#pass1").val();
				var pass2 = $("#pass2").val();
				if (pass1 == "" || pass2 == "" || pass1 == pass2) {
					$(this).tooltipster("close");
					$(event.target).removeClass( "ui-state-error" );
					if (pass1 && (pass1 == pass2)) {
						$(".ui-dialog-buttonpane button:contains('password')").prop("disabled", false).css("cursor" , "pointer");
					} else {
						$(".ui-dialog-buttonpane button:contains('password')").prop("disabled", 'disabled').css("cursor" , "auto");
					}
				} else {
					$(this).tooltipster("open");
					event.target.trigger("focus");
					$(event.target).addClass( "ui-state-error" );
				}
			});
		},
		close: function() {
			$(this).find( "form" ).trigger('reset');
			$("#mailinp, #oldpass, #pass1, #pass2").tooltipster("destroy");
			$(this).dialog("destroy");
		}
	});
}

function newGroupForm (grpToEdit) {
	var newGroupFormDiv = '<div id="new-group-form"> \
	<form autocomplete="off"> \
	<fieldset> \
	<label for="grpname">Group name</label> \
	<input type="text" name="grpname" id="grpname" autocomplete="off" /><br> \
	<label for="descr">Description</label> \
	<input type="text" name="descr" id="descr" autocomplete="off" size="30" /> \
	</fieldset> \
	<!-- Allow form submission with keyboard without duplicating the dialog button --> \
	<input type="submit" tabindex="-1" style="position:absolute; top:-1000px"> \
	</form> \
	</div>';
	$( newGroupFormDiv ).dialog({
		height: 250,
		width: 440,
		modal: true,
		title: "Group details",
		buttons: {
			"Save groups": {
				click: function() {
					var grp = $("#grpname").val(),
					dsc = $("#descr").val();
					usercfg.groups[grp] = {description: dsc};
					SaveUsrCfg(true);
					$(this).dialog("close");
					$('#adminmenu a[data-abbr="users"]').trigger( "click" );
				},
				text: "Save groups",
				class: 'savecontrol'
			},
			Cancel: function() {
				$(this).dialog("close");
			}
		},
		create: function() {
			$("#grpname").tooltipster({
				trigger: 'custom',
				position: 'right',
			});
			alertForm = $(this).find( "form" ).on( "submit", function( event ) {
				event.preventDefault();
				saveUser(user, true);
			});
			$("#grpname").on("blur", function( event ) {
				if (!event.relatedTarget || event.relatedTarget && event.relatedTarget.textContent != "Cancel") {
					if (! this.value) {
						$("#grpname").tooltipster('content', 'Group name is required').tooltipster('open');
						$(event.target).addClass( "ui-state-error" );
						$(event.target).trigger("focus");
						$("button.savecontrol").button("disable");
					} else if (this.value != grpToEdit && usercfg.groups[this.value]) {
						$("#grpname").tooltipster('content', 'Group already exists!').tooltipster('open');
						$(event.target).addClass( "ui-state-error" );
						$(event.target).trigger("focus");
						$("button.savecontrol").button("disable");
					} else {
						$("#grpname").tooltipster("close");
						$(event.target).removeClass( "ui-state-error" );
						$("button.savecontrol").button("enable");
					}
				}
			});
			if (grpToEdit) {
				$("#grpname").val(grpToEdit);
				$("#descr").val(usercfg.groups[grpToEdit].description);
			} else {
				$("button.savecontrol").button("disable");
			}
		},
		open: function() {
			$('.ui-widget-overlay').addClass('custom-overlay');
		},
		close: function() {
			$(this).find( "form" ).trigger('reset');
			$("#grpname").tooltipster("destroy");
			$(this).dialog("destroy");
		}
	});
}

function repDetailForm (report) {
	var isNewRep = false,
	oldRepCfg = JSON.parse(JSON.stringify(repcfg));
	repFormDiv = '<div id="rep-dialog-form" class="repform"> \
	<form autocomplete="off"> \
	<fieldset> \
	<legend>Properties</legend> \
	<label class="rform" for="repname">Report name</label> \
	<input class="rform" type="text" name="repname" id="repname" style="width: 24em" title="Report already exists!" /> \
	<select class="multisel fr" name="format" id="format" style="width: 14em; float: right"> \
	<option value="IMG">Image (PNG)</option> \
	<option value="PDF">Portable document (PDF)</option> \
	<option value="CSV">Comma separated values (CSV)</option> \
	<!-- option value="XLS">Excel sheet (XLS)</option --> \
	</select> \
	<label class="rform" for="format" style="width: 8em; float: right">Output format</label><br style="clear: left;"> \
	<label class="rform" for="groupmem">Recipient groups</label> \
	<select class="multisel" name="groupmem" id="groupmem" multiple style="width: 10em"></select> \
	<label class="rform" for="mode" style="width: 4em">Mode</label> \
	<select class="multisel" name="mode" id="mode" multiple style="width: 8em"> \
		<option value="recurrence" selected>Recurrence</option> \
		<option value="timerange">Time range</option> \
	</select> \
	<label class="rform cb" for="disabled">Disabled</label> \
	<input class="rform cb" type="checkbox" name="disabled" id="disabled" title="Don\'t run this report periodically"> \
	<label class="rform cb" for="zipattach">ZIP&nbsp;attachments</label> \
	<input class="rform cb" type="checkbox" name="zipattach" id="zipattach" title="Send one ZIP instead of many single files"><br style="clear: left;"> \
	<div id="flip"> \
	</div> \
	</fieldset> \
	<fieldset style="height: 17em; margin-top: 4px"> \
	<legend>Items <button id="addrepitem"></button></legend> \
	<div id="itemtablediv"></div> \
	</fieldset> \
	<!-- Allow form submission with keyboard without duplicating the dialog button --> \
	<input type="submit" tabindex="-1" style="position:absolute; top:-1000px"> \
	</form> \
	</div>';

	$( repFormDiv ).dialog({
		height: 560,
		width: 850,
		modal: true,
		title: "Report details",
		dialogClass: "no-close-dialog",
		buttons: [
			{
				id: "button-save",
				text: "Save definition",
				click: function() {
					if (!isNewRep) {
						var d = new Date();
						repcfgusr.reports[report].updated = d.toISOString();
					}
					SaveRepCfg(true);
					$(this).dialog("close");
					if (!inXormon) {
						$( "#side-menu" ).fancytree( "getTree" ).reactivate();
					}
				}
			},
			{
				id: "button-saverun",
				text: "Save definition & Run",
				click: function() {
					if ( inXormon ) {
						document.body.style.cursor = "wait";
					}
					if (!isNewRep) {
						var d = new Date();
						repcfgusr.reports[report].updated = d.toISOString();
					}
					var o = repcfgusr.reports;
					var $repname = $("#repname");
					if ($repname.val() != $repname.data("oldvalue")) {
						report = $repname.val();
						o[report] =  o[$repname.data("oldvalue")];
						delete o[$repname.data("oldvalue")];
					}
					var postdata = {cmd: "saveall", acl: JSON.stringify(repcfg, null, 2), user: userName};
					$.post( cgiPath + "/reporter.sh", postdata, function( data ) {
						var returned = JSON.parse(data);
						if (returned.status == "fail") {
							$(returned.msg).dialog({
								dialogClass: "info",
								title: "Configuration save - " + returned.status,
								minWidth: 600,
								modal: true,
								show: {
									effect: "fadeIn",
									duration: 500
								},
								hide: {
									effect: "fadeOut",
									duration: 200
								},
								open: function() {
									$('.ui-widget-overlay').addClass('custom-overlay');
								},
								buttons: {
									OK: function() {
										$(this).dialog("close");
									}
								}
							});
						} else {
							if (repcfgusr.reports[report].items && repcfgusr.reports[report].items.length) {
								document.body.style.cursor = 'wait';
								generateReport(report, userName);
							} else {
								$.alert("Nothing to report, please select some content for this report!", "Empty report detected", false);
							}
						}
						if ( inXormon ) {
							myreadyFunc();
							document.body.style.cursor = "default";
						}
					});
					$(this).dialog("close");
					if (!inXormon) {
						$( "#side-menu" ).fancytree( "getTree" ).reactivate();
					}
				}
			},
			{
				id: "button-cancel",
				text: "Cancel",
				click: function() {
					repcfg = JSON.parse(JSON.stringify(oldRepCfg));
					$(this).dialog("close");
					if (!inXormon) {
						$( "#side-menu" ).fancytree( "getTree" ).reactivate();
					}
					else {
						myreadyFunc();
					}
				}
			}
		],
		create: function() {
			var isAdmin = false;
			var repForm = $(this).find( "form" ).on( "submit", function( event ) {
				event.preventDefault();
			//	SaveRepCfg();
			});
			$("#addrepitem").button({
				icon: 'ui-icon-plus'
			}).on("click", function(event) {
				var $itablerows = $("#itemtable tbody tr");
				if ($itablerows.length) {
					var curclass = $itablerows.first().find('.itemclass').text();
					curPlatform = platforms[curclass.toLowerCase()].longname;
					if (curclass == "POWER") {
						repItemFormPower();
					} else if (curclass == "CUSTOM") {
						repItemFormCustom();
					} else if (curclass == "VMWARE") {
						repItemFormVmware();
					} else if (curclass == "OVIRT") {
						repItemFormoVirt();
					} else if (curclass == "SOLARIS") {
						repItemFormSolaris();
					} else if (curclass == "HYPERV") {
						repItemFormHyperV();
					} else if (curclass == "NUTANIX") {
						repItemFormNutanix();
					} else if (curclass == "TOP") {
						repItemFormTop();
					} else if (curclass == "RCA") {
						repItemFormRCA();
					}
				} else {
					selectReportItemClass();
				}
			}).button("disable");
			var recurrence = function() {
				var div = '<label class="rform" for="repfreq">Recurrence</label> \
				<select class="multisel" name="fakefreq" id="fakefreq" multiple style="width: 6em"> \
					<option value="daily">Daily</option> \
					<option value="weekly">Weekly</option> \
					<option value="monthly" selected>Monthly</option> \
					<option value="yearly">Yearly</option> \
				</select> \
				<input class="rform" type="text" name="repfreq" id="repfreq" style="width: 24em; margin-top: 4px;" title="Click to change report frequency, repeating etc." readonly="readonly"> \
				<select class="multisel fr" name="reprange" id="reprange" style="width: 9em; float: right"> \
				<option value="prev" selected>Previous month</option> \
				<option value="last">Last 31 days</option> \
				</select> \
				<label class="rform" for="reprange" style="width: unset; float: right">Range</label>';
				$( "#flip" ).html(div);
				$('#fakefreq').multipleSelect({
					single: true,
					onOpen: function() {
						rruleDialog(report);
					}
				});
				$("#repfreq").on("click", function() {
					rruleDialog(report);
				});
				$('#reprange').multipleSelect({
					onClick: function(view) {
						repcfgusr.reports[report].range = view.value;
					},
					single: true
				});
				if (report) {
					$("#repfreq").val(rrToText(repcfgusr.reports[report].rrule));
				}
			};
			recurrence();
			var timerange = function () {
				var div = "<label class='rform' for='fromTime'>From</label> \
				<input class='rform' type='text' id='fromTime' style='width: 10em'> \
				<label class='rform' style='width: 3em' for='toTime'>to</label> \
				<input class='rform' type='text' id='toTime' style='width: 10em'>";
				$( "#flip" ).html(div);
				var now = new Date();
				var twoWeeksBefore = new Date();
				var yesterday = new Date();
				var nowPlusHour = new Date();
				yesterday.setDate(now.getDate() - 1);
				twoWeeksBefore.setDate(now.getDate() - 14);
				nowPlusHour.setHours(now.getHours() + 1);
				var startDateTextBox = $('#fromTime'),
				endDateTextBox = $('#toTime');

				$("#fromTime").datetimepicker({
					defaultDate: '-1d',
					dateFormat: "yy-mm-dd",
					timeFormat: "HH:00",
					maxDate: nowPlusHour,
					changeMonth: true,
					changeYear: true,
					showButtonPanel: true,
					showOtherMonths: true,
					selectOtherMonths: true,
					showMinute: false,
					onClose: function(dateText, inst) {
						if (endDateTextBox.val() !== '') {
							var testStartDate = startDateTextBox.datetimepicker('getDate');
							var testEndDate = endDateTextBox.datetimepicker('getDate');
							if (testStartDate > testEndDate) {
								endDateTextBox.datetimepicker('setDate', testStartDate);
							}
						} else {
							endDateTextBox.val(dateText);
						}
						repcfgusr.reports[report].sunix = startDateTextBox.datetimepicker('getDate').getTime() / 1000;
						repcfgusr.reports[report].eunix = endDateTextBox.datetimepicker('getDate').getTime() / 1000;
					},
					onSelect: function(selectedDateTime) {
						endDateTextBox.datetimepicker('option', 'minDate', startDateTextBox.datetimepicker('getDate'));
					}
				});
				$("#toTime").datetimepicker({
					defaultDate: 0,
					dateFormat: "yy-mm-dd",
					timeFormat: "HH:00",
					maxDate: nowPlusHour,
					changeMonth: true,
					changeYear: true,
					showButtonPanel: true,
					showOtherMonths: true,
					selectOtherMonths: true,
					showMinute: false,
					onClose: function(dateText, inst) {
						if (startDateTextBox.val() !== '') {
							var testStartDate = startDateTextBox.datetimepicker('getDate');
							var testEndDate = endDateTextBox.datetimepicker('getDate');
							if (testStartDate > testEndDate) {
								startDateTextBox.datetimepicker('setDate', testEndDate);
							}
						} else {
							startDateTextBox.val(dateText);
						}
						repcfgusr.reports[report].sunix = startDateTextBox.datetimepicker('getDate').getTime() / 1000;
						repcfgusr.reports[report].eunix = endDateTextBox.datetimepicker('getDate').getTime() / 1000;
					},
					onSelect: function(selectedDateTime) {
						startDateTextBox.datetimepicker('option', 'maxDate', endDateTextBox.datetimepicker('getDate'));
					}
				});
			};
			$( "#mode" ).multipleSelect({
				single: true,
				onClick: function(view) {
					repcfgusr.reports[report].mode = view.value;
					if (view.value == "timerange") {
						timerange();
					} else {
						recurrence();
					}
				}
			});

			if (! backendSupportsPDF) {
				$('#format option:eq(1)').prop("disabled", true);
			}
			$('#format').multipleSelect({
				placeholder: "Select format to define items!",
				single: true,
				onClick: function(view) {
					$("#button-save,#button-saverun").button("enable");
					repcfgusr.reports[report].format = view.value;
					$("#addrepitem").button("enable");
					if (view.value == "PDF") {
						repcfgusr.reports[report].zipattach = false;
						$('#zipattach').prop("checked", false).checkboxradio("disable");
					} else {
						$('#zipattach').checkboxradio("enable");
					}
				},
				onBlur: function(event) {
					if ( ( !$("#format").val() ) && event.relatedTarget && event.relatedTarget.textContent != "Cancel" && event.relatedTarget.dataset.name != "selectItemformat") {
						$('#format').multipleSelect('focus');
						//$('#format').multipleSelect({
						//	isOpen: true,
						//	keepOpen: true
						//});
						$('#format').multipleSelect('open');
					}
				}
			});
			$('#format').multipleSelect('uncheckAll');
			$.each(repcfgusr.groups, function(grp, val) {
				var isIn = (repcfgusr.reports[report] !== undefined && ($.inArray(grp, repcfgusr.reports[report].recipients) >= 0));
				$("<option />", {text: grp, value: grp, selected: isIn}).appendTo($("#groupmem"));
			});
			$('#groupmem').multipleSelect({
				onClick: function(view) {
					repcfgusr.reports[report].recipients = $('#groupmem').multipleSelect('getSelects');
				},
				onCheckAll: function(view) {
					repcfgusr.reports[report].recipients = $('#groupmem').multipleSelect('getSelects');
				},
				onUncheckAll: function(view) {
					repcfgusr.reports[report].recipients = $('#groupmem').multipleSelect('getSelects');
				}
			});
			$('#zipattach, #keepfiles, #disabled').checkboxradio().on("change", function () {
				repcfgusr.reports[report][this.id] = this.checked;
			});
			if (! backendSupportsZIP) {
				$('#zipattach').checkboxradio("disable");
			}
			if (report) {
				// $("#repname").val(report).prop('disabled', 'disabled');
				if (repcfgusr.reports[report].items.length) {
					$('#format').multipleSelect('disable');
				}
				$("#repname").val(report);
				$("#fakefreq").multipleSelect('setSelects', [repcfgusr.reports[report].freq]);
				if (repcfgusr.reports[report].format) {
					$('#format').multipleSelect('setSelects', [repcfgusr.reports[report].format]);
					$("#addrepitem").button("enable");
				}
				$("#repfreq").val(rrToText(repcfgusr.reports[report].rrule));
				var rrange = repcfgusr.reports[report].freq;
				switch (rrange) {
					case "yearly":
						$("#reprange option:first").text("Previous year");
						$("#reprange option:last").text("Last 365 days");
						break;
					case "monthly":
						$("#reprange option:first").text("Previous month");
						$("#reprange option:last").text("Last 31 days");
						break;
					case "weekly":
						$("#reprange option:first").text("Previous week");
						$("#reprange option:last").text("Last 7 days");
						break;
					case "daily":
						$("#reprange option:first").text("Yesterday");
						$("#reprange option:last").text("Last 24 hours");
						break;
				}
				if (! repcfgusr.reports[report].range) {
					repcfgusr.reports[report].range = "prev";
				}
				$("#reprange").multipleSelect("setSelects", [repcfgusr.reports[report].range]);
				$("#reprange").multipleSelect("refresh");
				if ( repcfgusr.reports[report].format == "PDF" ) {
					$('#zipattach').prop( "disabled", true );
				}
				$('#zipattach').prop('checked', repcfgusr.reports[report].zipattach).checkboxradio( "refresh" );
				$('#keepfiles').prop('checked', repcfgusr.reports[report].keepfiles).checkboxradio( "refresh" );
				$('#disabled').prop('checked', repcfgusr.reports[report].disabled).checkboxradio( "refresh" );
				if ( repcfgusr.reports[report].mode && repcfgusr.reports[report].mode == "timerange" ) {
					$( "#mode" ).multipleSelect("setSelects", ["timerange"]);
					timerange();
					if (repcfgusr.reports[report].sunix ) {
						$("#fromTime").datetimepicker('setDate', new Date(repcfgusr.reports[report].sunix * 1000));
					}
					if (repcfgusr.reports[report].eunix ) {
						$("#toTime").datetimepicker('setDate', new Date(repcfgusr.reports[report].eunix * 1000));
					}
				}
			} else {
				// report = "New Report #" + Math.floor((Math.random() * 899) + 100);
				var d = new Date();
				report = "New Report " + d.toLocaleTimeString();
				if (report.match(/[^a-zA-Z0-9 #:]/g)) {
					report = report.replace(/[^a-zA-Z0-9 #:]/g, '');
				}
				isNewRep = true;
				if (repcfgusr.reports[report] == undefined) {
					// repRuleStr = "FREQ=MONTHLY;BYMONTHDAY=" + d.getDate();
					repRuleStr = "FREQ=MONTHLY;BYMONTHDAY=1";
					repRuleObj = RRule.fromString(repRuleStr);
					$("#repfreq").val(rrToText(repRuleStr));
					repcfgusr.reports[report] = {format: "", rrule: repRuleStr, freq: "monthly", range: "prev", recipients: [], items: [], zipattach: false, keepfiles: false};
					repcfgusr.reports[report].created = d.toISOString();
				}
				$("#repname").val(report);
			}
			$("#repname").tooltipster({
				trigger: 'custom',
				position: 'right',
			});
			$("#repname").on("focus", function( event ) {
				if ( $(this).data("oldvalue") == undefined ) {
					$(this).data("oldvalue", $(this).val());
				}
			});
			$("#repname").on("blur", function( event ) {
				if(!event.relatedTarget || event.relatedTarget && event.relatedTarget.textContent != "Cancel") {
					if ($("#repname") && $(this).val() !== $(this).data("oldvalue") ) {
						var o = repcfgusr.reports;
						if (o[$(this).val()] !== undefined) {
							$(this).tooltipster("open");
							$(event.target).trigger("focus");
						} else {
							$(this).tooltipster("close");
						}
					}
				}
			}).on("change", function() {
				this.value = $.trim(this.value);
				if (this.value.match(/[^a-zA-Z0-9 #:]/g)) {
					this.value = this.value.replace(/[^a-zA-Z0-9 #:]/g, '');
				}
			});

			itemList = repcfgusr.reports[report].items;

			if (itemList.length) {
				renderItemsTable(itemList);
			}

			$("#rruleset").button().on("click", function( event ) {
				rruleDialog(report);
			});

		},
		open: function() {
			$('.ui-widget-overlay').addClass('custom-overlay');
			if ( !$("#format").val() ) {
				$("#button-save,#button-saverun").button("disable");
				$('#format').multipleSelect('focus');
				setTimeout(function() {
					$('#format').multipleSelect('open');
				}, 100);
			}
		},
		close: function() {
			$(this).find( "form" ).trigger('reset');
			$(this).dialog("destroy");
		}
	});
}

function rruleDialog(repid) {
	var rruleFormDiv = '<div id="rrule-form" class="repform"> \
	<form> \
	<fieldset style="float: left;"> \
		<legend>Definition</legend> \
		<label for="rrfreq">Frequency</label> \
		<select class="multisel" name="rrfreq" id="rrfreq"> \
			<option value="3">Daily</option> \
			<option value="2">Weekly</option> \
			<option value="1">Monthly</option> \
			<option value="0">Yearly</option> \
		</select><div class="descr" title="YEARLY, MONTHLY, WEEKLY, DAILY<br> \
		– type of recurrence to use (i.e. is the event every year, every month, weekly, or daily)"></div><br> \
		<label for="byweekday">By weekday</label> \
		<select class="multisel" name="byweekday" id="byweekday" multiple> \
			<option value="0">Monday</option> \
			<option value="1">Tuesday</option> \
			<option value="2">Wednesday</option> \
			<option value="3">Thursday</option> \
			<option value="4">Friday</option> \
			<option value="5">Saturday</option> \
			<option value="6">Sunday</option> \
		</select><div class="descr" title="When given, these variables will define the weekdays where the \
			recurrence will be applied."></div> \
		<br> \
		<label for="bymonth">By month</label> \
		<select class="multisel" name="bymonth" id="bymonth" multiple> \
			<option value="1">January</option> \
			<option value="2">February</option> \
			<option value="3">March</option> \
			<option value="4">April</option> \
			<option value="5">May</option> \
			<option value="6">June</option> \
			<option value="7">July</option> \
			<option value="8">August</option> \
			<option value="9">September</option> \
			<option value="10">October</option> \
			<option value="11">November</option> \
			<option value="12">December</option> \
		</select><div class="descr" title="Meaning the months to apply the recurrence to."></div> \
		<br> \
		<label for="bysetpos">By setpos</label> \
		<input id="bysetpos" class="rrcan" /><div class="descr" title="Comma-separated list of values. Valid values are 1 to 366 or -366 to -1.<br> \
		Each BYSETPOS value corresponds to the nth occurrence within the set of events specified by the rule. \
		It MUST only be used in conjunction with another BYxxx rule part. <br>\
		For example <i>the last work day of the month</i> could be represented as:<br>\
		<pre>RRULE:FREQ=MONTHLY;BYDAY=MO,TU,WE,TH,FR;BYSETPOS=-1</pre>"></div> \
		<br> \
		<label for="bymonthday">By month day</label> \
		<input id="bymonthday" class="rrcan" /><div class="descr" title="Comma-separated list of days \
		of the month. Valid values are 1 to 31 or -31 to -1. For example, -10 represents the tenth to the last day of the month."></div> \
		<br> \
		<label for="byyearday">By year day</label> \
		<input id="byyearday" class="rrcan" /><div class="descr" title="Comma-separated list of days \
		of the year. Valid values are 1 to 366 or -366 to -1. For \
		example, -1 represents the last day of the year (December 31st) \
		and -306 represents the 306th to the last day of the year (March 1st)."></div> \
		<br> \
		<label for="byweekno">By week number</label> \
		<input id="byweekno" class="rrcan" /><div class="descr" title="Comma-separated list of \
		ordinals specifying weeks of the year. Valid values are 1 to 53 \
		or -53 to -1. This corresponds to weeks according to week \
		numbering as defined in [ISO.8601.2004]."></div> \
		<br style="clear: left;"> \
	</fieldset> \
	<fieldset style="float: right;"> \
		<legend>Nearest future occurrences</legend> \
		<div id="nearfuture"></div> \
	</fieldset> \
	<div id="rrstring"></div> \
</form> \
</div>';
	$( rruleFormDiv ).dialog({
		height: 490,
		width: 820,
		modal: true,
		title: "Recurrence rule",
		dialogClass: "no-close-dialog",
		buttons: {
			"Use this rule": function() {
				repcfgusr.reports[repid].freq = $('#rrfreq option:selected').text().toLowerCase();
				repcfgusr.reports[repid].rrule = rrToString(repRuleObj);
				$("#repfreq").val(rrToText(repcfgusr.reports[repid].rrule));
				$("#fakefreq").multipleSelect('setSelects', [repcfgusr.reports[repid].freq]);
				var rrange = $('#rrfreq').val();
				switch (rrange) {
					case "0":
						$("#reprange option:first").text("Previous year");
						$("#reprange option:last").text("Last 365 days");
						break;
					case "1":
						$("#reprange option:first").text("Previous month");
						$("#reprange option:last").text("Last 31 days");
						break;
					case "2":
						$("#reprange option:first").text("Previous week");
						$("#reprange option:last").text("Last 7 days");
						break;
					case "3":
						$("#reprange option:first").text("Yesterday");
						$("#reprange option:last").text("Last 24 hours");
						break;
				}
				$("#reprange").multipleSelect("refresh");
				$(this).dialog("close");
			},
			Cancel: function() {
				$(this).dialog("close");
			}
		},
		create: function() {
			$('#byweekday, #bymonth').multipleSelect();
			$('#rrfreq').multipleSelect({
				single: true,
				onClick: function(view) {
					if (view.value == 3 || view.value == 2) {
						$('#bymonthday').val("");
					}
					if (view.value == 3) {
						$('input.rrcan').val("").prop("disabled", true);
						$('#byweekday, #bymonth').multipleSelect("uncheckAll");
						$('#byweekday, #bymonth').multipleSelect("disable");
					} else {
						$('input.rrcan').prop("disabled", false);
						$('#byweekday, #bymonth').multipleSelect("enable");
					}
				}
			});
			$( "#rrule-form [title]" ).tooltip ({
				position: {
					my: "left top",
					at: "right+5 top-5"
				},
				open: function(event, ui) {
					if (typeof(event.originalEvent) === 'undefined') {
						return false;
					}
					var $id = $(ui.tooltip).attr('id');
					// close any lingering tooltips
					$('div.ui-tooltip').not('#' + $id).remove();
					// ajax function to pull in data and add it to the tooltip goes here
				},
				close: function(event, ui) {
					ui.tooltip.hover(function() {
						$(this).stop(true).fadeTo(400, 1);
					},
					function() {
						$(this).fadeOut('400', function() {
							$(this).remove();
						});
					});
				},
				content: function () {
					return $(this).prop('title');
				}
			});
			if (repid) {
				repRuleStr = repcfgusr.reports[repid].rrule;
			}
			repRuleObj = RRule.fromString(repRuleStr);
			$('#rrfreq').multipleSelect('setSelects', [repRuleObj.options.freq]);
			$('#byweekday').multipleSelect('setSelects', [repRuleObj.options.byweekday]);
			$('#bymonth').multipleSelect('setSelects', [repRuleObj.options.bymonth]);
			$('#bysetpos').val(repRuleObj.origOptions.bysetpos);
			$('#bymonthday').val(repRuleObj.origOptions.bymonthday );
			$('#byyearday').val(repRuleObj.origOptions.byyearday);
			$('#byweekno').val(repRuleObj.origOptions.byweekno);
			$( "#nearfuture" ).empty().append(listRRuleOccurs(repRuleObj));
			var rstr = rrToString(repRuleObj);
			$( "#rrstring" ).html("RRULE: " + rstr + "<br>Human: " + rrToText(rstr));

			$('#rrule-form input, #rrule-form select').on("change", function(event, data) {
				repRuleObj = rrCreate();
				$( "#nearfuture" ).empty().append(listRRuleOccurs(repRuleObj));
				var rstr = rrToString(repRuleObj);
				$( "#rrstring" ).html("RRULE: " + rstr + "<br>Human: " + rrToText(rstr));
			});
			if (repRuleObj.options.freq == 3) {
				$('input.rrcan').val("").prop("disabled", true);
				$('#byweekday, #bymonth').multipleSelect("disable");
			}
		},
		open: function() {
			$('.ui-widget-overlay').addClass('custom-overlay');
		},
		close: function() {
			$(this).find( "form" ).trigger('reset');
			$( "#rrule-form label[title]" ).tooltip( "destroy" );
			$(this).dialog( "destroy" );
		}
	});
}

///// Power item start
function repItemFormPower (repItemIdx) {
	var isNewItem = false,
	repItem,
	oldRepItem,
	report = $("#repname").val(),
	reptype = $("#format").val(),
	repItemFormDiv = '<div id="rep-item-form" class="repform"> \
	<form autocomplete="off"> \
	<fieldset style="float: left;"> \
	<label for="rephost">Host</label> \
	<select class="multisel" type="text" name="rephost" id="rephost"></select> \
	<label for="allhosts" class="cb">Always all&nbsp;</label> \
	<input type="checkbox" name="allhosts" id="allhosts" class="cb" title="Select all available hosts"> \
	<div class="descr" title="This checkbox selects all servers existing at the time the report is being generated.<br> If you check <b>[Select all]</b>, report will contain only servers existing at the time the rule was created."></div> \
	<br style="clear: left;"> \
	<label for="repsubsys">Subsystem</label> \
	<select class="multisel" type="text" name="repsubsys" id="repsubsys"> \
	</select> \
	<label for="outdated" class="cb button_outdated">Out of date</label> \
	<input type="checkbox" name="outdated" id="outdated" class="cb button_outdated" title="Include outdated LPARs"> \
	<div class="descr button_outdated" title="When checked, outdated LPARs (not updated for 30+ days) can be selected."></div> \
	<br style="clear: left;"> \
	<label for="repitem">Items</label> \
	<select class="multisel" name="repitem" id="repitem"></select> \
	<label for="entiresubsys" class="cb">Always all&nbsp;</label> \
	<input type="checkbox" name="entiresubsys" id="entiresubsys" class="cb" title="Select all available items"> \
	<div class="descr" title="This checkbox selects all existing items on given server(s) at the time the report is being generated.<br> If you check <b>[Select all]</b>, report will contain only items existing at the time the rule was created."></div> \
	<br style="clear: left;"> \
	<label for="repmetric">Metric</label> \
	<select class="multisel" name="repmetric" id="repmetric"> \
	</select><br style="clear: left;"> \
	<label class="srate" for="sample_rate" style="display: none">Sample rate</label> \
	<select class="multisel srate" name="sample_rate" id="sample_rate" multiple style="width: 7em; display: none"> \
		<option value="60" selected>1 minute</option> \
		<option value="300">5 minutes</option> \
		<option value="3600">1 hour</option> \
		<option value="18000">5 hours</option> \
		<option value="86400">1 day</option> \
	</select><br style="clear: left;"> \
	</fieldset> \
	<!-- Allow form submission with keyboard without duplicating the dialog button --> \
	<input type="submit" tabindex="-1" style="position:absolute; top:-1000px; left: -1000px;"> \
	</form> \
	</div>';
	if (repItemIdx !== undefined) {
		oldRepItem = JSON.parse(JSON.stringify(itemList[repItemIdx]));
	}

	if (reptype != "CSV") {
		reptype = "IMG";
	}

	$( repItemFormDiv ).dialog({
		height: 480,
		width: 540,
		modal: true,
		title: "Reported item selection - " + curPlatform,
		dialogClass: "no-close-dialog",
		buttons: [
			{
				id: "button-ok",
				text: "Use this definition",
				click: function() {
					$(this).dialog('close');
					delete repItem.type;
					if (isNewItem) {
						itemList.push(repItem);
					} else {
						itemList[repItemIdx] = repItem;
					}
					$('#format').multipleSelect('disable');
					renderItemsTable(itemList);
				}
			},
			{
				id: "button-cancel",
				text: "Cancel",
				click: function() {
					if (oldRepItem) {
						itemList[repItemIdx] = JSON.parse(JSON.stringify(oldRepItem));
					}
					$(this).dialog('close');
				}
			},
		],
		create: function() {
			var isAdmin = false;
			var repForm = $(this).find( "form" ).on( "submit", function( event ) {
				event.preventDefault();
			//	SaveRepCfg();
			});
			curPlatform = "POWER";
			var myfleet = fleet[curPlatform];
			$("#button-ok").button("disable");
			$( "div.descr" ).tooltip ({
				position: {
					my: "right top",
					at: "right+5 top+20"
				},
				open: function(event, ui) {
					if (typeof(event.originalEvent) === 'undefined') {
						return false;
					}
					var $id = $(ui.tooltip).attr('id');
					// close any lingering tooltips
					$('div.ui-tooltip').not('#' + $id).remove();
					// ajax function to pull in data and add it to the tooltip goes here
				},
				close: function(event, ui) {
					ui.tooltip.hover(function() {
						$(this).stop(true).fadeTo(400, 1);
					},
					function() {
						$(this).fadeOut('400', function() {
							$(this).remove();
						});
					});
				},
				content: function () {
					return $(this).prop('title');
				}
			});

			if (reptype == "CSV") {
				$(".srate").show();
				$('#sample_rate').multipleSelect({
					onClick: function(view) {
						repItem.sample_rate = view.value;
						if ($('#repmetric').multipleSelect('getSelects').length) {
							$("#button-ok").button("enable");
						}
					},
					single: true,
				});
			}
			$('#allhosts').checkboxradio().on("change", function () {
				repItem.allhosts = this.checked;
				repItem.group = curPlatform;
				repItemTypeChange();
				if (this.checked) {
					$('#rephost').multipleSelect("uncheckAll").multipleSelect("disable");
					$('#entiresubsys').prop("checked", false).checkboxradio("refresh").checkboxradio("disable");
					repItem.host = "";
					var $opt = $("<option />", {
						value: "SERVER",
						text: "SERVER"
					});
					$('#repsubsys').append($opt);
					$opt = $("<option />", {
						value: "LPAR",
						text: "LPAR"
					});
					$('#repsubsys').append($opt);
					$opt = $("<option />", {
						value: "POOL",
						text: "POOL"
					});
					$('#repsubsys').append($opt);
					$('#repsubsys').multipleSelect("uncheckAll").multipleSelect("enable").multipleSelect("refresh");
				} else {
					$('#entiresubsys').prop("checked", false).checkboxradio("refresh").checkboxradio("disable");
					$('#rephost').multipleSelect("enable").multipleSelect("refresh");
					$('#repsubsys').multipleSelect("uncheckAll").multipleSelect("disable").multipleSelect("refresh");
					$('#repitem').multipleSelect("uncheckAll").multipleSelect("disable").multipleSelect("refresh");
					$('#repmetric').multipleSelect("uncheckAll").multipleSelect("disable").multipleSelect("refresh");
				}
			});
			$('#entiresubsys').checkboxradio({
				disabled: true
			}).on("change", function () {
				repItem.entiresubsys = this.checked;
				repItem.name = [];
				if (this.checked) {
					$('#repitem').multipleSelect("uncheckAll").multipleSelect("disable");
					$('#repmetric').empty().multipleSelect("enable");
					var ssys = $("#repsubsys option:selected").val();
					var ltype = "all";
					var metricGroup = "ITEMS";
					$.each(metrics[curPlatform][ssys][reptype][metricGroup][ltype], function(idx, val0) {
						try {
							var ttext = (urlItems[val0][2]) ? urlItems[val0][2] : urlItems[val0][0];
							$opt = $("<option />", {
								value: val0,
								text: ttext
							});
							$('#repmetric').append($opt);
						}
						catch(e) { }
					});
					$('#repmetric').multipleSelect('refresh');
					$('#repmetric').multipleSelect('uncheckAll');
				} else {
					var ssys = $("#repsubsys option:selected").val();
					$('#repmetric').multipleSelect("uncheckAll").multipleSelect("disable").multipleSelect("refresh");
				}
			});
			$('#outdated').checkboxradio({
				disabled: true
			}).on("change", function () {
				repItem.outdated = this.checked;
				var hosts = $('#rephost').multipleSelect('getSelects');
				if ($('#allhosts').prop("checked")) {
					hosts = [];
					$.each(myfleet, function(fkey, fvalue) {
						hosts.push(fkey);
					});
				}
				var ssys = "LPAR";
				$('#repitem').empty().multipleSelect("enable");
				// $("#button-ok").button("disable");
				$.each(hosts, function(idx, hostname) {
					if (myfleet[hostname] && myfleet[hostname].subsys[ssys]) {
						$.each(myfleet[hostname].subsys[ssys], function(key1, val1) {
							if ( $("#repitem option[value='" + val1.name + "']").length == 0) {
								var $opt = $("<option />", {
									value: val1.name,
									text: val1.name
								});
								if (val1.type) {
									$opt.data("type", val1.type);
								}
								if (val1.hmc) {
									$opt.data("hmc", val1.hmc);
									repItem.hmc = val1.hmc;
								}
								$('#repitem').append($opt);
							}
						});
					}
				});
				if (this.checked) {
					ssys = "OUTDATED";
					$.each(hosts, function(idx, hostname) {
						if (myfleet[hostname] && myfleet[hostname].subsys[ssys]) {
							$.each(myfleet[hostname].subsys[ssys], function(key1, val1) {
								if ( $("#repitem option[value='" + val1.name + "']").length == 0) {
									var $opt = $("<option />", {
										value: val1.name,
										text: val1.name,
										class: "removed"
									});
									if (val1.type) {
										$opt.data("type", val1.type);
									}
									if (val1.hmc) {
										$opt.data("hmc", val1.hmc);
										repItem.hmc = val1.hmc;
									}
									$('#repitem').append($opt);
								}
							});
						}
					});
				} else {
					$('#entiresubsys').checkboxradio("enable");
				}
				$('#repitem').multipleSelect('refresh').multipleSelect('setSelects', repItem.name);
			});
			var itemChange = function() {
				repItem.name = $('#repitem').multipleSelect('getSelects');
				$("#button-ok").button("disable");
				$('#repmetric').empty().multipleSelect("enable");
				var ssys = $("#repsubsys option:selected").val();
				var metricGroup = "ITEMS";
				var items = $('#repitem').multipleSelect('getSelects');
				$.each(items, function(idx, item) {
					var ltype = $("#repitem option[value='" + item + "']").data("type");
					if (ltype && metrics[curPlatform][ssys][reptype][metricGroup][ltype]) {
						$.each(metrics[curPlatform][ssys][reptype][metricGroup][ltype], function(idx, val0) {
							if ( $("#repmetric option[value='" + val0 + "']").length == 0) {
								try {
									var ttext = (urlItems[val0][2]) ? urlItems[val0][2] : urlItems[val0][0];
									$opt = $("<option />", {
										value: val0,
										text: ttext
									});
									$('#repmetric').append($opt);
								}
								catch(e) { }
							}
						});
					}
					$('#repmetric').multipleSelect('refresh');
					$('#repmetric').multipleSelect('uncheckAll');
				});
			};

			$('#repitem').multipleSelect({
				filter: true,
				single: false,
				maxHeight: 200,
				//selectAll: false,
				//allSelected: false,
				onClick: function() {
					itemChange();
				},
				onCheckAll: function() {
					itemChange();
				},
				onUncheckAll: function() {
					repItem.name = [];
					$("#button-ok").button("disable");
					$('#repmetric').empty().multipleSelect("disable");
				}
			}).multipleSelect("disable");

			var subsysChange = function(view, ui) {
				var hosts = $('#rephost').multipleSelect('getSelects');
				var metricGroup = "ITEMS";
				if ($('#allhosts').prop("checked")) {
					hosts = [];
					$.each(myfleet, function(fkey, fvalue) {
						hosts.push(fkey);
					});
				}
				var ssys = view.value;
				repItem.subsys = ssys;
				$('#entiresubsys').prop("checked", false).checkboxradio("refresh");
				$('#entiresubsys').checkboxradio("enable");
				if (ssys == "LPAR") {
					$('#outdated').checkboxradio("refresh");
					$('#outdated').checkboxradio("enable");
					$('.button_outdated').show();
				} else {
					$('#outdated').checkboxradio("disable");
					$('.button_outdated').hide();
				}
				$('#repmetric').empty().multipleSelect("disable").multipleSelect("refresh");
				$('#repitem').empty().multipleSelect("enable");
				$("#button-ok").button("disable");
				$.each(hosts, function(idx, hostname) {
					if (myfleet[hostname] && myfleet[hostname].subsys[ssys]) {
						$.each(myfleet[hostname].subsys[ssys], function(key1, val1) {
							if ( $("#repitem option[value='" + val1.name + "']").length == 0) {
								var $opt = $("<option />", {
									value: val1.name,
									text: val1.name
								});
								if (val1.type) {
									$opt.data("type", val1.type);
								}
								if (val1.hmc) {
									$opt.data("hmc", val1.hmc);
									repItem.hmc = val1.hmc;
								}
								$('#repitem').append($opt);
							}
						});
					}
				});
				if (ssys == "LPAR" && $('#outdated').prop("checked")) {
					var ssysex = "OUTDATED";
					$.each(hosts, function(idx, hostname) {
						if (myfleet[hostname] && myfleet[hostname].subsys[ssysex]) {
							$.each(myfleet[hostname].subsys[ssysex], function(key1, val1) {
								if ( $("#repitem option[value='" + val1.name + "']").length == 0) {
									var $opt = $("<option />", {
										value: val1.name,
										text: val1.name,
										class: "removed"
									});
									if (val1.type) {
										$opt.data("type", val1.type);
									}
									if (val1.hmc) {
										$opt.data("hmc", val1.hmc);
										repItem.hmc = val1.hmc;
									}
									$('#repitem').append($opt);
								}
							});
						}
					});
				}
				if (! ui ) {
					$('#repitem').multipleSelect('uncheckAll');
					$('#repitem').multipleSelect('refresh');
				}
			};
			$('#repsubsys').multipleSelect({
				filter: false,
				single: true,
				selectAll: false,
				maxHeight: 200,
				allSelected: false,
				onClick: function(view) {
					subsysChange(view);
				}
			}, "disable");

			var repHostChange = function() {
				repItem.group = curPlatform;
				repItem.host = $('#rephost').multipleSelect('getSelects');
				var metricGroup = "ITEMS";
				$('#repsubsys').empty();
				$('#repitem').empty().multipleSelect("disable").multipleSelect("refresh");
				$('#repmetric').empty().multipleSelect("disable").multipleSelect("refresh");
				$("#button-ok").button("disable");
				$.each(repItem.host, function(key, val) {
					$.each(myfleet[val].subsys, function(key2, val2) {
						if (key2 != "OUTDATED") {
							try {
								if (metrics[repItem.group][key2][reptype][metricGroup]) {
									if ( $("#repsubsys option[value='" + key2 + "']").length == 0) {
										var $opt = $("<option />", {
											value: key2,
											text: key2,
										});
										$('#repsubsys').append($opt);
									}
								}
							}
							catch (e) {}
						}
					});
				});
				$('#repsubsys').multipleSelect("enable");
				$('#repsubsys').multipleSelect('uncheckAll');
				$('#repsubsys').multipleSelect('refresh');
			};

			$('#rephost').multipleSelect({
				filter: true,
				single: false,
				onClick: function() {
					repHostChange();
				},
				onCheckAll:  function() {
					repHostChange();
				},
				onUncheckAll: function() {
					repItem.host = [];
					$('#repsubsys').empty().multipleSelect("disable").multipleSelect("refresh");
					$('#repitem').empty().multipleSelect("disable").multipleSelect("refresh");
					$('#repmetric').empty().multipleSelect("disable").multipleSelect("refresh");
					$("#button-ok").button("disable");
				}
			});

			var repItemTypeChange = function(line) {
				if ( ! line ) {
					$("#button-ok").button("disable");
					$('#repsubsys').empty().multipleSelect("disable").multipleSelect("refresh");
					$('#repitem').empty().multipleSelect("disable").multipleSelect("refresh");
					$('#repmetric').empty().multipleSelect("disable").multipleSelect("refresh");
					$('#allhosts').checkboxradio("enable");
					$('#rephost').multipleSelect('enable').multipleSelect('refresh').multipleSelect("uncheckAll");
				} else {
					var selected = line.name;
					if (! jQuery.isArray( selected )) {
						selected = [selected];
					}
					var hosts = line.host;
					if (! jQuery.isArray( hosts )) {
						hosts = [hosts];
					}
					curPlatform = line.group;
					var ssys = line.subsys;
					var metricGroup = "ITEMS";
					if (ssys == "LPAR") {
						$('#outdated').checkboxradio("enable");
						$('.button_outdated').show();
						if (line.outdated) {
							$('#outdated').prop("checked", true).checkboxradio("refresh");
						}
					} else {
						$('.button_outdated').hide();
					}
					if (line.allhosts) {
						$('#allhosts').prop("checked", true).checkboxradio("refresh");
						$('#rephost').multipleSelect("disable");
						var $opt = $("<option />", {
							value: "SERVER",
							text: "SERVER"
						});
						$('#repsubsys').append($opt);
						$opt = $("<option />", {
							value: "LPAR",
							text: "LPAR"
						});
						$('#repsubsys').append($opt);
						$opt = $("<option />", {
							value: "POOL",
							text: "POOL"
						});
						$('#repsubsys').append($opt);
						$('#repsubsys').multipleSelect('refresh');
						$('#repsubsys').multipleSelect('setSelects', [ssys]).multipleSelect("refresh").multipleSelect("enable");
						subsysChange({value: ssys}, true);
					} else {
						$('#rephost').multipleSelect("enable");
						$('#rephost').multipleSelect('refresh');
						$('#rephost').multipleSelect('setSelects', hosts);
						$.each(hosts, function(key, val) {
							$.each(myfleet[val].subsys, function(key2, val2) {
								if (key2 != "OUTDATED") {
									$opt = $("<option />", {
										value: key2,
										text: key2,
									});
									if ( $("#repsubsys option[value='" + key2 + "']").length == 0) {
										$('#repsubsys').append($opt);
									}
								}
							});
						});
						$('#repsubsys').multipleSelect("enable");
						$('#repsubsys').multipleSelect('refresh');
						$('#repsubsys').multipleSelect('setSelects', [line.subsys]);
					}
					$('#entiresubsys').checkboxradio("enable");

					if (line.entiresubsys) {
						$('#entiresubsys').prop("checked", true).checkboxradio("refresh");
						$('#repitem').multipleSelect("disable");
					} else {
						$('#repitem').multipleSelect("enable");
						$('#repitem').multipleSelect('setSelects', [line.subsys]);
					}


					try {
						if ( reptype != "CSV" && metrics[curPlatform][ssys][metricCategory][reptype].AGGREGATES.length) {
							$opt = $("<option />", { value: "", text: "[all aggregated]" });
							$('#repitem').append($opt);
						}
					}
					catch (e) {}
					$.each(hosts, function(idx, host) {
						if (myfleet[host]) {
							$.each(myfleet[host].subsys[line.subsys], function(key1, val1) {
								if ( $("#repitem option[value='" + val1.name + "']").length == 0) {
									$opt = $("<option />", {
										value: val1.name,
										text: val1.name
									});
									if (val1.type) {
										$opt.data("type", val1.type);
									}
									if (val1.hmc) {
										$opt.data("hmc", val1.hmc);
										repItem.hmc = val1.hmc;
									}
									$('#repitem').append($opt);
								}
							});
						}
					});
					if (ssys == "LPAR" && line.outdated) {
						var ssysex = "OUTDATED";
						$.each(hosts, function(idx, host) {
							if (myfleet[host] && myfleet[host].subsys[ssysex]) {
								$.each(myfleet[host].subsys[ssysex], function(key1, val1) {
									if ( $("#repitem option[value='" + val1.name + "']").length == 0) {
										var $opt = $("<option />", {
											value: val1.name,
											text: val1.name,
											class: "removed"
										});
										if (val1.type) {
											$opt.data("type", val1.type);
										}
										if (val1.hmc) {
											$opt.data("hmc", val1.hmc);
											repItem.hmc = val1.hmc;
										}
										$('#repitem').append($opt);
									}
								});
							}
						});
					}
					$('#repitem').multipleSelect('refresh');
					$('#repitem').multipleSelect('setSelects', selected);
					var ltype = "all";
					if (curPlatform == "CUSTOM") {
						ltype = ssys;
					} else if ( selected.length == 1 ) {
						ltype = $("#repitem option:selected").data("type");
					}
					$('#repmetric').multipleSelect("enable");
					if (metrics[curPlatform][ssys][reptype][metricGroup][ltype]) {
						$.each(metrics[curPlatform][ssys][reptype][metricGroup][ltype], function(idx, val0) {
							try {
								var ttext = (urlItems[val0][2]) ? urlItems[val0][2] : urlItems[val0][0];
								$opt = $("<option />", {
									value: val0,
									text: ttext
								});
								$('#repmetric').append($opt);
							}
							catch (e) {}
						});
					}
					if (line.sample_rate) {
						$('#sample_rate').multipleSelect('setSelects', [line.sample_rate]);
					}

					$('#repmetric').multipleSelect('refresh');
					$('#repmetric').multipleSelect('setSelects', line.metrics);
				}
			};


			// $("#repitemtype input").checkboxradio();

			$('#repmetric').multipleSelect({
				maxHeight: 200,
				disabled: true,
				single: false,
				onClick: function(view) {
					repItem.metrics = $('#repmetric').multipleSelect('getSelects');
					if (repItem.metrics.length) {
						$("#button-ok").button("enable");
					} else {
						$("#button-ok").button("disable");
					}
				},
				onCheckAll: function(view) {
					repItem.metrics = $('#repmetric').multipleSelect('getSelects');
					$("#button-ok").button("enable");
				},
				onUncheckAll: function(view) {
					repItem.metrics = $('#repmetric').multipleSelect('getSelects');
					$("#button-ok").button("disable");
				}
			}, "disable");

			$('#rephost').empty();
			$.each(myfleet, function(key3, val3) {
				$opt = $("<option />", {
					value: key3,
					text: key3,
					"data-platform": val3.platform
				});
				$('#rephost').append($opt);
			});
			if (repItemIdx !== undefined) {
				repItem = repcfgusr.reports[report].items[repItemIdx];
				repItemTypeChange(repItem);
			} else {
				isNewItem = true;
				repItem = {host: "", subsys: "", name: "", metrics: [], group: "POWER"};
				repItemTypeChange();
			}
		},
		open: function() {
			$('#rephost').multipleSelect('refresh');
			$('.ui-widget-overlay').addClass('custom-overlay');
		},
		close: function() {
			$(this).find( "form" ).trigger('reset');
			$(this).dialog("destroy").remove();
		}
	});

}
///// Power item end

function repItemFormCustom (repItemIdx) {
	var isNewItem = false,
	repItem,
	oldRepItem,
	report = $("#repname").val(),
	reptype = $("#format").val(),
	repItemFormDiv = '<div id="rep-item-form" class="repform"> \
	<form autocomplete="off"> \
	<fieldset style="float: left;"> \
	<label for="rephost">Group name</label> \
	<select class="multisel" type="text" name="rephost" id="rephost"></select><br style="clear: left;"> \
	<label for="repsubsys">Subsystem</label> \
	<select class="multisel" type="text" name="repsubsys" id="repsubsys"> \
	</select><br style="clear: left;"> \
	<label for="repmetric">Metric</label> \
	<select class="multisel" name="repmetric" id="repmetric"> \
	</select><br style="clear: left;"> \
	<label class="srate" for="sample_rate" style="display: none">Sample rate</label> \
	<select class="multisel srate" name="sample_rate" id="sample_rate" multiple style="width: 7em; display: none"> \
		<option value="60" selected>1 minute</option> \
		<option value="300">5 minutes</option> \
		<option value="3600">1 hour</option> \
		<option value="18000">5 hours</option> \
		<option value="86400">1 day</option> \
	</select><br style="clear: left;"> \
	</fieldset> \
	<!-- Allow form submission with keyboard without duplicating the dialog button --> \
	<input type="submit" tabindex="-1" style="position:absolute; top:-1000px; left: -1000px;"> \
	</form> \
	</div>';
	if (repItemIdx !== undefined) {
		oldRepItem = JSON.parse(JSON.stringify(itemList[repItemIdx]));
	}

	if (reptype != "CSV") {
		reptype = "IMG";
	}

	$( repItemFormDiv ).dialog({
		height: 480,
		width: 520,
		modal: true,
		title: "Reported item selection - " + curPlatform,
		dialogClass: "no-close-dialog",
		buttons: [
			{
				id: "button-ok",
				text: "Use this definition",
				click: function() {
					$(this).dialog('close');
					delete repItem.type;
					if (isNewItem) {
						itemList.push(repItem);
					} else {
						itemList[repItemIdx] = repItem;
					}
					$('#format').multipleSelect('disable');
					renderItemsTable(itemList);
				}
			},
			{
				id: "button-cancel",
				text: "Cancel",
				click: function() {
					if (oldRepItem) {
						itemList[repItemIdx] = JSON.parse(JSON.stringify(oldRepItem));
					}
					$(this).dialog('close');
				}
			},
		],
		create: function() {
			var isAdmin = false;
			var repForm = $(this).find( "form" ).on( "submit", function( event ) {
				event.preventDefault();
			//	SaveRepCfg();
			});
			$("#button-ok").button("disable");

			var repHostChange = function(view) {
				if (view) {
					repItem.host = [view.value];
				}
				var ssys = "";
				$.each(cgroups, function(key, val) {
					if (val.title == view.value) {
						ssys = val.cgtype;
					}
				});
				$opt = $("<option />", {
					value: ssys,
					text: ssys
				});
				$('#repsubsys').empty().append($opt);
				$('#repsubsys').multipleSelect('refresh');
				$('#repsubsys').multipleSelect('checkAll');
				$('#repmetric').empty().multipleSelect("enable");
				repItem.group = "CUSTOM";
				repItem.subsys = ssys;
				var metricGroup = "ITEMS";
				if (ssys && metrics[repItem.group][ssys][reptype][metricGroup][ssys]) {
					$.each(metrics[repItem.group][ssys][reptype][metricGroup][ssys], function(idx, val0) {
						try {
							var ttext = urlItems[val0][2] ? urlItems[val0][2] : urlItems[val0][0];
							$opt = $("<option />", {
								value: val0,
								text: ttext
							});
							$('#repmetric').append($opt);
						}
						catch (e) {}
					});
				}
				$('#repmetric').multipleSelect('refresh').multipleSelect('uncheckAll');
				$("#button-ok").button("disable");
			};
			$('#rephost').multipleSelect({
				filter: true,
				single: true,
				onClick: function(view) {
					repHostChange(view);
				}
			});
			$('#repsubsys').multipleSelect({
				filter: false,
				single: true,
				selectAll: false,
				maxHeight: 200,
				allSelected: false,
				onClick: function(view) {
					//subsysChange(view);
				}
			}).multipleSelect("disable");

			$('#repmetric').multipleSelect({
				maxHeight: 200,
				disabled: true,
				single: false,
				onClick: function(view) {
					repItem.metrics = $('#repmetric').multipleSelect('getSelects');
					if (repItem.metrics.length) {
						$("#button-ok").button("enable");
					} else {
						$("#button-ok").button("disable");
					}
				},
				onCheckAll: function(view) {
					repItem.metrics = $('#repmetric').multipleSelect('getSelects');
					$("#button-ok").button("enable");
				},
				onUncheckAll: function(view) {
					repItem.metrics = [];
					$("#button-ok").button("disable");
				}
			}).multipleSelect("disable");

			if (reptype == "CSV") {
				$(".srate").show();
				$('#sample_rate').multipleSelect({
					onClick: function(view) {
						repItem.sample_rate = view.value;
						if ($('#repmetric').multipleSelect('getSelects').length) {
							$("#button-ok").button("enable");
						}
					},
					single: true,
				});
			}
			$.each(cgroups, function(key, val) {
				var $opt = $("<option />", {
					value: val.title,
					text: val.title,
					"data-platform": val.type
				});
				$('#rephost').append($opt);
			});
			$('#rephost').multipleSelect('refresh').multipleSelect('uncheckAll');

			if (repItemIdx == undefined) {
				isNewItem = true;
				repItem = {host: "", subsys: "", name: "", metrics: [], group: "CUSTOM"};
			} else {
				repItem = repcfgusr.reports[report].items[repItemIdx];
				if (! jQuery.isArray( repItem.host )) {
					repItem.host = [repItem.host];
				}
				$('#rephost').multipleSelect('setSelects', repItem.host).multipleSelect('refresh');
				repHostChange({label: repItem.host[0], value: repItem.host[0]});
				$('#repmetric').multipleSelect('setSelects', oldRepItem.metrics);
				if (repItem.sample_rate) {
					$('#sample_rate').multipleSelect('setSelects', [repItem.sample_rate]);
				}
			}
		},
		open: function() {
			$('.ui-widget-overlay').addClass('custom-overlay');
		},
		close: function() {
			$(this).dialog("destroy");
		}
	});

}

function repItemFormVmware (repItemIdx) {
	var isNewItem = false,
	repItem,
	oldRepItem,
	report = $("#repname").val(),
	reptype = $("#format").val(),
	repItemFormDiv = '<div id="rep-item-form" class="repform"> \
	<form autocomplete="off"> \
	<fieldset style="float: left;"> \
	<label for="vcenter">vCenter</label> \
	<select class="multisel" type="text" name="vcenter" id="vcenter"></select> \
	<!--label for="allvcenters" class="cb">Always all</label> \
	<input type="checkbox" name="allhosts" id="allvcenters" class="cb" "Select all available hosts"> \
	<div class="descr" title="This checkbox selects all vCenters existing at the time the report is being generated.<br> If you check <b>[Select all]</b>, report will contain only vCenters existing at the time the rule was created."></div--> \
	<br style="clear: left;"> \
	<label for="repsubsys">Subsystem</label> \
	<select class="multisel" type="text" name="repsubsys" id="repsubsys"> \
	</select><br style="clear: left;"> \
	<!--label for="inventory">Inventory</label> \
	<select class="multisel" type="text" name="inventory" id="inventory"> \
		<option value="CLUSTER">Cluster</option> \
		<option value="DATACENTER">Storage</option> \
	</select><br style="clear: left;"--> \
	<label for="rephost">Cluster</label> \
	<select class="multisel" type="text" name="rephost" id="rephost"></select> \
	<!--label for="allhosts" class="cb">Always all</label> \
	<input type="checkbox" name="allhosts" id="allhosts" class="cb" "Select all available hosts"> \
	<div class="descr" title="This checkbox selects all clusters/datacnters existing at the time the report is being generated.<br> If you check <b>[Select all]</b>, report will contain only clusters/datacenters existing at the time the rule was created."></div--> \
	<br style="clear: left;"> \
	<label for="repitem">Item</label> \
	<select class="multisel" name="repitem" id="repitem"></select> \
	<label for="entiresubsys" class="cb">Always all</label> \
	<input type="checkbox" name="entiresubsys" id="entiresubsys" class="cb" "Select all available items"> \
	<div class="descr" title="This checkbox selects all existing items on given server(s) at the time the report is being generated.<br> If you check <b>[Select all]</b>, report will contain only items existing at the time the rule was created."></div> \
	<br style="clear: left;"> \
	<label for="repmetric">Metric</label> \
	<select class="multisel" name="repmetric" id="repmetric"> \
	</select><br style="clear: left;"> \
	<label class="srate" for="sample_rate" style="display: none">Sample rate</label> \
	<select class="multisel srate" name="sample_rate" id="sample_rate" multiple style="width: 7em; display: none"> \
		<option value="60" selected>1 minute</option> \
		<option value="300">5 minutes</option> \
		<option value="3600">1 hour</option> \
		<option value="18000">5 hours</option> \
		<option value="86400">1 day</option> \
	</select><br style="clear: left;"> \
	</fieldset> \
	<!-- Allow form submission with keyboard without duplicating the dialog button --> \
	<input type="submit" tabindex="-1" style="position:absolute; top:-1000px; left: -1000px;"> \
	</form> \
	</div>';
	curPlatform = "VMWARE";
	var myfleet = fleet[curPlatform];
	var repHostDef = function (single) {
		$('#rephost').multipleSelect("destroy");
		$('#rephost').multipleSelect({
			filter: true,
			single: single,
			selectAll: false,
			allSelected: false,
			onClick: function(view) {
				var hosts = $('#rephost').multipleSelect('getSelects');
				repItem.host = hosts;
				var metricGroup = "ITEMS";
				var ssys = repItem.subsys;
				var inventory = ssys == "DATASTORE" ? "DATACENTER" : "CLUSTER";
				$("#button-ok").button("disable");
				if (ssys == "CLUSTER") {
					$('#repitem').empty().multipleSelect("disable");
					$('#entiresubsys').prop("checked", false).checkboxradio("refresh");
					$('#entiresubsys').checkboxradio("disable");
					$('#repmetric').empty().multipleSelect('enable');
					$.each(metrics[repItem.group][ssys][reptype][metricGroup], function(idx, val0) {
						if ( $("#repmetric option[value='" + val0 + "']").length == 0) {
							try {
								var ttext = (urlItems[val0][2]) ? urlItems[val0][2] : urlItems[val0][0];
								$opt = $("<option />", {
									value: val0,
									text: ttext
								});
								$('#repmetric').append($opt);
							}
							catch(e) { }
						}
					});
					$('#repmetric').multipleSelect('refresh').multipleSelect('uncheckAll');
				} else {
					$('#repitem').empty().multipleSelect("enable");
					$('#repmetric').empty().multipleSelect("disable").multipleSelect("refresh");
					$('#entiresubsys').prop("checked", false).checkboxradio("refresh");
					$('#entiresubsys').checkboxradio("enable");
					$.each(hosts, function(idx, hostname) {
						if (metrics[repItem.group][ssys][reptype][metricGroup]) {
							$.each(myfleet[repItem.vcenter].inventory[inventory][hostname][ssys], function(key, val) {
								var value = val.name;
								if (val.uuid) {
									value = val.uuid;
								}
								var $opt = $("<option />", {
									value: value,
									text: val.name
								});
								$('#repitem').append($opt);
							});
						}
					});
					$('#repitem').multipleSelect('uncheckAll').multipleSelect("refresh");
				}
			}
		});
	};

	if (repItemIdx !== undefined) {
		oldRepItem = JSON.parse(JSON.stringify(itemList[repItemIdx]));
	}

	if (reptype != "CSV") {
		reptype = "IMG";
	}

	$( repItemFormDiv ).dialog({
		height: 480,
		width: 520,
		modal: true,
		title: "Reported item selection - " + curPlatform,
		dialogClass: "no-close-dialog",
		buttons: [
			{
				id: "button-ok",
				text: "Use this definition",
				click: function() {
					$(this).dialog('close');
					delete repItem.type;
					if (isNewItem) {
						itemList.push(repItem);
					} else {
						itemList[repItemIdx] = repItem;
					}
					$('#format').multipleSelect('disable');
					renderItemsTable(itemList);
				}
			},
			{
				id: "button-cancel",
				text: "Cancel",
				click: function() {
					if (oldRepItem) {
						itemList[repItemIdx] = JSON.parse(JSON.stringify(oldRepItem));
					}
					$(this).dialog('close');
				}
			},
		],
		create: function() {
			var isAdmin = false;
			var repForm = $(this).find( "form" ).on( "submit", function( event ) {
				event.preventDefault();
			//	SaveRepCfg();
			});
			$("#button-ok").button("disable");
			$( "div.descr" ).tooltip ({
				position: {
					my: "right top",
					at: "right+5 top+20"
				},
				open: function(event, ui) {
					if (typeof(event.originalEvent) === 'undefined') {
						return false;
					}
					var $id = $(ui.tooltip).attr('id');
					// close any lingering tooltips
					$('div.ui-tooltip').not('#' + $id).remove();
					// ajax function to pull in data and add it to the tooltip goes here
				},
				close: function(event, ui) {
					ui.tooltip.hover(function() {
						$(this).stop(true).fadeTo(400, 1);
					},
					function() {
						$(this).fadeOut('400', function() {
							$(this).remove();
						});
					});
				},
				content: function () {
					return $(this).prop('title');
				}
			});
			$("#button-ok").button("disable");

			$('#entiresubsys').checkboxradio({
				disabled: true
			}).on("change", function () {
				repItem.entiresubsys = this.checked;
				repItem.name = [];
				if (this.checked) {
					$('#repitem').multipleSelect("uncheckAll").multipleSelect("disable").multipleSelect("refresh");
					$('#repmetric').empty().multipleSelect("enable");
					var ssys = $("#repsubsys option:selected").val();
					var metricGroup = "ITEMS";
					$.each(metrics[repItem.group][ssys][reptype][metricGroup], function(idx, val0) {
						if ( $("#repmetric option[value='" + val0 + "']").length == 0) {
							try {
								var ttext = (urlItems[val0][2]) ? urlItems[val0][2] : urlItems[val0][0];
								$opt = $("<option />", {
									value: val0,
									text: ttext
								});
								$('#repmetric').append($opt);
							}
							catch(e) { }
						}
					});
					$('#repmetric').multipleSelect('refresh');
					$('#repmetric').multipleSelect('uncheckAll');
				} else {
					$('#repitem').multipleSelect("uncheckAll").multipleSelect("enable").multipleSelect("refresh");
					$('#repmetric').multipleSelect("disable").multipleSelect("refresh");
				}
			});

			var repHostChange = function() {
				repItem.host = $('#rephost').multipleSelect('getSelects');
				$opt = $("<option />", {
					value: $('#rephost :selected').data("platform"),
					text: $('#rephost :selected').data("platform")
				});
				$('#repsubsys').empty().append($opt);
				$('#repsubsys').multipleSelect('refresh');
				$('#repsubsys').multipleSelect('checkAll');
				$('#repmetric').empty().multipleSelect("enable");
				var ssys = $("#repsubsys option:selected").val();
				repItem.group = "VMWARE";
				repItem.subsys = ssys;
				$('#repmetric').empty();
				var metricGroup = "ITEMS";
				if (metrics[repItem.group][ssys][reptype][metricGroup][ssys]) {
					$.each(metrics[repItem.group][ssys][reptype][metricGroup][ssys], function(idx, val0) {
						try {
							var ttext = urlItems[val0][2] ? urlItems[val0][2] : urlItems[val0][0];
							$opt = $("<option />", {
								value: val0,
								text: ttext
							});
							$('#repmetric').append($opt);
						}
						catch (e) {}
					});
				}
				$('#repmetric').multipleSelect('refresh');
				$('#repmetric').multipleSelect('uncheckAll');
			};
			$('#vcenter').multipleSelect({
				filter: true,
				single: true,
				allSelected: false,
				onClick: function(view) {
					repItem.vcenter = view.value;
					$('#repsubsys').empty().multipleSelect('enable');
					$.each(myfleet[repItem.vcenter].subsys, function(sskey, ssval) {
						var $opt = $("<option />", {
							value: ssval.value,
							text: ssval.text
						});
						$('#repsubsys').append($opt);
					});
					$('#repsubsys').multipleSelect('uncheckAll').multipleSelect('refresh');
					$('#rephost').empty().multipleSelect('disable').multipleSelect('refresh');
					$('#repitem').empty().multipleSelect("disable").multipleSelect('refresh');
					$('#repmetric').empty().multipleSelect("disable").multipleSelect('refresh');
				}
			});

			var subsysChange = function(view) {
				var inventory;
				var metricGroup = "ITEMS";
				var ssys = view.value;
				repItem.subsys = ssys;
				var single = (view.value != "CLUSTER");  // use multiple select for cluster totals
				repHostDef(single);
				$('#rephost').multipleSelect("enable");
				$('#repitem').empty().multipleSelect("disable").multipleSelect('refresh');
				$('#repmetric').empty().multipleSelect("disable").multipleSelect('refresh');
				$('#entiresubsys').prop("checked", false).checkboxradio("refresh");
				$('#entiresubsys').checkboxradio("disable");
				if (view.value == "DATASTORE") {
					$("label[for='rephost'").text("Datacenter");
					inventory = "DATACENTER";
				} else {
					$("label[for='rephost'").text("Cluster");
					inventory = "CLUSTER";
				}
				$.each(myfleet[repItem.vcenter].inventory[inventory], function(key, val) {
					var $opt = $("<option />", {
						value: key,
						text: key
					});
					$('#rephost').append($opt);
				});
				$('#rephost').multipleSelect('refresh').multipleSelect('uncheckAll');
			};
			$('#repsubsys').multipleSelect({
				filter: false,
				single: true,
				selectAll: false,
				maxHeight: 200,
				allSelected: false,
				onClick: function(view) {
					subsysChange(view);
				}
			}, "disable");

			var itemChange = function() {
				repItem.name = $('#repitem').multipleSelect('getSelects');
				$("#button-ok").button("disable");
				$('#repmetric').empty().multipleSelect("enable");
				var ssys = repItem.subsys;
				if (ssys == "VM") {
					repItem.namelabel = $('#repitem').multipleSelect('getSelects', 'text');
				}
				var metricGroup = "ITEMS";
				var items = $('#repitem').multipleSelect('getSelects');
				$.each(items, function(idx, item) {
					$.each(metrics[repItem.group][ssys][reptype][metricGroup], function(idx, val0) {
						if ( $("#repmetric option[value='" + val0 + "']").length == 0) {
							try {
								var ttext = (urlItems[val0][2]) ? urlItems[val0][2] : urlItems[val0][0];
								$opt = $("<option />", {
									value: val0,
									text: ttext
								});
								$('#repmetric').append($opt);
							}
							catch(e) { }
						}
					});
				});
				$('#repmetric').multipleSelect('refresh');
				$('#repmetric').multipleSelect('uncheckAll');
			};

			$('#repitem').multipleSelect({
				filter: true,
				single: false,
				maxHeight: 200,
				onClick: function() {
					itemChange();
				},
				onCheckAll: function() {
					itemChange();
				},
				onUncheckAll: function() {
					repItem.name = [];
					$("#button-ok").button("disable");
					$('#repmetric').empty().multipleSelect("disable");
				}
			}).multipleSelect("disable");
			$('#repmetric').multipleSelect({
				maxHeight: 200,
				disabled: true,
				single: false,
				onClick: function(view) {
					repItem.metrics = $('#repmetric').multipleSelect('getSelects');
					if (repItem.metrics.length) {
						$("#button-ok").button("enable");
					} else {
						$("#button-ok").button("disable");
					}
				},
				onCheckAll: function(view) {
					repItem.metrics = $('#repmetric').multipleSelect('getSelects');
					$("#button-ok").button("enable");
				},
				onUncheckAll: function(view) {
					repItem.metrics = $('#repmetric').multipleSelect('getSelects');
					$("#button-ok").button("disable");
				}
			}, "disable");
			if (reptype == "CSV") {
				$(".srate").show();
				$('#sample_rate').multipleSelect({
					onClick: function(view) {
						repItem.sample_rate = view.value;
						if ($('#repmetric').multipleSelect('getSelects').length) {
							$("#button-ok").button("enable");
						}
					},
					single: true,
				});
			}

			$.each(myfleet, function(key, val) {
				var $opt = $("<option />", {
					value: key,
					text: key,
					"data-platform": val.platform
				});
				$('#vcenter').append($opt);
			});
			$('#vcenter').multipleSelect('refresh').multipleSelect('uncheckAll');

			if (repItemIdx == undefined) {
				isNewItem = true;
				repItem = {host: "", subsys: "", name: "", metrics: [], group: "VMWARE"};
				repHostDef(true);
				$('#rephost').multipleSelect("disable");
			} else {
				repItem = repcfgusr.reports[report].items[repItemIdx];
				var single = (repItem.subsys != "CLUSTER");  // use multiple select for cluster totals
				repHostDef(single);
				$('#rephost').multipleSelect("enable");
				if (! jQuery.isArray( repItem.host )) {
					repItem.host = [repItem.host];
				}
				$('#vcenter').multipleSelect('setSelects', [repItem.vcenter]).multipleSelect('refresh');
				$.each(myfleet[repItem.vcenter].subsys, function(sskey, ssval) {
					var $opt = $("<option />", {
						value: ssval.value,
						text: ssval.text
					});
					$('#repsubsys').append($opt);
				});
				$('#repsubsys').multipleSelect('refresh').multipleSelect('setSelects', [repItem.subsys]).multipleSelect('enable');

				var inventory = repItem.subsys == "DATASTORE" ? "DATACENTER" : "CLUSTER";
				if (inventory == "DATACENTER") {
					$("label[for='rephost'").text("Datacenter");
				}
				$.each(myfleet[repItem.vcenter].inventory[inventory], function(key, val) {
					var $opt = $("<option />", {
						value: key,
						text: key
					});
					$('#rephost').append($opt);
				});
				$('#rephost').multipleSelect('refresh').multipleSelect('setSelects', repItem.host).multipleSelect('enable');
				if (repItem.subsys == "CLUSTER") {
				} else {
					$.each(repItem.host, function(idx, hostname) {
						$.each(myfleet[repItem.vcenter].inventory[inventory][repItem.host[0]][repItem.subsys], function(key, val) {
							var value = val.name;
							if (val.uuid) {
								value = val.uuid;
							}
							var $opt = $("<option />", {
								value: value,
								text: val.name
							});
							$('#repitem').append($opt);
						});
					});
					$('#entiresubsys').checkboxradio("enable");
					if (repItem.entiresubsys) {
						$('#entiresubsys').prop("checked", true).checkboxradio("refresh");
					} else {
						$('#repitem').multipleSelect('refresh').multipleSelect('setSelects', repItem.name).multipleSelect('enable');
					}
				}


				var metricGroup = "ITEMS";
				$.each(metrics[repItem.group][repItem.subsys][reptype][metricGroup], function(idx, val0) {
					if ( $("#repmetric option[value='" + val0 + "']").length == 0) {
						try {
							var ttext = (urlItems[val0][2]) ? urlItems[val0][2] : urlItems[val0][0];
							$opt = $("<option />", {
								value: val0,
								text: ttext
							});
							$('#repmetric').append($opt);
						}
						catch(e) { }
					}
				});

				$('#repmetric').multipleSelect('refresh').multipleSelect('setSelects', oldRepItem.metrics).multipleSelect('enable');
				if (repItem.sample_rate) {
					$('#sample_rate').multipleSelect('setSelects', [repItem.sample_rate]);
				}
			}
		},
		open: function() {
			$('.ui-widget-overlay').addClass('custom-overlay');
		},
		close: function() {
			$(this).dialog("destroy");
		}
	});

}

function repItemFormoVirt (repItemIdx) {
	var isNewItem = false,
	repItem,
	oldRepItem,
	report = $("#repname").val(),
	reptype = $("#format").val(),
	repItemFormDiv = '<div id="rep-item-form" class="repform"> \
	<form autocomplete="off"> \
	<fieldset style="float: left;"> \
	<label for="datacenter">Data Center</label> \
	<select class="multisel" type="text" name="datacenter" id="datacenter"></select> \
	<br style="clear: left;"> \
	<label for="repsubsys">Subsystem</label> \
	<select class="multisel" type="text" name="repsubsys" id="repsubsys"> \
	</select><br style="clear: left;"> \
	<label for="rephost">Cluster</label> \
	<select class="multisel" type="text" name="rephost" id="rephost"></select> \
	<!--label for="allhosts" class="cb">Always all</label> \
	<input type="checkbox" name="allhosts" id="allhosts" class="cb" "Select all available hosts"> \
	<div class="descr" title="This checkbox selects all clusters/datacnters existing at the time the report is being generated.<br> If you check <b>[Select all]</b>, report will contain only clusters/datacenters existing at the time the rule was created."></div--> \
	<br style="clear: left;"> \
	<label for="repitem">Item</label> \
	<select class="multisel" name="repitem" id="repitem"></select> \
	<label for="entiresubsys" class="cb">Always all</label> \
	<input type="checkbox" name="entiresubsys" id="entiresubsys" class="cb" "Select all available items"> \
	<div class="descr" title="This checkbox selects all existing items on given server(s) at the time the report is being generated.<br> If you check <b>[Select all]</b>, report will contain only items existing at the time the rule was created."></div> \
	<br style="clear: left;"> \
	<label for="repmetric">Metric</label> \
	<select class="multisel" name="repmetric" id="repmetric"> \
	</select><br style="clear: left;"> \
	</fieldset> \
	<!-- Allow form submission with keyboard without duplicating the dialog button --> \
	<input type="submit" tabindex="-1" style="position:absolute; top:-1000px; left: -1000px;"> \
	</form> \
	</div>';
	if (repItemIdx !== undefined) {
		oldRepItem = JSON.parse(JSON.stringify(itemList[repItemIdx]));
	}

	if (reptype != "CSV") {
		reptype = "IMG";
	}

	$( repItemFormDiv ).dialog({
		height: 480,
		width: 520,
		modal: true,
		title: "Reported item selection - " + curPlatform,
		dialogClass: "no-close-dialog",
		buttons: [
			{
				id: "button-ok",
				text: "Use this definition",
				click: function() {
					$(this).dialog('close');
					delete repItem.type;
					if (isNewItem) {
						itemList.push(repItem);
					} else {
						itemList[repItemIdx] = repItem;
					}
					$('#format').multipleSelect('disable');
					renderItemsTable(itemList);
				}
			},
			{
				id: "button-cancel",
				text: "Cancel",
				click: function() {
					if (oldRepItem) {
						itemList[repItemIdx] = JSON.parse(JSON.stringify(oldRepItem));
					}
					$(this).dialog('close');
				}
			},
		],
		create: function() {
			var isAdmin = false;
			var repForm = $(this).find( "form" ).on( "submit", function( event ) {
				event.preventDefault();
			//	SaveRepCfg();
			});
			curPlatform = "OVIRT";
			var myfleet = fleet[curPlatform];
			$("#button-ok").button("disable");
			$( "div.descr" ).tooltip ({
				position: {
					my: "right top",
					at: "right+5 top+20"
				},
				open: function(event, ui) {
					if (typeof(event.originalEvent) === 'undefined') {
						return false;
					}
					var $id = $(ui.tooltip).attr('id');
					// close any lingering tooltips
					$('div.ui-tooltip').not('#' + $id).remove();
					// ajax function to pull in data and add it to the tooltip goes here
				},
				close: function(event, ui) {
					ui.tooltip.hover(function() {
						$(this).stop(true).fadeTo(400, 1);
					},
					function() {
						$(this).fadeOut('400', function() {
							$(this).remove();
						});
					});
				},
				content: function () {
					return $(this).prop('title');
				}
			});
			$("#button-ok").button("disable");

			$('#entiresubsys').checkboxradio({
				disabled: true
			}).on("change", function () {
				repItem.entiresubsys = this.checked;
				repItem.name = [];
				if (this.checked) {
					$('#repitem').multipleSelect("uncheckAll").multipleSelect("disable").multipleSelect("refresh");
					$('#repmetric').empty().multipleSelect("enable");
					var ssys = $("#repsubsys option:selected").val();
					var metricGroup = "ITEMS";
					$.each(metrics[repItem.group][ssys][reptype][metricGroup], function(idx, val0) {
						if ( $("#repmetric option[value='" + val0 + "']").length == 0) {
							try {
								var ttext = (urlItems[val0][2]) ? urlItems[val0][2] : urlItems[val0][0];
								$opt = $("<option />", {
									value: val0,
									text: ttext
								});
								$('#repmetric').append($opt);
							}
							catch(e) { }
						}
					});
					$('#repmetric').multipleSelect('refresh');
					$('#repmetric').multipleSelect('uncheckAll');
				} else {
					$('#repitem').multipleSelect("uncheckAll").multipleSelect("enable").multipleSelect("refresh");
					$('#repmetric').multipleSelect("disable").multipleSelect("refresh");
				}
			});

			var repHostChange = function() {
				repItem.host = $('#rephost').multipleSelect('getSelects');
				$opt = $("<option />", {
					value: $('#rephost :selected').data("platform"),
					text: $('#rephost :selected').data("platform")
				});
				$('#repsubsys').empty().append($opt);
				$('#repsubsys').multipleSelect('refresh');
				$('#repsubsys').multipleSelect('checkAll');
				$('#repmetric').empty().multipleSelect("enable");
				var ssys = $("#repsubsys option:selected").val();
				repItem.group = "OVIRT";
				repItem.subsys = ssys;
				$('#repmetric').empty();
				var metricGroup = "ITEMS";
				if (metrics[repItem.group][ssys][reptype][metricGroup][ssys]) {
					$.each(metrics[repItem.group][ssys][reptype][metricGroup][ssys], function(idx, val0) {
						try {
							var ttext = urlItems[val0][2] ? urlItems[val0][2] : urlItems[val0][0];
							$opt = $("<option />", {
								value: val0,
								text: ttext
							});
							$('#repmetric').append($opt);
						}
						catch (e) {}
					});
				}
				$('#repmetric').multipleSelect('refresh');
				$('#repmetric').multipleSelect('uncheckAll');
			};
			$('#datacenter').multipleSelect({
				filter: true,
				single: true,
				allSelected: false,
				onClick: function(view) {
					repItem.datacenter = view.value;
					$('#repsubsys').empty().multipleSelect('enable');
					$.each(myfleet[repItem.datacenter].subsys, function(sskey, ssval) {
						var $opt = $("<option />", {
							value: ssval.value,
							text: ssval.text
						});
						if (reptype != "CSV" || ssval.value == "STORAGEDOMAIN" || ssval.value == "VM" || ssval.value == "DISK") {
							$('#repsubsys').append($opt);
						}
					});
					$('#repsubsys').multipleSelect('uncheckAll').multipleSelect('refresh');
					$('#rephost').empty().multipleSelect('disable').multipleSelect('refresh');
					$('#repitem').empty().multipleSelect("disable").multipleSelect('refresh');
					$('#repmetric').empty().multipleSelect("disable").multipleSelect('refresh');
				}
			});
			$('#rephost').multipleSelect({
				filter: true,
				single: true,
				selectAll: false,
				allSelected: false,
				onClick: function(view) {
					var hosts = [view.value];
					repItem.host = hosts;
					var metricGroup = "ITEMS";
					var ssys = repItem.subsys;
					var inventory = (ssys == "STORAGEDOMAIN" || ssys == "DISK") ? "STORAGEDOMAIN" : "CLUSTER";
					$("#button-ok").button("disable");
					if (ssys == "CLUSTER" || ssys == "STORAGEDOMAIN") {
						$('#repitem').empty().multipleSelect("disable");
						$('#entiresubsys').prop("checked", false).checkboxradio("refresh");
						$('#entiresubsys').checkboxradio("disable");
						$('#repmetric').empty().multipleSelect('enable');
						$.each(metrics[repItem.group][ssys][reptype][metricGroup], function(idx, val0) {
							if ( $("#repmetric option[value='" + val0 + "']").length == 0) {
								try {
									var ttext = (urlItems[val0][2]) ? urlItems[val0][2] : urlItems[val0][0];
									$opt = $("<option />", {
										value: val0,
										text: ttext
									});
									$('#repmetric').append($opt);
								}
								catch(e) { }
							}
						});
						$('#repmetric').multipleSelect('refresh').multipleSelect('uncheckAll');
					} else {
						$('#repitem').empty().multipleSelect("enable");
						$('#repmetric').empty().multipleSelect("disable").multipleSelect("refresh");
						$('#entiresubsys').prop("checked", false).checkboxradio("refresh");
						$('#entiresubsys').checkboxradio("enable");
						$.each(hosts, function(idx, hostname) {
							if (metrics[repItem.group][ssys][reptype][metricGroup]) {
								$.each(myfleet[repItem.datacenter].inventory[inventory][hostname][ssys], function(key, val) {
									var value = val.name;
									if (val.uuid) {
										value = val.uuid;
									}
									var $opt = $("<option />", {
										value: value,
										text: val.name
									});
									$('#repitem').append($opt);
								});
							}
						});
						$('#repitem').multipleSelect('uncheckAll').multipleSelect("refresh");
					}
				}
			}, "disable");

			var subsysChange = function(view) {
				var inventory;
				var metricGroup = "ITEMS";
				var ssys = view.value;
				repItem.subsys = ssys;
				$('#rephost').empty().multipleSelect('enable');
				$('#repitem').empty().multipleSelect("disable").multipleSelect('refresh');
				$('#repmetric').empty().multipleSelect("disable").multipleSelect('refresh');
				$('#entiresubsys').prop("checked", false).checkboxradio("refresh");
				$('#entiresubsys').checkboxradio("disable");
				if (view.value == "STORAGEDOMAIN" || ssys == "DISK") {
					$("label[for='rephost'").text("Domain");
					inventory = "STORAGEDOMAIN";
				} else {
					$("label[for='rephost'").text("Cluster");
					inventory = "CLUSTER";
				}
				$.each(myfleet[repItem.datacenter].inventory[inventory], function(key, val) {
					if (ssys != "DISK" || myfleet[repItem.datacenter].inventory[inventory][key].DISK) {
						var $opt = $("<option />", {
							value: key,
							text: val.label
						});
						$('#rephost').append($opt);
					}
				});
				$('#rephost').multipleSelect('refresh').multipleSelect('uncheckAll');
			};
			$('#repsubsys').multipleSelect({
				filter: false,
				single: true,
				selectAll: false,
				maxHeight: 200,
				allSelected: false,
				onClick: function(view) {
					subsysChange(view);
				}
			}, "disable");

			var itemChange = function() {
				repItem.name = $('#repitem').multipleSelect('getSelects');
				$("#button-ok").button("disable");
				$('#repmetric').empty().multipleSelect("enable");
				var ssys = repItem.subsys;
				if (ssys == "VM") {
					repItem.namelabel = $('#repitem').multipleSelect('getSelects', 'text');
				}
				var metricGroup = "ITEMS";
				var items = $('#repitem').multipleSelect('getSelects');
				$.each(items, function(idx, item) {
					$.each(metrics[repItem.group][ssys][reptype][metricGroup], function(idx, val0) {
						if ( $("#repmetric option[value='" + val0 + "']").length == 0) {
							try {
								var ttext = (urlItems[val0][2]) ? urlItems[val0][2] : urlItems[val0][0];
								$opt = $("<option />", {
									value: val0,
									text: ttext
								});
								$('#repmetric').append($opt);
							}
							catch(e) { }
						}
					});
				});
				$('#repmetric').multipleSelect('refresh');
				$('#repmetric').multipleSelect('uncheckAll');
			};

			$('#repitem').multipleSelect({
				filter: true,
				single: false,
				maxHeight: 200,
				onClick: function() {
					itemChange();
				},
				onCheckAll: function() {
					itemChange();
				},
				onUncheckAll: function() {
					repItem.name = [];
					$("#button-ok").button("disable");
					$('#repmetric').empty().multipleSelect("disable");
				}
			}).multipleSelect("disable");
			$('#repmetric').multipleSelect({
				maxHeight: 200,
				disabled: true,
				single: false,
				onClick: function(view) {
					repItem.metrics = $('#repmetric').multipleSelect('getSelects');
					if (repItem.metrics.length) {
						$("#button-ok").button("enable");
					} else {
						$("#button-ok").button("disable");
					}
				},
				onCheckAll: function(view) {
					repItem.metrics = $('#repmetric').multipleSelect('getSelects');
					$("#button-ok").button("enable");
				},
				onUncheckAll: function(view) {
					repItem.metrics = $('#repmetric').multipleSelect('getSelects');
					$("#button-ok").button("disable");
				}
			}, "disable");
			$.each(myfleet, function(key, val) {
				var $opt = $("<option />", {
					value: key,
					text: val.label
				});
				$('#datacenter').append($opt);
			});
			$('#datacenter').multipleSelect('refresh').multipleSelect('uncheckAll');

			if (repItemIdx == undefined) {
				isNewItem = true;
				repItem = {host: "", subsys: "", name: "", metrics: [], group: "OVIRT"};
			} else {
				repItem = repcfgusr.reports[report].items[repItemIdx];
				if (! jQuery.isArray( repItem.host )) {
					repItem.host = [repItem.host];
				}
				$('#datacenter').multipleSelect('setSelects', [repItem.datacenter]).multipleSelect('refresh');
				if (myfleet[repItem.datacenter]) {
					$.each(myfleet[repItem.datacenter].subsys, function(sskey, ssval) {
						var $opt = $("<option />", {
							value: ssval.value,
							text: ssval.text
						});
						if (reptype != "CSV" || ssval.value == "STORAGEDOMAIN" || ssval.value == "VM" || ssval.value == "DISK") {
							$('#repsubsys').append($opt);
						}
					});
					$('#repsubsys').multipleSelect('refresh').multipleSelect('setSelects', [repItem.subsys]).multipleSelect('enable');
				}

				var inventory = (repItem.subsys == "STORAGEDOMAIN" || repItem.subsys == "DISK") ? "STORAGEDOMAIN" : "CLUSTER";
				if (inventory == "STORAGEDOMAIN" || inventory == "DISK") {
					$("label[for='rephost'").text("Domain");
				}
				$.each(myfleet[repItem.datacenter].inventory[inventory], function(key, val) {
					var $opt = $("<option />", {
						value: key,
						text: val.label
					});
					$('#rephost').append($opt);
				});
				$('#rephost').multipleSelect('refresh').multipleSelect('setSelects', repItem.host).multipleSelect('enable');
				if (repItem.subsys == "CLUSTER" || repItem.subsys == "STORAGEDOMAIN") {
				} else {
					$.each(repItem.host, function(idx, hostname) {
						$.each(myfleet[repItem.datacenter].inventory[inventory][repItem.host[0]][repItem.subsys], function(key, val) {
							var value = val.name;
							if (val.uuid) {
								value = val.uuid;
							}
							var $opt = $("<option />", {
								value: value,
								text: val.name
							});
							$('#repitem').append($opt);
						});
					});
					$('#entiresubsys').checkboxradio("enable");
					if (repItem.entiresubsys) {
						$('#entiresubsys').prop("checked", true).checkboxradio("refresh");
					} else {
						$('#repitem').multipleSelect('refresh').multipleSelect('setSelects', repItem.name).multipleSelect('enable');
					}
				}


				var metricGroup = "ITEMS";
				$.each(metrics[repItem.group][repItem.subsys][reptype][metricGroup], function(idx, val0) {
					if ( $("#repmetric option[value='" + val0 + "']").length == 0) {
						try {
							var ttext = (urlItems[val0][2]) ? urlItems[val0][2] : urlItems[val0][0];
							$opt = $("<option />", {
								value: val0,
								text: ttext
							});
							$('#repmetric').append($opt);
						}
						catch(e) { }
					}
				});

				$('#repmetric').multipleSelect('refresh').multipleSelect('setSelects', oldRepItem.metrics).multipleSelect('enable');
			}
		},
		open: function() {
			$('.ui-widget-overlay').addClass('custom-overlay');
		},
		close: function() {
			$(this).dialog("destroy");
		}
	});

}
function repItemFormSolaris (repItemIdx) {
	var isNewItem = false,
	repItem,
	oldRepItem,
	report = $("#repname").val(),
	reptype = $("#format").val(),
	repItemFormDiv = '<div id="rep-item-form" class="repform"> \
	<form autocomplete="off"> \
	<fieldset style="float: left;"> \
	<label for="repsubsys">Level</label> \
	<select class="multisel" type="text" name="repsubsys" id="repsubsys"> \
		<option value="TOTAL" selected>Total</option> \
		<option value="LDOM">LDOM / Global zone</option> \
		<option value="ZONE">Zone</option> \
	</select><br style="clear: left;"> \
	<label for="repitem">LDOM name</label> \
	<select class="multisel" type="text" name="repitem" id="repitem"></select> \
	<label for="entiresubsys" class="cb">Always all</label> \
	<input type="checkbox" name="entiresubsys" id="entiresubsys" class="cb" "Select all available LDOMs"> \
	<div class="descr" title="This checkbox selects all LDOMs existing at the time the report is being generated.<br> If you check <b>[Select all]</b>, report will contain only LDOMs existing at the time the rule was created."></div> \
	<br style="clear: left;"> \
	<label for="repzone">Zone name</label> \
	<select class="multisel" type="text" name="repzone" id="repzone"> \
	</select><br style="clear: left;"> \
	<label for="repmetric">Metric</label> \
	<select class="multisel" name="repmetric" id="repmetric"> \
	</select><br style="clear: left;"> \
	<label class="srate" for="sample_rate" style="display: none">Sample rate</label> \
	<select class="multisel srate" name="sample_rate" id="sample_rate" multiple style="width: 7em; display: none"> \
		<option value="60" selected>1 minute</option> \
		<option value="300">5 minutes</option> \
		<option value="3600">1 hour</option> \
		<option value="18000">5 hours</option> \
		<option value="86400">1 day</option> \
	</select><br style="clear: left;"> \
	</fieldset> \
	<!-- Allow form submission with keyboard without duplicating the dialog button --> \
	<input type="submit" tabindex="-1" style="position:absolute; top:-1000px; left: -1000px;"> \
	</form> \
	</div>';
	if (repItemIdx !== undefined) {
		oldRepItem = JSON.parse(JSON.stringify(itemList[repItemIdx]));
	}

	if (reptype != "CSV") {
		reptype = "IMG";
	}

	$( repItemFormDiv ).dialog({
		height: 480,
		width: 520,
		modal: true,
		title: "Reported item selection - " + curPlatform,
		dialogClass: "no-close-dialog",
		buttons: [
			{
				id: "button-ok",
				text: "Use this definition",
				click: function() {
					$(this).dialog('close');
					delete repItem.type;
					if (isNewItem) {
						itemList.push(repItem);
					} else {
						itemList[repItemIdx] = repItem;
					}
					$('#format').multipleSelect('disable');
					renderItemsTable(itemList);
				}
			},
			{
				id: "button-cancel",
				text: "Cancel",
				click: function() {
					if (oldRepItem) {
						itemList[repItemIdx] = JSON.parse(JSON.stringify(oldRepItem));
					}
					$(this).dialog('close');
				}
			},
		],
		create: function() {
			var isAdmin = false;
			curPlatform = "SOLARIS";
			var myfleet = fleet[curPlatform];
			var repForm = $(this).find( "form" ).on( "submit", function( event ) {
				event.preventDefault();
			//	SaveRepCfg();
			});
			$("#button-ok").button("disable");
			$( "div.descr" ).tooltip ({
				position: {
					my: "right top",
					at: "right+5 top+20"
				},
				open: function(event, ui) {
					if (typeof(event.originalEvent) === 'undefined') {
						return false;
					}
					var $id = $(ui.tooltip).attr('id');
					// close any lingering tooltips
					$('div.ui-tooltip').not('#' + $id).remove();
					// ajax function to pull in data and add it to the tooltip goes here
				},
				close: function(event, ui) {
					ui.tooltip.hover(function() {
						$(this).stop(true).fadeTo(400, 1);
					},
					function() {
						$(this).fadeOut('400', function() {
							$(this).remove();
						});
					});
				},
				content: function () {
					return $(this).prop('title');
				}
			});

			$('#entiresubsys').checkboxradio().on("change", function () {
				repItem.entiresubsys = this.checked;
				repItem.group = curPlatform;
				repItemChange();
				if (this.checked) {
					$('#repitem').multipleSelect("uncheckAll").multipleSelect("disable");
					repItem.name = [];
					var metricGroup = "ITEMS";
					$('#repmetric').empty();
					if (metrics[repItem.group][repItem.subsys][reptype][metricGroup]) {
						$.each(metrics[repItem.group][repItem.subsys][reptype][metricGroup], function(idx, val0) {
							try {
								var ttext = urlItems[val0][2] ? urlItems[val0][2] : urlItems[val0][0];
								var $opt = $("<option />", {
									value: val0,
									text: ttext
								});
								$('#repmetric').append($opt);
							}
							catch (e) {}
						});
					}
					$('#repmetric').multipleSelect('refresh');
					$('#repmetric').multipleSelect("uncheckAll").multipleSelect("enable");
				} else {
					$('#repitem').multipleSelect("enable");
					$('#repmetric').multipleSelect("uncheckAll").multipleSelect("disable");
				}
			});

			var repItemChange = function() {
				repItem.name = $('#repitem').multipleSelect('getSelects');
				var ssys = $('#repsubsys').val();
				$('#repmetric').empty().multipleSelect("enable");
				repItem.group = "SOLARIS";
				repItem.subsys = ssys;
				var metricGroup = "ITEMS";
				if (metrics[repItem.group][ssys][reptype][metricGroup]) {
					$.each(metrics[repItem.group][ssys][reptype][metricGroup], function(idx, val0) {
						try {
							var ttext = urlItems[val0][2] ? urlItems[val0][2] : urlItems[val0][0];
							var $opt = $("<option />", {
								value: val0,
								text: ttext
							});
							$('#repmetric').append($opt);
						}
						catch (e) {}
					});
				}
				$('#repmetric').multipleSelect('refresh');
				$('#repmetric').multipleSelect('uncheckAll');
				if (ssys == "ZONE" && repItem.name) {
					var zonelist = [];
					$('#repzone').empty().multipleSelect("enable").multipleSelect('refresh');
					$.each(repItem.name, function(key, val) {
						var result = $.grep(myfleet.LDOM, function(e) {
							return e.name == val;
						});
						$.each(result[0].zones, function(key, val) {
							zonelist.push(val);
						});
					});
					zonelist = unique( zonelist );

					$.each(zonelist, function(key, val) {
						var $opt = $("<option />", {
							value: val,
							text: val
						});
						$('#repzone').append($opt);
					});
					$('#repzone').multipleSelect('refresh').multipleSelect('uncheckAll');
				} else {
					$('#repzone').multipleSelect("disable");
				}
			};
			var subsysChange = function(view) {
				repItem.group = "SOLARIS";
				var metricGroup = "ITEMS";
				var ssys = view.value;
				repItem.subsys = ssys;
				$('#repitem').empty().multipleSelect("enable").multipleSelect('refresh');
				$('#repmetric').empty().multipleSelect("refresh");
				if (ssys == "TOTAL") {
					$("label[for='repitem'").text("");
					$("label[for='repzone'").text("");
					$("#repitem").multipleSelect("disable");
					$("#repzone").empty().multipleSelect("refresh").multipleSelect("disable");
					$('#repmetric').multipleSelect("enable");
					$('#entiresubsys').prop("checked", false).checkboxradio("refresh");
					$('#entiresubsys').checkboxradio("disable");
					repItem.group = "SOLARIS";
					if (metrics[repItem.group][ssys][reptype][metricGroup]) {
						$.each(metrics[repItem.group][ssys][reptype][metricGroup], function(idx, val0) {
							try {
								var ttext = urlItems[val0][2] ? urlItems[val0][2] : urlItems[val0][0];
								$opt = $("<option />", {
									value: val0,
									text: ttext
								});
								$('#repmetric').append($opt);
							}
							catch (e) {}
						});
					}
					$('#repmetric').multipleSelect('refresh');
					$('#repmetric').multipleSelect('uncheckAll');
				} else {
					$("label[for='repitem'").text("LDOM name");
					$.each(myfleet.LDOM, function(key, val) {
						if (ssys != "ZONE" || val.zones) {
							var $opt = $("<option />", {
								value: val.name,
								text: val.name
							});
							$('#repitem').append($opt);
						}
					});
					$('#repitem').multipleSelect('refresh');
					if (! view.isNew) {
						$('#repitem').multipleSelect('uncheckAll');
					}
					if (ssys == "ZONE") {
						repItem.entiresubsys = false;
						$("label[for='repzone'").text("Zone name");
					} else {
						$('#entiresubsys').checkboxradio("enable");
						$("label[for='repzone'").text("");
						$("#repzone").empty().multipleSelect('refresh').multipleSelect("disable");
					}

					$('#repmetric').multipleSelect("disable");
				}
			};
			$('#repsubsys').multipleSelect({
				single: true,
				selectAll: false,
				maxHeight: 200,
				allSelected: false,
				onClick: function(view) {
					subsysChange(view);
				}
			}, 'uncheckAll');
			$('#repitem').multipleSelect({
				filter: true,
				single: false,
				onClick: function() {
					repItemChange();
				},
				onCheckAll:  function() {
					repItemChange();
				},
				onUncheckAll: function() {
					if (repItem) {
						repItem.name = [];
					}
					$('#repmetric').empty().multipleSelect("disable");
					$("#button-ok").button("disable");
				}
			}, "disable");
			$('#repzone').multipleSelect({
				filter: true,
				single: false,
				onClick: function() {
					repItem.zones = $('#repzone').multipleSelect('getSelects');
					if (repItem.zones) {
						$('#repmetric').multipleSelect("enable");
					}
					if ($('#repmetric').multipleSelect('getSelects').length) {
						$("#button-ok").button("enable");
					} else {
						$("#button-ok").button("disable");
					}
				},
				onCheckAll:  function() {
					$('#repmetric').multipleSelect("enable");
					repItem.zones = $('#repzone').multipleSelect('getSelects');
					if ($('#repmetric').multipleSelect('getSelects').length) {
						$("#button-ok").button("enable");
					} else {
						$("#button-ok").button("disable");
					}

				},
				onUncheckAll: function() {
					repItem.zones = [];
					$('#repmetric').multipleSelect("disable");
					$("#button-ok").button("disable");
				}
			}, "disable");
			$('#repmetric').multipleSelect({
				filter: false,
				maxHeight: 200,
				single: false,
				onClick: function(view) {
					repItem.metrics = $('#repmetric').multipleSelect('getSelects');
					if (repItem.metrics.length) {
						$("#button-ok").button("enable");
					} else {
						$("#button-ok").button("disable");
					}
				},
				onCheckAll: function(view) {
					repItem.metrics = $('#repmetric').multipleSelect('getSelects');
					$("#button-ok").button("enable");
				},
				onUncheckAll: function(view) {
					repItem.metrics = $('#repmetric').multipleSelect('getSelects');
					$("#button-ok").button("disable");
				}
			}, "disable");
			if (reptype == "CSV") {
				$(".srate").show();
				$('#sample_rate').multipleSelect({
					onClick: function(view) {
						repItem.sample_rate = view.value;
						if ($('#repmetric').multipleSelect('getSelects').length) {
							$("#button-ok").button("enable");
						}
					},
					single: true,
				});
			}
			if (repItemIdx == undefined) {
				isNewItem = true;
				repItem = {host: "", subsys: "", name: "", metrics: [], group: "SOLARIS"};
				$('#entiresubsys').checkboxradio("disable");
				// subsysChange();
			} else {
				repItem = repcfgusr.reports[report].items[repItemIdx];
				$('#repsubsys').multipleSelect('setSelects', [repItem.subsys]);
				subsysChange( {value: repItem.subsys, isNew: true} );

				if (! jQuery.isArray( repItem.name )) {
					repItem.name = [repItem.name];
				}
				if (repItem.subsys == "TOTAL") {
					$("label[for='repitem'").text("");
					$("label[for='repzone'").text("");
				} else {
					$("label[for='repitem'").text("LDOM name");
					$('#repitem').multipleSelect('setSelects', repItem.name);
					/*
					$.each(myfleet["LDOM"], function(key, val) {
						if (repItem.subsys != "ZONE" || val.zones) {
							var $opt = $("<option />", {
								value: val.name,
								text: val.name
							});
							$('#repitem').append($opt);
						}
					});
					*/
					if (repItem.subsys == "ZONE") {
						$("label[for='repzone'").text("Zone name");
						$('#repzone').multipleSelect("enable");
						$('#entiresubsys').checkboxradio("disable");
						var zonelist = [];
						$.each(repItem.name, function(key, val) {
							var result = $.grep(myfleet.LDOM, function(e) {
								return e.name == val;
							});
							$.each(result[0].zones, function(key, val) {
								zonelist.push(val);
							});
						});
						zonelist = jQuery.uniqueSort( zonelist );

						$.each(zonelist, function(key, val) {
							var $opt = $("<option />", {
								value: val,
								text: val
							});
							$('#repzone').append($opt);
						});
						$('#repzone').multipleSelect('refresh').multipleSelect('setSelects', repItem.zones);
					} else {
						$("label[for='repzone'").text("");
					}
					// $('#repitem').multipleSelect('refresh').multipleSelect('setSelects', repItem.name).multipleSelect("enable");

					if (repItem.entiresubsys) {
						$('#entiresubsys').prop("checked", true).checkboxradio("refresh");
						$('#repitem').multipleSelect("disable");
					} else {
						$('#repitem').multipleSelect('refresh').multipleSelect('setSelects', repItem.name).multipleSelect('enable');
					}
				}
				var metricGroup = "ITEMS";
				$('#repmetric').empty();
				if (metrics[repItem.group][repItem.subsys][reptype][metricGroup]) {
					$.each(metrics[repItem.group][repItem.subsys][reptype][metricGroup], function(idx, val0) {
						try {
							var ttext = urlItems[val0][2] ? urlItems[val0][2] : urlItems[val0][0];
							var $opt = $("<option />", {
								value: val0,
								text: ttext
							});
							$('#repmetric').append($opt);
						}
						catch (e) {}
					});
				}
				$('#repmetric').multipleSelect('refresh');
				$('#repmetric').multipleSelect('enable').multipleSelect('setSelects', oldRepItem.metrics);
			}
		},
		open: function() {
			$('.ui-widget-overlay').addClass('custom-overlay');
		},
		close: function() {
			$(this).dialog("destroy");
		}
	});

}

function repItemFormHyperV (repItemIdx) {
	var isNewItem = false,
	repItem,
	oldRepItem,
	report = $("#repname").val(),
	reptype = $("#format").val(),
	repItemFormDiv = '<div id="rep-item-form" class="repform"> \
	<form autocomplete="off"> \
	<fieldset style="float: left;"> \
	<label class="level1" for="replevel1">Top Level</label> \
	<select class="multisel level1" id="replevel1"> \
		<option value="DOMAIN">Domain (Workroup)</option> \
		<option value="CLUSTER">Cluster</option> \
	</select><br class="level1" style="clear: left;"> \
	<label class="level2" for="replevel2">Name</label> \
	<select class="multisel level2" id="replevel2"> \
	</select><br class="level2" style="clear: left;"> \
	<label class="level3" for="replevel3">Server</label> \
	<select class="multisel level3" id="replevel3"> \
	</select><br class="level3" style="clear: left;"> \
	<label class="level4" for="replevel4">Subsystem</label> \
	<select class="multisel level4" id="replevel4"> \
	</select><br class="level4" style="clear: left;"> \
	<label class="level5" for="replevel5">Items</label> \
	<select class="multisel level5" id="replevel5"> \
	</select><br class="level5" style="clear: left;"> \
	<label for="repmetric">Metric</label> \
	<select class="multisel" id="repmetric"> \
	</select><br style="clear: left;"> \
	<label class="srate" for="sample_rate" style="display: none">Sample rate</label> \
	<select class="multisel srate" name="sample_rate" id="sample_rate" multiple style="width: 7em; display: none"> \
		<option value="60" selected>1 minute</option> \
		<option value="300">5 minutes</option> \
		<option value="3600">1 hour</option> \
		<option value="18000">5 hours</option> \
		<option value="86400">1 day</option> \
	</select><br style="clear: left;"> \
	</fieldset> \
	<!-- Allow form submission with keyboard without duplicating the dialog button --> \
	<input type="submit" tabindex="-1" style="position:absolute; top:-1000px; left: -1000px;"> \
	</form> \
	</div>';
	if (repItemIdx !== undefined) {
		oldRepItem = JSON.parse(JSON.stringify(itemList[repItemIdx]));
	}

	if (reptype != "CSV") {
		reptype = "IMG";
	}

	$( repItemFormDiv ).dialog({
		height: 480,
		width: 520,
		modal: true,
		title: "Reported item selection - " + curPlatform,
		dialogClass: "no-close-dialog",
		buttons: [
			{
				id: "button-ok",
				text: "Use this definition",
				click: function() {
					$(this).dialog('close');
					delete repItem.type;
					if (isNewItem) {
						itemList.push(repItem);
					} else {
						itemList[repItemIdx] = repItem;
					}
					$('#format').multipleSelect('disable');
					renderItemsTable(itemList);
				}
			},
			{
				id: "button-cancel",
				text: "Cancel",
				click: function() {
					if (oldRepItem) {
						itemList[repItemIdx] = JSON.parse(JSON.stringify(oldRepItem));
					}
					$(this).dialog('close');
				}
			},
		],
		create: function() {
			var isAdmin = false;
			var repForm = $(this).find( "form" ).on( "submit", function( event ) {
				event.preventDefault();
			//	SaveRepCfg();
			});
			curPlatform = "HYPERV";
			var myfleet = fleet[curPlatform];
			$("#button-ok").button("disable");
			$( "div.descr" ).tooltip ({
				position: {
					my: "right top",
					at: "right+5 top+20"
				},
				open: function(event, ui) {
					if (typeof(event.originalEvent) === 'undefined') {
						return false;
					}
					var $id = $(ui.tooltip).attr('id');
					// close any lingering tooltips
					$('div.ui-tooltip').not('#' + $id).remove();
					// ajax function to pull in data and add it to the tooltip goes here
				},
				close: function(event, ui) {
					ui.tooltip.hover(function() {
						$(this).stop(true).fadeTo(400, 1);
					},
					function() {
						$(this).fadeOut('400', function() {
							$(this).remove();
						});
					});
				},
				content: function () {
					return $(this).prop('title');
				}
			});
			$("#button-ok").button("disable");

			var repLevel1Change = function(value) {
				repItem.level = value;
				if (value == "CLUSTER") {
					$(".level2, .level4, .level5").hide();
					$(".level3:not(#replevel3)").show();
					$("label[for='replevel3'").text("Name");
					$('#replevel3').empty().multipleSelect('enable');
					$.each(myfleet[value], function(key, val) {
						var $opt = $("<option />", {
							value: key,
							text: key
						});
						$('#replevel3').append($opt);
					});
					$('#replevel3').multipleSelect('refresh').multipleSelect('uncheckAll');
				} else {
					$(".level2:not(#replevel2)").show();
					$('#replevel2').empty().multipleSelect('enable');
					$.each(myfleet[value], function(key, val) {
						var $opt = $("<option />", {
							value: key,
							text: key
						});
						$('#replevel2').append($opt);
					});
					$('#replevel2').multipleSelect('refresh').multipleSelect('uncheckAll');
				}
			};

			$('#replevel1').multipleSelect({
				single: true,
				allSelected: false,
				onClick: function(view) {
					repLevel1Change(view.value);
				}
			}).multipleSelect("uncheckAll");

			var repLevel2Change = function(value) {
				if (value === undefined) {
					return;
				}
				repItem.domain = value;
				$("label[for='replevel3'").text("Server");
				$(".level3:not(#replevel3)").show();
				$('#replevel3').empty().multipleSelect('enable');
				$.each(myfleet[repItem.level][value], function(key, val) {
					var $opt = $("<option />", {
						value: Object.keys(val)[0],
						text: Object.keys(val)[0]
					});
					$('#replevel3').append($opt);
				});
				$('#replevel3').multipleSelect('refresh').multipleSelect('uncheckAll');
			};

			$('#replevel2').multipleSelect({
				single: true,
				allSelected: false,
				onClick: function(view) {
					repLevel2Change([view.value]);
				}
			}).multipleSelect("disable");

			var repLevel3Change = function(value) {
				if (value === undefined) {
					return;
				}
				repItem.host = value;
				$(".level4:not(#replevel4)").show();
				if ($('#replevel1').val() == "CLUSTER") {
					$('#replevel4').empty().append("<option value='CLUSTER'>Totals</option><option value='VM'>VM</option>");
				} else {
					$('#replevel4').empty().append("<option value='SERVER'>Server totals</option><option value='VM'>VM</option><option value='STORAGE'>Storage</option>");
				}
				$('#replevel4').multipleSelect('refresh').multipleSelect('enable').multipleSelect('uncheckAll');
				$("label[for='replevel4'").text("Subsystem");
			};

			$('#replevel3').multipleSelect({
				single: true,
				allSelected: false,
				onClick: function(view) {
					repLevel3Change([view.value]);
				}
			}).multipleSelect("disable");

			var repLevel4Change = function(value) {
				if (value === undefined) {
					return;
				}
				repItem.subsys = value;
				if (value == "CLUSTER" || value == "SERVER") {
					$(".level5").hide();
					$('#repmetric').empty().multipleSelect("enable");
					var metricGroup = "ITEMS";
					$.each(metrics.HYPERV[value][reptype][metricGroup], function(idx, val0) {
						try {
							var ttext = urlItems[val0][2] ? urlItems[val0][2] : urlItems[val0][0];
							$opt = $("<option />", {
								value: val0,
								text: ttext
							});
							$('#repmetric').append($opt);
						}
						catch (e) {}
					});
					$('#repmetric').multipleSelect('refresh').multipleSelect('uncheckAll');
				} else {
					$('#repmetric').multipleSelect('uncheckAll').multipleSelect("disable");
					$("label[for='replevel5'").text("Items");
					$(".level5:not(#replevel5)").show();
					$('#replevel5').empty().multipleSelect('enable');
					var selected;
					var host = $('#replevel3').val();

					if (repItem.level == "CLUSTER") {
						selected = [myfleet.CLUSTER];
					} else {
						var domain = $('#replevel2').val();
						if (domain && domain.length) {
							selected = $.grep(myfleet.DOMAIN[domain], function(e) {
								return Object.keys(e)[0] == host;
							});
						}
					}
					if (selected && selected[0] && host) {
						$.each(selected[0][host][value], function(key, val) {
							var $opt = $("<option />", {
								value: val,
								text: val
							});
							$('#replevel5').append($opt);
						});
						$('#replevel5').multipleSelect('refresh').multipleSelect('uncheckAll');
					}
					// $("label[for='replevel2'").text("Domain (workgroup)");
				}
			};

			$('#replevel4').multipleSelect({
				single: true,
				allSelected: false,
				onClick: function(view) {
					repLevel4Change(view.value);
				}
			}).multipleSelect("disable");

			var repLevel5Change = function() {
				repItem.name = $('#replevel5').multipleSelect('getSelects');
				$("#button-ok").button("disable");
				$('#repmetric').empty().multipleSelect("enable");
				var ssys = repItem.subsys;
				var metricGroup = "ITEMS";
				$.each(metrics[repItem.group][ssys][reptype][metricGroup], function(idx, val0) {
					try {
						var ttext = (urlItems[val0][2]) ? urlItems[val0][2] : urlItems[val0][0];
						$opt = $("<option />", {
							value: val0,
							text: ttext
						});
						$('#repmetric').append($opt);
					}
					catch(e) { }
				});
				$('#repmetric').multipleSelect('refresh');
				$('#repmetric').multipleSelect('uncheckAll');
			};

			$('#replevel5').multipleSelect({
				filter: true,
				single: false,
				maxHeight: 200,
				onClick: function() {
					repLevel5Change();
				},
				onCheckAll: function() {
					repLevel5Change();
				},
				onUncheckAll: function() {
					repItem.name = [];
					$("#button-ok").button("disable");
					$('#repmetric').empty().multipleSelect("disable");
				}
			}).multipleSelect("disable");

			$('#repmetric').multipleSelect({
				maxHeight: 200,
				disabled: true,
				single: false,
				onClick: function(view) {
					repItem.metrics = $('#repmetric').multipleSelect('getSelects');
					if (repItem.metrics.length) {
						$("#button-ok").button("enable");
					} else {
						$("#button-ok").button("disable");
					}
				},
				onCheckAll: function(view) {
					repItem.metrics = $('#repmetric').multipleSelect('getSelects');
					$("#button-ok").button("enable");
				},
				onUncheckAll: function(view) {
					repItem.metrics = $('#repmetric').multipleSelect('getSelects');
					$("#button-ok").button("disable");
				}
			}, "disable");
			if (reptype == "CSV") {
				$(".srate").show();
				$('#sample_rate').multipleSelect({
					onClick: function(view) {
						repItem.sample_rate = view.value;
						if ($('#repmetric').multipleSelect('getSelects').length) {
							$("#button-ok").button("enable");
						}
					},
					single: true,
				});
			}

			$(".level2, .level3, .level4, .level5").hide();
			if (repItemIdx == undefined) {
				isNewItem = true;
				repItem = {host: "", subsys: "", name: "", metrics: [], group: "HYPERV"};
			} else {
				repItem = repcfgusr.reports[report].items[repItemIdx];
				$('#replevel1').multipleSelect('setSelects', [repItem.level]);
				repLevel1Change(repItem.level);
				$('#replevel2').multipleSelect('setSelects', repItem.domain);
				repLevel2Change(repItem.domain);
				$('#replevel3').multipleSelect('setSelects', repItem.host);
				repLevel3Change(repItem.host);
				$('#replevel4').multipleSelect('setSelects', [repItem.subsys]);
				repLevel4Change(repItem.subsys);
				if (oldRepItem.name.length) {
					repLevel5Change();
					$('#replevel5').multipleSelect('setSelects', oldRepItem.name);
				}

				// $('#repmetric').multipleSelect('setSelects', oldRepItem.metrics).multipleSelect('enable');
				$('#repmetric').multipleSelect('setSelects', oldRepItem.metrics);
			}
		},
		open: function() {
			$('.ui-widget-overlay').addClass('custom-overlay');
		},
		close: function() {
			$(this).dialog("destroy");
		}
	});

}

function repItemFormNutanix (repItemIdx) {
	var isNewItem = false,
	repItem,
	oldRepItem,
	report = $("#repname").val(),
	reptype = $("#format").val(),
	repItemFormDiv = '<div id="rep-item-form" class="repform"> \
	<form autocomplete="off"> \
	<fieldset style="float: left;"> \
	<label for="repcluster">Cluster</label> \
	<select class="multisel" type="text" name="repcluster" id="repcluster"></select> \
	<br style="clear: left;"> \
	<label for="repsubsys">Subsystem</label> \
	<select class="multisel" type="text" name="repsubsys" id="repsubsys"> \
	</select><br style="clear: left;"> \
	<label for="repitem">Item</label> \
	<select class="multisel" name="repitem" id="repitem"></select> \
	<br style="clear: left;"> \
	<!-- \
	<label for="entiresubsys" class="cb">Always all</label> \
	<input type="checkbox" name="entiresubsys" id="entiresubsys" class="cb" "Select all available items"> \
	<div class="descr" title="This checkbox selects all existing items on given server(s) at the time the report is being generated.<br> If you check <b>[Select all]</b>, report will contain only items existing at the time the rule was created."></div> \
	--> \
	<label for="repmetric">Metric</label> \
	<select class="multisel" name="repmetric" id="repmetric"> \
	</select><br style="clear: left;"> \
	</fieldset> \
	<!-- Allow form submission with keyboard without duplicating the dialog button --> \
	<input type="submit" tabindex="-1" style="position:absolute; top:-1000px; left: -1000px;"> \
	</form> \
	</div>';
	if (repItemIdx !== undefined) {
		oldRepItem = JSON.parse(JSON.stringify(itemList[repItemIdx]));
	}

	if (reptype != "CSV") {
		reptype = "IMG";
	}

	$( repItemFormDiv ).dialog({
		height: 480,
		width: 520,
		modal: true,
		title: "Reported item selection - " + curPlatform,
		dialogClass: "no-close-dialog",
		buttons: [
			{
				id: "button-ok",
				text: "Use this definition",
				click: function() {
					$(this).dialog('close');
					delete repItem.type;
					if (isNewItem) {
						itemList.push(repItem);
					} else {
						itemList[repItemIdx] = repItem;
					}
					$('#format').multipleSelect('disable');
					renderItemsTable(itemList);
				}
			},
			{
				id: "button-cancel",
				text: "Cancel",
				click: function() {
					if (oldRepItem) {
						itemList[repItemIdx] = JSON.parse(JSON.stringify(oldRepItem));
					}
					$(this).dialog('close');
				}
			},
		],
		create: function() {
			var isAdmin = false;
			var repForm = $(this).find( "form" ).on( "submit", function( event ) {
				event.preventDefault();
			//	SaveRepCfg();
			});
			curPlatform = "NUTANIX";
			var myfleet = fleet[curPlatform];
			$("#button-ok").button("disable");
			$( "div.descr" ).tooltip ({
				position: {
					my: "right top",
					at: "right+5 top+20"
				},
				open: function(event, ui) {
					if (typeof(event.originalEvent) === 'undefined') {
						return false;
					}
					var $id = $(ui.tooltip).attr('id');
					// close any lingering tooltips
					$('div.ui-tooltip').not('#' + $id).remove();
					// ajax function to pull in data and add it to the tooltip goes here
				},
				close: function(event, ui) {
					ui.tooltip.hover(function() {
						$(this).stop(true).fadeTo(400, 1);
					},
					function() {
						$(this).fadeOut('400', function() {
							$(this).remove();
						});
					});
				},
				content: function () {
					return $(this).prop('title');
				}
			});
			$("#button-ok").button("disable");

			$('#repcluster').multipleSelect({
				filter: true,
				single: true,
				selectAll: false,
				allSelected: false,
				onClick: function(view) {
					var hosts = [view.value];
					repItem.host = hosts;
					repItem.clusteruuid = view.value;
					$('#repsubsys').empty().multipleSelect('enable');
					$.each(myfleet[view.value].subsys, function(sskey, ssval) {
						var $opt = $("<option />", {
							value: ssval.value,
							text: ssval.text
						});
						$('#repsubsys').append($opt);
					});
					$('#repsubsys').multipleSelect('uncheckAll').multipleSelect('refresh');
					$("#button-ok").button("disable");
					$('#repmetric').empty().multipleSelect("disable");
					$('#entiresubsys').prop("checked", false).checkboxradio("refresh");
					$('#entiresubsys').checkboxradio("enable");
				}
			}).multipleSelect("disable");

			var subsysChange = function(view) {
				var metricGroup = "ITEMS";
				var ssys = view.value;
				var clusters = $('#repcluster').multipleSelect('getSelects');
				repItem.subsys = ssys;
				$('#repitem').empty().multipleSelect("disable");
				$('#repmetric').empty().multipleSelect("disable").multipleSelect('refresh');
				$('#entiresubsys').prop("checked", false).checkboxradio("refresh");
				$('#entiresubsys').checkboxradio("disable");
				if (ssys == "SERVERTOTALS" || ssys == "STORAGETOTALS" || ssys == "VMTOTALS") {
					$('#repmetric').empty().multipleSelect("enable");
					var ssys = repItem.subsys;
					var metricGroup = "ITEMS";
					var items = $('#repitem').multipleSelect('getSelects');
					$.each(metrics[repItem.group][ssys][reptype][metricGroup], function(idx, val0) {
						if ( $("#repmetric option[value='" + val0 + "']").length == 0) {
							try {
								var ttext = (urlItems[val0][2]) ? urlItems[val0][2] : urlItems[val0][0];
								$opt = $("<option />", {
									value: val0,
									text: ttext
								});
								$('#repmetric').append($opt);
							}
							catch(e) { }
						}
					});
					$('#repmetric').multipleSelect('refresh');
					$('#repmetric').multipleSelect('uncheckAll');
				} else {
					$.each(clusters, function(idx, hostname) {
						$.each(myfleet[hostname].inventory[ssys], function(key, val) {
							var value = val.name;
							if (val.uuid) {
								value = val.uuid;
							}
							var $opt = $("<option />", {
								value: value,
								text: val.name
							});
							$('#repitem').append($opt);
						});
					});
					$('#repitem').multipleSelect('uncheckAll').multipleSelect("refresh");
				}
			};
			$('#repsubsys').multipleSelect({
				filter: false,
				single: true,
				selectAll: false,
				maxHeight: 200,
				allSelected: false,
				onClick: function(view) {
					subsysChange(view);
				}
			}).multipleSelect("disable");

			var itemChange = function() {
				repItem.name = $('#repitem').multipleSelect('getSelects');
				$("#button-ok").button("disable");
				$('#repmetric').empty().multipleSelect("enable");
				var ssys = repItem.subsys;
				var metricGroup = "ITEMS";
				var items = $('#repitem').multipleSelect('getSelects');
				$.each(items, function(idx, item) {
					$.each(metrics[repItem.group][ssys][reptype][metricGroup], function(idx, val0) {
						if ( $("#repmetric option[value='" + val0 + "']").length == 0) {
							try {
								var ttext = (urlItems[val0][2]) ? urlItems[val0][2] : urlItems[val0][0];
								$opt = $("<option />", {
									value: val0,
									text: ttext
								});
								$('#repmetric').append($opt);
							}
							catch(e) { }
						}
					});
				});
				$('#repmetric').multipleSelect('refresh');
				$('#repmetric').multipleSelect('uncheckAll');
			};

			$('#repitem').multipleSelect({
				filter: true,
				single: false,
				maxHeight: 200,
				onClick: function() {
					itemChange();
				},
				onCheckAll: function() {
					itemChange();
				},
				onUncheckAll: function() {
					repItem.name = [];
					$("#button-ok").button("disable");
					$('#repmetric').empty().multipleSelect("disable");
				}
			}).multipleSelect("disable");
			$('#repmetric').multipleSelect({
				maxHeight: 200,
				disabled: true,
				single: false,
				onClick: function(view) {
					repItem.metrics = $('#repmetric').multipleSelect('getSelects');
					if (repItem.metrics.length) {
						$("#button-ok").button("enable");
					} else {
						$("#button-ok").button("disable");
					}
				},
				onCheckAll: function(view) {
					repItem.metrics = $('#repmetric').multipleSelect('getSelects');
					$("#button-ok").button("enable");
				},
				onUncheckAll: function(view) {
					repItem.metrics = $('#repmetric').multipleSelect('getSelects');
					$("#button-ok").button("disable");
				}
			}).multipleSelect("disable");
			$.each(myfleet, function(key, val) {
				var $opt = $("<option />", {
					value: key,
					text: val.label
				});
				$('#repcluster').append($opt);
			});
			$('#repcluster').multipleSelect('refresh').multipleSelect('uncheckAll');

			if (repItemIdx == undefined) {
				isNewItem = true;
				repItem = {host: "", subsys: "", name: "", metrics: [], group: "NUTANIX"};
			} else {
				repItem = repcfgusr.reports[report].items[repItemIdx];
				if (! jQuery.isArray( repItem.host )) {
					repItem.host = [repItem.host];
				}
				$('#repcluster').multipleSelect('refresh').multipleSelect('setSelects', [repItem.clusteruuid]).multipleSelect('enable');


				$.each(myfleet[repItem.clusteruuid].subsys, function(sskey, ssval) {
					var $opt = $("<option />", {
						value: ssval.value,
						text: ssval.text
					});
					$('#repsubsys').append($opt);
				});
				$('#repsubsys').multipleSelect('enable').multipleSelect('refresh');
				if (repItem.subsys == "SERVERTOTALS" || repItem.subsys == "STORAGETOTALS" || repItem.subsys == "VMTOTALS") {
				} else {
					$.each(myfleet[repItem.clusteruuid].inventory[repItem.subsys], function(key, val) {
						var value = val.name;
						if (val.uuid) {
							value = val.uuid;
						}
						var $opt = $("<option />", {
							value: value,
							text: val.name
						});
						$('#repitem').append($opt);
					});
					$('#repitem').multipleSelect('refresh').multipleSelect('setSelects', repItem.name).multipleSelect('enable');
				}

				var metricGroup = "ITEMS";
				$.each(metrics[repItem.group][repItem.subsys][reptype][metricGroup], function(idx, val0) {
					if ( $("#repmetric option[value='" + val0 + "']").length == 0) {
						try {
							var ttext = (urlItems[val0][2]) ? urlItems[val0][2] : urlItems[val0][0];
							$opt = $("<option />", {
								value: val0,
								text: ttext
							});
							$('#repmetric').append($opt);
						}
						catch(e) { }
					}
				});

				$('#repmetric').multipleSelect('refresh').multipleSelect('setSelects', oldRepItem.metrics).multipleSelect('enable');
			}
		},
		open: function() {
			$('.ui-widget-overlay').addClass('custom-overlay');
		},
		close: function() {
			$(this).dialog("destroy");
		}
	});
}

function repItemFormTop (repItemIdx) {
	var isNewItem = false,
	repItem,
	oldRepItem,
	report = $("#repname").val(),
	reptype = $("#format").val(),
	repItemFormDiv = '<div id="rep-item-form" class="repform"> \
	<form autocomplete="off"> \
	<fieldset style="float: left;"> \
	<label for="platform">Platform</label> \
	<select class="multisel" type="text" id="platform"> \
		<option value="POWER">IBM Power Systems</option> \
		<option value="VMWARE">VMWare</option> \
	</select><br style="clear: left;"> \
	<label for="level">Level</label> \
	<select class="multisel" type="text" id="level"> \
		<option value="global">Global</option> \
		<option value="server">Server/vCenter</option> \
	</select><br style="clear: left;"> \
	<label for="source">Source</label> \
	<select class="multisel" name="source" id="source"> \
	</select><br style="clear: left;"> \
	<label class="srate" for="toptimerange">Time range</label> \
	<select class="multisel" id="toptimerange" style="width: 9em"> \
		<option value="day">last day</option> \
		<option value="week">last 7 days</option> \
		<option value="month">last 31 days</option> \
		<option value="year">last 365 days</option> \
	</select><br style="clear: left;"> \
	<label for="repmetric">Metric</label> \
	<select class="multisel" name="repmetric" id="repmetric"> \
	</select><br style="clear: left;"> \
	<label for="topcount">Top (n)</label> \
	<input type="number" value="10" id="topcount" style="width: 4em" title="" /><br> \
	</fieldset> \
	<!-- Allow form submission with keyboard without duplicating the dialog button --> \
	<input type="submit" tabindex="-1" style="position:absolute; top:-1000px; left: -1000px;"> \
	</form> \
	</div>';
	var topTimeRangeSt = "enable";
	var topTimeRangeVal;
	if (repItemIdx !== undefined) {
		oldRepItem = JSON.parse(JSON.stringify(itemList[repItemIdx]));
		if (repItemIdx > 0) {
			topTimeRangeSt = "disable";
			topTimeRangeVal = itemList[0].toptimerange;
		}
	} else if (itemList.length) {
		topTimeRangeSt = "disable";
		topTimeRangeVal = itemList[0].toptimerange;
	}

	if (reptype != "CSV") {
		reptype = "IMG";
	}

	$( repItemFormDiv ).dialog({
		height: 380,
		width: 420,
		modal: true,
		title: "Reported item selection - " + curPlatform,
		dialogClass: "no-close-dialog",
		buttons: [
			{
				id: "button-ok",
				text: "Use this definition",
				click: function() {
					$(this).dialog('close');
					delete repItem.type;
					if (topTimeRangeSt == "disable") {
						repItem.toptimerange = topTimeRangeVal;
					}
					if (isNewItem) {
						itemList.push(repItem);
					} else {
						itemList[repItemIdx] = repItem;
					}
					$('#format').multipleSelect('disable');
					renderItemsTable(itemList);
				}
			},
			{
				id: "button-cancel",
				text: "Cancel",
				click: function() {
					if (oldRepItem) {
						itemList[repItemIdx] = JSON.parse(JSON.stringify(oldRepItem));
					}
					$(this).dialog('close');
				}
			},
		],
		create: function() {
			var isAdmin = false;
			var repForm = $(this).find( "form" ).on( "submit", function( event ) {
				event.preventDefault();
			//	SaveRepCfg();
			});

			$('#platform').multipleSelect({
				filter: false,
				single: true,
				onClick: function(view) {
					repItem.host = [view.value];
					$('#level').multipleSelect("enable");
					$('#source').empty().multipleSelect('uncheckAll').multipleSelect("disable");
					var metrics = "";
					if (view.value == "POWER") {
						metrics = '<option value="rep_cpu">CPU load</option><option value="rep_saniops">SAN IOPS</option><option value="rep_san">SAN</option><option value="rep_lan">LAN</option>';
					} else {
						metrics = '<option value="rep_cpu">CPU load</option><option value="rep_iops">IOPS</option><option value="rep_disk">DISK</option><option value="rep_lan">LAN</option>';
					}
					$('#repmetric').empty().append(metrics).multipleSelect('refresh').multipleSelect("uncheckAll").multipleSelect('disable');
				}
			});
			$('#level').multipleSelect({
				filter: false,
				single: true,
				onClick: function(view) {
					repItem.subsys = view.value;
					if (view.value == "server") {
						$('#source').empty().multipleSelect("enable");
						$.each(fleet[$('#platform').val()], function(key, val) {
							var $opt = $("<option />", {
								value: key,
								text: key,
								"data-platform": val.platform
							});
							$('#source').append($opt);
						});
						$('#source').multipleSelect('refresh').multipleSelect('uncheckAll');
					} else {
						$('#source').multipleSelect("uncheckAll").multipleSelect("disable");
						$('#toptimerange').multipleSelect(topTimeRangeSt);
						if (topTimeRangeSt == "disable") {
							$('#repmetric').multipleSelect('enable');
						}
					}
				}
			}, "disable");
			$('#source').multipleSelect({
				filter: true,
				single: false,
				maxHeight: 200,
				onClick: function(view) {
					repItem.name = $('#source').multipleSelect('getSelects');
					if (repItem.name.length) {
						$('#toptimerange').multipleSelect(topTimeRangeSt);
						if (topTimeRangeSt == "disable") {
							$('#repmetric').multipleSelect('enable');
						}
					} else {
						$('#toptimerange').multipleSelect("disable");
						$("#button-ok").button("disable");
					}
				},
				onCheckAll: function(view) {
					repItem.name = $('#source').multipleSelect('getSelects');
					//repItem.metrics = $('#repmetric').multipleSelect('getSelects');
					$('#toptimerange').multipleSelect(topTimeRangeSt);
					if (topTimeRangeSt == "disable") {
						$('#repmetric').multipleSelect('enable');
					}
				},
				onUncheckAll: function(view) {
					repItem.name = $('#source').multipleSelect('getSelects');
					//repItem.metrics = $('#repmetric').multipleSelect('getSelects');
					$('#toptimerange').multipleSelect("disable");
					$("#button-ok").button("disable");
				}
			}, "disable");
			$('#toptimerange').multipleSelect({
				filter: false,
				single: true,
				maxHeight: 200,
				disabled: true,
				onClick: function(view) {
					repItem.toptimerange = view.value;
					$('#repmetric').multipleSelect('enable');
				}
			}).multipleSelect("disable");
			$('#repmetric').multipleSelect({
				maxHeight: 200,
				disabled: true,
				single: false,
				onClick: function(view) {
					repItem.metrics = $('#repmetric').multipleSelect('getSelects');
					if (repItem.metrics.length) {
						$("#button-ok").button("enable");
					} else {
						$("#button-ok").button("disable");
					}
				},
				onCheckAll: function(view) {
					repItem.metrics = $('#repmetric').multipleSelect('getSelects');
					$("#button-ok").button("enable");
				},
				onUncheckAll: function(view) {
					repItem.metrics = $('#repmetric').multipleSelect('getSelects');
					$("#button-ok").button("disable");
				}
			}).multipleSelect("disable");

			$('#topcount').on("change paste keyup", function() {
				repItem.topcount = parseInt($(this).val());
				if (repItem.topcount > 0 ) {
					$("#button-ok").button("enable");
				} else {
					$("#button-ok").button("disable");
				}
			});

			if (repItemIdx == undefined) {
				isNewItem = true;
				repItem = {host: "", subsys: "", name: "", metrics: [], group: "TOP", topcount: 10};
				$('#rep-item-form select.multisel').multipleSelect('uncheckAll');
			} else {
				repItem = repcfgusr.reports[report].items[repItemIdx];
				$('#platform').multipleSelect('setSelects', repItem.host).multipleSelect('refresh');
				var metrics = "";
				if ($('#platform').val() == "POWER") {
					metrics = '<option value="rep_cpu">CPU load</option><option value="rep_saniops">SAN IOPS</option><option value="rep_san">SAN</option><option value="rep_lan">LAN</option>';
				} else {
					metrics = '<option value="rep_cpu">CPU load</option><option value="rep_iops">IOPS</option><option value="rep_disk">DISK</option><option value="rep_lan">LAN</option>';
				}
				$('#repmetric').append(metrics).multipleSelect('refresh').multipleSelect('setSelects', repItem.metrics);
				$('#level').multipleSelect('setSelects', [repItem.subsys]).multipleSelect('refresh');
				if ($('#level').val() == "server") {
					$('#source').multipleSelect("enable");
					$.each(fleet[$('#platform').val()], function(key, val) {
						var $opt = $("<option />", {
							value: key,
							text: key,
							"data-platform": val.platform
						});
						$('#source').append($opt);
					});
					$('#source').multipleSelect('refresh').multipleSelect('setSelects', repItem.name);
				}
				$('#topcount').val([repItem.topcount]);
				$('#rep-item-form select.multisel').multipleSelect('enable');
				$('#toptimerange').multipleSelect('setSelects', [repItem.toptimerange]).multipleSelect('refresh').multipleSelect(topTimeRangeSt);
				if (repItem.subsys == "global") {
					$('#source').multipleSelect('disable');
				}
				$("#button-ok").button("enable");
			}
			$("#button-ok").button("disable");
		},
		open: function() {
			$('.ui-widget-overlay').addClass('custom-overlay');
		},
		close: function() {
			$(this).dialog("destroy");
		}
	});

}

function repItemFormRCA (repItemIdx) {
	var isNewItem = false,
	repItem,
	oldRepItem,
	report = $("#repname").val(),
	reptype = $("#format").val(),
	repItemFormDiv = '<div id="rep-item-form" class="repform"> \
	<form autocomplete="off"> \
	<fieldset style="float: left;"> \
	<label for="platform">Platform</label> \
	<select class="multisel" type="text" id="platform"> \
		<option value="POWER">IBM Power Systems</option> \
		<option value="VMWARE">VMWare</option> \
	</select><br style="clear: left;"> \
	<label class="srate" for="toptimerange">Time range</label> \
	<select class="multisel" id="toptimerange" style="width: 9em"> \
		<option value="day">last day</option> \
		<option value="week">last 7 days</option> \
		<option value="month">last 31 days</option> \
	</select><br style="clear: left;"> \
	<label for="repmetric">Metric</label> \
	<select class="multisel" name="repmetric" id="repmetric"> \
	</select><br style="clear: left;"> \
	</fieldset> \
	<!-- Allow form submission with keyboard without duplicating the dialog button --> \
	<input type="submit" tabindex="-1" style="position:absolute; top:-1000px; left: -1000px;"> \
	</form> \
	</div>';
	if (repItemIdx !== undefined) {
		oldRepItem = JSON.parse(JSON.stringify(itemList[repItemIdx]));
	}

	if (reptype != "CSV") {
		reptype = "IMG";
	}

	$( repItemFormDiv ).dialog({
		height: 380,
		width: 420,
		modal: true,
		title: "Reported item selection - " + curPlatform,
		dialogClass: "no-close-dialog",
		buttons: [
			{
				id: "button-ok",
				text: "Use this definition",
				click: function() {
					$(this).dialog('close');
					delete repItem.type;
					if (isNewItem) {
						itemList.push(repItem);
					} else {
						itemList[repItemIdx] = repItem;
					}
					$('#format').multipleSelect('disable');
					renderItemsTable(itemList);
				}
			},
			{
				id: "button-cancel",
				text: "Cancel",
				click: function() {
					if (oldRepItem) {
						itemList[repItemIdx] = JSON.parse(JSON.stringify(oldRepItem));
					}
					$(this).dialog('close');
				}
			},
		],
		create: function() {
			var isAdmin = false;
			var repForm = $(this).find( "form" ).on( "submit", function( event ) {
				event.preventDefault();
			//	SaveRepCfg();
			});
			$('#platform').multipleSelect({
				filter: false,
				single: true,
				onClick: function(view) {
					repItem.host = [view.value];
					$('#toptimerange').multipleSelect("enable");
					$('#source').empty().multipleSelect('uncheckAll').multipleSelect("disable");
					var metrics = "";
					if (view.value == "POWER") {
						metrics = '<option value="rep_cpu">CPU load</option><option value="rep_mem">Memory</option>';
					} else {
						metrics = '<option value="rep_cpu">CPU load</option>';
					}
					$('#repmetric').empty().append(metrics).multipleSelect('refresh').multipleSelect('setSelects', repItem.metrics);
				}
			});
			$('#toptimerange').multipleSelect({
				filter: false,
				single: true,
				maxHeight: 200,
				disabled: true,
				onClick: function(view) {
					repItem.toptimerange = view.value;
					$('#repmetric').multipleSelect('enable');
				}
			}, "disable");
			$('#repmetric').multipleSelect({
				maxHeight: 200,
				disabled: true,
				single: false,
				onClick: function(view) {
					repItem.metrics = $('#repmetric').multipleSelect('getSelects');
					if (repItem.metrics.length) {
						$("#button-ok").button("enable");
					} else {
						$("#button-ok").button("disable");
					}
				},
				onCheckAll: function(view) {
					repItem.metrics = $('#repmetric').multipleSelect('getSelects');
					$("#button-ok").button("enable");
				},
				onUncheckAll: function(view) {
					repItem.metrics = $('#repmetric').multipleSelect('getSelects');
					$("#button-ok").button("disable");
				}
			}, "disable");

			$('#topcount').on("change paste keyup", function() {
				repItem.topcount = parseInt($(this).val());
				if (repItem.topcount > 0 ) {
					$("#button-ok").button("enable");
				} else {
					$("#button-ok").button("disable");
				}
			});

			if (repItemIdx == undefined) {
				isNewItem = true;
				repItem = {host: "", subsys: "", name: "", metrics: [], group: "RCA"};
				$('#rep-item-form select.multisel').multipleSelect('uncheckAll');
			} else {
				repItem = repcfgusr.reports[report].items[repItemIdx];
				$('#platform').multipleSelect('setSelects', repItem.host).multipleSelect('refresh');
				var metrics = "";
				if ($('#platform').val() == "power") {
					metrics = '<option value="rep_cpu">CPU load</option><option value="rep_mem">Memory</option>';
				} else {
					metrics = '<option value="rep_cpu">CPU load</option>';
				}
				$('#repmetric').append(metrics).multipleSelect('refresh').multipleSelect('setSelects', repItem.metrics);
				$('#level').multipleSelect('setSelects', [repItem.subsys]).multipleSelect('refresh');
				if ($('#level').val() == "server") {
					$('#source').multipleSelect("enable");
					$.each(fleet[$('#platform').val()], function(key, val) {
						var $opt = $("<option />", {
							value: key,
							text: key,
							"data-platform": val.platform
						});
						$('#source').append($opt);
					});
					$('#source').multipleSelect('refresh').multipleSelect('setSelects', repItem.name);
				}
				$('#toptimerange').multipleSelect('setSelects', [repItem.toptimerange]).multipleSelect('refresh');
				$('#topcount').val([repItem.topcount]);
				$('#rep-item-form select.multisel').multipleSelect('enable');
				if (repItem.subsys == "global") {
					$('#source').multipleSelect('disable');
				}
				$("#button-ok").button("enable");
			}
			$("#button-ok").button("disable");
		},
		open: function() {
			$('.ui-widget-overlay').addClass('custom-overlay');
		},
		close: function() {
			$(this).dialog("destroy");
		}
	});

}

function rrCreate () {
	var v = {},
	list,
	da = new Date();
	da.setHours(0,0,0,0);
	da.setDate(da.getDate() + 1);
	v.freq = Number($('#rrfreq').val()),
	v.dtstart = da;

	list = $('#byweekday').multipleSelect('getSelects');
	if (list.length) {
		v.byweekday = list.map(Number);
	}
	list = $('#bymonth').multipleSelect('getSelects');
	if (list.length) {
		v.bymonth = list.map(Number);
	}
	list = $('#bysetpos').val();
	if (list) {
		v.bysetpos = list.split(',').map(Number);
	}
	list = $('#bymonthday').val();
	if (list) {
		v.bymonthday = list.split(',').map(Number);
	}
	list = $('#byyearday').val();
	if (list) {
		v.byyearday = list.split(',').map(Number);
	}
	list = $('#byweekno').val();
	if (list) {
		v.byweekno = list.split(',').map(Number);
	}
	var rule = new RRule( v );
	return rule;
}

function rrToText (rrule) {
	var rr = RRule.fromString(rrule);
	return rr.toText();
}

function rrToString(rule) {
	var str = RRule.optionsToString({
		freq: rule.options.freq,
		bymonth: rule.options.bymonth,
		bymonthday: rule.options.bymonthday.concat(rule.options.bynmonthday),
		bysetpos: rule.options.bysetpos,
		byweekday: rule.options.byweekday,
		byweekno: rule.options.byweekno,
		byyearday: rule.options.byyearday
	});
	return str;
}

function listRRuleOccurs(rule) {
	var html = "",
	maxlines = 20;
	da = new Date();
	da.setHours(0,0,0,0);
	da.setDate(da.getDate() + 1);
	if (inXormon) {
		rule.options.dtstart = new Date();
	} else {
		rule.timeset[0].constructor(0,0,0,0);
	}
	rule.options.byhour = [0];
	rule.options.byminute = [0];
	rule.options.bysecond = [0];
	var lines = rule.all(function (date, i) {
		return i < maxlines;
	});
	$.each(lines, function (i, node) {
		html += node.toString().split(" (")[0] + "<br>";
	});
	return html;
}
function nextRuleRun(rrule) {
	var rr = RRule.fromString(rrule);
	var maxlines = 1;
	da = new Date();
	da.setHours(0,0,0,0);
	da.setDate(da.getDate() + 1);
	if (inXormon) {
		rr.options.dtstart = new Date();
	} else {
		rr.timeset[0].constructor(0,0,0,0);
	}
	rr.options.byhour = [0];
	rr.options.byminute = [0];
	rr.options.bysecond = [0];
	var lines = rr.all(function (date, i) {
		return i < maxlines;
	});
	return lines[0];
}

function renderItemsTable(items) {
	var html = "<table id='itemtable' class='cfgtree'><thead><tr><th>Edit</th><th>Clone</th><th>Delete</th><th>Source</th><th>Class</th><th>Subsystem</th><th>Name</th><th>Metric</th></tr></thead>";
	$.each(items, function (i, node) {
		html += "<tr>";
		html += "<td style='text-align: center'><a href='#' class='itemlink'><span class='ui-icon ui-icon-pencil'></span></a></td>";
		html += "<td style='text-align: center'><a href='#' class='itemclone'><span class='ui-icon ui-icon-copy'></span></a></td>";
		html += "<td style='text-align: center'><div class='delete' title='Delete item'></div></td>";
		var names = "";
		if (node.vmname && ! node.namelabel) {
			node.namelabel = node.vmname;
			delete node.vmname;
		}
		if (node.entiresubsys) {
			names = "ALL";
		} else if (node.namelabel) {
			names = node.namelabel.join(", ");
		} else if ((node.group == "VMWARE" || node.group == "OVIRT") && node.subsys == "CLUSTER") {
			names = "Cluster totals";
		} else if (node.name) {
			names = node.name.join(", ");
		}
		var tMetrics = jQuery.map( node.metrics, function( m ) {
			return ((urlItems[m][2]) ? urlItems[m][2] : urlItems[m][0]);
		});
		html += "<td>" + (node.allhosts ? "ALL" : node.host) + "</td><td class='itemclass'>" + node.group + "</td><td>" + node.subsys + "</td><td>" + names + "</td><td>" + tMetrics.join(", ") + "</td>";
		html += "</tr>";
	});
	html += "</table>";
	$("#itemtablediv").html(html);
	$("#itemtablediv div.delete").on("click", function(event) {
		event.preventDefault();
		var index = $(this).parents("tr").index();
		$.confirm(
			"Are you sure you want to remove this item?",
			"Item remove confirmation",
			function() { /* Ok action here*/
				// var grp = $(event.target).parent().parent().find(".grplink").text();
				// $(event.target).parent().parent().remove();
				// delete usercfg.groups[grp];
				itemList.splice(index, 1);
				renderItemsTable(itemList);
				if (! itemList.length) {
					$('#format').multipleSelect('enable');
				}
				// SaveRepCfg();
			}
		);
	});
	$("#itemtable a.itemclone").on("click", function(event) {
		event.preventDefault();
		var index = $(this).parents("tr").index();
		var line = JSON.parse(JSON.stringify(itemList[index]));
		itemList.splice(index, 0, line);
		renderItemsTable(itemList);
	});
	$("#itemtable a.itemlink").on("click", function(event) {
		event.preventDefault();
		var index = $(this).parents("tr").index(),
		iclass = $(this).parents("tr").find(".itemclass").text().toLowerCase();
		curPlatform = platforms[iclass].longname;
		if (iclass == "power") {
			repItemFormPower(index, function() {
				renderItemsTable(itemList);
			});
		} else if (iclass == "custom") {
			repItemFormCustom(index, function() {
				renderItemsTable(itemList);
			});
		} else if (iclass == "vmware") {
			repItemFormVmware(index, function() {
				renderItemsTable(itemList);
			});
		} else if (iclass == "ovirt") {
			repItemFormoVirt(index, function() {
				renderItemsTable(itemList);
			});
		} else if (iclass == "solaris") {
			repItemFormSolaris(index, function() {
				renderItemsTable(itemList);
			});
		} else if (iclass == "hyperv") {
			repItemFormHyperV(index, function() {
				renderItemsTable(itemList);
			});
		} else if (iclass == "nutanix") {
			repItemFormNutanix(index, function() {
				renderItemsTable(itemList);
			});
		} else if (iclass == "top") {
			repItemFormTop(index, function() {
				renderItemsTable(itemList);
			});
		} else if (iclass == "rca") {
			repItemFormRCA(index, function() {
				renderItemsTable(itemList);
			});
		}
	});
}

function newGroupFormStor () {
	var newGroupFormDiv = '<div id="new-group-form"> \
	<form autocomplete="off"> \
	<fieldset> \
	<label for="grpname">Group name</label> \
	<input type="text" name="grpname" id="grpname" autocomplete="off" /><br> \
	<label for="descr">Description</label> \
	<input type="text" name="descr" id="descr" autocomplete="off" /> \
	</fieldset> \
	<!-- Allow form submission with keyboard without duplicating the dialog button --> \
	<input type="submit" tabindex="-1" style="position:absolute; top:-1000px"> \
	</form> \
	</div>';
	$( newGroupFormDiv ).dialog({
		height: 250,
		width: 440,
		modal: true,
		title: "Edit mail group",
		buttons: {
			"Save group": function() {
				var grp = $("#grpname").val(),
					dsc = $("#descr").val();
				usercfg.groups[grp] = {description: dsc};
				SaveUsrCfg();
				$(this).dialog("close");
				$( "#side-menu" ).fancytree( "getTree" ).reactivate();
			},
			Cancel: function() {
				$(this).dialog("close");
			}
		},
		create: function() {
			$("#grpname").tooltipster({
				trigger: 'custom',
				position: 'right',
			});
			alertForm = $(this).find( "form" ).on( "submit", function( event ) {
				event.preventDefault();
				saveUser(user, true);
			});
			$("#grpname").on("blur", function( event ) {
				if (!event.relatedTarget || event.relatedTarget && event.relatedTarget.textContent != "Cancel") {
					if (! this.value) {
						$("#grpname").tooltipster('content', 'Group name is required').tooltipster('open');
						$(event.target).addClass( "ui-state-error" );
						$(event.target).trigger("focus");
					} else if (usercfg.groups[this.value]) {
						$("#grpname").tooltipster('content', 'Group already exists!').tooltipster('open');
						$(event.target).addClass( "ui-state-error" );
						$(event.target).trigger("focus");
					} else {
						$("#grpname").tooltipster("close");
						$(event.target).removeClass( "ui-state-error" );
					}
				}
			});
		},
		close: function() {
			$(this).find( "form" ).trigger('reset');
			$("#grpname").tooltipster("destroy");
			$(this).dialog("destroy");
		}
	});
}

function newRepGroupForm (grpToEdit) {
	var newRepGroupFormDiv = '<div id="new-rep-group-form"> \
	<form autocomplete="off"> \
	<fieldset> \
	<label for="grpname">Group name</label> \
	<input type="text" name="grpname" id="grpname" autocomplete="off" /><br> \
	<label for="descr">Description</label> \
	<input type="text" name="descr" id="descr" autocomplete="off" /><br> \
	<label for="emails">E-mails</label> \
	<input type="text" name="emails" id="emails" autocomplete="off" title="Space separated list of recepient e-mail addresses" /> \
	<label for="mailfrom">Mail from</label> \
	<input type="text" name="mailfrom" id="mailfrom" autocomplete="off" title="E-mail adddress to be used as a sender" /> \
	</fieldset> \
	<!-- Allow form submission with keyboard without duplicating the dialog button --> \
	<input type="submit" tabindex="-1" style="position:absolute; top:-1000px"> \
	</form> \
	</div>';
	$( newRepGroupFormDiv ).dialog({
		height: 290,
		width: 440,
		modal: true,
		title: "Edit group",
		buttons: {
			"Save & send test message": {
				click: function() {
					// save group first
					var grp = $("#grpname").val(),
					dsc = $("#descr").val(),
					emails = $("#emails").val().split(" "),
					mailfrom = $("#mailfrom").val();
					if (grpToEdit) {
						delete repcfgusr.groups[grpToEdit];
						if (grpToEdit != grp) {
							$.each(repcfgusr.reports, function(i1, rep) {
								var changeGrp = $.inArray(grpToEdit, rep.recipients);
								if (changeGrp > -1) {
									rep.recipients[changeGrp] = grp;
								}
							});
						}
					}
					repcfgusr.groups[grp] = {description: dsc, emails: emails, mailfrom: mailfrom};
					SaveRepCfg(false, function() {
						// now send test mail
						var postdata = {cmd: "mailtest", group: $("#grpname").val()};
						$.post( cgiPath + "/reporter.sh", postdata, function( data ) {
							$("<div>" + data.message + "</div>").dialog({
								dialogClass: "info",
								title: "Send test message - " + data.success ? "succeed" : "fail",
								minWidth: 600,
								modal: true,
								show: {
									effect: "fadeIn",
									duration: 500
								},
								hide: {
									effect: "fadeOut",
									duration: 200
								},
								open: function() {
									$('.ui-widget-overlay').addClass('custom-overlay');
								},
								buttons: {
									OK: function() {
										$(this).dialog("close");
									}
								}
							});
						});
					});
				},
				text: "Save & send test message",
				class: 'savecontrol'
			},
			"Save group": {
				click: function() {
					var grp = $("#grpname").val(),
					dsc = $("#descr").val(),
					emails = $("#emails").val().split(" "),
					mailfrom = $("#mailfrom").val();
					if (grpToEdit) {
						delete repcfgusr.groups[grpToEdit];
						if (grpToEdit != grp) {
							$.each(repcfgusr.reports, function(i1, rep) {
								var changeGrp = $.inArray(grpToEdit, rep.recipients);
								if (changeGrp > -1) {
									rep.recipients[changeGrp] = grp;
								}
							});
						}
					}
					repcfgusr.groups[grp] = {description: dsc, emails: emails, mailfrom: mailfrom};
					SaveRepCfg(true);
					$(this).dialog("close");
					if (!inXormon) {
						$( "#side-menu" ).fancytree( "getTree" ).reactivate();
					}
				},
				text: "Save group",
				class: 'savecontrol'
			},
			Cancel: function() {
				$(this).dialog("close");
			}
		},
		create: function() {
			if (!grpToEdit) {
				$("button.savecontrol").button("disable");
			}
			$("#grpname").tooltipster({
				trigger: 'custom',
				position: 'right',
			});
			$("#mailfrom, #emails").tooltipster({
				trigger: 'custom',
				position: 'right',
			});
			$("#mailfrom").on("blur", function( event ) {
				if(!event.relatedTarget || event.relatedTarget && event.relatedTarget.textContent != "Cancel") {
					if (!$("#mailfrom").val() || emailRegex.test( $("#mailfrom").val())) {
						$(this).tooltipster("close");
						$(event.target).removeClass( "ui-state-error" );
						$("button.savecontrol").button("enable");
					} else {
						$(this).tooltipster("open");
						$(event.target).trigger("focus");
						$(event.target).addClass( "ui-state-error" );
						$("button.savecontrol").button("disable");
					}
				}
			});
			$("#emails").on("blur", function( event ) {
				if(!event.relatedTarget || event.relatedTarget && event.relatedTarget.textContent != "Cancel") {
					var emails = $("#emails").val().split(" ");
					var valid = true;
					for (var i = 0; i < emails.length; i++) {
						if( emails[i] == "" || ! emailRegex.test(emails[i])){
							valid = false;
						}
					}
					if (!$("#emails").val() || valid) {
						$(this).tooltipster("close");
						$(event.target).removeClass( "ui-state-error" );
						$("button.savecontrol").button("enable");
					} else {
						$(this).tooltipster("open");
						$(event.target).trigger("focus");
						$(event.target).addClass( "ui-state-error" );
						$("button.savecontrol").button("disable");
					}
				}
			});
			$("#grpname").on("blur", function( event ) {
				if (!event.relatedTarget || event.relatedTarget && event.relatedTarget.textContent != "Cancel") {
					if (! this.value) {
						$("#grpname").tooltipster('content', 'Group name is required').tooltipster('open');
						$(event.target).addClass( "ui-state-error" );
						$(event.target).trigger("focus");
						$("button.savecontrol").button("disable");
					} else if (this.value != grpToEdit && repcfgusr.groups[this.value]) {
						$("#grpname").tooltipster('content', 'Group already exists!').tooltipster('open');
						$(event.target).addClass( "ui-state-error" );
						$(event.target).trigger("focus");
						$("button.savecontrol").button("disable");
					} else {
						$("#grpname").tooltipster("close");
						$(event.target).removeClass( "ui-state-error" );
						$("button.savecontrol").button("enable");
					}
				}
			});
			if (grpToEdit) {
				$("#grpname").val(grpToEdit);
				$("#descr").val(repcfgusr.groups[grpToEdit].description);
				$("#emails").val(repcfgusr.groups[grpToEdit].emails.join(" "));
				$("#mailfrom").val(repcfgusr.groups[grpToEdit].mailfrom);
			}
		},
		open: function() {
			$('.ui-widget-overlay').addClass('custom-overlay');
		},
		close: function() {
			$(this).find( "form" ).trigger('reset');
			$("#grpname").tooltipster("destroy");
			$(this).dialog("destroy");
		}
	});
}

function generateReport (repName, userName) {
	$.getJSON(cgiPath + '/reporter.sh?cmd=generate', {repname: repName, user: userName }, function(data) {
		if (data.success) {
			var ttt = "<div id='progressDialog'><div id='pdfprogressbar'><div class='progress-label'>Please wait...</div></div><input type='button' value='Cancel' id='terminate' data-pid='" + data.pid + "'></div>";
			progressDialog = $( ttt ).dialog({
				dialogClass: "no-close",
				minWidth: 480,
				height: 136,
				modal: true,
				title: "Generating report - it can take a long time...",
				show: {
					effect: "fadeIn",
					duration: 500
				},
				hide: {
					effect: "fadeOut",
					duration: 200
				},
				open: function( event, ui ) {
					$( "#pdfprogressbar" ).progressbar({
						"max": data.count
					});
					$( "#terminate" ).on("click", function(e) {
						$.getJSON(cgiPath + "/reporter.sh?cmd=stop&pid=" + data.pid, function(data) {
							if(data.status=="terminated") {
								document.body.style.cursor = 'default';
							}
						});
					});
				}
			});
			setTimeout(function() {
				getReportStatus(data.pid);
			}, 100);
		}
	});
}
function getReportStatus(pid){
	$.getJSON(cgiPath + "/reporter.sh?cmd=status&pid=" + pid, function(data) {
		// $('#statusmessage').html(data.message);
		if(data.status=="pending") {
			$( "#pdfprogressbar" ).progressbar( "option", "max", data.count );
			$( "#pdfprogressbar" ).progressbar( "value", data.done )
			.children(".progress-label").text(data.done + " of " + data.count);
			setTimeout(function() {
				getReportStatus(pid);
			}, 500);
		} else if (data.status=="done" || data.status=="failed") {
			document.body.style.cursor = 'default';
			var dlg = "<p>Error message follows:</p>";
			var title = "";
			var log = "";
			if (data.status == "done") {
				dlg = "<p>Report log follows:</p>";
				title = "Report test succeed";
				log = "<h3>Your report has been generated.</h3>";
				if (data.emails) {
					log += "<p>It has been sent to the defined mail groups</p>";
				}
				log += "<p>You can find it on the host running this tool:</p>";
				log += "<pre>" + data.stored + "</pre>";
				log += "<p>Download it from the following link:</p>";
				log += "<p><a href='" + cgiPath + "/reporter.sh?cmd=get&filename=" + encodeURIComponent(data.dnld) + "' target='_blank'>" + data.filename + "</a></p>";
				// backendSupportsPDF = true;
			} else {
				title = "Report test failed";
				log = dlg + "<pre>" + data.error + "</pre>";
			}
			$("<div></div>").dialog( {
				buttons: { "OK": function () { $(this).dialog("close"); } },
				close: function (event, ui) {
					$(this).remove();
				},
				open: function() {
					$('.ui-widget-overlay').addClass('custom-overlay');
				},
				resizable: false,
				position: { my: "top", at: "top+20", of: window },
				title: title,
				minWidth: 800,
				modal: true
			}).html(log);
			$( "#progressDialog" ).dialog( "destroy" );
		} else if (data.status=="terminated") {
			$( "#progressDialog" ).dialog( "destroy" );
		} else {
			setTimeout(function() {
				getReportStatus(pid);
			}, 500);
		}
	});
}

function selectReportItemClass() {
	var selectedClass,
	reptype = $("#format").val(),
	repItemClassDiv = '<div id="new-rep-item-class"> \
		<fieldset> \
		<legend>Platforms</legend> \
		<button id="power">IBM Power Systems</button> \
		<div class="btnwrapper vmware" style="display: inline-block"><button id="vmware">VMware</button></div> \
		<div class="btnwrapper ovirt" style="display: inline-block"><button id="ovirt">oVirt</button></div> \
		<div class="btnwrapper solaris" style="display: inline-block"><button id="solaris">Solaris</button></div> \
		<div class="btnwrapper hyperv" style="display: inline-block"><button id="hyperv">Hyper-V</button></div> \
		<div class="btnwrapper nutanix" style="display: inline-block"><button id="nutanix">Nutanix</button></div> \
		</fieldset> \
		<br> \
		<fieldset> \
		<legend>Common items</legend> \
		<button id="custom">Custom Group</button> \
		<div class="btnwrapper top" style="display: inline-block"><button id="top">Top (n)</button></div> \
		<div class="btnwrapper rca" style="display: inline-block"><button id="rca">Resource Configuration Advisor</button></div> \
		</fieldset> \
	</div>';
	$( repItemClassDiv ).dialog({
		height: 290,
		width: 580,
		modal: true,
		title: "Select report item class",
		buttons: {
			Cancel: function() {
				$(this).dialog("close");
			}
		},
		create: function() {
			$( "#new-rep-item-class button" ).button({
				icon: false
			}).on("click", function(event) {
				selectedClass = $(this).attr("id");
				$("#new-rep-item-class").dialog("close");
			});
			if ( reptype == "CSV" ) {
				$("#solaris").button("disable");
				$(".btnwrapper.solaris").attr("title", "Cannot use Solaris items on CSV report, not implemented yet");
				$("#hyperv").button("disable");
				$(".btnwrapper.hyperv").attr("title", "Cannot use HyperV items on CSV report, not implemented yet");
				$("#nutanix").button("disable");
				$(".btnwrapper.nutanix").attr("title", "Cannot use Nutanix items on CSV report, not implemented yet");
			} else {
				// $("#top").button("disable");
				// $(".btnwrapper.top").attr("title", "You can use Top (n) items only in CSV reports");
				$("#rca").button("disable");
				$(".btnwrapper.rca").attr("title", "You can use Resource Configuration Advisor items only in CSV reports");
			}
			if (!sysInfo.isAdmin) {
				$("#top").button("disable");
				$(".btnwrapper.top").attr("title", "Only for Administrators");
				$("#rca").button("disable");
				$(".btnwrapper.rca").attr("title", "Only for Administrators");
			}
		},
		open: function() {
			$('.ui-widget-overlay').addClass('custom-overlay');
		},
		close: function() {
			$(this).find( "form" ).trigger('reset');
			$(this).dialog("destroy");
			if (selectedClass) {
				curPlatform = platforms[selectedClass].longname;
				if (selectedClass == "power") {
					repItemFormPower();
				} else if (selectedClass == "custom") {
					repItemFormCustom();
				} else if (selectedClass == "vmware") {
					repItemFormVmware();
				} else if (selectedClass == "ovirt") {
					repItemFormoVirt();
				} else if (selectedClass == "solaris") {
					repItemFormSolaris();
				} else if (selectedClass == "hyperv") {
					repItemFormHyperV();
				} else if (selectedClass == "nutanix") {
					repItemFormNutanix();
				} else if (selectedClass == "top") {
					repItemFormTop();
				} else if (selectedClass == "rca") {
					repItemFormRCA();
				} else {
					//repItemForm();
				}
			}
		}
	});
}

$.fn.sort_select_box = function(){
	// Get options from select box
	var my_options = $("#" + this.attr('id') + ' option');
	// sort alphabetically
	my_options.sort(function(a,b) {
		if (a.text > b.text) {
			return 1;
		} else if (a.text < b.text) {
			return -1;
		} else {
			return 0;
		}
	});
	//replace with sorted my_options;
	$(this).empty().append( my_options );

	// clearing any selections
	$("#"+this.attr('id')+" option").attr('selected', false);
};

function ACLcfg () {
	var ACLroot = [
		{title: "Custom group", key: "cgroup", folder: true},
		{title: "IBM Power", key: "power", folder: true},
		{title: "IBM Power CMC", key: "cmc", folder: true},
		{title: "VMware", key: "vmware", folder: true},
		{title: "Nutanix", key: "nutanix", folder: true},
		{title: "Proxmox", key: "proxmox", folder: true},
		{title: "FusionCompute", key: "fusioncompute", folder: true},
		{title: "oVirt/RHV", key: "ovirt", folder: true},
		{title: "XenServer", key: "xen", folder: true},
		{title: "HyperV", key: "hyperv", folder: true},
		{title: "Solaris", key: "solaris", folder: true},
		{title: "Oracle VM", key: "oraclevm", folder: true},
		{title: "Linux", key: "linux", folder: true},

		{title: "AWS", key: "aws", folder: true},
		{title: "Azure", key: "azure", folder: true},
		{title: "GCloud", key: "gcloud", folder: true},
		{title: "Cloudstack", key: "cloudstack", folder: true},

		{title: "Kubernetes", key: "kubernetes", folder: true},
		{title: "Openshift", key: "openshift", folder: true},
		{title: "Docker", key: "docker", folder: true},

		{title: "Oracle DB", key: "oracledb", folder: true},
		{title: "PostgreSQL", key: "postgres", folder: true},
		{title: "SQLServer", key: "sqlserver", folder: true},
		{title: "DB2", key: "db2", folder: true},

		{title: "Unmanaged", key: "solo", folder: true},
	];

	function updateGranted () {
		$(".aclh4").hide();
		$(".acd").empty();
		selNodes = $('#aclitemstree').fancytree("getTree").getSelectedNodes(true);
		var group = $("#aclgrptree").fancytree("getActiveNode").title;
		var cACL = usercfg.groups[group].ACL;
		cACL.lpars = {};
		cACL.pools = {};
		cACL.vms = {};
		cACL.vmcl = {};
		cACL.vmrp = {};
		cACL.vmvc = {};
		cACL.solo = {};
		cACL.cgroups = [];
		cACL.linux = [];
		cACL.sections = {};
		$.each(ACLroot, function(i, node) {
			cACL.sections[node.key] = false;
		});
		$.each(selNodes, function (i, node) {
			var server;
			if (node.getLevel() == 1) {
				cACL.sections[node.key] = true;
				switch (node.key) {
					case "power":
						$("#acl_pw").append("All granted<br>");
						$(".apw").show();
						break;
					case "vmware":
						$("#acl_vm").append("All granted<br>");
						$(".avm").show();
						break;
					case "solo":
						$("#acl_un").append("All granted<br>");
						$(".aun").show();
						break;
					case "cgroup":
						$("#acl_cg").append("All granted<br>");
						$(".acg").show();
						break;
					case "linux":
						$("#acl_linux").append("All granted<br>");
						$(".alinux").show();
						break;
					default:
						if (platforms[node.key]) {
							var string = "<h4 class='aclh4'>" + platforms[node.key].longname + "</h4>All granted<br>";
							$('#more_platforms').show().append(string);
						}
						break;
				}
			} else if (node.getLevel() == 2) {
				switch (node.data.obj) {
					case "L":
					case "P":
					case "SP":
						$("#acl_pw").append(node.title + " &rArr; *<br>");
						$(".apw").show();
						cACL.lpars[node.title] = [];
						cACL.lpars[node.title].push("*");
						cACL.pools[node.title] = [];
						cACL.pools[node.title].push("*");
						break;
					case "VM":
						$("#acl_vm").append(node.title + " &rArr; *<br>");
						$(".avm").show();
						cACL.vms[node.title] = [];
						cACL.vms[node.title].push("*");
						break;
					case "U":
						$("#acl_un").append(node.title + " &rArr; *<br>");
						$(".aun").show();
						cACL.solo[node.title] = [];
						cACL.solo[node.title].push("*");
						break;
					case "C":
						$("#acl_cg").append(node.title + "<br>");
						$(".acg").show();
						cACL.cgroups.push(node.title);
						break;
					case "X":
						$("#acl_linux").append(node.title + "<br>");
						$(".alinux").show();
						cACL.linux.push(node.title);
						break;
				}
			} else if (node.getLevel() == 3) {
				server = node.parent.title;
				switch (node.data.obj) {
					case "L":
						$("#acl_pw").append("LPAR: " + server + " &rArr; *<br>");
						$(".apw").show();
						if (!cACL.lpars[server]) {
							cACL.lpars[server] = [];
						}
						cACL.lpars[server].push("*");
						break;
					case "P":
					case "SP":
						$("#acl_pw").append("POOL: " + server + " &rArr; *<br>");
						$(".apw").show();
						if (!cACL.pools[server]) {
							cACL.pools[server] = [];
						}
						cACL.pools[server].push("*");
						break;
					case "VM":
						$("#acl_vm").append(server + " &rArr; " + node.title + "<br>");
						$(".avm").show();
						if (!cACL.vms[server]) {
							cACL.vms[server] = [];
						}
						cACL.vms[server].push(node.title);
						break;
					case "U":
						$("#acl_un").append(server + " &rArr; " + node.title + "<br>");
						$(".aun").show();
						if (!cACL.solo[server]) {
							cACL.solo[server] = [];
						}
						cACL.solo[server].push(node.title);
						break;
					case "C":
						$("#acl_cg").append(node.title + " &rArr; *<br>");
						$(".acg").show();
						cACL.cgroups.push(node.title);
						break;
				}
			} else if (node.getLevel() == 4) {
				server = node.parent.title;
				switch (node.data.obj) {
					case "L":
						server = node.parent.parent.title;
						$("#acl_pw").append("LPAR: " + server + " &rArr; " + node.title + "<br>");
						$(".apw").show();
						if (!cACL.lpars[server]) {
							cACL.lpars[server] = [];
						}
						cACL.lpars[server].push(node.title);
						break;
					case "P":
					case "SP":
						server = node.parent.parent.title;
						$("#acl_pw").append("POOL: " + server + " &rArr; " + node.title + "<br>");
						$(".apw").show();
						if (!cACL.pools[server]) {
							cACL.pools[server] = [];
						}
						cACL.pools[server].push(node.data.value);
						break;
				}
			}
		});
		//var joined = selNodes.map (function(elem) { return elem.title; }).join();
		//$("#acltable tr.highlight td:eq(3)").text(JSON.stringify(olpars));
	}
	$("#aclgrptree").fancytree({
		checkbox: false,
		clickFolderMode: 2,
		icon: false,
		autoCollapse: true,
		source: {
			url: '/lpar2rrd-cgi/users.sh?cmd=grptree'
		},
		activate: function (event, data) {
			$("#aclitemstree").fancytree("enable");
			$("#aclcustgrptre").fancytree("enable");
			var anode = data.node;
			var custgrps = [],
			linux = [],
			lpars = {},
			pools = {},
			vms = {},
			solo = {};
			if (usercfg.groups[anode.title].ACL) {
				custgrps = usercfg.groups[anode.title].ACL.cgroups;
				linux = usercfg.groups[anode.title].ACL.linux;
				lpars = usercfg.groups[anode.title].ACL.lpars;
				pools = usercfg.groups[anode.title].ACL.pools;
				vms = usercfg.groups[anode.title].ACL.vms;
				solo = usercfg.groups[anode.title].ACL.solo;
				if (!lpars) {
					lpars = {};
				}
				if (!pools) {
					pools = {};
				}
				if (!vms) {
					vms = {};
				}
				if (!solo) {
					solo = {};
				}
			} else {
				usercfg.groups[anode.title].ACL = {};
				usercfg.groups[anode.title].ACL.cgroups = [];
				usercfg.groups[anode.title].ACL.linux = [];
				usercfg.groups[anode.title].ACL.lpars = {};
				usercfg.groups[anode.title].ACL.pools = {};
				usercfg.groups[anode.title].ACL.vms = {};
				usercfg.groups[anode.title].ACL.solo = {};
			}

			var itemtree = $("#aclitemstree").fancytree("getTree");
			var rootNode = itemtree.getRootNode();
			$.each(rootNode.getChildren(), function(idx, node) {
				if (usercfg.groups[anode.title].ACL.sections && usercfg.groups[anode.title].ACL.sections[node.key]) {
					node.setSelected(true);
				} else {
					node.setSelected(false);
				}
			});

			var allpower = usercfg.groups[anode.title].ACL.sections && usercfg.groups[anode.title].ACL.sections.power;
			var ignoreServerLevel = usercfg.options.acl_power_server_ignore;
			if (allpower) {
				$("#aclitemstree").fancytree("getTree").getNodeByKey("power").setSelected(true);
			} else {
				$("#aclitemstree").fancytree("getTree").getNodeByKey("power").visit(function(node) {
					if (node.getLevel() == 2) {
						var slpars = lpars[node.title] && lpars[node.title][0] == "*";
						var spools = pools[node.title] && pools[node.title][0] == "*";
						node.setSelected(slpars && spools ? true : false);
					} else if (node.getLevel() == 3) {
						if (!node.isSelected()) {
							select = false;
							if (node.data.obj == "L") {
								select = lpars[node.parent.title] && lpars[node.parent.title][0] == "*" ? true : false;
							} else {
								select = pools[node.parent.title] && pools[node.parent.title][0] == "*" ? true : false;
							}
						}
						node.setSelected(select);
						if (node.isSelected()) {
						}
					} else {
						if (!node.parent.isSelected()) {
							var select = false;
							if (node.data.obj == "L") {
								if (lpars[node.parent.parent.title]) {
									if ($.inArray(node.title, lpars[node.parent.parent.title]) !== -1) {
										select = true;
									}
								} else if (ignoreServerLevel) {
									var allLpars = [];
									$.each(lpars, function(key, server) {
										jQuery.merge(allLpars, server);
									});
									if ($.inArray(node.title, allLpars) !== -1) {
										select = true;
									}
								}
							} else {
								if (pools[node.parent.parent.title]) {
									if ($.inArray(node.data.value, pools[node.parent.parent.title]) !== -1) {
										select = true;
									}
								}
							}
							node.setSelected(select);
						}
					}
				});
			}
			var allvmware = usercfg.groups[anode.title].ACL.sections && usercfg.groups[anode.title].ACL.sections.vmware;
			if (allvmware) {
				$("#aclitemstree").fancytree("getTree").getNodeByKey("vmware").setSelected(true);
			} else {
				$("#aclitemstree").fancytree("getTree").getNodeByKey("vmware").visit(function(node) {
					if (node.hasChildren()) {
						var select = vms[node.title] && vms[node.title][0] == "*" ? true : false;
						node.setSelected(select);
						if (node.isSelected()) {
						}
					} else {
						if (!node.parent.isSelected()) {
							var select = false;
							if (vms[node.parent.title]) {
								if ($.inArray(node.title, vms[node.parent.title]) !== -1) {
									select = true;
								}
							}
							node.setSelected(select);
						}
					}
				});
			}

			var allsolo = usercfg.groups[anode.title].ACL.sections && usercfg.groups[anode.title].ACL.sections.solo;
			if (allsolo) {
				$("#aclitemstree").fancytree("getTree").getNodeByKey("solo").setSelected(true);
			} else {
				$("#aclitemstree").fancytree("getTree").getNodeByKey("solo").visit(function(node) {
					if (node.hasChildren()) {
						var select = solo[node.title] && solo[node.title][0] == "*" ? true : false;
						node.setSelected(select);
					} else {
						if (!node.parent.isSelected()) {
							var select = false;
							if (solo[node.parent.title]) {
								if ($.inArray(node.title, solo[node.parent.title]) !== -1) {
									select = true;
								}
							}
							node.setSelected(select);
						}
					}
				});
			}
			var allcgroup = usercfg.groups[anode.title].ACL.sections && usercfg.groups[anode.title].ACL.sections.cgroup;
			if (allcgroup) {
				$("#aclitemstree").fancytree("getTree").getNodeByKey("cgroup").setSelected(true);
			} else {
				$("#aclitemstree").fancytree("getTree").getNodeByKey("cgroup").visit(function(node) {
					node.setSelected($.inArray(node.title, custgrps) !== -1);
				});
			}
			var alllinux = usercfg.groups[anode.title].ACL.sections && usercfg.groups[anode.title].ACL.sections.linux;
			if (alllinux) {
				$("#aclitemstree").fancytree("getTree").getNodeByKey("linux").setSelected(true);
			} else {
				$("#aclitemstree").fancytree("getTree").getNodeByKey("linux").visit(function(node) {
					node.setSelected($.inArray(node.title, linux) !== -1);
				});
			}

			updateGranted();
		}
	});
	$("#aclcustgrptre").fancytree({
		checkbox: true,
		icon: false,
		clickFolderMode: 2,
		autoCollapse: false,
		source: {
			url: '/lpar2rrd-cgi/genjson.sh?jsontype=cust'
		},
		disabled: true,
		select: function (event, data) {
			var node = data.node;
			selNodes = $(this).fancytree("getTree").getSelectedNodes();
			var group = $("#aclgrptree").fancytree("getActiveNode").title;
			usercfg.groups[group].ACL.cgroups = [];

			$("#acl_cg").empty();
			$(".acg").hide();
			$.each(selNodes, function (i, node) {
				$("#acl_cg").append(node.title + "<br>");
				$(".acg").show();
				usercfg.groups[group].ACL.cgroups.push(node.title);
			});
		}
	});

	$("#aclitemstree").fancytree({
		checkbox: true,
		selectMode: 3,
		icon: false,
		extensions: ["glyph"],
		glyph: {
			preset: "awesome5"
		},
		clickFolderMode: 2,
		autoCollapse: false,
		source: ACLroot,
		init: function (event, data) {
			var mtree = $('#side-menu').fancytree("getTree");
			var atree = $(this).fancytree("getTree");
			var ptree = atree.getNodeByKey("power");
			var vtree = atree.getNodeByKey("vmware");
			var ltree = atree.getNodeByKey("linux");
			var utree = atree.getNodeByKey("solo");
			var ctree = atree.getNodeByKey("cgroup");
			var newParent = {
				"title": "",
				"folder": true,
			};
			var newChild = {
				"title": "",
			};
			mtree.visit(function(node) {
				if (node.data.obj) {
					newParent.obj = node.data.obj;
					newChild.obj = node.data.obj;
					switch (node.data.obj) {
						case "L":
							var parent = ptree.findFirst(node.data.srv, true);
							if (! parent) {
								newParent.title = node.data.srv;
								parent = ptree.addNode(newParent, "child");
							}
							var subsys = parent.findFirst("LPAR", true);
							if (! subsys) {
								newParent.title = "LPAR";
								subsys = parent.addNode(newParent, "child");
							}
							newChild.title = node.data.altname;
							subsys.addNode(newChild, "child");
							break;
						case "P":
						case "SP":
							var parent = ptree.findFirst(node.data.srv, true);
							if (! parent) {
								newParent.title = node.data.srv;
								parent = ptree.addNode(newParent, "child");
							}
							var subsys = parent.findFirst("POOL", true);
							if (! subsys) {
								newParent.title = "POOL";
								subsys = parent.addNode(newParent, "child");
							}
							newChild.title = node.title;
							newChild.value = node.data.altname;
							subsys.addNode(newChild, "child");
							break;
						case "VM":
							var parent = vtree.findFirst(node.data.parent, true);
							if (! parent) {
								newParent.title = node.data.parent;
								parent = vtree.addNode(newParent, "child");
							}
							newChild.title = node.title;
							parent.addNode(newChild, "child");
							break;
						case "X":
							newChild.title = node.title;
							ltree.addNode(newChild, "child");
							break;
						case "U":
							var parent = utree.findFirst(node.data.srv, true);
							if (! parent) {
								newParent.title = node.data.srv;
								parent = utree.addNode(newParent, "child");
							}
							newChild.title = node.data.altname;
							parent.addNode(newChild, "child");
							break;
						case "C":
							/*
							*var parent = ctree.findFirst(node.data.srv, true);
							*if (! parent) {
							*    newParent.title = node.data.srv;
							*    parent = ctree.addNode(newParent, "child");
							*}
							*/
							newChild.title = node.title;
							ctree.addNode(newChild, "child");
							break;
					}
				}
			});
		},
		/*
		*{
		*    url: '/lpar2rrd-cgi/genjson.sh?jsontype=aclitems'
		*},
		*/
		disabled: true,
		select: function (event, data) {
			if (data.targetType == "checkbox") {
				updateGranted();
			}
		}
	});
	// $("#aclitemstree").fancytree('getTree').getSelectedNodes();

	// $("#aclitemstree").fancytree("disable");
	// $("#aclcustgrptree").fancytree("disable");

	$("#saveacl").button().on("click", function(event) {
		SaveUsrCfg(true);
		/*
		var acltxt = "";
		$("#acltable tr").each(function() {
			var atxt = [];
			$(this).find("td").each(function() {
				atxt.push(this.textContent.replace(/\|/g, "===pipe==="));
			});
			if (atxt.length) {
				acltxt += atxt.join("|") + "\n";
			}
		});
		//$("#aclfile").text(acltxt).show();

		var postdata = {
			'acl': acltxt
		};
		$("#aclfile").load(this.action, postdata);
		$("#aclfile").show();
		*/
	});

	$.getJSON('/lpar2rrd-cgi/users.sh?cmd=json', function(data) {
		usercfg = data;
		if (usercfg.options) {
			$("#acl_power_server_ignore").prop("checked", usercfg.options.acl_power_server_ignore);
		}
		$("#acl_power_server_ignore").off().on("change", function(event) {
			usercfg.options.acl_power_server_ignore = $("#acl_power_server_ignore").prop("checked");
		});
	});
}

// use this transport for "binary" data type
$.ajaxTransport("+binary", function(options, originalOptions, jqXHR){
	// check for conditions and support for blob / arraybuffer response type
	if (window.FormData && ((options.dataType && (options.dataType == 'binary')) || (options.data && ((window.ArrayBuffer && options.data instanceof ArrayBuffer) || (window.Blob && options.data instanceof Blob)))))
		{
			return {
				// create new XMLHttpRequest
				send: function(headers, callback){
					// setup all variables
					var xhr = new XMLHttpRequest(),
					url = options.url,
					type = options.type,
					async = options.async || true,
					// blob or arraybuffer. Default is blob
					dataType = options.responseType || "blob",
					data = options.data || null,
					username = options.username || null,
					password = options.password || null;

					xhr.addEventListener('load', function(){
						var data = {};
						data[options.dataType] = xhr.response;
						// make callback and send data
						callback(xhr.status, xhr.statusText, data, xhr.getAllResponseHeaders());
					});

					xhr.open(type, url, async);

					// setup custom headers
					for (var i in headers ) {
						xhr.setRequestHeader(i, headers[i] );
					}

					if (options.xhrFields) {
						for (var key in options.xhrFields) {
							if (options.xhrFields.hasOwnProperty(key)) {
								xhr[key] = options.xhrFields[key];
							}
						}
					}

					xhr.responseType = dataType;
					xhr.send(data);
				},
				abort: function(){
					jqXHR.abort();
				}
			};
		}
});

function legendTable(element, table_data) {
	var legdiv = $(element).parents(".relpos").find("div.legend");
	/*
	var pane = $(legdiv).data('jsp');
	if (pane) {
		pane.destroy();
	}
	*/
	$(legdiv).html(Base64.decode(table_data));
	var $t = element.parents(".relpos").find('table.tablesorter');
	if ($t.length) {
		var updated = $t.find(".tdupdated");
		if (updated) {
			element.parents(".detail").siblings(".updated").text(updated.text());
			updated.parent().remove();
		}
		tableSorter($t);
		$t.find("a").on("click", function(ev) {
			var url = $(this).attr('href');
			if ((url.substring(0, 7) != "http://") && (!/\.csv$/.test(url)) && (!/lpar-list-rep\.sh/.test(url)) && ($(this).text() != "CSV")) {
				backLink(url, ev);
			return false;
			}
		});
		$t.find("td.legsq").each(function() {
			$(this).siblings('td').each(function() {
				if ($(this).text().length > 0 && ! $(this).attr("title")) {
					$(this).attr("title", $(this).text()); // set tooltip (to see very long names)
				}
			});
			var bgcolor = $(this).text();
			if (bgcolor) {
				var parLink = $(this).parents(".relpos").find("a.detail").attr("href");
				var parParams = getParams(parLink);
				// var trTime = trTime.match(/&time=([dwmy])/)[1];
				var trItem = "lpar";
				if (parParams.item == "memaggreg" || parParams.item == "customosmem" || parParams.item == "custommem") {
					trItem = "mem";
				} else if (parParams.item == "pagingagg") {
					trItem = "pg1";
				} else if (parParams.item == "memams") {
					trItem = "ams";
				} else if (parParams.item == "customoslan") {
					trItem = "lan";
				} else if (parParams.item == "job_cpu") {
					trItem = "as4job_proc";
				} else if (parParams.item == "waj") {
					trItem = "as4job_core";
				} else if (parParams.item == "disk_io") {
					trItem = "as4job_disk";
				} else if (parParams.item == "disk_io") {
					trItem = "as4job_disk";
				} else if (parParams.item == "disks") {
					trItem = "as4job_diskio_sec";
				} else if (parParams.item == "disk_busy") {
					trItem = "as4job_dbusy";
				} else if (parParams.item == "jobs") {
					trItem = "powlin_job";
				} else if (parParams.item == "jobs_mem") {
					trItem = "powlin_mem";
				}
				var trTime = parParams.time;
				switch (trTime) {
					case "60" :
						trTime = "m";
					break;
					case "3600" :
						trTime = "h";
					break;
					case "86400" :
						trTime = "d";
					break;
				}
				var trLink;
				if (this.dataset && this.dataset.job) {
					trLink = parLink;
				} else if (this.dataset && this.dataset.url) {
					trLink = this.dataset.url;
				} else {
					trLink = $(this).parent().find(".clickabletd a").last().attr("href");
				}
				var trParams = getParams(trLink);
				if (trParams.item == "pool") {
					if (trParams.lpar == "pool") {
						trItem = "pool";
					} else {
						trItem = "shpool";
					}
				}
				if (trParams.square_item) {
					trItem = trParams.square_item;
				}
				if (this.dataset && this.dataset.job) {
					trLink = "/lpar2rrd-cgi/detail-graph.sh?host=" + trParams.host + "&server=" + trParams.server + "&lpar=" + trParams.lpar +
						"&item=" + trItem + "&time=" + trTime + "&type_sam=m&detail=1&upper=0&entitle=0" + "&none=" + encodeURIComponent(this.dataset.job);
				} else if (trParams.host == "Hitachi") {
					trLink = "/lpar2rrd-cgi/detail-graph.sh?host=" + trParams.server + "&server=" + trParams.host + "&lpar=" + trParams.lpar +
						"&item=" + trItem + "&time=" + trTime + "&type_sam=m&detail=1&upper=0&entitle=0" + "&none=" + encodeURIComponent(this.dataset.job);
				} else if (this.dataset && this.dataset.url) {
					trLink = this.dataset.url;
				} else {
					trLink = "/lpar2rrd-cgi/detail-graph.sh?host=" + trParams.host + "&server=" + trParams.server + "&lpar=" + trParams.lpar +
						"&item=" + trItem + "&time=" + trTime + "&type_sam=m&detail=1&upper=0&entitle=0&sunix=" + parParams.sunix + "&eunix=" + parParams.eunix;
				}
				if ( parParams.item != "memaggreg" && ! $(this).hasClass("noclick")  && trParams.lpar) {
					$(this).html("<a href='" + trLink + "' title='Click to get [" + decodeURIComponent(trParams.lpar.replace(/\+/g, " ")) + "] detail in a pop-up view' class='detail'><div class='innersq' style='background:" + bgcolor + ";'></div></a>");
					$(this).find('a.detail').colorbox({
						photo: true,
						// transition: 'none',
						live: false,
						speed: 300,
						fadeOut: 100,
						scalePhotos: true, // images won't be scaled to fit to browser's height
						initialWidth: 1200,
						maxWidth: "95%",
						opacity: 0.4,
						hideOnContentClick: true,
						onOpen: function(obj) {
							if (storedUrl) {
								obj.href = zoomedUrl;
							} else {
								var tUrl = obj.href;
								tUrl += "&nonefb=" + Math.floor(new Date().getTime() / 1000);
								obj.href = tUrl;
							}
							return true;
						},
						onComplete: function() {
							$('.cboxPhoto').off().on("click", $.colorbox.close);
						},
						onClosed: function() {
							if (storedUrl) {
								$(storedObj).attr("href", storedUrl);
								storedUrl = "";
								storedObj = {};
							}
						}
					});
				} else {
					$(this).html("<center><div class='innersq' style='background:" + bgcolor + ";'></div><center>");
				}
			}
		});
		if ($t.find("a.detail").length) {
			$t.find("tr").find("th").first().addClass("popup").attr("title", "Click on the color square below to get LPAR/VM detail in a pop-up view");
		}
		if (sysInfo.legend_height) {
			if ($(legdiv).hasClass("higher")) {
				$t.parent().css("max-height", sysInfo.legend_height * 3 + "px");
			} else {
				$t.parent().css("max-height", sysInfo.legend_height + "px");
			}
		}
		// $(legdiv).jScrollPane();
		// pane = $(legdiv).data('jsp');
		// pane.reinitialise();
	}
	$(element).parents("td.relpos").css("vertical-align", "top");
	$(element).parents("td.relpos").css("text-align", "left");
	/*
	var toplevel = curNode.getParentList()[0];
	if (! toplevel || toplevel.title != "XenServer") {
		$(element).parents(".relpos").find("div.favs").show();
	}
	*/
	$(element).parents(".relpos").find("div.dash").show();
	// $(element).parents(".relpos").find("div.popdetail").show();
}

function hostDetailForm(hostAlias) {
	var hostDetailFormDiv = '<div id="host-config-form"> \
	<form autocomplete="off"> \
	<fieldset> \
	<legend>Common options</legend> \
	<input type="hidden" name="uuid" id="uuid" /> \
	<label for="hostalias">Host alias</label> \
	<input type="text" name="hostalias" id="hostalias" class="reqrd" autocomplete="off" /><br> \
	<!--label for="platform">Platform</label> \
	<input type="text" id="platform" name="platform" disabled><br--> \
	<label for="hostname">Host name / IP</label> \
	<input type="text" name="hostname" id="hostname" class="reqrd" title="" autocomplete="off" /><br> \
	<label for="username">User name</label> \
	<input type="text" name="username" id="username" class="reqrd" title="" autocomplete="nope" /><br> \
	</fieldset> \
	<fieldset> \
	<legend><label><input type="checkbox" name="authapi" id="authapi" disabled>API&nbsp;</label></legend> \
	<label for="apiport">API Port</label> \
	<input type="number" value="443" name="apiport" id="apiport" class="api" style="width: 5em" title="" autocomplete="off" /><br> \
	<label for="apiproto">API protocol</label> \
	<select class="api" id="apiproto" name="apiproto" style="width: 7em"> \
	<option value="https">HTTPS</option> \
	<option value="http">HTTP</option> \
	</select><br> \
	<label for="password">API Password</label> \
	<input type="password" name="password" id="password" class="api" style="width: 8em" title="" autocomplete="new-password" /><span class="showpass api">Show</span><br> \
	</fieldset> \
	<fieldset> \
	<legend><label><input type="checkbox" name="authssh" id="authssh" disabled>SSH&nbsp;</label></legend> \
	<label for="sshport">SSH Port</label> \
	<input type="number" value="22" name="sshport" id="sshport" class="ssh" style="width: 4em" title="" /><br> \
	<label for="sshkey">SSH key path</label> \
	<input type="text" name="sshkeyinput" id="sshkeyinput" class="ssh" style="" title="" /> \
	</fieldset> \
	<!-- Allow form submission with keyboard without duplicating the dialog button --> \
	<input type="submit" tabindex="-1" style="position:absolute; top:-1000px"> \
	</form> \
	</div>';
	$( hostDetailFormDiv ).dialog({
		height: 490,
		width: 420,
		modal: true,
		title: "Host configuration",
		buttons: {
			"Save host": {
				click: function() {
					var hostalias = $("#hostalias").val(),
					hostname = $("#hostname").val(),
					username = $("#username").val(),
					sshport = $("#sshport").val(),
					sshkey = $("#sshkeyinput").val(),
					apiport = $("#apiport").val(),
					apiproto = $("#apiproto").val(),
					password = Base64.encode(uuencode($("#password").val())),
					authapi = $("#authapi").prop('checked'),
					authssh = $("#authssh").prop('checked'),
					created = null;
					if (hostAlias) {
						created = hostcfg.platforms[curPlatform].aliases[hostAlias].created;
						delete hostcfg.platforms[curPlatform].aliases[hostAlias];
					}
					hostcfg.platforms[curPlatform].aliases[hostalias] = {
						uuid: $("#uuid").val(),
						host: hostname,
						username: username,
						ssh_port: sshport,
						ssh_key_id: sshkey,
						api_port: apiport,
						proto: apiproto,
						password: password,
						auth_api: authapi,
						auth_ssh: authssh
					};
					if (hostAlias) {
						hostcfg.platforms[curPlatform].aliases[hostalias].updated = TimeStamp();
						hostcfg.platforms[curPlatform].aliases[hostalias].created = created;
					} else {
						hostcfg.platforms[curPlatform].aliases[hostalias].created = TimeStamp();
					}
					SaveHostsCfg(true);
					$(this).dialog("close");
					$('#adminmenu a[data-abbr="hosts-' + $("#hosttable").data("platform") + '"]').trigger( "click" );
				},
				text: "Save host",
				class: 'savecontrol'
			},
			"Test connection": {
				click: function() {
					var hostalias = $("#hostalias").val(),
					hostname = $("#hostname").val(),
					username = $("#username").val(),
					sshport = $("#sshport").val(),
					sshkey = $("#sshkeyinput").val(),
					apiport = $("#apiport").val(),
					apiproto = $("#apiproto").val(),
					password = Base64.encode(uuencode($("#password").val())),
					authapi = $("#authapi").prop('checked'),
					authssh = $("#authssh").prop('checked'),
					created = null;
					if (hostAlias) {
						created = hostcfg.platforms[curPlatform].aliases[hostAlias].created;
						delete hostcfg.platforms[curPlatform].aliases[hostAlias];
					}
					hostcfg.platforms[curPlatform].aliases[hostalias] = {
						uuid: $("#uuid").val(),
						host: hostname,
						username: username,
						ssh_port: sshport,
						ssh_key_id: sshkey,
						api_port: apiport,
						proto: apiproto,
						password: password,
						auth_api: authapi,
						auth_ssh: authssh
					};
					if (hostAlias) {
						hostcfg.platforms[curPlatform].aliases[hostalias].updated = TimeStamp();
						hostcfg.platforms[curPlatform].aliases[hostalias].created = created;
					} else {
						hostcfg.platforms[curPlatform].aliases[hostalias].created = TimeStamp();
					}
					SaveHostsCfg(false);
					$(this).dialog("close");
					$('#adminmenu a[data-abbr="hosts-' + $("#hosttable").data("platform") + '"]').trigger( "click" );
					testConnection(hostalias, hostcfg.platforms[curPlatform].aliases[hostalias]);
				},
				text: "Save & Test connection",
				class: 'savecontrol'
			},
			Cancel: function() {
				$(this).dialog("close");
			}
		},
		create: function() {
			var curHost = {};
			var sshkeyel;
			$("button.savecontrol").button("disable");
			$("#hostalias").tooltipster({
				trigger: 'custom',
				position: 'right',
			});
			if (hostAlias) {
				curHost = hostcfg.platforms[curPlatform].aliases[hostAlias];
				$("#hostalias").val(hostAlias);
				$("#uuid").val(curHost.uuid);
				$("#hostname").val(curHost.host);
				// $("#platform").val(curHost.platform);
				$("#username").val(curHost.username);
				$("#sshport").val(curHost.ssh_port);
				$("#sshkeyinput").val(curHost.ssh_key_id);
				$("#apiport").val(curHost.api_port);
				$("#apiproto").val(curHost.proto);
				if (curHost.password === true) {
					$("#password").attr("placeholder", "Don't fill to keep current");
					$("#password").addClass("keepass");
				} else {
					$("#password").val(reveal(curHost.password));
				}
				validateHostCfg(curHost);
				$("#authapi").prop('checked', curHost.auth_api);
				$("#authssh").prop('checked', curHost.auth_ssh);
				$(".showpass").hide();

			} else {
				$("#authapi").prop('checked', hostcfg.platforms[curPlatform].api),
				$("#authssh").prop('checked', hostcfg.platforms[curPlatform].ssh);
			}
			$(".api").prop('disabled', !$("#authapi").is(':checked'));
			$("#apiproto").change(function() {
				if ($("#apiproto").val() == 'http') {
					$("#apiport").val(80);
				} else {
					$("#apiport").val(443);
				}
			});
			$("input[type=radio]").change(function() {
				$(".ssh").prop('disabled', !$("#authssh").is(':checked'));
				if ($("#authssh").is(':checked')) {
					if (! $("#sshport").val()) {
						$("#sshport").val(22);
					}
				}
				$(".api").prop('disabled', !$("#authapi").is(':checked'));
				if ($("#authapi").is(':checked')) {
					if (! $("#apiport").val()) {
						$("#apiport").val(443);
					}
					if (! $("#apiproto").val()) {
						$("#apiproto").val("https");
					}
				}
			});
			$(".reqrd, .api, .ssh").change(function() {
				validateHostCfg(true);
			});

			$(".showpass").button().mousedown(function(e) {
				e.stopPropagation();
				$(this).prev().attr('type','text');
			}).mouseup(function(){
				$(this).prev().attr('type','password');
			}).mouseout(function(){
				$(this).prev().attr('type','password');
			});
			$("#password").on("keyup", function( event ) {
				if ($(this).val()) {
					$(".showpass").button("enable");
				} else {
					$(".showpass").button("disable");
				}
			});
			$("#hostalias").on("blur", function( event ) {
				if (!event.relatedTarget || event.relatedTarget && event.relatedTarget.textContent != "Cancel") {
					if (! this.value) {
						$("#hostalias").tooltipster('content', 'Alias name is required').tooltipster('open');
						$(event.target).addClass( "ui-state-error" );
						$(event.target).trigger("focus");
						// validateHostCfg(curHost);
						$("button.savecontrol").button("disable");
					} else if (this.value != hostAlias && hostcfg.platforms[curPlatform].aliases[this.value]) {
						$("#hostalias").tooltipster('content', 'Host alias already exists!').tooltipster('open');
						$(event.target).addClass( "ui-state-error" );
						$(event.target).trigger("focus");
						// validateHostCfg(curHost);
						$("button.savecontrol").button("disable");
					} else {
						$("#hostalias").tooltipster("close");
						$(event.target).removeClass( "ui-state-error" );
						if (curHost.platform) {
							validateHostCfg(curHost);
						}
						// $("button.savecontrol").button("enable");
					}
				}
			});
		},
		open: function() {
			$('.ui-widget-overlay').addClass('custom-overlay');
		},
		close: function() {
			$(this).find( "form" ).trigger('reset');
			$("#grpname").tooltipster("destroy");
			$(this).dialog("destroy");
		}
	});
}

function hostDetailFormNutanix(hostAlias) {
	var hostDetailFormDiv = '<div id="host-config-form"> \
		<form autocomplete="off"> \
		<fieldset> \
		<legend>Options</legend> \
		<input type="hidden" name="uuid" id="uuid" /> \
		<label for="hostalias">Host alias</label> \
		<input type="text" name="hostalias" id="hostalias" onkeypress="return event.charCode != 95" class="reqrd" autocomplete="off" /><br> \
		<label for="type">Type</label> \
		<select class="type" id="type" name="type" style="width: 10em"> \
		<option value="element">Prism Element (API v2)</option> \
	    <option value="element_old">Prism Element (API v1)</option> \
		<option value="central">Prism Central (API v3)</option> \
		</select><br> \
		<!--label for="platform">Platform</label> \
		<input type="text" id="platform" name="platform" disabled><br--> \
		<label for="hostname">Host name / IP</label> \
		<input type="text" name="hostname" id="hostname" class="reqrd" title="" autocomplete="off" /><br> \
		<label for="username">User name</label> \
		<input type="text" name="username" id="username" class="reqrd" title="" autocomplete="nope" /><br> \
		<input type="hidden" name="authapi" id="authapi" value="true"> \
		<label for="apiport">API Port</label> \
		<input type="number" value="9440" name="apiport" id="apiport" class="api" style="width: 5em" title="" autocomplete="off" /><br> \
		<label for="apiproto">API protocol</label> \
		<select class="api" id="apiproto" name="apiproto" style="width: 7em"> \
		<option value="https">HTTPS</option> \
		<option value="http">HTTP</option> \
		</select><br> \
		<label for="password">API Password</label> \
		<input type="password" name="password" id="password" class="api" style="width: 8em" title="" autocomplete="new-password" /><span class="showpass api">Show</span><br> \
		</fieldset> \
		<!-- Allow form submission with keyboard without duplicating the dialog button --> \
		<input type="submit" tabindex="-1" style="position:absolute; top:-1000px"> \
		</form> \
		</div>';
	$( hostDetailFormDiv ).dialog({
		height: 490,
		width: 420,
		modal: true,
		title: "Host configuration",
		buttons: {
			"Save host": {
				click: function() {
					var hostalias = $("#hostalias").val(),
						hostname = $("#hostname").val(),
						username = $("#username").val(),
						apiport = $("#apiport").val(),
						apiproto = $("#apiproto").val(),
						password = Base64.encode(uuencode($("#password").val())),
						authapi = $("#authapi").val(),
						type = $("#type").val(),
						created = null;
					hostalias = hostalias.replace(/_/g, '');
					if (hostAlias) {
						created = hostcfg.platforms[curPlatform].aliases[hostAlias].created;
						delete hostcfg.platforms[curPlatform].aliases[hostAlias];
					}
					hostcfg.platforms[curPlatform].aliases[hostalias] = {
						uuid: $("#uuid").val(),
						host: hostname,
						username: username,
						api_port: apiport,
						proto: apiproto,
						password: password,
						auth_api: authapi,
						type: type
					};
					if (hostAlias) {
						hostcfg.platforms[curPlatform].aliases[hostalias].updated = TimeStamp();
						hostcfg.platforms[curPlatform].aliases[hostalias].created = created;
					} else {
						hostcfg.platforms[curPlatform].aliases[hostalias].created = TimeStamp();
					}
					SaveHostsCfg(true);
					$(this).dialog("close");
					$('#adminmenu a[data-abbr="hosts-' + $("#hosttable").data("platform") + '"]').trigger( "click" );
				},
				text: "Save host",
				class: 'savecontrol'
			},
			"Test connection": {
				click: function() {
					var hostalias = $("#hostalias").val(),
						hostname = $("#hostname").val(),
						username = $("#username").val(),
						apiport = $("#apiport").val(),
						apiproto = $("#apiproto").val(),
						password = Base64.encode(uuencode($("#password").val())),
						authapi = $("#authapi").val(),
						type = $("#type").val(),
						created = null;
					if (hostAlias) {
						created = hostcfg.platforms[curPlatform].aliases[hostAlias].created;
						delete hostcfg.platforms[curPlatform].aliases[hostAlias];
					}
					hostcfg.platforms[curPlatform].aliases[hostalias] = {
						uuid: $("#uuid").val(),
						host: hostname,
						username: username,
						api_port: apiport,
						proto: apiproto,
						password: password,
						auth_api: authapi,
						type: type,
					};
					if (hostAlias) {
						hostcfg.platforms[curPlatform].aliases[hostalias].updated = TimeStamp();
						hostcfg.platforms[curPlatform].aliases[hostalias].created = created;
					} else {
						hostcfg.platforms[curPlatform].aliases[hostalias].created = TimeStamp();
					}
					SaveHostsCfg(false);
					$(this).dialog("close");
					$('#adminmenu a[data-abbr="hosts-' + $("#hosttable").data("platform") + '"]').trigger( "click" );
					testConnection(hostalias, hostcfg.platforms[curPlatform].aliases[hostalias]);
				},
				text: "Save & Test connection",
				class: 'savecontrol'
			},
			Cancel: function() {
				$(this).dialog("close");
			}
		},
		create: function() {
			var curHost = {};
			var sshkeyel;
			$("button.savecontrol").button("disable");
			$("#hostalias").tooltipster({
				trigger: 'custom',
				position: 'right',
			});
			if (hostAlias) {
				curHost = hostcfg.platforms[curPlatform].aliases[hostAlias];
				$("#hostalias").val(hostAlias);
				$("#uuid").val(curHost.uuid);
				$("#hostname").val(curHost.host);
				// $("#platform").val(curHost.platform);
				$("#username").val(curHost.username);
				$("#apiport").val(curHost.api_port);
				$("#apiproto").val(curHost.proto);
				$("#type").val(curHost.type);
				if (curHost.password === true) {
					$("#password").attr("placeholder", "Don't fill to keep current");
					$("#password").addClass("keepass");
				} else {
					$("#password").val(reveal(curHost.password));
				}
				validateHostCfg(curHost);
				$("#authapi").prop('checked', curHost.auth_api);
				$(".showpass").hide();

			} else {
				$("#authapi").prop('checked', hostcfg.platforms[curPlatform].api);
			}
			$("#apiproto").change(function() {
				if ($("#apiproto").val() == 'http') {
					$("#apiport").val(80);
				} else {
					$("#apiport").val(9440);
				}
			});
			$("input[type=radio]").change(function() {
				$(".api").prop('disabled', !$("#authapi").is(':checked'));
				if ($("#authapi").is(':checked')) {
					if (! $("#apiport").val()) {
						$("#apiport").val(9440);
					}
					if (! $("#apiproto").val()) {
						$("#apiproto").val("https");
					}
				}
			});
			$(".reqrd, .api").change(function() {
				validateHostCfg(true);
			});

			$(".showpass").button().mousedown(function(e) {
				e.stopPropagation();
				$(this).prev().attr('type','text');
			}).mouseup(function(){
				$(this).prev().attr('type','password');
			}).mouseout(function(){
				$(this).prev().attr('type','password');
			});
			$("#password").on("keyup", function( event ) {
				if ($(this).val()) {
					$(".showpass").button("enable");
				} else {
					$(".showpass").button("disable");
				}
			});
			$("#hostalias").on("blur", function( event ) {
				if (!event.relatedTarget || event.relatedTarget && event.relatedTarget.textContent != "Cancel") {
					if (! this.value) {
						$("#hostalias").tooltipster('content', 'Alias name is required').tooltipster('open');
						$(event.target).addClass( "ui-state-error" );
						$(event.target).trigger("focus");
						// validateHostCfg(curHost);
						$("button.savecontrol").button("disable");
					} else if (this.value != hostAlias && hostcfg.platforms[curPlatform].aliases[this.value]) {
						$("#hostalias").tooltipster('content', 'Host alias already exists!').tooltipster('open');
						$(event.target).addClass( "ui-state-error" );
						$(event.target).trigger("focus");
						// validateHostCfg(curHost);
						$("button.savecontrol").button("disable");
					} else {
						$("#hostalias").tooltipster("close");
						$(event.target).removeClass( "ui-state-error" );
						if (curHost.platform) {
							validateHostCfg(curHost);
						}
						// $("button.savecontrol").button("enable");
					}
				}
			});
		},
		open: function() {
			$('.ui-widget-overlay').addClass('custom-overlay');
		},
		close: function() {
			$(this).find( "form" ).trigger('reset');
			$("#grpname").tooltipster("destroy");
			$(this).dialog("destroy");
		}
	});
}

function reloadHostCfg() {
	$.getJSON('/lpar2rrd-cgi/hosts.sh?cmd=json', function(data) {
		hostcfg = {};
		// check for the old format, if true, make conversion
		if (data.aliases) {
			hostcfg.platforms = {};
			$.each(data.platforms, function(idx, val) {
				hostcfg.platforms[val.id] = val;
				hostcfg.platforms[val.id].aliases = {};
				delete hostcfg.platforms[val.id].id;
			});
			$.each(data.aliases, function(idx, val) {
				if (hostcfg.platforms[val.platform]) {
					hostcfg.platforms[val.platform].aliases[idx] = val;
					delete hostcfg.platforms[val.platform].aliases[idx].platform;
				}
			});

		} else {
			hostcfg = data;
		}
	});
}

function hostDetailFormAWS(hostAlias) {
	var hostDetailFormDiv = '<div id="host-config-form"> \
		<form autocomplete="off"> \
		<fieldset> \
		<legend>Options</legend> \
		<input type="hidden" name="uuid" id="uuid" /> \
		<label for="hostalias">Host alias</label> \
		<input type="text" name="hostalias" id="hostalias" onkeypress="return event.charCode != 95" class="reqrd" autocomplete="off" /><br> \
		<label for="username">Access key</label> \
		<input type="text" name="aws_access_key_id" id="aws_access_key_id" class="reqrd" title="" autocomplete="nope" /><br> \
		<input type="hidden" name="authapi" id="authapi" value="true"> \
		<label for="password">Secret key</label> \
		<input type="password" name="aws_secret_access_key" id="aws_secret_access_key" class="api" style="width: 8em" title="" autocomplete="new-password" /><span class="showpass api">Show</span><br> \
		<label for="interval">Interval</label> \
		<select id="interval" name="interval"> \
		<option value="300">5 minutes</option> \
		<option value="60">1 minute</option> \
		</select> \
		</fieldset> \
		<fieldset> \
		<table id="tbl_aws"><tr><td><small>Enter access key & secret key before load regions</small></td><td></td></tr></table> \
		<legend>Regions</legend> \
		</fieldset> \
		<!-- Allow form submission with keyboard without duplicating the dialog button --> \
		<input type="submit" tabindex="-1" style="position:absolute; top:-1000px"> \
		</form> \
		</div>';
	$( hostDetailFormDiv ).dialog({
		height: 490,
		width: 420,
		modal: true,
		title: "Host configuration",
		buttons: {
			"Save host": {
				click: function() {
					var hostalias = $("#hostalias").val(),
						host = "aws.amazon.com",
						api_port = "443",
						aws_access_key_id = $("#aws_access_key_id").val(),
						aws_secret_access_key = Base64.encode(uuencode($("#aws_secret_access_key").val())),
						//regions = $("#regions").val(),
						regions = [],
						authapi = $("#authapi").val(),
						interval = parseInt($("#interval").val()),
						created = null;
					hostalias = hostalias.replace(/_/g, '');
					if (hostAlias) {
						created = hostcfg.platforms[curPlatform].aliases[hostAlias].created;
						available_regions = hostcfg.platforms[curPlatform].aliases[hostAlias].available_regions;
						delete hostcfg.platforms[curPlatform].aliases[hostAlias];
					}
					var tabl_aws_rows = document.getElementById('tbl_aws').rows.length;
					for (var i=0, iLen=tabl_aws_rows; i<iLen; i++) {
						var tbl_value = $("#tbl_region_"+i).val();
						if ($("#tbl_region_"+i).prop('checked') ) {
							regions.push(available_regions[i]);
						}
					}
					hostcfg.platforms[curPlatform].aliases[hostalias] = {
						uuid: $("#uuid").val(),
						hostalias: hostalias,
						host: host,
						regions: regions,
						interval: interval,
						aws_access_key_id: aws_access_key_id,
						aws_secret_access_key: aws_secret_access_key,
						auth_api: authapi,
						api_port: api_port
					};
					if (hostAlias) {
						hostcfg.platforms[curPlatform].aliases[hostalias].updated = TimeStamp();
						hostcfg.platforms[curPlatform].aliases[hostalias].created = created;
						hostcfg.platforms[curPlatform].aliases[hostalias].available_regions = available_regions;
					} else {
						hostcfg.platforms[curPlatform].aliases[hostalias].created = TimeStamp();
					}
					SaveHostsCfg(true);
					$(this).dialog("close");
					$('#adminmenu a[data-abbr="hosts-' + $("#hosttable").data("platform") + '"]').trigger( "click" );
				},
				text: "Save host",
				class: 'savecontrol'
			},
			"Load regions" : {
				click: function() {
					var hostalias = $("#hostalias").val(),
						host = "aws.amazon.com",
						api_port = "443",
						aws_access_key_id = $("#aws_access_key_id").val(),
						aws_secret_access_key = Base64.encode(uuencode($("#aws_secret_access_key").val())),
						regions = [],
						authapi = $("#authapi").val(),
						interval = parseInt($("#interval").val()),
						created = null;
					if (hostAlias) {
						created = hostcfg.platforms[curPlatform].aliases[hostAlias].created;
						available_regions = hostcfg.platforms[curPlatform].aliases[hostAlias].available_regions;
						delete hostcfg.platforms[curPlatform].aliases[hostAlias];
					}
					var tabl_aws_rows = document.getElementById('tbl_aws').rows.length;
					for (var i=0, iLen=tabl_aws_rows; i<iLen; i++) {
						var tbl_value = $("#tbl_region_"+i).val();
						if ($("#tbl_region_"+i).prop('checked') ) {
							regions.push(available_regions[i]);
						}
					}
					hostcfg.platforms[curPlatform].aliases[hostalias] = {
						hostalias: hostalias,
						host: host,
						api_port: api_port,
						regions: regions,
						interval: interval,
						aws_access_key_id: aws_access_key_id,
						aws_secret_access_key: aws_secret_access_key,
						auth_api: authapi
					};
					if (hostAlias) {
						hostcfg.platforms[curPlatform].aliases[hostalias].updated = TimeStamp();
						hostcfg.platforms[curPlatform].aliases[hostalias].created = created;
						hostcfg.platforms[curPlatform].aliases[hostalias].available_regions = available_regions;
					} else {
						hostcfg.platforms[curPlatform].aliases[hostalias].created = TimeStamp();
					}

					SaveHostsCfg(false);

					var tbl_body = "";
					tbl_body += "<tr style=\"font-size: 12px;\"><td>Loading regions...</td><td><td></tr>";
					$("#tbl_aws tbody").html(tbl_body);

					loadRegions(hostalias, hostcfg.platforms[curPlatform].aliases[hostalias]);

					setTimeout(function(){
						setTimeout(function(){
							reloadHostCfg();
						}, 2000);

						setTimeout(function(){
							var tbl_body = "";
							var curHost = hostcfg.platforms[curPlatform].aliases[hostalias];
							var incl_regions = curHost.regions;

							if (typeof curHost.available_regions == 'undefined') {
								tbl_body += "<tr style=\"font-size: 12px;\"><td>Unable load regions from AWS. Try \"Test conn\"</td><td><td></tr>";
							}

							$.each(curHost.available_regions, function(i, region) {
								var ind = i+1;
								var checked = $.inArray(region, incl_regions);
								var checked_text = "";
								if (checked >= 0) {
									checked_text = "checked";
								} else {
									checked_text = '';
								}
								tbl_body += "<tr style=\"font-size: 12px;\"><td><label>"+region+"</label></td><td><input type=\"checkbox\" id=\"tbl_region_"+i+"\" name=\"tbl_region_"+i+"\" "+checked_text+"><td></tr>";
							});
							$("#tbl_aws tbody").html(tbl_body);
							hostAlias = $("#hostalias").val();
						}, 4000);

					}, 2000);
				},
				text: "Load regions",
				class: 'savecontrol'

			},
			"Test connection": {
				click: function() {
					var hostalias = $("#hostalias").val(),
						host = "aws.amazon.com",
						api_port = "443",
						aws_access_key_id = $("#aws_access_key_id").val(),
						aws_secret_access_key = Base64.encode(uuencode($("#aws_secret_access_key").val())),
						authapi = $("#authapi").val(),
						created = null,
						regions = [],
						interval = parseInt($("#interval").val());
					if (hostAlias) {
						created = hostcfg.platforms[curPlatform].aliases[hostAlias].created;
						available_regions = hostcfg.platforms[curPlatform].aliases[hostAlias].available_regions;
						delete hostcfg.platforms[curPlatform].aliases[hostAlias];
					}
					var tabl_aws_rows = document.getElementById('tbl_aws').rows.length;
					for (var i=0, iLen=tabl_aws_rows; i<iLen; i++) {
						var tbl_value = $("#tbl_region_"+i).val();
						if ($("#tbl_region_"+i).prop('checked') ) {
							regions.push(available_regions[i]);
						}
					}
					hostcfg.platforms[curPlatform].aliases[hostalias] = {
						uuid: $("#uuid").val(),
						hostalias: hostalias,
						interval: interval,
						host: host,
						regions: regions,
						aws_access_key_id: aws_access_key_id,
						aws_secret_access_key: aws_secret_access_key,
						auth_api: authapi
					};
					if (hostAlias) {
						hostcfg.platforms[curPlatform].aliases[hostalias].updated = TimeStamp();
						hostcfg.platforms[curPlatform].aliases[hostalias].created = created;
						hostcfg.platforms[curPlatform].aliases[hostalias].host = "aws.amazon.com";
						hostcfg.platforms[curPlatform].aliases[hostalias].api_port = "443";
						hostcfg.platforms[curPlatform].aliases[hostalias].regions = regions;
						hostcfg.platforms[curPlatform].aliases[hostalias].available_regions = available_regions;
					} else {
						hostcfg.platforms[curPlatform].aliases[hostalias].host = "aws.amazon.com";
						hostcfg.platforms[curPlatform].aliases[hostalias].api_port = "443";
						hostcfg.platforms[curPlatform].aliases[hostalias].created = TimeStamp();
					}
					SaveHostsCfg(false);
					$(this).dialog("close");
					$('#adminmenu a[data-abbr="hosts-' + $("#hosttable").data("platform") + '"]').trigger( "click" );
					testConnection(hostalias, hostcfg.platforms[curPlatform].aliases[hostalias]);

					setTimeout(function(){
						reloadHostCfg();

						var tbl_body = "";
						var curHost = hostcfg.platforms[curPlatform].aliases[hostalias];
						var incl_regions = curHost.regions;
						$.each(curHost.available_regions, function(i, region) {
							var ind = i+1;
							tbl_body += "<tr style=\"font-size: 12px;\"><td><label>"+region+"</label></td><td><input type=\"checkbox\" id=\"tbl_region_"+i+"\" name=\"tbl_region_"+i+"\" ><td></tr>";
						});
					}, 6000);
				},
				text: "Test conn",
				class: 'savecontrol'
			},
			Cancel: function() {
				$(this).dialog("close");
			}
		},
		create: function() {
			var curHost = {};
			var sshkeyel;
			$("button.savecontrol").button("disable");
			$("#hostalias").tooltipster({
				trigger: 'custom',
				position: 'right',
			});
			if (hostAlias) {
				curHost = hostcfg.platforms[curPlatform].aliases[hostAlias];
				$("#hostalias").val(hostAlias);
				$("#uuid").val(curHost.uuid);
				$("#interval").val(curHost.interval);
				$("#aws_access_key_id").val(curHost.aws_access_key_id);
				$("#aws_secret_access_key").val(reveal(curHost.aws_secret_access_key));
				validateHostCfg(curHost);
				$("#authapi").prop('checked', curHost.auth_api);
				$(".showpass").hide();

				var tbl_body = "";
				var incl_regions = curHost.regions;
				$.each(curHost.available_regions, function(i, region) {
					var ind = i+1;
					var checked = $.inArray(region, incl_regions);
					var checked_text = "";
					if (checked >= 0) {
						checked_text = "checked";
					} else {
						checked_text = '';
					}
					tbl_body += "<tr style=\"font-size: 12px;\"><td><label>"+region+"</label></td><td><input type=\"checkbox\" id=\"tbl_region_"+i+"\" name=\"tbl_region_"+i+"\" "+checked_text+"><td></tr>";
				});
				$("#tbl_aws tbody").html(tbl_body);
			} else {
				$("#authapi").prop('checked', hostcfg.platforms[curPlatform].api);
			}
			$(".reqrd, .api").change(function() {
				validateHostCfg(true);
			});

			$(".showpass").button().mousedown(function(e) {
				e.stopPropagation();
				$(this).prev().attr('type','text');
			}).mouseup(function(){
				$(this).prev().attr('type','aws_secret_access_key');
			}).mouseout(function(){
				$(this).prev().attr('type','aws_secret_access_key');
			});
			$("#aws_secret_access_key").on("keyup", function( event ) {
				if ($(this).val()) {
					$(".showpass").button("enable");
				} else {
					$(".showpass").button("disable");
				}
			});
			$("#hostalias").on("blur", function( event ) {
				if (!event.relatedTarget || event.relatedTarget && event.relatedTarget.textContent != "Cancel") {
					if (! this.value) {
						$("#hostalias").tooltipster('content', 'Alias name is required').tooltipster('open');
						$(event.target).addClass( "ui-state-error" );
						$(event.target).trigger("focus");
						// validateHostCfg(curHost);
						$("button.savecontrol").button("disable");
					} else if (this.value != hostAlias && hostcfg.platforms[curPlatform].aliases[this.value]) {
						$("#hostalias").tooltipster('content', 'Host alias already exists!').tooltipster('open');
						$(event.target).addClass( "ui-state-error" );
						$(event.target).trigger("focus");
						// validateHostCfg(curHost);
						$("button.savecontrol").button("disable");
					} else {
						$("#hostalias").tooltipster("close");
						$(event.target).removeClass( "ui-state-error" );
						if (curHost.platform) {
							validateHostCfg(curHost);
						}
						// $("button.savecontrol").button("enable");
					}
				}
			});
		},
		open: function() {
			$('.ui-widget-overlay').addClass('custom-overlay');
		},
		close: function() {
			$(this).find( "form" ).trigger('reset');
			$("#grpname").tooltipster("destroy");
			$(this).dialog("destroy");
		}
	});
}

function hostDetailFormGCloud(hostAlias) {
	var hostDetailFormDiv = '<div id="host-config-form"> \
		<form autocomplete="off" enctype="multipart/form-data" id="gcloudform"> \
		<fieldset> \
		<legend>Options</legend> \
		<input type="hidden" name="uuid" id="uuid" /> \
		<label for="hostalias">Host alias</label> \
		<input type="text" name="hostalias" id="hostalias" class="reqrd" onkeypress="return event.charCode != 95" autocomplete="off" /><br> \
		<label for="username">Credentials file</label> \
		<input type="file" name="credentials" id="file" title="" accept=".json" class="reqrd" /><br> \
		<input type="hidden" name="authapi" id="authapi" value="true"> \
		</fieldset> \
		<fieldset> \
		<legend>Credentials</legend> \
		<div id="cred"><small><b>No credentials file uploaded!</b><br>You have to upload credentials first</small></div> \
		</fieldset> \
		<!-- Allow form submission with keyboard without duplicating the dialog button --> \
		<input type="submit" tabindex="-1" style="position:absolute; top:-1000px"> \
		</form> \
		</div>';
	$( hostDetailFormDiv ).dialog({
		height: 490,
		width: 420,
		modal: true,
		title: "Host configuration",
		buttons: {
			"Save host": {
				click: function() {
					var hostalias = $("#hostalias").val(),
						host = "monitoring.googleapis.com",
						authapi = $("#authapi").val(),
						created = null;
					hostalias = hostalias.replace(/_/g, '');
					var credentials;
					var file = document.getElementById('file').files[0];
					var fr = new FileReader();
					fr.onload = function(e) {
						//console.log(e);
						var result = JSON.parse(e.target.result);
						var formatted = JSON.stringify(result, null, 2);
						var json_obj = JSON.parse(formatted);
						reloadCredentials(json_obj);
						if (typeof json_obj.client_id !== 'undefined') {
							$('#cred').html("<small><b>Credentials Uploaded!</b><br>Client ID: " + json_obj.client_id + "<br>Project ID: " + json_obj.project_id + "</small>");
						} else {
							$('#cred').html("<small><b>Bad credentials file!</b></small>");
						}
					};
					fr.readAsText(file);

					function reloadCredentials(c) {
						credentials = c;
						//console.log(credentials);
						saveGCloud(credentials);
					}

					function saveGCloud(credentials) {

						if (hostAlias) {
							created = hostcfg.platforms[curPlatform].aliases[hostAlias].created;
							delete hostcfg.platforms[curPlatform].aliases[hostAlias];
						}

						hostcfg.platforms[curPlatform].aliases[hostalias] = {
							uuid: $("#uuid").val(),
							hostalias: hostalias,
							host: host,
							auth_api: authapi,
							credentials: credentials,
							username: credentials.client_id
						};
						if (hostAlias) {
							hostcfg.platforms[curPlatform].aliases[hostalias].updated = TimeStamp();
							hostcfg.platforms[curPlatform].aliases[hostalias].created = created;
							hostcfg.platforms[curPlatform].aliases[hostalias].api_port = "443";
						} else {
							hostcfg.platforms[curPlatform].aliases[hostalias].created = TimeStamp();
							hostcfg.platforms[curPlatform].aliases[hostalias].api_port = "443";
						}
						SaveHostsCfg(true);
					}


					//$(this).dialog("close");
					//$('#adminmenu a[data-abbr="hosts-' + $("#hosttable").data("platform") + '"]').trigger( "click" );
				},
				text: "Save host",
				class: 'savecontrol'
			},
			"Test connection": {
				click: function() {
					var hostalias = $("#hostalias").val(),
						host = "monitoring.googleapis.com",
						authapi = $("#authapi").val();

					var credentials;
					var file = document.getElementById('file').files[0];
					var fr = new FileReader();
					fr.onload = function(e) {
						//console.log(e);
						var result = JSON.parse(e.target.result);
						var formatted = JSON.stringify(result, null, 2);
						var json_obj = JSON.parse(formatted);
						reloadCredentials(json_obj);
						if (typeof json_obj.client_id !== 'undefined') {
							$('#cred').html("<small><b>Credentials Uploaded!</b><br>Client ID: " + json_obj.client_id + "<br>Project ID: " + json_obj.project_id + "</small>");
						} else {
							$('#cred').html("<small><b>Bad credentials file!</b></small>");
						}
					};
					fr.readAsText(file);

					function reloadCredentials(c) {
						credentials = c;
						//console.log(credentials);
						saveGCloud(credentials);
					}


					function saveGCloud(credentials) {

						if (hostAlias) {
							var created = hostcfg.platforms[curPlatform].aliases[hostAlias].created;
							delete hostcfg.platforms[curPlatform].aliases[hostAlias];
						}
						hostcfg.platforms[curPlatform].aliases[hostalias] = {
							uuid: $("#uuid").val(),
							hostalias: hostalias,
							host: host,
							auth_api: authapi,
							credentials: credentials,
							username: credentials.client_id
						};
						if (hostAlias) {
							hostcfg.platforms[curPlatform].aliases[hostalias].updated = TimeStamp();
							hostcfg.platforms[curPlatform].aliases[hostalias].created = created;
							hostcfg.platforms[curPlatform].aliases[hostalias].host = "monitoring.googleapis.com";
							hostcfg.platforms[curPlatform].aliases[hostalias].api_port = "443";
						} else {
							hostcfg.platforms[curPlatform].aliases[hostalias].host = "monitoring.googleapis.com";
							hostcfg.platforms[curPlatform].aliases[hostalias].api_port = "443";
							hostcfg.platforms[curPlatform].aliases[hostalias].created = TimeStamp();
						}
						SaveHostsCfg(false);
						$(this).dialog("close");
						$('#adminmenu a[data-abbr="hosts-' + $("#hosttable").data("platform") + '"]').trigger( "click" );
						testConnection(hostalias, hostcfg.platforms[curPlatform].aliases[hostalias]);
					}
				},
				text: "Save & Test connection",
				class: 'savecontrol'
			},
			Cancel: function() {
				$(this).dialog("close");
			}
		},
		create: function() {
			var curHost = {};
			var sshkeyel;
			$("button.savecontrol").button("disable");
			$("#hostalias").tooltipster({
				trigger: 'custom',
				position: 'right',
			});
			if (hostAlias) {
				curHost = hostcfg.platforms[curPlatform].aliases[hostAlias];
				$("#hostalias").val(hostAlias);
				$("#uuid").val(curHost.uuid);
				validateHostCfg(curHost);
				$("#authapi").prop('checked', curHost.auth_api);
				$(".showpass").hide();

				var json_obj = curHost.credentials;
				if (typeof json_obj.client_id !== 'undefined') {
					$('#cred').html("<small><b>Credentials Uploaded!</b><br>Client ID: " + json_obj.client_id + "<br>Project ID: " + json_obj.project_id + "</small>");
				}

			} else {
				$("#authapi").prop('checked', hostcfg.platforms[curPlatform].api);
			}
			$(".reqrd, .api").change(function() {
				validateHostCfg(true);
			});
			$("#hostalias").on("blur", function( event ) {
				if (!event.relatedTarget || event.relatedTarget && event.relatedTarget.textContent != "Cancel") {
					if (! this.value) {
						$("#hostalias").tooltipster('content', 'Alias name is required').tooltipster('open');
						$(event.target).addClass( "ui-state-error" );
						$(event.target).trigger("focus");
						// validateHostCfg(curHost);
						$("button.savecontrol").button("disable");
					} else if (this.value != hostAlias && hostcfg.platforms[curPlatform].aliases[this.value]) {
						$("#hostalias").tooltipster('content', 'Host alias already exists!').tooltipster('open');
						$(event.target).addClass( "ui-state-error" );
						$(event.target).trigger("focus");
						// validateHostCfg(curHost);
						$("button.savecontrol").button("disable");
					} else {
						$("#hostalias").tooltipster("close");
						$(event.target).removeClass( "ui-state-error" );
						if (curHost.platform) {
							validateHostCfg(curHost);
						}
						// $("button.savecontrol").button("enable");
					}
				}
			});
		},
		open: function() {
			$('.ui-widget-overlay').addClass('custom-overlay');
		},
		close: function() {
			$(this).find( "form" ).trigger('reset');
			$("#grpname").tooltipster("destroy");
			$(this).dialog("destroy");
		}
	});
}

function hostDetailFormAzure(hostAlias) {
	var hostDetailFormDiv = '<div id="host-config-form"> \
		<form autocomplete="off"> \
		<fieldset> \
		<legend>Options</legend> \
		<input type="hidden" name="uuid" id="uuid" /> \
		<label for="hostalias">Host alias</label> \
		<input type="text" name="hostalias" id="hostalias" class="reqrd" onkeypress="return event.charCode != 95" autocomplete="off" /><br> \
		<label for="tenant">Tenant ID</label> \
		<input type="text" name="tenant" id="tenant" class="reqrd" title="" autocomplete="off" /><br> \
		<label for="client">Client ID</label> \
		<input type="text" name="client" id="client" class="reqrd" title="" autocomplete="new-password" /><br> \
		<label for="secret">Client Secret</label> \
		<input type="password" name="secret" id="secret" class="reqrd" title="" autocomplete="new-password" /><br> \
		<input type="hidden" name="authapi" id="authapi" value="true"> \
		</fieldset> \
		<fieldset> \
		<legend>Subscriptions</legend> \
		<label for="subscription">Subscription ID</label> \
		<input type="text" name="subscription" id="subscription" class="reqrd" autocomplete="off" /><br> \
		</fieldset> \
	    <fieldset> \
		<legend>Configuration</legend> \
		<label for="container">Allow diagnostics extension *</label> \
		<input type="checkbox" name="diagnostics" id="diagnostics" /><br> \
		</fieldset> \
	    <small>* <a href="https://www.lpar2rrd.com/Azure-diagnostics-extension.php">Azure diagnostics extension</a></small> \
		<!-- Allow form submission with keyboard without duplicating the dialog button --> \
		<input type="submit" tabindex="-1" style="position:absolute; top:-1000px"> \
		</form> \
		</div>';
	$( hostDetailFormDiv ).dialog({
		height: 490,
		width: 420,
		modal: true,
		title: "Host configuration",
		buttons: {
			"Save host": {
				click: function() {
					var hostalias = $("#hostalias").val(),
						host = "management.azure.com",
						api_port = "443",
						tenant = $("#tenant").val(),
						client = $("#client").val(),
						secret = $("#secret").val(),
						subscription = $("#subscription").val(),
						diagnostics = document.getElementById("diagnostics").checked,
						authapi = $("#authapi").val(),
						created = null;
					hostalias = hostalias.replace(/_/g, '');
					if (hostAlias) {
						created = hostcfg.platforms[curPlatform].aliases[hostAlias].created;
						delete hostcfg.platforms[curPlatform].aliases[hostAlias];
					}
					hostcfg.platforms[curPlatform].aliases[hostalias] = {
						uuid: $("#uuid").val(),
						host: host,
						hostalias: hostalias,
						tenant: tenant,
						client: client,
						auth_api: authapi,
						secret: secret,
						diagnostics: diagnostics,
						api_port: api_port
					};
					hostcfg.platforms[curPlatform].aliases[hostalias].subscriptions = [];
					hostcfg.platforms[curPlatform].aliases[hostalias].subscriptions[0] = subscription;
					if (hostAlias) {
						hostcfg.platforms[curPlatform].aliases[hostalias].updated = TimeStamp();
						hostcfg.platforms[curPlatform].aliases[hostalias].created = created;
					} else {
						hostcfg.platforms[curPlatform].aliases[hostalias].created = TimeStamp();
					}
					SaveHostsCfg(true);
					$(this).dialog("close");
					$('#adminmenu a[data-abbr="hosts-' + $("#hosttable").data("platform") + '"]').trigger( "click" );
				},
				text: "Save host",
				class: 'savecontrol'
			},
			"Test connection": {
				click: function() {
					var hostalias = $("#hostalias").val(),
						host = "management.azure.com",
						tenant = $("#tenant").val(),
						client = $("#client").val(),
						secret = $("#secret").val(),
						subscription = $("#subscription").val(),
						diagnostics = document.getElementById("diagnostics").checked,
						authapi = $("#authapi").val(),
						api_port = "443",
						created = null;
					if (hostAlias) {
						created = hostcfg.platforms[curPlatform].aliases[hostAlias].created;
						delete hostcfg.platforms[curPlatform].aliases[hostAlias];
					}
					hostcfg.platforms[curPlatform].aliases[hostalias] = {
						uuid: $("#uuid").val(),
						host: host,
						hostalias: hostalias,
						tenant: tenant,
						client: client,
						auth_api: authapi,
						secret: secret,
						diagnostics: diagnostics,
						api_port: api_port
					};
					hostcfg.platforms[curPlatform].aliases[hostalias].subscriptions = [];
					hostcfg.platforms[curPlatform].aliases[hostalias].subscriptions[0] = subscription;
					if (hostAlias) {
						hostcfg.platforms[curPlatform].aliases[hostalias].updated = TimeStamp();
						hostcfg.platforms[curPlatform].aliases[hostalias].created = created;
					} else {
						hostcfg.platforms[curPlatform].aliases[hostalias].created = TimeStamp();
					}
					SaveHostsCfg(false);
					$(this).dialog("close");
					$('#adminmenu a[data-abbr="hosts-' + $("#hosttable").data("platform") + '"]').trigger( "click" );
					testConnection(hostalias, hostcfg.platforms[curPlatform].aliases[hostalias]);
				},
				text: "Save & Test connection",
				class: 'savecontrol'
			},
			Cancel: function() {
				$(this).dialog("close");
			}
		},
		create: function() {
			var curHost = {};
			var sshkeyel;
			$("button.savecontrol").button("disable");
			$("#hostalias").tooltipster({
				trigger: 'custom',
				position: 'right',
			});
			if (hostAlias) {
				curHost = hostcfg.platforms[curPlatform].aliases[hostAlias];
				$("#hostalias").val(hostAlias);
				$("#uuid").val(curHost.uuid);
				$("#client").val(curHost.client);
				$("#tenant").val(curHost.tenant);
				$("#secret").val(curHost.secret);
				$("#subscription").val(curHost.subscriptions[0]);
				document.getElementById("diagnostics").checked = curHost.diagnostics;
				validateHostCfg(curHost);
				$("#authapi").prop('checked', curHost.auth_api);
			} else {
				$("#authapi").prop('checked', hostcfg.platforms[curPlatform].api);
			}

			$(".reqrd, .api").change(function() {
				validateHostCfg(true);
			});

			$("#hostalias").on("blur", function( event ) {
				if (!event.relatedTarget || event.relatedTarget && event.relatedTarget.textContent != "Cancel") {
					if (! this.value) {
						$("#hostalias").tooltipster('content', 'Alias name is required').tooltipster('open');
						$(event.target).addClass( "ui-state-error" );
						$(event.target).trigger("focus");
						// validateHostCfg(curHost);
						$("button.savecontrol").button("disable");
					} else if (this.value != hostAlias && hostcfg.platforms[curPlatform].aliases[this.value]) {
						$("#hostalias").tooltipster('content', 'Host alias already exists!').tooltipster('open');
						$(event.target).addClass( "ui-state-error" );
						$(event.target).trigger("focus");
						// validateHostCfg(curHost);
						$("button.savecontrol").button("disable");
					} else {
						$("#hostalias").tooltipster("close");
						$(event.target).removeClass( "ui-state-error" );
						if (curHost.platform) {
							validateHostCfg(curHost);
						}
						// $("button.savecontrol").button("enable");
					}
				}
			});
		},
		open: function() {
			$('.ui-widget-overlay').addClass('custom-overlay');
		},
		close: function() {
			$(this).find( "form" ).trigger('reset');
			$("#grpname").tooltipster("destroy");
			$(this).dialog("destroy");
		}
	});
}

function hostDetailFormKubernetes(hostAlias) {
	var hostDetailFormDiv = '<div id="host-config-form"> \
		<form autocomplete="off"> \
		<fieldset> \
		<legend>Options</legend> \
		<input type="hidden" name="uuid" id="uuid" /> \
		<label for="hostalias">Host alias</label> \
		<input type="text" name="hostalias" id="hostalias" class="reqrd" onkeypress="return event.charCode != 95" autocomplete="off" /><br> \
		<label for="protocol">Protocol</label> \
		<select name="protocol" id="protocol">\
		<option value="https">HTTPS</option>\
		<option value="http">HTTP</option>\
		</select><br>\
		<label for="host">Endpoint</label> \
		<input type="text" name="host" id="host" class="reqrd" title="" autocomplete="off" placeholder="<ip>:<port>" /><br> \
		<label for="token">Token</label> \
		<input type="text" name="token" id="token" class="reqrd" title="" autocomplete="nope" /><br> \
		<input type="hidden" name="authapi" id="authapi" value="true"> \
        <label for="monitor">Monitor level</label> \
        <select name="monitor" id="monitor"> \
        <option value="1">Nodes & Namespaces</option> \
        <option value="2">Nodes, Namespaces & Pods</option> \
        <option value="3">Nodes, Namespaces, Pods & Containers</option> \
        </select> \
	    <input type="hidden" name="container" id="container" value="0"> \
        </fieldset> \
	    <fieldset> \
		<legend>Namespaces to monitor</legend> \
	    <div style="text-align: right;"><small><a href="#" id="selectAll" onclick="event.preventDefault();var tabl_k8s_rows = document.getElementById(\'tbl_k8s\').rows.length;for (var i=0, iLen=tabl_k8s_rows; i<iLen; i++) { $(\'#tbl_namespace_\'+i).prop( \'checked\', true );  } ">select all</a></small></div> \
		<table id="tbl_k8s" width="100%"><tr><td><small>Enter endpoint & token before load namespaces</small></td><td></td></tr></table> \
		</fieldset> \
	    <small><i>Containers & Pods statistics can occupy 30-60% of data space for Kubernetes / OpenShift on LPAR2RRD server.<br>Its collection using also CPU resources on LPAR2RRD server.</i></small> \
		<!-- Allow form submission with keyboard without duplicating the dialog button --> \
		<input type="submit" tabindex="-1" style="position:absolute; top:-1000px"> \
		</form> \
		</div>';
	$( hostDetailFormDiv ).dialog({
		height: 490,
		width: 420,
		modal: true,
		title: "Host configuration",
		buttons: {
			"Save host": {
				click: function() {
					var hostalias = $("#hostalias").val(),
						host = $("#host").val(),
						protocol = $("#protocol").val(),
						token = $("#token").val(),
						container = document.getElementById("container").checked,
						monitor = $("#monitor").val(),
						authapi = $("#authapi").val(),
						uuid = $("#uuid").val(),
						namespaces = [],
						created = null;
					hostalias = hostalias.replace(/_/g, '');
					if (hostAlias) {
						created = hostcfg.platforms[curPlatform].aliases[hostAlias].created;
						available_namespaces = hostcfg.platforms[curPlatform].aliases[hostAlias].available_namespaces;
						delete hostcfg.platforms[curPlatform].aliases[hostAlias];
					}
					var tabl_k8s_rows = document.getElementById('tbl_k8s').rows.length;
					for (var i=0, iLen=tabl_k8s_rows; i<iLen; i++) {
						var tbl_value = $("#tbl_namespace_"+i).val();
						if ($("#tbl_namespace_"+i).prop('checked') ) {
							namespaces.push(available_namespaces[i]);
						}
					}
					hostcfg.platforms[curPlatform].aliases[hostalias] = {
						uuid: uuid,
						host: host,
						hostalias: hostalias,
						protocol: protocol,
						token: token,
						monitor: monitor,
						container: container,
						auth_api: authapi,
						namespaces: namespaces,
					};
					if (hostAlias) {
						hostcfg.platforms[curPlatform].aliases[hostalias].updated = TimeStamp();
						hostcfg.platforms[curPlatform].aliases[hostalias].created = created;
						hostcfg.platforms[curPlatform].aliases[hostalias].available_namespaces = available_namespaces;
					} else {
						hostcfg.platforms[curPlatform].aliases[hostalias].created = TimeStamp();
					}
					SaveHostsCfg(true);
					$(this).dialog("close");
					$('#adminmenu a[data-abbr="hosts-' + $("#hosttable").data("platform") + '"]').trigger( "click" );
				},
				text: "Save",
				class: 'savecontrol'
			},
			"Load namespaces" : {
				click: function() {
					var hostalias = $("#hostalias").val(),
						host = $("#host").val(),
						protocol = $("#protocol").val(),
						token = $("#token").val(),
						monitor = $("#monitor").val(),
						container = document.getElementById("container").checked,
						authapi = $("#authapi").val(),
						uuid = $("#uuid").val(),
						created = null,
					    namespaces = [];
					hostalias = hostalias.replace(/_/g, '');
					if (hostAlias) {
						created = hostcfg.platforms[curPlatform].aliases[hostAlias].created;
						available_namespaces = hostcfg.platforms[curPlatform].aliases[hostAlias].available_namespaces;
						delete hostcfg.platforms[curPlatform].aliases[hostAlias];
					}
					var tabl_k8s_rows = document.getElementById('tbl_k8s').rows.length;
					for (var i=0, iLen=tabl_k8s_rows; i<iLen; i++) {
						var tbl_value = $("#tbl_namespace_"+i).val();
						if ($("#tbl_namespace_"+i).prop('checked') ) {
							namespaces.push(available_namespaces[i]);
						}
					}
					hostcfg.platforms[curPlatform].aliases[hostalias] = {
						uuid: uuid,
						host: host,
						hostalias: hostalias,
						protocol: protocol,
						token: token,
						monitor: monitor,
						container: container,
						auth_api: authapi,
						namespaces: namespaces,
					};
					if (hostAlias) {
						hostcfg.platforms[curPlatform].aliases[hostalias].updated = TimeStamp();
						hostcfg.platforms[curPlatform].aliases[hostalias].created = created;
					} else {
						hostcfg.platforms[curPlatform].aliases[hostalias].created = TimeStamp();
					}
					SaveHostsCfg(false);

					var tbl_body = "";
					tbl_body += "<tr style=\"font-size: 12px;\"><td>Loading namespaces...</td><td><td></tr>";
					$("#tbl_k8s tbody").html(tbl_body);

					loadNamespaces(hostalias, hostcfg.platforms[curPlatform].aliases[hostalias]);

					setTimeout(function(){
						setTimeout(function(){
							reloadHostCfg();
						}, 2000);

						setTimeout(function(){
							var tbl_body = "";
							var curHost = hostcfg.platforms[curPlatform].aliases[hostalias];
							var incl_namespaces = curHost.namespaces;

							if (typeof curHost.available_namespaces == 'undefined') {
								tbl_body += "<tr style=\"font-size: 12px;\"><td>Unable load namespaces. Try \"Test conn\"</td><td><td></tr>";
							}

							$.each(curHost.available_namespaces, function(i, namespace) {
								var ind = i+1;
								var checked = $.inArray(namespace, incl_namespaces);
								var checked_text = "";
								if (checked >= 0) {
									checked_text = "checked";
								} else {
									checked_text = '';
								}
								tbl_body += "<tr style=\"font-size: 12px;\"><td><label>"+namespace+"</label></td><td><input type=\"checkbox\" id=\"tbl_namespace_"+i+"\" name=\"tbl_namespace_"+i+"\" "+checked_text+"><td></tr>";
							});
							$("#tbl_k8s tbody").html(tbl_body);
							hostAlias = $("#hostalias").val();
						}, 4000);

					}, 2000);
				},
				text: "Load namespaces",
				class: 'savecontrol'
			},
			"Test connection": {
				click: function() {
					var hostalias = $("#hostalias").val(),
						host = $("#host").val(),
						protocol = $("#protocol").val(),
						token = $("#token").val(),
						monitor = $("#monitor").val(),
						container = document.getElementById("container").checked,
						authapi = $("#authapi").val(),
						uuid = $("#uuid").val(),
						namespaces = [],
						created = null;
					hostalias = hostalias.replace(/_/g, '');
					if (hostAlias) {
						created = hostcfg.platforms[curPlatform].aliases[hostAlias].created;
						available_namespaces = hostcfg.platforms[curPlatform].aliases[hostAlias].available_namespaces;
						delete hostcfg.platforms[curPlatform].aliases[hostAlias];
					}
					var tabl_k8s_rows = document.getElementById('tbl_k8s').rows.length;
					for (var i=0, iLen=tabl_k8s_rows; i<iLen; i++) {
						var tbl_value = $("#tbl_namespace_"+i).val();
						if ($("#tbl_namespace_"+i).prop('checked') ) {
							namespaces.push(available_namespaces[i]);
						}
					}
					hostcfg.platforms[curPlatform].aliases[hostalias] = {
						uuid: uuid,
						host: host,
						hostalias: hostalias,
						protocol: protocol,
						token: token,
						monitor: monitor,
						container: container,
						auth_api: authapi,
						namespaces: namespaces,
					};
					if (hostAlias) {
						hostcfg.platforms[curPlatform].aliases[hostalias].updated = TimeStamp();
						hostcfg.platforms[curPlatform].aliases[hostalias].created = created;
						hostcfg.platforms[curPlatform].aliases[hostalias].available_namespaces = available_namespaces;
					} else {
						hostcfg.platforms[curPlatform].aliases[hostalias].created = TimeStamp();
					}
					SaveHostsCfg(false);
					$(this).dialog("close");
					$('#adminmenu a[data-abbr="hosts-' + $("#hosttable").data("platform") + '"]').trigger( "click" );
					testConnection(hostalias, hostcfg.platforms[curPlatform].aliases[hostalias]);

					setTimeout(function(){
						reloadHostCfg();

						var tbl_body = "";
						var curHost = hostcfg.platforms[curPlatform].aliases[hostalias];
						var incl_namespaces = curHost.namespaces;
						$.each(curHost.available_namespaces, function(i, namespace) {
							var ind = i+1;
							tbl_body += "<tr style=\"font-size: 12px;\"><td><label>"+namespace+"</label></td><td><input type=\"checkbox\" id=\"tbl_namespace_"+i+"\" name=\"tbl_namespace_"+i+"\" ><td></tr>";
						});
					}, 6000);
				},
				text: "Test conn",
				class: 'savecontrol'
			},
			Cancel: function() {
				$(this).dialog("close");
			}
		},
		create: function() {
			var curHost = {};
			var sshkeyel;
			$("button.savecontrol").button("disable");
			$("#hostalias").tooltipster({
				trigger: 'custom',
				position: 'right',
			});
			if (hostAlias) {
				curHost = hostcfg.platforms[curPlatform].aliases[hostAlias];
				$("#hostalias").val(hostAlias);
				$("#uuid").val(curHost.uuid);
				$("#protocol").val(curHost.protocol);
				$("#token").val(curHost.token);
				$("#monitor").val(curHost.monitor);
				$("#host").val(curHost.host);
				document.getElementById("container").checked = curHost.container;
				validateHostCfg(curHost);
				$("#authapi").prop('checked', curHost.auth_api);

				var tbl_body = "";
				var incl_namespaces = curHost.namespaces;
				$.each(curHost.available_namespaces, function(i, namespace) {
					var ind = i+1;
					var checked = $.inArray(namespace, incl_namespaces);
					var checked_text = "";
					if (checked >= 0) {
						checked_text = "checked";
					} else {
						checked_text = '';
					}
					tbl_body += "<tr style=\"font-size: 12px;\"><td><label>"+namespace+"</label></td><td><input type=\"checkbox\" id=\"tbl_namespace_"+i+"\" name=\"tbl_namespace_"+i+"\" "+checked_text+"><td></tr>";
				});
				$("#tbl_k8s tbody").html(tbl_body);
			} else {
				$("#authapi").prop('checked', hostcfg.platforms[curPlatform].auth_api);
			}

			$(".reqrd, .api").change(function() {
				validateHostCfg(true);
			});

			$("#hostalias").on("blur", function( event ) {
				if (!event.relatedTarget || event.relatedTarget && event.relatedTarget.textContent != "Cancel") {
					if (! this.value) {
						$("#hostalias").tooltipster('content', 'Alias name is required').tooltipster('open');
						$(event.target).addClass( "ui-state-error" );
						$(event.target).trigger("focus");
						// validateHostCfg(curHost);
						$("button.savecontrol").button("disable");
					} else if (this.value != hostAlias && hostcfg.platforms[curPlatform].aliases[this.value]) {
						$("#hostalias").tooltipster('content', 'Host alias already exists!').tooltipster('open');
						$(event.target).addClass( "ui-state-error" );
						$(event.target).trigger("focus");
						// validateHostCfg(curHost);
						$("button.savecontrol").button("disable");
					} else {
						$("#hostalias").tooltipster("close");
						$(event.target).removeClass( "ui-state-error" );
						if (curHost.platform) {
							validateHostCfg(curHost);
						}
						// $("button.savecontrol").button("enable");
					}
				}
			});
		},
		open: function() {
			$('.ui-widget-overlay').addClass('custom-overlay');
		},
		close: function() {
			$(this).find( "form" ).trigger('reset');
			$("#grpname").tooltipster("destroy");
			$(this).dialog("destroy");
		}
	});
}

function hostDetailFormCloudstack(hostAlias) {
	var hostDetailFormDiv = '<div id="host-config-form"> \
		<form autocomplete="off"> \
		<fieldset> \
		<legend>Options</legend> \
		<input type="hidden" name="uuid" id="uuid" /> \
		<label for="hostalias">Host alias</label> \
		<input type="text" name="hostalias" id="hostalias" class="reqrd" onkeypress="return event.charCode != 95" autocomplete="off" /><br> \
		<label for="protocol">Protocol</label> \
		<select name="protocol" id="protocol">\
		<option value="https">HTTPS</option>\
		<option value="http">HTTP</option>\
		</select>\
		<label for="host">Host</label> \
		<input type="text" name="host" id="host" class="reqrd" title="" autocomplete="off" /><br> \
		<label for="token">Port</label> \
		<input type="text" name="api_port" id="api_port" class="reqrd" title="" autocomplete="nope" /><br> \
		<label for="token">Username</label> \
		<input type="text" name="username" id="username" class="reqrd" title="" autocomplete="nope" /><br> \
		<label for="token">Password</label> \
		<input type="password" name="password" id="password" class="reqrd" title="" autocomplete="nope" /><br> \
		<input type="hidden" name="authapi" id="authapi" value="true"> \
		<!-- Allow form submission with keyboard without duplicating the dialog button --> \
		<input type="submit" tabindex="-1" style="position:absolute; top:-1000px"> \
		</form> \
		</div>';
		$( hostDetailFormDiv ).dialog({
		height: 490,
		width: 420,
		modal: true,
		title: "Host configuration",
		buttons: {
			"Save host": {
				click: function() {
					var hostalias = $("#hostalias").val(),
						host = $("#host").val(),
						protocol = $("#protocol").val(),
						api_port = $("#api_port").val(),
						username = $("#username").val(),
						password = Base64.encode(uuencode($("#password").val())),
						authapi = $("#authapi").val(),
						created = null;
					hostalias = hostalias.replace(/_/g, '');
					if (hostAlias) {
						created = hostcfg.platforms[curPlatform].aliases[hostAlias].created;
						delete hostcfg.platforms[curPlatform].aliases[hostAlias];
					}
					hostcfg.platforms[curPlatform].aliases[hostalias] = {
						uuid: $("#uuid").val(),
						host: host,
						hostalias: hostalias,
						protocol: protocol,
						api_port: api_port,
						username: username,
						password: password,
						auth_api: authapi,
					};
					if (hostAlias) {
						hostcfg.platforms[curPlatform].aliases[hostalias].updated = TimeStamp();
						hostcfg.platforms[curPlatform].aliases[hostalias].created = created;
					} else {
						hostcfg.platforms[curPlatform].aliases[hostalias].created = TimeStamp();
					}
					SaveHostsCfg(true);
					$(this).dialog("close");
					$('#adminmenu a[data-abbr="hosts-' + $("#hosttable").data("platform") + '"]').trigger( "click" );
				},
				text: "Save host",
				class: 'savecontrol'
			},
			"Test connection": {
				click: function() {
					var hostalias = $("#hostalias").val(),
						host = $("#host").val(),
						protocol = $("#protocol").val(),
						api_port = $("#api_port").val(),
						username = $("#username").val(),
						password = Base64.encode(uuencode($("#password").val())),
						authapi = $("#authapi").val(),
						created = null;
					hostalias = hostalias.replace(/_/g, '');
					if (hostAlias) {
						created = hostcfg.platforms[curPlatform].aliases[hostAlias].created;
						delete hostcfg.platforms[curPlatform].aliases[hostAlias];
					}
					hostcfg.platforms[curPlatform].aliases[hostalias] = {
						uuid: $("#uuid").val(),
						host: host,
						hostalias: hostalias,
						protocol: protocol,
						api_port: api_port,
						username: username,
						password: password,
						auth_api: authapi,
					};
					if (hostAlias) {
						hostcfg.platforms[curPlatform].aliases[hostalias].updated = TimeStamp();
						hostcfg.platforms[curPlatform].aliases[hostalias].created = created;
					} else {
						hostcfg.platforms[curPlatform].aliases[hostalias].created = TimeStamp();
					}
					SaveHostsCfg(false);
					$(this).dialog("close");
					$('#adminmenu a[data-abbr="hosts-' + $("#hosttable").data("platform") + '"]').trigger( "click" );
					testConnection(hostalias, hostcfg.platforms[curPlatform].aliases[hostalias]);
				},
				text: "Save & Test connection",
				class: 'savecontrol'
			},
			Cancel: function() {
				$(this).dialog("close");
			}
		},
		create: function() {
			var curHost = {};
			var sshkeyel;
			$("button.savecontrol").button("disable");
			$("#hostalias").tooltipster({
				trigger: 'custom',
				position: 'right',
			});
			if (hostAlias) {
				curHost = hostcfg.platforms[curPlatform].aliases[hostAlias];
				$("#hostalias").val(hostAlias);
				$("#uuid").val(curHost.uuid);
				$("#protocol").val(curHost.protocol);
				$("#api_port").val(curHost.api_port);
				$("#username").val(curHost.username);
				if (curHost.password === true) {
					$("#password").attr("placeholder", "Don't fill to keep current");
					$("#password").addClass("keepass");
				} else {
					$("#password").val(reveal(curHost.password));
				}
				$("#host").val(curHost.host);
				validateHostCfg(curHost);
				$("#authapi").prop('checked', curHost.auth_api);
			} else {
				$("#authapi").prop('checked', hostcfg.platforms[curPlatform].auth_api);
			}

			$(".reqrd, .api").change(function() {
				validateHostCfg(true);
			});

			$("#hostalias").on("blur", function( event ) {
				if (!event.relatedTarget || event.relatedTarget && event.relatedTarget.textContent != "Cancel") {
					if (! this.value) {
						$("#hostalias").tooltipster('content', 'Alias name is required').tooltipster('open');
						$(event.target).addClass( "ui-state-error" );
						$(event.target).trigger("focus");
						// validateHostCfg(curHost);
						$("button.savecontrol").button("disable");
					} else if (this.value != hostAlias && hostcfg.platforms[curPlatform].aliases[this.value]) {
						$("#hostalias").tooltipster('content', 'Host alias already exists!').tooltipster('open');
						$(event.target).addClass( "ui-state-error" );
						$(event.target).trigger("focus");
						// validateHostCfg(curHost);
						$("button.savecontrol").button("disable");
					} else {
						$("#hostalias").tooltipster("close");
						$(event.target).removeClass( "ui-state-error" );
						if (curHost.platform) {
							validateHostCfg(curHost);
						}
						// $("button.savecontrol").button("enable");
					}
				}
			});
		},
		open: function() {
			$('.ui-widget-overlay').addClass('custom-overlay');
		},
		close: function() {
			$(this).find( "form" ).trigger('reset');
			$("#grpname").tooltipster("destroy");
			$(this).dialog("destroy");
		}
	});
}

function hostDetailFormProxmox(hostAlias) {
	var hostDetailFormDiv = '<div id="host-config-form"> \
		<form autocomplete="off"> \
		<fieldset> \
		<legend>Options</legend> \
		<input type="hidden" name="uuid" id="uuid" /> \
		<label for="hostalias">Host alias</label> \
		<input type="text" name="hostalias" id="hostalias" class="reqrd" onkeypress="return event.charCode != 95" autocomplete="off" /><br> \
		<label for="protocol">Protocol</label> \
		<select name="protocol" id="protocol">\
		<option value="https">HTTPS</option>\
		<option value="http">HTTP</option>\
		</select><br>\
		<label for="host">Host</label> \
		<input type="text" name="host" id="host" class="reqrd" title="" autocomplete="off" /><br> \
		<label for="backup_host">Backup Host</label> \
		<input type="text" name="backup_host" id="backup_host" title="" autocomplete="off" /><br> \
		<label for="domain">Realm</label> \
	    <select name="domain" id="domain">\
	    <option value="pve">Proxmox VE authentication server</option>\
	    <option value="pam">Linux PAM standard auth</option>\
		</select><br>\
		<label for="api_port">Port</label> \
		<input type="number" name="api_port" id="api_port" class="reqrd" title="" autocomplete="nope" /><br> \
		<label for="username">Username</label> \
		<input type="text" name="username" id="username" class="reqrd" title="" autocomplete="nope" /><br> \
		<label for="password">Password</label> \
		<input type="password" name="password" id="password" class="reqrd" title="" autocomplete="nope" /><br> \
		<input type="hidden" name="authapi" id="authapi" value="true"> \
		<!-- Allow form submission with keyboard without duplicating the dialog button --> \
		<input type="submit" tabindex="-1" style="position:absolute; top:-1000px"> \
		</form> \
		</div>';
		$( hostDetailFormDiv ).dialog({
		height: 490,
		width: 420,
		modal: true,
		title: "Host configuration",
		buttons: {
			"Save host": {
				click: function() {
					var hostalias = $("#hostalias").val(),
						host = $("#host").val(),
						backup_host = $("#backup_host").val(),
						domain = $("#domain").val(),
						protocol = $("#protocol").val(),
						api_port = $("#api_port").val(),
						username = $("#username").val(),
						password = Base64.encode(uuencode($("#password").val().replace(" ", "%20"))),
						authapi = $("#authapi").val(),
						created = null;
					hostalias = hostalias.replace(/_/g, '');
					if (hostAlias) {
						created = hostcfg.platforms[curPlatform].aliases[hostAlias].created;
						delete hostcfg.platforms[curPlatform].aliases[hostAlias];
					}
					hostcfg.platforms[curPlatform].aliases[hostalias] = {
						uuid: $("#uuid").val(),
						host: host,
						backup_host: backup_host,
						domain: domain,
						hostalias: hostalias,
						protocol: protocol,
						api_port: api_port,
						username: username,
						password: password,
						auth_api: authapi,
					};
					if (hostAlias) {
						hostcfg.platforms[curPlatform].aliases[hostalias].updated = TimeStamp();
						hostcfg.platforms[curPlatform].aliases[hostalias].created = created;
					} else {
						hostcfg.platforms[curPlatform].aliases[hostalias].created = TimeStamp();
					}
					SaveHostsCfg(true);
					$(this).dialog("close");
					$('#adminmenu a[data-abbr="hosts-' + $("#hosttable").data("platform") + '"]').trigger( "click" );
				},
				text: "Save host",
				class: 'savecontrol'
			},
			"Test connection": {
				click: function() {
					var hostalias = $("#hostalias").val(),
						host = $("#host").val(),
						backup_host = $("#backup_host").val(),
						domain = $("#domain").val(),
						protocol = $("#protocol").val(),
						api_port = $("#api_port").val(),
						username = $("#username").val(),
						password = Base64.encode(uuencode($("#password").val().replace(" ", "%20"))),
						authapi = $("#authapi").val(),
						created = null;
					hostalias = hostalias.replace(/_/g, '');
					if (hostAlias) {
						created = hostcfg.platforms[curPlatform].aliases[hostAlias].created;
						delete hostcfg.platforms[curPlatform].aliases[hostAlias];
					}
					hostcfg.platforms[curPlatform].aliases[hostalias] = {
						uuid: $("#uuid").val(),
						host: host,
						backup_host: backup_host,
						domain: domain,
						hostalias: hostalias,
						protocol: protocol,
						api_port: api_port,
						username: username,
						password: password,
						auth_api: authapi,
					};
					if (hostAlias) {
						hostcfg.platforms[curPlatform].aliases[hostalias].updated = TimeStamp();
						hostcfg.platforms[curPlatform].aliases[hostalias].created = created;
					} else {
						hostcfg.platforms[curPlatform].aliases[hostalias].created = TimeStamp();
					}
					SaveHostsCfg(false);
					$(this).dialog("close");
					$('#adminmenu a[data-abbr="hosts-' + $("#hosttable").data("platform") + '"]').trigger( "click" );
					testConnection(hostalias, hostcfg.platforms[curPlatform].aliases[hostalias]);
				},
				text: "Save & Test connection",
				class: 'savecontrol'
			},
			Cancel: function() {
				$(this).dialog("close");
			}
		},
		create: function() {
			var curHost = {};
			var sshkeyel;
			$("button.savecontrol").button("disable");
			$("#hostalias").tooltipster({
				trigger: 'custom',
				position: 'right',
			});
			if (hostAlias) {
				curHost = hostcfg.platforms[curPlatform].aliases[hostAlias];
				$("#hostalias").val(hostAlias);
				$("#uuid").val(curHost.uuid);
				$("#protocol").val(curHost.protocol);
				$("#api_port").val(curHost.api_port);
				$("#username").val(curHost.username);
				if (curHost.password === true) {
					$("#password").attr("placeholder", "Don't fill to keep current");
					$("#password").addClass("keepass");
					$("#password").removeClass("reqrd");
				} else {
					$("#password").val(reveal(curHost.password));
				}
				$("#host").val(curHost.host);
				$("#backup_host").val(curHost.backup_host);
				$("#domain").val(curHost.domain);
				validateHostCfg(curHost);
				$("#authapi").prop('checked', curHost.auth_api);
			} else {
				$("#authapi").prop('checked', hostcfg.platforms[curPlatform].auth_api);
			}

			$(".reqrd, .api").change(function() {
				validateHostCfg(true);
			});

			$("#hostalias").on("blur", function( event ) {
				if (!event.relatedTarget || event.relatedTarget && event.relatedTarget.textContent != "Cancel") {
					if (! this.value) {
						$("#hostalias").tooltipster('content', 'Alias name is required').tooltipster('open');
						$(event.target).addClass( "ui-state-error" );
						$(event.target).trigger("focus");
						// validateHostCfg(curHost);
						$("button.savecontrol").button("disable");
					} else if (this.value != hostAlias && hostcfg.platforms[curPlatform].aliases[this.value]) {
						$("#hostalias").tooltipster('content', 'Host alias already exists!').tooltipster('open');
						$(event.target).addClass( "ui-state-error" );
						$(event.target).trigger("focus");
						// validateHostCfg(curHost);
						$("button.savecontrol").button("disable");
					} else {
						$("#hostalias").tooltipster("close");
						$(event.target).removeClass( "ui-state-error" );
						if (curHost.platform) {
							validateHostCfg(curHost);
						}
						// $("button.savecontrol").button("enable");
					}
				}
			});
		},
		open: function() {
			$('.ui-widget-overlay').addClass('custom-overlay');
		},
		close: function() {
			$(this).find( "form" ).trigger('reset');
			$("#grpname").tooltipster("destroy");
			$(this).dialog("destroy");
		}
	});
}

function hostDetailFormFusionCompute(hostAlias) {
	var hostDetailFormDiv = '<div id="host-config-form"> \
		<form autocomplete="off"> \
		<fieldset> \
		<legend>Options</legend> \
		<input type="hidden" name="uuid" id="uuid" /> \
		<label for="hostalias">Host alias</label> \
		<input type="text" name="hostalias" id="hostalias" class="reqrd" onkeypress="return event.charCode != 95" autocomplete="off" /><br> \
		<label for="protocol">Protocol</label> \
		<select name="proto" id="proto">\
		<option value="https">HTTPS</option>\
		<option value="http">HTTP</option>\
		</select><br>\
	    <label for="version">Version</label> \
	    <select name="version" id="version"> \
	    <option value="v8.0">8.0</option> \
	    <option value="v6.5">6.5</option> \
	    <option value="v6.1">6.1</option> \
	    </select><br> \
		<label for="host">Host</label> \
		<input type="text" name="host" id="host" class="reqrd" title="" autocomplete="off" /><br> \
		<label for="api_port">Port</label> \
		<input type="text" name="api_port" id="api_port" class="reqrd" title="" placeholder="7443" autocomplete="nope" /><br> \
		<label for="usertype">User type</label> \
		<select name="usertype" id="usertype">\
		<option value="0">Local user</option>\
		<option value="1">Domain user</option>\
		<option value="2">Interface interconnection user</option>\
		</select><br>\
		<label for="username">Username</label> \
		<input type="text" name="username" id="username" class="reqrd" title="" autocomplete="nope" /><br> \
		<label for="token">Password</label> \
		<input type="password" name="password" id="password" class="reqrd" title="" autocomplete="nope" /><br> \
		<input type="hidden" name="authapi" id="authapi" value="true"> \
		<!-- Allow form submission with keyboard without duplicating the dialog button --> \
		<input type="submit" tabindex="-1" style="position:absolute; top:-1000px"> \
		</form> \
		</div>';
		$( hostDetailFormDiv ).dialog({
		height: 490,
		width: 420,
		modal: true,
		title: "Host configuration",
		buttons: {
			"Save host": {
				click: function() {
					var hostalias = $("#hostalias").val(),
						host = $("#host").val(),
						version = $("#version").val(),
						usertype = $("#usertype").val(),
						proto = $("#proto").val(),
						api_port = $("#api_port").val(),
						username = $("#username").val(),
						password = Base64.encode(uuencode($("#password").val().replace(" ", "%20"))),
						authapi = $("#authapi").val(),
						created = null;
					hostalias = hostalias.replace(/_/g, '');
					if (hostAlias) {
						created = hostcfg.platforms[curPlatform].aliases[hostAlias].created;
						delete hostcfg.platforms[curPlatform].aliases[hostAlias];
					}
					hostcfg.platforms[curPlatform].aliases[hostalias] = {
						uuid: $("#uuid").val(),
						host: host,
						version: version,
						usertype: usertype,
						hostalias: hostalias,
						proto: proto,
						api_port: api_port,
						username: username,
						password: password,
						auth_api: authapi,
					};
					if (hostAlias) {
						hostcfg.platforms[curPlatform].aliases[hostalias].updated = TimeStamp();
						hostcfg.platforms[curPlatform].aliases[hostalias].created = created;
					} else {
						hostcfg.platforms[curPlatform].aliases[hostalias].created = TimeStamp();
					}
					SaveHostsCfg(true);
					$(this).dialog("close");
					$('#adminmenu a[data-abbr="hosts-' + $("#hosttable").data("platform") + '"]').trigger( "click" );
				},
				text: "Save host",
				class: 'savecontrol'
			},
			"Test connection": {
				click: function() {
					var hostalias = $("#hostalias").val(),
						host = $("#host").val(),
						version = $("#version").val(),
						usertype = $("#usertype").val(),
						proto = $("#proto").val(),
						api_port = $("#api_port").val(),
						username = $("#username").val(),
						password = Base64.encode(uuencode($("#password").val().replace(" ", "%20"))),
						authapi = $("#authapi").val(),
						created = null;
					hostalias = hostalias.replace(/_/g, '');
					if (hostAlias) {
						created = hostcfg.platforms[curPlatform].aliases[hostAlias].created;
						delete hostcfg.platforms[curPlatform].aliases[hostAlias];
					}
					hostcfg.platforms[curPlatform].aliases[hostalias] = {
						uuid: $("#uuid").val(),
						host: host,
						version: version,
						usertype: usertype,
						hostalias: hostalias,
						proto: proto,
						api_port: api_port,
						username: username,
						password: password,
						auth_api: authapi,
					};
					if (hostAlias) {
						hostcfg.platforms[curPlatform].aliases[hostalias].updated = TimeStamp();
						hostcfg.platforms[curPlatform].aliases[hostalias].created = created;
					} else {
						hostcfg.platforms[curPlatform].aliases[hostalias].created = TimeStamp();
					}
					SaveHostsCfg(false);
					$(this).dialog("close");
					$('#adminmenu a[data-abbr="hosts-' + $("#hosttable").data("platform") + '"]').trigger( "click" );
					testConnection(hostalias, hostcfg.platforms[curPlatform].aliases[hostalias]);
				},
				text: "Save & Test connection",
				class: 'savecontrol'
			},
			Cancel: function() {
				$(this).dialog("close");
			}
		},
		create: function() {
			var curHost = {};
			var sshkeyel;
			$("button.savecontrol").button("disable");
			$("#hostalias").tooltipster({
				trigger: 'custom',
				position: 'right',
			});
			if (hostAlias) {
				curHost = hostcfg.platforms[curPlatform].aliases[hostAlias];
				$("#hostalias").val(hostAlias);
				$("#uuid").val(curHost.uuid);
				$("#version").val(curHost.version);
				$("#proto").val(curHost.proto);
				$("#api_port").val(curHost.api_port);
				$("#username").val(curHost.username);
				if (curHost.password === true) {
					$("#password").attr("placeholder", "Don't fill to keep current");
					$("#password").addClass("keepass");
				} else {
					$("#password").val(reveal(curHost.password));
				}
				$("#host").val(curHost.host);
				$("#usertype").val(curHost.usertype);
				validateHostCfg(curHost);
				$("#authapi").prop('checked', curHost.auth_api);
			} else {
				$("#authapi").prop('checked', hostcfg.platforms[curPlatform].auth_api);
			}

			$(".reqrd, .api").change(function() {
				validateHostCfg(true);
			});

			$("#hostalias").on("blur", function( event ) {
				if (!event.relatedTarget || event.relatedTarget && event.relatedTarget.textContent != "Cancel") {
					if (! this.value) {
						$("#hostalias").tooltipster('content', 'Alias name is required').tooltipster('open');
						$(event.target).addClass( "ui-state-error" );
						$(event.target).trigger("focus");
						// validateHostCfg(curHost);
						$("button.savecontrol").button("disable");
					} else if (this.value != hostAlias && hostcfg.platforms[curPlatform].aliases[this.value]) {
						$("#hostalias").tooltipster('content', 'Host alias already exists!').tooltipster('open');
						$(event.target).addClass( "ui-state-error" );
						$(event.target).trigger("focus");
						// validateHostCfg(curHost);
						$("button.savecontrol").button("disable");
					} else {
						$("#hostalias").tooltipster("close");
						$(event.target).removeClass( "ui-state-error" );
						if (curHost.platform) {
							validateHostCfg(curHost);
						}
						// $("button.savecontrol").button("enable");
					}
				}
			});
		},
		open: function() {
			$('.ui-widget-overlay').addClass('custom-overlay');
		},
		close: function() {
			$(this).find( "form" ).trigger('reset');
			$("#grpname").tooltipster("destroy");
			$(this).dialog("destroy");
		}
	});
}

function hostDetailFormPower(hostAlias) {
	var hostDetailFormDiv = '<div id="host-config-form"> \
	<form autocomplete="off"> \
	<fieldset class="nohide"> \
	<legend>Common options</legend> \
	<input type="hidden" name="uuid" id="uuid" /> \
	<label for="hostalias">HMC alias</label> \
	<input type="text" name="hostalias" id="hostalias" class="reqrd" autocomplete="off" /><br> \
	<!--label for="platform">Platform</label> \
	<input type="text" id="platform" name="platform" disabled><br--> \
	<label for="hostname">Host name / IP</label> \
	<input type="text" name="hostname" id="hostname" class="reqrd" title="" autocomplete="off" /><br> \
	<label for="username">User name</label> \
	<input type="text" name="username" id="username" class="reqrd" title="" autocomplete="off" /><br> \
	</fieldset> \
	<fieldset> \
	<legend><label><input type="checkbox" name="dualhmc" id="dualhmc"> Dual HMC (2nd node) &nbsp; &nbsp; &nbsp; &nbsp; &nbsp; &nbsp;<a target="_blank" href="https://lpar2rrd.com/HMC-dual-setup.php">Read this</a></label></legend> \
	<label for="hmc2">Host name / IP</label> \
	<input type="text" name="hmc2" id="hmc2" title="" autocomplete="off" disabled /><br> \
	</fieldset> \
	<fieldset> \
	<legend><label id="authapilabel"><input type="radio" name="auth" id="authapi" disabled>HMC REST API&nbsp;</label></legend> \
	<!-- label for="apiproto">API protocol</label> \
	<select class="api" id="apiproto" name="apiproto" style="width: 7em"> \
	<option value="https">HTTPS</option> \
	<option value="http">HTTP</option> \
	</select><br--> \
	<label for="password" class="api">Password</label> \
	<input type="password" name="password" id="password" class="api" style="width: 12em" title="" autocomplete="off" /><span class="showpass api">Show</span><br> \
	<input type="checkbox" name="exclude" id="exclude" class="raexcl" style="width: unset; display: none"> \
	<label class="raexcl" for="exclude" style="width: 320px; padding: 4px; margin: 0; text-align: left; display: none">Exclude server from REST API, use CLI:</label> \
	<select class="multisel raexcl" style="width: 360px; display: none" name="exservers" id="exservers"></select> \
	<!--label for="apiport">HMC port</label--> \
	<input type="hidden" value="12443" name="apiport" id="apiport" class="api" style="width: 5em" title="" autocomplete="off" /> \
	</fieldset> \
	<fieldset> \
	<legend><label><input type="radio" name="auth" id="authssh" disabled>HMC CLI (SSH)&nbsp;</label></legend> \
	<label for="sshkey">SSH command</label> \
	<input type="text" name="sshkeyinput" id="sshkeyinput" value="' + sysInfo.sshcmd + '" class="ssh" style="" title="" /> \
	<!--label for="sshport">SSH Port</label--> \
	<input type="hidden" value="22" name="sshport" id="sshport" class="ssh" style="width: 4em" title="" /><br> \
	</fieldset> \
	<fieldset id="enhanced_fldset" class="nohide" style=""><legend>Proxy mode</legend><input type="checkbox" class="ui-dform-checkbox" name="proxy" id="proxy"><label for="proxy">Use remote target </label><a target="_blank" id="enhanced_link" href="https://www.lpar2rrd.com/proxy-agent.php"><img name="help2" src="css/images/question-mark-icon_20x20.png" style="margin-top: 5px; margin-left: 5px;"></a></fieldset> \
	<!-- Allow form submission with keyboard without duplicating the dialog button --> \
	<input type="submit" tabindex="-1" style="position:absolute; top:-1000px"> \
	</form> \
	</div>';
	var curHost = {};
	$( hostDetailFormDiv ).dialog({
		height: 490,
		width: 420,
		modal: true,
		title: "HMC connection settings",
		buttons: {
			"Save host": {
				click: function() {
					var hostalias = $("#hostalias").val(),
					hostname = $("#hostname").val(),
					username = $("#username").val(),
					sshport = $("#sshport").val(),
					sshkey = $("#sshkeyinput").val(),
					apiport = $("#apiport").val(),
					apiproto = $("#apiproto").val(),
					password = Base64.encode(uuencode($("#password").val())),
					authapi = $("#authapi").prop('checked'),
					authssh = $("#authssh").prop('checked'),
					proxy = $("#proxy").prop('checked'),
					created = null;
					if (proxy) {
						authapi = true;
						authssh = false;
					}
					if ( ! apiproto ) {
						apiproto = "https";
					}
					if (hostAlias) {
						created = hostcfg.platforms[curPlatform].aliases[hostAlias].created;
						delete hostcfg.platforms[curPlatform].aliases[hostAlias];
					}
					hostcfg.platforms[curPlatform].aliases[hostalias] = {
						uuid: $("#uuid").val(),
						host: hostname,
						username: username,
						ssh_port: sshport,
						ssh_key_id: sshkey,
						api_port: apiport,
						proto: apiproto,
						password: password,
						auth_api: authapi,
						auth_ssh: authssh,
						proxy: proxy
					};
					if (curHost.exclude) {
						hostcfg.platforms[curPlatform].aliases[hostalias].exclude = curHost.exclude;
					}
					if ($("#hmc2").length) {
						hostcfg.platforms[curPlatform].aliases[hostalias].hmc2 = $("#hmc2").val();
					}
					if (hostAlias) {
						hostcfg.platforms[curPlatform].aliases[hostalias].updated = TimeStamp();
						hostcfg.platforms[curPlatform].aliases[hostalias].created = created;
					} else {
						hostcfg.platforms[curPlatform].aliases[hostalias].created = TimeStamp();
					}
					SaveHostsCfg(true);
					$(this).dialog("close");
					var current_index = $("#tabs").tabs("option","active");
					$("#tabs").tabs('load',current_index);
					// $('#adminmenu a[data-abbr="hosts-' + $("#hosttable").data("platform") + '"]').trigger( "click" );
				},
				text: "Save host",
				class: 'savecontrol'
			},
			"Test connection": {
				click: function() {
					var hostalias = $("#hostalias").val(),
					hostname = $("#hostname").val(),
					username = $("#username").val(),
					sshport = $("#sshport").val(),
					sshkey = $("#sshkeyinput").val(),
					apiport = $("#apiport").val(),
					apiproto = $("#apiproto").val(),
					password = Base64.encode(uuencode($("#password").val())),
					authapi = $("#authapi").prop('checked'),
					authssh = $("#authssh").prop('checked'),
					proxy = $("#proxy").prop('checked'),
					created = null;
					if (proxy) {
						authapi = true;
						authssh = false;
					}
					if ( ! apiproto ) {
						apiproto = "https";
					}
					if (hostAlias) {
						created = hostcfg.platforms[curPlatform].aliases[hostAlias].created;
						delete hostcfg.platforms[curPlatform].aliases[hostAlias];
					}
					hostcfg.platforms[curPlatform].aliases[hostalias] = {
						uuid: $("#uuid").val(),
						host: hostname,
						username: username,
						ssh_port: sshport,
						ssh_key_id: sshkey,
						api_port: apiport,
						proto: apiproto,
						password: password,
						auth_api: authapi,
						auth_ssh: authssh
					};
					if (curHost.exclude) {
						hostcfg.platforms[curPlatform].aliases[hostalias].exclude = curHost.exclude;
					}
					if ($("#hmc2").length) {
						hostcfg.platforms[curPlatform].aliases[hostalias].hmc2 = $("#hmc2").val();
					}
					if (hostAlias) {
						hostcfg.platforms[curPlatform].aliases[hostalias].updated = TimeStamp();
						hostcfg.platforms[curPlatform].aliases[hostalias].created = created;
					} else {
						hostcfg.platforms[curPlatform].aliases[hostalias].created = TimeStamp();
					}
					SaveHostsCfg(false);
					$(this).dialog("close");
					$('#adminmenu a[data-abbr="hosts-' + $("#hosttable").data("platform") + '"]').trigger( "click" );
					testConnection(hostalias, hostcfg.platforms[curPlatform].aliases[hostalias]);
				},
				text: "Save & Test connection",
				id: "savetestbutton",
				class: 'savecontrol'
			},
			Cancel: function() {
				$(this).dialog("close");
			}
		},
		create: function() {
			var sshkeyel;
			if (sysInfo.useRestAPIExclusion) {
				$('.raexcl').show().prop("disabled", false);
				$('#exservers').multipleSelect({
					filter: true,
					single: false,
					maxHeight: 200,
					selectAll: false,
					//allSelected: false,
					onClick: function() {
						curHost.exclude = [];
						var selected = $('#exservers').multipleSelect("getSelects");
						$.each(selected, function(idx, val) {
							var item = {"name": val, "exclude_data_load" : true, "exclude_data_fetch" : true};
							curHost.exclude.push(item);
						});
					},
					onCheckAll: function() {
						curHost.exclude = [];
						var selected = $('#exservers').multipleSelect("getSelects");
						$.each(selected, function(idx, val) {
							var item = {"name": val, "exclude_data_load" : true, "exclude_data_fetch" : true};
							curHost.exclude.push(item);
						});
					},
					onUncheckAll: function() {
						curHost.exclude = [];
					}
				}).multipleSelect("disable");
				$('#exclude').on("change", function () {
					if ($(this).prop('checked')) {
						// $('#exservers').multipleSelect("enable");
						curHost.exclude = [];
						checkServers(curHost.host);
					} else {
						$('#exservers').multipleSelect("disable");
						delete curHost.exclude;
					}
				});
			}
			$("button.savecontrol").button("disable");
			$("#hostalias, #hmc2").tooltipster({
				trigger: 'custom',
				position: 'right',
			});
			$("#mailfrom, #emails").tooltipster({
				trigger: 'custom',
				position: 'right',
			});
			/*
			$.each(sortProperties(hostcfg.platforms, "order", true), function(i,val) {
				var isSelected = (val.id == curPlatform);
				$("<option />", {text: val.id, value: val.id, selected: isSelected}).appendTo($("#platform"));
			});
			*/
			var checkServers = function(hmc, selected) {
				$("body *").css("cursor", "progress");
				$.post('/lpar2rrd-cgi/hosts.sh', {
					cmd: "powerserverlist",
					hmc: hmc,
				}, function(data) {
					$("body *").css("cursor", "default");
					if (data.length) {
						$('#exservers').empty().multipleSelect("enable");
						$.each(data, function(idx, val) {
							var $opt = $("<option />", {
								value: val,
								text: val
							});
							$('#exservers').append($opt);
						});
						$('#exservers').multipleSelect('refresh');
						if (selected) {
							$('#exservers').multipleSelect("setSelects", selected);
						} else {
							$('#exservers').multipleSelect('uncheckAll');
						}
					} else {
						$('#exservers').multipleSelect("disable");
					}
				});
			};
			sshkeyel = "#sshkeyinput";
			$("#sshkeyinput").show();
			if (hostAlias) {
				curHost = hostcfg.platforms[curPlatform].aliases[hostAlias];
				$("#hostalias").val(hostAlias);
				$("#uuid").val(curHost.uuid);
				$("#hostname").val(curHost.host);
				// $("#platform").val(curHost.platform);
				$("#username").val(curHost.username);
				$("#sshport").val(curHost.ssh_port);
				$("#sshkeyinput").val(curHost.ssh_key_id);
				$("#apiport").val(curHost.api_port);
				$("#apiproto").val(curHost.proto);
				if (curHost.password === true) {
					$("#password").attr("placeholder", "Don't fill to keep current");
					$("#password").addClass("keepass");
				} else {
					$("#password").val(reveal(curHost.password));
				}

				validateHostCfg(curHost);
				$("#authapi").prop('checked', curHost.auth_api);
				$(".showpass").hide();
				$("#proxy").prop('checked', curHost.proxy);
				if ($("#proxy").prop("checked")) {
					$("#savetestbutton").button("disable");
					$("#host-config-form fieldset").each(function() {
						if (! $(this).hasClass("nohide")) {
							$(this).hide();
						}
					});
				}
				if (curHost.hmc2) {
					$("#dualhmc").prop('checked', true);
					$("#hmc2").val(curHost.hmc2).prop("disabled", false);
				}


				$.post('/lpar2rrd-cgi/hosts.sh', {
					cmd: "gethmcversion",
					hmc: curHost.host,
				}, function(data) {
					if (data && data.hmcversion) {
						if (data.hmcversion) {
							var majorVersion = data.hmcversion.match(/^V(\d+)R.*$/);
							if (majorVersion[1] < 8) {
								$("input[type=radio]").prop("disabled", true);
								$("#authapi").prop( "checked", false );
								$("#authssh").prop( "checked", true );
								$("#authapilabel").text("HMC REST API (unsupported HMC version: " + data.hmcversion + ")");
								$(".api").hide();
								$(".api").prop('disabled', true);
								$(".ssh").prop('disabled', false);
							} else {
								$("input[type=radio]").prop("disabled", false);
								$(".api").prop('disabled', false);
								if (sysInfo.useRestAPIExclusion) {
									$('.raexcl').prop("disabled", false);
								}
							}
						}
					} else {
						$("input[type=radio]").prop("disabled", false);
						$(".api").prop('disabled', false);
					}
				});

				$("#authssh").prop('checked', curHost.auth_ssh);
				if (sysInfo.useRestAPIExclusion && curHost.exclude && curHost.exclude.length) {
					var selected = $.map(curHost.exclude, function (i, val) {
						return i.name;
					});
					$("#exclude").prop("checked", true);
					checkServers(curHost.host, selected);
				}

			} else {
				// $("button.savecontrol").button("disable");
			}
			$(".api").prop('disabled', !$("#authapi").is(':checked'));
			$(".ssh").prop('disabled', !$("#authssh").is(':checked'));
			$("#apiproto").change(function() {
				if ($("#apiproto").val() == 'http') {
					$("#apiport").val(80);
				} else {
					$("#apiport").val(443);
				}
			});
			$("input[type=radio]").change(function() {
				$(".ssh").prop('disabled', !$("#authssh").is(':checked'));
				if ($("#authssh").is(':checked')) {
					if (! $("#sshport").val()) {
						$("#sshport").val(22);
					}
				}
				$(".api").prop('disabled', !$("#authapi").is(':checked'));
				if ($("#authapi").is(':checked')) {
					if (! $("#apiport").val()) {
						$("#apiport").val(443);
					}
					if (! $("#apiproto").val()) {
						$("#apiproto").val("https");
					}
				}
			});
			$(".reqrd, .api, .ssh").change(function() {
				if (validateHostCfg(true)) {
					$("#authapi").prop('disabled', false);
					$("#authssh").prop('disabled', false);
					if (sysInfo.useRestAPIExclusion) {
						$('.raexcl').prop("disabled", false);
					}
				}
			});

			$(".showpass").button().mousedown(function(e) {
				e.stopPropagation();
				$(this).prev().attr('type','text');
			}).mouseup(function(){
				$(this).prev().attr('type','password');
			}).mouseout(function(){
				$(this).prev().attr('type','password');
			});
			$("#password").on("keyup", function( event ) {
				if ($(this).val()) {
					$(".showpass").button("enable");
				} else {
					$(".showpass").button("disable");
				}
			});
			$("#hostalias").on("blur", function( event ) {
				if (!event.relatedTarget || event.relatedTarget && event.relatedTarget.textContent != "Cancel") {
					if (! this.value) {
						$("#hostalias").tooltipster('content', 'Alias name is required').tooltipster('open');
						$(event.target).addClass( "ui-state-error" );
						$(event.target).trigger("focus");
						// validateHostCfg(curHost);
						$("button.savecontrol").button("disable");
					} else if (this.value != hostAlias && hostcfg.platforms[curPlatform].aliases[this.value]) {
						$("#hostalias").tooltipster('content', 'Host alias already exists!').tooltipster('open');
						$(event.target).addClass( "ui-state-error" );
						$(event.target).trigger("focus");
						// validateHostCfg(curHost);
						$("button.savecontrol").button("disable");
					} else {
						$("#hostalias").tooltipster("close");
						$(event.target).removeClass( "ui-state-error" );
						if (curHost.platform) {
							validateHostCfg(curHost);
						}
						// $("button.savecontrol").button("enable");
					}
				}
			});
			$("#hmc2").on("blur", function( event ) {
				var found_in = "";
				var tocheck = this.value;
				$.each(hostcfg.platforms[curPlatform].aliases, function(i, host) {
					if (tocheck && (tocheck == host.host || tocheck == host.hmc2)) {
						found_in = i;
					}
				});
				hostcfg.platforms[curPlatform].aliases;

				if (this.value == $("#hostname").val()) {
					$("#hmc2").tooltipster('content', 'Hostname/IP already used in primary node!').tooltipster('open');
					$(event.target).addClass( "ui-state-error" );
					$(event.target).trigger("focus");
					// validateHostCfg(curHost);
					$("button.savecontrol").button("disable");
				} else if (found_in) {
					$("#hmc2").tooltipster('content', 'Hostname/IP already used in alias called ' + found_in + '!').tooltipster('open');
					$(event.target).addClass( "ui-state-error" );
					$(event.target).trigger("focus");
					// validateHostCfg(curHost);
					$("button.savecontrol").button("disable");
				} else {
					$("#hmc2").tooltipster("close");
					$(event.target).removeClass( "ui-state-error" );
					validateHostCfg(curHost);
				}
			});
			$("#proxy, #dualhmc").checkboxradio();
			$("#host-config-form").on("change", "#proxy", function (ev) {
				if ($(ev.target).prop("checked")) {
					$("#savetestbutton").button("disable");
					$("#host-config-form fieldset").each(function() {
						if (! $(this).hasClass("nohide")) {
							$(this).hide(200);
						}
					});
				} else {
					$("#savetestbutton").button("enable");
					$("#host-config-form fieldset").show(200);
				}
			});
			$("#host-config-form").on("change", "#dualhmc", function (ev) {
				if ($(ev.target).prop("checked")) {
					$("#hmc2").prop("disabled", false);
				} else {
					$("#hmc2").prop("disabled", true).val("");
					$("#hmc2").tooltipster("close");
					$("#hmc2").removeClass( "ui-state-error" );
				}
			});
		},
		open: function() {
			$('.ui-widget-overlay').addClass('custom-overlay');
		},
		close: function() {
			$(this).find( "form" ).trigger('reset');
			$("#grpname").tooltipster("destroy");
			$(this).dialog("destroy");
			$("*").css("cursor", "default");
		}
	});
}

function hostDetailFormCMC(hostAlias) {
	var hostDetailFormDiv = '<div id="host-config-form"> \
	<form autocomplete="off"> \
	<fieldset class="nohide"> \
	<legend>Common options</legend> \
	<input type="hidden" name="uuid" id="uuid" /> \
	<label for="hostalias">CMC alias</label> \
	<input type="text" name="hostalias" id="hostalias" class="reqrd" autocomplete="off" /><br> \
	<!--label for="platform">Platform</label> \
	<input type="text" id="platform" name="platform" disabled><br--> \
	<label for="hostname">Host name / IP</label> \
	<input type="text" name="hostname" id="hostname" class="reqrd" title="" autocomplete="off" /><br> \
	<label for="username">Client ID</label> \
	<input type="text" name="username" id="username" class="reqrd" title="" autocomplete="new-password" /><br> \
	<label for="password">Client secret</label> \
	<input type="password" name="password" id="password" class="reqrd" style="width: 12em" title="" autocomplete="new-password" /><span class="showpass api">Show</span><br> \
	<label for="proxy_url">Proxy URL</label> \
	<select id="apiproto" name="apiproto" style="width: 7em"> \
	<option value="">---</option> \
	<option value="https">https://</option> \
	<option value="http">http://</option> \
	</select> \
	<input type="text" name="proxy_url" id="proxy_url" style="width: 12em" title="" autocomplete="off" /><br> \
	</fieldset> \
	<!-- Allow form submission with keyboard without duplicating the dialog button --> \
	<input type="submit" tabindex="-1" style="position:absolute; top:-1000px"> \
	</form> \
	</div>';
	var curHost = {};
	$( hostDetailFormDiv ).dialog({
		height: 490,
		width: 480,
		modal: true,
		title: "CMC connection settings",
		buttons: {
			"Save host": {
				click: function() {
					var hostalias = $("#hostalias").val(),
					hostname = $("#hostname").val(),
					username = $("#username").val(),
					password = Base64.encode(uuencode($("#password").val())),
					apiproto = $("#apiproto").val(),
					proxy_url = $("#proxy_url").val(),
					created = null;
					if (hostAlias) {
						created = hostcfg.platforms[curPlatform].aliases[hostAlias].created;
						delete hostcfg.platforms[curPlatform].aliases[hostAlias];
					}
					hostcfg.platforms[curPlatform].aliases[hostalias] = {
						uuid: $("#uuid").val(),
						host: hostname,
						username: username,
						password: password,
						proxy_url: proxy_url,
						proto: apiproto
					};
					if (hostAlias) {
						hostcfg.platforms[curPlatform].aliases[hostalias].updated = TimeStamp();
						hostcfg.platforms[curPlatform].aliases[hostalias].created = created;
					} else {
						hostcfg.platforms[curPlatform].aliases[hostalias].created = TimeStamp();
					}
					SaveHostsCfg(true);
					$(this).dialog("close");
					var current_index = $("#tabs").tabs("option","active");
					$("#tabs").tabs('load',current_index);
					// $('#adminmenu a[data-abbr="hosts-' + $("#hosttable").data("platform") + '"]').trigger( "click" );
				},
				text: "Save host",
				class: 'savecontrol'
			},
			"Test connection": {
				click: function() {
					var hostalias = $("#hostalias").val(),
					hostname = $("#hostname").val(),
					username = $("#username").val(),
					password = Base64.encode(uuencode($("#password").val())),
					apiproto = $("#apiproto").val(),
					proxy_url = $("#proxy_url").val(),
					created = null;
					if (hostAlias) {
						created = hostcfg.platforms[curPlatform].aliases[hostAlias].created;
						delete hostcfg.platforms[curPlatform].aliases[hostAlias];
					}
					hostcfg.platforms[curPlatform].aliases[hostalias] = {
						uuid: $("#uuid").val(),
						host: hostname,
						username: username,
						password: password,
						proxy_url: proxy_url,
						proto: apiproto
					};
					if (hostAlias) {
						hostcfg.platforms[curPlatform].aliases[hostalias].updated = TimeStamp();
						hostcfg.platforms[curPlatform].aliases[hostalias].created = created;
					} else {
						hostcfg.platforms[curPlatform].aliases[hostalias].created = TimeStamp();
					}
					SaveHostsCfg(false);
					$(this).dialog("close");
					$('#adminmenu a[data-abbr="hosts-' + $("#hosttable").data("platform") + '"]').trigger( "click" );

					testConnection(hostalias, hostcfg.platforms[curPlatform].aliases[hostalias]);
				},
				text: "Save & Test connection",
				id: "savetestbutton",
				class: 'savecontrol'
			},
			Cancel: function() {
				$(this).dialog("close");
			}
		},
		create: function() {
			$("button.savecontrol").button("disable");
			$("#hostalias").tooltipster({
				trigger: 'custom',
				position: 'right',
			});
			if (hostAlias) {
				curHost = hostcfg.platforms[curPlatform].aliases[hostAlias];
				$("#hostalias").val(hostAlias);
				$("#uuid").val(curHost.uuid);
				$("#hostname").val(curHost.host);
				// $("#platform").val(curHost.platform);
				$("#username").val(curHost.username);
				$("#proxy_url").val(curHost.proxy_url);
				$("#apiproto").val(curHost.proto);
				$("#proxy_url").prop("disabled", ! curHost.proto);
				if (curHost.password === true) {
					$("#password").attr("placeholder", "Don't fill to keep current");
					$("#password").addClass("keepass");
				} else {
					$("#password").val(reveal(curHost.password));
				}

				validateHostCfg(curHost);
				$(".showpass").hide();
			}
			$(".reqrd, .api, .ssh").change(function() {
				if (validateHostCfg(true)) {
					if (sysInfo.useRestAPIExclusion) {
						$('.raexcl').prop("disabled", false);
					}
				}
			});

			$(".showpass").button().mousedown(function(e) {
				e.stopPropagation();
				$(this).prev().attr('type','text');
			}).mouseup(function(){
				$(this).prev().attr('type','password');
			}).mouseout(function(){
				$(this).prev().attr('type','password');
			});
			$("#password").on("keyup", function( event ) {
				if ($(this).val()) {
					$(".showpass").button("enable");
				} else {
					$(".showpass").button("disable");
				}
			});
			$("#hostalias").on("blur", function( event ) {
				if (!event.relatedTarget || event.relatedTarget && event.relatedTarget.textContent != "Cancel") {
					if (! this.value) {
						$("#hostalias").tooltipster('content', 'Alias name is required').tooltipster('open');
						$(event.target).addClass( "ui-state-error" );
						$(event.target).trigger("focus");
						// validateHostCfg(curHost);
						$("button.savecontrol").button("disable");
					} else if (this.value != hostAlias && hostcfg.platforms[curPlatform].aliases[this.value]) {
						$("#hostalias").tooltipster('content', 'Host alias already exists!').tooltipster('open');
						$(event.target).addClass( "ui-state-error" );
						$(event.target).trigger("focus");
						// validateHostCfg(curHost);
						$("button.savecontrol").button("disable");
					} else {
						$("#hostalias").tooltipster("close");
						$(event.target).removeClass( "ui-state-error" );
						if (curHost.platform) {
							validateHostCfg(curHost);
						}
						// $("button.savecontrol").button("enable");
					}
				}
			});
			$("#host-config-form").on("change", "#apiproto", function (ev) {
				if ($(ev.target).val()) {
					$("#proxy_url").prop("disabled", false);
					// $("#savetestbutton").button("disable");
				} else {
					$("#proxy_url").val("").prop("disabled", true);
					// $("#savetestbutton").button("enable");
				}
			});
		},
		open: function() {
			$('.ui-widget-overlay').addClass('custom-overlay');
		},
		close: function() {
			$(this).find( "form" ).trigger('reset');
			$("#grpname").tooltipster("destroy");
			$(this).dialog("destroy");
			$("*").css("cursor", "default");
		}
	});
}

function hostDetailFormVmware(hostAlias) {
	var hostDetailFormDiv = '<div id="host-config-form"> \
	<form autocomplete="new-password"> \
	<fieldset> \
	<legend>Common options</legend> \
	<input type="hidden" name="uuid" id="uuid" /> \
	<label for="hostalias">vCenter alias</label> \
	<input type="text" name="hostalias" id="hostalias" class="reqrd" autocomplete="new-password" /><br> \
	<!--label for="platform">Platform</label> \
	<input type="text" id="platform" name="platform" disabled><br--> \
	<label for="hostname">Host name / IP</label> \
	<input type="text" name="hostname" id="hostname" class="reqrd" title="" autocomplete="new-password" /><br> \
	<label for="username">User name</label> \
	<input type="text" name="username" id="username" class="reqrd" title="" autocomplete="new-password" /><br> \
	</fieldset> \
	<fieldset> \
	<legend><label>API&nbsp;</label></legend> \
	<!-- label for="apiproto">API protocol</label> \
	<select class="api" id="apiproto" name="apiproto" style="width: 7em"> \
	<option value="https">HTTPS</option> \
	<option value="http">HTTP</option> \
	</select><br--> \
	<label for="password">Password</label> \
	<input type="password" name="password" id="password" class="api" style="width: 12em" title="" autocomplete="new-password" /><span class="showpass api">Show</span><br> \
	<label for="apiport">Port</label> \
	<input type="number" value="443" name="apiport" id="apiport" class="api" style="width: 5em" title="" autocomplete="new-password" disabled /><br> \
	</fieldset> \
	<!-- Allow form submission with keyboard without duplicating the dialog button --> \
	<input type="submit" tabindex="-1" style="position:absolute; top:-1000px"> \
	</form> \
	</div>';
	$( hostDetailFormDiv ).dialog({
		height: 390,
		width: 420,
		modal: true,
		title: "vCenter connection & credentials",
		buttons: {
			"Save host": {
				click: function() {
					var hostalias = $("#hostalias").val(),
					hostname = $("#hostname").val(),
					username = $("#username").val(),
					sshport = $("#sshport").val(),
					sshkey = $("#sshkeyinput").val(),
					apiport = $("#apiport").val(),
					apiproto = $("#apiproto").val(),
					password = Base64.encode(uuencode($("#password").val())),
					authapi = true,
					authssh = false,
					created = null;
					hostalias = hostalias.replace(/\s+/g, '_');
					if ( ! apiproto ) {
						apiproto = "https";
					}
					if (hostAlias) {
						created = hostcfg.platforms[curPlatform].aliases[hostAlias].created;
						delete hostcfg.platforms[curPlatform].aliases[hostAlias];
					}
					hostcfg.platforms[curPlatform].aliases[hostalias] = {
						uuid: $("#uuid").val(),
						host: hostname,
						username: username,
						ssh_port: sshport,
						ssh_key_id: sshkey,
						api_port: apiport,
						proto: apiproto,
						password: password,
						auth_api: authapi,
						auth_ssh: authssh
					};
					if (hostAlias) {
						hostcfg.platforms[curPlatform].aliases[hostalias].updated = TimeStamp();
						hostcfg.platforms[curPlatform].aliases[hostalias].created = created;
					} else {
						hostcfg.platforms[curPlatform].aliases[hostalias].created = TimeStamp();
					}
					$.post('/lpar2rrd-cgi/hosts.sh', {
						cmd: "vmwareaddcreds",
						platform: curPlatform,
						alias: hostalias,
						server: hostname,
						username: username,
						password: password
					}, function(data) {
						if (data.success) {
							SaveHostsCfg(true);
						} else {
							$.alert("Something went wrong", data.error, false);
						}
						$("#host-config-form").dialog("close");
						$('#adminmenu a[data-abbr="hosts-' + $("#hosttable").data("platform") + '"]').trigger( "click" );
					});
				},
				text: "Save host",
				class: 'savecontrol'
			},
			"Test connection": {
				click: function() {
					var hostalias = $("#hostalias").val(),
					hostname = $("#hostname").val(),
					username = $("#username").val(),
					sshport = $("#sshport").val(),
					sshkey = $("#sshkeyinput").val(),
					apiport = $("#apiport").val(),
					apiproto = $("#apiproto").val(),
					password = Base64.encode(uuencode($("#password").val())),
					authapi = true,
					authssh = false,
					created = null;
					hostalias = hostalias.replace(/\s+/g, '_');

					if ( ! apiproto ) {
						apiproto = "https";
					}
					if (hostAlias) {
						created = hostcfg.platforms[curPlatform].aliases[hostAlias].created;
						delete hostcfg.platforms[curPlatform].aliases[hostAlias];
					}
					hostcfg.platforms[curPlatform].aliases[hostalias] = {
						uuid: $("#uuid").val(),
						host: hostname,
						username: username,
						ssh_port: sshport,
						ssh_key_id: sshkey,
						api_port: apiport,
						proto: apiproto,
						password: password,
						auth_api: authapi,
						auth_ssh: authssh
					};
					if (hostAlias) {
						hostcfg.platforms[curPlatform].aliases[hostalias].updated = TimeStamp();
						hostcfg.platforms[curPlatform].aliases[hostalias].created = created;
					} else {
						hostcfg.platforms[curPlatform].aliases[hostalias].created = TimeStamp();
					}
					$.post('/lpar2rrd-cgi/hosts.sh', {
						cmd: "vmwareaddcreds",
						platform: curPlatform,
						alias: hostalias,
						server: hostname,
						username: username,
						password: password
					}, function(data) {
						if (data.success) {
							SaveHostsCfg(false);
						} else {
							$.alert("Something went wrong", data.error, false);
						}
						$("#host-config-form").dialog("close");
						$('#adminmenu a[data-abbr="hosts-' + $("#hosttable").data("platform") + '"]').trigger( "click" );
						testConnection(hostalias, hostcfg.platforms[curPlatform].aliases[hostalias]);
					});
				},
				text: "Save & Test connection",
				class: 'savecontrol'
			},
			Cancel: function() {
				$(this).dialog("close");
			}
		},
		create: function() {
			var curHost = {};
			var sshkeyel;
			$("button.savecontrol").button("disable");
			$("#hostalias").tooltipster({
				trigger: 'custom',
				position: 'right',
			});
			$("#mailfrom, #emails").tooltipster({
				trigger: 'custom',
				position: 'right',
			});
			/*
			$.each(sortProperties(hostcfg.platforms, "order", true), function(i,val) {
				var isSelected = (val.id == curPlatform);
				$("<option />", {text: val.id, value: val.id, selected: isSelected}).appendTo($("#platform"));
			});
			*/
			sshkeyel = "#sshkeyinput";
			$("#sshkeyinput").show();
			if (hostAlias) {
				curHost = hostcfg.platforms[curPlatform].aliases[hostAlias];
				$("#hostalias").val(hostAlias);
				$("#uuid").val(curHost.uuid);
				$("#hostname").val(curHost.host);
				// $("#platform").val(curHost.platform);
				$("#username").val(curHost.username);
				$("#sshport").val(curHost.ssh_port);
				$(sshkeyel).val(curHost.ssh_key_id);
				$("#apiport").val(curHost.api_port);
				$("#apiproto").val(curHost.proto);
				if (curHost.password === true) {
					$("#password").attr("placeholder", "Don't fill to keep current");
					$("#password").addClass("keepass");
				} else {
					$("#password").val(reveal(curHost.password));
				}
				validateHostCfg(curHost);
				$("#authapi").prop('checked', curHost.auth_api);
				$("#authssh").prop('checked', curHost.auth_ssh);
				$(".showpass").hide();

			} else {
				// $("button.savecontrol").button("disable");
			}
			$("input[type=radio]").change(function() {
				$(".ssh").prop('disabled', !$("#authssh").is(':checked'));
				if ($("#authssh").is(':checked')) {
					if (! $("#sshport").val()) {
						$("#sshport").val(22);
					}
				}
				$(".api").prop('disabled', !$("#authapi").is(':checked'));
				if ($("#authapi").is(':checked')) {
					if (! $("#apiport").val()) {
						$("#apiport").val(443);
					}
					if (! $("#apiproto").val()) {
						$("#apiproto").val("https");
					}
				}
			});
			$(".reqrd, .api, .ssh").change(function() {
				validateHostCfg(true);
			});

			$(".showpass").button().mousedown(function(e) {
				e.stopPropagation();
				$(this).prev().attr('type','text');
			}).mouseup(function(){
				$(this).prev().attr('type','password');
			}).mouseout(function(){
				$(this).prev().attr('type','password');
			});
			$("#password").on("keyup", function( event ) {
				if ($(this).val()) {
					$(".showpass").button("enable");
				} else {
					$(".showpass").button("disable");
				}
			});
			$("#hostalias").on("blur", function( event ) {
				if (!event.relatedTarget || event.relatedTarget && event.relatedTarget.textContent != "Cancel") {
					if (! this.value) {
						$("#hostalias").tooltipster('content', 'Alias name is required').tooltipster('open');
						$(event.target).addClass( "ui-state-error" );
						$(event.target).trigger("focus");
						// validateHostCfg(curHost);
						$("button.savecontrol").button("disable");
					} else if (this.value != hostAlias && hostcfg.platforms[curPlatform].aliases[this.value]) {
						$("#hostalias").tooltipster('content', 'Host alias already exists!').tooltipster('open');
						$(event.target).addClass( "ui-state-error" );
						$(event.target).trigger("focus");
						// validateHostCfg(curHost);
						$("button.savecontrol").button("disable");
					} else {
						$("#hostalias").tooltipster("close");
						$(event.target).removeClass( "ui-state-error" );
						if (curHost.platform) {
							validateHostCfg(curHost);
						}
						// $("button.savecontrol").button("enable");
					}
				}
			});
		},
		open: function() {
			$('.ui-widget-overlay').addClass('custom-overlay');
		},
		close: function() {
			$(this).find( "form" ).trigger('reset');
			$("#grpname").tooltipster("destroy");
			$(this).dialog("destroy");
		}
	});
}

function hostDetailFormOvirt(hostAlias) {
	var hostDetailFormDiv = '<div id="host-config-form"> \
	<form autocomplete="off"> \
	<fieldset> \
	<legend>Common options</legend> \
	<input type="hidden" name="uuid" id="uuid" /> \
	<label for="hostalias">Host alias</label> \
	<input type="text" name="hostalias" id="hostalias" class="reqrd" autocomplete="off" /><br> \
	<!--label for="platform">Platform</label> \
	<input type="text" id="platform" name="platform" disabled><br--> \
	<label for="hostname">Host name / IP</label> \
	<input type="text" name="hostname" id="hostname" class="reqrd" title="" autocomplete="off" /><br> \
	</fieldset> \
	<fieldset> \
	<legend><label>oVirt Data Warehouse history DB&nbsp;</label></legend> \
	<!-- label for="apiproto">API protocol</label> \
	<select class="api" id="apiproto" name="apiproto" style="width: 7em"> \
	<option value="https">HTTPS</option> \
	<option value="http">HTTP</option> \
	</select><br--> \
	<label for="username">User name</label> \
	<input type="text" value="ovirt_engine_history" name="username" id="username" class="reqrd" title="" autocomplete="off" /><br> \
	<label for="password">Password</label> \
	<input type="password" name="password" id="password" class="api" style="width: 12em" title="" autocomplete="off" /><span class="showpass api">Show</span><br> \
	<input type="hidden" value="5432" name="apiport" id="apiport" class="api" style="width: 5em" title="" autocomplete="off" disabled /> \
	</fieldset>';
	if (sysInfo.useOVirtRestAPI) {
	  hostDetailFormDiv += '\
	<fieldset class="ovirt_rapi"> \
	<legend><label><input type="checkbox" name="authapi" id="authapi">&nbsp;oVirt REST API</label></legend> \
	<label for="apihostname">Host name / IP</label> \
	<input type="text" name="apihostname" id="apihostname" class="reqrd" title="" autocomplete="off" /><br> \
	<label for="apiusername">User name</label> \
	<input type="text" name="apiusername" id="apiusername" title="" autocomplete="off" disabled /><br> \
	<label for="apiport2">API Port</label> \
	<input type="number" name="apiport2" id="apiport2" class="api" style="width: 5em" title="" autocomplete="off" disabled /><br> \
	<label for="apipassword">API Password</label> \
	<input type="password" name="apipassword" id="apipassword" class="api" style="width: 12em" title="" autocomplete="new-password" disabled /><span class="showpass api">Show</span><br> \
	</fieldset>';
	}
	hostDetailFormDiv += '\
	<!-- Allow form submission with keyboard without duplicating the dialog button --> \
	<input type="submit" tabindex="-1" style="position:absolute; top:-1000px"> \
	</form> \
	</div>';
	$( hostDetailFormDiv ).dialog({
		height: 460,
		width: 420,
		modal: true,
		title: "RHV / oVirt Virtualization Manager connection",
		buttons: {
			"Save host": {
				click: function() {
					var hostalias = $("#hostalias").val(),
					hostname = $("#hostname").val(),
					username = $("#username").val(),
					sshport = $("#sshport").val(),
					sshkey = $("#sshkeyinput").val(),
					apiport = $("#apiport").val(),
					apiproto = $("#apiproto").val(),
					password = Base64.encode(uuencode($("#password").val())),
					authapi = $("#authapi").prop('checked'),
					authssh = false,
					created = null;
					if ( ! apiproto ) {
						apiproto = "https";
					}
					if (hostAlias) {
						created = hostcfg.platforms[curPlatform].aliases[hostAlias].created;
						delete hostcfg.platforms[curPlatform].aliases[hostAlias];
					}
					hostcfg.platforms[curPlatform].aliases[hostalias] = {
						uuid: $("#uuid").val(),
						host: hostname,
						username: username,
						ssh_port: sshport,
						ssh_key_id: sshkey,
						api_port: apiport,
						proto: apiproto,
						password: password,
						auth_api: authapi,
						auth_ssh: authssh
					};
					if (authapi) {
						hostcfg.platforms[curPlatform].aliases[hostalias].api_hostname = $("#apihostname").val();
						hostcfg.platforms[curPlatform].aliases[hostalias].api_port2 = $("#apiport2").val();
						hostcfg.platforms[curPlatform].aliases[hostalias].api_username = $("#apiusername").val();
						hostcfg.platforms[curPlatform].aliases[hostalias].api_password = Base64.encode(uuencode($("#apipassword").val()));
					}
					if (hostAlias) {
						hostcfg.platforms[curPlatform].aliases[hostalias].updated = TimeStamp();
						hostcfg.platforms[curPlatform].aliases[hostalias].created = created;
					} else {
						hostcfg.platforms[curPlatform].aliases[hostalias].created = TimeStamp();
					}
					SaveHostsCfg(true);
					$("#host-config-form").dialog("close");
					$('#adminmenu a[data-abbr="hosts-' + $("#hosttable").data("platform") + '"]').trigger( "click" );
				},
				text: "Save host",
				class: 'savecontrol'
			},
			"Test connection": {
				click: function() {
					var hostalias = $("#hostalias").val(),
					hostname = $("#hostname").val(),
					username = $("#username").val(),
					sshport = $("#sshport").val(),
					sshkey = $("#sshkeyinput").val(),
					apiport = $("#apiport").val(),
					apiproto = $("#apiproto").val(),
					password = Base64.encode(uuencode($("#password").val())),
					authapi = $("#authapi").prop('checked'),
					authssh = false,
					created = null;
					if ( ! apiproto ) {
						apiproto = "https";
					}
					if (hostAlias) {
						created = hostcfg.platforms[curPlatform].aliases[hostAlias].created;
						delete hostcfg.platforms[curPlatform].aliases[hostAlias];
					}
					hostcfg.platforms[curPlatform].aliases[hostalias] = {
						uuid: $("#uuid").val(),
						host: hostname,
						username: username,
						ssh_port: sshport,
						ssh_key_id: sshkey,
						api_port: apiport,
						proto: apiproto,
						password: password,
						auth_api: authapi,
						auth_ssh: authssh
					};
					if (authapi) {
						hostcfg.platforms[curPlatform].aliases[hostalias].api_hostname = $("#apihostname").val();
						hostcfg.platforms[curPlatform].aliases[hostalias].api_port2 = $("#apiport2").val();
						hostcfg.platforms[curPlatform].aliases[hostalias].api_username = $("#apiusername").val();
						hostcfg.platforms[curPlatform].aliases[hostalias].api_password = Base64.encode(uuencode($("#apipassword").val()));
					}
					if (hostAlias) {
						hostcfg.platforms[curPlatform].aliases[hostalias].updated = TimeStamp();
						hostcfg.platforms[curPlatform].aliases[hostalias].created = created;
					} else {
						hostcfg.platforms[curPlatform].aliases[hostalias].created = TimeStamp();
					}
					SaveHostsCfg(false);
					$("#host-config-form").dialog("close");
					$('#adminmenu a[data-abbr="hosts-' + $("#hosttable").data("platform") + '"]').trigger( "click" );
					testConnection(hostalias, hostcfg.platforms[curPlatform].aliases[hostalias]);
				},
				text: "Save & Test connection",
				class: 'savecontrol'
			},
			Cancel: function() {
				$(this).dialog("close");
			}
		},
		create: function() {
			var curHost = {};
			var sshkeyel;
			$("button.savecontrol").button("disable");
			$("#hostalias").tooltipster({
				trigger: 'custom',
				position: 'right',
			});
			if (hostAlias) {
				curHost = hostcfg.platforms[curPlatform].aliases[hostAlias];
				$("#hostalias").val(hostAlias);
				$("#uuid").val(curHost.uuid);
				$("#hostname").val(curHost.host);
				// $("#platform").val(curHost.platform);
				$("#username").val(curHost.username);
				$("#sshport").val(curHost.ssh_port);
				$(sshkeyel).val(curHost.ssh_key_id);
				$("#apiport").val(curHost.api_port);
				$("#apiproto").val(curHost.proto);
				if (curHost.password === true) {
					$("#password").attr("placeholder", "Don't fill to keep current");
					$("#password").addClass("keepass");
				} else {
					$("#password").val(reveal(curHost.password));
				}
				$("#authapi").prop('checked', curHost.auth_api);
				if ($("#authapi").prop('checked')) {
					$("#apihostname").val(curHost.api_hostname);
					$("#apiusername").val(curHost.api_username);
					if (curHost.api_password === true) {
						$("#apipassword").attr("placeholder", "Don't fill to keep current");
						$("#apipassword").addClass("keepass");
					} else {
						$("#apipassword").val(reveal(curHost.password));
					}
					$("#apiport2").val(curHost.api_port2);
					$("fieldset.ovirt_rapi input").prop('disabled', false);
				}
				validateHostCfg(curHost);
				$("#authssh").prop('checked', curHost.auth_ssh);
				$(".showpass").hide();

			} else {
				// $("button.savecontrol").button("disable");
			}
			$(".reqrd, .api, .ssh").change(function() {
				validateHostCfg(true);
			});

			$(".showpass").button().mousedown(function(e) {
				e.stopPropagation();
				$(this).prev().attr('type','text');
			}).mouseup(function(){
				$(this).prev().attr('type','password');
			}).mouseout(function(){
				$(this).prev().attr('type','password');
			});
			$("#password").on("keyup", function( event ) {
				if ($(this).val()) {
					$(".showpass").button("enable");
				} else {
					$(".showpass").button("disable");
				}
			});
			$("#hostalias").on("blur", function( event ) {
				if (!event.relatedTarget || event.relatedTarget && event.relatedTarget.textContent != "Cancel") {
					if (! this.value) {
						$("#hostalias").tooltipster('content', 'Alias name is required').tooltipster('open');
						$(event.target).addClass( "ui-state-error" );
						$(event.target).trigger("focus");
						// validateHostCfg(curHost);
						$("button.savecontrol").button("disable");
					} else if (this.value != hostAlias && hostcfg.platforms[curPlatform].aliases[this.value]) {
						$("#hostalias").tooltipster('content', 'Host alias already exists!').tooltipster('open');
						$(event.target).addClass( "ui-state-error" );
						$(event.target).trigger("focus");
						// validateHostCfg(curHost);
						$("button.savecontrol").button("disable");
					} else {
						$("#hostalias").tooltipster("close");
						$(event.target).removeClass( "ui-state-error" );
						if (curHost.platform) {
							validateHostCfg(curHost);
						}
						// $("button.savecontrol").button("enable");
					}
				}
			});
			$("#authapi").on("change", function(event) {
				if ($(event.target).prop("checked")) {
					$("fieldset.ovirt_rapi input").prop('disabled', false);
					if (! $("#apiport2").val()) {
						$("#apiport2").val(443);
					}
				} else {
					$("fieldset.ovirt_rapi input[type!=checkbox]").prop('disabled', true);
				}
			});
		},
		open: function() {
			$('.ui-widget-overlay').addClass('custom-overlay');
		},
		close: function() {
			$(this).find( "form" ).trigger('reset');
			$("#grpname").tooltipster("destroy");
			$(this).dialog("destroy");
		}
	});
}
function hostDetailFormOracleVM(hostAlias) {
	var hostDetailFormDiv = '<div id="host-config-form"> \
	<form autocomplete="off"> \
	<fieldset> \
	<legend>Common options</legend> \
	<input type="hidden" name="uuid" id="uuid" /> \
	<label for="hostalias">Host alias</label> \
	<input type="text" name="hostalias" id="hostalias" class="reqrd" autocomplete="off" /><br> \
	<!--label for="platform">Platform</label> \
	<input type="text" id="platform" name="platform" disabled><br--> \
	<label for="hostname">Host name / IP</label> \
	<input type="text" name="hostname" id="hostname" class="reqrd" title="" autocomplete="off" /><br> \
	<label for="username">User name</label> \
	<input type="text" name="username" id="username" class="reqrd" title="" autocomplete="nope" /><br> \
	</fieldset> \
	<fieldset> \
	<legend><label><input type="checkbox" name="authapi" id="authapi" checked disabled>API&nbsp;</label></legend> \
	<label for="apiport">API Port</label> \
	<input type="number" value="7002" name="apiport" id="apiport" class="api" style="width: 5em" title="" autocomplete="off" /><br> \
	<label for="password">API Password</label> \
	<input type="password" name="password" id="password" class="api" style="width: 8em" title="" autocomplete="new-password" /><span class="showpass api">Show</span><br> \
	</fieldset> \
	<!-- Allow form submission with keyboard without duplicating the dialog button --> \
	<input type="submit" tabindex="-1" style="position:absolute; top:-1000px"> \
	</form> \
	</div>';
	$( hostDetailFormDiv ).dialog({
		height: 490,
		width: 420,
		modal: true,
		title: "Host configuration",
		buttons: {
			"Save host": {
				click: function() {
					var hostalias = $("#hostalias").val(),
					hostname = $("#hostname").val(),
					username = $("#username").val(),
					sshport = $("#sshport").val(),
					sshkey = $("#sshkeyinput").val(),
					apiport = $("#apiport").val(),
					apiproto = $("#apiproto").val(),
					password = Base64.encode(uuencode($("#password").val())),
					authapi = $("#authapi").prop('checked'),
					authssh = $("#authssh").prop('checked'),
					created = null;
					if (hostAlias) {
						created = hostcfg.platforms[curPlatform].aliases[hostAlias].created;
						delete hostcfg.platforms[curPlatform].aliases[hostAlias];
					}
					hostcfg.platforms[curPlatform].aliases[hostalias] = {
						uuid: $("#uuid").val(),
						host: hostname,
						username: username,
						ssh_port: sshport,
						ssh_key_id: sshkey,
						api_port: apiport,
						proto: apiproto,
						password: password,
						auth_api: authapi,
						auth_ssh: authssh
					};
					if (hostAlias) {
						hostcfg.platforms[curPlatform].aliases[hostalias].updated = TimeStamp();
						hostcfg.platforms[curPlatform].aliases[hostalias].created = created;
					} else {
						hostcfg.platforms[curPlatform].aliases[hostalias].created = TimeStamp();
					}
					SaveHostsCfg(true);
					$(this).dialog("close");
					$('#adminmenu a[data-abbr="hosts-' + $("#hosttable").data("platform") + '"]').trigger( "click" );
				},
				text: "Save host",
				class: 'savecontrol'
			},
			"Test connection": {
				click: function() {
					var hostalias = $("#hostalias").val(),
					hostname = $("#hostname").val(),
					username = $("#username").val(),
					sshport = $("#sshport").val(),
					sshkey = $("#sshkeyinput").val(),
					apiport = $("#apiport").val(),
					apiproto = $("#apiproto").val(),
					password = Base64.encode(uuencode($("#password").val())),
					authapi = $("#authapi").prop('checked'),
					authssh = $("#authssh").prop('checked'),
					created = null;
					if (hostAlias) {
						created = hostcfg.platforms[curPlatform].aliases[hostAlias].created;
						delete hostcfg.platforms[curPlatform].aliases[hostAlias];
					}
					hostcfg.platforms[curPlatform].aliases[hostalias] = {
						uuid: $("#uuid").val(),
						host: hostname,
						username: username,
						ssh_port: sshport,
						ssh_key_id: sshkey,
						api_port: apiport,
						proto: apiproto,
						password: password,
						auth_api: authapi,
						auth_ssh: authssh
					};
					if (hostAlias) {
						hostcfg.platforms[curPlatform].aliases[hostalias].updated = TimeStamp();
						hostcfg.platforms[curPlatform].aliases[hostalias].created = created;
					} else {
						hostcfg.platforms[curPlatform].aliases[hostalias].created = TimeStamp();
					}
					SaveHostsCfg(false);
					$(this).dialog("close");
					$('#adminmenu a[data-abbr="hosts-' + $("#hosttable").data("platform") + '"]').trigger( "click" );
					testConnection(hostalias, hostcfg.platforms[curPlatform].aliases[hostalias]);
				},
				text: "Save & Test connection",
				class: 'savecontrol'
			},
			Cancel: function() {
				$(this).dialog("close");
			}
		},
		create: function() {
			var curHost = {};
			var sshkeyel;
			$("button.savecontrol").button("disable");
			$("#hostalias").tooltipster({
				trigger: 'custom',
				position: 'right',
			});
			if (hostAlias) {
				curHost = hostcfg.platforms[curPlatform].aliases[hostAlias];
				$("#hostalias").val(hostAlias);
				$("#uuid").val(curHost.uuid);
				$("#hostname").val(curHost.host);
				// $("#platform").val(curHost.platform);
				$("#username").val(curHost.username);
				$("#sshport").val(curHost.ssh_port);
				$("#sshkeyinput").val(curHost.ssh_key_id);
				$("#apiport").val(curHost.api_port);
				$("#apiproto").val(curHost.proto);
				if (curHost.password === true) {
					$("#password").attr("placeholder", "Don't fill to keep current");
					$("#password").addClass("keepass");
				} else {
					$("#password").val(reveal(curHost.password));
				}
				validateHostCfg(curHost);
				$("#authapi").prop('checked', curHost.auth_api);
				$("#authssh").prop('checked', curHost.auth_ssh);
				$(".showpass").hide();

			} else {
				$("#authapi").prop('checked', hostcfg.platforms[curPlatform].api),
				$("#authssh").prop('checked', hostcfg.platforms[curPlatform].ssh);
			}
			$(".api").prop('disabled', !$("#authapi").is(':checked'));
			$("#apiproto").change(function() {
				if ($("#apiproto").val() == 'http') {
					$("#apiport").val(80);
				} else {
					$("#apiport").val(443);
				}
			});
			$("input[type=radio]").change(function() {
				$(".ssh").prop('disabled', !$("#authssh").is(':checked'));
				if ($("#authssh").is(':checked')) {
					if (! $("#sshport").val()) {
						$("#sshport").val(22);
					}
				}
				$(".api").prop('disabled', !$("#authapi").is(':checked'));
				if ($("#authapi").is(':checked')) {
					if (! $("#apiport").val()) {
						$("#apiport").val(443);
					}
					if (! $("#apiproto").val()) {
						$("#apiproto").val("https");
					}
				}
			});
			$(".reqrd, .api, .ssh").change(function() {
				validateHostCfg(true);
			});

			$(".showpass").button().mousedown(function(e) {
				e.stopPropagation();
				$(this).prev().attr('type','text');
			}).mouseup(function(){
				$(this).prev().attr('type','password');
			}).mouseout(function(){
				$(this).prev().attr('type','password');
			});
			$("#password").on("keyup", function( event ) {
				if ($(this).val()) {
					$(".showpass").button("enable");
				} else {
					$(".showpass").button("disable");
				}
			});
			$("#hostalias").on("blur", function( event ) {
				if (!event.relatedTarget || event.relatedTarget && event.relatedTarget.textContent != "Cancel") {
					if (! this.value) {
						$("#hostalias").tooltipster('content', 'Alias name is required').tooltipster('open');
						$(event.target).addClass( "ui-state-error" );
						$(event.target).trigger("focus");
						// validateHostCfg(curHost);
						$("button.savecontrol").button("disable");
					} else if (this.value != hostAlias && hostcfg.platforms[curPlatform].aliases[this.value]) {
						$("#hostalias").tooltipster('content', 'Host alias already exists!').tooltipster('open');
						$(event.target).addClass( "ui-state-error" );
						$(event.target).trigger("focus");
						// validateHostCfg(curHost);
						$("button.savecontrol").button("disable");
					} else {
						$("#hostalias").tooltipster("close");
						$(event.target).removeClass( "ui-state-error" );
						if (curHost.platform) {
							validateHostCfg(curHost);
						}
						// $("button.savecontrol").button("enable");
					}
				}
			});
		},
		open: function() {
			$('.ui-widget-overlay').addClass('custom-overlay');
		},
		close: function() {
			$(this).find( "form" ).trigger('reset');
			$("#grpname").tooltipster("destroy");
			$(this).dialog("destroy");
		}
	});
}

function hostDetailFormOracleDB(hostAlias, isCloned) {
	var hostDetailFormDiv = '<div id="host-config-form"> \
	<form autocomplete="off"> \
	<fieldset> \
	<legend>Common options</legend> \
	<input type="hidden" name="uuid" id="uuid" /> \
	<label for="hostalias">Host alias</label> \
	<input type="text" name="hostalias" id="hostalias" class="reqrd" autocomplete="off" /><br> \
	<label for="menu-group" id="mglabel">Menu group</label> \
	<select id="menu-group" name="menu-group"> \
	<option value="">--- select or create ---</option> \
	</select><br> \
	<label for="menu-subgroup" class="msubgrp" disabled>&#8627; subgroup</label> \
	<select id="menu-subgroup" name="menu-subgroup" class="msubgrp" disabled> \
	<option value="">--- select or create ---</option> \
	</select><br class="msubgrp"> \
	<label for="dbtype">DB type</label> \
	<select id="dbtype" name="type" style="width: 10em"> \
	<option value="Standalone">Standalone</option> \
	<option value="Multitenant">Multitenant</option> \
	<option value="RAC">RAC Standalone</option> \
	<option value="RAC_Multitenant">RAC Multitenant</option> \
	</select><br> \
	<label for="username" id="usernamelabel">User name</label> \
	<input type="text" name="username" id="username" class="reqrd" title="" autocomplete="nope" /><br> \
	<label for="password">Password</label> \
	<input type="password" name="password" id="password" style="width: 8em" title="" autocomplete="new-password" /><span class="showpass">Show</span><br> \
	<label for="port">Port</label> \
	<input type="number" value="1521" name="port" id="port" style="width: 5em" title="" autocomplete="off" /><br> \
	</fieldset> \
	<fieldset> \
	<legend>Host options</legend> \
	<div id="multihostlist"> \
	<div id="Host" class="multihostorder"> \
	<div class="hostlist"> \
	<div class="listWrapper"><label for="hostname" class="fo" >Host <span class="hostorder"></span></label> \
	<input type="text" name="hostname" class="reqrd" title="" autocomplete="off" /><span class="appendhost appendbutton far fa-plus-square"></span><br>\
	<label for="instance" id="odbInstance">Service</label> \
	<input type="text" name="instance" id="instance" class="reqrd" autocomplete="off" /> \
	<div class="servicelist"><br><label class="services">PDB Service <span class="serviceorder">1</span></label><input type="text" name="service" title="" autocomplete="off"  /> \
	<span class="appendservice far fa-plus-square services appendbutton"></span><span class="removeservice appendbutton far fa-minus-square services"></span><br></div> \
	</div> \
	</div> \
	</div> \
	</div> \
	</fieldset> \
	<fieldset> \
	<legend>Data Guard</legend> \
	<div id="multidghostlist"> \
	<div id="Host-1" class="multidghostorder"> \
	<div class="dghostlist"><label for="dghostname">Host <span class="dghostorder"></span></label> \
	<input type="text" id="firstDGhost" name="dghostname" title="" autocomplete="off" /></div><span class="appenddghost appendbutton far fa-plus-square"></span><br> \
	<div class="dgCDBservices"><label for="dgCDBservice">Service <span class="dgCDBserviceorder"></span></label>	\
	<input type="text" id="firstDGservice" name="dgCDBservice" title="" autocomplete="off" /><br></div> \
	<div class="dgservicelist dgservices"><label for="dgservicename">PDB service <span class="dgserviceorder"></span></label> \
	<input type="text" name="service" title="" autocomplete="off" /><span class="appendservice appendbutton far fa-plus-square"></span><br></div> \
	</div> \
	</div> \
	</fieldset> \
	<!-- Allow form submission with keyboard without duplicating the dialog button --> \
	<input type="submit" tabindex="-1" style="position:absolute; top:-1000px"> \
	</form> \
	</div>';
	$( hostDetailFormDiv ).dialog({
		height: 520,
		width: 420,
		modal: true,
		title: "Host configuration",
		buttons: {
			"Save host": {
				click: function() {
					var hostalias = $("#hostalias").val(),
					instance = $("#instance").val(),
					//services = $("#services").val(),
					type = $("#dbtype").val(),
					hostname = $("input[name=hostname]").val(),
					username = $("#username").val(),
					port = $("#port").val(),
					password = Base64.encode(uuencode($("#password").val())),
					menu_group = $("#menu-group").val(),
					menu_subgroup = $("#menu-subgroup").val(),
					created = null;
					if (hostAlias) {
						created = hostcfg.platforms[curPlatform].aliases[hostAlias].created;
						delete hostcfg.platforms[curPlatform].aliases[hostAlias];
					}
					hostcfg.platforms[curPlatform].aliases[hostalias] = {
						uuid: $("#uuid").val(),
						instance: instance,
						type: type,
						host: hostname,
						username: username,
						password: password,
						port: port,
						menu_group: menu_group,
						menu_subgroup: menu_subgroup
					};
					if (hostAlias) {
						hostcfg.platforms[curPlatform].aliases[hostalias].updated = TimeStamp();
						hostcfg.platforms[curPlatform].aliases[hostalias].created = created;
					} else {
						hostcfg.platforms[curPlatform].aliases[hostalias].created = TimeStamp();
					}

					if (type == "RAC" || type == "RAC_Multitenant") {
						hostcfg.platforms[curPlatform].aliases[hostalias].hosts = $("input[name=hostname]").map(function(){return $(this).val();}).get();
						delete hostcfg.platforms[curPlatform].aliases[hostalias].host;
						var RACcnt = 0;
						$.each(hostcfg.platforms[curPlatform].aliases, function(i, host) {
							if (host.type == "RAC") {
								RACcnt++;
							}
						});
						if ( type == "RAC_Multitenant") {
							//var car = getPDBServices("multihost");//$("input[name=service]").map(function(){return $(this).val();}).get();
							var serviceArray = [];//$("#multihost .Host").children("input[name=service]").map(function(){return $(this).val();}).get();
 							$("#multihostlist").children(".multihostorder").each(function( index ) {
								var id = $(this).attr("id");
								var firstService;
								if(index <= 0){
									firstService = $("#"+id+" input[name=instance]").val();
								} else {
									firstService = $("#"+id+" input[name=CDBservice]").val();
								}
								var car = $("#"+id+" input[name=service]").map(function(){return $(this).val();}).get();
								car.unshift(firstService);
								serviceArray.push(car);
							});
							hostcfg.platforms[curPlatform].aliases[hostalias].services = serviceArray;
						}
						if (RACcnt <= 1) {
							SaveHostsCfg(true);
						} else if (RACcnt >= 1 && sysInfo.unlimitedRAC) {
							SaveHostsCfg(true);
						} else {
							$.message('<div><p>You use LPAR2RRD Oracle Database Free Edition. You can define only one Oracle RAC instance.</p><p>Number of Oracle stand-alone DBs is not restricted.</p><p>You can add RAC nodes as stand-alone instance but you lose <a href="https://www.lpar2rrd.com/Oracle-DB-performance-monitoring.php"target="_blank">RAC only metrics</a></p><p>Benefits of the <a href="https://lpar2rrd.com/support.htm#benefits" target="_blank"><b>Enterprise Edition</b></a>.</p></div>', "Free Edition limitation");
						}
					} else if (type === "Standalone") {
						if ($("#firstDGhost").value != ""){
							var hosts = $("input[name=dghostname]").map(function(){return $(this).val();}).get();
							var	instances =$("input[name=dgCDBservice]").map(function(){return $(this).val();}).get();
							var i;
							var dgs = [];
							for (i = 0; i < hosts.length; i++) {
								var dg = {instance: [instances[i]], hosts: [hosts[i]]};
								dgs.push(dg);
							}
							hostcfg.platforms[curPlatform].aliases[hostalias].dataguard = dgs;
						}
						SaveHostsCfg(true);
					} else if (type === "Multitenant") {
						hostcfg.platforms[curPlatform].aliases[hostalias].services = $("#Host input[name=service]").map(function(){return $(this).val();}).get();
						if ($("#firstDGhost").value != ""){
							var dgs = [];
							$("#multidghostlist").children(".multidghostorder").each(function( index ) {
								var id = $(this).attr("id");
								var firstService;
								firstService = $("#"+id+" input[name=dgCDBservice]").val();
								var host = $("#"+id+" input[name=dghostname]").val();
								var pdbs = $("#"+id+" input[name=service]").map(function(){return $(this).val();}).get();
								var dg = {instance: [firstService], hosts: [host], pdbs: pdbs};
								dgs.push(dg);
							});

							hostcfg.platforms[curPlatform].aliases[hostalias].dataguard = dgs;
						}
						SaveHostsCfg(true);
					}
					$(this).dialog("close");
					$('#adminmenu a[data-abbr="hosts-' + $("#hosttable").data("platform") + '"]').trigger( "click" );
				},
				text: "Save host",
				class: 'savecontrol'
			},
			"Test connection": {
				create: function() {
					$(this).hide();
				},
				click: function() {
					var hostalias = $("#hostalias").val(),
					instance = $("#instance").val(),
					type = $("#dbtype").val(),
					hostname = $("#hostname").val(),
					username = $("#username").val(),
					port = $("#port").val(),
					password = Base64.encode(uuencode($("#password").val())),
					created = null;
					if (hostAlias) {
						created = hostcfg.platforms[curPlatform].aliases[hostAlias].created;
						delete hostcfg.platforms[curPlatform].aliases[hostAlias];
					}
					hostcfg.platforms[curPlatform].aliases[hostalias] = {
						uuid: $("#uuid").val(),
						instance: instance,
						type: type,
						host: hostname,
						username: username,
						password: password,
						port: port
					};
					if (hostAlias) {
						hostcfg.platforms[curPlatform].aliases[hostalias].updated = TimeStamp();
						hostcfg.platforms[curPlatform].aliases[hostalias].created = created;
					} else {
						hostcfg.platforms[curPlatform].aliases[hostalias].created = TimeStamp();
					}
					SaveHostsCfg(false);
					$(this).dialog("close");
					$('#adminmenu a[data-abbr="hosts-' + $("#hosttable").data("platform") + '"]').trigger( "click" );
					testConnection(hostalias, hostcfg.platforms[curPlatform].aliases[hostalias]);
				},
				text: "Save & Test connection",
				class: 'savecontrol'
			},
			Cancel: function() {
				$(this).dialog("close");
			}
		},
		create: function() {
			var curHost = {};
			var sshkeyel;
			var hostListRefresh = function() {
				$(".hostlist").each(function( index ) {
					$(this).find(".hostorder").text(index + 1);
					$(this).find(".appendhost").hide();
				});
				$(".hostlist").last().find(".appendhost").show();

				$(".multihostorder").each(function( index ) {
					$(this).attr("id","Host-"+(index + 1));
				});
			};
			var dghostListRefresh = function() {
				$(".dghostlist").each(function( index ) {
					$(this).find(".dghostorder").text(index + 1);
					$(this).find(".appenddghost").hide();
				});
				$(".dghostlist").last().find(".appenddghost").show();

				$(".multidghostorder").each(function( index ) {
					$(this).attr("id","Host-"+(index + 1));
				});
			};
			var serviceListRefresh = function(div) {
				var total = $("#"+div).find(".servicelist").length;
				$("#"+div).find(".servicelist").each(function( index ) {
					$(this).find(".serviceorder").text(index + 1);
					if (index !== total - 1){
						$(this).find(".appendservice").hide();
					}else{
						$(this).find(".appendservice").show();
					}
				});
				//$(".servicelist").last().find(".appendservice").show();
			};
			var dgcdbserviceRefresh = function() {
				$(".dgCDBservices").each(function( index ) {
					$(this).find(".dgCDBserviceorder").text(index + 1);
				});
			};
			var cdbserviceRefresh = function() {
				$(".CDBservices").each(function( index ) {
					$(this).find(".CDBserviceorder").text(index + 2);
				});
			};
			var getPDBServices = function(div) {
				//var car = $("input[name=service]").map(function(){return $(this).val();}).get();
				var car = $("#"+div).children("input[name=service]").map(function(){return $(this).val();}).get();

				return car;
			};
			var getODBGroups = function() {
				var dbgroups = {groups: {}, subgroups: {}};
				$.each(hostcfg.platforms[curPlatform].aliases, function(i, host) {
					if (host.menu_group) {
						if ($.isEmptyObject(dbgroups.groups[host.menu_group])) {
							dbgroups.groups[host.menu_group] = {};
						}
					}
					if (host.menu_subgroup) {
						if ($.isEmptyObject(dbgroups.subgroups[host.menu_subgroup])) {
							dbgroups.subgroups[host.menu_subgroup] = {};
						}
					}
				});
				return dbgroups;
			};
			var ODBGroups = getODBGroups();
			$.each(Object.keys(ODBGroups.groups).sort(), function(key, val) {
				$("<option />", {text: val}).appendTo($("#menu-group"));
			});
			$.each(Object.keys(ODBGroups.subgroups).sort(), function(key, val) {
				$("<option />", {text: val}).appendTo($("#menu-subgroup"));
			});
			$("#menu-group").select2({
				tags: true,
				dropdownParent: $(this)
			});
			$("#menu-subgroup").select2({
				tags: true,
				dropdownParent: $(this)
			});
			$("button.savecontrol").button("disable");
			$("#hostalias, #password").tooltipster({
				trigger: 'custom',
				position: 'right',
			});
			$("#dbtype").on("change", function(e) {
				if (e.target.value == "RAC") {
					$("#odbInstance").text("Service");
					$(".services, .servicelist").hide();
					$(".appendhost, .removehost, .hostlist").show();
					$(".fo").text("Instance VIP 1");
					hostListRefresh();
					$('#firstService input[type=text]').removeClass('reqrd');
					$(".CDBservices").hide();
				}else if (e.target.value == "Multitenant") {
					$(".appendservice, .removeservice, .servicelist").show();
					serviceListRefresh();
					$(".hostorder").empty();
					$(".hostlist").hide();
					$(".hostlist").first().show();
					$("#odbInstance").text("CDB Service");
					$(".appendhost, .removehost").hide();
					$('#firstService input[type=text]').addClass('reqrd');
					$(".services").show();
					$(".dgservices, .dgservicelist").show();
					$(".CDBservices").hide();
					$(".fo").text("Host");
				}else if (e.target.value == "RAC_Multitenant") {
					$(".appendservice, .removeservice, .services, .servicelist").show();
				    serviceListRefresh();
					$(".hostorder").empty();
					$(".hostlist").hide();
					$(".hostlist").first().show();
					$("#odbInstance").text("CDB Service 1");
					$(".appendhost, .removehost").hide();
					//$('#firstService input[type=text]').addClass('reqrd');
					$(".appendhost, .removehost, .hostlist").show();
					hostListRefresh();
					//$("#odbInstance").hide();
					//$('#instance').hide();
					$(".CDBservices").show();
					$(".fo").text("Instance VIP 1");
				} else {
					$("#odbInstance").text("Service");
					$(".hostorder").empty();
					$(".hostlist").hide();
					$(".hostlist").first().show();
					$(".appendhost, .removehost").hide();
					$('#firstService input[type=text]').removeClass('reqrd');
					$(".services, .servicelist, .dgservicelist, .dgservices").hide();
					$(".fo").text("Host");
					//$(".CDBservices").hide();
				}
			});
			$("#menu-group").on("change", function(e) {
				if (e.target.value == "") {
					$("#menu-subgroup").val("").trigger("change");
					$(".msubgrp").prop("disabled", true);
				} else {
					$(".msubgrp").prop("disabled", false);
				}
			});
			if (hostAlias) {
				curHost = hostcfg.platforms[curPlatform].aliases[hostAlias];
				$("#hostalias").val(hostAlias);
				$("#uuid").val(curHost.uuid);
				$("#instance").val(curHost.instance);
				$("#dbtype").val(curHost.type);
				if (curHost.menu_group) {
					$("#menu-group").val(curHost.menu_group).trigger('change');
					$(".msubgrp").prop("disabled", false);
				}
				$("#menu-subgroup").val(curHost.menu_subgroup).trigger('change');
				if (curHost.type == "Multitenant") {
					if (curHost.services){
						$("#firstService").remove();
					}
					$.each(curHost.services, function(i, value) {
						if(i == 0){
							$("input[name=service]").val(value);
						}else{
							var order = i + 1;
							var ni = '<div class="servicelist"><label class="services">PDB Service <span class="serviceorder">'+ order +'</span></label><input type="text" name="service" services" title="" autocomplete="off" value="' + value + '" /><span class="appendservice appendbutton far fa-plus-square services"></span><span class="removeservice appendbutton far fa-minus-square services"></span><br></div>';

							$(".multihostorder").append(ni);
						}
					});
					serviceListRefresh();
				}
				if (curHost.type == "RAC") {
					$.each(curHost.hosts, function(i, value) {
						if (i == 0) {
							$("input[name=hostname]").val(value);
						} else {
							var ni = '<div class="hostlist"><label>Instance VIP <span class="hostorder"></span></label><input type="text" name="hostname" class="reqrd" title="" autocomplete="off" value="' + value + '" /><span class="appendhost appendbutton far fa-plus-square"></span><span class="removehost appendbutton far fa-minus-square"></span><br></div>';
							$(ni).insertBefore( $("#odbInstance") );
						}
					});
					hostListRefresh();
				} else if(curHost.type == "RAC_Multitenant") {
					//.val(curHost.instance);
					$.each(curHost.hosts, function(i, value) {
					var curServices = curHost.services[i];
					if (i == 0) {
						var div = $(this).parent().attr("id");
						var pdbGUI;
						$("input[name=hostname]").val(value);
						$("input[name=service]").val(curServices[1]);
						//#$("input[name=service]").remove();
						var counter;
						var i;
						for (i = 0; i < curServices.length; i++) {
							var pdb = curServices[i];
							if ( i > 1){
								counter = i;
								pdbGUI =  '<div class="servicelist services" "><label for="servicename">PDB service <span class="serviceorder">'+ i +'</span></label><input type="text" name="service" title="" autocomplete="off" value="'+pdb+'"/><span class="appendservice appendbutton far fa-plus-square"></span><br></div>';
								$(".multihostorder").append(pdbGUI);
							}

						}

						if (counter > 1){
							serviceListRefresh(div);
						}
					} else {
					var ni = '<div id="HOST-1" class="multihostorder"> <span class="hostSeparator"></span> <div class="hostlist"><label>Host <span class="hostorder"></span></label><input type="text" name="hostname" class="reqrd" title="" autocomplete="off" value="'+value+'" /><span class="appendhost appendbutton far fa-plus-square"></span><span class="removehost appendbutton far fa-minus-square"></span><br>';
					var cdb = curServices[0];
					ni +=  '</div>	<div class="CDBservices"><label for="CDBservice">CDB Service <span class="CDBserviceorder"></span></label>	<input type="text" name="CDBservice" class="reqrd" title="" autocomplete="off" value="'+cdb+'" /><br>';
					var j;
					for (j = 0; j < curServices.length; j++) {
						var pdb = curServices[j];
						if ( j > 0){
							ni +=  '</div><div class="servicelist services" id="firstService"><label for="servicename">PDB service <span class="serviceorder">'+ j +'</span></label><input type="text" name="service" title="" autocomplete="off" value="'+pdb+'"/><span class="appendservice appendbutton far fa-plus-square"></span><br></div></div>';
						}
					}
					$("#multihostlist").append(ni);
					}
					var div = $(this).parent().parent().attr("id");
					serviceListRefresh(div);
					});
					cdbserviceRefresh();
					hostListRefresh();

				} else {
					$("input[name=hostname]").val(curHost.host);
				}
				if (curHost.dataguard){
					$("#firstDGhost").val(curHost.dataguard[0].hosts[0]);
					$("#firstDGservice").val(curHost.dataguard[0].instance[0]);
					for (var i = 1, l =  curHost.dataguard.length; i < l; i++) {
						var obj =  curHost.dataguard[i];
						var ni = '<div id="HOST-2" class="multidghostorder"> <span class="hostSeparator"></span> <div class="dghostlist"><label>Host <span class="dghostorder"></span></label><input type="text"value="' + curHost.dataguard[i].hosts[0] +'" name="dghostname" title="" autocomplete="off" /><span class="appenddghost appendbutton far fa-plus-square"></span><span class="removehost appendbutton far fa-minus-square"></span><br></div><div class="dgCDBservices"><label for="CDBservice">Service <span class="dgCDBserviceorder"></span></label><input type="text" name="dgCDBservice" title="" value="' + curHost.dataguard[i].instance[0] +'"autocomplete="off" /><br></div></div>';
						$("#multidghostlist").append(ni);
					}
					dgcdbserviceRefresh();
					dghostListRefresh();
				}
				$("#username").val(curHost.username);
				$("#port").val(curHost.port);
				if (curHost.password === true) {
					$("#password").attr("placeholder", "Don't fill to keep current");
					$("#password").addClass("keepass");
				} else {
					$("#password").val(reveal(curHost.password));
				}
				validateHostCfg(curHost);
				$(".showpass").hide();

			} else {
				$("#dbtype").val("Standalone");
			}
			$("#dbtype").trigger("change");
			$(this).on("change", ".reqrd, .api, .ssh", function() {
				validateHostCfg(true);
			});

			$(".showpass").button().mousedown(function(e) {
				e.stopPropagation();
				$(this).prev().attr('type','text');
			}).mouseup(function(){
				$(this).prev().attr('type','password');
			}).mouseout(function(){
				$(this).prev().attr('type','password');
			});
			$("#password").on("keyup", function( event ) {
				if ($(this).val()) {
					$(".showpass").button("enable");
				} else {
					$(".showpass").button("disable");
				}
			});
			$(this).on("click", ".appendhost", function( event ) {
				event.stopPropagation();
				var type = $( "#dbtype option:selected" ).text();
				if ( type == "RAC Multitenant" ) {
				var ni = '<div id="HOST-1" class="multihostorder">  <div class="hostlist"><div class="listWrapper"><span class="hostSeparator"></span><label>Host <span class="hostorder"></span></label><input type="text" name="hostname" class="reqrd" title="" autocomplete="off" /><span class="appendhost appendbutton far fa-plus-square"></span><span class="removehost appendbutton far fa-minus-square"></span><br>	<div class="CDBservices"><label for="CDBservice">CDB Service <span class="CDBserviceorder"></span></label>	<input type="text" name="CDBservice" class="reqrd" title="" autocomplete="off" /><br></div><div class="servicelist services" id="firstService"><label for="servicename">PDB service <span class="serviceorder"></span></label><input type="text" name="service" title="" autocomplete="off" /><span class="appendservice appendbutton far fa-plus-square"></span><br></div></div></div></div>';
				$("#multihostlist").append(ni);
				cdbserviceRefresh();
				} else {
					var ni = '<div class="hostlist"><label>Instance VIP <span class="hostorder"></span></label><input type="text" name="hostname" class="reqrd" title="" autocomplete="off" /><span class="appendhost appendbutton far fa-plus-square"></span><span class="removehost appendbutton far fa-minus-square"></span><br></div>';
					$(ni).insertBefore( $("#odbInstance") );
				}
				hostListRefresh();
				return false;
			});
			$(this).on("click", ".appenddghost", function( event ) {
				event.stopPropagation();
				var type = $( "#dbtype option:selected" ).text();
				var ni;
				if( type == "RAC Multitenant" || type == "Multitenant"){
					ni = '<div id="HOST-1" class="multidghostorder"> <span class="hostSeparator"></span> <div class="dghostlist"><label>Host <span class="dghostorder"></span></label><input type="text" name="dghostname" title="" autocomplete="off" /><span class="appenddghost appendbutton far fa-plus-square"></span><span class="removehost appendbutton far fa-minus-square"></span><br></div><div class="dgCDBservices"><label for="CDBservice">Service <span class="dgCDBserviceorder"></span></label><input type="text" name="dgCDBservice" title="" autocomplete="off" /><br></div> </div><div class="servicelist services" id="firstService"><label for="servicename">PDB service <span class="serviceorder"></span></label><input type="text" name="service" title="" autocomplete="off" /><span class="appendservice appendbutton far fa-plus-square"></span><br></div></div>';
				}else{
					ni = '<div id="HOST-1" class="multidghostorder"> <span class="hostSeparator"></span> <div class="dghostlist"><label>Host <span class="dghostorder"></span></label><input type="text" name="dghostname" title="" autocomplete="off" /><span class="appenddghost appendbutton far fa-plus-square"></span><span class="removehost appendbutton far fa-minus-square"></span><br></div><div class="dgCDBservices"><label for="CDBservice">Service <span class="dgCDBserviceorder"></span></label><input type="text" name="dgCDBservice" title="" autocomplete="off" /><br></div></div>';
				}
				$("#multidghostlist").append(ni);
				dgcdbserviceRefresh();
				dghostListRefresh();
				return false;
			});

			$(this).on("click", ".removehost", function( event ) {
				event.stopPropagation();
				$(this).closest(".hostlist").remove();
				hostListRefresh();
				return false;
			});
			$(this).on("click", ".appendservice", function( event ) {
				event.stopPropagation();
				var ni = '<div class="servicelist"><label class="services">PDB Service <span class="serviceorder"></span></label><input type="text" name="service" class="services" title="" autocomplete="off" /><span class="appendservice appendbutton far fa-plus-square services"></span><span class="removeservice appendbutton far fa-minus-square services"></span><br></div>';

				$(this).closest(".listWrapper").append(ni);
				var div = $(this).parents(".multihostorder").attr("id");

				serviceListRefresh(div);
				return false;
			});
			$(this).on("click", ".removeservice", function( event ) {
				event.stopPropagation();
				var div = $(this).parents(".multihostorder").attr("id");
				$(this).closest("div").remove();

				serviceListRefresh(div);
				return false;
			});
			$("#hostalias").on("blur", function( event ) {
				if (!event.relatedTarget || event.relatedTarget && event.relatedTarget.textContent != "Cancel") {
					var regex = new RegExp("^[a-zA-Z0-9_\.\-]+$");
					if (! this.value) {
						$("#hostalias").tooltipster('content', 'Alias name is required').tooltipster('open');
						$(event.target).addClass( "ui-state-error" );
						$(event.target).trigger("focus");
						// validateHostCfg(curHost);
						$("button.savecontrol").button("disable");
					} else if (this.value != hostAlias && hostcfg.platforms[curPlatform].aliases[this.value]) {
						$("#hostalias").tooltipster('content', 'Host alias already exists!').tooltipster('open');
						$(event.target).addClass( "ui-state-error" );
						$(event.target).trigger("focus");
						// validateHostCfg(curHost);
						$("button.savecontrol").button("disable");
					} else if (! regex.test(this.value)) {
						$("#hostalias").tooltipster('content', 'Bad characters used in this field').tooltipster('open');
						$(event.target).addClass( "ui-state-error" );
						$(event.target).trigger("focus");
						// validateHostCfg(curHost);
						$("button.savecontrol").button("disable");
					} else {
						$("#hostalias").tooltipster("close");
						$(event.target).removeClass( "ui-state-error" );
						validateHostCfg(curHost);
						// $("button.savecontrol").button("enable");
					}
				}
			});
			$("#password").on("change", function(event) {
				var atRegex = RegExp("@");
				if (atRegex.test(event.target.value)) {
					$("#password").tooltipster('content', "Don't use @ characters in password field").tooltipster('open');
					$(event.target).addClass( "ui-state-error" );
					$(event.target).trigger("focus");
					// validateHostCfg(curHost);
					$("button.savecontrol").button("disable");
				} else {
					$("#password").tooltipster("close");
					$(event.target).removeClass( "ui-state-error" );
					validateHostCfg(curHost);
				}
			});
		},
		open: function() {
			$('.ui-widget-overlay').addClass('custom-overlay');
		},
		close: function() {
			if (isCloned && hostAlias) {
				delete hostcfg.platforms[curPlatform].aliases[hostAlias];
			}
			$(this).find( "form" ).trigger('reset');
			$("#grpname").tooltipster("destroy");
			$(this).dialog("destroy");
		}
	});
}

function hostDetailFormSQLServer(hostAlias) {
	var hostDetailFormDiv = '<div id="host-config-form"> \
	<form autocomplete="off"> \
	<fieldset class="nohide"> \
	<legend>Common options</legend> \
	<input type="hidden" name="uuid" id="uuid" /> \
	<label for="hostalias">Hostname alias</label> \
	<input type="text" name="hostalias" id="hostalias" class="reqrd" autocomplete="off" /><br> \
	<label for="instance" id="odbInstance">DB name</label> \
	<input type="text" name="instance" id="instance" class="reqrd" autocomplete="off" /> <br>\
	<div class="hostlist"><label for="hostname">Host <span class="hostorder"></span></label> \
	<input type="text" name="hostname" class="reqrd" title="" autocomplete="off" /></div> <br>\
	<label for="username" id="usernamelabel">User name</label> \
	<input type="text" name="username" id="username" class="reqrd" title="" autocomplete="nope" /><br> \
	<label for="password">Password</label> \
	<input type="password" name="password" id="password" style="width: 8em" title="" autocomplete="new-password" /><span class="showpass">Show</span><br> \
	<label for="port">Port</label> \
	<input type="number" value="1433" name="port" id="port" style="width: 5em" title="" autocomplete="off" /><br><br> \
	<input type="checkbox" class="ui-dform-checkbox" name="mirrored" id="mirrored"><label for="mirrored">Multi-subnet failover </label> \
	<input type="checkbox" class="ui-dform-checkbox" name="useWhitelist" id="useWhitelist"><label for="useWhitelist">Use Whitelist </label> \
	</fieldset> \
	<fieldset id="whitelistfs" style="display:none"> \
	<legend>Whitelist</legend> \
	<div id="multidblist"> \
	<div id="whitedb" class="dblistorder"> \
	<div class="dblist"><label for="whitedb">DB <span class="dborder"></span></label> \
	<input type="text" name="whitedb" title="" autocomplete="off" /><span class="appendwhitedb appendbutton far fa-plus-square"></span><br></div> \
	</div> \
	</fieldset> \
	<!-- Allow form submission with keyboard without duplicating the dialog button --> \
	<input type="submit" tabindex="-1" style="position:absolute; top:-1000px"> \
	</form> \
	</div>';
	$( hostDetailFormDiv ).dialog({
		height: 490,
		width: 420,
		modal: true,
		title: "Host configuration",
		buttons: {
			"Save host": {
				click: function() {
					var hostalias = $("#hostalias").val(),
					instance = $("#instance").val(),
					type = "Standalone",
					hostname = $("input[name=hostname]").val(),
					username = $("#username").val(),
					port = $("#port").val(),
					password = Base64.encode(uuencode($("#password").val())),
					mirrored = $("#mirrored").prop('checked'),
					use_whitelist = $("#useWhitelist").prop('checked'),
					dbs = $("input[name=whitedb]").map(function(){return $(this).val();}).get(),
					created = null;
					if (hostAlias) {
						created = hostcfg.platforms[curPlatform].aliases[hostAlias].created;
						delete hostcfg.platforms[curPlatform].aliases[hostAlias];
					}
					hostcfg.platforms[curPlatform].aliases[hostalias] = {
						uuid: $("#uuid").val(),
						instance: instance,
						type: type,
						host: hostname,
						username: username,
						password: password,
						port: port,
						dbs: dbs,
						mirrored: mirrored,
						use_whitelist: use_whitelist
					};
					if (hostAlias) {
						hostcfg.platforms[curPlatform].aliases[hostalias].updated = TimeStamp();
						hostcfg.platforms[curPlatform].aliases[hostalias].created = created;
					} else {
						hostcfg.platforms[curPlatform].aliases[hostalias].created = TimeStamp();
					}

					if (type === "Standalone") {
						SaveHostsCfg(true);
					}
					$(this).dialog("close");
					$('#adminmenu a[data-abbr="hosts-' + $("#hosttable").data("platform") + '"]').trigger( "click" );
				},
				text: "Save host",
				class: 'savecontrol'
			},
			"Test connection": {
				create: function() {
					$(this).hide();
				},
				click: function() {
					var hostalias = $("#hostalias").val(),
					instance = $("#instance").val(),
					type = $("#dbtype").val(),
					hostname = $("#hostname").val(),
					username = $("#username").val(),
					port = $("#port").val(),
					password = Base64.encode(uuencode($("#password").val())),
					created = null;
					if (hostAlias) {
						created = hostcfg.platforms[curPlatform].aliases[hostAlias].created;
						delete hostcfg.platforms[curPlatform].aliases[hostAlias];
					}
					hostcfg.platforms[curPlatform].aliases[hostalias] = {
						uuid: $("#uuid").val(),
						instance: instance,
						type: type,
						host: hostname,
						username: username,
						password: password,
						port: port
					};
					if (hostAlias) {
						hostcfg.platforms[curPlatform].aliases[hostalias].updated = TimeStamp();
						hostcfg.platforms[curPlatform].aliases[hostalias].created = created;
					} else {
						hostcfg.platforms[curPlatform].aliases[hostalias].created = TimeStamp();
					}
					SaveHostsCfg(false);
					$(this).dialog("close");
					$('#adminmenu a[data-abbr="hosts-' + $("#hosttable").data("platform") + '"]').trigger( "click" );
					testConnection(hostalias, hostcfg.platforms[curPlatform].aliases[hostalias]);
				},
				text: "Save & Test connection",
				class: 'savecontrol'
			},
			Cancel: function() {
				$(this).dialog("close");
			}
		},
		create: function() {
			var curHost = {};
			var sshkeyel;
			$("#menu-group").select2({
				tags: true,
				dropdownParent: $(this)
			});
			$("#menu-subgroup").select2({
				tags: true,
				dropdownParent: $(this)
			});
			$("button.savecontrol").button("disable");
			$("#hostalias").tooltipster({
				trigger: 'custom',
				position: 'right',
			});
			var dbListRefresh = function() {
				$(".dblist").each(function( index ) {
					$(this).find(".dborder").text(index + 1);
					$(this).find(".appendwhitedb").hide();
				});
				$(".dblist").last().find(".appendwhitedb").show();

				$(".dblistorder").each(function( index ) {
					$(this).attr("id","Host-"+(index + 1));
				});
			};
			$(this).on("click", ".appendwhitedb", function( event ) {
				event.stopPropagation();
				var type = $( "#dbtype option:selected" ).text();
				var ni = '<div class="dblist"><label>DB <span class="dborder"></span></label><input type="text" name="whitedb" class="reqrd" title="" autocomplete="off" /><span class="appendwhitedb appendbutton far fa-plus-square"></span><span class="removewhitedb appendbutton far fa-minus-square"></span><br></div>';
				$("#multidblist").append(ni);
				dbListRefresh();
				return false;
			});
			$(this).on("click", ".removewhitedb", function( event ) {
				event.stopPropagation();
				$(this).closest("div").remove();
				dbListRefresh();
				return false;
			});
			$("#menu-group").on("change", function(e) {
				if (e.target.value == "") {
					$("#menu-subgroup").val("").trigger("change");
					$(".msubgrp").prop("disabled", true);
				} else {
					$(".msubgrp").prop("disabled", false);
				}
			});
			if (hostAlias) {
				curHost = hostcfg.platforms[curPlatform].aliases[hostAlias];
				$("#hostalias").val(hostAlias);
				$("#uuid").val(curHost.uuid);
				$("#instance").val(curHost.instance);
				$("#dbtype").val(curHost.type);
				$("input[name=hostname]").val(curHost.host);
				// $("#platform").val(curHost.platform);
				$("#username").val(curHost.username);
				$("#port").val(curHost.port);
				if (curHost.password === true) {
					$("#password").attr("placeholder", "Don't fill to keep current");
					$("#password").addClass("keepass");
				} else {
					$("#password").val(reveal(curHost.password));
				}
				validateHostCfg(curHost);
				$(".showpass").hide();

				$("#mirrored").prop('checked', curHost.mirrored);
				$("#useWhitelist").prop('checked', curHost.use_whitelist);
				if ($("#useWhitelist").prop("checked")) {
					$("#whitelistfs").show();
				}

				$.each(curHost.dbs, function(i, value) {
					if (i == 0) {
						$("input[name=whitedb]").val(value);
					} else {
						var ni = '<div class="dblist"><label>DB <span class="dborder"></span></label><input type="text" name="whitedb" value="'+value+'" text="'+value+'"  title="" autocomplete="off" /><span class="appendwhitedb appendbutton far fa-plus-square"></span><span class="removewhitedb appendbutton far fa-minus-square"></span><br></div>';
						$("#multidblist").append(ni);
					}
				});
				dbListRefresh();

			} else {
				$("#dbtype").val("Standalone");
			}
			$("#dbtype").trigger("change");
			$(this).on("change", ".reqrd, .api, .ssh", function() {
				validateHostCfg(true);
			});

			$(".showpass").button().mousedown(function(e) {
				e.stopPropagation();
				$(this).prev().attr('type','text');
			}).mouseup(function(){
				$(this).prev().attr('type','password');
			}).mouseout(function(){
				$(this).prev().attr('type','password');
			});
			$("#password").on("keyup", function( event ) {
				if ($(this).val()) {
					$(".showpass").button("enable");
				} else {
					$(".showpass").button("disable");
				}
			});
			$("#hostalias").on("blur", function( event ) {
				if (!event.relatedTarget || event.relatedTarget && event.relatedTarget.textContent != "Cancel") {
					var regex = new RegExp("^[a-zA-Z0-9_\.\-]+$");
					if (! this.value) {
						$("#hostalias").tooltipster('content', 'Alias name is required').tooltipster('open');
						$(event.target).addClass( "ui-state-error" );
						$(event.target).trigger("focus");
						// validateHostCfg(curHost);
						$("button.savecontrol").button("disable");
					} else if (this.value != hostAlias && hostcfg.platforms[curPlatform].aliases[this.value]) {
						$("#hostalias").tooltipster('content', 'Host alias already exists!').tooltipster('open');
						$(event.target).addClass( "ui-state-error" );
						$(event.target).trigger("focus");
						// validateHostCfg(curHost);
						$("button.savecontrol").button("disable");
					} else if (! regex.test(this.value)) {
						$("#hostalias").tooltipster('content', 'Bad characters used in this field').tooltipster('open');
						$(event.target).addClass( "ui-state-error" );
						$(event.target).trigger("focus");
						// validateHostCfg(curHost);
						$("button.savecontrol").button("disable");
					} else {
						$("#hostalias").tooltipster("close");
						$(event.target).removeClass( "ui-state-error" );
						if (curHost.platform) {
							validateHostCfg(curHost);
						}
						// $("button.savecontrol").button("enable");
					}
				}
			});

			$("#useWhitelist, #mirrored").checkboxradio();
			$("#host-config-form").on("change", "#useWhitelist", function (ev) {
				if ($(ev.target).prop("checked")) {
					//$("#savetestbutton").button("disable");
					$("#savetestbutton").button("enable");
					$("#host-config-form fieldset").show(200);
				} else {
					$("#host-config-form fieldset").each(function() {
						if (! $(this).hasClass("nohide")) {
							$(this).hide(200);
						}
					});
				}
			});
		},
		open: function() {
			$('.ui-widget-overlay').addClass('custom-overlay');
		},
		close: function() {
			$(this).find( "form" ).trigger('reset');
			$("#grpname").tooltipster("destroy");
			$(this).dialog("destroy");
		}
	});
}

function hostDetailFormPostgres(hostAlias) {
	var hostDetailFormDiv = '<div id="host-config-form"> \
	<form autocomplete="off"> \
	<fieldset class="nohide"> \
	<legend>Common options</legend> \
	<input type="hidden" name="uuid" id="uuid" /> \
	<label for="hostalias">Hostname alias</label> \
	<input type="text" name="hostalias" id="hostalias" class="reqrd" autocomplete="off" /><br> \
	<label for="instance" id="odbInstance">DB name</label> \
	<input type="text" name="instance" id="instance" class="reqrd" autocomplete="off" /> <br>\
	<div class="hostlist"><label for="hostname">Host <span class="hostorder"></span></label> \
	<input type="text" name="hostname" class="reqrd" title="" autocomplete="off" /></div> <br>\
	<label for="username" id="usernamelabel">User name</label> \
	<input type="text" name="username" id="username" class="reqrd" title="" autocomplete="nope" /><br> \
	<label for="password">Password</label> \
	<input type="password" name="password" id="password" style="width: 8em" title="" autocomplete="new-password" /><span class="showpass">Show</span><br> \
	<label for="port">Port</label> \
	<input type="number" value="5432" name="port" id="port" style="width: 5em" title="" autocomplete="off" /><br><br> \
	<input type="checkbox" class="ui-dform-checkbox" name="useWhitelist" id="useWhitelist"><label for="useWhitelist">Use Whitelist </label> \
	</fieldset> \
	<fieldset id="whitelistfs" style="display:none"> \
	<legend>Whitelist</legend> \
	<div id="multidblist"> \
	<div id="whitedb" class="dblistorder"> \
	<div class="dblist"><label for="whitedb">DB <span class="dborder"></span></label> \
	<input type="text" name="whitedb" title="" autocomplete="off" /><span class="appendwhitedb appendbutton far fa-plus-square"></span><br></div> \
	</div> \
	</fieldset> \
	<!-- Allow form submission with keyboard without duplicating the dialog button --> \
	<input type="submit" tabindex="-1" style="position:absolute; top:-1000px"> \
	</form> \
	</div>';
	$( hostDetailFormDiv ).dialog({
		height: 490,
		width: 420,
		modal: true,
		title: "Host configuration",
		buttons: {
			"Save host": {
				click: function() {
					var hostalias = $("#hostalias").val(),
					instance = $("#instance").val(),
					//services = $("#services").val(),
					type = "Standalone",
					hostname = $("input[name=hostname]").val(),
					username = $("#username").val(),
					port = $("#port").val(),
					dbs = $("input[name=whitedb]").map(function(){return $(this).val();}).get(),
					password = Base64.encode(uuencode($("#password").val())),
					use_whitelist = $("#useWhitelist").prop('checked'),
					created = null;
					if (hostAlias) {
						created = hostcfg.platforms[curPlatform].aliases[hostAlias].created;
						delete hostcfg.platforms[curPlatform].aliases[hostAlias];
					}
					hostcfg.platforms[curPlatform].aliases[hostalias] = {
						uuid: $("#uuid").val(),
						instance: instance,
						type: type,
						host: hostname,
						username: username,
						password: password,
						port: port,
						dbs: dbs,
						use_whitelist: use_whitelist
					};
					if (hostAlias) {
						hostcfg.platforms[curPlatform].aliases[hostalias].updated = TimeStamp();
						hostcfg.platforms[curPlatform].aliases[hostalias].created = created;
					} else {
						hostcfg.platforms[curPlatform].aliases[hostalias].created = TimeStamp();
					}

					if (type === "Standalone") {
					//	if ($("#firstDGhost").value != ""){
					//		var hosts = $("input[name=dghostname]").map(function(){return $(this).val();}).get();
					//		var	instances =$("input[name=dgCDBservice]").map(function(){return $(this).val();}).get();
					//		var i;
					//		var dgs = [];
					//		for (i = 0; i < hosts.length; i++) {
					//			var dg = {instance: [instances[i]], hosts: [hosts[i]]};
					//			dgs.push(dg);
					//		}
					//		hostcfg.platforms[curPlatform].aliases[hostalias].dataguard = dgs;
					//	}
						SaveHostsCfg(true);
					}
					$(this).dialog("close");
					$('#adminmenu a[data-abbr="hosts-' + $("#hosttable").data("platform") + '"]').trigger( "click" );
				},
				text: "Save host",
				class: 'savecontrol'
			},
			"Test connection": {
				create: function() {
					$(this).hide();
				},
				click: function() {
					var hostalias = $("#hostalias").val(),
					instance = $("#instance").val(),
					type = $("#dbtype").val(),
					hostname = $("#hostname").val(),
					username = $("#username").val(),
					port = $("#port").val(),
					password = Base64.encode(uuencode($("#password").val())),
					created = null;
					if (hostAlias) {
						created = hostcfg.platforms[curPlatform].aliases[hostAlias].created;
						delete hostcfg.platforms[curPlatform].aliases[hostAlias];
					}
					hostcfg.platforms[curPlatform].aliases[hostalias] = {
						uuid: $("#uuid").val(),
						instance: instance,
						type: type,
						host: hostname,
						username: username,
						password: password,
						port: port
					};
					if (hostAlias) {
						hostcfg.platforms[curPlatform].aliases[hostalias].updated = TimeStamp();
						hostcfg.platforms[curPlatform].aliases[hostalias].created = created;
					} else {
						hostcfg.platforms[curPlatform].aliases[hostalias].created = TimeStamp();
					}
					SaveHostsCfg(false);
					$(this).dialog("close");
					$('#adminmenu a[data-abbr="hosts-' + $("#hosttable").data("platform") + '"]').trigger( "click" );
					testConnection(hostalias, hostcfg.platforms[curPlatform].aliases[hostalias]);
				},
				text: "Save & Test connection",
				class: 'savecontrol'
			},
			Cancel: function() {
				$(this).dialog("close");
			}
		},
		create: function() {
			var curHost = {};
			var sshkeyel;
			var dbListRefresh = function() {
				$(".dblist").each(function( index ) {
					$(this).find(".dborder").text(index + 1);
					$(this).find(".appendwhitedb").hide();
				});
				$(".dblist").last().find(".appendwhitedb").show();

				$(".dblistorder").each(function( index ) {
					$(this).attr("id","Host-"+(index + 1));
				});
			};
			$("#menu-group").select2({
				tags: true,
				dropdownParent: $(this)
			});
			$("#menu-subgroup").select2({
				tags: true,
				dropdownParent: $(this)
			});
			$("button.savecontrol").button("disable");
			$("#hostalias").tooltipster({
				trigger: 'custom',
				position: 'right',
			});
			$("#dbtype").on("change", function(e) {
				if (e.target.value == "RAC") {
					$("#odbInstance").text("Service");
					$(".services, .servicelist").hide();
					$(".appendhost, .removehost, .hostlist").show();
					$('#firstService input[type=text]').removeClass('reqrd');
					$(".CDBservices").hide();
				} else {
					$("#odbInstance").text("DB name");
					$(".hostorder").empty();
					$(".hostlist").hide();
					$(".hostlist").first().show();
					$(".appendhost, .removehost").hide();
					$('#firstService input[type=text]').removeClass('reqrd');
					$(".services, .servicelist, .dgservicelist, .dgservices").hide();
					//$(".CDBservices").hide();
				}
			});
			$("#menu-group").on("change", function(e) {
				if (e.target.value == "") {
					$("#menu-subgroup").val("").trigger("change");
					$(".msubgrp").prop("disabled", true);
				} else {
					$(".msubgrp").prop("disabled", false);
				}
			});
			if (hostAlias) {
				curHost = hostcfg.platforms[curPlatform].aliases[hostAlias];
				$("#hostalias").val(hostAlias);
				$("#uuid").val(curHost.uuid);
				$("#instance").val(curHost.instance);
				$("#dbtype").val(curHost.type);
				$("input[name=hostname]").val(curHost.host);
				// $("#platform").val(curHost.platform);
				$("#username").val(curHost.username);
				$("#port").val(curHost.port);
				if (curHost.password === true) {
					$("#password").attr("placeholder", "Don't fill to keep current");
					$("#password").addClass("keepass");
				} else {
					$("#password").val(reveal(curHost.password));
				}
				validateHostCfg(curHost);
				$(".showpass").hide();

				$("#useWhitelist").prop('checked', curHost.use_whitelist);
				if ($("#useWhitelist").prop("checked")) {
					$("#whitelistfs").show();
				}

				$.each(curHost.dbs, function(i, value) {
					if (i == 0) {
						$("input[name=whitedb]").val(value);
					} else {
						var ni = '<div class="dblist"><label>DB <span class="dborder"></span></label><input type="text" name="whitedb" value="'+value+'" text="'+value+'"  title="" autocomplete="off" /><span class="appendwhitedb appendbutton far fa-plus-square"></span><span class="removewhitedb appendbutton far fa-minus-square"></span><br></div>';
						$("#multidblist").append(ni);
					}
				});
				dbListRefresh();

			} else {
				$("#dbtype").val("Standalone");
			}
			$("#dbtype").trigger("change");
			$(this).on("change", ".reqrd, .api, .ssh", function() {
				validateHostCfg(true);
			});

			$(".showpass").button().mousedown(function(e) {
				e.stopPropagation();
				$(this).prev().attr('type','text');
			}).mouseup(function(){
				$(this).prev().attr('type','password');
			}).mouseout(function(){
				$(this).prev().attr('type','password');
			});
			$("#password").on("keyup", function( event ) {
				if ($(this).val()) {
					$(".showpass").button("enable");
				} else {
					$(".showpass").button("disable");
				}
			});
			var dbListRefresh = function() {
				$(".dblist").each(function( index ) {
					$(this).find(".dborder").text(index + 1);
					$(this).find(".appendwhitedb").hide();
				});
				$(".dblist").last().find(".appendwhitedb").show();

				$(".dblistorder").each(function( index ) {
					$(this).attr("id","Host-"+(index + 1));
				});
			};
			$(this).on("click", ".appendwhitedb", function( event ) {
				event.stopPropagation();
				var type = $( "#dbtype option:selected" ).text();
				var ni = '<div class="dblist"><label>DB <span class="dborder"></span></label><input type="text" name="whitedb" class="reqrd" title="" autocomplete="off" /><span class="appendwhitedb appendbutton far fa-plus-square"></span><span class="removewhitedb appendbutton far fa-minus-square"></span><br></div>';
				$("#multidblist").append(ni);
				dbListRefresh();
				return false;
			});
			$(this).on("click", ".removewhitedb", function( event ) {
				event.stopPropagation();
				$(this).closest("div").remove();
				dbListRefresh();
				return false;
			});

			$("#hostalias").on("blur", function( event ) {
				if (!event.relatedTarget || event.relatedTarget && event.relatedTarget.textContent != "Cancel") {
					var regex = new RegExp("^[a-zA-Z0-9_\.\-]+$");
					if (! this.value) {
						$("#hostalias").tooltipster('content', 'Alias name is required').tooltipster('open');
						$(event.target).addClass( "ui-state-error" );
						$(event.target).trigger("focus");
						// validateHostCfg(curHost);
						$("button.savecontrol").button("disable");
					} else if (this.value != hostAlias && hostcfg.platforms[curPlatform].aliases[this.value]) {
						$("#hostalias").tooltipster('content', 'Host alias already exists!').tooltipster('open');
						$(event.target).addClass( "ui-state-error" );
						$(event.target).trigger("focus");
						// validateHostCfg(curHost);
						$("button.savecontrol").button("disable");
					} else if (! regex.test(this.value)) {
						$("#hostalias").tooltipster('content', 'Bad characters used in this field').tooltipster('open');
						$(event.target).addClass( "ui-state-error" );
						$(event.target).trigger("focus");
						// validateHostCfg(curHost);
						$("button.savecontrol").button("disable");
					} else {
						$("#hostalias").tooltipster("close");
						$(event.target).removeClass( "ui-state-error" );
						if (curHost.platform) {
							validateHostCfg(curHost);
						}
						// $("button.savecontrol").button("enable");
					}
				}
			});
			$("#useWhitelist").checkboxradio();
			$("#host-config-form").on("change", "#useWhitelist", function (ev) {
				if ($(ev.target).prop("checked")) {
					//$("#savetestbutton").button("disable");
					//$("#savetestbutton").button("enable");
					$("#host-config-form fieldset").show(200);
				} else {
					$("#host-config-form fieldset").each(function() {
						if (! $(this).hasClass("nohide")) {
							$(this).hide(200);
						}
					});
				}
			});
		},
		open: function() {
			$('.ui-widget-overlay').addClass('custom-overlay');
		},
		close: function() {
			$(this).find( "form" ).trigger('reset');
			$("#grpname").tooltipster("destroy");
			$(this).dialog("destroy");
		}
	});
}

function hostDetailFormDb2(hostAlias) {
	var hostDetailFormDiv = '<div id="host-config-form"> \
	<form autocomplete="off"> \
	<fieldset class="nohide"> \
	<legend>Common options</legend> \
	<input type="hidden" name="uuid" id="uuid" /> \
	<label for="hostalias">Hostname alias</label> \
	<input type="text" name="hostalias" id="hostalias" class="reqrd" autocomplete="off" /><br> \
	<label for="menu-group" id="mglabel">Menu group</label> \
	<select id="menu-group" name="menu-group"> \
	<option value="">--- select or create ---</option> \
	</select><br> \
	<label for="menu-subgroup" class="msubgrp" disabled>&#8627; subgroup</label> \
	<select id="menu-subgroup" name="menu-subgroup" class="msubgrp" disabled> \
	<option value="">--- select or create ---</option> \
	</select><br class="msubgrp"> \
	<label for="instance" id="odbInstance">DB name</label> \
	<input type="text" name="instance" id="instance" class="reqrd" autocomplete="off" /> <br>\
	<div class="hostlist"><label for="hostname">Host <span class="hostorder"></span></label> \
	<input type="text" name="hostname" class="reqrd" title="" autocomplete="off" /></div> <br>\
	<label for="username" id="usernamelabel">User name</label> \
	<input type="text" name="username" id="username" class="reqrd" title="" autocomplete="nope" /><br> \
	<label for="password">Password</label> \
	<input type="password" name="password" id="password" style="width: 8em" title="" autocomplete="new-password" /><span class="showpass">Show</span><br> \
	<label for="port">Port</label> \
	<input type="number" value="25010" name="port" id="port" style="width: 5em" title="" autocomplete="off" /><br><br> \
	<!-- Allow form submission with keyboard without duplicating the dialog button --> \
	<input type="submit" tabindex="-1" style="position:absolute; top:-1000px"> \
	</form> \
	</div>';
	$( hostDetailFormDiv ).dialog({
		height: 490,
		width: 420,
		modal: true,
		title: "Host configuration",
		buttons: {
			"Save host": {
				click: function() {
					var hostalias = $("#hostalias").val(),
					instance = $("#instance").val(),
					//services = $("#services").val(),
					type = "Standalone",
					hostname = $("input[name=hostname]").val(),
					username = $("#username").val(),
					port = $("#port").val(),
					password = Base64.encode(uuencode($("#password").val())),
					menu_group = $("#menu-group").val(),
					menu_subgroup = $("#menu-subgroup").val(),
					created = null;
					if (hostAlias) {
						created = hostcfg.platforms[curPlatform].aliases[hostAlias].created;
						delete hostcfg.platforms[curPlatform].aliases[hostAlias];
					}
					hostcfg.platforms[curPlatform].aliases[hostalias] = {
						uuid: $("#uuid").val(),
						instance: instance,
						type: type,
						host: hostname,
						username: username,
						password: password,
						menu_group: menu_group,
						menu_subgroup: menu_subgroup,
						port: port
					};
					if (hostAlias) {
						hostcfg.platforms[curPlatform].aliases[hostalias].updated = TimeStamp();
						hostcfg.platforms[curPlatform].aliases[hostalias].created = created;
					} else {
						hostcfg.platforms[curPlatform].aliases[hostalias].created = TimeStamp();
					}

					if (type === "Standalone") {
						SaveHostsCfg(true);
					}
					$(this).dialog("close");
					$('#adminmenu a[data-abbr="hosts-' + $("#hosttable").data("platform") + '"]').trigger( "click" );
				},
				text: "Save host",
				class: 'savecontrol'
			},
			"Test connection": {
				create: function() {
					$(this).hide();
				},
				click: function() {
					var hostalias = $("#hostalias").val(),
					instance = $("#instance").val(),
					type = $("#dbtype").val(),
					hostname = $("#hostname").val(),
					username = $("#username").val(),
					port = $("#port").val(),
					password = Base64.encode(uuencode($("#password").val())),
					created = null;
					if (hostAlias) {
						created = hostcfg.platforms[curPlatform].aliases[hostAlias].created;
						delete hostcfg.platforms[curPlatform].aliases[hostAlias];
					}
					hostcfg.platforms[curPlatform].aliases[hostalias] = {
						uuid: $("#uuid").val(),
						instance: instance,
						type: type,
						host: hostname,
						username: username,
						password: password,
						port: port
					};
					if (hostAlias) {
						hostcfg.platforms[curPlatform].aliases[hostalias].updated = TimeStamp();
						hostcfg.platforms[curPlatform].aliases[hostalias].created = created;
					} else {
						hostcfg.platforms[curPlatform].aliases[hostalias].created = TimeStamp();
					}
					SaveHostsCfg(false);
					$(this).dialog("close");
					$('#adminmenu a[data-abbr="hosts-' + $("#hosttable").data("platform") + '"]').trigger( "click" );
					testConnection(hostalias, hostcfg.platforms[curPlatform].aliases[hostalias]);
				},
				text: "Save & Test connection",
				class: 'savecontrol'
			},
			Cancel: function() {
				$(this).dialog("close");
			}
		},
		create: function() {
			var curHost = {};
			var sshkeyel;


            var getODBGroups = function() {
                var dbgroups = {groups: {}, subgroups: {}};
                $.each(hostcfg.platforms[curPlatform].aliases, function(i, host) {
                    if (host.menu_group) {
                        if ($.isEmptyObject(dbgroups.groups[host.menu_group])) {
                            dbgroups.groups[host.menu_group] = {};
                        }
                    }
                    if (host.menu_subgroup) {
                        if ($.isEmptyObject(dbgroups.subgroups[host.menu_subgroup])) {
                            dbgroups.subgroups[host.menu_subgroup] = {};
                        }
                    }
                });
                return dbgroups;
            }

			var ODBGroups = getODBGroups();
			$.each(Object.keys(ODBGroups.groups).sort(), function(key, val) {
				$("<option />", {text: val}).appendTo($("#menu-group"));
			});
			$.each(Object.keys(ODBGroups.subgroups).sort(), function(key, val) {
				$("<option />", {text: val}).appendTo($("#menu-subgroup"));
			});
			$("#menu-group").select2({
				tags: true,
				dropdownParent: $(this)
			});
			$("#menu-subgroup").select2({
				tags: true,
				dropdownParent: $(this)
			});
			$("#menu-group").on("change", function(e) {
				if (e.target.value == "") {
					$("#menu-subgroup").val("").trigger("change");
					$(".msubgrp").prop("disabled", true);
				} else {
					$(".msubgrp").prop("disabled", false);
				}
			});
			$("button.savecontrol").button("disable");
			$("#hostalias").tooltipster({
				trigger: 'custom',
				position: 'right',
			});
			if (hostAlias) {
				curHost = hostcfg.platforms[curPlatform].aliases[hostAlias];
				$("#hostalias").val(hostAlias);
				$("#uuid").val(curHost.uuid);
				$("#instance").val(curHost.instance);
				$("#dbtype").val(curHost.type);
				if (curHost.menu_group) {
					$("#menu-group").val(curHost.menu_group).trigger('change');
					$(".msubgrp").prop("disabled", false);
				}
				$("#menu-subgroup").val(curHost.menu_subgroup).trigger('change');
				$("input[name=hostname]").val(curHost.host);
				// $("#platform").val(curHost.platform);
				$("#username").val(curHost.username);
				$("#port").val(curHost.port);
				if (curHost.password === true) {
					$("#password").attr("placeholder", "Don't fill to keep current");
					$("#password").addClass("keepass");
				} else {
					$("#password").val(reveal(curHost.password));
				}
				validateHostCfg(curHost);
				$(".showpass").hide();

			} else {
				$("#dbtype").val("Standalone");
			}
			$("#dbtype").trigger("change");
			$(this).on("change", ".reqrd, .api, .ssh", function() {
				validateHostCfg(true);
			});

			$(".showpass").button().mousedown(function(e) {
				e.stopPropagation();
				$(this).prev().attr('type','text');
			}).mouseup(function(){
				$(this).prev().attr('type','password');
			}).mouseout(function(){
				$(this).prev().attr('type','password');
			});
			$("#password").on("keyup", function( event ) {
				if ($(this).val()) {
					$(".showpass").button("enable");
				} else {
					$(".showpass").button("disable");
				}
			});


			$("#hostalias").on("blur", function( event ) {
				if (!event.relatedTarget || event.relatedTarget && event.relatedTarget.textContent != "Cancel") {
					var regex = new RegExp("^[a-zA-Z0-9_\.\-]+$");
					if (! this.value) {
						$("#hostalias").tooltipster('content', 'Alias name is required').tooltipster('open');
						$(event.target).addClass( "ui-state-error" );
						$(event.target).trigger("focus");
						// validateHostCfg(curHost);
						$("button.savecontrol").button("disable");
					} else if (this.value != hostAlias && hostcfg.platforms[curPlatform].aliases[this.value]) {
						$("#hostalias").tooltipster('content', 'Host alias already exists!').tooltipster('open');
						$(event.target).addClass( "ui-state-error" );
						$(event.target).trigger("focus");
						// validateHostCfg(curHost);
						$("button.savecontrol").button("disable");
					} else if (! regex.test(this.value)) {
						$("#hostalias").tooltipster('content', 'Bad characters used in this field').tooltipster('open');
						$(event.target).addClass( "ui-state-error" );
						$(event.target).trigger("focus");
						// validateHostCfg(curHost);
						$("button.savecontrol").button("disable");
					} else {
						$("#hostalias").tooltipster("close");
						$(event.target).removeClass( "ui-state-error" );
						if (curHost.platform) {
							validateHostCfg(curHost);
						}
						// $("button.savecontrol").button("enable");
					}
				}
			});
		},
		open: function() {
			$('.ui-widget-overlay').addClass('custom-overlay');
		},
		close: function() {
			$(this).find( "form" ).trigger('reset');
			$("#grpname").tooltipster("destroy");
			$(this).dialog("destroy");
		}
	});
}

function validateHostCfg(curHost) {
	var valid = true,
	needapi = true,
	needssh = true;

	if ( $(".ui-state-error")[0] ) {
		valid = false;
	}
	if (curHost) {
		needapi = $("#authapi").prop('checked');
		needssh = $("#authssh").prop('checked');
	} else {
		needapi = hostcfg.platforms[curPlatform].api;
		needssh = hostcfg.platforms[curPlatform].ssh;
	}
	$("input.api, select.api").each(function( index ) {
		if (needapi) {
			if ( $( this ).val() == "" ) {
				if ( $(this).is(":visible") ) {
					if ( $(this).attr('type') == "password" ) {
						if ( ! $(this).hasClass('keepass') )  {
							valid = false;
						}
					} else {
						valid = false;
					}
				}
			}
		} else {
			// $( this ).prop('disabled', true);
		}
	});
	$("input.ssh, select.ssh").each(function( index ) {
		if (needssh) {
			if ( $( this ).val() == "" ) {
				if ( $(this).is(":visible") ) {
					if ( $(this).attr('type') == "password" ) {
						if ( ! $(this).hasClass('keepass') )  {
							valid = false;
						}
					} else {
						valid = false;
					}
				}
			}
		} else {
			// $( this ).prop('disabled', true);
		}
	});
	$("input.reqrd").each(function( index ) {
		if ( $(this).is(":visible") ) {
			if (! $( this ).val() ) {
				valid = false;
			}
		}
	});
	$("#authapi").prop('checked', needapi);
	$("#authssh").prop('checked', needssh);
	if (valid) {
		$("button.savecontrol").button("enable");
	} else {
		$("button.savecontrol").button("disable");
	}
	return valid;
}

function SaveHostsCfg(showResult, alias, hwtype, hostname, uuid) {
	$.each(hostcfg, function(rk, rv) {
		$.each(rv, function(ck, cv) {
			if (cv.aliases) {
			$.each(cv.aliases, function(ak, av) {
				if (! av.uuid ) {
					av.uuid = generateUUID();
				}
			});
			}
		});
	});
	var postdata = {cmd: "saveall", acl: JSON.stringify(hostcfg, null, 2), toremove: alias, hw_type: hwtype, hostname: hostname, uuid: uuid};
	$.post( "/lpar2rrd-cgi/hosts.sh", postdata, function( data ) {
		var returned = JSON.parse(data);
		if (showResult || returned.status == "fail") {
			$(returned.msg).dialog({
				dialogClass: "info",
				title: "Host configuration save - " + returned.status,
				minWidth: 600,
				modal: true,
				show: {
					effect: "fadeIn",
					duration: 500
				},
				hide: {
					effect: "fadeOut",
					duration: 200
				},
				buttons: {
					OK: function() {
						$(this).dialog("close");
					}
				}
			});
		}
		if (inXormon) {
			myreadyFunc();
		}
	});
}

function loadRegions(hAlias, hostParams) {
	hostParams.username = "" + hostParams.aws_access_key_id;
	hostParams.password = "" + hostParams.aws_secret_access_key;

	$.post('/lpar2rrd-cgi/hosts.sh', {
		cmd: "apitest",
		platform: curPlatform,
		host: hostParams.host,
		username: hostParams.username,
		password: hostParams.password,
		alias: hAlias,
		type: hostParams.type
	});
}

function loadNamespaces(hAlias, hostParams) {
	hostParams.username = hostParams.token.substring(0,24) + "...";
	hostParams.password = hostParams.token;
	hostParams.proto = hostParams.protocol;

	$.post('/lpar2rrd-cgi/hosts.sh', {
		cmd: "apitest",
		platform: curPlatform,
		host: hostParams.host,
		port: hostParams.api_port,
		proto: hostParams.proto,
		username: hostParams.username,
		password: hostParams.password,
		alias: hAlias,
		type: hostParams.type
	});
}

function testConnection(hAlias, hostParams) {
	var result = true,
	testCnt = 0,
	apilog = "",
	sshlog = "";
	if (!inXormon) {
		document.body.style.cursor = 'wait';
	}
	$("<div><div id='apilog'></div><div id='sshlog'></div></div>").dialog( {
		buttons: { "OK": function () { $(this).dialog("close"); } },
		close: function (event, ui) {
			document.body.style.cursor = 'default';
			$(this).remove();
		},
		open: function() {
			$('.ui-widget-overlay').addClass('custom-overlay');
		},
		resizable: false,
		position: { my: "top", at: "top+220", of: window },
		title: hAlias + ": host connection test",
		dialogClass: "no-close-dialog loading",
		minWidth: 800,
		modal: true
	});
	if (curPlatform == 'IBM Power CMC') {
		if (hostParams.instance) {
			hostParams.api_port = hostParams.port;
		}
		$.post('/lpar2rrd-cgi/hosts.sh', {cmd: "conntest", host: hostParams.host, port: hostParams.api_port,platform: curPlatform, alias: hAlias }, function(data) {
			apilog = "<br><b>CMC API connection:</b> ";
			//console.log(data);
			if (data.success) {
				//$("#apilog").append(data);
				//$("#apilog").append("<span class='noerr'>OK</span>");
				$("#apilog").html( apilog + data.error);
				document.body.style.cursor = 'default';
				$('.ui-dialog').removeClass('loading');

			} else {
				$("#apilog").append("<span class='error'>" + data.error + "</span>");
				$("#apilog").html( apilog + data.error);
				result = false;
				document.body.style.cursor = 'default';
				$('.ui-dialog').removeClass('loading');
			}
		}, "json");
	}
	if (hostParams.auth_api || hostParams.instance || curPlatform == 'RHV (oVirt)') {
		testCnt++;
		if (hostParams.instance) {
			hostParams.api_port = hostParams.port;
		}
		$.post('/lpar2rrd-cgi/hosts.sh', {cmd: "conntest", host: hostParams.host, port: hostParams.api_port,platform: curPlatform, alias: hAlias }, function(data) {
			apilog = (curPlatform == "RHV (oVirt)" || curPlatform == "OracleDB") ? "<br><b>DB host network connection:</b> " : "<br><b>API host network connection:</b> ";
			if (data.success) {
				$("#apilog").html( apilog + data.error);
				testCnt++;
				if (curPlatform == "AWS") {
					hostParams.username = "" + hostParams.aws_access_key_id;
					//hostParams.username = hostParams.aws_access_key_id;
					hostParams.password = ""+hostParams.aws_secret_access_key;
				}
				if (curPlatform == "Azure") {
					hostParams.username = hostParams.client;
				}
				if (curPlatform == "Cloudstack") {
					hostParams.proto = hostParams.protocol;
				}
				if (curPlatform == "Kubernetes" || curPlatform == "Openshift") {
				  hostParams.username = hostParams.token.substring(0,24) + "...";
				  hostParams.password = hostParams.token;
				  hostParams.proto = hostParams.protocol;
				}
				if (curPlatform == "Proxmox") {
				  hostParams.proto = hostParams.protocol;
				}
				if (curPlatform == "FusionCompute") {
				  hostParams.type = hostParams.usertype;
				  hostParams.instance = hostParams.version;
				}
				$.post('/lpar2rrd-cgi/hosts.sh', {
					cmd: "apitest",
					platform: curPlatform,
					host: hostParams.host,
					port: hostParams.api_port,
					proto: hostParams.proto,
					username: hostParams.username,
					password: hostParams.password,
					instance: hostParams.instance,
					alias: hAlias,
					type: hostParams.type
				}, function(data1) {
					testCnt--;
					$("#apilog").append((curPlatform == "RHV (oVirt)" || curPlatform == "OracleDB") ? "<br><b>DB data test:</b> " : "<br><b>API authorization</b> (" + hostParams.username + "): ");
					if (data1.success) {

						$("#apilog").append("<span class='noerr'>OK</span>");

						if (curPlatform == "VMware") {
							$("#apilog").append("<br><b>API data test:</b> ");
							testCnt++;
							$.post('/lpar2rrd-cgi/hosts.sh', {
								cmd: "vmwaredatatest",
								alias: hAlias,
								platform: curPlatform,
								host: hostParams.host,
								port: hostParams.api_port,
								proto: hostParams.proto,
								username: hostParams.username,
								password: hostParams.password
							}, function(data2) {
								testCnt--;
								if (data2.success) {
									$("#apilog").append("<span class='noerr'>OK</span>");
								} else {
									$("#apilog").append("<span class='error'>" + data2.error + "</span>");
									result = false;
								}
								if (testCnt < 1) {
									document.body.style.cursor = 'default';
									$('.ui-dialog').removeClass('loading');
								}
								$("#apilog").append("<br>");
							}, "json");

						} else if (curPlatform == "IBM Power Systems") {
							$("#apilog").append("<br><br><b>API data test</b><table id='pwrsrvtest'><tbody></tbody></table>");
							var $srvtable = $("#pwrsrvtest > tbody");
							testCnt++;
							$.post('/lpar2rrd-cgi/hosts.sh', {
								cmd: "powerserverlist",
								platform: curPlatform,
								hmc: hostParams.host,
							}, function(data2) {
								testCnt--;
								if (data2.length) {
									$.each(data2, function(i, val) {
										testCnt++;
										var tdid = "td_" + i;
										var tr = "<tr><td>" + val + "</td><td id='" + tdid + "'></td></tr>";
										$srvtable.append(tr);
										$("#" + tdid).html('<img src="css/images/sloading.gif" style="display: block;" />');
										$.ajax({
											url: '/lpar2rrd-cgi/hosts.sh',
											type: 'POST',
											dataType: "json",
											data: {
												cmd: "powerserversingletest",
												platform: curPlatform,
												hmc: hostParams.host,
												server: val
											},
											success: function(data3) {
												testCnt--;
												if (data3.success) {
													$("#" + tdid).html("<span class='noerr'>OK</span>");
												} else {
													$("#" + tdid).html("<span class='error'>" + data3.error + "</span>");
												}
												if (testCnt < 1) {
													document.body.style.cursor = 'default';
													$('.ui-dialog').removeClass('loading');
												}
											}
										});
									});
								} else {
									$("#apilog").append("no managed servers found<br>");
								}
								if (testCnt < 1) {
									document.body.style.cursor = 'default';
									$('.ui-dialog').removeClass('loading');
								}
							}, "json");
						} else if (curPlatform == "RHV (oVirt)" && hostParams.auth_api) {
							$("#apilog").append("<br><b>REST API host network test:</b> ");
							testCnt++;
							$.post('/lpar2rrd-cgi/hosts.sh', {cmd: "conntest", host: hostParams.api_hostname, port: hostParams.api_port2, platform: curPlatform, alias: hAlias }, function(data2) {
								testCnt--;
								if (data2.success) {
									$("#apilog").append(data2.error);
								} else {
									$("#apilog").append("<span class='error'>" + data2.error + "</span>");
									result = false;
								}
								if (testCnt < 1) {
									document.body.style.cursor = 'default';
									$('.ui-dialog').removeClass('loading');
								}
								$("#apilog").append("<br>");
							}, "json");
						}
					} else {
						$("#apilog").append("<span class='error'>" + data1.error + "</span>");
						document.body.style.cursor = 'default';
						$('.ui-dialog').removeClass('loading');
						result = false;
					}
					// $("#apilog").append("<br>");
					if (testCnt < 1) {
						document.body.style.cursor = 'default';
						$('.ui-dialog').removeClass('loading');
					}
				}, "json");
			} else {
				$("#apilog").append("<span class='error'>" + data.error + "</span>");
				result = false;
			}
			testCnt--;
			if (testCnt < 1) {
				document.body.style.cursor = 'default';
				$('.ui-dialog').removeClass('loading');
			}
		}, "json");
	}
	if (hostParams.auth_ssh) {
		testCnt++;
		$.post('/lpar2rrd-cgi/hosts.sh', {cmd: "conntest", host: hostParams.host, port: hostParams.ssh_port }, function(data) {
			sshlog = "<b>SSH network connection:</b> ";
			if (data.success) {
				sshlog += data.error;
				testCnt++;
				if (curPlatform == "IBM Power Systems") {
					$.post('/lpar2rrd-cgi/hosts.sh', {
						cmd: "sshdatatest",
						alias: hAlias,
						platform: curPlatform,
						host: hostParams.host,
						port: hostParams.ssh_port,
						username: hostParams.username,
						sshkey: hostParams.ssh_key_id
					}, function(data) {
						testCnt--;
						if (testCnt < 1) {
							document.body.style.cursor = 'default';
							$('.ui-dialog').removeClass('loading');
						}
						sshlog += "<br><b>SSH data test:</b> ";
						if (data.success) {
							sshlog += "<span>" + data.error + "</span>";
						} else {
							sshlog += "<span class='error'>" + data.error + "</span>";
							result = false;
						}
						$("#sshlog").html(sshlog + "<br>");
					}, "json");
				} else {
					$.post('/lpar2rrd-cgi/hosts.sh', {
						cmd: "sshtest",
						alias: hAlias,
						platform: curPlatform,
						host: hostParams.host,
						port: hostParams.ssh_port,
						username: hostParams.username,
						sshkey: hostParams.ssh_key_id
					}, function(data) {
						testCnt--;
						if (testCnt < 1) {
							document.body.style.cursor = 'default';
							$('.ui-dialog').removeClass('loading');
						}
						sshlog += "<br><b>SSH authorization:</b> ";
						if (data.success) {
							sshlog += "<span class='noerr'>OK</span>";
						} else {
							sshlog += "<span class='error'>" + data.error + "</span>";
							result = false;
						}
						$("#sshlog").html(sshlog + "<br>");
					}, "json");
				}
			} else {
				sshlog += "<span class='error'>" + data.error + "</span>";
				$("#sshlog").html(sshlog + "<br>");
				result = false;
			}
			testCnt--;
			if (testCnt < 1) {
				document.body.style.cursor = 'default';
				$('.ui-dialog').removeClass('loading');
			}
		}, "json");
	}
}

function about () {
	var aboutDiv = '<div id="about"> \
	<p style="text-align: center; outline: none;"><a href="https://lpar2rrd.com/" id="aboutlogo" style="outline: none; "target="_blank"><img src="css/images/logo-lpar2rrd.png" alt="LPAR2RRD HOME" border="0" style=""></a></p> \
	<table id="abouttable"> \
	</table> \
	</div>';
	$( aboutDiv ).dialog({
		height: 660,
		width: 450,
		modal: true,
		title: "About this tool",
		buttons: { "OK": function () { $(this).dialog("destroy"); } },
		create: function() {
			var postdata = {jsontype: "about"};
			$.getJSON(cgiPath + '/genjson.sh', postdata, function(data, status, jqXHR) {
				var header = jqXHR.getResponseHeader('server');
				if (! header) {
					header = "n/a";
				}
				var rows = "<tr><td>LPAR2RRD version</td><td>" + data.tool_version + "</td></tr>";
				rows += "<tr><td>LPAR2RRD edition</td><td>" + data.edition + "</td></tr>";
				rows += "<tr><td>OS info</td><td>" + data.os_info + "</td></tr>";
				rows += "<tr><td>Perl version</td><td>" + data.perl_version + "</td></tr>";
				rows += "<tr><td>Web server info</td><td>" + header + "</td></tr>";
				rows += "<tr><td>RRDTOOL version</td><td>" + data.rrdtool_version + "</td></tr>";
				rows += "<tr><td>SQLite version</td><td>" + data.sqlite_version + "</td></tr>";
				// rows += "<tr><td>RRDp version</td><td>" + data.RRDp_version + "</td></tr>";
				if (data.vmcount) {
					rows += "<tr><td colspan='2'></td></tr>";
					rows += "<tr><td style='border-top:0; font-weight: bold'>Total VMs</td><td style='border-top:0'>Get a quote via <a target='_blank' id='quote'>email</a></td></tr>";
					var body = "Hello sales, \n\n" +
								"(please fill in these fields): \n" +
								"Full Name: \n" +
								"Company name: \n" +
								"Company address: \n" +
								"Support length [1/2/3 years]: \n\n" +
								"Environment: \n\n";
					$.each(Object.keys(data.vmcount).sort(), function(key, val) {
						if (data.vmcount[val]) {
							rows += "<tr><td>" + val + "</td><td>" + data.vmcount[val] + "</td></tr>";
							body += val + ": " + data.vmcount[val] + "\n";
						}
					});
				}
				$( "#abouttable" ).html(rows);
				var qref = "mailto:sales@lpar2rrd.com?subject=LPAR2RRD%20quote%20request&body=";
				qref += encodeURIComponent(body);
				$( "#quote" ).prop("href", qref);
			});
		},
		open: function() {
			$('.ui-widget-overlay').addClass('custom-overlay');
		},
		close: function() {
			$(this).dialog("destroy");
		}
	});
}


function splitWithTail(str,delim,count){
	var parts = str.split(delim);
	var tail = parts.slice(count).join(delim);
	var result = parts.slice(0,count);
	result.push(tail);
	return result;
}

function img2pdf(){return list={},$("a.ui-tabs-anchor").length?$.each($("li.ui-state-default:visible a.ui-tabs-anchor"),function(a,t){name=this.text,tabimg=$(this.attributes.href.value+" img.lazy"),count=$(tabimg).length,imgarr=$(tabimg).map(function(){if(src=$(this).attr("data-src"),$(this).hasClass("nolegend")&&(src=src.replace("detail=0","detail=1")),!sysInfo.basename||$(this).hasClass("loaded"))return src}).get(),list[name]=imgarr}):(name="CPU",tabimg=$("#content img.lazy"),count=$(tabimg).length,imgarr=$(tabimg).map(function(){if(src=$(this).attr("data-src"),$(this).hasClass("nolegend")&&(src=src.replace("detail=0","detail=1")),!sysInfo.basename||$(this).hasClass("loaded"))return src}).get(),list[name]=imgarr),list}

function reveal(inString) {
	if (inString === true ) {
		return true;
	} else if (! inString ) {
		return "";
	}
	inString = Base64.decode(inString);
	var stop = false;
	var inIndex = 0;
	var outIndex = 0;
	var totalLen = 0;

	var inBytes = inString.split("");
	var buffLen = inBytes.length;
	var outBytes = new Array(buffLen);

	do {
		if (inIndex < buffLen) {
			var n = inBytes[inIndex].charCodeAt(0) - 32 & 0x3F;

			++inIndex;

			if (n > 45) {
				throw 'Invalid Data';
			}

			if (n < 45) {
				stop = true;
			}

			totalLen += n;

			while (n > 0) {
				decodeChars(inBytes, inIndex, outBytes, outIndex);
				outIndex += 3;
				inIndex += 4;
				n -= 3;
			}

			++inIndex;
		} else {
			stop = true;
		}
	} while (!stop);

	return outBytes.join("").trim();
}

function decodeChars(inBytes, inIndex, outBytes, outIndex) {
	var c1 = inBytes[inIndex].charCodeAt(0);
	var c2 = inBytes[inIndex + 1].charCodeAt(0);
	var c3 = inBytes[inIndex + 2].charCodeAt(0);
	var c4 = inBytes[inIndex + 3].charCodeAt(0);

	var b1 = (c1 - 32 & 0x3F) << 2 | (c2 - 32 & 0x3F) >> 4;
	var b2 = (c2 - 32 & 0x3F) << 4 | (c3 - 32 & 0x3F) >> 2;
	var b3 = (c3 - 32 & 0x3F) << 6 | c4 - 32 & 0x3F;

	outBytes[outIndex] = String.fromCharCode(b1 & 0xFF);
	if (b2 & 0xFF) {
		outBytes[outIndex + 1] = String.fromCharCode(b2 & 0xFF);
	}
	if (b3 & 0xFF) {
		outBytes[outIndex + 2] = String.fromCharCode(b3 & 0xFF);
	}
}
function uuencode(s) {
	// s = unescape(encodeURIComponent(s));
	var n = 0;
	var res = [];
	for (;;) {
		var len = s.length - n;
		if (len > 45) {
			len = 45;
		}
		res.push(uuenc(len));
		var s2 = s.substring(n, n + len);
		s2 += String.fromCharCode(0) + String.fromCharCode(0);
		for (var i = 0; i < len; i += 3) {
			res.push(uuenc(s2.charCodeAt(i) >> 2));
			res.push(uuenc(((s2.charCodeAt(i) & 3) << 4) + (s2.charCodeAt(i + 1) >> 4)));
			res.push(uuenc(((s2.charCodeAt(i + 1) & 15) << 2) + (s2.charCodeAt(i + 2) >> 6)));
			res.push(uuenc(s2.charCodeAt(i + 2) & 0x3f));
		}
		n += len;
		if (n == s.length) {
			break;
		}
		res.push("\n");
	}
	return res.join("");
}
function uuenc(c) {
	return c == 0 ? "`" : String.fromCharCode(0x20 + c);
}

/**
 * Sort object properties (only own properties will be sorted).
 * @param {object} obj object to sort properties
 * @param {string|int} sortedBy 1 - sort object properties by specific value.
 * @param {bool} isNumericSort true - sort object properties as numeric value, false - sort as string value.
 * @param {bool} reverse false - reverse sorting.
 * @returns {Array} array of items in [[key,value],[key,value],...] format.
 */
function sortProperties(obj, sortedBy, isNumericSort, reverse) {
	sortedBy = sortedBy || 1; // by default first key
	isNumericSort = isNumericSort || false; // by default text sort
	reverse = reverse || false; // by default no reverse

	var reversed = (reverse) ? -1 : 1;

	var sortable = [];
	for (var key in obj) {
		if (obj.hasOwnProperty(key)) {
			sortable.push([key, obj[key]]);
		}
	}
	if (isNumericSort) {
		sortable.sort(function (a, b) {
			return reversed * (a[1][sortedBy] - b[1][sortedBy]);
		});
	} else {
		sortable.sort(function (a, b) {
			var x = a[1][sortedBy].toLowerCase(),
			y = b[1][sortedBy].toLowerCase();
			return x < y ? reversed * -1 : x > y ? reversed : 0;
		});
		return sortable; // array in format [ [ key1, val1 ], [ key2, val2 ], ... ]
	}
}
function replaceUrlParam(url, paramName, paramValue){
	if (! url) {
		return "";
	}

	if (paramValue == null) {
		paramValue = '';
	}

	var pattern = new RegExp('\\b('+paramName+'=).*?(&|#|$)');
	if (url.search(pattern)>=0) {
		return url.replace(pattern,'$1' + paramValue + '$2');
	}

	url = url.replace(/[?#]$/,'');
	return url + (url.indexOf('?')>0 ? '&' : '?') + paramName + '=' + paramValue;
}

function download(filename, text) {

	if (navigator.msSaveBlob) { // IE 10+
		navigator.msSaveBlob(new Blob([text], { type: 'application/json;charset=utf-8;' }), filename);
	} else {
		var element = document.createElement('a');
		element.setAttribute('href', 'data:application/json;charset=utf-8,' + encodeURIComponent(text));
		element.setAttribute('download', filename);

		element.style.display = 'none';
		document.body.appendChild(element);
		element.click();
		document.body.removeChild(element);
	}
}

function showPrediction (predDiv) {
	var url = $(predDiv).data("src"),
		pWidth = $(predDiv).data("width") ? $(predDiv).data("width") : 1000,
		pHeight = $(predDiv).data("height") ? $(predDiv).data("height") : 300,
		pTitle = $(predDiv).data("title");
	$(predDiv).html("<div style='width: 100%; height: 100%; text-align: center'><img src='css/images/sloading.gif' style='margin-top: 100px'></div>");
	$.getJSON(url, function(data) {
		if (! jQuery.isEmptyObject(data)) {
			if (data.status) {
				// show status instead of graph
				$(predDiv).replaceWith("<div class='error_placeholder' style='width: " + pWidth + "px; height: 50px; text-align: center; border: 1px dotted red; overflow: hidden;'><p>" + data.status + "</p></div>");
			} else {
				var threshold1 = data.thresholds ? data.thresholds[0].value : null;
				/*
				if (! data.thresholds[1]) {
					data.thresholds.push({value: null, title : "" });
				}
				var threshold2 = data.thresholds ? data.thresholds[1].value : null;
				*/
				var series = {};
				series.xDate = [];
				series.yReal = [];
				series.yPred = [];
				series.thrs1 = [];
				//series.thrs2 = [];
				$.each(Object.keys(data.data.real).sort(), function(x, i) {
					series.xDate.push(Date.parse(i)/1000);
					series.yPred.push(null);
					series.yReal.push(data.data.real[i]);
					series.thrs1.push(threshold1);
					//series.thrs2.push(threshold2);
				});
				$.each(Object.keys(data.data.prediction).sort(), function(x, i) {
					series.xDate.push(Date.parse(i)/1000);
					series.yReal.push(null);
					series.yPred.push(parseFloat(data.data.prediction[i]));
					series.thrs1.push(threshold1);
					//series.thrs2.push(threshold2);
				});

				const fmtDate = uPlot.fmtDate("{YYYY}-{MM}-{DD}");
				// const tzDate = ts => uPlot.tzDate(new Date(ts * 1e3), "Etc/UTC");
				/*
				const tzDate = function (ts) {
					uPlot.tzDate(new Date(ts * 1e3), "Etc/UTC")
				}
				*/
				const opts = {
					title: pTitle,
					width: pWidth,
					height: pHeight,
					series: [
						{
							label: "date",
							value: function(u, ts) {
								return fmtDate(new Date(ts * 1e3));
							},
						},
						{
							label: "real",
							scale: "mb",
							// value: (u, v) => v == null ? "--" : v.toFixed(2),
							value: function(u, v) {
								return v == null ? "--" : v.toFixed(2);
							},
							stroke: "#1f77b4",
							width: 2,
							fill: "rgba(31, 119, 180, 0.5)",
							//spanGaps: true,
						},
						{
							label: "predicted",
							scale: "mb",
							// value: (u, v) => v == null ? "--" : v.toFixed(2),
							value: function(u, v) {
								return v == null ? "--" : v.toFixed(2);
							},
							stroke: "#ff7f0e",
							width: 2,
							fill: "rgba(255, 127, 14, 0.5)",
							//spanGaps: true,
						},
						{
							label: data.thresholds[0].title,
							scale: "mb",
							// value: (u, v) => v == null ? "-" : (v/1000000).toFixed(1) + "MB",
							stroke: "red",
							width: 1,
							//spanGaps: true,
						}
						/*
						{
							label: data.thresholds[1].title,
							scale: "mb",
							// value: (u, v) => v == null ? "-" : (v/1000000).toFixed(1) + "MB",
							// value: (u, v) => v == null ? "-" : niceBytes(v*1048576),
							stroke: "grey",
							width: 1,
							dash: [10, 5]
							//spanGaps: true,
						}
						*/
					],
					axes: [
						{
							font: "11px Arial",
							space: 60,
							values: [
								// tick incr          default           year                             month    day                        hour     min                sec       mode
								[3600 * 24 * 365,   "{YYYY}",         null,                            null,    null,                      null,    null,              null,        1],
								[3600 * 24 * 28,    "{MMM}",          "\n{YYYY}",                      null,    null,                      null,    null,              null,        1],
								[3600 * 24,         "{M}-{D}",        "\n{YYYY}",                      null,    null,                      null,    null,              null,        1],
								[3600,              "{h}{aa}",        "\n{M}-{D}-{YY}",                null,    "\n{M}-{D}",               null,    null,              null,        1],
								[60,                "{h}:{mm}{aa}",   "\n{M}-{D}-{YY}",                null,    "\n{M}-{D}",               null,    null,              null,        1],
								[1,                 ":{ss}",          "\n{M}-{D}-{YY} {h}:{mm}{aa}",   null,    "\n{M}-{D} {h}:{mm}{aa}",  null,    "\n{h}:{mm}{aa}",  null,        1],
								[0.001,             ":{ss}.{fff}",    "\n{M}-{D}-{YY} {h}:{mm}{aa}",   null,    "\n{M}-{D} {h}:{mm}{aa}",  null,    "\n{h}:{mm}{aa}",  null,        1],
							]
						},
						{
							side: 3,
							scale: 'mb',
							// values: (u, vals, space) => vals.map(v => niceBytes(v*1048576, false)),
							size: 60,
							gap: 4,
							font: "11px Arial",
							grid: {show: true},
						}
					]
				};

				$(predDiv).empty().css('width', 'auto').css('height', 'auto');
				var u = new uPlot(opts, [series.xDate, series.yReal, series.yPred, series.thrs1, series.thrs2], predDiv);
			}
		}
	});
}

const capUnits = ['bytes', 'KB', 'MB', 'GB', 'TB', 'PB', 'EB', 'ZB', 'YB'];

function niceBytes(x, integer) {

	var l = 0, n = parseInt(x, 10) || 0;

	while(n >= 1024 && ++l) {
		n = n/1024;
	}
	if (integer) {
		return(n.toFixed(0) + ' ' + capUnits[l]);
	} else {
		return(n.toFixed(n < 100 && l > 0 ? 1 : 0) + ' ' + capUnits[l]);
	}
}

const freqUnits = ['Hz', 'kHz', 'MHz', 'GHz'];

function generateUUID() {            // Public Domain/MIT
	var d = new Date().getTime();    // Timestamp
	var d2 = (performance && performance.now && (performance.now()*1000)) || 0;  // Time in microseconds since page-load or 0 if unsupported
	return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
		var r = Math.random() * 16;  // random number between 0 and 16
		if(d > 0) {                  // Use timestamp until depleted
			r = (d + r)%16 | 0;
			d = Math.floor(d/16);
		} else {                     // Use microseconds since page-load if supported
			r = (d2 + r)%16 | 0;
			d2 = Math.floor(d2/16);
		}
		return (c === 'x' ? r : (r & 0x3 | 0x8)).toString(16);
	});
}

/**
 * Overflow Tabs v1.10
 * Extends jQuery UI Tabs.
 *
 * This plugin will automatically detect the available space in a tabs container
 * and then determine if all of the tabs will fit, any tab that cannot fit in the
 * container on a single row will be grouped together in an 'overflow' drop down.
 *
 * The tabs are automatically updated when the page resizes and can be updated manually
 * by running:
 *
 * 			$("#tabs").tabs("refresh");
 *
 * Initialising the overflow tabs can be done by simply adding an extra option
 * when loading the jQuery ui tabs:
 *
 * 			var tabs = $('#tabs').tabs({
 * 				overflowTabs: true
 * 			});
 *
 * Released under the MIT license:
 *   http://www.opensource.org/licenses/mit-license.php
 */
$.widget("ui.tabs", $.ui.tabs, {
	options: {
		overflowTabs: false,
		tabPadding: 25,
		containerPadding: 0,
		dropdownSize: 50,
		hasButtons: false
	},

	_create: function() {
		this._super("_create");
		this.tabsWidth = 0;
		this.containerWidth = 0;

		if (!this.options.overflowTabs) {
			return;
		}

		// update the tabs
		this.updateOverflowTabs();

		// Detect a window resize and check the tabs again
		var that = this;
		$(window).resize(function() {
			// Add a slight delay after resize, to fix Maximise issue.
			setTimeout(function() {
				that.updateOverflowTabs();
			}, 150);
		});

		// Detect dropdown click
		$(this.element).on('click', '.overflow-selector', function() {
			that.toggleList();
		});
	},

	refresh: function() {
		this._super("refresh");
		this.updateOverflowTabs();
	},

	visible: function(tab, after) {
		if (after === undefined) {
			$(this.element).find('ul:first').prepend($(tab));
		} else {
			$(this.element).find('.last-fixed-tab:first').after($(tab));
		}

		this.toggleList();
	},

	toggleList: function() {
		if ($(this.element).find('.ui-tabs-overflow:first').hasClass('hide')) {
			$(this.element).find('.ui-tabs-overflow:first').removeClass('hide');
		} else {
			$(this.element).find('.ui-tabs-overflow:first').addClass('hide');
		}
	},

	updateOverflowTabs: function() {
		var failsafe = 0;
		this._calculateWidths();

		// Loop until tabsWidth is less than the containerWidth
		while (this.tabsWidth > this.containerWidth && failsafe < 30)
		{
			this._hideTab();
			this._calculateWidths();
			failsafe++;
		}

		// Finish now if there are no tabs in the overflow list
		if ($(this.element).find('.ui-tabs-overflow:first li').length == 0) {
			return;
		}

		// Reset
		failsafe = 0;

		// Get the first tab in the overflow list
		var next = this._nextTab();

		// Loop until we cannot fit any more tabs
		while (next.totalSize < this.containerWidth && $(this.element).find('.ui-tabs-overflow:first li').length > 0 && failsafe < 30)
		{
			next.tab.appendTo($(this.element).find('.ui-tabs-nav:first'));
			this._calculateWidths();

			next = this._nextTab();

			failsafe++;
		}

		// Check to see if overflow list is now empty
		if ($(this.element).find('.ui-tabs-overflow:first li').length == 0)
		{
			$(this.element).find('.ui-tabs-overflow:first').remove();
			$(this.element).find('.overflow-selector:first').remove();
		}
		var last_visible_tab = $(this.element).find('.ui-tabs-nav li:last');
		var tabs_offset = $(".ui-tabs .ui-tabs-nav").offset();
		if ( tabs_offset && tabs_offset.left >= 0 && last_visible_tab.length && last_visible_tab.position().left >= 0 ) {
			var tabs_end = tabs_offset.left + last_visible_tab.position().left + last_visible_tab.outerWidth();
			$("div.overflow-selector").css("left", tabs_end + 2);
			$("ul.ui-tabs-overflow").css("left", tabs_end - tabs_offset.left - 136);
		}
	},

	_calculateWidths: function() {
		var width = 0;
		var buttons = this.options.hasButtons;

		$(this.element).find('.ui-tabs-nav:first > li').each(function(){
			width += $(this).outerWidth(true) + (buttons ? 10 : 0);
		});

		this.tabsWidth = width;
		this.containerWidth = $(this.element).parent().width() - this.options.containerPadding - this.options.dropdownSize;

		$(this.element).find('.overflow-selector:first .total').html($(this.element).find('.ui-tabs-overflow:first li').length);
	},

	_hideTab: function() {
		if (!$(this.element).find('.ui-tabs-overflow').length)
		{
			$(this.element).find('.ui-tabs-nav:first').after('<ul class="ui-tabs-overflow hide"></ul>');
			$(this.element).find('.ui-tabs-overflow:first').after('<div class="overflow-selector">&#8595 <span class="total">0</span></div>');
		}

		var lastTab = $(this.element).find('.ui-tabs-nav:first li').last();
		lastTab.prependTo($(this.element).find('.ui-tabs-overflow:first'));
	},

	_nextTab: function() {
		var result = {};
		var firstTab = $(this.element).find('.ui-tabs-overflow:first li').first();

		result.tab = firstTab;
		result.totalSize = this.tabsWidth + this._textWidth(firstTab) + this.options.tabPadding;

		return result;
	},

	_textWidth: function(element) {
		var self = $(element),
			children = self.children(),
			calculator = $('<span style="display: inline-block;" />'),
			width;

		children.wrap(calculator);
		width = children.parent().width();
		children.unwrap();

		return width;
	}
});

function CheckDeviceCfg(devcfg) {
	if (sysInfo.free.indexOf('p') == -1) {
		var cntr = 0;
		$.each(Object.keys(devcfg.platforms['IBM Power Systems']['aliases']).sort(), function(x, i) {
			var val = devcfg.platforms['IBM Power Systems']['aliases'][i];
			cntr++;
			val[atob('dW5saWNlbnNlZA')] = (cntr > 4);
		});
		cntr = 0;
		if (devcfg.platforms['IBM Power CMC']) {
			$.each(Object.keys(devcfg.platforms['IBM Power CMC']['aliases']).sort(), function(x, i) {
				var val = devcfg.platforms['IBM Power CMC']['aliases'][i];
				cntr++;
				val[atob('dW5saWNlbnNlZA')] = (cntr > 1);
			});
		}

	}
}

// vim: set ts=4 sw=4 tw=0 noet :

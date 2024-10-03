CREATE TABLE IF NOT EXISTS "config" (
      "db_version" text PRIMARY KEY NOT NULL,
      "timestamp" DATETIME DEFAULT CURRENT_TIMESTAMP
    );
INSERT OR REPLACE INTO "config" ("db_version") VALUES ('1.01');
CREATE TABLE IF NOT EXISTS "classes" (
      "class" text PRIMARY KEY NOT NULL,
      "label" text NOT NULL,
      "class_order" integer
);
INSERT OR REPLACE INTO "classes" ("class", "label", "class_order") VALUES ('SERVER', 'Server', 1);
INSERT OR REPLACE INTO "classes" ("class", "label", "class_order") VALUES ('DB', 'Database', 2);
INSERT OR REPLACE INTO "classes" ("class", "label", "class_order") VALUES ('CLOUD', 'Cloud', 3);
INSERT OR REPLACE INTO "classes" ("class", "label", "class_order") VALUES ('CONTAINER', 'Container', 4);

CREATE TABLE IF NOT EXISTS "hw_types" (
      "hw_type" text PRIMARY KEY NOT NULL,
      "label" text NOT NULL,
      "class" text DEFAULT 'SERVER',
      "hw_type_order" integer,
      FOREIGN KEY ("class") REFERENCES "classes" ("class")
);

INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order") VALUES ('POWER', 'IBM Power Systems', 1);
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order") VALUES ('VMWARE', 'VMware', 2);
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order") VALUES ('NUTANIX', 'Nutanix', 3);
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order") VALUES ('PROXMOX', 'Proxmox', 4);
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order") VALUES ('OVIRT', 'oVirt', 5);
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order") VALUES ('XENSERVER', 'XenServer', 6);
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order") VALUES ('WINDOWS', 'Windows / Hyper-V', 7);
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order") VALUES ('SOLARIS', 'Solaris', 8);
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order") VALUES ('ORACLEVM', 'OracleVM', 9);
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order", "class") VALUES ('ORACLEDB', 'OracleDB', 10, 'DB');
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order", "class") VALUES ('POSTGRES', 'PostgreSQL', 11, 'DB');
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order", "class") VALUES ('AWS', 'Amazon Web Services', 12, 'CLOUD');
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order", "class") VALUES ('GCLOUD', 'Google Cloud', 13, 'CLOUD');
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order", "class") VALUES ('AZURE', 'Microsoft Azure', 14, 'CLOUD');
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order", "class") VALUES ('KUBERNETES', 'Kubernetes', 15, 'CONTAINER');
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order", "class") VALUES ('OPENSHIFT', 'Red Hat OpenShift', 16, 'CONTAINER');
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order", "class") VALUES ('CLOUDSTACK', 'Apache CloudStack', 17, 'CLOUD');
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order") VALUES ('LINUX', 'Linux', 18);
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order", "class") VALUES ('SQLSERVER', 'SQLServer', 19, 'DB');
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order") VALUES ('FUSIONCOMPUTE', 'FusionCompute', 20);
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order", "class") VALUES ('DOCKER', 'Docker', 21, 'CONTAINER');
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order", "class") VALUES ('DB2', 'IBM Db2', 22, 'DB');

CREATE TABLE IF NOT EXISTS "subsystems" (
      "hw_type" text NOT NULL,
      "subsystem" text NOT NULL,
      "label" text,
      "subsystem_order" integer,
      "subsystem_parent" integer,
      "menu_items" text CHECK ( menu_items IN ('folders','items','folder_folders','folder_items') )
                        NOT NULL DEFAULT 'folders',
      "inherit_acl_from" integer DEFAULT NULL,
      "recursive_folder" integer NOT NULL DEFAULT 0,
      "item_subsystem" integer DEFAULT NULL,
      "agent" integer NOT NULL DEFAULT 0,
      PRIMARY KEY ("hw_type", "subsystem"),
      FOREIGN KEY ("hw_type") REFERENCES "hw_types" ("hw_type") ON DELETE NO ACTION ON UPDATE NO ACTION
);

INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('XENSERVER', 'POOL', NULL, 1, NULL, 'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('XENSERVER', 'HOST', NULL, 2, 1, 'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('XENSERVER', 'VM', 'VM', 3, 1, 'folder_items');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('XENSERVER', 'STORAGE', NULL, 4, 2, 'folder_items');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('XENSERVER', 'LAN', 'LAN', 5, 2, 'folder_items');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('XENSERVER', 'VOLUME', NULL, NULL, NULL, 'folder_items');

INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('OVIRT', 'DATACENTER', NULL, 1, NULL, 'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('OVIRT', 'CLUSTER', NULL, 2, 1, 'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('OVIRT', 'HOST', NULL, 3, 2, 'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('OVIRT', 'VM', 'VM', 4, 2, 'folder_items');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('OVIRT', 'HOST_NIC', 'LAN', 5, 3, 'folder_items');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('OVIRT', 'VM_NIC', NULL, 6, NULL, 'folder_items');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('OVIRT', 'STORAGE_DOMAIN', 'Storage domain', 7, 1, 'folder_folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('OVIRT', 'DISK', NULL, 8, 7, 'items');

INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('POWER', 'CMC', 'CMC', 1, NULL, 'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('POWER', 'CMCCONSOLE', NULL, 2, 1, 'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('POWER', 'CMCPOOL', 'Pool', 3, 2, 'folder_items');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('POWER', 'CMCSERVER', 'Server', 4, 2, 'folder_items');

INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items", "inherit_acl_from") VALUES ('POWER', 'HMC', 'HMC Totals', 5, NULL, 'folder_items', 0);
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('POWER', 'SERVER', 'Server', 6, NULL, 'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('POWER', 'VM' , 'LPAR', 7, 6, 'folder_items');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('POWER', 'POOL', 'Shared Pool', 8, 6, 'folder_items');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('POWER', 'HEA', 'HEA', 9, 6, 'folder_items');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('POWER', 'LAN', 'LAN', 10, 6, 'folder_items');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('POWER', 'SAN', 'SAN', 11, 6, 'folder_items');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('POWER', 'SAS', 'SAS', 12, 6, 'folder_items');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('POWER', 'SRI', 'SR-IOV', 13, 6, 'folder_items');

INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('VMWARE', 'VCENTER', NULL, 1, NULL, 'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('VMWARE', 'CLUSTER', NULL, 2, 1, 'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('VMWARE', 'RESOURCEPOOL', 'Resource Pool', 3, 2, 'folder_items');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items", "inherit_acl_from") VALUES ('VMWARE', 'ESXI', 'ESXi', 4, 2, 'folder_folders', 1);
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('VMWARE', 'VM', 'VM', 5, 2, 'folder_items');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('VMWARE', 'DATACENTER', NULL, 6, 1, 'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('VMWARE', 'DATASTORE', NULL, 7, 6, 'items');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items", "recursive_folder", "item_subsystem") VALUES ('VMWARE', 'RESOURCEPOOL_FOLDER', NULL, 8, 3, 'folders', 1, 3);
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items", "recursive_folder", "item_subsystem") VALUES ('VMWARE', 'VM_FOLDER', NULL, 9, 5, 'folders', 1, 5);
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items", "recursive_folder", "item_subsystem") VALUES ('VMWARE', 'DATASTORE_FOLDER', NULL, 10, 6, 'folders', 1, 7);


INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items", "agent") VALUES ('LINUX', 'SERVER', NULL, 1, NULL, 'items', 1);

INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('WINDOWS', 'DOMAIN', NULL, 1, NULL, 'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('WINDOWS', 'SERVER', NULL, 2, 1, 'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('WINDOWS', 'VM', 'VM', 3, 2, 'folder_items');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('WINDOWS', 'STORAGE', NULL, 4, 2, 'folder_items');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('WINDOWS', 'WINDOWS_CLUSTER', NULL, 5, NULL, 'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('WINDOWS', 'CLUSTER_VM', 'VM', 6, 5, 'folder_items');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('WINDOWS', 'S2D_VOLUME', 'VOLUMES', 7, 5, 'folder_items');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('WINDOWS', 'S2D_PD', 'DRIVES', 8, 5, 'folder_items');

INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('NUTANIX', 'POOL', NULL, 1, NULL, 'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('NUTANIX', 'HOST', 'Servers', 2, 1, 'folder_items');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('NUTANIX', 'VM', 'VM', 3, 1, 'folder_items');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('NUTANIX', 'STORAGE', 'Storage', 4, 1, 'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('NUTANIX', 'STORAGE_POOL', 'Storage Pools', 5, 4, 'folder_items');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('NUTANIX', 'STORAGE_CONTAINER', 'Storage Containers', 6, 4, 'folder_items');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('NUTANIX', 'VIRTUAL_DISK', 'Virtual disks', 7, 4, 'folder_items');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('NUTANIX', 'PHYSICAL_DISK', 'Physical disks', 8, 4, 'folder_items');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('NUTANIX', 'VOLUME_GROUP', 'Volume groups', 9, 4, 'folder_items');

INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('KUBERNETES', 'CLUSTER', NULL, 1, NULL, 'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('KUBERNETES', 'NODE', 'Nodes', 2, 1, 'folder_items');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('KUBERNETES', 'PODS', 'Pods', 3, 1, 'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('KUBERNETES', 'POD', NULL, 4, 7, 'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('KUBERNETES', 'CONTAINER', 'Containers', 5, 4, 'folder_items');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('KUBERNETES', 'NAMESPACES', 'Namespaces', 6, 1, 'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('KUBERNETES', 'NAMESPACE', NULL, 7, 6, 'folders');


INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('OPENSHIFT', 'CLUSTER', NULL, 1, NULL, 'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('OPENSHIFT', 'NODE', 'Nodes', 2, 1, 'folder_items');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('OPENSHIFT', 'PROJECTS', 'Projects', 3, 1, 'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('OPENSHIFT', 'PROJECT', NULL, 4, 3, 'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('OPENSHIFT', 'POD', NULL, 5, 4, 'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('OPENSHIFT', 'CONTAINER', 'Containers', 6, 5, 'folder_items');

INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('CLOUDSTACK', 'CLOUD', NULL, 1, NULL, 'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('CLOUDSTACK', 'HOST', 'Host', 2, 1, 'folder_items');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('CLOUDSTACK', 'INSTANCE', 'Instance', 3, 1, 'folder_items');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('CLOUDSTACK', 'VOLUME', 'Volume', 4, 1, 'folder_items');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('CLOUDSTACK', 'PRIMARY_STORAGE', 'Primary Storage', 5, 1, 'folder_items');

INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('PROXMOX', 'CLUSTER', NULL, 1, NULL, 'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('PROXMOX', 'NODE', 'Node', 2, 1, 'folder_items');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('PROXMOX', 'VM', 'VM', 3, 1, 'folder_items');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('PROXMOX', 'LXC', 'LXC', 4, 1, 'folder_items');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('PROXMOX', 'STORAGE', 'Storage', 5, 1, 'folder_items');

INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('AWS', 'REGION', NULL, 1, NULL, 'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('AWS', 'EC2', 'Elastic Compute Cloud', 2, 1, 'folder_items');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('AWS', 'EBS', 'Elastic Block Store', 3, 1, 'folder_items');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('AWS', 'API', 'API Gateway', 4, 1, 'folder_items');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('AWS', 'LAMBDA', 'Lambda', 5, 1, 'folder_items');

INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('GCLOUD', 'REGION', NULL, 1, NULL, 'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('GCLOUD', 'COMPUTE', 'Compute Engine', 2, 1, 'folder_items');

INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('AZURE', 'LOCATION', NULL, 1, NULL, 'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('AZURE', 'VM', 'VM', 2, 1, 'folder_items');

INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('ORACLEDB', 'HOSTS', 'Hosts', 1, NULL, 'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('ORACLEDB', 'ITEMS', "Items", 2, 1, 'folder_items');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('ORACLEDB', 'STANDALONE_FOLDERS', 'Standalone', 3, NULL, 'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('ORACLEDB', 'STANDALONE', "label", 4, 15, 'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('ORACLEDB', 'RAC_FOLDERS', 'RAC', 5, NULL, 'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('ORACLEDB', 'RAC', NULL, 6, 15, 'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('ORACLEDB', 'GLOBAL_CACHE', 'Global Cache', 7, 6, 'folder_items');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('ORACLEDB', 'TOTAL', 'Total', 8, 6, 'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('ORACLEDB', 'INSTANCES_FOLDERS', 'Instances', 9, 15, 'folder_folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('ORACLEDB', 'INSTANCE', "Instances", 10, 6, 'folder_folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('ORACLEDB', 'MULTITENANT_FOLDERS', 'Multitenant', 11, NULL, 'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('ORACLEDB', 'MULTITENANT', NULL, 12, 15, 'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('ORACLEDB', 'PDB_FOLDERS', 'PDBs', 13, 12, 'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('ORACLEDB', 'PDBS', "PDBs", 14, 12, 'folder_folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('ORACLEDB', 'ODB_FOLDER', NULL, 15, NULL, 'folders');

INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('ORACLEVM', 'MANAGER'   , NULL,       1, NULL ,'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('ORACLEVM', 'SERVERPOOL', NULL,       2, 1    ,'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('ORACLEVM', 'SERVER'    , 'Server',   3, 2    ,'folder_items');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('ORACLEVM', 'VM'        , 'VM',       4, 2    ,'folder_items');

INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items", "inherit_acl_from") VALUES ('SOLARIS', 'SOLARIS_TOTAL', NULL, 1, NULL, 'folders', 0);
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('SOLARIS', 'CDOM'               , NULL,       2, NULL ,'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('SOLARIS', 'LDOM'               , NULL,       3, 2    ,'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('SOLARIS', 'ZONE_C'             ,'ZONE',      4, 2    ,'folder_items');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('SOLARIS', 'ZONE_L'             ,'ZONE',      5, 3    ,'folder_items');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('SOLARIS', 'STANDALONE_LDOM'    , NULL,       6, NULL ,'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('SOLARIS', 'STANDALONE_ZONE_L10'  ,'ZONE',    7, 6    ,'folder_items');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('SOLARIS', 'STANDALONE_ZONE_L11'  ,'ZONE',    8, 6    ,'folder_items');

INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('POSTGRES', 'HOST', 'Host', 1, NULL, 'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('POSTGRES', 'DB_FOLDERS', 'DBs', 2, 1, 'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('POSTGRES', 'DB', "label", 3, 2, 'folders');

INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('SQLSERVER', 'HOST', 'Host', 1, NULL, 'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('SQLSERVER', 'DB_FOLDERS', 'DBs', 2, 1, 'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('SQLSERVER', 'DB', "label", 3, 2, 'folders');

INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('FUSIONCOMPUTE', 'SITE', NULL, 1, NULL, 'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('FUSIONCOMPUTE', 'CLUSTERS', 'Clusters', 2, 1, 'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('FUSIONCOMPUTE', 'DATASTORE', 'Datastore', 3, 1, 'folder_items');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('FUSIONCOMPUTE', 'CLUSTER', NULL, 4, 2, 'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('FUSIONCOMPUTE', 'HOST', 'Host', 5, 4, 'folder_items');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('FUSIONCOMPUTE', 'VM', 'VM', 6, 4, 'folder_items');

INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('DOCKER', 'HOST', NULL, 1, NULL, 'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('DOCKER', 'CONTAINER', 'Containers', 2, 1, 'folder_items');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('DOCKER', 'VOLUME', 'Volumes', 3, 1, 'folder_items');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('DB2', 'HOST', 'Host', 1, NULL, 'folders');

INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('DB2', 'DB_FOLDERS', 'Members', 2, 1, 'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('DB2', 'DB', "label", 3, 2, 'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('DB2', 'BUFFERPOOL', "Buffer pools", 4, 1, 'folder_items');


CREATE TABLE IF NOT EXISTS "totals" (
  "hw_type" text NOT NULL,
  "subsystem" text NOT NULL,
  "href" text NOT NULL,
  "label" text NOT NULL,
  "total_order" integer NULL,
  FOREIGN KEY ("hw_type", "subsystem") REFERENCES "subsystems" ("hw_type", "subsystem") ON DELETE NO ACTION ON UPDATE NO ACTION
);

CREATE TABLE IF NOT EXISTS "properties" (
      "property_name" text PRIMARY KEY NOT NULL
);
CREATE TABLE IF NOT EXISTS "objects" (
      "object_id" text PRIMARY KEY NOT NULL,
      "label" text NOT NULL,
      "hw_type" text,
      "object_timestamp" DATETIME DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY ("hw_type") REFERENCES "hw_types" ("hw_type") ON DELETE CASCADE ON UPDATE NO ACTION
    );
CREATE TABLE IF NOT EXISTS "object_items" (
      "item_id" text PRIMARY KEY NOT NULL,
      "label" text,
      "object_id" text NOT NULL,
      "hw_type" text,
      "subsystem" text NOT NULL,
      "item_timestamp" DATETIME DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY ("hw_type", "subsystem") REFERENCES "subsystems" ("hw_type", "subsystem") ON DELETE CASCADE ON UPDATE NO ACTION,
      FOREIGN KEY ("object_id") REFERENCES "objects" ("object_id") ON DELETE CASCADE ON UPDATE NO ACTION
    );
CREATE TABLE IF NOT EXISTS "item_properties" (
      "item_id" text NOT NULL,
      "property_name" text NOT NULL,
      "property_value" text,
      PRIMARY KEY ("item_id", "property_name"),
      FOREIGN KEY ("item_id") REFERENCES "object_items" ("item_id") ON DELETE CASCADE ON UPDATE NO ACTION,
      FOREIGN KEY ("property_name") REFERENCES "properties" ("property_name") ON DELETE CASCADE ON UPDATE NO ACTION
);
CREATE TABLE IF NOT EXISTS "item_relations" (
      "parent" text NOT NULL,
      "child" text NOT NULL,
      PRIMARY KEY ("parent", "child"),
      FOREIGN KEY ("parent") REFERENCES "object_items" ("item_id") ON DELETE CASCADE ON UPDATE NO ACTION,
      FOREIGN KEY ("child") REFERENCES "object_items" ("item_id") ON DELETE CASCADE ON UPDATE NO ACTION
);
CREATE TABLE IF NOT EXISTS "agent_relations" (
      "agent_id" text NOT NULL,
      "item_id" text NOT NULL,
      "relation_timestamp" DATETIME DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY ("agent_id", "item_id"),
      FOREIGN KEY ("item_id") REFERENCES "object_items" ("item_id") ON DELETE CASCADE ON UPDATE NO ACTION
);
CREATE TABLE IF NOT EXISTS "hostcfg_relations" (
      "hostcfg_id" text NOT NULL,
      "item_id" text NOT NULL,
      PRIMARY KEY ("hostcfg_id", "item_id"),
      FOREIGN KEY ("item_id") REFERENCES "object_items" ("item_id") ON DELETE CASCADE ON UPDATE NO ACTION
);

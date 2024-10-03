.timeout 30000

INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order") VALUES ('WINDOWS', 'Hyper-V', 12);
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order") VALUES ('LINUX', 'Linux', 13);

INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('VMWARE', 'RESOURCEPOOL', 'Resource Pool', 3, 2, 'folder_items');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items", "inherit_acl_from") VALUES ('VMWARE', 'ESXI', 'ESXi', 4, 2, 'folder_folders', 1);
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('VMWARE', 'VM', 'VM', 5, 2, 'folder_items');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('VMWARE', 'DATACENTER', NULL, 6, 1, 'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('VMWARE', 'DATASTORE', NULL, 7, 6, 'items');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items", "recursive_folder", "item_subsystem") VALUES ('VMWARE', 'RESOURCEPOOL_FOLDER', NULL, 8, 3, 'folders', 1, 3);
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items", "recursive_folder", "item_subsystem") VALUES ('VMWARE', 'VM_FOLDER', NULL, 9, 5, 'folders', 1, 5);
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items", "recursive_folder", "item_subsystem") VALUES ('VMWARE', 'DATASTORE_FOLDER', NULL, 10, 6, 'folders', 1, 7);

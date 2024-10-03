.timeout 30000

INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('KUBERNETES', 'POD', NULL, 4, 7, 'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('KUBERNETES', 'NAMESPACES', 'Namespaces', 6, 1, 'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('KUBERNETES', 'NAMESPACE', NULL, 7, 6, 'folders');

INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('DB2', 'BUFFERPOOL', "Buffer pools", 4, 1, 'folder_items');

INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order", "class") VALUES ('CLOUDSTACK', 'Apache CloudStack', 17, 'CLOUD');

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


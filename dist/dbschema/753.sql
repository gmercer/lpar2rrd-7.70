.timeout 30000

INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order", "class") VALUES ('DB2', 'IBM Db2', 22, 'DB');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('DB2', 'HOST', 'Host', 1, NULL, 'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('DB2', 'DB_FOLDERS', 'Members', 2, 1, 'folders');
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items") VALUES ('DB2', 'DB', "label", 3, 2, 'folders');

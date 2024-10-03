.timeout 30000

INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order") VALUES ('NUTANIX', 'Nutanix', 3);
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order") VALUES ('ORACLEDB', 'OracleDB', 4);
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order") VALUES ('ORACLEVM', 'OracleVM', 5);
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order") VALUES ('SOLARIS', 'Solaris', 6);
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order") VALUES ('OVIRT', 'oVirt', 7);
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order") VALUES ('XENSERVER', 'XenServer', 8);
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order") VALUES ('WINDOWS', 'Hyper-V', 9);
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order") VALUES ('AWS', 'Amazon Web Services', 10);
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order") VALUES ('GCLOUD', 'Google Cloud', 11);
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order") VALUES ('AZURE', 'Microsoft Azure', 12);
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order") VALUES ('KUBERNETES', 'Kubernetes', 13);
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order") VALUES ('OPENSHIFT', 'Openshift', 14);
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order") VALUES ('LINUX', 'Linux', 15);

INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items", "inherit_acl_from") VALUES ('POWER', 'HMC', 'HMC Totals', 1, NULL, 'folder_items', 0);
INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items", "inherit_acl_from") VALUES ('SOLARIS', 'SOLARIS_TOTAL', NULL, 1, NULL, 'folders', 0);

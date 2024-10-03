.timeout 30000

ALTER TABLE "hw_types" ADD COLUMN "hw_type_order" integer;

INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "class", "hw_type_order") VALUES ('POWER', 'IBM Power Systems', 'VIRTUALIZATION', 1);
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "class", "hw_type_order") VALUES ('VMWARE', 'VMware', 'VIRTUALIZATION', 2);
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "class", "hw_type_order") VALUES ('XENSERVER', 'XenServer', 'VIRTUALIZATION', 3);
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "class", "hw_type_order") VALUES ('OVIRT', 'oVirt', 'VIRTUALIZATION', 4);
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "class", "hw_type_order") VALUES ('NUTANIX', 'Nutanix', 'VIRTUALIZATION', 5);
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "class", "hw_type_order") VALUES ('AWS', 'Amazon Web Services', 'VIRTUALIZATION', 7);
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "class", "hw_type_order") VALUES ('GCLOUD', 'Google Cloud', 'VIRTUALIZATION', 8);
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "class", "hw_type_order") VALUES ('AZURE', 'Microsoft Azure', 'VIRTUALIZATION', 9);
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "class", "hw_type_order") VALUES ('WINDOWS', 'WINDOWS', 'VIRTUALIZATION', 12);
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "class", "hw_type_order") VALUES ('LINUX', 'LINUX', 'VIRTUALIZATION', 13);

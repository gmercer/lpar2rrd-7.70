.timeout 30000

PRAGMA foreign_keys=OFF;

BEGIN TRANSACTION;

DELETE FROM "classes" WHERE ("class" = 'VIRTUALIZATION');
INSERT OR REPLACE INTO "classes" ("class", "label", "class_order") VALUES ('SERVER', 'Server', 1);
INSERT OR REPLACE INTO "classes" ("class", "label", "class_order") VALUES ('DB', 'Database', 2);
INSERT OR REPLACE INTO "classes" ("class", "label", "class_order") VALUES ('CLOUD', 'Cloud', 3);

ALTER TABLE "hw_types" RENAME TO "_hw_types_old";

CREATE TABLE "hw_types" (
      "hw_type" text PRIMARY KEY NOT NULL,
      "label" text NOT NULL,
      "class" text DEFAULT 'SERVER',
      "hw_type_order" integer,
      FOREIGN KEY ("class") REFERENCES "classes" ("class")
);

INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order", "class") VALUES ('POWER', 'IBM Power Systems', 1, 'SERVER');
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order", "class") VALUES ('VMWARE', 'VMware', 2, 'SERVER');
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order", "class") VALUES ('NUTANIX', 'Nutanix', 3, 'SERVER');
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order", "class") VALUES ('PROXMOX', 'Proxmox', 4, 'SERVER');
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order", "class") VALUES ('OVIRT', 'oVirt', 5, 'SERVER');
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order", "class") VALUES ('XENSERVER', 'XenServer', 6, 'SERVER');
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order", "class") VALUES ('WINDOWS', 'Hyper-V', 7, 'SERVER');
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order", "class") VALUES ('SOLARIS', 'Solaris', 8, 'SERVER');
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order", "class") VALUES ('ORACLEVM', 'OracleVM', 9, 'SERVER');
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order", "class") VALUES ('ORACLEDB', 'OracleDB', 10, 'DB');
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order", "class") VALUES ('POSTGRES', 'PostgreSQL', 11, 'DB');
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order", "class") VALUES ('AWS', 'Amazon Web Services', 12, 'CLOUD');
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order", "class") VALUES ('GCLOUD', 'Google Cloud', 13, 'CLOUD');
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order", "class") VALUES ('AZURE', 'Microsoft Azure', 14, 'CLOUD');
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order", "class") VALUES ('KUBERNETES', 'Kubernetes', 15, 'CLOUD');
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order", "class") VALUES ('OPENSHIFT', 'Red Hat OpenShift', 16, 'CLOUD');
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order", "class") VALUES ('CLOUDSTACK', 'Apache CloudStack', 17, 'SERVER');
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order", "class") VALUES ('LINUX', 'Linux', 18, 'SERVER');
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order", "class") VALUES ('SQLSERVER', 'SQLServer', 19, 'DB');

DROP TABLE IF EXISTS "_hw_types_old";

COMMIT;

PRAGMA foreign_keys=ON;

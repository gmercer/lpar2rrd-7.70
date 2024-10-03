.timeout 30000

INSERT OR REPLACE INTO "classes" ("class", "label", "class_order") VALUES ('CONTAINER', 'Container', 4);

INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order", "class") VALUES ('KUBERNETES', 'Kubernetes', 15, 'CONTAINER');
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order", "class") VALUES ('OPENSHIFT', 'Red Hat OpenShift', 16, 'CONTAINER');
INSERT OR REPLACE INTO "hw_types" ("hw_type", "label", "hw_type_order", "class") VALUES ('DOCKER', 'Docker', 21, 'CONTAINER');

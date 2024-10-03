.timeout 30000

ALTER TABLE "subsystems" ADD COLUMN "agent" integer NOT NULL DEFAULT 0;

INSERT OR REPLACE INTO "subsystems" ("hw_type", "subsystem", "label", "subsystem_order", "subsystem_parent", "menu_items", "agent") VALUES ('LINUX', 'SERVER', NULL, 1, NULL, 'items', 1);

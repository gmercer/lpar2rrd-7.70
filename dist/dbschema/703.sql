.timeout 30000

CREATE TABLE IF NOT EXISTS "hostcfg_relations" (
      "hostcfg_id" text NOT NULL,
      "item_id" text NOT NULL,
      PRIMARY KEY ("hostcfg_id", "item_id"),
      FOREIGN KEY ("item_id") REFERENCES "object_items" ("item_id") ON DELETE CASCADE ON UPDATE NO ACTION
);

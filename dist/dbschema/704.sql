.timeout 30000

CREATE TABLE IF NOT EXISTS "agent_relations" (
      "agent_id" text NOT NULL,
      "item_id" text NOT NULL,
      "relation_timestamp" DATETIME DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY ("agent_id", "item_id"),
      FOREIGN KEY ("item_id") REFERENCES "object_items" ("item_id") ON DELETE CASCADE ON UPDATE NO ACTION
);

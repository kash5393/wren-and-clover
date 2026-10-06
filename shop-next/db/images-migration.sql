CREATE TABLE IF NOT EXISTS product_images (
  product_id TEXT PRIMARY KEY REFERENCES products (id) ON DELETE CASCADE,
  content_type TEXT NOT NULL,
  data BYTEA NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Выполняется автоматически один раз при первом старте контейнера db

CREATE TABLE items (
    id integer PRIMARY KEY,
    value text NOT NULL
);

INSERT INTO items (id, value)
SELECT n, 'item-' || lpad(n::text, 3, '0')
FROM generate_series(1, 100) AS n;
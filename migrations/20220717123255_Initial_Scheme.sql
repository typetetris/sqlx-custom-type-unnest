CREATE TYPE test_id AS (
  id INTEGER
);
CREATE SEQUENCE test_id_seq AS INTEGER;
CREATE TABLE test (
  id test_id NOT NULL PRIMARY KEY DEFAULT ROW(nextval('test_id_seq')),
  name TEXT UNIQUE
);
ALTER SEQUENCE test_id_seq OWNED BY test.id;

CREATE TABLE dependent2 (
  id SERIAL PRIMARY KEY,
  test test_id REFERENCES test(id) ON DELETE CASCADE NOT NULL UNIQUE
);

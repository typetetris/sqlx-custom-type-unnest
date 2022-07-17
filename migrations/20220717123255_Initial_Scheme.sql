CREATE TYPE test_id AS (
  id INTEGER
);
CREATE SEQUENCE test_id_seq AS INTEGER;
CREATE TABLE test (
  id test_id NOT NULL PRIMARY KEY DEFAULT ROW(nextval('test_id_seq')),
  name TEXT UNIQUE
);
ALTER SEQUENCE test_id_seq OWNED BY test.id;

CREATE TABLE dependent (
  id SERIAL PRIMARY KEY,
  test test_id REFERENCES test(id) ON DELETE CASCADE NOT NULL UNIQUE
);

CREATE TABLE dependent_with_name (
  id SERIAL PRIMARY KEY,
  test test_id REFERENCES test(id) ON DELETE CASCADE NOT NULL,
  name TEXT,
  UNIQUE (test,name)
);

CREATE TYPE test2_id AS (
  id INTEGER,
  name TEXT
);

CREATE SEQUENCE test2_id_seq AS INTEGER;
CREATE TABLE test2 (
  id test2_id NOT NULL PRIMARY KEY DEFAULT ROW(nextval('test_id_seq'),'a description'),
  name TEXT UNIQUE
);
ALTER SEQUENCE test2_id_seq OWNED BY test.id;

CREATE TABLE dependent2 (
  id SERIAL PRIMARY KEY,
  test test2_id REFERENCES test2(id) ON DELETE CASCADE NOT NULL UNIQUE
);


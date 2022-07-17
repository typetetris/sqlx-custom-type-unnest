Combining custom record types with unnest results in wrong type looked up by sqlx
=================================================================================

To gain more type safety, we would like to create our own record types in postgres
for ids. (Domain types don't quite cut it, because of the automatic conversions
on them on the postgres side.)

So we create our type and a table with an `id` column of that type.

```sql
CREATE TYPE test_id AS (
  id INTEGER
);
CREATE SEQUENCE test_id_seq AS INTEGER;
CREATE TABLE test (
  id test_id NOT NULL PRIMARY KEY DEFAULT ROW(nextval('test_id_seq')),
  name TEXT UNIQUE
);
ALTER SEQUENCE test_id_seq OWNED BY test.id;
```

To support that type on the rust side, we define:

```rust
#[derive(Clone, Copy, Hash, PartialEq, Eq, sqlx::Type, Debug)]
#[sqlx(type_name = "test_id")]
pub struct TestDBID {
    id: i32
}
```

Now we insert some data in it

```rust
    let test_ids: Result<Vec<_>,_> = sqlx::query!(
        "
        INSERT INTO test (name)
        SELECT * FROM UNNEST($1::TEXT[])
        ON CONFLICT (name) DO UPDATE SET name = test.name
        RETURNING id AS \"id: TestDBID\"
        ",
        &names[..]
        ).fetch(&pool)
        .map(|result| result.map(|record| record.id))
        .collect()
        .await;
```

and hand over a slice reference of type `&[String]` on the rust side,
the result is correctly inferred as `Result<Vec<TestDBID>, sqlx::Error>`.

Now we want to create a table having a foreign key column referencing
table `test`

```sql
CREATE TABLE dependent (
  id SERIAL PRIMARY KEY,
  test test_id REFERENCES test(id) ON DELETE CASCADE NOT NULL UNIQUE
);
```

and insert some data

```rust
    let dependent_ids: Result<Vec<_>,_> = sqlx::query!(
        "
        INSERT INTO dependent (test)
        SELECT test_ids FROM UNNEST($1::test_id[]) AS test_ids(id)
        ON CONFLICT (test) DO UPDATE SET test = dependent.test
        RETURNING id
        ",
        &test_ids[..],
        ).fetch(&pool)
        .map(|result| result.map(|record| record.id))
        .collect()
        .await;
```

but this results in the following error:

```
error: unsupported type _test_id for param #1
  --> src/main.rs:29:44
   |
29 |       let dependent_ids: Result<Vec<_>,_> = sqlx::query!(
   |  ____________________________________________^
30 | |         "
31 | |         INSERT INTO dependent (test)
32 | |         SELECT test_ids FROM UNNEST($1::test_id[]) AS test_ids(id)
...  |
36 | |         &test_ids[..],
37 | |         ).fetch(&pool)
   | |_________^
   |
   = note: this error originates in the macro `$crate::sqlx_macros::expand_query` (in Nightly builds, run with -Z macro-backtrace for more info)

error: could not compile `sqlx-custom-type-unnest` due to previous error
```

Using `PREPARE` and `EXECUTE` like this works (on an empty database):

```
INSERT INTO test(name) VALUES ('a'),('b');
PREPARE insert_dependent(test_id[]) AS 
INSERT INTO dependent (test)
SELECT test_ids FROM UNNEST($1::test_id[]) AS test_ids(id)
ON CONFLICT (test) DO UPDATE SET test = dependent.test
RETURNING id;

EXECUTE insert_dependent(ARRAY[ROW(1), ROW(2)]::test_id[]);
```

if there are rows with ids `(1), (2)` in tables `test`.

Setting postgres logging very high, one can see, that sqlx queries `pg_types`
like this (`oid` would be different for your instance of postgres db of course):

```
dev=# SELECT typname, typtype, typcategory, typrelid, typelem, typbasetype FROM pg_catalog.pg_type WHERE oid = 18200;
 typname  | typtype | typcategory | typrelid | typelem | typbasetype
----------+---------+-------------+----------+---------+-------------
 _test_id | b       | A           |        0 |   18201 |           0
```

resulting an a type named `_test_id`, which of course, we don't know. I don't know much about postgres type system
internals, so I am just guessing here. If we look up that `typelem`, we get the wanted type:

```
dev=# SELECT typname, typtype, typcategory, typrelid, typelem, typbasetype FROM pg_catalog.pg_type WHERE oid = 18201;
 typname | typtype | typcategory | typrelid | typelem | typbasetype
---------+---------+-------------+----------+---------+-------------
 test_id | c       | C           |    18199 |       0 |           0
```

maybe there is some lookup of another indirection missing?

In [this example repo](https://github.com/typetetris/sqlx-custom-type-unnest) this is example `record-single-element`.

To try compile it, run

```
docker compose up -d
export DATABASE_URL="postgresql://dev:dev@localhost/dev"
sqlx migrate run
cargo build --example record-single-element
```

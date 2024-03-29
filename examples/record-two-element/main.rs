use anyhow::Context;
use sqlx::postgres::{PgHasArrayType, PgTypeInfo};
use tokio_stream::StreamExt;

#[derive(Clone, Hash, PartialEq, Eq, sqlx::Type, Debug)]
#[sqlx(type_name = "test_id")]
pub struct TestDBID {
    id: i32,
    name: String
}

impl PgHasArrayType for TestDBID {
    fn array_type_info() -> PgTypeInfo {
        PgTypeInfo::with_name("_test_id")
    }
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let database_url = std::env::var("DATABASE_URL").context("DATABASE_URL environment variable not set")?;
    let pool = sqlx::postgres::PgPoolOptions::new().connect(database_url.as_str()).await?;

    let names: Vec<_> = ["test_name1", "test_name2", "test_name3"].into_iter().map(|v| v.to_string()).collect();
    let test_ids: Result<Vec<_>,_> = sqlx::query!(
        "
        INSERT INTO test2 (name)
        SELECT * FROM UNNEST($1::TEXT[])
        ON CONFLICT (name) DO UPDATE SET name = test2.name
        RETURNING id AS \"id: TestDBID\"
        ",
        &names[..]
        ).fetch(&pool)
        .map(|result| result.map(|record| record.id))
        .collect()
        .await;

    let test_ids = test_ids?;

    let dependent2_ids: Result<Vec<_>,_> = sqlx::query!(
        "
        INSERT INTO dependent2 (test)
        SELECT test_ids FROM UNNEST($1::test2_id[]) AS test_ids(id, name)
        ON CONFLICT (test) DO UPDATE SET test = dependent2.test
        RETURNING id
        ",
        &test_ids[..] as &[TestDBID],
        ).fetch(&pool)
        .map(|result| result.map(|record| record.id))
        .collect()
        .await;

    Ok(())
}

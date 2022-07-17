use anyhow::Context;
use tokio_stream::StreamExt;

#[derive(Clone, Copy, Hash, PartialEq, Eq, sqlx::Type, Debug)]
#[sqlx(type_name = "test_id")]
pub struct TestDBID {
    id: i32
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let database_url = std::env::var("DATABASE_URL").context("DATABASE_URL environment variable not set")?;
    let pool = sqlx::postgres::PgPoolOptions::new().connect(database_url.as_str()).await?;

    let names: Vec<_> = ["test_name1", "test_name2", "test_name3"].into_iter().map(|v| v.to_string()).collect();
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

    let dep_names: Vec<_> = ["dependent_name1", "dependent_name2", "dependent_name3"].into_iter().map(|v| v.to_string()).collect();
    let dependent2_ids: Result<Vec<_>,_> = sqlx::query!(
        "
        INSERT INTO dependent_with_name (test,name)
        SELECT ROW(test_ids.id)::test_id, test_ids.name FROM UNNEST($1::test_id[], $2::TEXT[]) AS test_ids(id, name)
        ON CONFLICT (test,name) DO UPDATE SET test = dependent_with_name.test
        RETURNING id
        ",
        &test_ids[..],
        &dep_names[..]
        ).fetch(&pool)
        .map(|result| result.map(|record| record.id))
        .collect()
        .await;
    
    Ok(())
}

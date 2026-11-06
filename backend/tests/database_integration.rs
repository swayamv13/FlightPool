use sqlx::{PgPool, postgres::PgPoolOptions};
use std::{env, path::PathBuf, time::Duration};

const EXPECTED_TABLES: [&str; 24] = [
    "audit_logs",
    "booking_passengers",
    "bookings",
    "driver_assignments",
    "driver_documents",
    "driver_ledger_entries",
    "drivers",
    "fare_consents",
    "fare_quotes",
    "flight_events",
    "flight_instances",
    "group_members",
    "group_proposals",
    "outbox_events",
    "passenger_profiles",
    "payment_attempts",
    "payment_review_cases",
    "payments",
    "refunds",
    "ride_groups",
    "ride_stops",
    "rides",
    "users",
    "vehicles",
];

const IMPORTANT_TABLES: [&str; 7] = [
    "bookings",
    "ride_groups",
    "fare_quotes",
    "drivers",
    "payments",
    "refunds",
    "outbox_events",
];

fn load_database_url() -> String {
    let cwd =
        env::current_dir().expect("database integration test could not read the working directory");
    let candidates = [
        cwd.join(".env"),
        cwd.join("../.env"),
        cwd.join("backend/.env"),
        cwd.join("../../.env"),
    ];

    for candidate in candidates {
        if candidate.is_file() {
            dotenvy::from_path(&candidate).unwrap_or_else(|_| {
                panic!(
                    "could not load environment file {}",
                    display_path(candidate)
                )
            });
            break;
        }
    }

    env::var("DATABASE_URL")
        .ok()
        .filter(|value| !value.trim().is_empty())
        .expect("DATABASE_URL is required in the project .env; the URL itself was not printed")
}

fn display_path(path: PathBuf) -> String {
    path.file_name()
        .map(|name| name.to_string_lossy().into_owned())
        .unwrap_or_else(|| ".env".to_string())
}

async fn connect() -> PgPool {
    PgPoolOptions::new()
        .max_connections(2)
        .acquire_timeout(Duration::from_secs(5))
        .connect(&load_database_url())
        .await
        .expect("could not connect to PostgreSQL; verify DATABASE_URL and database availability")
}

async fn public_table_names(pool: &PgPool) -> Vec<String> {
    sqlx::query_scalar::<_, String>(
        r#"
        SELECT tablename
        FROM pg_catalog.pg_tables
        WHERE schemaname = 'public'
        ORDER BY tablename
        "#,
    )
    .fetch_all(pool)
    .await
    .expect("could not read public table metadata")
}

#[tokio::test]
async fn database_accepts_select_one() {
    let pool = connect().await;
    let value = sqlx::query_scalar::<_, i32>("SELECT 1")
        .fetch_one(&pool)
        .await
        .expect("SELECT 1 failed while checking PostgreSQL connectivity");

    assert_eq!(value, 1, "SELECT 1 returned an unexpected value");
}

#[tokio::test]
async fn all_expected_public_tables_exist() {
    let pool = connect().await;
    let tables = public_table_names(&pool).await;

    let missing: Vec<&str> = EXPECTED_TABLES
        .iter()
        .copied()
        .filter(|expected| !tables.iter().any(|actual| actual == expected))
        .collect();

    assert!(
        missing.is_empty(),
        "missing expected public tables: {missing:?}"
    );
    assert_eq!(
        tables.len(),
        EXPECTED_TABLES.len(),
        "expected exactly {} public tables, found {}: {tables:?}",
        EXPECTED_TABLES.len(),
        tables.len()
    );
}

#[tokio::test]
async fn expected_public_triggers_exist() {
    let pool = connect().await;
    let trigger_count = sqlx::query_scalar::<_, i64>(
        r#"
        SELECT COUNT(*)
        FROM pg_catalog.pg_trigger trigger_row
        JOIN pg_catalog.pg_class class_row ON class_row.oid = trigger_row.tgrelid
        JOIN pg_catalog.pg_namespace namespace_row ON namespace_row.oid = class_row.relnamespace
        WHERE namespace_row.nspname = 'public'
          AND NOT trigger_row.tgisinternal
        "#,
    )
    .fetch_one(&pool)
    .await
    .expect("could not read public trigger metadata");

    assert_eq!(
        trigger_count, 6,
        "expected 6 public triggers, found {trigger_count}"
    );
}

#[tokio::test]
async fn important_public_tables_exist() {
    let pool = connect().await;
    let tables = public_table_names(&pool).await;
    let missing: Vec<&str> = IMPORTANT_TABLES
        .iter()
        .copied()
        .filter(|expected| !tables.iter().any(|actual| actual == expected))
        .collect();

    assert!(
        missing.is_empty(),
        "missing important public tables: {missing:?}"
    );
}

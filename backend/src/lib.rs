mod config;
mod routes;

pub use config::Config;
use sqlx::PgPool;

pub fn create_router(pool: PgPool) -> axum::Router {
    routes::router(pool)
}

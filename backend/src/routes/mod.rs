mod health;

use axum::Router;
use sqlx::PgPool;

#[derive(Clone)]
pub struct AppState {
    pub pool: PgPool,
}

pub fn router(pool: PgPool) -> Router {
    Router::new()
        .merge(health::live_routes())
        .merge(health::ready_routes())
        .with_state(AppState { pool })
}

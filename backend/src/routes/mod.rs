mod health;

use axum::Router;

pub fn router() -> Router {
    Router::new()
        .merge(health::live_routes())
        .merge(health::ready_routes())
}

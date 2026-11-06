mod config;
mod routes;

pub use config::Config;

pub fn create_router() -> axum::Router {
    routes::router()
}

use axum::{Json, Router, extract::State, http::StatusCode, routing::get};
use serde::Serialize;

use super::AppState;

#[derive(Debug, Serialize)]
struct HealthResponse {
    status: &'static str,
    service: &'static str,
}

#[derive(Debug, Serialize)]
struct ReadyResponse {
    status: &'static str,
    application_initialized: bool,
    database_configured: bool,
    database: &'static str,
}

pub fn live_routes() -> Router<AppState> {
    Router::new().route(
        "/health/live",
        get(|| async {
            Json(HealthResponse {
                status: "ok",
                service: "flightpool-api",
            })
        }),
    )
}

pub fn ready_routes() -> Router<AppState> {
    Router::new().route("/health/ready", get(readiness))
}

async fn readiness(State(state): State<AppState>) -> (StatusCode, Json<ReadyResponse>) {
    let database_available = sqlx::query_scalar::<_, i32>("SELECT 1")
        .fetch_one(&state.pool)
        .await
        .is_ok_and(|value| value == 1);

    readiness_response(database_available)
}

fn readiness_response(database_available: bool) -> (StatusCode, Json<ReadyResponse>) {
    let (status_code, status) = if database_available {
        (StatusCode::OK, "ok")
    } else {
        (StatusCode::SERVICE_UNAVAILABLE, "unavailable")
    };

    (
        status_code,
        Json(ReadyResponse {
            status,
            application_initialized: true,
            database_configured: true,
            database: if database_available {
                "available"
            } else {
                "unavailable"
            },
        }),
    )
}

#[cfg(test)]
mod tests {
    use axum::{
        Router,
        body::Body,
        http::{Request, StatusCode},
        routing::get,
    };
    use http_body_util::BodyExt;
    use tower::ServiceExt;

    async fn response_body(router: Router, uri: &str) -> (StatusCode, String) {
        let response = router
            .oneshot(Request::builder().uri(uri).body(Body::empty()).unwrap())
            .await
            .unwrap();
        let status = response.status();
        let body = response.into_body().collect().await.unwrap().to_bytes();

        (status, String::from_utf8(body.to_vec()).unwrap())
    }

    #[tokio::test]
    async fn liveness_returns_http_200() {
        let router = Router::<()>::new().route(
            "/health/live",
            get(|| async {
                axum::Json(super::HealthResponse {
                    status: "ok",
                    service: "flightpool-api",
                })
            }),
        );

        let (status, _) = response_body(router, "/health/live").await;

        assert_eq!(status, StatusCode::OK);
    }

    #[tokio::test]
    async fn readiness_returns_http_503_when_database_is_unavailable() {
        let (status, body) = super::readiness_response(false);
        let body_json = serde_json::to_string(&body.0).unwrap();

        assert_eq!(status, StatusCode::SERVICE_UNAVAILABLE);
        assert!(body_json.contains("\"database_configured\":true"));
        assert!(body_json.contains("\"database\":\"unavailable\""));
    }
}

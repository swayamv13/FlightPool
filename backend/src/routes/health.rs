use axum::{Json, Router, http::StatusCode, routing::get};
use serde::Serialize;

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

pub fn live_routes() -> Router {
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

pub fn ready_routes() -> Router {
    Router::new().route("/health/ready", get(|| async { readiness(false) }))
}

fn readiness(database_configured: bool) -> (StatusCode, Json<ReadyResponse>) {
    let (status_code, status) = if database_configured {
        (StatusCode::OK, "ok")
    } else {
        (StatusCode::SERVICE_UNAVAILABLE, "unavailable")
    };

    (
        status_code,
        Json(ReadyResponse {
            status,
            application_initialized: true,
            database_configured,
            database: if database_configured {
                "configured"
            } else {
                "not configured"
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
        let router = Router::new().route(
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
        let router =
            Router::new().route("/health/ready", get(|| async { super::readiness(false) }));

        let (status, body) = response_body(router, "/health/ready").await;

        assert_eq!(status, StatusCode::SERVICE_UNAVAILABLE);
        assert!(body.contains("\"database_configured\":false"));
    }
}

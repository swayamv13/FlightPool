# FlightPool Engineering v1.0

Contains the proposed system architecture and initial PostgreSQL/SQLx schema baseline.

- `docs/ARCHITECTURE_AND_SYSTEM_DESIGN.md` — modules, flows, security, deployment and coding roadmap.
- `docs/POSTGRES_SCHEMA_NOTES.md` — schema rationale and application-enforced invariants.
- `docs/IMPLEMENTATION_CHECKLIST.md` — coding checklist.
- `migrations/0001_initial_schema.sql` — initial SQLx-compatible PostgreSQL migration.

**Status:** Engineering baseline for review, not a claim that the backend has been implemented or tested. Apply to a disposable PostgreSQL 16+ database first. Some business rules require Rust transaction-level validation and cannot be enforced by simple SQL constraints.

Suggested SQLx CLI workflow:
```bash
cargo install sqlx-cli --no-default-features --features rustls,postgres
export DATABASE_URL='postgres://flightpool:flightpool_dev@localhost:5432/flightpool'
sqlx database create
sqlx migrate run
sqlx migrate info
```

Suggested Rust starting dependencies (pin versions to the actual workspace/lockfile): Axum 0.8, Tokio, Serde, SQLx with PostgreSQL/UUID/chrono/JSON/migrate features, UUID, Chrono, tracing and thiserror.

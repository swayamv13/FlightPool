# FlightPool Implementation Checklist

## Before coding
- [ ] Confirm repository and branch strategy.
- [ ] Review architecture and migration.
- [ ] Confirm PostgreSQL 16+ and local Docker setup.
- [ ] Add `.env.example`; never commit real secrets.
- [ ] Choose development-only authentication adapter.
- [ ] Confirm Rust toolchain and SQLx CLI version.

## M1 — Database foundation
- [ ] Start disposable PostgreSQL 16+.
- [ ] Apply `0001_initial_schema.sql` with SQLx CLI.
- [ ] Run `sqlx migrate info`.
- [ ] Add migration integration tests.
- [ ] Test CHECK constraints and unique indexes.
- [ ] Test one active group per booking.
- [ ] Test one active assignment per driver.
- [ ] Add transaction tests for max 4 passengers and min 2 parties.
- [ ] Add concurrent last-seat test.
- [ ] Review encryption/key management before storing real addresses.

## M2 — Rust foundation
- [ ] Axum `/health/live` and `/health/ready`.
- [ ] Config loading and startup validation.
- [ ] SQLx pool and graceful shutdown.
- [ ] Structured tracing and request IDs.
- [ ] Standard error response.
- [ ] Module/service/repository boundaries.
- [ ] CI: fmt, clippy, unit tests, migration tests.

## M3 onward
- [ ] Flights and flight event adapter.
- [ ] Booking lifecycle and ownership.
- [ ] Matching engine with deterministic routing fake.
- [ ] Immutable group proposals and fare quote versions.
- [ ] Fare consent workflow.
- [ ] Driver verification and dispatch.
- [ ] Ride readiness, OTP and completion.
- [ ] Payment adapter and idempotent webhooks.
- [ ] Outbox worker with leases, retries and dead-letter/review handling.
- [ ] Security, privacy, airport and legal readiness reviews.

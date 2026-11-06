# FlightPool PostgreSQL Schema Notes v1.0

## Conventions
- PostgreSQL 16+; UUID primary keys; `TIMESTAMPTZ`; UTC persistence; integer paise; restrictive foreign keys for business history.
- Address ciphertext and nonce are separate from coordinates. Encryption/decryption occurs in Rust using managed keys; never store keys in PostgreSQL.
- JSONB is for route/proposal snapshots, filtered provider metadata, audit metadata and outbox payloads—not core relational fields.
- PostgreSQL enums constrain status values; Rust services enforce legal transitions.

## Important relationships
- A `bookings` row is one independent booking party; `party_size` is the travellers in that party. Parties are never split.
- `group_members` is historical. A partial unique index permits one active membership per booking. Cross-row group capacity and minimum-party checks happen transactionally while locking the group row.
- Each `group_proposals` row is a versioned route/membership snapshot. Each `fare_quotes` row is an immutable passenger-specific quote version. Consent applies to a specific quote.
- A confirmed group produces at most one ride. `ride_stops` associates each pickup/drop with its booking.
- Every driver offer is stored in `driver_assignments`; rejected/timed-out offers remain history.
- Payment attempts and refunds are separate records. Webhooks must be verified and idempotent.
- Outbox rows are written in the same transaction as the business event. Workers claim rows using `FOR UPDATE SKIP LOCKED`, leases and retry backoff.

## Application-enforced invariants
1. Group passenger total <= 4.
2. Pooled confirmation requires >= 2 distinct active booking parties.
3. All required fare consents for the current proposal must be accepted.
4. Confirmed membership is frozen.
5. Each passenger detour <= 15 minutes.
6. Each booking wait <= 10 minutes.
7. New group formation cutoff is estimated pickup minus 30 minutes.
8. Booking opens 24 hours before scheduled arrival.
9. Vehicle and luggage compatibility.
10. Valid driver/ride/payment state transitions.

For membership changes: begin transaction, `SELECT groups ... FOR UPDATE`, read active memberships, validate party count/seats/luggage/cutoff, write membership/proposal/quotes, then commit. Do not call external providers inside the transaction.

## SQLx migration workflow
```bash
cargo install sqlx-cli --no-default-features --features rustls,postgres
export DATABASE_URL='postgres://flightpool:flightpool_dev@localhost:5432/flightpool'
sqlx database create
sqlx migrate run
sqlx migrate info
```

Apply migrations to a fresh disposable PostgreSQL database in CI. Once a migration has been applied in a shared environment, add a new forward migration instead of editing the old one.

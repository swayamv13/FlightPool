-- FlightPool baseline schema | PostgreSQL 16+ | SQLx migration 0001
-- Review and apply to a disposable database before shared/production use.
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;

CREATE TYPE user_role AS ENUM ('PASSENGER','DRIVER','ADMIN','OPS');
CREATE TYPE account_status AS ENUM ('PENDING','ACTIVE','SUSPENDED','CLOSED');
CREATE TYPE flight_status AS ENUM ('SCHEDULED','DELAYED','LANDED','CANCELLED','DIVERTED','UNKNOWN');
CREATE TYPE booking_status AS ENUM ('REQUESTED','WAITLISTED','PROPOSAL_PENDING','CONFIRMED','CANCELLED','EXPIRED');
CREATE TYPE vehicle_category AS ENUM ('SEDAN','SUV');
CREATE TYPE luggage_size AS ENUM ('CABIN','MEDIUM','LARGE');
CREATE TYPE group_status AS ENUM ('FORMING','PROPOSAL_PENDING','CONFIRMED','DISPATCHING','DRIVER_ASSIGNED','NEEDS_SUPPORT','EXPIRED','CANCELLED');
CREATE TYPE membership_status AS ENUM ('ACTIVE','LEFT','REMOVED');
CREATE TYPE proposal_status AS ENUM ('OPEN','ACCEPTED','REJECTED','EXPIRED','SUPERSEDED','CANCELLED');
CREATE TYPE consent_decision AS ENUM ('ACCEPTED','REJECTED','PENDING','EXPIRED');
CREATE TYPE driver_verification_status AS ENUM ('PENDING','UNDER_REVIEW','APPROVED','REJECTED','SUSPENDED','EXPIRED');
CREATE TYPE availability_status AS ENUM ('OFFLINE','AVAILABLE','BUSY','SUSPENDED');
CREATE TYPE document_type AS ENUM ('IDENTITY','DRIVING_LICENCE','VEHICLE_RC','INSURANCE','PERMIT','OTHER');
CREATE TYPE document_status AS ENUM ('PENDING','VERIFIED','REJECTED','EXPIRED');
CREATE TYPE ride_status AS ENUM ('PENDING_DISPATCH','DRIVER_ASSIGNED','PICKUP_READY','DRIVER_ARRIVED','OTP_VERIFIED','IN_PROGRESS','COMPLETED','CANCELLED','NO_SHOW');
CREATE TYPE stop_type AS ENUM ('PICKUP','DROPOFF');
CREATE TYPE assignment_status AS ENUM ('OFFERED','ACCEPTED','REJECTED','TIMED_OUT','CANCELLED','COMPLETED');
CREATE TYPE payment_status AS ENUM ('PENDING','PROCESSING','PAID','FAILED','REVIEW_REQUIRED','PARTIALLY_REFUNDED','REFUNDED');
CREATE TYPE payment_attempt_status AS ENUM ('STARTED','SUCCEEDED','FAILED','UNKNOWN');
CREATE TYPE refund_status AS ENUM ('PENDING','PROCESSING','SUCCEEDED','FAILED');
CREATE TYPE ledger_entry_type AS ENUM ('RIDE_EARNING','COMMISSION','TOLL_REIMBURSEMENT','ADJUSTMENT','PAYOUT');
CREATE TYPE outbox_status AS ENUM ('PENDING','PROCESSING','DELIVERED','FAILED','DEAD_LETTER');
CREATE TYPE review_case_status AS ENUM ('OPEN','IN_REVIEW','RESOLVED','CLOSED');

CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  phone_e164 VARCHAR(20) NOT NULL UNIQUE,
  email CITEXT UNIQUE,
  role user_role NOT NULL,
  status account_status NOT NULL DEFAULT 'PENDING',
  phone_verified_at TIMESTAMPTZ,
  email_verified_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (phone_e164 ~ '^\+[1-9][0-9]{7,14}$')
);

CREATE TABLE passenger_profiles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE RESTRICT,
  full_name VARCHAR(160) NOT NULL,
  emergency_contact_ciphertext BYTEA,
  emergency_contact_nonce BYTEA,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK ((emergency_contact_ciphertext IS NULL) = (emergency_contact_nonce IS NULL))
);

CREATE TABLE flight_instances (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  flight_number VARCHAR(12) NOT NULL,
  airline_code VARCHAR(3) NOT NULL,
  origin_airport CHAR(3) NOT NULL,
  destination_airport CHAR(3) NOT NULL,
  terminal VARCHAR(12),
  scheduled_arrival_at TIMESTAMPTZ NOT NULL,
  estimated_arrival_at TIMESTAMPTZ NOT NULL,
  actual_arrival_at TIMESTAMPTZ,
  status flight_status NOT NULL DEFAULT 'SCHEDULED',
  provider_name VARCHAR(80),
  provider_reference VARCHAR(160),
  last_provider_sync_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (origin_airport ~ '^[A-Z]{3}$'),
  CHECK (destination_airport ~ '^[A-Z]{3}$')
);
CREATE INDEX idx_flight_instances_number_arrival ON flight_instances (flight_number, scheduled_arrival_at);
CREATE INDEX idx_flight_instances_status_eta ON flight_instances (status, estimated_arrival_at);

CREATE TABLE flight_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  flight_instance_id UUID NOT NULL REFERENCES flight_instances(id) ON DELETE RESTRICT,
  previous_status flight_status,
  new_status flight_status NOT NULL,
  scheduled_arrival_at TIMESTAMPTZ,
  estimated_arrival_at TIMESTAMPTZ,
  actual_arrival_at TIMESTAMPTZ,
  source VARCHAR(80) NOT NULL,
  source_event_reference VARCHAR(160),
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  observed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_flight_events_flight_observed ON flight_events (flight_instance_id, observed_at DESC);

CREATE TABLE bookings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_reference_hash BYTEA NOT NULL,
  flight_instance_id UUID NOT NULL REFERENCES flight_instances(id) ON DELETE RESTRICT,
  primary_passenger_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  destination_locality VARCHAR(100) NOT NULL,
  destination_address_ciphertext BYTEA NOT NULL,
  destination_address_nonce BYTEA NOT NULL,
  destination_latitude NUMERIC(9,6) NOT NULL,
  destination_longitude NUMERIC(9,6) NOT NULL,
  party_size SMALLINT NOT NULL,
  luggage_count SMALLINT NOT NULL DEFAULT 0,
  largest_luggage_size luggage_size,
  vehicle_preference vehicle_category,
  status booking_status NOT NULL DEFAULT 'REQUESTED',
  requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  wait_expires_at TIMESTAMPTZ,
  cancelled_at TIMESTAMPTZ,
  cancellation_reason_code VARCHAR(60),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (party_size BETWEEN 1 AND 4),
  CHECK (luggage_count BETWEEN 0 AND 20),
  CHECK (destination_latitude BETWEEN -90 AND 90),
  CHECK (destination_longitude BETWEEN -180 AND 180),
  CHECK (octet_length(destination_address_nonce) >= 12),
  CHECK (octet_length(booking_reference_hash) >= 32)
);
CREATE INDEX idx_bookings_flight_status_requested ON bookings (flight_instance_id, status, requested_at);
CREATE INDEX idx_bookings_wait_expiry ON bookings (wait_expires_at) WHERE status = 'WAITLISTED';

CREATE TABLE booking_passengers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id UUID NOT NULL REFERENCES bookings(id) ON DELETE RESTRICT,
  full_name VARCHAR(160) NOT NULL,
  passenger_type VARCHAR(30) NOT NULL DEFAULT 'ADULT',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_booking_passengers_booking ON booking_passengers (booking_id);

CREATE TABLE ride_groups (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  flight_instance_id UUID NOT NULL REFERENCES flight_instances(id) ON DELETE RESTRICT,
  vehicle_category vehicle_category NOT NULL,
  status group_status NOT NULL DEFAULT 'FORMING',
  membership_frozen_at TIMESTAMPTZ,
  formed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  confirmed_at TIMESTAMPTZ,
  cancelled_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK ((status IN ('CONFIRMED','DISPATCHING','DRIVER_ASSIGNED','NEEDS_SUPPORT') AND membership_frozen_at IS NOT NULL)
      OR status NOT IN ('CONFIRMED','DISPATCHING','DRIVER_ASSIGNED','NEEDS_SUPPORT'))
);
CREATE INDEX idx_groups_flight_status ON ride_groups (flight_instance_id, status, created_at);

CREATE TABLE group_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id UUID NOT NULL REFERENCES ride_groups(id) ON DELETE RESTRICT,
  booking_id UUID NOT NULL REFERENCES bookings(id) ON DELETE RESTRICT,
  party_size SMALLINT NOT NULL,
  status membership_status NOT NULL DEFAULT 'ACTIVE',
  joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  left_at TIMESTAMPTZ,
  removal_reason_code VARCHAR(60),
  UNIQUE (group_id, booking_id),
  CHECK (party_size BETWEEN 1 AND 4),
  CHECK ((status = 'ACTIVE' AND left_at IS NULL) OR (status <> 'ACTIVE' AND left_at IS NOT NULL))
);
CREATE UNIQUE INDEX uq_group_members_one_active_group_per_booking ON group_members (booking_id) WHERE status = 'ACTIVE';
CREATE INDEX idx_group_members_group_active ON group_members (group_id) WHERE status = 'ACTIVE';

CREATE TABLE group_proposals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id UUID NOT NULL REFERENCES ride_groups(id) ON DELETE RESTRICT,
  proposal_version INTEGER NOT NULL,
  status proposal_status NOT NULL DEFAULT 'OPEN',
  route_snapshot JSONB NOT NULL,
  route_distance_meters INTEGER NOT NULL,
  estimated_duration_seconds INTEGER NOT NULL,
  routing_provider VARCHAR(80) NOT NULL,
  routing_fetched_at TIMESTAMPTZ NOT NULL,
  membership_snapshot JSONB NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (group_id, proposal_version),
  CHECK (proposal_version > 0),
  CHECK (route_distance_meters >= 0),
  CHECK (estimated_duration_seconds >= 0)
);
CREATE INDEX idx_group_proposals_group_created ON group_proposals (group_id, created_at DESC);

CREATE TABLE fare_quotes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  proposal_id UUID NOT NULL REFERENCES group_proposals(id) ON DELETE RESTRICT,
  booking_id UUID NOT NULL REFERENCES bookings(id) ON DELETE RESTRICT,
  quote_version INTEGER NOT NULL,
  currency CHAR(3) NOT NULL DEFAULT 'INR',
  base_amount_paise BIGINT NOT NULL DEFAULT 0,
  distance_amount_paise BIGINT NOT NULL DEFAULT 0,
  toll_amount_paise BIGINT NOT NULL DEFAULT 0,
  airport_fee_paise BIGINT NOT NULL DEFAULT 0,
  discount_amount_paise BIGINT NOT NULL DEFAULT 0,
  total_amount_paise BIGINT NOT NULL,
  breakdown JSONB NOT NULL DEFAULT '{}'::jsonb,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (proposal_id, booking_id, quote_version),
  CHECK (quote_version > 0),
  CHECK (base_amount_paise >= 0 AND distance_amount_paise >= 0),
  CHECK (toll_amount_paise >= 0 AND airport_fee_paise >= 0),
  CHECK (discount_amount_paise >= 0 AND total_amount_paise >= 0)
);
CREATE INDEX idx_fare_quotes_booking_created ON fare_quotes (booking_id, created_at DESC);

CREATE TABLE fare_consents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  fare_quote_id UUID NOT NULL REFERENCES fare_quotes(id) ON DELETE RESTRICT,
  booking_id UUID NOT NULL REFERENCES bookings(id) ON DELETE RESTRICT,
  decision consent_decision NOT NULL DEFAULT 'PENDING',
  responded_at TIMESTAMPTZ,
  response_channel VARCHAR(30),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (fare_quote_id, booking_id),
  CHECK ((decision = 'PENDING' AND responded_at IS NULL) OR (decision <> 'PENDING' AND responded_at IS NOT NULL))
);
CREATE INDEX idx_fare_consents_quote_decision ON fare_consents (fare_quote_id, decision);

CREATE TABLE drivers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE RESTRICT,
  verification_status driver_verification_status NOT NULL DEFAULT 'PENDING',
  availability_status availability_status NOT NULL DEFAULT 'OFFLINE',
  approved_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_drivers_dispatch_eligible ON drivers (availability_status, verification_status);

CREATE TABLE vehicles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id UUID NOT NULL REFERENCES drivers(id) ON DELETE RESTRICT,
  category vehicle_category NOT NULL,
  registration_number VARCHAR(24) NOT NULL UNIQUE,
  passenger_capacity SMALLINT NOT NULL,
  luggage_capacity_units SMALLINT NOT NULL,
  verification_status driver_verification_status NOT NULL DEFAULT 'PENDING',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (passenger_capacity BETWEEN 1 AND 8),
  CHECK (luggage_capacity_units >= 0)
);
CREATE INDEX idx_vehicles_driver_status ON vehicles (driver_id, verification_status);

CREATE TABLE driver_documents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id UUID NOT NULL REFERENCES drivers(id) ON DELETE RESTRICT,
  document_type document_type NOT NULL,
  storage_reference VARCHAR(500) NOT NULL,
  verification_status document_status NOT NULL DEFAULT 'PENDING',
  issued_at DATE,
  expires_at DATE,
  reviewed_by UUID REFERENCES users(id) ON DELETE RESTRICT,
  reviewed_at TIMESTAMPTZ,
  rejection_reason_code VARCHAR(80),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (expires_at IS NULL OR issued_at IS NULL OR expires_at >= issued_at)
);
CREATE INDEX idx_driver_documents_driver_type ON driver_documents (driver_id, document_type, verification_status);

CREATE TABLE rides (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id UUID NOT NULL UNIQUE REFERENCES ride_groups(id) ON DELETE RESTRICT,
  vehicle_id UUID REFERENCES vehicles(id) ON DELETE RESTRICT,
  status ride_status NOT NULL DEFAULT 'PENDING_DISPATCH',
  pickup_point_code VARCHAR(40) NOT NULL,
  pickup_terminal VARCHAR(12),
  otp_verifier BYTEA,
  otp_expires_at TIMESTAMPTZ,
  otp_attempt_count SMALLINT NOT NULL DEFAULT 0,
  assigned_at TIMESTAMPTZ,
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  cancelled_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (otp_attempt_count >= 0)
);
CREATE INDEX idx_rides_status_created ON rides (status, created_at);

CREATE TABLE ride_stops (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ride_id UUID NOT NULL REFERENCES rides(id) ON DELETE RESTRICT,
  booking_id UUID NOT NULL REFERENCES bookings(id) ON DELETE RESTRICT,
  stop_order SMALLINT NOT NULL,
  stop_type stop_type NOT NULL,
  locality VARCHAR(100) NOT NULL,
  address_ciphertext BYTEA,
  address_nonce BYTEA,
  latitude NUMERIC(9,6) NOT NULL,
  longitude NUMERIC(9,6) NOT NULL,
  planned_arrival_at TIMESTAMPTZ,
  actual_arrival_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (ride_id, stop_order),
  CHECK (stop_order > 0),
  CHECK (latitude BETWEEN -90 AND 90),
  CHECK (longitude BETWEEN -180 AND 180),
  CHECK ((address_ciphertext IS NULL) = (address_nonce IS NULL))
);
CREATE INDEX idx_ride_stops_booking ON ride_stops (booking_id, ride_id);

CREATE TABLE driver_assignments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ride_id UUID NOT NULL REFERENCES rides(id) ON DELETE RESTRICT,
  driver_id UUID NOT NULL REFERENCES drivers(id) ON DELETE RESTRICT,
  vehicle_id UUID NOT NULL REFERENCES vehicles(id) ON DELETE RESTRICT,
  status assignment_status NOT NULL DEFAULT 'OFFERED',
  offered_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  response_deadline TIMESTAMPTZ NOT NULL,
  responded_at TIMESTAMPTZ,
  rejection_reason_code VARCHAR(80),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (response_deadline > offered_at)
);
CREATE UNIQUE INDEX uq_driver_one_active_assignment ON driver_assignments (driver_id) WHERE status IN ('OFFERED','ACCEPTED');
CREATE UNIQUE INDEX uq_ride_one_accepted_assignment ON driver_assignments (ride_id) WHERE status = 'ACCEPTED';
CREATE INDEX idx_assignments_ride_created ON driver_assignments (ride_id, created_at DESC);

CREATE TABLE payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id UUID NOT NULL REFERENCES bookings(id) ON DELETE RESTRICT,
  ride_id UUID NOT NULL REFERENCES rides(id) ON DELETE RESTRICT,
  fare_quote_id UUID NOT NULL REFERENCES fare_quotes(id) ON DELETE RESTRICT,
  amount_paise BIGINT NOT NULL,
  currency CHAR(3) NOT NULL DEFAULT 'INR',
  status payment_status NOT NULL DEFAULT 'PENDING',
  provider_name VARCHAR(80),
  provider_payment_reference VARCHAR(200),
  idempotency_key VARCHAR(160) NOT NULL UNIQUE,
  paid_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (amount_paise >= 0)
);
CREATE INDEX idx_payments_booking_status ON payments (booking_id, status);
CREATE INDEX idx_payments_ride ON payments (ride_id);

CREATE TABLE payment_attempts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  payment_id UUID NOT NULL REFERENCES payments(id) ON DELETE RESTRICT,
  attempt_number INTEGER NOT NULL,
  status payment_attempt_status NOT NULL DEFAULT 'STARTED',
  provider_attempt_reference VARCHAR(200),
  provider_response_code VARCHAR(100),
  failure_code VARCHAR(100),
  failure_message_safe VARCHAR(500),
  requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at TIMESTAMPTZ,
  response_payload_redacted JSONB NOT NULL DEFAULT '{}'::jsonb,
  UNIQUE (payment_id, attempt_number),
  CHECK (attempt_number > 0)
);
CREATE INDEX idx_payment_attempts_payment_created ON payment_attempts (payment_id, requested_at DESC);

CREATE TABLE refunds (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  payment_id UUID NOT NULL REFERENCES payments(id) ON DELETE RESTRICT,
  amount_paise BIGINT NOT NULL,
  currency CHAR(3) NOT NULL DEFAULT 'INR',
  status refund_status NOT NULL DEFAULT 'PENDING',
  reason_code VARCHAR(80) NOT NULL,
  provider_refund_reference VARCHAR(200),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (amount_paise > 0)
);
CREATE INDEX idx_refunds_payment_status ON refunds (payment_id, status);

CREATE TABLE driver_ledger_entries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id UUID NOT NULL REFERENCES drivers(id) ON DELETE RESTRICT,
  ride_id UUID REFERENCES rides(id) ON DELETE RESTRICT,
  entry_type ledger_entry_type NOT NULL,
  amount_paise BIGINT NOT NULL,
  currency CHAR(3) NOT NULL DEFAULT 'INR',
  description_code VARCHAR(80) NOT NULL,
  eligible_for_payout_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_driver_ledger_driver_created ON driver_ledger_entries (driver_id, created_at DESC);

CREATE TABLE payment_review_cases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  payment_id UUID NOT NULL REFERENCES payments(id) ON DELETE RESTRICT,
  status review_case_status NOT NULL DEFAULT 'OPEN',
  reason_code VARCHAR(100) NOT NULL,
  assigned_to UUID REFERENCES users(id) ON DELETE RESTRICT,
  resolution_code VARCHAR(100),
  resolution_notes_safe VARCHAR(1000),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  resolved_at TIMESTAMPTZ
);
CREATE INDEX idx_payment_review_open ON payment_review_cases (status, created_at) WHERE status IN ('OPEN','IN_REVIEW');

CREATE TABLE audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_user_id UUID REFERENCES users(id) ON DELETE RESTRICT,
  action VARCHAR(120) NOT NULL,
  entity_type VARCHAR(80) NOT NULL,
  entity_id UUID,
  reason TEXT,
  before_snapshot JSONB,
  after_snapshot JSONB,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  request_id UUID,
  ip_address INET,
  user_agent VARCHAR(500),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_audit_entity_created ON audit_logs (entity_type, entity_id, created_at DESC);
CREATE INDEX idx_audit_actor_created ON audit_logs (actor_user_id, created_at DESC);

CREATE TABLE outbox_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  aggregate_type VARCHAR(80) NOT NULL,
  aggregate_id UUID NOT NULL,
  event_type VARCHAR(160) NOT NULL,
  payload JSONB NOT NULL,
  status outbox_status NOT NULL DEFAULT 'PENDING',
  attempt_count INTEGER NOT NULL DEFAULT 0,
  available_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  locked_by VARCHAR(120),
  locked_until TIMESTAMPTZ,
  last_error_safe VARCHAR(1000),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  delivered_at TIMESTAMPTZ,
  CHECK (attempt_count >= 0)
);
CREATE INDEX idx_outbox_ready ON outbox_events (available_at, created_at) WHERE status IN ('PENDING','FAILED');
CREATE INDEX idx_outbox_lease ON outbox_events (locked_until) WHERE status = 'PROCESSING';

-- updated_at is maintained by Rust service methods in v1; no implicit trigger.

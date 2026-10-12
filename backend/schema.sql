-- Budget/Spaces API schema. Applied automatically on boot (see lib/db.dart),
-- and safe to re-run.

create extension if not exists pgcrypto; -- gen_random_uuid()

-- One row per signed-in person, keyed by their Google account.
create table if not exists users (
  id          uuid primary key default gen_random_uuid(),
  google_sub  text unique not null,
  email       text,
  name        text,
  created_at  timestamptz not null default now()
);

-- A single, monotonic write counter across every document, so a client can ask
-- "what changed since seq N?" and page through it in order.
create sequence if not exists documents_seq;

-- Every syncable record, stored verbatim in `body` (it already carries its own
-- id / updatedAt / deletedAt). `collection` is 'expenses', 'brain', etc.
-- updated_at / deleted_at are lifted out of the body to drive last-write-wins
-- and tombstone handling; `seq` is bumped on every write for incremental pull.
create table if not exists documents (
  user_id     uuid not null references users(id) on delete cascade,
  collection  text not null,
  doc_id      text not null,
  updated_at  timestamptz not null,
  deleted_at  timestamptz,
  body        jsonb not null,
  seq         bigint not null default nextval('documents_seq'),
  primary key (user_id, collection, doc_id)
);

create index if not exists documents_user_seq on documents (user_id, seq);

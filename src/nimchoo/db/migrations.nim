## The database schema, as a list of migrations.  Entry `i` takes the database
## from schema version `i` to `i + 1` (the version is SQLite's
## `PRAGMA user_version`).  Each migration is a list of statements, because
## one `exec` runs one statement.  Never edit a migration that has been
## released: add a new one.

{.push raises: [].}

const defaultUser* = "default"

const allMigrations*: seq[seq[string]] = @[
  # 1: users, imported files, activities and their coordinates
  @["""
create table user (
  id integer primary key,
  name text not null unique)""",
    """
create table file (
  id integer primary key,
  user_id integer not null references user(id),
  name text not null,
  sha256 text not null,
  imported_at integer not null,
  unique (user_id, sha256))""",
    """
create table activity (
  id integer primary key,
  user_id integer not null references user(id),
  file_id integer not null references file(id),
  session integer not null,
  start_t integer not null,
  end_t integer not null,
  utc_offset_s integer,
  sport text,
  sub_sport text,
  elapsed_s real,
  timer_s real,
  distance_m real,
  calories integer,
  unique (file_id, session))""",
    """
create table coords (
  activity_id integer not null references activity(id),
  t integer not null,
  lon real not null,
  lat real not null,
  alt real,
  primary key (activity_id, t)) without rowid""",
    "insert into user(name) values ('" & defaultUser & "')"],
]

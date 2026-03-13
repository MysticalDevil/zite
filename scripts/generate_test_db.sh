#!/usr/bin/env sh
set -eu

if [ "${1:-}" = "" ]; then
    echo "usage: $0 <output.db>" >&2
    exit 1
fi

if ! command -v sqlite3 >/dev/null 2>&1; then
    echo "sqlite3 CLI is required" >&2
    exit 1
fi

db_path=$1

mkdir -p "$(dirname "$db_path")"
rm -f "$db_path"

sqlite3 "$db_path" <<'SQL'
PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;

CREATE TABLE users (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    age INTEGER,
    created_at INTEGER NOT NULL
);

CREATE TABLE notes (
    id INTEGER PRIMARY KEY,
    user_id INTEGER NOT NULL,
    body TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

INSERT INTO users (id, name, age, created_at) VALUES
    (1, 'alice', 30, 1700000000000),
    (2, 'bob', NULL, 1700000001000),
    (3, 'carol', 41, 1700000002000);

INSERT INTO notes (id, user_id, body, created_at) VALUES
    (1, 1, 'first note', 1700000010000),
    (2, 1, 'second note', 1700000011000),
    (3, 2, 'note for bob', 1700000012000);
SQL

echo "generated $db_path"

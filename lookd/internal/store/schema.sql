-- Look Studio library index. Files on disk stay the source of truth for
-- content; this database indexes them for fast queries and full-text search.
-- Times are unix seconds unless the column name ends in _ms.

CREATE TABLE IF NOT EXISTS meta (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS courses (
  id            TEXT PRIMARY KEY,          -- look course_id
  title         TEXT NOT NULL,
  teacher       TEXT NOT NULL DEFAULT '',
  teachers_json TEXT NOT NULL DEFAULT '[]',
  college       TEXT NOT NULL DEFAULT '',
  term          TEXT NOT NULL DEFAULT '',  -- e.g. 20261
  thumb         TEXT NOT NULL DEFAULT '',
  start_at      INTEGER NOT NULL DEFAULT 0,
  end_at        INTEGER NOT NULL DEFAULT 0,
  lecture_total INTEGER NOT NULL DEFAULT 0,
  progress      REAL NOT NULL DEFAULT 0,
  last_sub_id   TEXT NOT NULL DEFAULT '',
  last_learn_at TEXT NOT NULL DEFAULT '',
  pinned        INTEGER NOT NULL DEFAULT 0,
  hidden        INTEGER NOT NULL DEFAULT 0,
  alias         TEXT NOT NULL DEFAULT '',  -- user-chosen display name
  color         TEXT NOT NULL DEFAULT '',  -- user-chosen seed color (#RRGGBB)
  dir           TEXT NOT NULL DEFAULT '',  -- folder relative to library root
  synced_at     INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS lectures (
  id           TEXT PRIMARY KEY,           -- look sub_id
  course_id    TEXT NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
  title        TEXT NOT NULL DEFAULT '',
  date         TEXT NOT NULL DEFAULT '',   -- YYYY-MM-DD
  begin_at     INTEGER NOT NULL DEFAULT 0,
  end_at       INTEGER NOT NULL DEFAULT 0,
  lecturer     TEXT NOT NULL DEFAULT '',
  room         TEXT NOT NULL DEFAULT '',
  has_playback INTEGER NOT NULL DEFAULT 0,
  duration_s   INTEGER NOT NULL DEFAULT 0,
  thumb        TEXT NOT NULL DEFAULT '',
  dir          TEXT NOT NULL DEFAULT '',
  synced_at    INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS lectures_by_course ON lectures(course_id, begin_at);

-- Local files belonging to a lecture. path is relative to the library root.
CREATE TABLE IF NOT EXISTS assets (
  lecture_id TEXT NOT NULL REFERENCES lectures(id) ON DELETE CASCADE,
  kind       TEXT NOT NULL CHECK (kind IN ('video','audio','slides','courseware','transcript','material')),
  path       TEXT NOT NULL,
  bytes      INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  meta_json  TEXT NOT NULL DEFAULT '{}',
  PRIMARY KEY (lecture_id, kind, path)
);

CREATE TABLE IF NOT EXISTS slides (
  lecture_id TEXT NOT NULL,
  idx        INTEGER NOT NULL,
  t_sec      INTEGER NOT NULL,
  is_key     INTEGER NOT NULL DEFAULT 0,
  remote_url TEXT NOT NULL DEFAULT '',
  path       TEXT NOT NULL DEFAULT '',
  PRIMARY KEY (lecture_id, idx)
);

-- Transcript utterances; segments_fts mirrors text for search.
CREATE TABLE IF NOT EXISTS segments (
  lecture_id TEXT NOT NULL,
  idx        INTEGER NOT NULL,
  start_ms   INTEGER NOT NULL,
  end_ms     INTEGER NOT NULL,
  text       TEXT NOT NULL,
  PRIMARY KEY (lecture_id, idx)
);
CREATE VIRTUAL TABLE IF NOT EXISTS segments_fts USING fts5(
  text, content='segments', content_rowid='rowid', tokenize='trigram');
CREATE TRIGGER IF NOT EXISTS segments_ai AFTER INSERT ON segments BEGIN
  INSERT INTO segments_fts(rowid, text) VALUES (new.rowid, new.text);
END;
CREATE TRIGGER IF NOT EXISTS segments_ad AFTER DELETE ON segments BEGIN
  INSERT INTO segments_fts(segments_fts, rowid, text) VALUES ('delete', old.rowid, old.text);
END;

-- Notes are Markdown files under notes/; body is cached here for search.
CREATE TABLE IF NOT EXISTS notes (
  id         TEXT PRIMARY KEY,
  course_id  TEXT NOT NULL DEFAULT '',
  lecture_id TEXT NOT NULL DEFAULT '',
  title      TEXT NOT NULL,
  body       TEXT NOT NULL DEFAULT '',
  source     TEXT NOT NULL DEFAULT 'user' CHECK (source IN ('user','agent')),
  pinned     INTEGER NOT NULL DEFAULT 0,
  path       TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
CREATE VIRTUAL TABLE IF NOT EXISTS notes_fts USING fts5(
  title, body, content='notes', content_rowid='rowid', tokenize='trigram');
CREATE TRIGGER IF NOT EXISTS notes_ai AFTER INSERT ON notes BEGIN
  INSERT INTO notes_fts(rowid, title, body) VALUES (new.rowid, new.title, new.body);
END;
CREATE TRIGGER IF NOT EXISTS notes_ad AFTER DELETE ON notes BEGIN
  INSERT INTO notes_fts(notes_fts, rowid, title, body) VALUES ('delete', old.rowid, old.title, old.body);
END;
CREATE TRIGGER IF NOT EXISTS notes_au AFTER UPDATE ON notes BEGIN
  INSERT INTO notes_fts(notes_fts, rowid, title, body) VALUES ('delete', old.rowid, old.title, old.body);
  INSERT INTO notes_fts(rowid, title, body) VALUES (new.rowid, new.title, new.body);
END;

-- Persistent task queue (downloads, transcription).
CREATE TABLE IF NOT EXISTS jobs (
  id          TEXT PRIMARY KEY,
  course_id   TEXT NOT NULL,
  lecture_id  TEXT NOT NULL,
  kind        TEXT NOT NULL,             -- video | slides | courseware | transcript
  title       TEXT NOT NULL DEFAULT '',
  state       TEXT NOT NULL,             -- queued | running | paused | done | failed | canceled
  done_bytes  INTEGER NOT NULL DEFAULT 0,
  total_bytes INTEGER NOT NULL DEFAULT 0,
  progress    REAL NOT NULL DEFAULT 0,
  error       TEXT NOT NULL DEFAULT '',
  created_at  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS jobs_by_state ON jobs(state, created_at);

CREATE TABLE IF NOT EXISTS playback (
  lecture_id  TEXT PRIMARY KEY,
  position_ms INTEGER NOT NULL,
  duration_ms INTEGER NOT NULL DEFAULT 0,
  speed       REAL NOT NULL DEFAULT 1,
  updated_at  INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS bookmarks (
  id         INTEGER PRIMARY KEY,
  lecture_id TEXT NOT NULL,
  t_ms       INTEGER NOT NULL,
  label      TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS bookmarks_by_lecture ON bookmarks(lecture_id, t_ms);

CREATE TABLE IF NOT EXISTS settings (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL                    -- JSON
);

-- Dated items (homework, exams, activities) marked by the user or the
-- assistant. quote keeps the words that mention the date; t_ms points at
-- them in the lecture recording (-1 when they came from elsewhere).
CREATE TABLE IF NOT EXISTS schedule (
  id         TEXT PRIMARY KEY,
  kind       TEXT NOT NULL DEFAULT 'task' CHECK (kind IN ('homework','exam','activity','deadline','task')),
  title      TEXT NOT NULL,
  detail     TEXT NOT NULL DEFAULT '',
  due_date   TEXT NOT NULL,              -- YYYY-MM-DD
  due_time   TEXT NOT NULL DEFAULT '',   -- HH:MM, empty for all-day
  course_id  TEXT NOT NULL DEFAULT '',
  lecture_id TEXT NOT NULL DEFAULT '',
  t_ms       INTEGER NOT NULL DEFAULT -1,
  quote      TEXT NOT NULL DEFAULT '',
  source     TEXT NOT NULL DEFAULT 'user' CHECK (source IN ('user','agent')),
  done       INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS schedule_by_date ON schedule(due_date);

-- Chapter outline of a lecture (mirrors timeline.txt in the lecture folder).
CREATE TABLE IF NOT EXISTS timeline (
  lecture_id TEXT NOT NULL,
  idx        INTEGER NOT NULL,
  start_ms   INTEGER NOT NULL,
  end_ms     INTEGER NOT NULL,
  title      TEXT NOT NULL,
  PRIMARY KEY (lecture_id, idx)
);

-- Study time per local day, reported by the app (docs/specs/0001-learning-activity-heatmap.md).
-- kind: watch | read | practice (seconds) or ask (count).
CREATE TABLE IF NOT EXISTS activity (
  day        TEXT NOT NULL,              -- YYYY-MM-DD, local time
  kind       TEXT NOT NULL,
  course_id  TEXT NOT NULL DEFAULT '',
  lecture_id TEXT NOT NULL DEFAULT '',
  seconds    INTEGER NOT NULL DEFAULT 0,
  count      INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (day, kind, course_id, lecture_id)
);

-- Ids of applied activity reports, so a retried report is counted once
-- (kept for store.ReportsKept; not mirrored).
CREATE TABLE IF NOT EXISTS activity_reports (
  id TEXT PRIMARY KEY,
  at INTEGER NOT NULL
);

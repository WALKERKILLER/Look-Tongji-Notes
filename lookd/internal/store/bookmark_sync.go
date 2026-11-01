package store

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"time"
)

// The numeric ID remains device-local; sync_id and tombstones travel.
func (s *Store) ensureBookmarkSync() error {
	rows, e := s.DB.Query(`PRAGMA table_info(bookmarks)`)
	if e != nil {
		return e
	}
	cols := map[string]bool{}
	for rows.Next() {
		var cid, notnull, pk int
		var name, typ string
		var def any
		if e = rows.Scan(&cid, &name, &typ, &notnull, &def, &pk); e != nil {
			rows.Close()
			return e
		}
		cols[name] = true
	}
	rows.Close()
	for _, c := range []struct{ name, ddl string }{{"sync_id", `ALTER TABLE bookmarks ADD COLUMN sync_id TEXT NOT NULL DEFAULT ''`}, {"updated_at", `ALTER TABLE bookmarks ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0`}, {"deleted", `ALTER TABLE bookmarks ADD COLUMN deleted INTEGER NOT NULL DEFAULT 0`}} {
		if !cols[c.name] {
			if _, e = s.DB.Exec(c.ddl); e != nil {
				return e
			}
		}
	}
	return nil
}
func bookmarkID(b Bookmark) string {
	sum := sha256.Sum256([]byte(fmt.Sprintf("%s\x00%d\x00%s\x00%d", b.LectureID, b.TMs, b.Label, b.CreatedAt)))
	return "legacy-" + hex.EncodeToString(sum[:])
}
func newBookmarkID() string { b := make([]byte, 16); rand.Read(b); return hex.EncodeToString(b) }
func (s *Store) DeleteBookmark(ctx context.Context, id int64) error {
	_, e := s.DB.ExecContext(ctx, `UPDATE bookmarks SET deleted=1,updated_at=? WHERE id=?`, time.Now().UnixMilli(), id)
	return e
}

package store

import (
	"context"
	"time"
)

// Mirror commits: a library write that changes the index and a JSON file
// together records a token in its transaction, so that recovery after a
// crash can tell whether a journaled file change belongs to committed index
// state (library.recoverMirrors).

// MirrorCommitsKept is how long tokens whose journal was lost are kept.
const MirrorCommitsKept = 7 * 24 * time.Hour

func markMirrorCommit(ctx context.Context, q querier, token string) error {
	if token == "" {
		return nil
	}
	_, err := q.ExecContext(ctx, `INSERT INTO mirror_commits(token, at) VALUES(?, ?)`, token, time.Now().Unix())
	return err
}

// MirrorCommitted reports whether the transaction that recorded token committed.
func (s *Store) MirrorCommitted(ctx context.Context, token string) (bool, error) {
	var n int
	err := s.DB.QueryRowContext(ctx, `SELECT count(*) FROM mirror_commits WHERE token = ?`, token).Scan(&n)
	return n > 0, err
}

// ForgetMirrorCommit drops token, and tokens older than MirrorCommitsKept.
func (s *Store) ForgetMirrorCommit(ctx context.Context, token string) error {
	_, err := s.DB.ExecContext(ctx, `DELETE FROM mirror_commits WHERE token = ? OR at < ?`, token, time.Now().Add(-MirrorCommitsKept).Unix())
	return err
}

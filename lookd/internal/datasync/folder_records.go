package datasync

import (
	"bufio"
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"io"
	"strings"
	"time"
)

// Merge only append-only, uniquely identified records. Changed records with the
// same ID remain a file conflict rather than being spliced into invalid history.
func mergeIdentified(groups [][]json.RawMessage) ([]json.RawMessage, bool) {
	seen := map[string]json.RawMessage{}
	out := []json.RawMessage{}
	for _, group := range groups {
		for _, raw := range group {
			var item map[string]json.RawMessage
			if json.Unmarshal(raw, &item) != nil {
				return nil, false
			}
			var id string
			json.Unmarshal(item["id"], &id)
			if id == "" {
				var canonical any
				json.Unmarshal(raw, &canonical)
				b, _ := json.Marshal(canonical)
				h := sha256.Sum256(b)
				id = hex.EncodeToString(h[:])
			}
			var canonical any
			json.Unmarshal(raw, &canonical)
			normalized, _ := json.Marshal(canonical)
			if old, ok := seen[id]; ok {
				if !bytes.Equal(old, normalized) {
					return nil, false
				}
				continue
			}
			seen[id] = normalized
			out = append(out, normalized)
		}
	}
	return out, true
}
func (s *Service) mergeFolderRecords(ctx context.Context, f *folderStorage, entries map[string]folderEntry) error {
	for p, v := range entries {
		if len(v.Alternatives) == 0 || (!strings.Contains(p, "/quizzes/") && !strings.Contains(p, "/assistant/")) {
			continue
		}
		versions := append([]Entry{v.Entry}, v.Alternatives...)
		contents := [][]byte{}
		for _, entry := range versions {
			if entry.Size > 32<<20 {
				contents = nil
				break
			}
			r, e := f.open(ctx, "objects/"+entry.Hash)
			if e != nil {
				return e
			}
			b, e := io.ReadAll(io.LimitReader(r, entry.Size+1))
			r.Close()
			if e != nil {
				return e
			}
			sum := sha256.Sum256(b)
			if int64(len(b)) != entry.Size || hex.EncodeToString(sum[:]) != entry.Hash {
				contents = nil
				break
			}
			contents = append(contents, b)
		}
		if len(contents) == 0 {
			continue
		}
		groups := [][]json.RawMessage{}
		var quiz map[string]json.RawMessage
		valid := true
		for _, b := range contents {
			if strings.Contains(p, "/quizzes/") {
				var doc map[string]json.RawMessage
				if json.Unmarshal(b, &doc) != nil {
					valid = false
					break
				}
				if quiz == nil {
					quiz = doc
				} else {
					var a, c map[string]any
					json.Unmarshal(quiz["quiz"], &a)
					json.Unmarshal(doc["quiz"], &c)
					for _, key := range []string{"attempts", "best", "last"} {
						delete(a, key)
						delete(c, key)
					}
					aa, _ := json.Marshal(a)
					cc, _ := json.Marshal(c)
					if !bytes.Equal(aa, cc) {
						valid = false
						break
					}
				}
				var attempts []json.RawMessage
				if json.Unmarshal(doc["attempts"], &attempts) != nil {
					valid = false
					break
				}
				groups = append(groups, attempts)
			} else {
				var records []json.RawMessage
				scan := bufio.NewScanner(bytes.NewReader(b))
				scan.Buffer(make([]byte, 4096), 4<<20)
				for scan.Scan() {
					if len(bytes.TrimSpace(scan.Bytes())) > 0 {
						records = append(records, append([]byte{}, scan.Bytes()...))
					}
				}
				if scan.Err() != nil {
					valid = false
					break
				}
				groups = append(groups, records)
			}
		}
		if !valid {
			continue
		}
		merged, ok := mergeIdentified(groups)
		if !ok {
			continue
		}
		var b []byte
		if quiz != nil {
			quiz["attempts"], _ = json.Marshal(merged)
			b, _ = json.Marshal(quiz)
		} else {
			for _, row := range merged {
				b = append(b, row...)
				b = append(b, '\n')
			}
		}
		sum := sha256.Sum256(b)
		hash := hex.EncodeToString(sum[:])
		if e := f.put(ctx, "objects/"+hash, bytes.NewReader(b)); e != nil {
			return e
		}
		v.Entry = Entry{Hash: hash, Size: int64(len(b)), MTime: time.Now().UnixMilli()}
		v.Alternatives = nil
		entries[p] = v
	}
	return nil
}

package asr

import (
	"strings"
	"unicode"
	"unicode/utf8"
)

// MergeChunkSeams removes repeated speech recognised in adjacent overlapping
// chunks. It also supports repairing previously saved pool output. Only cues
// that overlap in time across a 20-minute seam are candidates; repetition
// within one chunk or at different times is preserved.
func MergeChunkSeams(us []Utterance) []Utterance {
	out := make([]Utterance, 0, len(us))
	var owners []int64
	for _, u := range us {
		owner := (u.StartMs + u.EndMs) / (2 * chunkSec * 1000)
		if len(out) > 0 {
			i := len(out) - 1
			prev := &out[i]
			seam := max(owner, owners[i]) * chunkSec * 1000
			if (owner == owners[i]+1 || owners[i] == owner+1) && prev.EndMs-u.StartMs >= 1000 &&
				u.StartMs >= seam-overlapSec*1000 && prev.EndMs <= seam+overlapSec*1000 {
				if tail, ok := seamTail(prev.Text, u.Text); ok {
					prev.Text += tail
					prev.EndMs = max(prev.EndMs, u.EndMs)
					owners[i] = max(owner, owners[i])
					continue
				}
			}
		}
		out = append(out, u)
		owners = append(owners, owner)
	}
	return out
}

// Keep rune offsets so removing a recognised prefix cannot split UTF-8.
func speechRunes(s string) ([]rune, []int) {
	var text []rune
	var ends []int
	for i, r := range s {
		if unicode.IsPunct(r) || unicode.IsSpace(r) {
			continue
		}
		text = append(text, unicode.ToLower(r))
		ends = append(ends, i+len(string(r)))
	}
	return text, ends
}

func seamMatch(a, b []rune) bool {
	// A long shared phrase may differ by one model substitution. Short
	// phrases are insufficient evidence for deleting recognised speech.
	if len(a) != len(b) || len(a) < 10 {
		return false
	}
	allow := min(2, max(1, len(a)/25))
	for i := range a {
		if a[i] != b[i] {
			allow--
			if allow < 0 {
				return false
			}
		}
	}
	return true
}

func seamTail(previous, current string) (string, bool) {
	a, _ := speechRunes(previous)
	b, ends := speechRunes(current)
	if len(b) >= 10 && len(b) <= len(a) {
		for i := 0; i+len(b) <= len(a); i++ {
			if seamMatch(a[i:i+len(b)], b) {
				return "", true
			}
		}
	}
	for n := min(len(a), len(b)); n >= 10; n-- {
		if seamMatch(a[len(a)-n:], b[:n]) {
			tail := current[ends[n-1]:]
			last, _ := utf8.DecodeLastRuneInString(previous)
			if unicode.IsPunct(last) {
				tail = strings.TrimLeftFunc(tail, func(r rune) bool {
					return unicode.IsSpace(r) || strings.ContainsRune(",.;:!?，。；：！？、", r)
				})
			}
			first, _ := utf8.DecodeRuneInString(tail)
			if last < 128 && !unicode.IsSpace(last) && first < 128 && (unicode.IsLetter(first) || unicode.IsDigit(first)) {
				tail = " " + tail
			}
			return tail, true
		}
	}
	return "", false
}

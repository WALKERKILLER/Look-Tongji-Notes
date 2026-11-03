package store

import "strings"

// IsLocalCourse identifies the reserved namespace owned by the local library.
func IsLocalCourse(id string) bool { return strings.HasPrefix(id, "local-") }

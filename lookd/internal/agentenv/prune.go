package agentenv

import (
	"io/fs"
	"os"
	"path/filepath"
	"strings"
)

// Files Node.js and the agent never read at run time. Declarations and
// source maps are about half of the agent's node_modules; Node's C headers
// only serve native addons, which are never built (install scripts are off).
var pruneSuffixes = []string{
	".d.ts", ".d.mts", ".d.cts",
	".js.map", ".mjs.map", ".cjs.map", ".ts.map", ".mts.map", ".cts.map", ".css.map",
}

// PruneModules deletes TypeScript declarations and source maps under a
// node_modules folder and returns the bytes freed.
func PruneModules(dir string) int64 {
	var freed int64
	filepath.WalkDir(dir, func(p string, d fs.DirEntry, err error) error {
		if err != nil || !d.Type().IsRegular() {
			return nil
		}
		name := d.Name()
		for _, s := range pruneSuffixes {
			if strings.HasSuffix(name, s) {
				if info, err := d.Info(); err == nil && os.Remove(p) == nil {
					freed += info.Size()
				}
				break
			}
		}
		return nil
	})
	return freed
}

// PruneNode deletes the headers and docs of an unpacked Node.js release.
func PruneNode(dir string) int64 {
	var freed int64
	for _, rel := range []string{"include", "share/doc", "CHANGELOG.md"} {
		p := filepath.Join(dir, rel)
		freed += size(p)
		os.RemoveAll(p)
	}
	return freed
}

func size(p string) int64 {
	var n int64
	filepath.WalkDir(p, func(_ string, d fs.DirEntry, err error) error {
		if err == nil && d.Type().IsRegular() {
			if info, err := d.Info(); err == nil {
				n += info.Size()
			}
		}
		return nil
	})
	return n
}

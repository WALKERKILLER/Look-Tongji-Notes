package server

import (
	"strings"
	"testing"

	"lookstudio/lookd/internal/store"
)

func TestMergeScheduleKeepsStoreOrder(t *testing.T) {
	a := []store.ScheduleItem{{ID: "u1", DueDate: "2026-10-22"}, {ID: "u2", DueDate: "2026-10-23", DueTime: "09:00"}}
	b := []store.ScheduleItem{{ID: "canvas:1", DueDate: "2026-10-23", DueTime: "08:00"}, {ID: "canvas:2", DueDate: "2026-10-21", DueTime: "23:59"}}
	var ids []string
	for _, it := range mergeSchedule(a, b) {
		ids = append(ids, it.ID)
	}
	if got := strings.Join(ids, ","); got != "canvas:2,u1,canvas:1,u2" {
		t.Fatal(got)
	}
	if !isCanvasItem("canvas:1") || isCanvasItem("abc") {
		t.Fatal("isCanvasItem")
	}
}

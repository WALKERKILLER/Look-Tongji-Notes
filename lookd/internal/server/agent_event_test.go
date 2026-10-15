package server

import (
	"net/http/httptest"
	"strings"
	"testing"

	"lookstudio/lookd/internal/events"
)

func TestAgentEventTypes(t *testing.T) {
	s := &Server{Bus: events.New()}
	ch, unsub := s.Bus.Subscribe()
	defer unsub()
	cases := []struct {
		body string
		bad  bool
	}{
		{`{"type":"agent_task","data":{"phase":"finished"}}`, false},
		{`{"type":"plugin_event","data":{"plugin":"socratic","kind":"notify","text":"hi"}}`, false},
		{`{"type":"notes_changed","data":{}}`, true},
		{`{"type":"plugin_event","data":[1]}`, true},
		{`{"type":"plugin_event","data":{"text":"` + strings.Repeat("x", 70<<10) + `"}}`, true},
	}
	for _, c := range cases {
		_, err := s.agentEvent(nil, httptest.NewRequest("POST", "/api/agent/event", strings.NewReader(c.body)))
		if (err != nil) != c.bad {
			t.Errorf("%.60s: err=%v", c.body, err)
		}
	}
	if got := len(ch); got != 2 {
		t.Fatalf("published %d events, want 2", got)
	}
}

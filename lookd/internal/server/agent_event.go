package server

import (
	"encoding/json"
	"net/http"
)

// agentEvent relays agent host events to app clients over the event bus.
// Only scheduled task progress is accepted (docs/specs/0003-scheduled-agent-tasks.md).
func (s *Server) agentEvent(_ http.ResponseWriter, r *http.Request) (any, error) {
	var in struct {
		Type string          `json:"type"`
		Data json.RawMessage `json:"data"`
	}
	if err := decode(r, &in); err != nil {
		return nil, err
	}
	if in.Type != "agent_task" {
		return nil, badRequest("type 只能是 agent_task")
	}
	var data map[string]any
	if err := json.Unmarshal(in.Data, &data); err != nil {
		return nil, badRequest("data 应为对象")
	}
	s.Bus.Publish(in.Type, data)
	return ok(), nil
}

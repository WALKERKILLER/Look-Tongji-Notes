package server

import (
	"encoding/json"
	"net/http"
)

// agentEvents are the event types the agent host may publish: scheduled task
// progress (docs/specs/0003-scheduled-agent-tasks.md) and plugin notices
// (docs/specs/0004-plugin-platform.md).
var agentEvents = map[string]bool{"agent_task": true, "plugin_event": true}

// agentEvent relays agent host events to app clients over the event bus.
func (s *Server) agentEvent(_ http.ResponseWriter, r *http.Request) (any, error) {
	var in struct {
		Type string          `json:"type"`
		Data json.RawMessage `json:"data"`
	}
	if err := decode(r, &in); err != nil {
		return nil, err
	}
	if !agentEvents[in.Type] {
		return nil, badRequest("type 只能是 agent_task 或 plugin_event")
	}
	if len(in.Data) > 64<<10 {
		return nil, badRequest("data 过大")
	}
	var data map[string]any
	if err := json.Unmarshal(in.Data, &data); err != nil {
		return nil, badRequest("data 应为对象")
	}
	s.Bus.Publish(in.Type, data)
	return ok(), nil
}

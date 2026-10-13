// Package events fans out daemon events to SSE subscribers.
package events

import (
	"encoding/json"
	"sync"
)

type Event struct {
	Type string `json:"type"`
	Data any    `json:"data"`
}

type Bus struct {
	mu   sync.Mutex
	subs map[chan []byte]struct{}
}

func New() *Bus { return &Bus{subs: map[chan []byte]struct{}{}} }

func (b *Bus) Publish(typ string, data any) {
	msg, err := json.Marshal(Event{Type: typ, Data: data})
	if err != nil {
		return
	}
	b.mu.Lock()
	defer b.mu.Unlock()
	for ch := range b.subs {
		select {
		case ch <- msg:
		default: // slow subscriber: drop rather than block the daemon
		}
	}
}

func (b *Bus) Subscribe() (chan []byte, func()) {
	ch := make(chan []byte, 256)
	b.mu.Lock()
	b.subs[ch] = struct{}{}
	b.mu.Unlock()
	return ch, func() {
		b.mu.Lock()
		delete(b.subs, ch)
		b.mu.Unlock()
	}
}

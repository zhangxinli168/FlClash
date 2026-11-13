package core

import (
	"github.com/metacubex/mihomo/adapter/outbound"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel"
)

// WireGuardResetParams narrows a reset to one outbound, or asks for the slow
// rebuild instead of the socket swap.
type WireGuardResetParams struct {
	Name string `json:"name,omitempty"`
	Full bool   `json:"full,omitempty"`
}

func handleWireGuardStatus() []outbound.WireGuardStatus {
	statuses := make([]outbound.WireGuardStatus, 0, 2)
	for _, proxy := range tunnel.AllProxies() {
		wg, ok := outbound.AsWireGuard(proxy.Adapter())
		if !ok {
			continue
		}
		statuses = append(statuses, wg.Status())
	}
	return statuses
}

// handleWireGuardReset drops the transport of every WireGuard outbound (or of
// the named one) so the next packet leaves through the network that is current
// now. A full reset rebuilds the device and can block for its init timeout, so
// the work outlives the answer instead of stalling the caller.
func handleWireGuardReset(params WireGuardResetParams) error {
	targets := make([]*outbound.WireGuard, 0, 2)
	for _, proxy := range tunnel.AllProxies() {
		wg, ok := outbound.AsWireGuard(proxy.Adapter())
		if !ok {
			continue
		}
		if params.Name != "" && wg.Name() != params.Name {
			continue
		}
		targets = append(targets, wg)
	}
	if len(targets) == 0 {
		return nil
	}
	safeGo("resetWireGuard", func() {
		for _, wg := range targets {
			var err error
			if params.Full {
				err = wg.ResetFull()
			} else {
				err = wg.Reset()
			}
			if err != nil {
				logError("[WG](%s) reset on request failed: %s", wg.Name(), err)
				continue
			}
			log.Infoln("[WG](%s) reset on request", wg.Name())
		}
	})
	return nil
}

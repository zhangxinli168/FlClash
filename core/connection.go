package core

import (
	"sync/atomic"
	"time"

	"github.com/metacubex/mihomo/adapter/outbound"
	"github.com/metacubex/mihomo/component/resolver"
	"github.com/metacubex/mihomo/dns"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

func handleGetTraffic(params TrafficParams) Traffic {
	up, down := statistic.DefaultManager.NowTraffic(params.OnlyProxy)
	return Traffic{Up: up, Down: down}
}

func handleGetTotalTraffic(params TrafficParams) Traffic {
	up, down := statistic.DefaultManager.TotalTraffic(params.OnlyProxy)
	return Traffic{Up: up, Down: down}
}

func handleResetTraffic() {
	statistic.DefaultManager.ResetStatistic()
}

func handleGetConnections() *statistic.Snapshot {
	return statistic.DefaultManager.Snapshot()
}

func handleGetConnectionCount() int {
	count := 0
	statistic.DefaultManager.Range(func(statistic.Tracker) bool {
		count++
		return true
	})
	return count
}

func handleCloseConnections() {
	statistic.DefaultManager.Range(func(c statistic.Tracker) bool {
		_ = c.Close()
		return true
	})
}

func handleResetConnections() {
	resolver.ResetConnection()
}

// A network change clears rather than waits out the TTLs: mihomo serves an
// expired entry once more before it refreshes it.
func handleClearDnsCache() {
	configMu.Lock()
	defer configMu.Unlock()
	dns.ClearAll()
}

// handleNetworkChanged is how the desktop host reports a new network, which
// Android's NetworkObserver reports through handleResetNetwork.
func handleNetworkChanged() {
	handleClearDnsCache()
	// Desktop has no NetworkObserver: a switch reaches the Core as this method
	// alone, so the WireGuard transports are dropped here too.
	resetWireGuard()
}

// A connection that went out over a network the device has left hangs until
// TCP gives up on it, and so do the DNS clients' pooled connections.
func handleResetNetwork() {
	handleCloseConnections()
	handleNetworkChanged()
	resetWireGuard()
}

var lastWireGuardReset atomic.Int64

// wireGuardResetDebounceMillis collapses one network switch into one reset: the
// switch arrives as several callbacks, and each of them would otherwise rebuild
// the sockets.
const wireGuardResetDebounceMillis = 1000

// resetWireGuard drops the transport sockets of every WireGuard outbound so the
// next packet rebinds them to the network that is current now.
//
// Closing connections is not enough for them. A WireGuard outbound holds its own
// UDP socket, created once and reused forever, and Android binds such a socket
// to an underlying network at the moment it is protected and never migrates it.
// After a Wi-Fi <-> cellular switch the socket keeps writing into a network that
// is gone — writes still succeed, so nothing retries, and the tunnel stays dark
// until the app restarts. Replacing the socket is the only thing that helps.
func resetWireGuard() {
	log.Debugln("[WG] resetWireGuard scan %d proxies", len(tunnel.AllProxies()))
	now := time.Now().UnixMilli()
	if previous := lastWireGuardReset.Swap(now); previous != 0 && now-previous < wireGuardResetDebounceMillis {
		log.Debugln("[WG] skip duplicated reset")
		return
	}
	for _, proxy := range tunnel.AllProxies() {
		wg, ok := outbound.AsWireGuard(proxy.Adapter())
		if !ok {
			log.Debugln("[WG] skip %s as %T", proxy.Name(), proxy.Adapter())
			continue
		}
		if err := wg.Reconnect(); err != nil {
			log.Warnln("[WG](%s) reconnect after network change failed: %s", wg.Name(), err)
			continue
		}
		log.Infoln("[WG](%s) reconnected after network change", wg.Name())
	}
}

// A connection that is already gone is closed as far as the host is concerned.
func handleCloseConnection(params IDParams) error {
	if c := statistic.DefaultManager.Get(params.ID); c != nil {
		_ = c.Close()
	}
	return nil
}

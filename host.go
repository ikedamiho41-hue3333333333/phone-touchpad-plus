/*
 *    Copyright (c) 2018 Unrud <unrud@outlook.com>
 *    Copyright (c) 2026 Phone Touchpad Plus contributors
 *
 *    This file is part of Phone Touchpad Plus, based on Remote-Touchpad.
 *    It is distributed under the GNU General Public License, version 3 or
 *    (at your option) any later version.
 */

package main

import (
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"sort"
	"strings"
)

type hostCandidate struct {
	Name         string
	IP           net.IP
	Flags        net.Flags
	DefaultRoute bool
}

type rankedHost struct {
	host  string
	name  string
	score int
}

var virtualInterfacePrefixes = []string{
	"tun", "tap", "wg", "tailscale", "docker", "br-", "veth", "virbr", "zt",
	"utun", "ppp", "vpn",
}

func isVirtualInterface(name string) bool {
	lowerName := strings.ToLower(name)
	for _, prefix := range virtualInterfacePrefixes {
		if strings.HasPrefix(lowerName, prefix) {
			return true
		}
	}
	return false
}

func candidateScore(candidate hostCandidate) (int, bool) {
	if candidate.Flags&net.FlagUp == 0 || candidate.Flags&net.FlagLoopback != 0 ||
		isVirtualInterface(candidate.Name) || candidate.IP == nil ||
		candidate.IP.IsUnspecified() || candidate.IP.IsLoopback() ||
		candidate.IP.IsLinkLocalUnicast() || candidate.IP.IsLinkLocalMulticast() ||
		candidate.IP.IsMulticast() {
		return 0, false
	}

	score := 0
	if candidate.IP.To4() != nil {
		if candidate.IP.IsPrivate() {
			score = 4000
		} else if candidate.IP.IsGlobalUnicast() {
			score = 3000
		}
	} else if candidate.IP.IsPrivate() {
		score = 2000
	} else if candidate.IP.IsGlobalUnicast() {
		score = 1000
	}
	if score == 0 {
		return 0, false
	}
	if candidate.DefaultRoute {
		score += 100
	}
	return score, true
}

func selectHosts(candidates []hostCandidate) (string, []string, error) {
	observed := make([]string, 0, len(candidates))
	ranked := make([]rankedHost, 0, len(candidates))
	seenObserved := make(map[string]bool)
	seenEligible := make(map[string]bool)
	for _, candidate := range candidates {
		if candidate.IP == nil {
			continue
		}
		host := candidate.IP.String()
		if !seenObserved[host] {
			observed = append(observed, host)
			seenObserved[host] = true
		}
		score, eligible := candidateScore(candidate)
		if !eligible || seenEligible[host] {
			continue
		}
		seenEligible[host] = true
		ranked = append(ranked, rankedHost{host: host, name: candidate.Name, score: score})
	}
	if len(ranked) == 0 {
		return "", observed, errors.New("no reachable LAN address found")
	}
	sort.Slice(ranked, func(i, j int) bool {
		if ranked[i].score != ranked[j].score {
			return ranked[i].score > ranked[j].score
		}
		if ranked[i].name != ranked[j].name {
			return ranked[i].name < ranked[j].name
		}
		return ranked[i].host < ranked[j].host
	})
	alternatives := make([]string, 0, len(ranked)-1)
	for _, candidate := range ranked[1:] {
		alternatives = append(alternatives, candidate.host)
	}
	return ranked[0].host, alternatives, nil
}

func preferMDNSHost(hostname string, resolved []net.IP, primary string, alternatives []string) (string, []string) {
	primaryIP := net.ParseIP(primary)
	if hostname == "" || primaryIP == nil {
		return primary, alternatives
	}
	for _, ip := range resolved {
		if ip.Equal(primaryIP) {
			return hostname, append([]string{primary}, alternatives...)
		}
	}
	return primary, alternatives
}

func findDefaultHosts() (string, []string, error) {
	defaultInterface := defaultRouteInterface()
	interfaces, err := net.Interfaces()
	if err != nil {
		return "", nil, fmt.Errorf("list network interfaces: %w", err)
	}
	candidates := make([]hostCandidate, 0)
	for _, networkInterface := range interfaces {
		addresses, addressErr := networkInterface.Addrs()
		if addressErr != nil {
			continue
		}
		for _, address := range addresses {
			ip, _, parseErr := net.ParseCIDR(address.String())
			if parseErr != nil {
				continue
			}
			candidates = append(candidates, hostCandidate{
				Name:         networkInterface.Name,
				IP:           ip,
				Flags:        networkInterface.Flags,
				DefaultRoute: networkInterface.Name == defaultInterface,
			})
		}
	}
	primary, alternatives, err := selectHosts(candidates)
	if err != nil {
		return primary, alternatives, err
	}
	hostname, hostnameErr := os.Hostname()
	if hostnameErr == nil && hostname != "" {
		mdnsHost := strings.TrimSuffix(hostname, ".local") + ".local"
		if resolved, lookupErr := net.LookupIP(mdnsHost); lookupErr == nil {
			primary, alternatives = preferMDNSHost(mdnsHost, resolved, primary, alternatives)
		}
	}
	return primary, alternatives, nil
}

func writeHosts(w io.Writer, primary string, alternatives []string) error {
	seen := make(map[string]bool)
	for _, host := range append([]string{primary}, alternatives...) {
		if host == "" || seen[host] {
			continue
		}
		seen[host] = true
		if _, err := fmt.Fprintln(w, host); err != nil {
			return err
		}
	}
	return nil
}

package main

import (
	"bytes"
	"net"
	"reflect"
	"strings"
	"testing"
)

func TestWriteHostsPrintsPrimaryThenUniqueAlternatives(t *testing.T) {
	var output bytes.Buffer
	if err := writeHosts(&output, "desktop.local", []string{"192.168.31.8", "192.168.31.8"}); err != nil {
		t.Fatal(err)
	}
	if got, want := output.String(), "desktop.local\n192.168.31.8\n"; got != want {
		t.Fatalf("writeHosts output = %q, want %q", got, want)
	}
}

func TestSelectHostsPrefersDefaultPrivateIPv4AndExcludesVirtualInterfaces(t *testing.T) {
	candidates := []hostCandidate{
		{Name: "tun0", IP: net.ParseIP("198.18.0.1"), Flags: net.FlagUp, DefaultRoute: true},
		{Name: "docker0", IP: net.ParseIP("172.17.0.1"), Flags: net.FlagUp},
		{Name: "eth0", IP: net.ParseIP("10.0.0.9"), Flags: net.FlagUp},
		{Name: "wlan0", IP: net.ParseIP("192.168.31.8"), Flags: net.FlagUp, DefaultRoute: true},
	}

	primary, alternatives, err := selectHosts(candidates)
	if err != nil {
		t.Fatal(err)
	}
	if primary != "192.168.31.8" {
		t.Fatalf("primary = %q, want %q", primary, "192.168.31.8")
	}
	if want := []string{"10.0.0.9"}; !reflect.DeepEqual(alternatives, want) {
		t.Fatalf("alternatives = %#v, want %#v", alternatives, want)
	}
}

func TestSelectHostsRejectsVirtualLoopbackAndLinkLocalCandidates(t *testing.T) {
	tests := []hostCandidate{
		{Name: "tap0", IP: net.ParseIP("10.0.0.2"), Flags: net.FlagUp},
		{Name: "wg0", IP: net.ParseIP("10.0.0.2"), Flags: net.FlagUp},
		{Name: "tailscale0", IP: net.ParseIP("100.64.0.2"), Flags: net.FlagUp},
		{Name: "br-test", IP: net.ParseIP("172.18.0.1"), Flags: net.FlagUp},
		{Name: "veth123", IP: net.ParseIP("172.18.0.2"), Flags: net.FlagUp},
		{Name: "virbr0", IP: net.ParseIP("192.168.122.1"), Flags: net.FlagUp},
		{Name: "ztabc", IP: net.ParseIP("10.1.0.2"), Flags: net.FlagUp},
		{Name: "lo", IP: net.ParseIP("127.0.0.1"), Flags: net.FlagUp | net.FlagLoopback},
		{Name: "wlan0", IP: net.ParseIP("169.254.1.2"), Flags: net.FlagUp},
		{Name: "wlan0", IP: net.ParseIP("fe80::1"), Flags: net.FlagUp},
	}
	for _, candidate := range tests {
		t.Run(candidate.Name+"-"+candidate.IP.String(), func(t *testing.T) {
			if primary, _, err := selectHosts([]hostCandidate{candidate}); err == nil {
				t.Fatalf("selectHosts() chose %q, want error", primary)
			}
		})
	}
}

func TestSelectHostsPrefersPrivateIPv4OverGlobalIPv6(t *testing.T) {
	primary, alternatives, err := selectHosts([]hostCandidate{
		{Name: "eth0", IP: net.ParseIP("2001:db8::10"), Flags: net.FlagUp},
		{Name: "wlan0", IP: net.ParseIP("192.168.50.10"), Flags: net.FlagUp},
	})
	if err != nil {
		t.Fatal(err)
	}
	if primary != "192.168.50.10" {
		t.Fatalf("primary = %q, want private IPv4", primary)
	}
	if want := []string{}; !reflect.DeepEqual(alternatives, want) {
		t.Fatalf("alternatives = %#v, want %#v", alternatives, want)
	}
}

func TestSelectHostsRejectsGlobalOnlyCandidate(t *testing.T) {
	const globalAddress = "203.0.113.10"
	primary, observed, err := selectHosts([]hostCandidate{
		{Name: "eth0", IP: net.ParseIP(globalAddress), Flags: net.FlagUp, DefaultRoute: true},
	})
	if err == nil || !strings.Contains(err.Error(), "no reachable LAN address") {
		t.Fatalf("error = %v, want descriptive LAN error", err)
	}
	if primary != "" {
		t.Fatalf("primary = %q, want empty", primary)
	}
	if want := []string{globalAddress}; !reflect.DeepEqual(observed, want) {
		t.Fatalf("observed candidates = %#v, want %#v", observed, want)
	}
}

func TestSelectHostsReturnsObservedCandidatesWhenNoneAreEligible(t *testing.T) {
	primary, alternatives, err := selectHosts([]hostCandidate{
		{Name: "wlan0", IP: net.ParseIP("192.0.2.10"), Flags: 0},
		{Name: "lo", IP: net.ParseIP("127.0.0.1"), Flags: net.FlagUp | net.FlagLoopback},
	})
	if err == nil || !strings.Contains(err.Error(), "no reachable LAN address") {
		t.Fatalf("error = %v, want descriptive LAN error", err)
	}
	if primary != "" {
		t.Fatalf("primary = %q, want empty", primary)
	}
	if want := []string{"192.0.2.10", "127.0.0.1"}; !reflect.DeepEqual(alternatives, want) {
		t.Fatalf("observed candidates = %#v, want %#v", alternatives, want)
	}
}

func TestPreferMDNSHostOnlyWhenItResolvesToPrimary(t *testing.T) {
	primary, alternatives := preferMDNSHost(
		"desktop.local",
		[]net.IP{net.ParseIP("192.168.31.8")},
		"192.168.31.8",
		[]string{"10.0.0.9"},
	)
	if primary != "desktop.local" {
		t.Fatalf("primary = %q, want mDNS host", primary)
	}
	if want := []string{"192.168.31.8", "10.0.0.9"}; !reflect.DeepEqual(alternatives, want) {
		t.Fatalf("alternatives = %#v, want %#v", alternatives, want)
	}

	primary, alternatives = preferMDNSHost(
		"desktop.local",
		[]net.IP{net.ParseIP("192.168.31.99")},
		"192.168.31.8",
		[]string{"10.0.0.9"},
	)
	if primary != "192.168.31.8" || !reflect.DeepEqual(alternatives, []string{"10.0.0.9"}) {
		t.Fatalf("unmatched mDNS changed hosts: %q %#v", primary, alternatives)
	}
}

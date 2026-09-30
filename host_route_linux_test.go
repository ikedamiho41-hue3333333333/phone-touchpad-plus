//go:build linux

package main

import (
	"strings"
	"testing"
)

func TestParseDefaultRouteInterface(t *testing.T) {
	fixture := "Iface\tDestination\tGateway\tFlags\tRefCnt\tUse\tMetric\tMask\tMTU\tWindow\tIRTT\n" +
		"wlan0\t00000000\t0131A8C0\t0003\t0\t0\t600\t00000000\t0\t0\t0\n" +
		"docker0\t000011AC\t00000000\t0001\t0\t0\t0\t00FFFFFF\t0\t0\t0\n"
	got, err := parseDefaultRouteInterface(strings.NewReader(fixture))
	if err != nil {
		t.Fatal(err)
	}
	if got != "wlan0" {
		t.Fatalf("interface = %q, want %q", got, "wlan0")
	}
}

func TestParseDefaultRouteInterfaceRejectsMalformedRows(t *testing.T) {
	fixture := "Iface\tDestination\tGateway\tFlags\n" +
		"wlan0\t00000000\tgateway\tnot-hex\n"
	if _, err := parseDefaultRouteInterface(strings.NewReader(fixture)); err == nil {
		t.Fatal("parseDefaultRouteInterface() succeeded, want error")
	}
}

func TestParseDefaultRouteInterfaceReportsMissingRoute(t *testing.T) {
	fixture := "Iface\tDestination\tGateway\tFlags\n" +
		"wlan0\t0031A8C0\t00000000\t0001\n"
	if _, err := parseDefaultRouteInterface(strings.NewReader(fixture)); err == nil {
		t.Fatal("parseDefaultRouteInterface() succeeded, want missing-route error")
	}
}

//go:build !linux

package main

func defaultRouteInterface() string {
	return ""
}

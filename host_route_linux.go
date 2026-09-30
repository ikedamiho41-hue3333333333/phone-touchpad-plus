//go:build linux

package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"
)

func parseDefaultRouteInterface(reader io.Reader) (string, error) {
	scanner := bufio.NewScanner(reader)
	for scanner.Scan() {
		fields := strings.Fields(scanner.Text())
		if len(fields) == 0 || fields[0] == "Iface" {
			continue
		}
		if len(fields) < 4 {
			return "", fmt.Errorf("malformed route row: expected at least 4 fields")
		}
		if fields[1] != "00000000" {
			continue
		}
		flags, err := strconv.ParseUint(fields[3], 16, 32)
		if err != nil {
			return "", fmt.Errorf("malformed default route flags: %w", err)
		}
		if flags&1 != 0 {
			return fields[0], nil
		}
	}
	if err := scanner.Err(); err != nil {
		return "", fmt.Errorf("read route table: %w", err)
	}
	return "", fmt.Errorf("default route not found")
}

func defaultRouteInterface() string {
	file, err := os.Open("/proc/net/route")
	if err != nil {
		return ""
	}
	defer file.Close()
	name, err := parseDefaultRouteInterface(file)
	if err != nil {
		return ""
	}
	return name
}

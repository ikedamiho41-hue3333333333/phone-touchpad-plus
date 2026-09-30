package main

import (
	"errors"
	"fmt"
	"io"
	"net/url"
	"os"
	"strings"

	qrcode "github.com/skip2/go-qrcode"
)

func run(args []string, stdin io.Reader) error {
	if len(args) != 1 {
		return errors.New("usage: phone-touchpad-plus-makeqr OUTPUT.png (URL is read from stdin)")
	}
	content, err := io.ReadAll(io.LimitReader(stdin, 8193))
	if err != nil {
		return fmt.Errorf("read pairing URL: %w", err)
	}
	if len(content) > 8192 {
		return errors.New("pairing URL is too long")
	}
	pairingURL := strings.TrimSuffix(string(content), "\n")
	pairingURL = strings.TrimSuffix(pairingURL, "\r")
	parsed, err := url.Parse(pairingURL)
	if err != nil || (parsed.Scheme != "http" && parsed.Scheme != "https") ||
		parsed.Host == "" || parsed.Fragment == "" {
		return errors.New("invalid pairing URL")
	}
	if err := qrcode.WriteFile(pairingURL, qrcode.Medium, 768, args[0]); err != nil {
		return fmt.Errorf("write QR code: %w", err)
	}
	return nil
}

func main() {
	if err := run(os.Args[1:], os.Stdin); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(2)
	}
}

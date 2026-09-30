package main

import (
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/ikedamiho41-hue3333333333/phone-touchpad-plus/terminal"
)

func resolveSecret(secretArg, secretFile string) (string, error) {
	if secretArg != "" && secretFile != "" {
		return "", errors.New("only one secret source may be configured")
	}
	secret := secretArg
	if secretFile != "" {
		content, err := os.ReadFile(secretFile)
		if err != nil {
			return "", fmt.Errorf("read secret file: %w", err)
		}
		secret = string(content)
		if strings.HasSuffix(secret, "\r\n") {
			secret = strings.TrimSuffix(secret, "\r\n")
		} else {
			secret = strings.TrimSuffix(secret, "\n")
		}
	}
	if secret == "" && (secretArg != "" || secretFile != "") {
		return "", errors.New("secret must not be empty")
	}
	if strings.ContainsAny(secret, "\r\n") {
		return "", errors.New("secret must be a single line")
	}
	return secret, nil
}

func generateSecret(reader io.Reader, byteLength int) (string, error) {
	if byteLength <= 0 {
		return "", errors.New("secret length must be positive")
	}
	content := make([]byte, byteLength)
	if _, err := io.ReadFull(reader, content); err != nil {
		return "", fmt.Errorf("generate secret: %w", err)
	}
	return base64.StdEncoding.EncodeToString(content), nil
}

func maybeWritePairingOutput(w io.Writer, pairingURL string, colorize, enabled bool) error {
	if !enabled {
		return nil
	}
	if _, err := fmt.Fprintln(w, pairingURL); err != nil {
		return err
	}
	qrCode, err := terminal.GenerateQRCode(pairingURL, colorize)
	if err != nil {
		return fmt.Errorf("generate QR code: %w", err)
	}
	if _, err := fmt.Fprint(w, qrCode); err != nil {
		return err
	}
	return nil
}

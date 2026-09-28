package main

import (
	"bytes"
	"encoding/base64"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func writeSecretFixture(t *testing.T, content string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "secret")
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestResolveSecretNormalizesOneTrailingLineEnding(t *testing.T) {
	for _, ending := range []string{"\n", "\r\n"} {
		t.Run(base64.StdEncoding.EncodeToString([]byte(ending)), func(t *testing.T) {
			path := writeSecretFixture(t, "file-secret"+ending)
			got, err := resolveSecret("", path)
			if err != nil {
				t.Fatal(err)
			}
			if got != "file-secret" {
				t.Fatalf("resolveSecret() = %q, want %q", got, "file-secret")
			}
		})
	}
}

func TestResolveSecretRejectsUnsafeInputsWithoutLeakingThem(t *testing.T) {
	const sensitive = "do-not-print-this-secret"
	tests := []struct {
		name       string
		secretArg  string
		secretFile func(*testing.T) string
	}{
		{name: "empty file", secretFile: func(t *testing.T) string { return writeSecretFixture(t, "") }},
		{name: "embedded newline", secretFile: func(t *testing.T) string { return writeSecretFixture(t, sensitive+"\nextra") }},
		{name: "missing file", secretFile: func(t *testing.T) string { return filepath.Join(t.TempDir(), "missing") }},
		{name: "conflicting sources", secretArg: sensitive, secretFile: func(t *testing.T) string { return writeSecretFixture(t, "file-value") }},
		{name: "command-line newline", secretArg: sensitive + "\nextra", secretFile: func(*testing.T) string { return "" }},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			_, err := resolveSecret(test.secretArg, test.secretFile(t))
			if err == nil {
				t.Fatal("resolveSecret() succeeded, want error")
			}
			if strings.Contains(err.Error(), sensitive) || strings.Contains(err.Error(), "file-value") {
				t.Fatalf("error leaked secret: %q", err)
			}
		})
	}
}

func TestGenerateSecretReadsExactByteCount(t *testing.T) {
	source := []byte{0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12}
	got, err := generateSecret(bytes.NewReader(source), 12)
	if err != nil {
		t.Fatal(err)
	}
	want := "AAECAwQFBgcICQoL"
	if got != want {
		t.Fatalf("generateSecret() = %q, want %q", got, want)
	}
}

func TestPairingOutputDisabledWritesNothing(t *testing.T) {
	const pairingURL = "http://phone-touchpad-plus.local:8765/#do-not-print-this-secret"
	var output bytes.Buffer
	if err := maybeWritePairingOutput(&output, pairingURL, false, false); err != nil {
		t.Fatal(err)
	}
	if output.Len() != 0 {
		t.Fatalf("disabled pairing output wrote %q", output.String())
	}
}

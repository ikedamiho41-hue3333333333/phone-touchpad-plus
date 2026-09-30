package main

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"
)

func TestRunReadsPairingURLFromStdin(t *testing.T) {
	output := filepath.Join(t.TempDir(), "pairing.png")
	const pairingURL = "http://phone-touchpad-plus.example:8765/#test-fixture-secret" // TEST-FIXTURE
	if err := run([]string{output}, bytes.NewBufferString(pairingURL+"\n")); err != nil {
		t.Fatal(err)
	}
	content, err := os.ReadFile(output)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.HasPrefix(content, []byte("\x89PNG\r\n\x1a\n")) {
		t.Fatalf("output does not have PNG signature: %x", content[:min(8, len(content))])
	}
}

func TestRunRejectsURLAsCommandLineArgument(t *testing.T) {
	if err := run([]string{"http://example.invalid/#secret", "pairing.png"}, bytes.NewReader(nil)); err == nil {
		t.Fatal("run() accepted pairing URL in command-line arguments")
	}
}

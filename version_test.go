package main

import (
	"bytes"
	"testing"
)

func TestWriteVersion(t *testing.T) {
	var output bytes.Buffer
	if err := writeVersion(&output); err != nil {
		t.Fatal(err)
	}
	if got, want := output.String(), "0.1.0\n"; got != want {
		t.Fatalf("writeVersion output = %q, want %q", got, want)
	}
}

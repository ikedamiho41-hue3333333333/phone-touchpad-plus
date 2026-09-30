package main

import (
	"errors"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/ikedamiho41-hue3333333333/phone-touchpad-plus/internal/protocol"
	"golang.org/x/net/websocket"
)

func writeProbeSecret(t *testing.T, secret string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "secret")
	if err := os.WriteFile(path, []byte(secret+"\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	return path
}

func authenticatedWebSocketServer(t *testing.T, secret string) string {
	t.Helper()
	server := httptest.NewServer(websocket.Handler(func(connection *websocket.Conn) {
		const challenge = "probe-test-challenge"
		if err := websocket.Message.Send(connection, challenge); err != nil {
			return
		}
		var response string
		if err := websocket.Message.Receive(connection, &response); err != nil {
			return
		}
		if response != protocol.ChallengeResponse(challenge, secret) {
			return
		}
		_ = websocket.Message.Send(connection, `{"capabilities":{"gestures":true}}`)
	}))
	t.Cleanup(server.Close)
	return "ws" + strings.TrimPrefix(server.URL, "http")
}

func TestProbeAuthenticatesWithSecretFile(t *testing.T) {
	const secret = "probe-fixture-secret"
	if err := probe(authenticatedWebSocketServer(t, secret), writeProbeSecret(t, secret)); err != nil {
		t.Fatal(err)
	}
}

func TestProbeClassifiesAuthenticationFailureWithoutLeakingSecret(t *testing.T) {
	const expectedSecret = "probe-fixture-secret"
	const wrongSecret = "do-not-leak-probe-secret"
	err := probe(authenticatedWebSocketServer(t, expectedSecret), writeProbeSecret(t, wrongSecret))
	if !errors.Is(err, ErrAuthentication) {
		t.Fatalf("probe error = %v, want ErrAuthentication", err)
	}
	if strings.Contains(err.Error(), wrongSecret) {
		t.Fatalf("probe error leaked secret: %v", err)
	}
}

func TestExitCodesKeepConnectionAndAuthenticationDistinct(t *testing.T) {
	tests := []struct {
		name string
		err  error
		want int
	}{
		{name: "success", want: 0},
		{name: "usage", err: ErrUsage, want: 2},
		{name: "connection", err: ErrConnection, want: 3},
		{name: "authentication", err: ErrAuthentication, want: 4},
		{name: "other", err: errors.New("other failure"), want: 1},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if got := exitCode(test.err); got != test.want {
				t.Fatalf("exitCode() = %d, want %d", got, test.want)
			}
		})
	}
}

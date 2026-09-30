//go:build integration

package main

import (
	"encoding/json"
	"io"
	"net/http"
	"os"
	"strings"
	"testing"

	"github.com/ikedamiho41-hue3333333333/phone-touchpad-plus/internal/protocol"
	"golang.org/x/net/websocket"
)

func TestLiveProtocol(t *testing.T) {
	const (
		baseURL = "http://127.0.0.1:18765/"
	)
	secretFile := os.Getenv("PTP_INTEGRATION_SECRET_FILE")
	if secretFile == "" {
		t.Fatal("PTP_INTEGRATION_SECRET_FILE is required")
	}
	secret, err := resolveSecret("", secretFile)
	if err != nil {
		t.Fatalf("load integration secret: %v", err)
	}

	response, err := http.Get(baseURL)
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	body, err := io.ReadAll(response.Body)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(body), "手机妙控板") {
		t.Fatal("custom Chinese interface missing")
	}

	ws, err := websocket.Dial("ws://127.0.0.1:18765/ws", "", baseURL)
	if err != nil {
		t.Fatal(err)
	}
	defer ws.Close()

	var challenge string
	if err := websocket.Message.Receive(ws, &challenge); err != nil {
		t.Fatal(err)
	}
	answer := protocol.ChallengeResponse(challenge, secret)
	if err := websocket.Message.Send(ws, answer); err != nil {
		t.Fatal(err)
	}

	var rawConfig string
	if err := websocket.Message.Receive(ws, &rawConfig); err != nil {
		t.Fatal(err)
	}
	var receivedConfig config
	if err := json.Unmarshal([]byte(rawConfig), &receivedConfig); err != nil {
		t.Fatal(err)
	}
	if receivedConfig.UpdateRate != 30 {
		t.Fatalf("unexpected update rate: %d", receivedConfig.UpdateRate)
	}
	if !receivedConfig.Capabilities.Gestures {
		t.Fatal("null controller did not advertise gesture capability")
	}

	for action := 0; action < int(inputGestureLimitForTest); action++ {
		if err := websocket.Message.Send(ws, "g"+string(rune('0'+action))); err != nil {
			t.Fatal(err)
		}
	}
	for _, command := range []string{"m3;-2", "s0;20", "S0;0"} {
		if err := websocket.Message.Send(ws, command); err != nil {
			t.Fatal(err)
		}
	}
}

const inputGestureLimitForTest = 6

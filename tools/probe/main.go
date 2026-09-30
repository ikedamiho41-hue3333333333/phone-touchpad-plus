package main

import (
	"errors"
	"flag"
	"fmt"
	"net/url"
	"os"
	"strings"

	"github.com/ikedamiho41-hue3333333333/phone-touchpad-plus/internal/protocol"
	"golang.org/x/net/websocket"
)

var (
	ErrUsage          = errors.New("invalid usage")
	ErrConnection     = errors.New("connection failed")
	ErrAuthentication = errors.New("authentication failed")
)

func readSecretFile(path string) (string, error) {
	contents, err := os.ReadFile(path)
	if err != nil {
		return "", errors.New("cannot read secret file")
	}
	secret := strings.TrimSuffix(string(contents), "\n")
	secret = strings.TrimSuffix(secret, "\r")
	if secret == "" || strings.ContainsAny(secret, "\r\n") {
		return "", errors.New("secret file must contain exactly one non-empty line")
	}
	return secret, nil
}

func probe(websocketURL, secretFile string) error {
	parsed, err := url.Parse(websocketURL)
	if err != nil || (parsed.Scheme != "ws" && parsed.Scheme != "wss") ||
		parsed.Host == "" || parsed.Fragment != "" {
		return errors.New("invalid WebSocket URL")
	}
	secret, err := readSecretFile(secretFile)
	if err != nil {
		return err
	}
	originScheme := "http"
	if parsed.Scheme == "wss" {
		originScheme = "https"
	}
	origin := originScheme + "://" + parsed.Host + "/"
	connection, err := websocket.Dial(websocketURL, "", origin)
	if err != nil {
		return ErrConnection
	}
	defer connection.Close()

	var challenge string
	if err := websocket.Message.Receive(connection, &challenge); err != nil {
		return ErrConnection
	}
	if err := websocket.Message.Send(connection, protocol.ChallengeResponse(challenge, secret)); err != nil {
		return ErrConnection
	}
	var configuration string
	if err := websocket.Message.Receive(connection, &configuration); err != nil {
		return ErrAuthentication
	}
	if strings.TrimSpace(configuration) == "" {
		return ErrAuthentication
	}
	return nil
}

func run(arguments []string) error {
	flags := flag.NewFlagSet("phone-touchpad-plus-probe", flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	var websocketURL, secretFile string
	flags.StringVar(&websocketURL, "url", "", "WebSocket URL without a secret fragment")
	flags.StringVar(&secretFile, "secret-file", "", "file containing the shared secret")
	if err := flags.Parse(arguments); err != nil {
		if errors.Is(err, flag.ErrHelp) {
			return err
		}
		return fmt.Errorf("%w: invalid arguments", ErrUsage)
	}
	if flags.NArg() != 0 || websocketURL == "" || secretFile == "" {
		return fmt.Errorf("%w: both -url and -secret-file are required", ErrUsage)
	}
	return probe(websocketURL, secretFile)
}

func exitCode(err error) int {
	switch {
	case err == nil, errors.Is(err, flag.ErrHelp):
		return 0
	case errors.Is(err, ErrUsage):
		return 2
	case errors.Is(err, ErrConnection):
		return 3
	case errors.Is(err, ErrAuthentication):
		return 4
	default:
		return 1
	}
}

func main() {
	err := run(os.Args[1:])
	if err == nil {
		fmt.Println("OK")
		return
	}
	code := exitCode(err)
	if code == 0 {
		return
	}
	fmt.Fprintln(os.Stderr, err)
	os.Exit(code)
}

package protocol

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
)

// ChallengeResponse returns the response used by the touchpad WebSocket
// authentication handshake.
func ChallengeResponse(challenge, secret string) string {
	mac := hmac.New(sha256.New, []byte(challenge))
	_, _ = mac.Write([]byte(secret))
	return base64.StdEncoding.EncodeToString(mac.Sum(nil))
}

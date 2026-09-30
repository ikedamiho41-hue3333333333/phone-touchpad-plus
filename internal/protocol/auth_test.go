package protocol

import "testing"

func TestChallengeResponseMatchesProtocolVector(t *testing.T) {
	got := ChallengeResponse("fixed-challenge", "fixed-secret")
	want := "LJDuyZrtnu9p5KbwTvzOtAHAr1KqSmofjnzOvVecpeI="
	if got != want {
		t.Fatalf("ChallengeResponse() = %q, want %q", got, want)
	}
}

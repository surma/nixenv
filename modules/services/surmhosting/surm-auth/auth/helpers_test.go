package auth

import (
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// jwtRegisteredClaimsShape aliases the registered claims type for the
// test helpers.
type jwtRegisteredClaimsShape = jwt.RegisteredClaims

func registeredClaims(issuer string, d time.Duration) jwt.RegisteredClaims {
	return registeredClaimsWithSubject(issuer, "github:987654", d)
}

func registeredClaimsWithSubject(issuer, subject string, d time.Duration) jwt.RegisteredClaims {
	now := time.Now()
	return jwt.RegisteredClaims{
		Issuer:    issuer,
		Subject:   subject,
		IssuedAt:  jwt.NewNumericDate(now),
		ExpiresAt: jwt.NewNumericDate(now.Add(d)),
	}
}

// jwtSignClaims signs claims with HS256 and returns the token string.
func jwtSignClaims(t *testing.T, claims *Claims, secret []byte) string {
	t.Helper()
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	signed, err := token.SignedString(secret)
	if err != nil {
		t.Fatal(err)
	}
	return signed
}

// jwtNewWithClaimsHS512 signs claims with HS512 to verify that the
// session manager rejects non-HS256 algorithms.
func jwtNewWithClaimsHS512(claims *Claims, secret []byte) string {
	token := jwt.NewWithClaims(jwt.SigningMethodHS512, claims)
	signed, err := token.SignedString(secret)
	if err != nil {
		panic(err)
	}
	return signed
}

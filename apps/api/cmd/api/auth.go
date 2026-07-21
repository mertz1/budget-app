package main

import (
	"context"
	"net/http"
	"strings"

	"github.com/lestrrat-go/httprc/v3"
	"github.com/lestrrat-go/jwx/v3/jwk"
	"github.com/lestrrat-go/jwx/v3/jwt"
)

type contextKey string

const userIDContextKey contextKey = "userID"

// requireAuth verifies the request's bearer token against Supabase's JWKS.
// It never parses or trusts the token without a valid signature — Supabase
// issues tokens, this only checks them (see CLAUDE.md: "do not hand-roll auth").
func requireAuth(jwks jwk.Set) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			raw := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
			if raw == "" {
				http.Error(w, "missing bearer token", http.StatusUnauthorized)
				return
			}

			token, err := jwt.Parse([]byte(raw), jwt.WithKeySet(jwks))
			if err != nil {
				http.Error(w, "invalid token", http.StatusUnauthorized)
				return
			}

			userID, _ := token.Subject()
			ctx := context.WithValue(r.Context(), userIDContextKey, userID)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

// fetchJWKS loads the Supabase project's JSON Web Key Set. The returned Set
// auto-refreshes in the background per Supabase's cache headers.
func fetchJWKS(ctx context.Context, jwksURL string) (jwk.Set, error) {
	cache, err := jwk.NewCache(ctx, httprc.NewClient())
	if err != nil {
		return nil, err
	}
	if err := cache.Register(ctx, jwksURL); err != nil {
		return nil, err
	}
	return cache.CachedSet(jwksURL)
}

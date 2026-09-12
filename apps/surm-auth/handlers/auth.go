package handlers

import (
	"log/slog"
	"net/http"
	"net/url"

	"github.com/surma/surm-auth/audit"
	"github.com/surma/surm-auth/config"
)

// handleAuth implements the forward-auth endpoint. Policy selection
// uses the fixed `app` query parameter only; Host and forwarded
// headers never choose a policy.
func (s *Server) handleAuth(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Missing, duplicate, and unknown app keys fail closed with 404.
	apps := r.URL.Query()["app"]
	if len(apps) != 1 {
		slog.Warn("forward-auth request without exactly one app key", "count", len(apps))
		http.NotFound(w, r)
		return
	}
	appKey := apps[0]

	appCfg, ok := s.deps.Config.Apps[appKey]
	if !ok {
		slog.Warn("forward-auth request for unknown app", "app", appKey)
		http.NotFound(w, r)
		return
	}

	// Every mode validates the forwarded return metadata: malformed or
	// cross-app metadata fails with 400 before any successful
	// response. The metadata only reconstructs the redirect; it never
	// selects policy.
	returnURL, err := s.forwardedReturnURL(r, &appCfg)
	if err != nil {
		slog.Warn("malformed forward-auth return metadata",
			"app", appKey,
			"error", err)
		http.Error(w, "Bad request", http.StatusBadRequest)
		return
	}

	if appCfg.Mode == config.ModePublic {
		// Public apps bypass authentication. Never fabricate identity
		// headers.
		w.WriteHeader(http.StatusOK)
		return
	}

	// Allowlisted apps require current policy state.
	if !s.deps.Policy.Available() {
		s.renderError(w, http.StatusServiceUnavailable, "Authentication policy is temporarily unavailable")
		return
	}

	claims := s.session(r)
	if claims == nil {
		loginURL := s.canonical + "/login?app=" + url.QueryEscape(appKey) +
			"&redirect=" + url.QueryEscape(returnURL)
		http.Redirect(w, r, loginURL, http.StatusFound)
		return
	}

	allowed, err := s.deps.Policy.HasAccess(appKey, claims.Provider, claims.UID)
	if err != nil {
		s.renderError(w, http.StatusServiceUnavailable, "Authentication policy is temporarily unavailable")
		return
	}

	if !allowed {
		s.auditAccessDenied(claims.SubjectID(), appKey, "no grant on allowlisted app")
		s.renderError(w, http.StatusForbidden, "Access denied")
		return
	}

	w.Header().Set("X-Auth-Request-User", claims.Username)
	w.Header().Set("X-Auth-Request-Email", claims.Email)
	w.WriteHeader(http.StatusOK)
}

// auditAccessDenied records an access denial event.
func (s *Server) auditAccessDenied(subject, app, detail string) {
	if err := s.deps.Audit.Record(audit.Event{
		Event:   audit.EventAccessDenied,
		Actor:   subject,
		Subject: subject,
		App:     app,
		Detail:  detail,
	}); err != nil {
		slog.Error("failed to write audit event", "error", err)
	}
}

// forwardedReturnURL reconstructs and validates the return URL from
// Traefik's forwarded request metadata. The metadata only serves to
// reconstruct the redirect; it never selects policy.
func (s *Server) forwardedReturnURL(r *http.Request, appCfg *config.AppConf) (string, error) {
	proto := r.Header.Get("X-Forwarded-Proto")
	host := r.Header.Get("X-Forwarded-Host")
	uri := r.Header.Get("X-Forwarded-Uri")
	if proto == "" || host == "" {
		return "", errMalformedReturn("missing forwarded proto or host")
	}
	if uri == "" {
		uri = "/"
	}
	raw := proto + "://" + host + uri
	redirect := s.validateRedirect(raw, appCfg.Domains, "")
	if redirect == "" {
		return "", errMalformedReturn("return URL does not belong to the app domains: " + raw)
	}
	return redirect, nil
}

type returnError struct{ msg string }

func (e returnError) Error() string { return e.msg }

func errMalformedReturn(msg string) error { return returnError{msg: msg} }

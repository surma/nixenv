package handlers

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"testing"
)

// TestRepoTemplatesParse verifies that the repository template
// directory parses at construction and renders with the handler data
// contracts. It uses the explicit "../templates" path relative to the
// handlers package directory that `go test` always sets as working
// directory.
func TestRepoTemplatesParse(t *testing.T) {
	server := newTestServerWithTemplates(t, "../templates")

	render := func(name string, data any) string {
		out := &bytes.Buffer{}
		if err := server.tmpl.ExecuteTemplate(out, name, data); err != nil {
			t.Fatalf("%s failed to render: %v", name, err)
		}
		return out.String()
	}

	body := render("login.html", map[string]any{
		"App": "demo", "AuthURL": "/login/github?app=demo&amp;redirect=%2F",
	})
	if !containsAll(body, "Login with GitHub", "/login/github?app=demo") {
		t.Errorf("login.html rendered unexpected content: %s", body)
	}

	body = render("login.html", map[string]any{
		"App": "", "AuthURL": "/login/github?redirect=%2F", "LoggedIn": true,
		"Username": "surma", "IsAdmin": true,
	})
	if !containsAll(body, "Signed in", "surma", "Open the admin console") {
		t.Errorf("landing login.html rendered unexpected content: %s", body)
	}

	body = render("error.html", map[string]any{"Error": "boom"})
	if !containsAll(body, "boom") {
		t.Errorf("error.html rendered unexpected content: %s", body)
	}

	body = render("admin.html", map[string]any{
		"Apps": []appView{{Key: "k", Mode: "allowlist", Domains: []string{"one.example", "two.example"}, Grants: 1}},
		"Users": []userView{
			{Subject: "github:1", Provider: "github", ID: "1", Username: "u", Role: "admin", Managed: true},
			{Subject: "github:2", Provider: "github", ID: "2", Username: "v", Role: "user", Managed: false},
		},
		"Events": nil,
		"CSRF":   "tok",
	})
	if !containsAll(body, "github:1", "managed by Nix", "/admin/users/role", `value="tok"`,
		`<a href="https://one.example">one.example</a>`,
		`<a href="https://two.example">two.example</a>`,
	) {
		t.Errorf("admin.html rendered unexpected content: %s", body)
	}
	if bytes.Contains([]byte(body), []byte("<th>Grants</th>")) {
		t.Errorf("admin.html still renders a grants header: %s", body)
	}
	if bytes.Contains([]byte(body), []byte("<td>1</td>")) {
		t.Errorf("admin.html still renders a grants cell: %s", body)
	}

	body = render("admin_app.html", map[string]any{
		"App":       appView{Key: "k", Mode: "allowlist", Domains: []string{"d"}},
		"Grants":    []grantView{{Subject: "github:2", Username: "u2", Provider: "github", ID: "2"}},
		"GrantForm": true, "CSRFGrant": "g", "CSRFDelete": "d",
	})
	if !containsAll(body, "/admin/grants/delete", `value="g"`, `value="d"`, "u2") {
		t.Errorf("admin_app.html rendered unexpected content: %s", body)
	}

	// Public mode renders without a grant-edit form.
	body = render("admin_app.html", map[string]any{
		"App":    appView{Key: "k", Mode: "public", Domains: []string{"d"}},
		"Grants": []grantView{}, "GrantForm": false, "CSRFGrant": "", "CSRFDelete": "",
	})
	if containsAll(body, "/admin/apps/k/grants") {
		t.Errorf("public app page shows a grant form: %s", body)
	}

	body = render("audit.html", map[string]any{
		"Events": []map[string]any{{"Time": "t", "Event": "login_success", "Actor": "a", "Subject": "s", "App": "x", "Detail": ""}},
	})
	if !containsAll(body, "login_success") {
		t.Errorf("audit.html rendered unexpected content: %s", body)
	}
}

// TestHealthEndpoint verifies the readiness contract.
func TestHealthEndpoint(t *testing.T) {
	server := newTestServer(t, testConfig(t), newFakeProvider(), 0)

	recorder := get(server, httptest.NewRequest(http.MethodGet, "https://auth.surma.technology/health", nil))
	if recorder.Code != 200 {
		t.Errorf("health status = %d, want 200", recorder.Code)
	}
}

func containsAll(s string, subs ...string) bool {
	for _, sub := range subs {
		if !bytes.Contains([]byte(s), []byte(sub)) {
			return false
		}
	}
	return true
}

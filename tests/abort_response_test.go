package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestServeHTTPPropagatesUpstreamAbortToRequestGoroutine(t *testing.T) {
	handler, _ := newTestHandler(t)
	request := httptest.NewRequest(http.MethodGet, "http://synthetic.test/aborted.js", nil)
	recorder := httptest.NewRecorder()
	defer func() {
		if recovered := recover(); recovered != http.ErrAbortHandler {
			t.Errorf("expected request goroutine to panic http.ErrAbortHandler, got %v", recovered)
		}
		if recorder.Body.Len() != 0 {
			t.Errorf("aborted response was sent: %q", recorder.Body.String())
		}
	}()
	_ = handler.ServeHTTP(recorder, request, func(w http.ResponseWriter, _ *http.Request) error {
		w.Header().Set("Cache-Control", "public, max-age=60")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("prefix"))
		panic(http.ErrAbortHandler)
	})
}

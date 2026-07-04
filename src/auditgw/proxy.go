package main

// proxy.go — reverse proxy for inference routes (/v1/* and /completion)
// to the local llama-server, with a streaming-safe tee: raw bytes are
// relayed to the client unchanged (flushed per line for SSE), while the
// SSE payloads are reassembled into the plain response text and THAT
// reassembled text is hashed for the audit log — never the raw bytes.

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

const maxBodyBytes = 32 << 20 // 32 MiB request cap
const maxRawCapture = 8 << 20 // fallback raw capture cap

// paramKeys are the request parameters preserved in the audit entry.
var paramKeys = []string{
	"model", "temperature", "top_p", "top_k", "min_p", "max_tokens",
	"n_predict", "stream", "repeat_penalty", "presence_penalty",
	"frequency_penalty", "seed", "stop", "cache_prompt",
}

func writeJSONError(w http.ResponseWriter, code int, msg string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	json.NewEncoder(w).Encode(map[string]any{
		"error": map[string]any{"code": code, "message": msg},
	})
}

// handleInference proxies one inference request and audits it on success.
func (s *Server) handleInference(w http.ResponseWriter, r *http.Request) {
	operator := strings.TrimSpace(r.Header.Get("X-Operator-Id"))
	if operator == "" {
		writeJSONError(w, http.StatusUnauthorized,
			"missing X-Operator-Id header: every inference request must identify its operator for the audit log")
		return
	}

	body, err := io.ReadAll(io.LimitReader(r.Body, maxBodyBytes+1))
	if err != nil {
		writeJSONError(w, http.StatusBadRequest, "cannot read request body")
		return
	}
	if len(body) > maxBodyBytes {
		writeJSONError(w, http.StatusRequestEntityTooLarge, "request body too large")
		return
	}
	promptSHA := sha256Hex(body)
	params := extractParams(body, r.URL.Path)

	target := fmt.Sprintf("http://127.0.0.1:%d%s", s.llmPort, r.URL.Path)
	if r.URL.RawQuery != "" {
		target += "?" + r.URL.RawQuery
	}
	outReq, err := http.NewRequestWithContext(r.Context(), r.Method, target, bytes.NewReader(body))
	if err != nil {
		writeJSONError(w, http.StatusBadGateway, "cannot build upstream request")
		return
	}
	copyProxyHeaders(outReq.Header, r.Header)
	outReq.Header.Set("Accept-Encoding", "identity") // keep SSE parseable

	resp, err := s.llmClient.Do(outReq)
	if err != nil {
		writeJSONError(w, http.StatusBadGateway,
			"llama-server unreachable on 127.0.0.1:"+fmt.Sprint(s.llmPort)+": "+err.Error())
		return
	}
	defer resp.Body.Close()

	for k, vv := range resp.Header {
		if isHopByHop(k) || strings.EqualFold(k, "Content-Length") {
			continue
		}
		for _, v := range vv {
			w.Header().Add(k, v)
		}
	}
	w.WriteHeader(resp.StatusCode)

	isSSE := strings.Contains(resp.Header.Get("Content-Type"), "text/event-stream")
	var responseText string
	var rawFallback []byte

	if isSSE {
		responseText, rawFallback = s.teeSSE(w, resp.Body)
	} else {
		raw, _ := io.ReadAll(resp.Body)
		w.Write(raw)
		if f, ok := w.(http.Flusher); ok {
			f.Flush()
		}
		responseText = extractResponseText(raw)
		rawFallback = raw
	}

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return // only completed inferences are audited
	}
	respSHA := ""
	if responseText != "" {
		respSHA = sha256Hex([]byte(responseText))
	} else {
		respSHA = sha256Hex(rawFallback)
	}
	if _, err := s.chain.Append(operator, s.modelFile, s.modelSHA, promptSHA, respSHA, params); err != nil {
		s.logf("ERROR: audit append failed: %v", err)
	}
}

// teeSSE relays the SSE stream to the client byte-for-byte (flushing per
// line) while reassembling the generated text from the event payloads.
// Returns the reassembled text plus a capped raw capture for fallback.
func (s *Server) teeSSE(w http.ResponseWriter, body io.Reader) (string, []byte) {
	flusher, _ := w.(http.Flusher)
	reader := bufio.NewReaderSize(body, 64*1024)
	var assembled strings.Builder
	var raw bytes.Buffer
	for {
		chunk, err := reader.ReadBytes('\n')
		if len(chunk) > 0 {
			if _, werr := w.Write(chunk); werr != nil {
				break // client went away; upstream context is tied to r.Context
			}
			if flusher != nil {
				flusher.Flush()
			}
			if raw.Len() < maxRawCapture {
				raw.Write(chunk)
			}
			appendSSEPayload(chunk, &assembled)
		}
		if err != nil {
			break
		}
	}
	return assembled.String(), raw.Bytes()
}

// appendSSEPayload parses one SSE line ("data: {...}") and appends any
// generated-text fragment it carries to sb.
func appendSSEPayload(line []byte, sb *strings.Builder) {
	t := bytes.TrimSpace(line)
	if !bytes.HasPrefix(t, []byte("data:")) {
		return
	}
	payload := bytes.TrimSpace(t[len("data:"):])
	if len(payload) == 0 || bytes.Equal(payload, []byte("[DONE]")) {
		return
	}
	var m map[string]any
	if err := json.Unmarshal(payload, &m); err != nil {
		return
	}
	sb.WriteString(contentFromMessage(m))
}

// extractResponseText pulls the generated text out of a non-streaming
// JSON response (OpenAI-compatible or llama.cpp /completion shape).
func extractResponseText(raw []byte) string {
	var m map[string]any
	if err := json.Unmarshal(raw, &m); err != nil {
		return ""
	}
	return contentFromMessage(m)
}

// contentFromMessage understands both API shapes:
//   - llama.cpp /completion: {"content": "..."}
//   - OpenAI chat:     choices[0].message.content or choices[0].delta.content
//   - OpenAI text:     choices[0].text
func contentFromMessage(m map[string]any) string {
	if c, ok := m["content"].(string); ok {
		return c
	}
	choices, ok := m["choices"].([]any)
	if !ok || len(choices) == 0 {
		return ""
	}
	ch, ok := choices[0].(map[string]any)
	if !ok {
		return ""
	}
	for _, key := range []string{"delta", "message"} {
		if inner, ok := ch[key].(map[string]any); ok {
			if c, ok := inner["content"].(string); ok {
				return c
			}
		}
	}
	if c, ok := ch["text"].(string); ok {
		return c
	}
	return ""
}

// extractParams keeps the whitelisted generation parameters plus the route.
func extractParams(body []byte, route string) json.RawMessage {
	out := map[string]any{"route": route}
	var m map[string]any
	if err := json.Unmarshal(body, &m); err == nil {
		for _, k := range paramKeys {
			if v, ok := m[k]; ok {
				out[k] = v
			}
		}
	}
	b, err := json.Marshal(out)
	if err != nil {
		return json.RawMessage(`{}`)
	}
	return b
}

var hopByHop = map[string]bool{
	"Connection": true, "Keep-Alive": true, "Proxy-Authenticate": true,
	"Proxy-Authorization": true, "Te": true, "Trailer": true,
	"Transfer-Encoding": true, "Upgrade": true,
}

func isHopByHop(k string) bool { return hopByHop[http.CanonicalHeaderKey(k)] }

func copyProxyHeaders(dst, src http.Header) {
	for k, vv := range src {
		if isHopByHop(k) || strings.EqualFold(k, "Host") {
			continue
		}
		for _, v := range vv {
			dst.Add(k, v)
		}
	}
}

func newLLMClient() *http.Client {
	return &http.Client{
		Timeout: 0, // streaming: no global timeout
		Transport: &http.Transport{
			MaxIdleConns:          4,
			IdleConnTimeout:       90 * time.Second,
			ResponseHeaderTimeout: 5 * time.Minute,
			DisableCompression:    true,
		},
	}
}

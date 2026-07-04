package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func newTestChain(t *testing.T) (string, *Chain) {
	t.Helper()
	dir := t.TempDir()
	path := filepath.Join(dir, "audit-test.jsonl")
	c, err := OpenChain(path, "test-build-001")
	if err != nil {
		t.Fatalf("OpenChain: %v", err)
	}
	return path, c
}

func appendN(t *testing.T, c *Chain, n int) {
	t.Helper()
	for i := 0; i < n; i++ {
		_, err := c.Append("dr-tanaka", "model.gguf", "abc123",
			sha256Hex([]byte("prompt")), sha256Hex([]byte("response")),
			json.RawMessage(`{"temperature":0.7,"top_p":0.9,"model":"m"}`))
		if err != nil {
			t.Fatalf("Append: %v", err)
		}
	}
}

func TestChainGenesisAndVerify(t *testing.T) {
	path, c := newTestChain(t)
	appendN(t, c, 3)
	n, err := VerifyChain(path)
	if err != nil {
		t.Fatalf("VerifyChain on intact chain: %v", err)
	}
	if n != 4 { // genesis + 3
		t.Fatalf("expected 4 entries, got %d", n)
	}
}

func TestGenesisCarriesBuildID(t *testing.T) {
	path, _ := newTestChain(t)
	data, _ := os.ReadFile(path)
	first := strings.SplitN(string(data), "\n", 2)[0]
	var e Entry
	if err := json.Unmarshal([]byte(first), &e); err != nil {
		t.Fatalf("genesis line unparseable: %v", err)
	}
	if e.Seq != 0 || e.PrevHash != genesisPrevHash {
		t.Fatalf("bad genesis: seq=%d prev=%s", e.Seq, e.PrevHash)
	}
	if !strings.Contains(string(e.Params), "test-build-001") {
		t.Fatalf("genesis params missing build id: %s", e.Params)
	}
}

func TestEntryHashIsCanonicalMinusEntryHash(t *testing.T) {
	path, c := newTestChain(t)
	appendN(t, c, 1)
	data, _ := os.ReadFile(path)
	lines := strings.Split(strings.TrimSpace(string(data)), "\n")
	var e Entry
	if err := json.Unmarshal([]byte(lines[1]), &e); err != nil {
		t.Fatal(err)
	}
	want, err := computeEntryHash(&e)
	if err != nil {
		t.Fatal(err)
	}
	if want != e.EntryHash {
		t.Fatalf("stored entry_hash %s != recomputed %s", e.EntryHash, want)
	}
}

func TestTamperedByteBreaksChain(t *testing.T) {
	path, c := newTestChain(t)
	appendN(t, c, 3)
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	// Flip one byte inside the third line (a real payload byte).
	lines := strings.Split(string(data), "\n")
	target := []byte(lines[2])
	idx := strings.Index(lines[2], "dr-tanaka")
	if idx < 0 {
		t.Fatal("operator not found in line")
	}
	target[idx] = 'X' // dr-tanaka -> Xr-tanaka
	lines[2] = string(target)
	tampered := filepath.Join(t.TempDir(), "tampered.jsonl")
	if err := os.WriteFile(tampered, []byte(strings.Join(lines, "\n")), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := VerifyChain(tampered); err == nil {
		t.Fatal("VerifyChain accepted a tampered chain")
	}
}

func TestDeletedEntryBreaksChain(t *testing.T) {
	path, c := newTestChain(t)
	appendN(t, c, 3)
	data, _ := os.ReadFile(path)
	lines := strings.Split(strings.TrimSpace(string(data)), "\n")
	// Remove the middle entry.
	cut := append([]string{}, lines[0], lines[1], lines[3])
	cutPath := filepath.Join(t.TempDir(), "cut.jsonl")
	os.WriteFile(cutPath, []byte(strings.Join(cut, "\n")+"\n"), 0o644)
	if _, err := VerifyChain(cutPath); err == nil {
		t.Fatal("VerifyChain accepted a chain with a deleted entry")
	}
}

func TestReopenContinuesChain(t *testing.T) {
	path, c := newTestChain(t)
	appendN(t, c, 2)
	c2, err := OpenChain(path, "test-build-001")
	if err != nil {
		t.Fatal(err)
	}
	appendN(t, c2, 2)
	n, err := VerifyChain(path)
	if err != nil {
		t.Fatalf("reopened chain broken: %v", err)
	}
	if n != 5 {
		t.Fatalf("expected 5 entries, got %d", n)
	}
	if c2.LastSeq() != 4 {
		t.Fatalf("expected last seq 4, got %d", c2.LastSeq())
	}
}

func TestCanonicalParamsSortedAndIdempotent(t *testing.T) {
	a, err := canonicalParams(json.RawMessage(`{"z":1,"a":{"y":2,"b":3}}`))
	if err != nil {
		t.Fatal(err)
	}
	if string(a) != `{"a":{"b":3,"y":2},"z":1}` {
		t.Fatalf("not sorted: %s", a)
	}
	b, _ := canonicalParams(a)
	if string(a) != string(b) {
		t.Fatalf("not idempotent: %s vs %s", a, b)
	}
}

func TestSSEReassembly(t *testing.T) {
	var sb strings.Builder
	for _, line := range []string{
		`data: {"choices":[{"delta":{"content":"Hello"}}]}`,
		`data: {"choices":[{"delta":{"content":" world"}}]}`,
		``,
		`data: {"content":"!"}`, // llama.cpp /completion stream shape
		`data: [DONE]`,
	} {
		appendSSEPayload([]byte(line+"\n"), &sb)
	}
	if sb.String() != "Hello world!" {
		t.Fatalf("reassembled %q", sb.String())
	}
}

func TestExtractNonStreaming(t *testing.T) {
	chat := []byte(`{"choices":[{"message":{"content":"final answer"}}]}`)
	if extractResponseText(chat) != "final answer" {
		t.Fatal("chat shape not extracted")
	}
	comp := []byte(`{"content":"raw completion"}`)
	if extractResponseText(comp) != "raw completion" {
		t.Fatal("/completion shape not extracted")
	}
}

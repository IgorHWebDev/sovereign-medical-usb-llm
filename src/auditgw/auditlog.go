package main

// auditlog.go — tamper-evident hash-chained JSONL audit log.
//
// Each line is one JSON entry:
//   {seq, ts_utc, operator_id, model_file, model_sha256,
//    prompt_sha256, response_sha256, params, prev_hash, entry_hash}
// entry_hash = SHA256(hex) of the canonical JSON of the entry with every
// field EXCEPT entry_hash, keys in the fixed order above, params
// canonicalized (object keys sorted). prev_hash of entry N equals
// entry_hash of entry N-1; the genesis entry (seq 0) uses 64 zeros.

import (
	"bufio"
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

const genesisPrevHash = "0000000000000000000000000000000000000000000000000000000000000000"

// Entry is one audit-log record.
type Entry struct {
	Seq            int64           `json:"seq"`
	TsUTC          string          `json:"ts_utc"`
	OperatorID     string          `json:"operator_id"`
	ModelFile      string          `json:"model_file"`
	ModelSHA256    string          `json:"model_sha256"`
	PromptSHA256   string          `json:"prompt_sha256"`
	ResponseSHA256 string          `json:"response_sha256"`
	Params         json.RawMessage `json:"params"`
	PrevHash       string          `json:"prev_hash"`
	EntryHash      string          `json:"entry_hash"`
}

// canonicalParams round-trips arbitrary JSON through a Go value so that
// object keys come out sorted (encoding/json sorts map keys). Idempotent.
func canonicalParams(raw json.RawMessage) (json.RawMessage, error) {
	if len(bytes.TrimSpace(raw)) == 0 {
		return json.RawMessage("{}"), nil
	}
	var v any
	if err := json.Unmarshal(raw, &v); err != nil {
		return nil, fmt.Errorf("params not valid JSON: %w", err)
	}
	out, err := json.Marshal(v)
	if err != nil {
		return nil, err
	}
	return json.RawMessage(out), nil
}

// canonicalBytes builds the canonical JSON of the entry minus entry_hash,
// with a fixed key order. This is the exact byte string that is hashed.
func canonicalBytes(e *Entry) ([]byte, error) {
	params, err := canonicalParams(e.Params)
	if err != nil {
		return nil, err
	}
	var b bytes.Buffer
	b.WriteByte('{')
	writeKV := func(key string, v any, last bool) error {
		kb, _ := json.Marshal(key)
		b.Write(kb)
		b.WriteByte(':')
		switch t := v.(type) {
		case json.RawMessage:
			b.Write(t)
		default:
			vb, err := json.Marshal(v)
			if err != nil {
				return err
			}
			b.Write(vb)
		}
		if !last {
			b.WriteByte(',')
		}
		return nil
	}
	if err := writeKV("seq", e.Seq, false); err != nil {
		return nil, err
	}
	writeKV("ts_utc", e.TsUTC, false)
	writeKV("operator_id", e.OperatorID, false)
	writeKV("model_file", e.ModelFile, false)
	writeKV("model_sha256", e.ModelSHA256, false)
	writeKV("prompt_sha256", e.PromptSHA256, false)
	writeKV("response_sha256", e.ResponseSHA256, false)
	writeKV("params", params, false)
	writeKV("prev_hash", e.PrevHash, true)
	b.WriteByte('}')
	return b.Bytes(), nil
}

// computeEntryHash returns the hex SHA256 of the canonical form.
func computeEntryHash(e *Entry) (string, error) {
	cb, err := canonicalBytes(e)
	if err != nil {
		return "", err
	}
	sum := sha256.Sum256(cb)
	return hex.EncodeToString(sum[:]), nil
}

func sha256Hex(data []byte) string {
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:])
}

// Chain is an append-only writer over one audit JSONL file.
type Chain struct {
	mu       sync.Mutex
	path     string
	seq      int64 // last written seq
	lastHash string
}

// OpenChain opens (or creates) the audit file at path. If the file is new
// or empty, a genesis entry carrying the stick build id is written first.
func OpenChain(path, buildID string) (*Chain, error) {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return nil, err
	}
	c := &Chain{path: path, seq: -1, lastHash: genesisPrevHash}

	fi, err := os.Stat(path)
	if err == nil && fi.Size() > 0 {
		last, err := lastEntry(path)
		if err != nil {
			return nil, fmt.Errorf("existing audit file %s is unreadable: %w", path, err)
		}
		c.seq = last.Seq
		c.lastHash = last.EntryHash
		return c, nil
	}
	// New chain: write genesis.
	params, _ := json.Marshal(map[string]any{
		"genesis":        true,
		"stick_build_id": buildID,
	})
	empty := sha256Hex(nil)
	gen := &Entry{
		Seq:            0,
		TsUTC:          time.Now().UTC().Format("2006-01-02T15:04:05Z"),
		OperatorID:     "system",
		ModelFile:      "",
		ModelSHA256:    "",
		PromptSHA256:   empty,
		ResponseSHA256: empty,
		Params:         params,
		PrevHash:       genesisPrevHash,
	}
	if err := c.writeEntry(gen); err != nil {
		return nil, err
	}
	return c, nil
}

// Append adds one inference record to the chain.
func (c *Chain) Append(operatorID, modelFile, modelSHA, promptSHA, responseSHA string, params json.RawMessage) (*Entry, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	e := &Entry{
		Seq:            c.seq + 1,
		TsUTC:          time.Now().UTC().Format("2006-01-02T15:04:05Z"),
		OperatorID:     operatorID,
		ModelFile:      modelFile,
		ModelSHA256:    modelSHA,
		PromptSHA256:   promptSHA,
		ResponseSHA256: responseSHA,
		Params:         params,
		PrevHash:       c.lastHash,
	}
	if err := c.writeEntry(e); err != nil {
		return nil, err
	}
	return e, nil
}

// writeEntry finalizes hashes and appends one JSONL line (fsynced).
// Caller must hold c.mu (or be the only owner, as in OpenChain).
func (c *Chain) writeEntry(e *Entry) error {
	cp, err := canonicalParams(e.Params)
	if err != nil {
		return err
	}
	e.Params = cp
	h, err := computeEntryHash(e)
	if err != nil {
		return err
	}
	e.EntryHash = h
	line, err := json.Marshal(e)
	if err != nil {
		return err
	}
	f, err := os.OpenFile(c.path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	if err != nil {
		return err
	}
	defer f.Close()
	if _, err := f.Write(append(line, '\n')); err != nil {
		return err
	}
	if err := f.Sync(); err != nil {
		return err
	}
	c.seq = e.Seq
	c.lastHash = e.EntryHash
	return nil
}

// LastSeq returns the highest seq written so far.
func (c *Chain) LastSeq() int64 {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.seq
}

// VerifySelf re-verifies the whole chain on disk under the append lock, so a
// concurrent Append cannot make status polling see a half-written last line.
// Returns the entry count and whether every link is intact.
func (c *Chain) VerifySelf() (int, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	n, err := VerifyChain(c.path)
	return n, err == nil
}

func lastEntry(path string) (*Entry, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 0, 1024*1024), 16*1024*1024)
	var last *Entry
	lineNo := 0
	for sc.Scan() {
		lineNo++
		txt := strings.TrimSpace(sc.Text())
		if txt == "" {
			continue
		}
		var e Entry
		if err := json.Unmarshal([]byte(txt), &e); err != nil {
			return nil, fmt.Errorf("line %d: %w", lineNo, err)
		}
		last = &e
	}
	if err := sc.Err(); err != nil {
		return nil, err
	}
	if last == nil {
		return nil, fmt.Errorf("no entries")
	}
	return last, nil
}

// VerifyChain checks every link of the audit file. It returns an error
// describing the first broken link, or nil if the whole chain is intact.
func VerifyChain(path string) (int, error) {
	f, err := os.Open(path)
	if err != nil {
		return 0, err
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 0, 1024*1024), 16*1024*1024)
	lineNo := 0
	count := 0
	prevHash := genesisPrevHash
	var prevSeq int64 = -1
	for sc.Scan() {
		lineNo++
		txt := strings.TrimSpace(sc.Text())
		if txt == "" {
			continue
		}
		var e Entry
		if err := json.Unmarshal([]byte(txt), &e); err != nil {
			return count, fmt.Errorf("line %d: invalid JSON: %w", lineNo, err)
		}
		if e.Seq != prevSeq+1 {
			return count, fmt.Errorf("line %d: seq %d does not follow %d", lineNo, e.Seq, prevSeq)
		}
		if e.PrevHash != prevHash {
			return count, fmt.Errorf("line %d (seq %d): prev_hash mismatch: chain broken", lineNo, e.Seq)
		}
		want, err := computeEntryHash(&e)
		if err != nil {
			return count, fmt.Errorf("line %d (seq %d): cannot canonicalize: %w", lineNo, e.Seq, err)
		}
		if want != e.EntryHash {
			return count, fmt.Errorf("line %d (seq %d): entry_hash mismatch: entry tampered", lineNo, e.Seq)
		}
		prevHash = e.EntryHash
		prevSeq = e.Seq
		count++
	}
	if err := sc.Err(); err != nil {
		return count, err
	}
	if count == 0 {
		return 0, fmt.Errorf("no entries found in %s", path)
	}
	return count, nil
}

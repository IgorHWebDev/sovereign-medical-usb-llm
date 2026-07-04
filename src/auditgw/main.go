package main

// auditgw — offline audit gateway for the med-usb stick.
//
// Subcommands:
//   serve  (default)  run the gateway: static UI + audited reverse proxy
//   verify <file>     verify a hash-chained audit JSONL file (nonzero on break)
//   append            append one entry to a chain (used by launchers/tests)
//   version           print version info
//
// Stdlib only. CGO_ENABLED=0. Binds 127.0.0.1 only.

import (
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"
)

const version = "auditgw 1.0.0 (med-usb m4)"

const usageText = `auditgw — offline audit gateway for the med-usb stick

Usage:
  auditgw [serve] [flags]     Run the gateway (default subcommand).
  auditgw verify <file>       Verify a hash-chained audit JSONL file.
                              Exits nonzero on the first broken link.
  auditgw append [flags]      Append one entry to a chain file (tooling/tests).
  auditgw version             Print version.
  auditgw -h | --help | help  Show this help.

Serve flags:
  --ui-dir DIR        Static UI directory to serve at /            (default ./ui)
  --ui-port N         Port for the UI + API on 127.0.0.1           (default 8180)
  --llm-port N        llama-server port on 127.0.0.1               (default 8080)
  --audit-dir DIR     Directory for audit-YYYYMM.jsonl             (default ./audit)
  --model-file NAME   GGUF filename recorded in audit entries
  --model-sha256 HEX  GGUF sha256 recorded in audit entries
  --build-id ID       Stick build id recorded in the genesis entry (default dev)
  --allow-online      Acknowledge a detected default route (else loud warning;
                      status exposed at /api/status as offline_warning)
  --spawn-llm         Launch and supervise llama-server ourselves
  --llm-bin PATH      llama-server binary (required with --spawn-llm)
  --llm-args "..."    Extra args passed to llama-server

Routes:
  /                    static UI (from --ui-dir)
  /v1/*, /completion   audited reverse proxy to llama-server
                       (requires X-Operator-Id header, else 401)
  /api/status          gateway + offline-guard status (JSON)
  /api/shutdown        POST: graceful exit (stops spawned llama-server too)

Audit entries are hash-chained JSONL:
  {seq, ts_utc, operator_id, model_file, model_sha256, prompt_sha256,
   response_sha256, params, prev_hash, entry_hash}
  entry_hash = SHA256 of the canonical JSON minus entry_hash.
`

func main() {
	args := os.Args[1:]
	if len(args) > 0 {
		switch args[0] {
		case "-h", "--help", "help":
			fmt.Print(usageText)
			os.Exit(0)
		case "version", "-v", "--version":
			fmt.Println(version)
			os.Exit(0)
		case "verify":
			os.Exit(cmdVerify(args[1:]))
		case "append":
			os.Exit(cmdAppend(args[1:]))
		case "serve":
			args = args[1:]
		}
	}
	os.Exit(cmdServe(args))
}

func cmdServe(args []string) int {
	fs := flag.NewFlagSet("serve", flag.ContinueOnError)
	fs.Usage = func() { fmt.Print(usageText) }
	uiDir := fs.String("ui-dir", "./ui", "")
	uiPort := fs.Int("ui-port", 8180, "")
	llmPort := fs.Int("llm-port", 8080, "")
	auditDir := fs.String("audit-dir", "./audit", "")
	modelFile := fs.String("model-file", "", "")
	modelSHA := fs.String("model-sha256", "", "")
	buildID := fs.String("build-id", "dev", "")
	allowOnline := fs.Bool("allow-online", false, "")
	spawnLLM := fs.Bool("spawn-llm", false, "")
	llmBin := fs.String("llm-bin", "", "")
	llmArgs := fs.String("llm-args", "", "")
	if err := fs.Parse(args); err != nil {
		if err == flag.ErrHelp {
			return 0
		}
		return 2
	}

	logger := log.New(os.Stderr, "[auditgw] ", log.LstdFlags|log.LUTC)
	auditPath := auditFilePath(*auditDir)
	chain, err := OpenChain(auditPath, *buildID)
	if err != nil {
		logger.Printf("FATAL: cannot open audit chain: %v", err)
		return 1
	}

	srv := &Server{
		uiDir:       mustDir(*uiDir, "ui"),
		uiPort:      *uiPort,
		llmPort:     *llmPort,
		modelFile:   *modelFile,
		modelSHA:    *modelSHA,
		buildID:     *buildID,
		allowOnline: *allowOnline,
		chain:       chain,
		auditPath:   auditPath,
		llmClient:   newLLMClient(),
		shutdown:    make(chan struct{}),
		logger:      logger,
	}
	if *spawnLLM {
		if *llmBin == "" {
			logger.Printf("FATAL: --spawn-llm requires --llm-bin")
			return 2
		}
		srv.sup = NewLLMSupervisor(*llmBin, splitArgs(*llmArgs), logger)
	}
	if err := srv.Run(); err != nil {
		logger.Printf("FATAL: %v", err)
		return 1
	}
	return 0
}

func cmdVerify(args []string) int {
	if len(args) != 1 {
		fmt.Fprintln(os.Stderr, "usage: auditgw verify <audit-file.jsonl>")
		return 2
	}
	n, err := VerifyChain(args[0])
	if err != nil {
		fmt.Fprintf(os.Stderr, "FAIL: %s: %v (%d entries verified before break)\n", args[0], err, n)
		return 1
	}
	fmt.Printf("OK: %s: %d entries, chain intact\n", args[0], n)
	return 0
}

func cmdAppend(args []string) int {
	fs := flag.NewFlagSet("append", flag.ContinueOnError)
	fs.Usage = func() {
		fmt.Fprintln(os.Stderr, `usage: auditgw append --file <chain.jsonl> --operator <id> --prompt <text> --response <text> [--params <json>] [--model-file <name>] [--model-sha256 <hex>] [--build-id <id>]`)
	}
	file := fs.String("file", "", "")
	operator := fs.String("operator", "", "")
	prompt := fs.String("prompt", "", "")
	response := fs.String("response", "", "")
	params := fs.String("params", "{}", "")
	modelFile := fs.String("model-file", "", "")
	modelSHA := fs.String("model-sha256", "", "")
	buildID := fs.String("build-id", "dev", "")
	if err := fs.Parse(args); err != nil {
		if err == flag.ErrHelp {
			return 0
		}
		return 2
	}
	if *file == "" || *operator == "" {
		fs.Usage()
		return 2
	}
	chain, err := OpenChain(*file, *buildID)
	if err != nil {
		fmt.Fprintf(os.Stderr, "FAIL: %v\n", err)
		return 1
	}
	e, err := chain.Append(*operator, *modelFile, *modelSHA,
		sha256Hex([]byte(*prompt)), sha256Hex([]byte(*response)),
		json.RawMessage(*params))
	if err != nil {
		fmt.Fprintf(os.Stderr, "FAIL: %v\n", err)
		return 1
	}
	fmt.Printf("appended seq=%d entry_hash=%s\n", e.Seq, e.EntryHash)
	return 0
}

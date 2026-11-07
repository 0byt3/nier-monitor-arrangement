package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"nier-monitor-arrangement/internal/arrangement"
	"os"
)

func main() {
	app, err := arrangement.Default()
	if err != nil {
		finish(arrangement.Result{Error: err.Error()})
		return
	}
	command := "snapshot"
	if len(os.Args) > 1 {
		command = os.Args[1]
	}
	ctx := context.Background()
	switch command {
	case "snapshot":
		snapshot, err := app.Snapshot(ctx)
		if err != nil {
			finish(arrangement.Result{Error: err.Error()})
		} else {
			finish(arrangement.Result{OK: true, Snapshot: &snapshot})
		}
	case "save":
		data, err := io.ReadAll(io.LimitReader(os.Stdin, 1024*1024+1))
		if err != nil || len(data) > 1024*1024 {
			finish(arrangement.Result{Error: "invalid or oversized save request"})
			return
		}
		var req arrangement.SaveRequest
		if err = json.Unmarshal(data, &req); err != nil {
			finish(arrangement.Result{Error: err.Error()})
			return
		}
		finish(app.Save(ctx, req))
	case "apply":
		finish(app.Apply(ctx))
	default:
		finish(arrangement.Result{Error: fmt.Sprintf("unknown command %q (use snapshot, save or apply)", command)})
	}
}

func finish(result arrangement.Result) {
	if err := json.NewEncoder(os.Stdout).Encode(result); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	if !result.OK {
		fmt.Fprintln(os.Stderr, result.Error)
		os.Exit(1)
	}
}

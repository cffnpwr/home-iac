package main

import (
	"context"
	"time"
)

// Nodeとインスタンスの状態の変化を待つ上限と確認の間隔
const (
	waitTimeout  = 15 * time.Minute
	pollInterval = 10 * time.Second
)

func waitPollInterval(ctx context.Context) error {
	timer := time.NewTimer(pollInterval)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-timer.C:
		return nil
	}
}

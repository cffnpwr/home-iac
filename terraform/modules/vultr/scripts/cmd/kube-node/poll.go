package main

import (
	"context"
	"time"
)

// 新しいインスタンスの作成と再起動の待機時間
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

package main

import (
	"bytes"
	"context"
	"errors"
	"log/slog"
	"net/netip"
	"text/template"

	"k8s.io/client-go/util/workqueue"

	"github.com/cffnpwr/home-iac/images/kea-ha-peers/internal/cluster"
	"github.com/cffnpwr/home-iac/images/kea-ha-peers/internal/kea"
	"github.com/cffnpwr/home-iac/images/kea-ha-peers/internal/netif"
	"github.com/cffnpwr/home-iac/images/kea-ha-peers/internal/peer"
)

// CiliumNodeの変更をまとめて1回の再生成にするため、queueのキーを1つだけ使用
const queueKey = "nodes"

type reconcilerConfig struct {
	nodeName      string
	labelSelector string
	subnet        netip.Prefix
	template      *template.Template
	configPath    string
	controlSocket string
}

type reconciler struct {
	config  reconcilerConfig
	logger  *slog.Logger
	queue   workqueue.TypedRateLimitingInterface[string]
	watcher *cluster.NodeWatcher
	// Keaに読み込ませた設定。未適用ならnil
	appliedConfig []byte
}

func newReconciler(config reconcilerConfig, logger *slog.Logger) (*reconciler, error) {
	queue := workqueue.NewTypedRateLimitingQueue(
		workqueue.DefaultTypedControllerRateLimiter[string](),
	)
	watcher, err := cluster.NewNodeWatcher(config.labelSelector, func() { queue.Add(queueKey) })
	if err != nil {
		return nil, err
	}

	return &reconciler{config: config, logger: logger, queue: queue, watcher: watcher}, nil
}

func (r *reconciler) run(ctx context.Context) error {
	defer r.queue.ShutDown()
	go func() {
		<-ctx.Done()
		r.queue.ShutDown()
	}()

	if err := r.watcher.Start(ctx); err != nil {
		return err
	}
	r.queue.Add(queueKey)

	for {
		key, shutdown := r.queue.Get()
		if shutdown {
			return nil
		}

		if err := r.reconcile(ctx); err != nil {
			r.logger.Error("failed to apply Kea configuration", "error", err)
			r.queue.AddRateLimited(key)
		} else {
			r.queue.Forget(key)
		}
		r.queue.Done(key)
	}
}

func (r *reconciler) reconcile(ctx context.Context) error {
	nodes, err := r.watcher.Nodes()
	if err != nil {
		return err
	}

	self, err := findSelf(nodes, r.config.nodeName, r.config.subnet)
	if err != nil {
		return err
	}
	interfaceName, err := netif.FindInterfaceName(self.lanAddress)
	if err != nil {
		return err
	}
	peers := peer.Assign(ciliumInternalIPs(nodes))

	d := kea.TemplateData{
		Subnet:    r.config.subnet,
		Interface: interfaceName,
		Self:      self.ciliumInternalIP,
		Peers:     peers,
	}
	config, err := kea.RenderConfig(r.config.template, d)
	if err != nil {
		return err
	}
	if bytes.Equal(config, r.appliedConfig) {
		return nil
	}

	if writeErr := kea.WriteConfig(r.config.configPath, config); writeErr != nil {
		return writeErr
	}
	// Keaの制御ソケットに接続できない場合、次の起動時に書き出した設定を読み込む
	reloadErr := kea.Reload(ctx, r.config.controlSocket)
	if reloadErr != nil && !errors.Is(reloadErr, kea.ErrControlSocketUnavailable) {
		return reloadErr
	}

	r.appliedConfig = config
	r.logger.Info(
		"applied Kea configuration",
		"interface", interfaceName,
		"self", self.ciliumInternalIP,
		"peers", len(peers),
	)

	return nil
}

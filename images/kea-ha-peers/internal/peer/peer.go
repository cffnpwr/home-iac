package peer

import (
	"net/netip"
	"slices"
)

type Role string

const (
	RolePrimary Role = "primary"
	RoleStandby Role = "standby"
	RoleBackup  Role = "backup"
)

type Peer struct {
	Address netip.Addr
	Role    Role
}

func Assign(addresses []netip.Addr) []Peer {
	sortedAddresses := slices.Clone(addresses)
	slices.SortFunc(sortedAddresses, netip.Addr.Compare)
	sortedAddresses = slices.Compact(sortedAddresses)

	// アドレスの小さい順にprimary・standby・backupを割り当て
	peers := make([]Peer, 0, len(sortedAddresses))
	for i, address := range sortedAddresses {
		role := RoleBackup
		switch i {
		case 0:
			role = RolePrimary
		case 1:
			role = RoleStandby
		}
		peers = append(peers, Peer{Address: address, Role: role})
	}

	return peers
}

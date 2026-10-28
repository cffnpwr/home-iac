package netif

import (
	"errors"
	"fmt"
	"net/netip"
)

var (
	ErrNoAddressInSubnet = errors.New("no address in the subnet")
	ErrAmbiguousAddress  = errors.New("multiple addresses in the subnet")
)

func SelectSubnetAddress(addresses []netip.Addr, subnet netip.Prefix) (netip.Addr, error) {
	var inSubnet []netip.Addr
	for _, address := range addresses {
		if subnet.Contains(address) {
			inSubnet = append(inSubnet, address)
		}
	}

	switch len(inSubnet) {
	case 0:
		return netip.Addr{}, fmt.Errorf("%w: %v not in %s", ErrNoAddressInSubnet, addresses, subnet)
	case 1:
		return inSubnet[0], nil
	default:
		return netip.Addr{}, fmt.Errorf("%w: %v in %s", ErrAmbiguousAddress, inSubnet, subnet)
	}
}

package netif

import (
	"errors"
	"fmt"
	"net"
	"net/netip"
	"slices"
)

var (
	ErrInterfaceNotFound = errors.New("no interface has the address")
	ErrListInterfaces    = errors.New("list network interfaces failed")
)

type interfaceAddresses struct {
	name     string
	prefixes []netip.Prefix
}

func FindInterfaceName(address netip.Addr) (string, error) {
	interfaces, err := net.Interfaces()
	if err != nil {
		return "", fmt.Errorf("%w: %v", ErrListInterfaces, err)
	}

	listed := make([]interfaceAddresses, 0, len(interfaces))
	for _, iface := range interfaces {
		addrs, addrsErr := iface.Addrs()
		if addrsErr != nil {
			return "", fmt.Errorf("%w: %s: %v", ErrListInterfaces, iface.Name, addrsErr)
		}

		prefixes := make([]netip.Prefix, 0, len(addrs))
		for _, addr := range addrs {
			if prefix, parseErr := netip.ParsePrefix(addr.String()); parseErr == nil {
				prefixes = append(prefixes, prefix)
			}
		}
		listed = append(listed, interfaceAddresses{name: iface.Name, prefixes: prefixes})
	}

	return findInterfaceName(listed, address)
}

func findInterfaceName(interfaces []interfaceAddresses, address netip.Addr) (string, error) {
	for _, iface := range interfaces {
		if slices.ContainsFunc(
			iface.prefixes,
			func(p netip.Prefix) bool { return p.Addr() == address },
		) {
			return iface.name, nil
		}
	}

	return "", fmt.Errorf("%w: %s", ErrInterfaceNotFound, address)
}

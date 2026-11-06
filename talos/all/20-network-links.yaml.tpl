# Node networking as Talos 1.13+ typed network documents (replaces
# .machine.network.interfaces). The NIC is matched by MAC and aliased to
# ethSel0 so nothing depends on kernel interface naming. Static address,
# no DHCP.
apiVersion: v1alpha1
kind: LinkAliasConfig
name: ethSel0
selector:
  match: glob("{{ .Node.Data.macAddr }}", mac(link.hardware_addr))
---
apiVersion: v1alpha1
kind: LinkConfig
name: ethSel0
mtu: 1500
addresses:
  - address: {{ .Node.IP }}/24
routes:
  - gateway: {{ .Data.gateway }}

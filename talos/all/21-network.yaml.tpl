# DNS for the nodes themselves (pods use CoreDNS via Cilium).
apiVersion: v1alpha1
kind: ResolverConfig
nameservers:
  - address: {{ .Data.nameserver }}
searchDomains:
  disableDefault: true

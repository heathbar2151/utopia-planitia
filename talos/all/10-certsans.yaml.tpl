# Extra SANs on the Talos API (apid) certificate; the node's own IPs are
# added automatically. The API server equivalent is in
# control-plane/10-cluster.yaml.tpl.
machine:
  certSANs:
    - 127.0.0.1
    - {{ .Data.vip }}

# Talos configuration

Machine configs are assembled by [topf](https://postfinance.github.io/topf/)
from `topf.yaml` plus the strategic merge patches in this directory, and
applied straight to the nodes (nothing is rendered to disk).

<https://www.talos.dev/latest/talos-guides/configuration/patching/>

## Patch directories

Patches merge in this order, alphabetically within each directory, with
later patches taking precedence:

- `all/`: every node
- `control-plane/`: control-plane nodes (all three nodes here)
- `worker/`: worker nodes (none yet)
- `node/<host>/`: one node

Files ending in `.yaml.tpl` are Go-templated per node (`.Node.Host`,
`.Node.IP`, `.Node.Data.macAddr`, and shared values like `.Data.vip`,
`.Data.gateway`, `.Data.nodeSubnet`, `.Data.nameserver`). JSON6902 patches
aren't supported; remove a key with `$patch: delete`.

LAN addressing never goes in a patch as a literal. It lives in `topf.yaml`
(`clusterEndpoint`, each node's `ip`/`data`, and the top-level `data:`
block), which is SOPS-encrypted for just those keys; edit it with
`sops topf.yaml`. topf decrypts it on the fly. Versions stay plaintext so
Renovate can still bump them.

## Workflow

- `task talos:diff` (or `NODE=drone-01`): redacted diff of pending changes
- `task talos:apply-node NODE=drone-01`: apply to one node (diff + confirm)
- Talos/Kubernetes upgrades: bump the version in
  `kubernetes/apps/system-upgrade/tuppr/upgrades/` (tuppr does the
  health-gated rolling upgrade) and keep `talosVersion`/`kubernetesVersion`
  in `topf.yaml` in step.
- `task talos:client-config`: regenerate the talosctl client config from
  the secrets bundle (`talsecret.sops.yaml`).

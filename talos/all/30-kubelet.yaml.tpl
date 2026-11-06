# The kubelet stays on the v1alpha1 .machine.kubelet form on purpose: the
# multi-document KubeletConfig (Talos 1.14+) has no extraMounts, and the
# kubelet must see /var/openebs/local to bind-mount the openebs-hostpath
# local PVs. Talos's generated KubeletConfig document is
# deleted below so the two forms don't conflict (node settings like nodeIP
# are already in KubeNodeConfig). Port extraMounts away once nothing uses
# openebs-hostpath.
machine:
  kubelet:
    # With the generated KubeletConfig deleted, these defaults have to be set
    # here or the kubelet falls back to Talos's own default version.
    image: ghcr.io/siderolabs/kubelet:{{ .KubernetesVersion }}
    defaultRuntimeSeccompProfileEnabled: true
    disableManifestsDirectory: true
    extraConfig:
      # Image GC. The defaults (85/80) start cleanup exactly at the
      # imagefs.available<15% hard-eviction line and never age images out,
      # so every old version piles up in /var. /var also holds etcd,
      # openebs-hostpath volumes and logs, so keep the low mark well above
      # that.
      imageGCHighThresholdPercent: 70
      imageGCLowThresholdPercent: 60
      # Remove images no container has used for 7 days, regardless of disk.
      imageMaximumGCAge: 168h
    extraMounts:
      - destination: /var/openebs/local
        type: bind
        source: /var/openebs/local
        options:
          - bind
          - rshared
          - rw
---
apiVersion: v1alpha1
kind: KubeletConfig
$patch: delete
---
apiVersion: v1alpha1
kind: KubeNodeConfig
nodeIP:
  validSubnets:
    - {{ .Data.nodeSubnet }}

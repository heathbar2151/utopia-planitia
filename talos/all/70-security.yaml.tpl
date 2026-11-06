{{- /*
  Talos 1.14 can run CRI, the kubelet and pods in an isolated sandbox
  namespace. `gen config` (and so topf) turns it on for 1.14 configs, but
  it breaks in-tree volume plugins that need host daemons, and this cluster
  mounts NFS in-tree (media, volsync repository). Keep the pre-1.14
  behaviour until that has been tested. Unknown to < 1.14 nodes, hence the
  version branch.
*/ -}}
{{ if semverCompare ">= 1.14.0-0" .Node.RuntimeData.TalosVersion -}}
apiVersion: v1alpha1
kind: SecurityProfileConfig
workloadIsolation: false
{{ end -}}

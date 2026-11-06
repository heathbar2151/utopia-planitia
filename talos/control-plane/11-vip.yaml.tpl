# Shared Kubernetes API address (clusterEndpoint). Talos moves it between
# control-plane nodes following etcd leadership, not API server health.
apiVersion: v1alpha1
kind: Layer2VIPConfig
name: {{ .Data.vip }}
link: ethSel0

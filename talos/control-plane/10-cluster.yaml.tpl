cluster:
  # Workloads run on the control-plane nodes too; see
  # control-plane/12-scheduling.yaml.
  etcd:
    extraArgs:
      listen-metrics-urls: http://0.0.0.0:2381
    advertisedSubnets:
      - {{ .Data.nodeSubnet }}
---
apiVersion: v1alpha1
kind: KubeNetworkConfig
podSubnets:
  - {{ .Data.podSubnet }}
serviceSubnets:
  - {{ .Data.serviceSubnet }}
---
# Cilium (bootstrap/helmfile.yaml) is the CNI and replaces kube-proxy.
apiVersion: v1alpha1
kind: KubeFlannelCNIConfig
$patch: delete
---
apiVersion: v1alpha1
kind: KubeProxyConfig
enabled: false
---
apiVersion: v1alpha1
kind: KubeCoreDNSConfig
enabled: false
---
apiVersion: v1alpha1
kind: KubeAPIServerConfig
certExtraSANs:
  - 127.0.0.1
  - {{ .Data.vip }}
extraArgs:
  # https://kubernetes.io/docs/tasks/extend-kubernetes/configure-aggregation-layer/
  enable-aggregator-routing: "true"
---
apiVersion: v1alpha1
kind: KubeControllerManagerConfig
extraArgs:
  bind-address: 0.0.0.0
  # Garbage-collect finished (Succeeded/Failed) pods once there are more
  # than 50 cluster-wide, oldest first. The Kubernetes default of 12500
  # meant pods that exited cleanly (e.g. during node shutdowns) were
  # never cleaned up. Count-based, so recent ones stay for debugging.
  terminated-pod-gc-threshold: "50"
---
apiVersion: v1alpha1
kind: KubeSchedulerConfig
extraArgs:
  bind-address: 0.0.0.0

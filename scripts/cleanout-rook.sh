#!/bin/bash

set -e  # Exit immediately if a command fails
set -o pipefail  # Catch errors in piped commands

NAMESPACE="rook-ceph"

echo "📢 Removing finalizers from Rook-Ceph resources..."

for resource in cephblockpools.ceph.rook.io cephclusters.ceph.rook.io cephfilesystems.ceph.rook.io cephfilesystemsubvolumegroups.ceph.rook.io; do
  for obj in $(kubectl get $resource -n $NAMESPACE --no-headers -o custom-columns=":metadata.name" 2>/dev/null); do
    echo "🛠 Patching $resource/$obj to remove finalizers..."
    kubectl patch $resource/$obj -n $NAMESPACE --type=merge -p '{"metadata":{"finalizers":[]}}' || echo "⚠️ Failed to patch $resource/$obj (may not exist)"
  done
done

echo "📢 Removing finalizers from ConfigMaps and Secrets..."

for resource in configmaps secrets; do
  for obj in $(kubectl get $resource -n $NAMESPACE --no-headers -o custom-columns=":metadata.name" 2>/dev/null); do
    echo "🛠 Patching $resource/$obj to remove finalizers..."
    kubectl patch $resource/$obj -n $NAMESPACE --type=merge -p '{"metadata":{"finalizers":[]}}' || echo "⚠️ Failed to patch $resource/$obj (may not exist)"
  done
done

echo "📢 Deleting all remaining resources in $NAMESPACE..."

kubectl delete cephblockpools.ceph.rook.io --all -n $NAMESPACE --grace-period=0 --force || echo "⚠️ Failed to delete cephblockpools"
kubectl delete cephclusters.ceph.rook.io --all -n $NAMESPACE --grace-period=0 --force || echo "⚠️ Failed to delete cephclusters"
kubectl delete cephfilesystems.ceph.rook.io --all -n $NAMESPACE --grace-period=0 --force || echo "⚠️ Failed to delete cephfilesystems"
kubectl delete cephfilesystemsubvolumegroups.ceph.rook.io --all -n $NAMESPACE --grace-period=0 --force || echo "⚠️ Failed to delete cephfilesystemsubvolumegroups"
kubectl delete configmaps,secrets --all -n $NAMESPACE --grace-period=0 --force || echo "⚠️ Failed to delete configmaps/secrets"

echo "📢 Deleting namespace $NAMESPACE..."
kubectl delete namespace $NAMESPACE --grace-period=0 --force || echo "⚠️ Failed to delete namespace (might be stuck)"

echo "✅ Cleanup completed!"

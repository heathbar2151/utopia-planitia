# Volsync PVC Restore Runbook

Use this to roll an app back to an earlier state when the current PVC data can't be used, for example after a database migration that blocks a downgrade. It replaces the PVC with a restore from a volsync backup.

It works for any app that uses the volsync component (`kubernetes/components/volsync`). Replace `<app>` and `<namespace>` everywhere.

## Prerequisites

- The image tag or digest to roll back to, if this is a version rollback
- The approximate time of the last good backup
- The Rook CSI provisioner is running:
  ```sh
  kubectl get pods -n rook-ceph | grep ctrlplugin
  ```

## Step 1: Find the last good snapshot

```sh
kubectl get replicationsource -n <namespace> <app> -o yaml
```

Look at `status.lastSyncTime` and note the last backup before the incident. The `restoreAsOf` value in Step 6 should be a minute or two after it.

## Step 2: Suspend the Flux Kustomization

```sh
flux suspend kustomization <app> -n <namespace>
```

## Step 3: Scale down the app

```sh
kubectl scale deployment -n <namespace> <app> --replicas=0
```

## Step 4: Set the image tag (version rollback only)

Set `image.tag` in `kubernetes/apps/<namespace>/<app>/app/helmrelease.yaml` to the target version and push it before Step 8. Skip this step for a data-only restore.

## Step 5: Delete the existing PVC

```sh
kubectl delete pvc -n <namespace> <app>
```

Don't recreate it by hand. The PVC comes from `kubernetes/components/volsync/pvc.yaml` with `dataSourceRef: ReplicationDestination`, so Flux recreates it in Step 8 and the volsync populator fills it.

## Step 6: Trigger the restore

Set a manual trigger and `restoreAsOf` on the ReplicationDestination. The trigger name must be new each time, so increment it on retries (`restore-now`, `restore-now-2`, ...):

```sh
kubectl patch replicationdestination -n <namespace> <app>-dst \
  --type=merge \
  -p '{"spec":{"trigger":{"manual":"restore-now"},"restic":{"restoreAsOf":"<TIMESTAMP>"}}}'
```

`<TIMESTAMP>` is RFC3339, for example `2026-01-01T12:00:00Z`.

## Step 7: Wait for the restore

Wait until the result is `Successful` and `lastManualSync` matches your trigger name:

```sh
kubectl get replicationdestination -n <namespace> <app>-dst \
  -o jsonpath='{.status.latestMoverStatus}'

kubectl get replicationdestination -n <namespace> <app>-dst \
  -o jsonpath='{.status.lastManualSync}'
```

It usually takes a few minutes, depending on data size. If it doesn't finish, check the mover logs:

```sh
kubectl logs -n <namespace> -l app.kubernetes.io/name=volsync -c volsync --tail=50
```

## Step 8: Resume the Kustomization

Make sure the Step 4 change is pushed first.

```sh
flux resume kustomization <app> -n <namespace>
```

Flux then:
1. Applies the HelmRelease (with the new image tag, if changed)
2. Recreates the PVC with `dataSourceRef: ReplicationDestination`
3. Lets the volsync populator restore the `latestImage` snapshot into it
4. Starts the pod once the PVC is bound

## Step 9: Verify

```sh
kubectl get pods -n <namespace> -w

kubectl get pod -n <namespace> -l app.kubernetes.io/name=<app> \
  -o jsonpath='{.items[0].spec.containers[0].image}'

kubectl logs -n <namespace> -l app.kubernetes.io/name=<app> -c app --tail=50
```

---

## Troubleshooting

### PVC stuck Pending

Check that the CSI provisioner is running:

```sh
kubectl get pods -n rook-ceph | grep ctrlplugin
```

If there are no pods, no PVC can be provisioned. Check the CSI ServiceAccounts and RBAC in `kubernetes/apps/rook-ceph/rook-ceph/app/csi-rbac.yaml`.

### Reconciliation error: spec is immutable

The PVC was created by hand and doesn't match the component. Delete it and let Flux recreate it:

```sh
kubectl delete pvc -n <namespace> <app>
flux reconcile kustomization <app> -n <namespace>
```

### App refuses to start because of an incompatible database

The app started before the restore, or started on the wrong image and ran a migration. Delete the PVC, use a new trigger name, and redo from Step 6.

### No eligible snapshots, or the mover can't connect

Check that the backup NFS share (`${SECRET_NAS_IP}:${SECRET_NAS_VOLSYNC_PATH}`, values in cluster-secrets) is enabled and reachable from the cluster.

### Kustomization not found

App Kustomizations live in the app's namespace, not `flux-system`:

```sh
flux resume kustomization <app> -n <namespace>
```

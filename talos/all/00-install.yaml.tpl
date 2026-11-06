{{- /*
  Install disk. The installer image comes from topf.yaml (factory +
  schematicId + talosVersion). Talos 1.14 replaced .machine.install with
  the UnattendedInstallConfig document and rejects a config that has both,
  so branch on the version the node is actually running.
*/ -}}
{{ if semverCompare ">= 1.14.0-0" .Node.RuntimeData.TalosVersion -}}
apiVersion: v1alpha1
kind: UnattendedInstallConfig
provisioning:
  diskSelector:
    match: disk.dev_path == "/dev/nvme1n1"
  wipe: false
{{ else -}}
machine:
  install:
    disk: /dev/nvme1n1
{{ end -}}

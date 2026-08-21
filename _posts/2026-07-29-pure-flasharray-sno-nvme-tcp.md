---
title: "Pure FlashArray on Single Node OpenShift with NVMe/TCP"
description: >-
  Connect a Pure FlashArray volume to Single Node OpenShift over NVMe/TCP,
  persist the path with MachineConfig, and consume it with LVMS using
  by-id paths.
date: 2026-07-29 08:30:00 -0500
categories: [OpenShift]
tags: [openshift, storage, sno, pure-storage]
og_image: /assets/img/og/pure-flasharray-sno-nvme-tcp.png
permalink: /posts/pure-flasharray-sno-nvme-tcp/
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization.
{: .prompt-info }

I wanted a Single Node OpenShift (SNO) lab that kept a Pure Storage FlashArray
volume after reboot—without hand-running `nvme connect` every time the node
came back. The pattern that stuck: connect RHCOS to the array over NVMe/TCP,
persist that connect with a MachineConfig (Ignition files + a systemd oneshot),
then hand one unused Pure NVMe namespace to LVM Storage (LVMS) using a stable
`/dev/disk/by-id/...` path.

This is a sequential lab guide for OpenShift admins who already know basic
`oc` and RHCOS. It is **not** a Portworx or Pure CSI walkthrough—just the host
path, the reboot story, and LVMS on top. For standing up the SNO itself and
the usual hub-storage choices, see the
[OpenShift PoC SNO hub](https://openshift-ssa.github.io/openshift-poc/fleet-management/sno-hub/)
and
[hub storage](https://openshift-ssa.github.io/openshift-poc/fleet-management/hub-storage/)
pages.

## Architecture overview

```text
Pure FlashArray
  (NVMe/TCP portals :4420, volume + host NQN)
        |
        |  NVMe/TCP
        v
RHCOS / SNO node
  nvme-tcp module
  systemd oneshot (MachineConfig)
  /dev/disk/by-id/nvme-Pure_Storage_FlashArray_<VOLUME>
        |
        v
LVM Storage (LVMS / TopoLVM)
  LVMCluster.deviceSelector.paths
  StorageClass (e.g. lvms-vg1)
```

MachineConfig owns durability. LVMS owns the StorageClass. Keep those jobs
separate: if the NVMe session is not back after boot, LVMS has nothing safe to
claim.

## Prerequisites

- OpenShift SNO (control-plane + worker on one node), cluster-admin
- FlashArray with Ethernet data ports you can put on the NVMe/TCP service
- Layer-3 reachability from the SNO node to those Pure data IPs on TCP **4420**
- Catalog access for the LVM Storage Operator (`redhat-operators`), including a
  pull secret if your cluster needs one
- Placeholders below are environment-specific—replace them; do not paste lab
  values into git

| Placeholder | Use |
| ----------- | --- |
| `<HOST_NQN>` | RHCOS host NQN registered on Pure |
| `<PURE_DATA_IP_n>` | FlashArray NVMe/TCP portal / data IPs |
| `<SUBSYSTEM_NQN>` | Subsystem NQN from `nvme discover` (this is `NVME_NQN`) |
| `<sno-node>` | SNO node name |
| `<VOLUME>` | Pure volume name fragment in the by-id symlink |

## Pure FlashArray setup

Do the array work before you chase RHCOS ghosts. Values and UI labels vary by
Purity version; the sequence does not.

### 1. Enable NVMe/TCP on data interfaces

In the FlashArray UI, open the network settings for the **data** Ethernet
ports (not management-only VIFs) and include **nvme-tcp** in the port services.
From the Pure CLI, the usual shape is:

```bash
# List candidate interfaces, then enable the nvme-tcp service
purenetwork eth list
purenetwork eth setattr --servicelist nvme-tcp <ctX.ethY>
```

Confirm portals:

```bash
purenetwork eth list --service nvme-tcp
```

Record the addresses as `<PURE_DATA_IP_1>`, `<PURE_DATA_IP_2>`, and so on.
You will put the comma-separated list into `NVME_ADDRS` later.

### 2. Capture the RHCOS host NQN

On the SNO node (debug shell is fine):

```bash
oc debug node/<sno-node> -- chroot /host bash -c 'cat /etc/nvme/hostnqn'
# or: nvme show-hostnqn
```

That string is `<HOST_NQN>`. If the file is missing, generate one with
`nvme gen-hostnqn` into `/etc/nvme/hostnqn` before you create the Pure host
object—then persist that file the same way you persist everything else on
RHCOS (MachineConfig), or you will get a new identity after rebuilds.

### 3. Create the host and attach the volume

**UI:** Storage → Hosts → create a host → configure NQNs → paste `<HOST_NQN>`.
Create a volume sized for the lab, then connect that volume to the host.

**CLI shape:**

```bash
purehost create --nqnlist <HOST_NQN> <pure-host-name>
purevol create --size 500G <volume-name>
purevol connect --host <pure-host-name> <volume-name>
```

You now have a host, a volume, and NVMe/TCP portals. The **subsystem** NQN
usually shows up on the host during discover (next section)—that value is
`<SUBSYSTEM_NQN>`, not the host NQN.

## Manual validation first (recommended)

Prove the fabric before you encode anything into Ignition.

```bash
oc debug node/<sno-node> -- chroot /host bash
```

Inside the node:

```bash
modprobe nvme-tcp
nvme discover -t tcp -a <PURE_DATA_IP_1> -s 4420
```

From the discover output, copy the subsystem NQN (`subnqn`) into
`<SUBSYSTEM_NQN>`, then connect:

```bash
nvme connect -t tcp -a <PURE_DATA_IP_1> -s 4420 -n <SUBSYSTEM_NQN>
# Optional second portal for another path:
# nvme connect -t tcp -a <PURE_DATA_IP_2> -s 4420 -n <SUBSYSTEM_NQN>

nvme list
nvme list-subsys
ls -l /dev/disk/by-id/nvme-Pure*
```

You want a clear namespace in `nvme list` and a symlink resembling
`/dev/disk/by-id/nvme-Pure_Storage_FlashArray_<VOLUME>`. That by-id path is
what LVMS should use. Device names like `/dev/nvme1n1` can move after reboot;
by-id generally does not.

This manual connect dies on reboot. The next section is the durable version.

## Persist with MachineConfig

I hit `RenderDegraded` on a MachineConfigPool when a file used Ignition
`contents.inline`. Prefer `contents.source` data URLs (base64 or
percent-encoded). Encode on a workstation, then paste into the MachineConfig.

Files to drop:

| Path | Role |
| ---- | ---- |
| `/etc/modules-load.d/nvme-tcp.conf` | Load `nvme-tcp` at boot |
| `/etc/nvme/nvme-tcp.env` | `NVME_ADDRS`, `NVME_NQN` (subsystem), `NVME_PORT` |
| `/usr/local/sbin/nvme-tcp-connect.sh` | Connect script |
| `/etc/systemd/system/nvme-tcp-connect.service` | Oneshot After/Wants `network-online.target` |

### Cleartext you will encode

`/etc/modules-load.d/nvme-tcp.conf`:

```text
nvme-tcp
```

`/etc/nvme/nvme-tcp.env` (replace placeholders with *your* values before
encoding):

```bash
NVME_ADDRS=<PURE_DATA_IP_1>,<PURE_DATA_IP_2>
NVME_NQN=<SUBSYSTEM_NQN>
NVME_PORT=4420
```

`/usr/local/sbin/nvme-tcp-connect.sh`:

```bash
#!/bin/bash
set -euo pipefail
ENV_FILE=/etc/nvme/nvme-tcp.env
if [[ ! -f "$ENV_FILE" ]]; then
  echo "missing $ENV_FILE" >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$ENV_FILE"
: "${NVME_ADDRS:?}"
: "${NVME_NQN:?}"
NVME_PORT="${NVME_PORT:-4420}"
modprobe nvme-tcp || true
IFS=',' read -r -a addrs <<< "$NVME_ADDRS"
for addr in "${addrs[@]}"; do
  addr="$(echo "$addr" | tr -d '[:space:]')"
  [[ -z "$addr" ]] && continue
  nvme connect -t tcp -a "$addr" -s "$NVME_PORT" -n "$NVME_NQN" || true
done
nvme list || true
```

`/etc/systemd/system/nvme-tcp-connect.service`:

```ini
[Unit]
Description=Connect NVMe/TCP to Pure FlashArray
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
EnvironmentFile=/etc/nvme/nvme-tcp.env
ExecStart=/usr/local/sbin/nvme-tcp-connect.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

Encode each file (Fedora/RHEL-compatible example):

```bash
base64 -w0 nvme-tcp.conf
base64 -w0 nvme-tcp.env
base64 -w0 nvme-tcp-connect.sh
base64 -w0 nvme-tcp-connect.service
```

On Windows PowerShell:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes('nvme-tcp.env'))
```

### MachineConfig excerpt

On SNO the pool is usually `master`. Create `99-master-nvme-tcp-pure.yaml`:

```yaml
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  name: 99-master-nvme-tcp-pure
  labels:
    machineconfiguration.openshift.io/role: master
spec:
  config:
    ignition:
      version: 3.2.0
    storage:
      files:
        - path: /etc/modules-load.d/nvme-tcp.conf
          mode: 420
          overwrite: true
          contents:
            source: data:text/plain;charset=utf-8;base64,bnZtZS10Y3AK
        - path: /etc/nvme/nvme-tcp.env
          mode: 420
          overwrite: true
          contents:
            # Replace this base64 after substituting real NVME_* values
            source: data:text/plain;charset=utf-8;base64,TlZNRV9BRERSUz08UFVSRV9EQVRBX0lQXzE+LDxQVVJFX0RBVEFfSVBfMj4KTlZNRV9OUU49PFNVQlNZU1RFTV9OUU4+Ck5WTUVfUE9SVD00NDIw
        - path: /usr/local/sbin/nvme-tcp-connect.sh
          mode: 493
          overwrite: true
          contents:
            source: data:text/plain;charset=utf-8;base64,IyEvYmluL2Jhc2gKc2V0IC1ldW8gcGlwZWZhaWwKRU5WX0ZJTEU9L2V0Yy9udm1lL252bWUtdGNwLmVudgppZiBbWyAhIC1mICIkRU5WX0ZJTEUiIF1dOyB0aGVuCiAgZWNobyAibWlzc2luZyAkRU5WX0ZJTEUiID4mMgogIGV4aXQgMQpmaQojIHNoZWxsY2hlY2sgZGlzYWJsZT1TQzEwOTAKc291cmNlICIkRU5WX0ZJTEUiCjogIiR7TlZNRV9BRERSUzo/fSIKOiAiJHtOVk1FX05RTjo/fSIKTlZNRV9QT1JUPSIke05WTUVfUE9SVDotNDQyMH0iCm1vZHByb2JlIG52bWUtdGNwIHx8IHRydWUKSUZTPScsJyByZWFkIC1yIC1hIGFkZHJzIDw8PCAiJE5WTUVfQUREUlMiCmZvciBhZGRyIGluICIke2FkZHJzW0BdfSI7IGRvCiAgYWRkcj0iJChlY2hvICIkYWRkciIgfCB0ciAtZCAnWzpzcGFjZTpdJykiCiAgW1sgLXogIiRhZGRyIiBdXSAmJiBjb250aW51ZQogIG52bWUgY29ubmVjdCAtdCB0Y3AgLWEgIiRhZGRyIiAtcyAiJE5WTUVfUE9SVCIgLW4gIiROVk1FX05RTiIgfHwgdHJ1ZQpkb25lCm52bWUgbGlzdCB8fCB0cnVl
        - path: /etc/systemd/system/nvme-tcp-connect.service
          mode: 420
          overwrite: true
          contents:
            source: data:text/plain;charset=utf-8;base64,W1VuaXRdCkRlc2NyaXB0aW9uPUNvbm5lY3QgTlZNZS9UQ1AgdG8gUHVyZSBGbGFzaEFycmF5CkFmdGVyPW5ldHdvcmstb25saW5lLnRhcmdldApXYW50cz1uZXR3b3JrLW9ubGluZS50YXJnZXQKCltTZXJ2aWNlXQpUeXBlPW9uZXNob3QKRW52aXJvbm1lbnRGaWxlPS9ldGMvbnZtZS9udm1lLXRjcC5lbnYKRXhlY1N0YXJ0PS91c3IvbG9jYWwvc2Jpbi9udm1lLXRjcC1jb25uZWN0LnNoClJlbWFpbkFmdGVyRXhpdD15ZXMKCltJbnN0YWxsXQpXYW50ZWRCeT1tdWx0aS11c2VyLnRhcmdldA==
    systemd:
      units:
        - name: nvme-tcp-connect.service
          enabled: true
```

Modes `420` and `493` are Ignition decimal for `0644` and `0755`. The env
file base64 above still contains the `<...>` placeholders—re-encode after you
substitute real IPs and the subsystem NQN.

> Do not use Ignition `contents.inline` for these files. Some Machine Config
> Operator versions reject it and the pool goes `RenderDegraded`.
{: .prompt-warning }

## Apply and wait for the MachineConfigPool

```bash
oc apply -f 99-master-nvme-tcp-pure.yaml
oc get mcp/master -w
```

Wait until `UPDATED=True`, `UPDATING=False`, `DEGRADED=False`. SNO will reboot
as the config rolls out—that is expected.

If the pool is `RenderDegraded`, inspect the rendered MachineConfig and the
MCO logs for Ignition validation errors. The first thing I check is whether
someone slipped `inline` back into a file entry.

## Verify after reboot

```bash
oc debug node/<sno-node> -- chroot /host bash -c '
  systemctl status nvme-tcp-connect.service --no-pager
  nvme list
  nvme list-subsys
  ls -l /dev/disk/by-id/nvme-Pure*
'
```

Confirm the oneshot ran after the network was up, the Pure namespace is
present, and the by-id symlink still points at the volume you intend for LVMS.

## Install and configure LVMS

LVM Storage turns that unused Pure namespace into a StorageClass. Target **one**
unused Pure NVMe namespace—never the RHCOS OS disk.

Install into the default operator namespace `openshift-lvm-storage`. Example
`lvms-install.yaml`:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-lvm-storage
  labels:
    openshift.io/cluster-monitoring: "true"
    pod-security.kubernetes.io/enforce: privileged
    pod-security.kubernetes.io/audit: privileged
    pod-security.kubernetes.io/warn: privileged
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-lvm-storage-operatorgroup
  namespace: openshift-lvm-storage
spec:
  targetNamespaces:
    - openshift-lvm-storage
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: lvms
  namespace: openshift-lvm-storage
spec:
  channel: stable-4.22
  installPlanApproval: Automatic
  name: lvms-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
```

```bash
oc apply -f lvms-install.yaml
oc get csv -n openshift-lvm-storage
```

When the CSV is `Succeeded`, create an `LVMCluster` that pins the by-id path.
Example `lvmcluster-pure.yaml`:

```yaml
apiVersion: lvm.topolvm.io/v1alpha1
kind: LVMCluster
metadata:
  name: sno-pure-nvme
  namespace: openshift-lvm-storage
spec:
  storage:
    deviceClasses:
      - name: vg1
        default: true
        deviceSelector:
          paths:
            - /dev/disk/by-id/nvme-Pure_Storage_FlashArray_<VOLUME>
          # forceWipeDevicesAndDestroyAllData: true  # destructive; see below
        thinPoolConfig:
          name: thin-pool-1
          sizePercent: 90
          overprovisionRatio: 10
```

```bash
oc apply -f lvmcluster-pure.yaml
oc get lvmcluster -n openshift-lvm-storage -o yaml
oc get sc
```

You should see a StorageClass such as `lvms-vg1`. Explicit `paths` matter: if
you omit `deviceSelector`, LVMS may claim every unused disk it likes—including
devices you did not mean to hand over on a busy lab node.

`forceWipeDevicesAndDestroyAllData: true` is an intentional, destructive
option when leftover filesystem or LVM signatures block VG creation. Default
is leave it off / `false`. Only enable it when you accept wiping that device
completely—and only after you have triple-checked it is not the OS disk.

Official field reference:
[Persistent storage using local storage (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/storage/persistent-storage-using-local-storage).

## Validate storage (smoke test)

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pure-lvms-smoke
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: lvms-vg1
  resources:
    requests:
      storage: 5Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: pure-lvms-smoke
  namespace: default
spec:
  containers:
    - name: pause
      image: registry.access.redhat.com/ubi9/ubi-minimal:latest
      command: ["sleep", "3600"]
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: pure-lvms-smoke
```

```bash
oc apply -f pure-lvms-smoke.yaml
oc get pvc pure-lvms-smoke -w
oc exec pure-lvms-smoke -- df -h /data
```

Bound PVC plus a mounted filesystem is enough to call the path good.

## Troubleshooting

| Symptom | What I check |
| ------- | ------------ |
| MCP `RenderDegraded` | File entries using `contents.inline` instead of `contents.source` |
| Service active, no devices | Unit raced the network; confirm `After=`/`Wants=network-online.target` and portal reachability to `:4420` |
| `nvme connect` fails | Host NQN on Pure, volume connected to that host, correct **subsystem** NQN in `NVME_NQN` |
| LVMS `Failed` / wrong disk | `deviceSelector.paths` must be the Pure by-id path, not `/dev/nvme0n1` (often OS) |
| Multiple data IPs | Put all portals in `NVME_ADDRS`; expect multiple paths in `nvme list-subsys`. This lab does not harden DM-multipath for a multi-node fleet |
| Device has signatures | Decide deliberately before setting `forceWipeDevicesAndDestroyAllData` |

## Cleanup and safety notes

- Point LVMS only at the unused Pure NVMe namespace. Selecting the RHCOS boot
  disk is a cluster-killing mistake.
- `forceWipeDevicesAndDestroyAllData` destroys data on the selected devices.
  Treat it like `wipefs` with a YAML switch.
- Removing the MachineConfig stops *new* connects after the next reboot; clean
  up LVMS/PVCs before you yank the disk out from under a volume group.
- Never commit real NQNs, portal IPs, API tokens, or pull secrets.

## Other storage paths on SNO

This post is one path: NVMe/TCP attach → MachineConfig → LVMS. If the same
SNO also runs
[Red Hat Advanced Cluster Management (RHACM)](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/),
Observability, and OpenShift
Virtualization, I usually choose among four patterns. Storage choice will not
fix an undersized node—those three stacks are heavy on CPU, RAM, and disk.

1. **LVMS on dedicated disks (this lab).** Edge-friendly default. Local NVMe
   or a Pure NVMe/TCP namespace, then `lvms-*` StorageClasses for RWO: operator
   PVs, Prometheus, and most VM disks. Keep the OS disk out of
   `deviceSelector`.
2. **Array-centric CSI.** Same fabric (NVMe/TCP, iSCSI, or FC), but volumes
   come from the vendor CSI (for example Pure) instead of TopoLVM. Prefer this
   when you want array snapshots, replication, or first-class LUN lifecycle on
   the FlashArray.
3. **Hybrid block + file.** LVMS or block CSI for RWO (boots, observability
   TSDB, most RHACM/operator claims) plus a small NFS/RWX class only when
   Virtualization needs shared disks. On SNO you do not get real off-box live
   migration, so RWX is for shared-volume patterns—not HA mobility.
4. **OpenShift Data Foundation.** Full platform storage (block, file, object)
   when you explicitly want Ceph features on that node—or ODF external mode
   if Ceph/RHCS already exists elsewhere. Heaviest footprint; size disks and
   memory before you treat it as the default for a single-node lab.

Sizing notes that bite in practice: Observability retention fills disks
quietly; pin by-id/by-path whenever a provisioner consumes raw devices; and
do not let auto-discovery claim the boot disk.

## Wrap-up

The durable SNO pattern is small on purpose: Pure host + volume on NVMe/TCP,
a MachineConfig that loads `nvme-tcp` and reconnects after `network-online`,
then an `LVMCluster` that selects a stable by-id path. Manual `nvme connect`
is for validation; Ignition `source` data URLs are for survival across reboot.
When LVMS is not enough, step up to vendor CSI, a hybrid RWX class, or ODF—
in that order of operational weight. For the array-centric CSI path on
multi-node Virtualization, see
[Dell Unity over iSCSI](/posts/openshift-virt-dell-unity-iscsi/). LVMS is still
local RWO—it is not a vSAN-style shared pool. For HCI SDS and certified CSI
options on OVE, see
[vSAN-like storage for OpenShift Virtualization Engine without ODF](/posts/ove-vsan-storage-alternatives/).
For when SNO
plus LVMS is the right *edge* form factor—not just a lab trick—see
[OpenShift edge architectures](/posts/openshift-edge-architectures/).

## Related posts

- [vSAN-like Storage for OpenShift Virtualization Engine](/posts/ove-vsan-storage-alternatives/)
- [OpenShift Virtualization with Dell Unity over iSCSI](/posts/openshift-virt-dell-unity-iscsi/)
- [OpenShift Edge Architectures: Form Factor, Then Fleet](/posts/openshift-edge-architectures/)

## Further reading

- [Pure Storage — NVMe-TCP on RHEL/Rocky/AlmaLinux quick start](https://support.purestorage.com/bundle/m_linux/page/Solutions/Linux/topics/t_rhel_nvme-tcp_quickstart.html)
- [OpenShift 4.22 — Persistent storage using local storage (LVM Storage)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/storage/persistent-storage-using-local-storage)
- [NVM Express — NVMe over Fabrics / TCP overview](https://nvmexpress.org/specification/nvme-of-specification/)
- [OpenShift 4.22 — Machine configuration](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/machine_configuration/index)
- [OpenShift PoC overview](https://openshift-ssa.github.io/openshift-poc/home/)
- [Hub install on SNO (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/fleet-management/sno-hub/)
- [Hub storage (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/fleet-management/hub-storage/)
- [Storage (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/post-installation/storage/)
- [Machine Config (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/operations/machine-config/)

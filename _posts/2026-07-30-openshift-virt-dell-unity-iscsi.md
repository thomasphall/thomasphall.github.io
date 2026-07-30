---
title: "Configuring OpenShift Virtualization with Dell Unity Storage over iSCSI"
description: >-
  Attach Dell Unity block storage to OpenShift over iSCSI and use it for
  OpenShift Virtualization VM disks via a CSI StorageClass.
date: 2026-07-30 07:00:00 -0500
categories: [OpenShift]
tags: [openshift, openshift-virtualization, dell-unity, iscsi, csi, storage]
permalink: /posts/openshift-virt-dell-unity-iscsi/
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization.
{: .prompt-info }

I wanted OpenShift Virtualization VM disks on Dell Unity without hand-mapping
LUNs to each worker and hoping `/dev/sdX` stayed put. The path that stuck:
enable iSCSI + multipath on RHCOS with MachineConfig, install Dell Container
Storage Modules (CSM) for Unity XT, then point VirtualMachine /
DataVolume claims at an iSCSI StorageClass.

This is a sequential lab guide for OpenShift admins who already know basic
`oc` and RHCOS. It is the **array-centric CSI** path—not host-attached LUNs
plus LVMS. Use LVMS when you already own a raw disk on the node and want a
local thin pool; use Unity CSI when you want Unisphere to own LUN lifecycle,
snapshots, and pool placement.

## Architecture overview

```text
Dell Unity XT
  (Unisphere API + iSCSI portals :3260, storage pool)
        |
        |  iSCSI (+ multipath)
        v
RHCOS workers
  iscsid.service
  multipathd.service + /etc/multipath.conf
  node IQN in /etc/iscsi/initiatorname.iscsi
        |
        v
Dell CSI Unity (CSM Operator)
  Secret: array credentials
  ContainerStorageModule CR
  StorageClass (protocol: iSCSI)
        |
        v
OpenShift Virtualization
  PVC / DataVolume → VM disk
```

MachineConfig owns initiator durability. CSI owns volume lifecycle.
Virtualization only consumes a StorageClass—keep those jobs separate.

## Prerequisites

- OpenShift Container Platform **4.22** with OpenShift Virtualization installed
- `cluster-admin`
- Dell Unity XT (or Unity with Unisphere API access) and a storage pool for lab
  volumes
- Layer-3 reachability from **worker** nodes to Unity iSCSI portals on TCP
  **3260** (dedicated storage VLAN is ideal; not required for a small lab)
- OperatorHub access for **Dell Container Storage Modules** (Certified)
- Placeholders below are environment-specific—replace them; do not paste lab
  values into git

| Placeholder | Use |
| ----------- | --- |
| `<ARRAY_ID>` | Unity array ID (Unisphere), e.g. `APM00…` |
| `<ARRAY_MGMT_HOST>` | Unisphere management URL host/IP |
| `<UNITY_ISCSI_PORTAL>` | Unity iSCSI portal IP (list all portals you use) |
| `<UNITY_IQN>` | Unity target IQN (from Unisphere / discovery) |
| `<NODE_IQN>` | RHCOS worker initiator IQN |
| `<STORAGE_POOL>` | Unity pool name for the StorageClass |
| `<STORAGE_CLASS>` | StorageClass name, e.g. `unity-<ARRAY_ID>-iscsi` |
| `<SECRET_NAME>` | Array config Secret (`unity-config` in OpenShift CSM docs) |
| `<NAMESPACE>` / `<VM_NAME>` / `<PVC_NAME>` | Workload identifiers |
| `<worker-node>` | A worker node name for debug checks |

> Verify Dell CSM / CSI Unity **supported OpenShift versions** and
> `configVersion` against current Dell docs before you pin numbers in
> GitOps. The CR examples below use values from Dell’s OpenShift Unity XT
> CSM Operator guide; bump them when your operator channel requires it.
{: .prompt-warning }

## Dell Unity setup

Do the array work before you chase RHCOS ghosts. UI labels vary by Unisphere
version; the sequence does not.

### 1. Enable iSCSI on data interfaces

In Unisphere, confirm Ethernet ports that should carry block I/O have the
**iSCSI** service (not management-only). Record portal addresses as
`<UNITY_ISCSI_PORTAL_1>`, `<UNITY_ISCSI_PORTAL_2>`, and so on. Dual portals
are why multipath shows up later.

Also capture the array ID (`<ARRAY_ID>`) and the storage pool name you will
hand to the StorageClass (`<STORAGE_POOL>`). On many Unity systems the array
ID looks like `APM…` in Unisphere system information—copy it exactly; the
StorageClass `arrayId` parameter is not a friendly display name.

If your lab shares Unisphere with other workloads, create a dedicated pool
(or a clearly named lab pool) so thin-provisioned CSI volumes do not surprise
someone else’s capacity planning.

### 2. Network path check

From a machine that can reach the storage VLAN (or from a debug shell on a
worker once networking is correct):

```bash
# Portal listening on iSCSI?
nc -vz <UNITY_ISCSI_PORTAL_1> 3260
```

If that fails, fix routing/firewall/VLAN tagging before installing CSI. The
driver will not invent a path that Layer-3 does not provide.

### 3. Host registration (CSI will help)

Dell CSI Unity registers OpenShift nodes as Unity hosts using each node’s
initiator IQN (and can refresh that mapping on an interval). You still need:

- A Unisphere user the driver can use (least privilege that can create/map
  LUNs for the lab)
- iSCSI connectivity so login and LUN attach succeed when a volume is
  provisioned

Manual host + LUN mapping is optional for a CSI lab. Prefer letting the
driver create and map volumes from the StorageClass. If your security model
requires pre-created hosts, register each `<NODE_IQN>` under a host / host
group up front and keep IQNs stable across rebuilds.

## RHCOS initiator side (MachineConfig)

On recent OpenShift/RHCOS releases, `iscsid` and a per-node initiator name
under `/etc/iscsi/initiatorname.iscsi` are often already present. Dell’s
OpenShift Unity guide still expects you to **enable** `iscsid` and configure
**multipath** for Unity via MachineConfig before installing the driver. Do
that on the `worker` pool (on SNO, use the `master` role instead).

### 1. Capture a node IQN (sanity check)

```bash
oc debug node/<worker-node> -- chroot /host bash -c '
  systemctl is-enabled iscsid || true
  systemctl status iscsid --no-pager || true
  cat /etc/iscsi/initiatorname.iscsi
'
```

That `InitiatorName=…` value is `<NODE_IQN>`. Each worker should have a
**unique** IQN. If two nodes share one, Unisphere host mapping will hurt.

### 2. Optional: prove discovery before CSI

```bash
oc debug node/<worker-node> -- chroot /host bash -c '
  iscsiadm -m discovery -t sendtargets -p <UNITY_ISCSI_PORTAL_1>
'
```

You should see `<UNITY_IQN>` (or several targets). You do **not** need to
leave a permanent manual `iscsiadm -m node --login` for the CSI path—the
node plugin handles session lifecycle for provisioned volumes. Discovery is
for proving the fabric.

### 3. Enable iscsid

`99-workers-enable-iscsid.yaml`:

```yaml
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  name: 99-workers-enable-iscsid
  labels:
    machineconfiguration.openshift.io/role: worker
spec:
  config:
    ignition:
      version: 3.4.0
    systemd:
      units:
        - name: iscsid.service
          enabled: true
```

### 4. Unity-aware multipath.conf

Cleartext `multipath.conf` (from Dell’s OpenShift Unity XT guide):

```text
defaults {
  polling_interval 5
  checker_timeout 15
  disable_changed_wwids yes
  find_multipaths no
}
devices {
  device {
    vendor                   DellEMC
    product                  Unity
    detect_prio              "yes"
    path_selector            "queue-length 0"
    path_grouping_policy     "group_by_prio"
    path_checker             tur
    failback                 immediate
    fast_io_fail_tmo         5
    no_path_retry            3
    rr_min_io_rq             1
    max_sectors_kb           1024
    dev_loss_tmo             10
  }
}
```

Encode and wrap in a MachineConfig. Prefer Ignition `contents.source` data
URLs (base64). I avoid `contents.inline` after hitting `RenderDegraded` on
other labs.

```bash
# Fedora/RHEL-compatible
base64 -w0 multipath.conf
```

`99-workers-multipath-conf.yaml` (replace the base64 if you edit the file):

```yaml
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  name: 99-workers-multipath-conf
  labels:
    machineconfiguration.openshift.io/role: worker
spec:
  config:
    ignition:
      version: 3.4.0
    storage:
      files:
        - path: /etc/multipath.conf
          mode: 256
          overwrite: true
          contents:
            source: data:text/plain;charset=utf-8;base64,ZGVmYXVsdHMgewogIHBvbGxpbmdfaW50ZXJ2YWwgNQogIGNoZWNrZXJfdGltZW91dCAxNQogIGRpc2FibGVfY2hhbmdlZF93d2lkcyB5ZXMKICBmaW5kX211bHRpcGF0aHMgbm8KfQpkZXZpY2VzIHsKICBkZXZpY2UgewogICAgdmVuZG9yICAgICAgICAgICAgICAgICAgIERlbGxFTUMKICAgIHByb2R1Y3QgICAgICAgICAgICAgICAgICBVbml0eQogICAgZGV0ZWN0X3ByaW8gICAgICAgICAgICAgICJ5ZXMiCiAgICBwYXRoX3NlbGVjdG9yICAgICAgICAgICAgInF1ZXVlLWxlbmd0aCAwIgogICAgcGF0aF9ncm91cGluZ19wb2xpY3kgICAgICJncm91cF9ieV9wcmlvIgogICAgcGF0aF9jaGVja2VyICAgICAgICAgICAgIHR1cgogICAgZmFpbGJhY2sgICAgICAgICAgICAgICAgIGltbWVkaWF0ZQogICAgZmFzdF9pb19mYWlsX3RtbyAgICAgICAgIDUKICAgIG5vX3BhdGhfcmV0cnkgICAgICAgICAgICAzCiAgICBycl9taW5faW9fcnEgICAgICAgICAgICAgMQogICAgbWF4X3NlY3RvcnNfa2IgICAgICAgICAgIDEwMjQKICAgIGRldl9sb3NzX3RtbyAgICAgICAgICAgICAxMAogIH0KfQ==
```

Mode `256` is Ignition decimal for `0400` (Dell’s sample). Mode `420`
(`0644`) also works if your site standard prefers readable config.

### 5. Enable multipathd

`99-workers-enable-multipathd.yaml`:

```yaml
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  name: 99-workers-enable-multipathd
  labels:
    machineconfiguration.openshift.io/role: worker
spec:
  config:
    ignition:
      version: 3.4.0
    systemd:
      units:
        - name: multipathd.service
          enabled: true
```

### 6. Apply and wait

```bash
oc apply -f 99-workers-enable-iscsid.yaml
oc apply -f 99-workers-multipath-conf.yaml
oc apply -f 99-workers-enable-multipathd.yaml
oc get mcp/worker -w
```

Wait until `UPDATED=True`, `UPDATING=False`, `DEGRADED=False`. Workers will
reboot as the config rolls out—that is expected.

```bash
oc debug node/<worker-node> -- chroot /host bash -c '
  systemctl is-active iscsid multipathd
  multipath -ll || true
  cat /etc/iscsi/initiatorname.iscsi
'
```

## Install Dell CSM Operator and Unity CSI

### 1. OperatorHub

In the OpenShift console: **OperatorHub** → search **Dell Container Storage
Modules** → Install into `openshift-operators` (default All namespaces /
recommended settings are fine for this lab).

```bash
oc get pods -n openshift-operators | grep -i dell
```

### 2. Project + array Secret

```bash
oc new-project unity
```

Create `config.yaml` with placeholders only—never commit real passwords:

```yaml
storageArrayList:
  - arrayId: "<ARRAY_ID>"
    username: "<unisphere-user>"
    password: "<unisphere-password>"
    endpoint: "https://<ARRAY_MGMT_HOST>/"
    skipCertificateValidation: true
    isDefault: true
```

```bash
oc create secret generic unity-config \
  --from-file=config=config.yaml \
  -n unity \
  --dry-run=client -o yaml > secret-unity-config.yaml
oc apply -f secret-unity-config.yaml
oc get secret unity-config -n unity
```

> Some Dell CSM Operator samples name the Secret `unity-creds` instead of
> `unity-config`. Match the Secret name your `ContainerStorageModule` sample
> and operator version expect—do not invent a third name.
{: .prompt-tip }

For labs, `skipCertificateValidation: true` is common. For anything shared,
install the Unisphere CA into the cert Secrets Dell documents
(`unity-cert-0`, …) and set validation accordingly.

### 3. ContainerStorageModule CR

Minimal shape from Dell’s OpenShift guide (confirm `configVersion` for your
CSM release):

```yaml
apiVersion: storage.dell.com/v1
kind: ContainerStorageModule
metadata:
  name: unity
  namespace: unity
spec:
  driver:
    csiDriverType: unity
    configVersion: v2.16.0
    forceRemoveDriver: true
```

```bash
oc apply -f csm-unity.yaml
oc get csm unity -n unity
oc get pods -n unity
```

You want `STATE=Succeeded` and controller/node pods Running. If the CR sits
in a failed state, start with operator logs and the Secret endpoint/arrayId
before you touch Virtualization.

### 4. StorageClass (iSCSI)

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: unity-<ARRAY_ID>-iscsi
provisioner: csi-unity.dellemc.com
reclaimPolicy: Delete
allowVolumeExpansion: true
volumeBindingMode: Immediate
parameters:
  protocol: iSCSI
  arrayId: "<ARRAY_ID>"
  storagepool: "<STORAGE_POOL>"
  thinProvisioned: "true"
  csi.storage.k8s.io/fstype: ext4
```

```bash
oc apply -f sc-unity-iscsi.yaml
oc get sc
```

That name is your `<STORAGE_CLASS>`. Optional parameters such as
`tieringPolicy` or `hostIOLimitName` belong in Unisphere—only set them when
they exist on your array. Dell’s sample catalog under the CSI Unity repo is
the right place to copy richer StorageClass variants.

Optional VolumeSnapshotClass:

```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: vsclass-unity
driver: csi-unity.dellemc.com
deletionPolicy: Delete
```

## Validate storage before VMs

Prove CSI before you involve CDI/DataVolumes.

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: unity-iscsi-smoke
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: unity-<ARRAY_ID>-iscsi
  resources:
    requests:
      storage: 8Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: unity-iscsi-smoke
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
        claimName: unity-iscsi-smoke
```

```bash
oc apply -f unity-iscsi-smoke.yaml
oc get pvc unity-iscsi-smoke -w
oc get pod unity-iscsi-smoke -w
oc exec unity-iscsi-smoke -- df -h /data
```

Bound PVC + mounted filesystem is the gate. On the worker that scheduled the
pod, you should also see multipath devices once the LUN is attached:

```bash
oc debug node/<worker-node> -- chroot /host bash -c 'multipath -ll; iscsiadm -m session'
```

## OpenShift Virtualization consumption

With a working StorageClass, VM disks are ordinary PVCs. Prefer
`dataVolumeTemplates` (or a DataVolume) so CDI owns import/clone when you
need a golden image; for an empty disk, a blank DataVolume is enough.

Example VirtualMachine using Unity iSCSI for the root disk:

```yaml
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: <VM_NAME>
  namespace: <NAMESPACE>
spec:
  running: true
  dataVolumeTemplates:
    - metadata:
        name: <VM_NAME>-root
      spec:
        pvc:
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 30Gi
          storageClassName: unity-<ARRAY_ID>-iscsi
        source:
          blank: {}
  template:
    metadata:
      labels:
        app: <VM_NAME>
    spec:
      domain:
        cpu:
          cores: 2
        memory:
          guest: 4Gi
        devices:
          disks:
            - name: rootdisk
              disk:
                bus: virtio
          interfaces:
            - name: default
              masquerade: {}
        resources: {}
      networks:
        - name: default
          pod: {}
      volumes:
        - name: rootdisk
          dataVolume:
            name: <VM_NAME>-root
```

```bash
oc apply -f vm-unity-root.yaml
oc get pvc,dv,vm,vmi -n <NAMESPACE>
oc get vmi <VM_NAME> -n <NAMESPACE> -o jsonpath='{.status.phase}{"\n"}'
```

You want the DataVolume/PVC Bound and the VMI Running. Console into the guest
only after that—storage problems show up as PVC Pending or VMI
scheduling/attach errors long before a guest kernel panic.

For a golden image import, point `spec.dataVolumeTemplates[].spec.source` at
`registry`, `http`, or `pvc` clone per
[OpenShift Virtualization storage docs](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/storage)
instead of `blank: {}`. Keep `storageClassName` on the Unity iSCSI class.

### Live migration note

RWO iSCSI block is the common Unity CSI pattern. Live migration needs shared
access semantics (and enough cluster capacity). Do not assume every Unity
StorageClass is migration-ready—validate your access mode and Dell feature
matrix before you promise VMotion-like behavior to stakeholders.

## Troubleshooting

| Symptom | What I check |
| ------- | ------------ |
| MCP `RenderDegraded` | Ignition `contents.inline` vs `contents.source`; invalid base64 |
| PVC Pending forever | CSM pods, `unity-config` endpoint/credentials/`arrayId`, StorageClass `storagepool` / `protocol` |
| Node plugin errors / attach fails | Worker → portal `:3260`, `iscsid` active, unique `<NODE_IQN>`, Unity host registration |
| Single path only / odd device names | `multipathd` enabled, Unity stanza in `/etc/multipath.conf`, dual portals reachable |
| VM created, disk missing | PVC/DV status first; then VMI volume status; StorageClass typo in the template |
| Cert errors to Unisphere | `skipCertificateValidation` vs proper `unity-cert-*` Secrets |
| Wrong Secret name | Align Secret with the sample for your CSM operator version |

Driver logs (namespace `unity` unless you renamed it):

```bash
oc logs -n unity -l app=csi-unity --tail=200
```

## Cleanup and safety notes

- Delete VMs / DataVolumes / PVCs before removing the StorageClass or CSM CR
  if you care about Unisphere cleanup order (`reclaimPolicy: Delete` will
  remove array volumes when PVCs go away).
- Rotating Unisphere passwords means updating the Secret and confirming the
  driver reloads config—do not leave stale credentials in git history.
- Multipath misconfiguration can confuse more than iSCSI alone; change
  `multipath.conf` deliberately and watch `mcp/worker`.
- Never commit real IQNs, portal IPs, Unisphere passwords, tokens, or pull
  secrets.

## Why not LVMS on a pre-mapped LUN?

Host-attach a Unity LUN, persist login with MachineConfig, then hand a
`/dev/disk/by-id/...` path to LVMS—the same pattern as my
[Pure FlashArray NVMe/TCP + LVMS](/posts/pure-flasharray-sno-nvme-tcp/)
lab. That is fine for SNO edge demos. For multi-node Virtualization where
you want dynamic provisioning, snapshots, and pool-backed thin volumes, Dell
CSI is the cleaner operational boundary: Unity owns the LUN, OpenShift owns
the PVC, Virtualization owns the VM.

Quick chooser:

| Need | Prefer |
| ---- | ------ |
| SNO / few nodes, one fat LUN, local thin pool | LVMS on by-id path |
| Dynamic provision per VM, Unisphere snapshots | Dell CSI Unity (this post) |
| Full platform block + file + object | OpenShift Data Foundation (heavier) |

## Wrap-up

The durable pattern is small on purpose: Unity iSCSI portals and pool,
MachineConfig for `iscsid` + Unity multipath, CSM Operator +
`ContainerStorageModule`, an iSCSI StorageClass, then VirtualMachine disks
as ordinary PVCs/DataVolumes. Prove Bound storage with a smoke pod before
you debug guest images.

### References

- [Dell CSM — Install CSI Unity XT on OpenShift (CSM Operator)](https://dell.github.io/csm-docs/docs/getting-started/installation/openshift/unityxt/csmoperator/)
- [Dell CSM — Unity XT driver (Operator parameters)](https://dell.github.io/csm-docs/v3/deployment/csmoperator/drivers/unity/)
- [Dell CSI Unity — samples](https://github.com/dell/csi-unity/tree/main/samples)
- [OpenShift 4.22 — Virtualization storage](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/storage)
- [OpenShift 4.22 — Machine configuration](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/machine_configuration/index)
- Related lab: [Pure FlashArray on SNO with NVMe/TCP + LVMS](/posts/pure-flasharray-sno-nvme-tcp/)

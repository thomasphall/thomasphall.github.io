---
title: "Fence Gray Host Failures on OpenShift Virtualization"
description: >-
  Configure Node Health Check, FAR, and PowerStore CSI so OpenShift
  Virtualization fences a hung host that still answers BMC—the gray
  failure vSphere HA misses.
date: 2026-08-26 09:30:00 -0500
categories: [OpenShift, Virtualization]
tags: [openshift, openshift-virtualization, vmware, storage, gitops, csi]
permalink: /posts/openshift-virt-gray-failure-ha/
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization.
{: .prompt-info }

vSphere HA is excellent at the failure it was designed for: the host is gone.
Heartbeats stop, the primary declares the host failed or isolated, and
protected VMs restart elsewhere from shared disk. A **gray failure** is the
other case. The host still answers management watchdogs and often still ticks
datastore heartbeats. Every guest is hung. The initiator keeps the storage
fabric busy, so healthy hosts on the same shared array slow down. vCenter
stays green. A human issues a hard reset. That reset is a crash for every
virtual machine (VM) on the box.

![VMware HA stays idle on a catatonic host while OpenShift Virtualization detects, fences, unmaps, and restarts the VM.](/assets/img/posts/openshift-virt-gray-failure-ha/compare-flows.svg)
{: .shadow .rounded-10 .w-100 }

_Same failure mode, two control planes. The guest still crashes. The difference is who fences the initiator, and when._

You cannot configure
[Red Hat OpenShift](https://www.redhat.com/en/technologies/cloud-computing/openshift)
to stop silicon from going catatonic. You *can* configure
[OpenShift Virtualization](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/index)
so that failure is detected, the node is power-cycled, the volume is
unmapped, and VMs crash-restart on a healthy worker—without waiting for a
human to notice. This post is that configuration, aimed at OpenShift
Container Platform 4.22 with Dell PowerStore Container Storage Interface
(CSI) as the shared-array example. It is GitOps-shaped, not a click-path
through the console.

If you are still building the landing zone itself, start with
[How to Get Started with an OpenShift PoC](/posts/getting-started-openshift-poc/)
and the
[OpenShift Virtualization (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/configure-the-cluster/virtualization/)
install. Identity and GitOps belong in that sequence before you freeze HA
operators:
[identity providers](https://openshift-ssa.github.io/openshift-poc/configure-the-cluster/configuring-identity-providers/)
and
[OpenShift GitOps](https://openshift-ssa.github.io/openshift-poc/configure-the-cluster/openshift-gitops/).
BMC and array passwords belong in
[External Secrets Operator](/posts/external-secrets-vs-secrets-store-csi/),
not in git.

## What “prevent” actually means

Three things stack in a gray failure: **detection** (the host looks
alive), **blast radius** (shared array frontend ports), and
**observability** (green host object). OpenShift Virtualization HA is not
installed by default in a useful form. Without Node Health Check (NHC) and a
remediator, the documented fallback is a qualified human deleting the `Node`
object—the same pager as the BMC button.

The sequence you want is:

1. **Detect** from cluster signals (kubelet `Ready`, PLEG), not from BMC
   liveness.
2. **Fence the host** with Fence Agents Remediation (FAR) over Redfish / iDRAC.
3. **Fence the disk** with `OutOfServiceTaint` so CSI unpublishes the volume.
4. **Recover VMs** with `runStrategy: Always` or `RerunOnFailure`.

![Five-step fence: detect with Node Health Check, fence the host with FAR Redfish, fence the disk with OutOfServiceTaint, unmap on PowerStore, recover the VM.](/assets/img/posts/openshift-virt-gray-failure-ha/fence-sequence.svg)
{: .shadow .rounded-10 .w-100 }

_Detect, fence host, unpublish, then start the VM. Never restart a disk-backed VMI while the old QEMU might still write._

BMC answering is *required to fence*. It is not proof the node is healthy.
That is the opposite of how vSphere HA treats management watchdogs in a gray
failure. Live migration does not apply; you cannot migrate off a hung host.
The guest still crashes. Application clustering still matters. For first-pass
Virtualization hardening around those VMs, see
[Hardening OpenShift Virtualization: First Priorities](/posts/openshift-virtualization-hardening-priorities/).

> Path B honesty: default NHC only watches `Ready`. If kubelet still
> heartbeats, OpenShift can miss the event the same way vSphere HA did. Close
> that with a Self Node Remediation (SNR) hardware watchdog, a guest
> watchdog, and I/O alerts. Do not claim Ready-based HA is complete.
{: .prompt-warning }

## Decisions to lock before YAML

| Choice              | Value                                                                                          |
| ------------------- | ---------------------------------------------------------------------------------------------- |
| Worker HA           | NHC → FAR (`fence_redfish`) → SNR if FAR times out                                             |
| Volume revoke       | FAR `OutOfServiceTaint` (not Dell CSM Resiliency)                                              |
| CSM Resiliency      | `enabled: false` — it conflicts with non-graceful node shutdown                                |
| VM disks            | PowerStore CSI, `volumeMode: Block`, `ReadWriteMany`                                           |
| Secrets             | External Secrets Operator                                                                      |
| Default MHC         | Leave `machine-api-termination-handler` alone; a custom Ready MHC **disables** NHC             |
| Workers vs control  | Two `NodeHealthCheck` objects. Never mix them.                                                 |

Put this in the **cluster** GitOps repo (namespace → OperatorGroup →
Subscription → operands), with sync-wave comments on each resource line in
`kustomization.yaml`. Application GitOps can own VM `runStrategy` and labels.
That split is the same one in
[GitOps Should Manage ACM, Not the Other Way Around](/posts/gitops-should-manage-acm/).

## Operators: Workload Availability

Install Node Health Check, Fence Agents Remediation, and Self Node Remediation
from `redhat-operators` into `openshift-workload-availability`. Channel
`stable`, `installPlanApproval: Manual`. Wait for ClusterServiceVersions to
reach `Succeeded` before you apply templates.

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-workload-availability
  annotations:
    argocd.argoproj.io/sync-wave: "0"
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: workload-availability-operator-group
  namespace: openshift-workload-availability
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  targetNamespaces:
    - openshift-workload-availability
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: node-health-check-operator
  namespace: openshift-workload-availability
  annotations:
    argocd.argoproj.io/sync-wave: "2"
spec:
  channel: stable
  name: node-health-check-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Manual
```

Repeat the Subscription pattern for `fence-agents-remediation` and
`self-node-remediation`. FAR pods must reach iDRAC on the management network.
Node names in FAR `nodeparameters` must match `oc get nodes` exactly (usually
the fully qualified domain name).

## Fence the node, then the volume

Shared iDRAC credentials via External Secrets; per-node BMC addresses in the
template, not as plaintext in git.

```yaml
apiVersion: fence-agents-remediation.medik8s.io/v1alpha1
kind: FenceAgentsRemediationTemplate
metadata:
  name: far-redfish-outofservice
  namespace: openshift-workload-availability
spec:
  template:
    spec:
      agent: fence_redfish
      remediationStrategy: OutOfServiceTaint
      retryCount: 5
      retryInterval: 5s
      timeout: 60s
      sharedSecretName: fence-agents-credentials-shared
      sharedparameters:
        "--action": reboot
        "--ssl-insecure": ""
        "--systems-uri": /redfish/v1/Systems/System.Embedded.1
      nodeparameters:
        --ip:
          worker-0.cluster.example.com: 192.168.10.20
          worker-1.cluster.example.com: 192.168.10.21
          worker-2.cluster.example.com: 192.168.10.22
```

Drop `--ssl-insecure` when iDRAC certificates are trusted. Prefer
`fence_redfish` over `fence_ipmilan` on current iDRAC. Prove it before NHC is
live:

```bash
fence_redfish --ip=192.168.10.20 --username=... --password=... \
  --ssl-insecure --systems-uri=/redfish/v1/Systems/System.Embedded.1 \
  --action=status
```

Confirm the SNR template name with
`oc get snrt -n openshift-workload-availability`. Worker `duration: 60s` is a
starting point for Virtualization HA; raise it if kubelet blips cause false
fences. For a PowerStore non-disruptive upgrade, set
`spec.pauseRequests: ["powerstore-ndu"]` on the worker NHC so an array
maintenance window is not mistaken for mass node failure.

```yaml
apiVersion: remediation.medik8s.io/v1alpha1
kind: NodeHealthCheck
metadata:
  name: nhc-virt-workers
spec:
  minHealthy: 51%
  selector:
    matchExpressions:
      - key: node-role.kubernetes.io/worker
        operator: Exists
      - key: node-role.kubernetes.io/control-plane
        operator: DoesNotExist
  unhealthyConditions:
    - type: Ready
      status: "False"
      duration: 60s
    - type: Ready
      status: Unknown
      duration: 60s
  escalatingRemediations:
    - order: 1
      timeout: 180s
      remediationTemplate:
        apiVersion: fence-agents-remediation.medik8s.io/v1alpha1
        kind: FenceAgentsRemediationTemplate
        name: far-redfish-outofservice
        namespace: openshift-workload-availability
    - order: 2
      timeout: 300s
      remediationTemplate:
        apiVersion: self-node-remediation.medik8s.io/v1alpha1
        kind: SelfNodeRemediationTemplate
        name: self-node-remediation-resource-deletion-template
        namespace: openshift-workload-availability
```

Use a second `NodeHealthCheck` for control-plane nodes with a higher
`minHealthy` and a longer duration. After SNR is installed, point
`SelfNodeRemediationConfig` at `/dev/watchdog` when the hardware has one.
That watchdog is the Path B backstop: docs call out deadlock, CPU starvation,
and loss of disk access. BMC can stay up while the node still resets.

## PowerStore: unique NQNs, then CSI, resiliency off

Red Hat Enterprise Linux CoreOS (RHCOS) ships the same NVMe host NQN on every
node. PowerStore cannot tell workers apart until you fix that—**before** CSI.
The pattern is the same class of host prep as
[Dell Unity iSCSI on OpenShift Virtualization](/posts/openshift-virt-dell-unity-iscsi/)
(MachineConfig first, driver second).

```yaml
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  name: 99-worker-custom-nvme-hostnqn
  labels:
    machineconfiguration.openshift.io/role: worker
spec:
  config:
    ignition:
      version: 3.4.0
    systemd:
      units:
        - name: custom-coreos-generate-nvme-hostnqn.service
          enabled: true
          contents: |
            [Unit]
            Description=Generate unique NVMe hostnqn
            [Service]
            Type=oneshot
            ExecStart=/usr/bin/sh -c '/usr/sbin/nvme gen-hostnqn > /etc/nvme/hostnqn'
            RemainAfterExit=yes
            [Install]
            WantedBy=multi-user.target
```

Fibre Channel or iSCSI still needs Dell `multipath.conf` and `multipathd`.
NVMe needs native multipath (`cat /sys/module/nvme_core/parameters/multipath`
should be `Y`). Do not load `nvme_tcp` if the fabric is NVMe/FC only. Zone
every virt worker to the array. Host I/O limits, queue depth, and
single-initiator multiple-target zoning live on the array and SAN—they cap a
noisy initiator while FAR runs. They do not replace fencing. Disk and IOPS
planning for the platform itself is a different post:
[OpenShift Storage Performance: Disks, IOPS, Architectures](/posts/openshift-storage-performance/).

![A sick initiator floods shared fabric links and PowerStore frontend ports, slowing healthy hosts.](/assets/img/posts/openshift-virt-gray-failure-ha/shared-fabric.svg)
{: .shadow .rounded-10 .w-100 }

_Host I/O limits buy time. They do not replace fencing. This is the same physics on ESXi and on RHCOS._

Install the certified Dell Container Storage Modules (CSM) Operator. Keep the
resiliency module **off** while FAR uses `OutOfServiceTaint`. Pin
`spec.version` to the sample that matches your operator. Store the array
stanza (`endpoint`, `globalID`, credentials, `blockProtocol`) in an
`ExternalSecret` that renders `powerstore-config`.

```yaml
apiVersion: storage.dell.com/v1
kind: ContainerStorageModule
metadata:
  name: powerstore
  namespace: powerstore
spec:
  version: v1.16.3
  driver:
    csiDriverType: powerstore
    authSecret: powerstore-config
    replicas: 2
    forceRemoveDriver: true
    csiDriverSpec:
      fSGroupPolicy: ReadWriteOnceWithFSType
      storageCapacity: true
    common:
      imagePullPolicy: IfNotPresent
      envs:
        - name: X_CSI_POWERSTORE_NODE_NAME_PREFIX
          value: csi-node
        - name: X_CSI_POWERSTORE_SKIP_CERTIFICATE_VALIDATION
          value: "true"
        - name: KUBELET_CONFIG_DIR
          value: /var/lib/kubelet
  modules:
    - name: resiliency
      enabled: false
```

Mark a ReadWriteMany Block class as the Virtualization default. Containerized
Data Importer import/clone generally wants `Immediate` binding.

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: powerstore-vm-rwx-block
  annotations:
    storageclass.kubevirt.io/is-default-virt-class: "true"
provisioner: csi-powerstore.dellemc.com
reclaimPolicy: Delete
allowVolumeExpansion: true
volumeBindingMode: Immediate
parameters:
  arrayID: "<PowerStore-globalID>"
```

After apply: `oc get storageprofile powerstore-vm-rwx-block -o yaml`. Claim
modes should include ReadWriteMany and Block.

## VMs that are allowed to fail over

```yaml
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: app-01
  namespace: vm-example
spec:
  runStrategy: Always
  template:
    spec:
      evictionStrategy: LiveMigrate
      domain:
        devices:
          disks:
            - name: rootdisk
              disk:
                bus: virtio
          watchdog:
            name: watchdog0
            i6300esb:
              action: poweroff
      volumes:
        - name: rootdisk
          dataVolume:
            name: app-01-root
```

In the guest: install `watchdog`, use `/dev/watchdog`, enable the service.
That covers a hung **guest**. A hung **host** is still NHC and FAR. Do not add
`podmon.dellemc.com/driver: csi-powerstore` while FAR `OutOfServiceTaint` is
in use.

## See Path B before Ready flips

NHC still keys off `Ready`. Alert so you page or run a playbook before the
fabric melts. Wire Alertmanager to Event-Driven Ansible if you want a human
in the loop—not a second uncoordinated remediator.

![Path A: I/O hang stalls PLEG and Ready flips so NHC fences. Path B: kubelet still heartbeats so default NHC misses it.](/assets/img/posts/openshift-virt-gray-failure-ha/path-a-path-b.svg)
{: .shadow .rounded-10 .w-100 }

_Path A is the automatic fence. Path B is the same class of miss as vSphere HA unless a watchdog or I/O alert fires._

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: virt-gray-failure
  namespace: openshift-monitoring
spec:
  groups:
    - name: virt-gray-failure
      rules:
        - alert: WorkerStorageIOWaitHigh
          expr: |
            avg by (instance) (rate(node_cpu_seconds_total{mode="iowait"}[5m])) > 0.3
          for: 2m
          labels:
            severity: critical
          annotations:
            summary: High iowait on {{ $labels.instance }}
        - alert: KubeletPlegSlow
          expr: |
            histogram_quantile(0.99,
              rate(kubelet_pleg_relist_duration_seconds_bucket[5m])) > 10
          for: 2m
          labels:
            severity: warning
```

Order-of-magnitude time-to-fence, not an SLA: Path A is often **about 4–8
minutes** with PLEG as the long pole (~3 minutes) plus a 60 second NHC wait
and Redfish. vSphere HA in a gray failure is however long it takes a human
to notice and reset. Path B without a watchdog is the same human clock.
Guest OS boot is extra on both platforms. Measure it in the lab.

![Order-of-magnitude time-to-fence: VMware waits on a human versus OpenShift Path A of about 4 to 8 minutes versus Path B unbounded.](/assets/img/posts/openshift-virt-gray-failure-ha/time-to-fence.svg)
{: .shadow .rounded-10 .w-100 }

_Not an SLA. PLEG is often the long pole on Path A. Guest OS boot is extra on both platforms._

## Prove it

Cordon is not the test.

1. `oc get csv -n openshift-workload-availability` and CSI pods in
   `powerstore` are healthy.
2. Each worker has a unique `/etc/nvme/hostnqn` and a PowerStore Host object.
3. `fence_redfish --action=status` works for every virt worker iDRAC.
4. Disposable VM on `powerstore-vm-rwx-block` with `runStrategy: Always`.
5. Induce `Ready=False` (stop kubelet in a debug session, or power-cycle from
   iDRAC) and watch `oc get nhc,far,snr -A`, nodes, VMIs, and
   VolumeAttachments.

Expect a FAR custom resource named after the node, an iDRAC reboot, the
out-of-service taint, VolumeAttachments gone, a new virtual machine instance
on another worker, and the volume remapped in PowerStore Manager. Other
workers’ VM I/O latency should drop when the initiator is fenced—not only
when the sick node’s operating system is healthy again.

## The solutions architect takeaway

1. **BMC is a reset button** — health is kubelet, PLEG, metrics, and array
   I/O. vSphere HA keys off management liveness, so this class of failure
   stays unfenced.
2. **Detect, fence host, unpublish, then start the VM** — never restart a
   disk-backed VMI while the old QEMU might still write.
3. **OutOfServiceTaint xor CSM Resiliency** — pick one volume-revoke path.
4. **PowerStore is still a shared fabric** — host I/O limits and zoning cap
   the storm; FAR cuts it. Unique NQNs are not optional.
5. **Path B is still a gray failure** — Ready-only NHC is incomplete without
   watchdog and I/O alerts.
6. **Untested `nodeparameters` is silent HA** — `fence_redfish --action=status`
   before production.

Manage operators and NHC through cluster GitOps so drift is a pull request.
Keep VM `runStrategy` with the application repo. Pause NHC during PowerStore
NDU. Leave the shipped MachineHealthCheck alone.

## Related posts

- [Virtualization Autopilot vs GitOps on OpenShift](/posts/virt-platform-autopilot-vs-gitops/)
- [Hardening OpenShift Virtualization: First Priorities](/posts/openshift-virtualization-hardening-priorities/)
- [OADP for OpenShift VMs: Backup Is Not DR](/posts/oadp-vms-backup-is-not-dr/)
- [OpenShift Storage Performance: Disks, IOPS, Architectures](/posts/openshift-storage-performance/)

> Want help mapping NHC, FAR, and PowerStore CSI onto a Virtualization landing
> zone? Reach out to your Red Hat account team—or prove `fence_redfish` and a
> disposable `runStrategy: Always` VM on a non-prod cluster first.
{: .prompt-tip }

## Further reading

- [Hardware, software, and operational requirements (OpenShift Virtualization)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/installing#virt-requirements)
- [Remediating nodes with Node Health Checks](https://docs.redhat.com/en/documentation/workload_availability_for_red_hat_openshift/25.9/html/remediation_fencing_and_maintenance/node-health-check-operator)
- [Using Fence Agents Remediation](https://docs.redhat.com/en/documentation/workload_availability_for_red_hat_openshift/25.9/html/remediation_fencing_and_maintenance/fence-agents-remediation-operator-remediate-nodes)
- [Using Self Node Remediation](https://docs.redhat.com/en/documentation/workload_availability_for_red_hat_openshift/25.9/html/remediation_fencing_and_maintenance/self-node-remediation-operator-remediate-nodes)
- [Dell CSM CSI PowerStore](https://dell.github.io/csm-docs/docs/concepts/csidriver/features/powerstore/)
- [OpenShift Virtualization (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/configure-the-cluster/virtualization/)
- [OpenShift GitOps (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/configure-the-cluster/openshift-gitops/)

---
title: "Upgrading OpenShift While VMs Stay Running"
description: >-
  How Machine Config Operator drains, live migration, and eviction strategy
  decide whether OpenShift Virtualization guests stay up through a 4.22
  upgrade.
date: 2026-10-23 11:00:00 -0500
categories: [OpenShift, Virtualization]
tags: [openshift, openshift-virtualization, gitops]
permalink: /posts/upgrading-openshift-while-vms-stay-running/
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization. Drain behavior, eviction
> defaults, and live-migration limits move. Confirm the
> [OpenShift Virtualization 4.22 update](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/updating)
> and
> [live migration](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/live-migration)
> chapters for the cluster you will actually upgrade.
{: .prompt-info }

A firmware flash and a cluster upgrade both reboot a machine. They are
different changes. Firmware servicing, covered in
[How to Update Server Firmware from OpenShift](/posts/update-server-firmware-from-openshift/),
boots one host into the Ironic Python Agent. An
[OpenShift](https://www.redhat.com/en/technologies/cloud-computing/openshift)
update keeps the node in the cluster, drains it, writes a new
[Red Hat Enterprise Linux CoreOS (RHCOS)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/machine_configuration/machine-config-index)
image, and reboots back into the cluster.

[OpenShift Virtualization](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/index)
guests stay running through that reboot only when they have already left
the node. The Machine Config Operator (MCO) drains the node first. A guest
that cannot leave holds that drain. After one hour the node is degraded
(`failed to drain node after 1 hour`), and the pool stays there until the
guest migrates or someone shuts it down. This post is how to sort those
guests before the window, on OpenShift Container Platform 4.22.

## Two phases, two moves

An update is not one reboot.

The Cluster Version Operator updates the operators first. That phase does
not reboot nodes. On a cluster update it often runs 60 to 120 minutes.
OpenShift Virtualization is one of those operators, and each minor of the
operator is supported only on the matching OpenShift minor. With the
`stable` channel and an Automatic approval strategy, the operator update
starts on its own once the cluster has moved. Most Virtualization operator
updates finish within about fifteen minutes. Moving guests onto new
`virt-launcher` pods can run longer than that reconcile.

Each virtual machine (VM) runs inside a `virt-launcher` pod. That pod is
where `libvirt` and QEMU live. `spec.workloadUpdateStrategy` on the
`HyperConverged` object decides how those pods pick up the new build:

| `workloadUpdateMethods` | Migratable guest | Guest that cannot migrate |
| ----------------------- | ---------------- | ------------------------- |
| `LiveMigrate` only (the default) | Live-migrates into a new launcher pod | Stays on the old launcher. `OutdatedVirtualMachineInstanceWorkloads` fires. |
| `LiveMigrate` and `Evict` | Live-migrates | Shuts down, in batches. `runStrategy: Always` starts a new instance on the new launcher. |
| Empty list | Left where it is | Left where it is |

Leave the method list at `LiveMigrate` only. Adding `Evict` is how you
schedule a power-off of every guest that cannot migrate, `batchEvictionSize`
at a time, `batchEvictionInterval` apart. That is a planned outage, and it
belongs on a change record.

A target pod that stays `Unschedulable` fails that attempt at about five
minutes. Any other `Pending` target fails at about fifteen. The controller
retries. A guest that can never be scheduled retries until someone changes
the VM or shuts it down. `oc get vmim -A` is the list of those attempts.
Only the last five per guest are kept.

Then the MCO updates nodes. The control-plane pool and the worker pool
proceed at the same time. Inside a pool, `spec.maxUnavailable` defaults to
`1`. For each node the MCO cordons it, drains it, writes the new
configuration, reboots, and uncordons. On bare metal, with no topology
zone, the oldest nodes go first. In a zoned cluster the zones go in
alphabetical order, oldest node in the zone first. One stuck drain holds
the next node in that pool. After one hour that node is degraded, and a
degraded node still counts against `maxUnavailable`.

The drain is a voluntary eviction. It is the moment
`evictionStrategy` matters. A guest that moved during the operator update
moves again when the node it landed on drains. A version update changes
the rendered machine config, so the workers reboot.

> A guest left on `evictionStrategy: LiveMigrate` that cannot actually
> migrate sits in `Pending` or `Scheduling`. The eviction webhook keeps
> `virt-launcher` on the node, the drain fails after one hour, and the
> node is degraded. Shut the guest down, or change the strategy and
> restart it, before you call the upgrade stuck.
{: .prompt-warning }

## Sort the guests before the window

The cluster default on a multi-node cluster is `LiveMigrate`. Single Node
OpenShift defaults to `None`, because there is nowhere to land. A
per-VM value on `spec.template.spec.evictionStrategy` overrides the
cluster default. Editing that field on a running VM does not retarget the
running instance. Restart the guest with `virtctl restart` before the
window so the new strategy is the one the drain will see.

| Strategy | What a drain does | Interrupts the guest | Can block the upgrade |
| -------- | ----------------- | -------------------- | --------------------- |
| `LiveMigrate` | Migrates, then frees the node | No, when the move succeeds | Yes, when the move cannot start or cannot finish |
| `LiveMigrateIfPossible` | Migrates when the guest can leave. Shuts it down when it cannot. | Only when migration is impossible | No |
| `None` | Shuts the guest down. Does not try to migrate. | Yes | No |

`LiveMigrate` is the right default for a guest on shared
`ReadWriteMany` (RWX) storage, with no host device, with a CPU the other
nodes can run, and with memory request capacity free somewhere else.
`None` together with `runStrategy: Always` is the product workaround for
hostpath-provisioner disks: the guest powers off for the reboot and comes
back when that node is `Ready` again, because the disk never left the box.
`LiveMigrateIfPossible` is the setting for every other guest you know may
fail to migrate (passthrough GPU, SR-IOV, a node selector with one legal
node) when the pool still has to finish.

```yaml
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: gpu-infer
  namespace: inference
spec:
  runStrategy: Always
  template:
    spec:
      evictionStrategy: LiveMigrateIfPossible
```

`runStrategy: Always` is what brings that guest back after the shutdown.
`RerunOnFailure` does not recreate an instance that stopped cleanly. Use
`Always` for a guest that must return after the node does.
`Manual` stays down until someone starts it. That is a fine choice for a
guest you intend to hold through the window. It is a poor default to
discover at 02:00.

A required node affinity or node selector that matches only the node being
drained turns an otherwise migratable guest into a blocked drain. Pin
roles and devices to a pool of nodes, not to the one server that is about
to reboot.

Passthrough devices are the common permanent case.
[OpenShift Virtualization 4.22 on NVIDIA HGX](/posts/openshift-virtualization-nvidia-hgx/)
is a whole-GPU guest. That guest does not live-migrate. Mark it
`LiveMigrateIfPossible` or `None` before the window and put the power-off
on the maintenance notice. The same rule covers SR-IOV and USB.

## What the landing node needs

Live migration needs four things at once.

1. **RWX storage.** Live migration requires `ReadWriteMany` (RWX). Use
   Block volume mode for VM disks. Local disks, LVM Storage bound to one
   node, and the hostpath provisioner are not RWX.
   [OpenShift Storage Performance: Disks, IOPS, Architectures](/posts/openshift-storage-performance/)
   is the storage side of that requirement. A two-node cluster can drain
   one node only when the survivor can take the guests; see
   [Two-Node + Arbiter for Edge OpenShift Virtualization](/posts/two-node-arbiter-edge-virtualization/).
2. **Spare memory requests.** Size it as the product of how many VM nodes
   can drain at once and the highest total VM memory requests on any one
   of those nodes. With `maxUnavailable: 1` and guests only on workers,
   that is one worker's worth of VM memory, free on the other workers,
   for the whole window. A three-node compact cluster has no second pool
   to add: those nodes belong to the `master` pool, and the `worker` pool
   is empty, so the drain is still one node.
3. **A compatible CPU.** A host-model CPU migrates only to a node that
   supports that host model. Mixed CPU generations in one virt pool fail
   this in the lab and then fail it again during the upgrade.
4. **Room under the migration caps.** The defaults are five migrations in
   the cluster and two outbound migrations per node. A drain waits its
   turn inside those caps. Raising worker `maxUnavailable` above `1`
   drains that many workers at once and multiplies the spare memory. Leave
   the control-plane pool at `1`. Do not set that pool to `3`.

`bandwidthPerMigration` defaults to `0`, which means unlimited. Two
unlimited copies on the same node NIC will contend with the guest traffic
on that NIC. The product guidance is a dedicated migration network: a
`NetworkAttachmentDefinition` in `openshift-cnv`, named from
`spec.virtualization.liveMigrationConfig.network` on the
`hco.kubevirt.io/v1` HyperConverged object. That attachment carries
migration traffic. It is not a guest NIC. Guest attachment types are
covered in
[OpenShift Virtualization Networking: Pod to Localnet](/posts/openshift-virtualization-networking/).
Set the migration network before the window. Saving it restarts
`virt-handler`. Migration traffic is TLS by default.

`completionTimeoutPerGiB` defaults to 800 seconds per GiB of guest memory.
A large, dirty guest (a busy database) can hold `maxUnavailable` for a
long time and still be within the timeout. `progressTimeout` cancels a
copy that makes no progress for 150 seconds. Post-copy (`allowPostCopy`)
is off by default. Leave it off for anything you would not pause, and
leave it off on RHCOS 10 nodes: a migration with `allowPostCopy: true`
does not complete there. Cross-migration between RHCOS 9 and RHCOS 10
workers is Technology Preview in 4.22, covered in
[RHCOS 10 on OpenShift 4.22: What Changes](/posts/rhcos-10-openshift/).

The load-aware descheduler is a different controller. It evicts
`virt-launcher` pods to chase node pressure, which also becomes a live
migration. That design is in
[Virtualization Autopilot vs GitOps on OpenShift](/posts/virt-platform-autopilot-vs-gitops/).
During this window those evictions compete with the drain for the same
five cluster-wide migration slots. Have that profile quiet before you
start.

## Own the strategy in Git

These fields belong in the cluster repo, on the `HyperConverged` object
in `openshift-cnv`. The operator reconciles its child objects from this
spec. The `v1beta1` fields below are the ones the 4.22 tuning chapter
still shows. Apply the keys you mean to own. A replace that omits a key
clears it.

```yaml
apiVersion: hco.kubevirt.io/v1beta1
kind: HyperConverged
metadata:
  name: kubevirt-hyperconverged
  namespace: openshift-cnv
spec:
  evictionStrategy: LiveMigrate
  workloadUpdateStrategy:
    workloadUpdateMethods:
      - LiveMigrate
  liveMigrationConfig:
    parallelMigrationsPerCluster: 5
    parallelOutboundMigrationsPerNode: 2
    completionTimeoutPerGiB: 800
    progressTimeout: 150
    allowPostCopy: false
```

Per-VM exceptions (`None`, `LiveMigrateIfPossible`) belong next to the
`VirtualMachine`, in the same repo. The cluster default is what a VM
inherits when its template says nothing.

The pod eviction webhook holds `virt-launcher` during a drain. KubeVirt
stopped creating a `PodDisruptionBudget` for this in 1.6, and OpenShift
Virtualization 4.22 is the 1.8 line. With `LiveMigrate`, the webhook
refuses the eviction until the migration finishes. That refusal is why a
guest that cannot migrate can hold the node.

A budget you add yourself can still hold every node. A `virt-launcher`
pod is owned by a `VirtualMachineInstance`, and that object has no scale
subresource. A budget with `maxUnavailable`, or with a percentage
`minAvailable`, reports `disruptionsAllowed: 0` and blocks every
voluntary eviction. If you must group a pool, use an integer
`minAvailable`.

Drain-driven migrations run as the virtualization controller. A person
who creates a `VirtualMachineInstanceMigration` needs the
`kubevirt.io:migrate` cluster role. That split, and the rest of who may
touch a guest, is in
[Hardening OpenShift Virtualization: First Priorities](/posts/openshift-virtualization-hardening-priorities/).

## The EUS hop is the exception

A normal z-stream or minor update should move the workers. An Extended
Update Support (EUS) hop is the case where you do not want guests
migrating during the intermediate minor. The 4.22 lifecycle framing is in
[What's New in OpenShift Virtualization 4.22](/posts/openshift-virtualization-4-22-features/).

Pause the worker `MachineConfigPool` (`spec.paused: true`) before that
hop, and set `workloadUpdateMethods` to an empty list so the operator
update does not migrate or evict. Leave the workers paused through the
intermediate minor and the target EUS update. After OpenShift
Virtualization is on the target version, restore `LiveMigrate`, watch
`oc get vmim -A`, and then unpause the worker pools. The procedure does
not wait for the outdated-launcher count to hit `0` before that unpause.

```shell
oc get kubevirt kubevirt-kubevirt-hyperconverged -n openshift-cnv \
  -o jsonpath='{.status.outdatedVirtualMachineInstanceWorkloads}{"\n"}'
oc get vmi -l kubevirt.io/outdatedLauncherImage --all-namespaces
```

A count above zero means a guest is still on the previous QEMU. Use it
before the next cluster update, once workload updates are enabled again.
The product procedure for the control-plane-only sequence is in the
Virtualization update chapter. Follow that procedure rather than pausing
workers on an ordinary upgrade.

## What to watch

Before the window:

```shell
oc get mcp
oc get nodes
oc get vm -A -o custom-columns=\
NAME:.metadata.name,\
NS:.metadata.namespace,\
STRATEGY:.spec.template.spec.evictionStrategy,\
RUN:.spec.runStrategy,\
STATUS:.status.printableStatus
```

`<none>` in `STRATEGY` means the template did not set one. On a multi-node
cluster the default is `LiveMigrate`, and the running instance usually
shows that value even when the template says `<none>`. That is the
default applied at start, not a missed restart. The drain reads the
running instance. A template you edited and did not restart still shows
the old strategy there:

```shell
oc get vmi -A -o custom-columns=\
NAME:.metadata.name,\
NS:.metadata.namespace,\
STRATEGY:.spec.evictionStrategy,\
NODE:.status.nodeName
```

Confirm the guests you expect to power off show `None` or
`LiveMigrateIfPossible` on that instance. A template value the instance
does not show has not been restarted.

While a pool shows `Updating`, a node in `SchedulingDisabled` is the one
in drain or reboot:

```shell
oc get mcp worker
oc get nodes
oc get vmim -A
```

`Succeeded` migrations are the guests that left. `Pending` and
`Scheduling` are the guests holding the drain. A gray host is a different
event: you cannot migrate off a node that is already wedged. That path is
[Fence Gray Host Failures on OpenShift Virtualization](/posts/openshift-virt-gray-failure-ha/).

## The solutions architect takeaway

1. **Two moves, then a reboot.** The operator update live-migrates guests
   that can move. The MCO drain does it again, one node at a time per
   pool, oldest bare-metal nodes first. Then the node reboots.
2. **Sort guests in Git before the window.** `LiveMigrate` for RWX guests
   with somewhere to go. `None` plus `runStrategy: Always` for hostpath.
   `LiveMigrateIfPossible` for GPUs, SR-IOV, and anything else that must
   not stall the pool. Restart after you change the strategy.
3. **Size the landing spot.** Spare memory requests equal to the fullest
   VM node, times how many VM nodes can drain at once. Leave worker
   `maxUnavailable` at `1` unless that math still holds. Leave the
   control-plane pool at `1`.
4. **The webhook holds the drain.** `LiveMigrate` makes the eviction
   webhook keep `virt-launcher` until the guest has moved. OpenShift
   Virtualization 4.22 does not create a `PodDisruptionBudget` for that.
   A hand-written budget with `maxUnavailable` blocks the drain on its
   own.
5. **EUS is the pause.** Empty `workloadUpdateMethods` and a paused worker
   pool cover both hops of a control-plane-only update. Restore
   `LiveMigrate`, watch the migrations, then unpause. An ordinary upgrade
   wants the workers to drain.

## Related posts

- [How to Update Server Firmware from OpenShift](/posts/update-server-firmware-from-openshift/)
- [Two-Node + Arbiter for Edge OpenShift Virtualization](/posts/two-node-arbiter-edge-virtualization/)
- [Fence Gray Host Failures on OpenShift Virtualization](/posts/openshift-virt-gray-failure-ha/)
- [OpenShift Virtualization 4.22 on NVIDIA HGX](/posts/openshift-virtualization-nvidia-hgx/)

> Want help planning an OpenShift upgrade around running virtual machines?
> Reach out to your Red Hat account team—or sort eviction strategy, spare
> memory, and `maxUnavailable` on a non-prod cluster before the production
> window.
{: .prompt-tip }

## Further reading

- [Updating OpenShift Virtualization (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/updating)
- [Live migration (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/live-migration)
- [Nodes: eviction and run strategies (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/nodes)
- [Understanding OpenShift updates (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/updating_clusters/understanding-openshift-updates-1)
- [Machine configuration overview (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/machine_configuration/machine-config-index)
- [OpenShift Virtualization (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/configure-the-cluster/virtualization/)
- [Machine Config (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/workloads-and-operations/day-2-operations/machine-config/)
- [VM failover (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/workloads-and-operations/operational-validation/vm-failover/)

---
title: "What Replaces vRealize Operations for VMs"
description: >-
  The few OpenShift Virtualization metrics and alerts that replace vRealize
  Operations during a VMware exit: readiness, migration, storage, and guest
  gaps.
date: 2026-09-22 07:00:00 -0500
categories: [OpenShift, Virtualization]
tags: [openshift, openshift-virtualization, vmware, migration, gitops, acm]
permalink: /posts/what-replaces-vrealize-operations/
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization.
{: .prompt-info }

vRealize Operations (vROps) earned its seat in a VMware design review by
answering five questions: is the virtual machine (VM) actually running, is
there room for the next one, is the guest in pain, is the disk slow, and did
the last move finish. VMware renamed the product to VMware Aria Operations.
The job in the room did not change. A VMware exit fails when that job is
replaced with a screenshot of every OpenShift alert.

On
[Red Hat OpenShift](https://www.redhat.com/en/technologies/cloud-computing/openshift)
Container Platform 4.22 the answers already ship with cluster monitoring and
[OpenShift Virtualization](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/index).
This post is the short list of signals to keep during the exit. It is a
solutions-architect map, not a PromQL catalog. Metric names in the
[4.22 virtualization monitoring chapter](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/monitoring)
are not an API and can change between versions. Confirm a name there before
you paste it into a `PrometheusRule`.

If the landing zone is still a diagram, start with
[How to Get Started with an OpenShift PoC](/posts/getting-started-openshift-poc/)
and the
[OpenShift Virtualization (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/configure-the-cluster/virtualization/)
install. Put alerting rules and the hub collector in git on the same
split as
[GitOps should manage ACM, not the cluster](/posts/gitops-should-manage-acm/).

## Three consoles that get mixed in the room

vROps was the performance and capacity console. Two neighbors often arrive
in the same breath, and they stay separate products on OpenShift.

| Question in the room                         | OpenShift answer                                                                 | Where it lives                                      |
| -------------------------------------------- | -------------------------------------------------------------------------------- | --------------------------------------------------- |
| Is the VM slow, full, stuck, or unschedulable? | Cluster monitoring plus OpenShift Virtualization metrics and alerts             | This post                                           |
| Who talked to whom, and was the flow dropped? | [Network Observability](/posts/network-observability-openshift/)                 | Flows, not guest CPU                                |
| What did the guest or the node log?          | OpenShift Logging with the Loki Operator                                         | Logs, not a capacity trend                          |

Network Observability is the closer cousin of Aria Operations for Networks.
Logging is the closer cousin of vRealize Log Insight. Neither one tells you
that a migrated Windows guest is swapping. Home → Overview still matters:
the Status card is the OpenShift Virtualization health rollup from alerts
and conditions. It is the "is the operator alive" tile, not the per-VM
chart.

The cluster checkup framework, including storage checkups, is Technology
Preview in 4.22. Treat it as a lab test. Do not put it on the operations
slide next to vROps.

## Where the VM metrics live

OpenShift Virtualization exposes Prometheus metrics from its own components.
The operator registers them with the platform monitoring stack. You do not
enable user-workload monitoring to see `kubevirt_vmi_*` series.
**Observe → Metrics** is the query browser for a cluster admin, or for a
user who can view every project. **Observe → Dashboards** (Perses) is where
the Node Memory Overcommit dashboard lives. That dashboard is the capacity
picture: physical memory, virtual memory assigned to VMs, pressure, and
whether hypervisor processes stayed inside their reservation.

User-workload monitoring is a different switch. Turn it on when a project
must scrape something the platform does not, usually an exporter inside a
guest. Leave it off while you are still learning the default virt series.

A single VM's first look is still the virtual machine in the console, then
**Observe → Metrics** when you need a rate across many VMs. Fleet history
is a hub problem, covered below. In-cluster Prometheus is the incident
store. It is sized for days of troubleshooting, not for a year of capacity
trending.

## Five signals worth paging on

The operator ships a long runbook list: virt-controller, virt-handler,
SSP, and HPP. Those alerts mean the hypervisor control plane is unhealthy.
Page them when they fire. Do not spend the first migration wave tuning
them. The vROps job collapses to five rows.

| vROps question              | What to watch on OpenShift                                                                 | Extra requirement                                      |
| --------------------------- | ------------------------------------------------------------------------------------------ | ------------------------------------------------------ |
| Is the VM actually running? | `VirtualMachineStuckInUnhealthyState`, `VirtLauncherPodsStuckFailed`, `KubeVirtNoAvailableNodesToRunVMs` | None; these ship with the operator                     |
| Can the next wave land?     | Node Memory Overcommit dashboard; `KubeVirtNoAvailableNodesToRunVMs`                       | Read the dashboard legend before you invent a threshold |
| Is the guest in pain?       | `KubeVirtVMGuestMemoryPressure`, `KubeVirtVMGuestMemoryAvailableLow`, `GuestFilesystemAlmostOutOfSpace`, `GuestVCPUQueueHighWarning` | Guest agent for memory and filesystem; `schedstats=enable` for vCPU queries |
| Is the disk slow?           | Read time divided by read IOPS, from the storage metrics                                   | Virt metrics; the array still has its own latency     |
| Did the move thrash?        | `kubevirt_vmi_migration_failed`, `KubeVirtVMIExcessiveMigrations`, `VMCannotBeEvicted`     | Ships with the operator                                |

`NoReadyVirtController`, `VirtHandlerDaemonSetRolloutFailing`, and
`OrphanedVirtualMachineInstances` sit beside the first row. If those fire,
you are debugging the hypervisor, not a guest that used to be a vSphere
alarm.

### Room for the next wave

The Node Memory Overcommit dashboard is the rightsizing and capacity view
vROps used to assemble with a super metric. The monitoring chapter's own
reading of the gauges: green while cluster utilization stays under 70% and
virtual memory committed stays under 120%, with pressure stall information
(PSI) near zero; amber as utilization hits 80–90% or virtual commit
approaches 150%; red above 90% utilization, PSI above 0.5, a node exceeding
its system reservation, or a per-node virtual commit above 200%.

Those colors are a legend, not your overcommit policy. An estate that
deliberately overcommits memory should move the lines with a
`PrometheusRule` in git after a wave shows the legend is wrong. An estate
that copied vSphere reservations one-for-one should treat red as "stop
importing." The workload panels compare guest-reported memory with what the
host charged for the virt-launcher. That gap is the start of a rightsizing
list. It is not a what-if simulator, and vROps what-if scenarios do not
have a button here.

`KubeVirtNoAvailableNodesToRunVMs` is the hard stop: the scheduler has
nowhere to place another VM. Capacity dashboards that stay green while that
alert fires are lying about a constraint the dashboard does not show
(CPU, a device, a taint, a local disk).

### Guest pain, and the agent gap

Host metrics see the virt-launcher. They do not see a Windows volume filling
up. `GuestFilesystemAlmostOutOfSpace`, `KubeVirtVMGuestMemoryPressure`, and
`KubeVirtVMGuestMemoryAvailableLow` read the guest. That requires the QEMU
guest agent, and the VM condition `AgentConnected`. A quiet guest panel
with the agent disconnected is missing data.

The same agent is what makes an online snapshot consistent. The
[OADP post](/posts/oadp-vms-backup-is-not-dr/) already treats it as a
backup requirement. Put it in the image before wave 1 for both reasons.
On Windows it arrives with the VirtIO drivers. Check `AgentConnected`
after Migration Toolkit for Virtualization (MTV) cutover, not only after a
hand-built lab VM.

Guest swap series (`kubevirt_vmi_memory_swap_in_traffic_bytes` and the
matching swap-out series) stay empty until the guest actually has swap
enabled. A Linux image with swap disabled will never trip a swap-rate alert. Use
the memory-pressure alerts, not a swap graph, for those guests.

vCPU delay is the steal-time counter, `kubevirt_vmi_vcpu_delay_seconds_total`.
That is the closest series to CPU ready: the guest wanted to run, and the
host ran something else. The documented query is a five-minute rate above
a small floor:

```promql
irate(kubevirt_vmi_vcpu_delay_seconds_total[5m]) > 0.05
```

vCPU wait, `kubevirt_vmi_vcpu_wait_seconds_total`, is the I/O-stall cousin.
The monitoring chapter requires the `schedstats=enable` kernel argument on
a `MachineConfig` before those vCPU queries return anything useful. That
argument adds scheduler stats and a small amount of scheduler load. Put the
`MachineConfig` in the cluster GitOps repo, roll one node, and confirm the
series exists before you alert on it. `GuestVCPUQueueHighWarning` and
`GuestVCPUQueueHighCritical` are the shipped alerts for a deep vCPU queue.
Start there if you do not yet want a custom expression.

### Disk slow is a ratio, then the array

The storage counters to know:

- `kubevirt_vmi_storage_read_traffic_bytes_total` and the write twin, for
  bytes moved
- `kubevirt_vmi_storage_iops_read_total` and the write twin, for operation
  rate
- `kubevirt_vmi_storage_read_times_seconds_total`, for time spent in reads

Average read latency is read time over read IOPS. The console's saved query
filters by VM name. The ratio without that filter:

```promql
sum by (name, namespace) (
  rate(kubevirt_vmi_storage_read_times_seconds_total[6m])
  /
  rate(kubevirt_vmi_storage_iops_read_total[6m])
)
```

A hot VM on that query is a reason to open the array, not a reason to
resize the guest. Datastore-style latency still belongs to the storage
platform. The
[storage performance post](/posts/openshift-storage-performance/)
is the disk and IOPS model; this query is how you notice a VM hitting it.
`PersistentVolumeFillingUp` is the capacity alarm on the volume. It is
closer to a datastore-usage widget than the latency ratio is.

CDI alerts (`CDINotReady`, `CDINoDefaultStorageClass`,
`CDIDataVolumeUnusualRestartCount`) are the import path. They fire while
MTV is still copying. They are wave signals. They are not the steady-state
latency signal you keep after the plan is `Succeeded`.

### Migration thrash

`kubevirt_vmi_migration_succeeded` and `kubevirt_vmi_migration_failed` are
gauges of how many migrations finished each way.
`kubevirt_vmi_migrations_in_running_phase` is how many are in flight. During a maintenance window, `kubevirt_vmi_migration_data_remaining_bytes`
and `kubevirt_vmi_migration_memory_transfer_rate_bytes` tell you whether a
running migration is making progress or rewriting dirty pages forever.
Those two are gauges for the person watching the window. They are a poor
24/7 page.

`KubeVirtVMIExcessiveMigrations` is the page: the VM keeps moving.
`VMCannotBeEvicted` is the drain that will never finish, usually a local
disk or a device that cannot migrate. Fix the placement. Do not silence
the alert to get a node upgrade through.

A host that still answers the API while every guest is hung is a different
problem. Metrics stay green often enough that this is not the detector.
That case is
[fencing a gray host failure](/posts/openshift-virt-gray-failure-ha/),
not a vROps symptom you recreate in PromQL.

## Do not rebuild the guest with node-exporter on day one

The monitoring chapter documents a second path: install `node-exporter`
inside the guest, front it with a `Service` and a `ServiceMonitor`, and
enable monitoring for user-defined projects. That is how you get process
and OS counters Prometheus will not see from the virt-launcher. It is real
work per image, and it is the long way back to a vROps agent on every VM.

Do it for a guest whose SLO is an in-guest counter you cannot see any other
way. Do not make it the standard for wave 1. The QEMU guest agent covers
filesystem fill and guest memory. Host series cover steal, storage, and
migration.

Downward metrics are the opposite direction. The `downwardMetrics` feature
gate and a device on the VM expose a set of host and VM stats *to the
guest*. On RHEL 9 you read them from the command line; `vm-dump-metrics`
is not supported there. That path is for a guest that needs to see the
hypervisor. It does not fill **Observe → Metrics**.

## Fleet history is RHACM

One cluster's **Observe** menu replaces vROps for that cluster. A program
with several clusters, or several old vCenters, needs
[Red Hat Advanced Cluster Management for Kubernetes (RHACM)](/posts/acm-openshift-virtualization/)
Observability. On 2.16 you enable it with a `MultiClusterObservability`
custom resource. The hub runs Thanos. A collector on each managed cluster
ships metrics and alerts, including OpenShift Virtualization alerts.

The RHACM **Virtual Machine** page links to Observability dashboards and
Observability metrics in Grafana. That is the multi-cluster VM view. It is
not a second product with its own symptom catalog. Series the default
collector does not keep are an allowlist entry
(`observability-metrics-custom-allowlist`), not proof the spoke failed to
scrape them. Put the `MultiClusterObservability` object and any allowlist
in the hub GitOps repo. For a PoC hub, start from
[Multicluster observability (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/configure-the-cluster/multicluster-observability/).

Retention is the actual vROps gap. Platform Prometheus answers "what broke
this afternoon." Hub Thanos answers "what did this estate do last month."
Size the hub object store for that, in the same region you already use for
the rest of the platform. AWS `us-east-2` is the usual choice on this site
when the hub is in AWS. Empty retention is how a capacity argument turns
into a screenshot from yesterday.

## The solutions architect takeaway

1. **Keep five questions** — running, room for the next VM, guest pain,
   disk latency, migration outcome. Leave the rest of the virt runbook list
   as control-plane pages.
2. **Platform Prometheus already scrapes virt metrics** — user-workload
   monitoring is for an in-guest exporter, not for `kubevirt_vmi_*`.
3. **The Node Memory Overcommit dashboard is the capacity view** — treat
   its colors as a legend. Change them in git only after a wave proves your
   overcommit policy disagrees.
4. **Guest filesystem and guest memory alerts need the QEMU guest agent** —
   `AgentConnected` after cutover. The same agent is your consistent
   snapshot. Swap graphs need swap in the guest.
5. **vCPU queries need `schedstats=enable`** — one `MachineConfig`, in git,
   rolled on purpose. Steal time is `kubevirt_vmi_vcpu_delay_seconds_total`.
6. **RHACM Observability is the multi-cluster vROps seat** — Thanos on the
   hub, virt alerts included, allowlist what the default collector drops.
7. **Flows and logs stay in their own posts** — Network Observability and
   Loki do not answer guest CPU or datastore latency.

If a non-prod cluster already runs Virtualization, the next proof is small.
Open **Observe → Dashboards**, read Node Memory Overcommit, confirm
`AgentConnected` on one migrated guest, and watch one real migration move
`kubevirt_vmi_migration_succeeded`. Then decide
whether any custom `PrometheusRule` is justified. Importing the old vROps
symptom pack before that proof is how the pager gets louder without getting
smarter.

## Related posts

- [How to Install Network Observability on OpenShift 4.22](/posts/network-observability-openshift/)
- [ACM as the Fleet Control Plane for OpenShift VMs](/posts/acm-openshift-virtualization/)
- [Fence Gray Host Failures on OpenShift Virtualization](/posts/openshift-virt-gray-failure-ha/)
- [OADP for OpenShift VMs: Backup Is Not DR](/posts/oadp-vms-backup-is-not-dr/)

> Want help choosing which VM signals to page on during a VMware exit?
> Reach out to your Red Hat account team—or confirm `AgentConnected` and
> one completed migration on a non-prod cluster before you import the old
> symptom catalog.
{: .prompt-tip }

## Further reading

- [Monitoring (OpenShift Virtualization 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/monitoring)
- [Monitoring (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/monitoring/index)
- [OpenShift Virtualization alert runbooks](https://github.com/openshift/runbooks)
- [ACM 2.16 Observability](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/2.16/html/observability/index)
- [Viewing virtual machine metrics in ACM 2.16](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/2.16/html/virtualization/acm-virt)
- [OpenShift Virtualization (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/configure-the-cluster/virtualization/)
- [Monitoring (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/configure-the-cluster/monitoring/)
- [Multicluster observability (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/configure-the-cluster/multicluster-observability/)

---
title: "How Much Spare Capacity Does Your VM Cluster Need?"
description: >-
  Plan OpenShift Virtualization CPU and memory headroom for maintenance,
  host failures, and growth. Work through an example and adapt the capacity calculator.
date: 2026-11-17 17:30:00 -0600
categories: [OpenShift, Virtualization]
tags: [openshift, openshift-virtualization, vmware, migration]
permalink: /posts/openshift-virtualization-spare-capacity/
social_title: |-
  How much
  spare capacity?
social_label: OpenShift Virtualization
social_subtitle: Maintenance · Failures · Growth
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization. The numbers below are an
> illustrative planning example. Use the support requirements for your
> release and validate the resulting design with representative workloads.
{: .prompt-info }

A six-host virtual machine cluster looks comfortable on an ordinary Tuesday.
Then one host enters maintenance, another fails, and next quarter's migration
wave needs somewhere to run.

The capacity question is whether the remaining hosts can carry that load
while the applications still meet their targets. A cluster-wide free-memory
number answers only part of it.

For Red Hat OpenShift Virtualization, I would make the capacity review cover
three things: **resource requests that fit, application performance under
the reduced capacity, and a valid destination for every affected VM.** This
post works through the arithmetic and includes a calculator you can adapt.

## Define what must stay running

Write the operating requirement as a scenario before choosing a spare-capacity
percentage:

- All hosts are available during the normal application peak.
- One host is unavailable for planned maintenance.
- One host fails while that maintenance is still in progress.
- The same conditions occur after the next migration wave or growth period.

Decide which scenarios the service must tolerate and what interruption is
allowed. Maintenance plus a separate host failure requires two hosts' worth
of capacity to be unavailable at once. If policy instead pauses maintenance
after a failure, record that limitation and how the team enforces it.

Count only hosts eligible to run these workloads. Dedicated control-plane
machines, a different CPU pool, or a worker with no access to the required
storage cannot be silently added to the recovery budget. Model a rack or
zone failure separately if that is the promised failure boundary.

An N+1 statement also needs a recovery procedure. Spare resources alone do
not establish that a failed host's VMs restart safely or within the required
time. The
[host-failure guide](/posts/openshift-virt-gray-failure-ha/)
covers the fencing and recovery side of that design.

## Keep requests, consumption, and guest sizing separate

A VM's configured vCPUs and guest RAM describe what the guest sees. The
resources requested by its launcher pod describe its scheduling footprint.
Measured consumption describes what it used during an observed workload.
Keep all three in the inventory.

The Kubernetes scheduler uses resource requests when choosing a node.
Low current utilization does not make a pod schedulable when its requests
do not fit. See the
[Kubernetes resource-management documentation](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/#how-pods-with-resource-requests-are-scheduled).
At the same time, a request that fits does not prove the application will
meet its latency or throughput target when other guests become busy.

For each resource, compare the total effective VM pod requests with the
concurrent demand measured under representative load. Use the larger as
the aggregate planning load in the simple model below. Include VM overhead
in both sides of that comparison. This conservative screen still needs
per-node placement checks and application testing.

Measure the workload together. Adding every VM's individual historical peak
can overstate concurrency; averaging an entire month can hide the batch
window that matters. Retain the observation interval, application activity,
and any missing guest telemetry. The
[benchmark guide](/posts/benchmark-openshift-vms-before-migration/)
provides a way to build that evidence before a migration wave.

For CPU, use a consistent unit across budgets and demand. Kubernetes CPU
units are the units used here; `1000m` is one CPU unit. Do not divide a
vCPU inventory by a physical-core count and treat the resulting ratio as
a measured performance limit. CPU generation, simultaneous multithreading,
dedicated CPU placement, and application behavior affect the result.

## Establish the budget available to VMs

Start from each worker's reported
[allocatable CPU and memory](https://kubernetes.io/docs/tasks/administer-cluster/reserve-compute-resources/#node-allocatable).
Account for
the non-VM workloads that must run there, including virtualization services,
monitoring, networking, and any colocated storage. Leave the operating margin
that your performance tests require.

System reservations already reflected in allocatable should not be
subtracted a second time. Conversely, allocatable has not subtracted the
requests of pods already running on the node. Reconcile the numbers rather
than mixing installed RAM, allocatable memory, and a dashboard's free memory.

Red Hat documents additional platform and per-VM overhead in the
[OpenShift Virtualization installation requirements](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/virtualization/installing).
Use those requirements to estimate a new environment, then inspect the
actual VM pod footprint and platform load. If you already counted the
launcher pod's effective request, do not add that same VM overhead again.

The calculator calls the result the **per-worker VM budget**. It is the
amount this plan allows VMs to consume on each surviving worker, after
the other commitments and operating margin have been accounted for.

For a compact cluster or workers that also provide storage, those other
commitments can change during a failure or rebuild. Use the budget for the
scenario being tested. A steady-state deduction can be too small for that
case.

## Work through a six-worker example

Assume six identical VM workers with compatible CPUs and shared storage.
The control plane runs elsewhere. Every VM in this example can use every
worker, and all can follow the planned maintenance procedure.

These are illustrative inputs, with VM overhead already included in the
workload figures:

| Input | CPU | Memory |
| --- | ---: | ---: |
| VM budget per worker | 56 CPU units | 448 GiB |
| Current aggregate VM planning load | 190 CPU units | 1,400 GiB |
| Growth through the planning horizon | 20% | 20% |
| Additional temporary load during operations | 8 CPU units | 64 GiB |

The temporary allowance represents additional work that must coexist on
the surviving workers, such as migration or import activity. It is an
assumption to validate, not an OpenShift default. Count only extra demand
that is absent from the workload total and the per-worker deductions.

Apply growth to the workload, then add the temporary allowance:

```text
Planned CPU    = 190 × 1.20 + 8  = 236 CPU units
Planned memory = 1,400 × 1.20 + 64 = 1,744 GiB
```

Now remove the unavailable workers from the supply side:

| Scenario | Available VM budget | Remaining CPU | Remaining memory |
| --- | --- | ---: | ---: |
| All six workers available | 336 CPU units / 2,688 GiB | 100 CPU units | 944 GiB |
| One worker unavailable | 280 CPU units / 2,240 GiB | 44 CPU units | 496 GiB |
| Maintenance plus a separate failure | 224 CPU units / 1,792 GiB | **−12 CPU units** | 48 GiB |

The six-worker plan covers the aggregate load with one worker unavailable.
It has a CPU shortfall when two are unavailable. Memory still fits on
paper, but that does not cancel the CPU deficit.

For this uniform pool, the arithmetic is:

```text
Survivors needed = round up the larger of:
                  planned CPU / per-worker CPU budget
                  planned memory / per-worker memory budget

Total workers = survivors needed + simultaneously unavailable workers
```

Here, CPU needs five survivors, while memory needs four. Add the two
unavailable workers and the arithmetic floor is **seven workers**. That
floor assumes the workloads can be packed onto those survivors. It still
needs placement and performance validation.

Another option is to reduce or defer demand, or agree to a narrower
maintenance and failure scenario. Make that decision explicitly before
the next wave consumes the remaining capacity.

## Try the capacity calculator

The calculator uses the example above. It assumes one pool of identical
workers and applies the same growth percentage to CPU and memory. Run
separate cases for different pools or workload mixes. A negative remainder
is a shortfall; a positive remainder is capacity left within the budgets
you entered.

{% include vm-capacity-calculator.html %}

For a more detailed forecast, replace percentage growth with the actual
next-wave inventory and revised VM sizes. You can enter those future totals
as the current load and set growth to zero. Keep temporary operational
demand separate.

## Check whether each VM has somewhere to land

Aggregate capacity is a useful first screen. It cannot prove placement.

Suppose four eligible destinations each have 96 GiB remaining within their
VM budget. Together they have 384 GiB free. A VM whose complete scheduling
footprint is 128 GiB still cannot fit on any of them without first moving
or removing another workload.

Repeat that check with the actual constraints: CPU compatibility, node
selectors, required affinity and anti-affinity, taints, storage access,
huge pages, device availability, and topology. A 128 GiB VM that can use
only two workers has a two-worker capacity problem, even if the cluster
contains twenty workers.

Inspect the largest guests and the most restricted pools first. For a
mixed-size cluster, remove the specific failed or maintained nodes from
the model. Subtracting an average host can hide the loss of the largest
worker or the only compatible destination.

## Reserve enough capacity to complete maintenance

Red Hat's
[live-migration requirements](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/virtualization/live-migration)
include shared RWX storage, compatible CPUs, and enough memory and network
capacity. Its approximate spare-memory calculation multiplies the maximum
number of concurrently draining nodes by the highest total VM memory
requests on a node. Use that check alongside the survivor calculation and
the per-VM placement review.

A live migration needs resources at the destination while the source VM
is still present. A cluster-wide memory sum can conceal that overlap.
The example removes draining workers' budgets entirely, so do not add
all their guest RAM again as a blanket migration allowance. Account for
additional activity on the surviving workers and test the actual sequence.

Available capacity also needs to last for the maintenance window. Large
guests with rapidly changing memory can take longer to migrate; concurrent
moves compete for bandwidth. Rehearse the intended drain concurrency with
representative application load and record completion times. The
[upgrade guide](/posts/upgrading-openshift-while-vms-stay-running/)
connects that rehearsal to node drains and guest evacuation.

For guests that cannot live migrate, include the agreed shutdown and
restart path in the plan. A restart does not remove the need for an
eligible destination when the original host remains unavailable.

## Treat overcommit and storage as separate decisions

Reducing a memory request can make the scheduling arithmetic fit while
leaving the real workload demand unchanged. Red Hat's
[higher VM density guidance](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/virtualization/postinstallation-configuration)
describes memory overcommitment and warns of performance effects under
high utilization. Validate any overcommit policy during the reduced-host
scenario, including guest pressure, host pressure, and application latency.

Likewise, a CPU allocation ratio does not guarantee a particular amount
of application throughput. Test shared-CPU workloads together. Review
dedicated CPUs, NUMA placement, and devices in their own eligible pools.

This calculator covers CPU and memory. Storage still needs its own capacity
and performance review: destination disks, snapshots, migration scratch
space, backup retention, growth, and rebuild activity. Network bandwidth
must cover application, storage, backup, and migration traffic that share
the same links. The
[storage performance guide](/posts/openshift-storage-performance/)
is the companion review for those limits.

## Turn the estimate into an admission decision

Before accepting the next wave, retain the inventory and workload evidence,
the scenario being protected, the remaining per-node budgets, and the
results of a maintenance rehearsal. Exercise host failure in an isolated,
representative environment with an agreed recovery procedure.

Put the resulting evidence and unresolved constraints in the
[production readiness scorecard](/posts/openshift-virtualization-production-readiness/).
Repeat the calculation when a wave lands, a VM grows, a placement rule
changes, or maintenance concurrency increases. Keep the forecast horizon
long enough to cover the time needed to acquire and prepare more capacity.

## The solutions architect takeaway

1. **Name the scenario.** One host unavailable and one host failing during
   maintenance are different capacity commitments.
2. **Budget what VMs can actually use.** Account for platform work, VM
   overhead, and the operating margin once.
3. **Check CPU and memory independently.** In the example, CPU requires an
   additional worker even though aggregate memory still fits.
4. **Prove placement and performance.** Every affected VM needs an eligible
   destination, and the application still has to meet its target.
5. **Revisit the plan before admitting growth.** Use the next wave and the
   hardware lead time to set the review date.

> Want help reviewing capacity for a VMware migration? Bring the workload
> inventory, performance evidence, and maintenance and failure scenarios
> to your Red Hat account team before committing to the next wave.
{: .prompt-tip }

## Related posts

- [Is OpenShift Virtualization Ready for Your Production VMs?](/posts/openshift-virtualization-production-readiness/)
- [Benchmark OpenShift VMs Before the First Migration Wave](/posts/benchmark-openshift-vms-before-migration/)
- [Upgrading OpenShift While VMs Stay Running](/posts/upgrading-openshift-while-vms-stay-running/)
- [What Replaces vRealize Operations for VMs](/posts/what-replaces-vrealize-operations/)

## Further reading

- [OpenShift Virtualization installation requirements (OpenShift 5.0)](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/virtualization/installing)
- [Live migration (OpenShift 5.0)](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/virtualization/live-migration)
- [Postinstallation configuration and VM density (OpenShift 5.0)](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/virtualization/postinstallation-configuration)
- [Resource management for pods and containers (Kubernetes)](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)

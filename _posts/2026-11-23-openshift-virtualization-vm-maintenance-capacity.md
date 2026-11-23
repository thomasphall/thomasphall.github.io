---
title: "How Many VMs Can You Actually Maintain on One OpenShift Cluster?"
description: >-
  Run a loaded node-drain rehearsal to find how many OpenShift VMs you can
  maintain within your change window while meeting application and storage targets.
date: 2026-11-23 08:00:00 -0600
categories: [OpenShift, Virtualization]
tags: [openshift, openshift-virtualization, storage, migration]
permalink: /posts/openshift-virtualization-vm-maintenance-capacity/
social_title: |-
  How many VMs can
  you maintain?
social_label: OpenShift Virtualization
social_subtitle: Node drains · Application latency · Storage recovery
---

> Personal site note. These views are my own and do not necessarily
> represent Red Hat. The worked example uses hypothetical rehearsal
> results.
{: .prompt-info }

You have six workers, a four-hour change window, and a migration wave
waiting for approval. The capacity spreadsheet says every virtual machine
(VM) has somewhere to go when you take a worker out. Then the first drain
takes 24 minutes, and the storage team needs another seven after the host
returns. Add the reboot and repeat that sequence across the pool, and
you're past the end of the window before allowing for a retry.

For Red Hat OpenShift Virtualization, I would set the VM count for a worker
pool by rehearsing maintenance with the applications busy. The useful number
is the largest workload mix you've shown you can evacuate and service
within the change window while keeping applications within their limits.
Start with the placement and headroom calculation, then put a clock on it.
My [spare-capacity guide and calculator](/posts/openshift-virtualization-spare-capacity/)
cover the placement side.

## What the 10,000-VM limit tells you

In its November 20 write-up, Red Hat's performance team cites a supported
limit of 10,000 VMs per cluster for OpenShift 4.22. The team exercised
drains and upgrades with 10,000 active VMs across 100 workers, with guests
actively modifying memory. It also looked at how storage disruption budgets
and Ceph recovery affected parallel drains. The introduction describes the
scenarios and leaves detailed results for later posts.
[Red Hat's scale-testing write-up](https://developers.redhat.com/blog/2026/11/20/high-scale-performance-testing-openshift-virtualization-introduction)

I'd borrow the test design. If your busiest worker runs a few large
database VMs, replay the transaction load those guests see during your
maintenance window. During live migration, memory that a guest modifies
after it has been copied may need to be sent again. Two workers with the
same VM count can take very different amounts of time to empty. The
effective migration bandwidth, eligible destinations, and storage load all
matter.
[OpenShift 4.22 live migration requirements](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/live-migration)

## Rehearse a drain with the applications busy

Pick a representative busy worker in each materially different pool.
Include a worker with the tightest placement constraints if it differs from
the one with the most VMs. Record the release, VM mix, storage layout,
migration network, and effective migration concurrency. Check each VM's
`LiveMigratable` condition and confirm there are eligible targets with
enough capacity. Agree on an outage and sequence for guests that need to be
shut down before maintenance. For an upgrade, rehearse the update path that
will drive the drain.
[Upgrading OpenShift While VMs Stay Running](/posts/upgrading-openshift-while-vms-stay-running/)

Set the application thresholds before starting. For a database-backed
service, I would record 95th-percentile transaction latency, failed requests,
and throughput under the expected load. Keep a short synthetic transaction
running from outside the VM to catch interruptions that a guest uptime check
would miss. Run the same probe before the drain, during migrations, and after
the host comes back.

Record these three milestones for each worker.

1. **Drain complete.** Start the clock when the drain begins. Record when
   the last required VM migration finishes and when the drain itself
   completes. Keep both times so you can see whether other workloads held up
   the drain. If a migration stalls, check whether it spent the time
   pending, scheduling, or running. During a running migration, graph
   `kubevirt_vmi_migration_data_remaining_bytes` and compare it with network
   utilization and guest load.
   [OpenShift 4.22 migration metrics](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/monitoring)
2. **Worker returned.** Record when servicing and reboot are complete and
   the worker is healthy and available to schedule workloads again. This
   captures the time spent on the actual change.
3. **Clear to start the next worker.** Record when application probes and
   storage meet your agreed conditions for continuing. With hyperconverged
   OpenShift Data Foundation, for example, watch Ceph health, any recovery or
   backfill, and guest I/O latency. Recovery can overlap earlier stages.
   Count only the additional wait after the worker returns.

Save the migration events, application probe results, and storage timeline
with the change record. Repeat at the planned drain concurrency before
budgeting on parallel maintenance. Two drains can compete for the same
destinations or network bandwidth, and storage disruption budgets can limit
which nodes are safe to service together.

## Work through a four-hour window

Suppose the six workers are serviced one at a time. All six need the change
that evening. The team sets aside 30 minutes for coordination, final checks,
and a retry allowance. That leaves 210 minutes for node work, or an average
of 35 minutes per worker.

- **At 120 VMs**, the timed rehearsal takes 16 minutes to drain a
  representative worker, 12 to service it and return it to scheduling, and
  two more before storage and application checks clear the next drain.
  Application latency stays inside the agreed target. At 30 minutes per
  worker, the projected window is **3 hours 30 minutes** including the
  allowance.
- **At 144 VMs**, placement still works and the application probes still
  pass. The drain takes 24 minutes, servicing takes 12, and the final wait
  takes seven. At 43 minutes per worker, the projected window is **4 hours
  48 minutes** including the same allowance.

Those projections assume the measured worker represents the other five.
In a mixed pool, budget each worker or group of comparable workers
separately. Then rehearse consecutive drains with the same sequencing you
plan to use. After the first drain, VMs may be concentrated on the next
worker in the queue, which changes the amount of work it has to do.

On these assumptions, I would take **120 VMs** into the full rehearsal and
hold the additional 24 until a new rehearsal fits the window. The timeline
gives the team somewhere to start. Check which migrations took longer and
whether the extra storage wait came from recovery or guest I/O. A change to
placement, migration bandwidth, or the maintenance schedule is worth
crediting once you've timed it under load.

## The solutions architect takeaway

Record the admission decision in terms the on-call team can use. For
example, six workers can service this 120-VM workload mix one node at a time
in four hours, provided the full rehearsal meets the application and
storage targets with the 30-minute allowance intact. Add that evidence to
the [production readiness scorecard](/posts/openshift-virtualization-production-readiness/).
Recheck it when a migration wave changes the workload mix or when the
maintenance sequence, storage, or network changes.

> Want help reviewing a VMware migration wave? Bring the drain timeline,
> application probe results, and change window to your Red Hat account team.
{: .prompt-tip }

## Related posts

- [How Much Spare Capacity Does Your VM Cluster Need?](/posts/openshift-virtualization-spare-capacity/)
- [Upgrading OpenShift While VMs Stay Running](/posts/upgrading-openshift-while-vms-stay-running/)
- [Is OpenShift Virtualization Ready for Your Production VMs?](/posts/openshift-virtualization-production-readiness/)

## Further reading

- [High Scale Performance Testing of OpenShift Virtualization](https://developers.redhat.com/blog/2026/11/20/high-scale-performance-testing-openshift-virtualization-introduction)
- [Live migration (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/live-migration)
- [Monitoring OpenShift Virtualization (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/monitoring)

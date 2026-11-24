---
title: "VMware to OpenShift Migration Guide"
description: >-
  Plan your VMware to OpenShift Virtualization move with a guided reading
  path through assessment, design, testing, migration, recovery, and daily operations.
permalink: /start-here/
icon: fas fa-compass
order: 0
---

This guide is for VMware administrators and platform teams planning a move
from vSphere to Red Hat OpenShift Virtualization. Follow the reading path
below to assess your estate, design the destination, test virtual machines
(VMs), and prepare for migration, recovery, and daily operations.

Start with the translation guide in the first stage, or jump to the decision
in front of your team. Complete the testing and recovery rehearsals before
the first production cutover.

**Jump to:** [Assess](#assess-the-estate) · [Design](#design-the-destination) ·
[Test](#prove-the-platform) · [Migrate](#plan-the-migration) ·
[Recover](#rehearse-recovery) · [Operate](#operate-the-platform)

The articles cover different product releases. Check the versions and
support references in each guide against the environment you plan to run.

## Assess the estate

Begin with what you own, what can move, and what the application needs.
Give exclusions an owner before they become migration surprises.

- [vSphere to OpenShift Virtualization: Translation Guide](/posts/vsphere-to-openshift-translation-guide/)
  maps familiar inventory, permissions, resource pools, and placement rules
  to the decisions you need to make on OpenShift.
- [OpenShift Migration Advisor: Rerun the Assessment](/posts/openshift-migration-advisor-rerun-assessment/)
  explains how to refresh the inventory, track remaining blockers, and
  scope an application wave.
- [32-bit VMs Stay Out of OpenShift Wave 1](/posts/32-bit-vms-not-wave-1/)
  helps separate legacy guest operating systems from applications that can
  run on supported guests.

**Leave this stage with:** a proposed first wave, application owners,
dependencies, and a list of workloads that need a different plan.

## Design the destination

Agree on the cluster, storage, network, and access design before scheduling
disk copies. Bring the teams that own those services into the review.

- [How to Get Started with an OpenShift PoC](/posts/getting-started-openshift-poc/)
  puts prerequisites, installation, and the first workload in order.
- [How Much Spare Capacity Does Your VM Cluster Need?](/posts/openshift-virtualization-spare-capacity/)
  works through CPU and memory budgets for maintenance, failures, and growth,
  with a calculator to adapt to your worker pool.
- [vSAN-like Storage for OpenShift Virtualization Engine](/posts/ove-vsan-storage-alternatives/)
  frames the choice between local-disk storage and an existing storage array.
- [Keep a VM on an existing datacenter VLAN](/posts/openshift-virtualization-networking/)
  walks through localnet when the destination workers can reach the VLAN.
- [Reach a ROSA VM at its own IP from an AWS VPC](/posts/rosa-bgp-cloud-connector/)
  shows how to advertise the VM network through Amazon VPC Route Server.

**Leave this stage with:** an agreed destination design and named owners
for storage, networks, access, and capacity.

## Prove the platform

Use representative applications in non-production. Agree on the acceptance
criteria before running the tests, including what happens during maintenance.

Use [Is OpenShift Virtualization Ready for Your Production VMs?](/posts/openshift-virtualization-production-readiness/)
and its downloadable checklist to collect evidence, owners, and open issues
for the go-live review.

- [Benchmark OpenShift VMs Before the First Migration Wave](/posts/benchmark-openshift-vms-before-migration/)
  builds a performance comparison around application demand and concurrent
  workloads.
- [Windows VMs on OpenShift: Build a Repeatable Standard](/posts/windows-vms-openshift-repeatable-standard/)
  connects image preparation, guest identity, drivers, patching, and restore
  tests into a repeatable Windows Server build and operating standard.
- [Hardening OpenShift Virtualization: First Priorities](/posts/openshift-virtualization-hardening-priorities/)
  gives you an initial security baseline to validate with the platform team.
- [Upgrading OpenShift While VMs Stay Running](/posts/upgrading-openshift-while-vms-stay-running/)
  explains the drain and guest-migration behavior to rehearse before an
  upgrade window depends on it.

**Leave this stage with:** recorded performance, access, and maintenance
test results, plus application-owner acceptance or a list of remaining fixes.

## Plan the migration

Choose the copy method, dependency order, validation window, and decision
to proceed or stop for each wave. Work through the recovery stage below
before executing the first production cutover.

- [VMware to OpenShift Virtualization: Copy Offload](/posts/mtv-storage-copy-offload-vmware/)
  helps determine whether a storage-assisted copy path fits your environment
  and migration window.
- [VDDK Off Broadcom's Public Portal: MTV Migrations](/posts/vddk-portal-mtv-openshift/)
  covers the access and packaging prerequisites when your Migration Toolkit
  for Virtualization (MTV) plan uses VMware's Virtual Disk Development Kit
  (VDDK).
- [Migrate Oracle Databases to OpenShift Virtualization](/posts/oracle-database-vsphere-to-openshift-virt/)
  is the additional design review for Oracle workloads, including the choice
  between a VM move and a database migration.

**Leave this stage with:** a migration runbook that names the owners,
application checks, cutover window, and rollback decision point.

## Rehearse recovery

Test how the service comes back when a migration, host, or recovery attempt
fails. Include application data written after cutover in the rehearsal.

- [Roll Back After Migrating to OpenShift Virtualization](/posts/vmware-to-openshift-migration-rollback/)
  separates returning to an unchanged source from preserving transactions
  accepted on the destination.
- [OADP for OpenShift VMs: Backup Is Not DR](/posts/oadp-vms-backup-is-not-dr/)
  separates backup, restore, and disaster recovery, and explains what to
  measure in a restore exercise.
- [Fence Gray Host Failures on OpenShift Virtualization](/posts/openshift-virt-gray-failure-ha/)
  examines the failure case where a host still responds to management
  requests while its workloads are stuck.

**Leave this stage with:** measured recovery times, verified application
data, and an agreed point at which the VMware source can be retired.

## Operate the platform

Assign ownership for alerts, maintenance, upgrades, and configuration
changes before handing the platform to the operations team.

- [What Replaces vRealize Operations for VMs](/posts/what-replaces-vrealize-operations/)
  identifies the monitoring questions to carry forward from the VMware
  environment.
- [ACM as the Fleet Control Plane for OpenShift VMs](/posts/acm-openshift-virtualization/)
  covers inventory, policy, and operations when the estate spans multiple
  clusters.
- [Park on 4.22 or Hop to 5.0 Before 4.22 Full Support Ends](/posts/openshift-4-22-vs-5-0-upgrade-decision/)
  connects the release decision to support dates, compatible Operators,
  and the update path available to each cluster.

**Leave this stage with:** an operating plan that names who responds,
who approves changes, and when maintenance and recovery rehearsals happen.

For more specific questions, browse the [migration articles](/tags/migration/),
[storage articles](/tags/storage/), or the [full archive](/archives/).

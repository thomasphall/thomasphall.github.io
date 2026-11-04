---
title: "Your VM Migrated. Can You Still Roll Back?"
description: >-
  Plan rollback from OpenShift Virtualization to VMware before cutover.
  Control production writes, preserve the source, and rehearse how changed
  data returns.
date: 2026-11-04 00:00:00 -0600
categories: [OpenShift, Virtualization]
tags: [openshift, openshift-virtualization, vmware, migration]
permalink: /posts/vmware-to-openshift-migration-rollback/
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization. The migration controls below
> refer to Migration Toolkit for Virtualization 2.12. Rehearse the return
> procedure with the application and database versions you actually run.
{: .prompt-info }

The virtual machine boots on Red Hat OpenShift Virtualization. The
application owner signs in. Someone on the change bridge says the VMware
copy is still there, so rollback is covered.

Then the application accepts an order.

If that order exists only on the new VM, powering on the old one brings
back an earlier version of the business. The source disks can be intact
and the rollback plan can still be wrong.

For a VMware vSphere migration, the useful question is **what has changed
since the source stopped, and how will those changes survive a return?**
Before the target changes production state, returning may be a controlled
restart of the source. Afterward, it needs a data recovery or application
failback procedure as well.

The
[Oracle migration post](/posts/oracle-database-vsphere-to-openshift-virt/)
uses a database standby to keep that return path current. A general
virtual machine (VM) migration needs the same conversation, even when
the workload is a file server, a queue consumer, or a small application
with its database on the boot disk.

## What MTV completes

The Red Hat Migration Toolkit for Virtualization (MTV) moves VMs to
OpenShift Virtualization. With
[warm migration](https://docs.redhat.com/en/documentation/migration_toolkit_for_virtualization/2.12/html/planning_your_migration_to_red_hat_openshift_virtualization/assembly_cold-warm-migration_mtv),
disk copying starts while the source runs. Cutover shuts the source down
and transfers the remaining data. Cold migration copies with the source
shut down. Neither approach carries the running guest's memory into the
new VM.

For a regular migration, MTV uses
[`virt-v2v` to prepare the copied guest](https://docs.redhat.com/en/documentation/migration_toolkit_for_virtualization/2.12/html/migrating_your_virtual_machines_to_red_hat_openshift_virtualization/assembly_understanding-mtv-migration_mtv)
for the destination, including changes to drivers and boot configuration.
Treat a later return of those converted disks to VMware as another
compatibility and migration exercise. Do not put an untested disk export
in the emergency procedure.

MTV also lets you
[cancel an in-progress migration](https://docs.redhat.com/en/documentation/migration_toolkit_for_virtualization/2.12/html/migrating_your_virtual_machines_to_red_hat_openshift_virtualization/assembly_migrating-from-vmware_mtv).
The documented behavior leaves already-migrated VMs unchanged. Canceling
the rest of a wave does not return its completed VMs to vSphere or move
their new application data back.

Record migration completion and application acceptance separately. The
first says the move finished. The second says the service works and its
recovery procedure is ready for the next failure.

## Find every place the application can write

Start with the application owner and follow one transaction. Record the
database, uploaded files, shared storage, message queues, and outside
services it touches. Include jobs that run without a user signing in.

A moved web server with a database that stays in place may have little
local data to return. It still needs an application version compatible
with the current database schema. A moved database VM has a different
problem: its old disks stop receiving transactions when the source stops.

The first important write might happen before you change DNS. A service
can start a scheduled job, consume a message, rotate a shared credential,
or call a payment API as soon as the guest boots. Removing the VM from a
load balancer only controls the traffic that passes through that load
balancer.

An isolated boot also writes logs and operating-system state. Decide
which changes are disposable and which affect production. The boundary
is the first change the business needs to preserve, whether it lands on
the VM or somewhere else.

For each application, write down three things:

- **Where authoritative data lives.** Include dependencies outside the
  migration wave and the owner who can verify their state.
- **What can change it.** User requests, integrations, scheduled tasks,
  queue consumers, and startup actions all count.
- **How it returns.** Name the replication, restore, replay, or
  reconciliation procedure, and who has rehearsed it.

If the third answer is only "the old VM is still powered off," the
procedure covers an unchanged application state. Keep production writers
closed until the plan addresses the next state too.

## Walk the cutover clock

Consider a warm migration of an order application and its database. These
times are illustrative; the checkpoints belong in the change record.

1. **21:50 — Close production writers.** Put the application into its
   maintenance state, drain active work, stop consumers and scheduled
   jobs, and close the database cleanly. Verify the application is quiet
   before the final transfer. Record the last accepted transaction or
   another application checkpoint the owner can verify.
2. **22:00 — Cut over the VMs.** Complete the final transfer. Confirm the
   source VMs are off and protected against an accidental restart. Keep
   their disks, configuration, and required vSphere capacity available.
3. **22:20 — Validate the target with production access blocked.** Check
   boot, disks, network paths, application startup, and the recorded data
   checkpoint. Keep background writers and outbound integrations under
   the same controls as user traffic. Any test writes must have an agreed
   disposition.
4. **22:35 — Authorize production writes.** The application owner accepts
   the checks and the named operator opens the service. Record this time
   separately from MTV completion. From here, use the procedure that
   preserves new transactions if you need to return.
5. **23:05 — A fault appears under load.** Stop admitting new work and
   identify the authoritative copy. If the target accepted orders, those
   orders must survive the recovery decision. Booting the old database
   cannot recover records its disks never received.

At 22:20, a failed check may still lead to a straightforward source
restart. At 23:05, the same symptom can require replication, restore,
or transaction reconciliation. Elapsed time alone does not choose the
procedure. Changed application state does.

## Make the validation window real

MTV 2.12 exposes a
[target power-state setting](https://docs.redhat.com/en/documentation/migration_toolkit_for_virtualization/2.12/html/planning_your_migration_to_red_hat_openshift_virtualization/assembly_migrating-vms-web-console_mtv):
`off`, `on`, or `auto`. The `auto` setting preserves the source power
state. For a wave that requires an explicit startup decision, select
**Powered off** and verify that behavior in the rehearsal.

That setting gives the operator control over startup after migration.
It does not define which destinations the guest can reach once started.
Prepare the validation network and application controls before booting
the target, and review migration hooks for actions that change external
systems.

Use the actual
[VM network attachment](/posts/openshift-virtualization-networking/)
to decide where isolation is enforced. Have the network owner prove that
the target cannot reach prohibited production endpoints. A namespace
label or an untested policy is insufficient evidence for an application
attached to an existing VLAN.

Keep duplicate hostnames and addresses separated. Give testers only the
access the rehearsal requires. If authentication or another shared
service must remain reachable, include its possible state changes in the
return procedure.

Test writes need the same attention. An order that sends an email,
reserves inventory, or reaches a payment service leaves effects outside
the VM. Deleting its local database row does not undo those effects. Use
test endpoints or a documented reconciliation procedure.

## Return before production state changes

For a retained source with no production changes to preserve, the return
sequence is relatively small. Rehearse it for the whole application:

1. Stop any remaining migration or automation activity that could start
   a target or change its routing. Confirm the resulting state.
2. Stop and isolate the target VMs. Verify they cannot serve traffic or
   resume background work while the source returns.
3. Check dependencies outside the VMs for changes made during validation,
   including credentials, application configuration, and test activity.
4. Start the retained source VMs in the application dependency order.
   Verify their data checkpoint and service health.
5. Restore the intended client path and reopen writers. Check actual
   client connections; DNS caches and established sessions can outlive
   a routing change.

Assign one person control of the source/target handoff. A powered-off VM
can still be started by another administrator or an automation job.
Record the controls that prevent that, and verify them on both platforms.

Keep the target disks and logs available for diagnosis until the
application owner releases them. Recovery is a poor time to discover
that cleanup removed the evidence needed to explain the failure.

## Return after the target accepts writes

Once production state changes, choose the recovery path based on where
the current data is and how it can be preserved.

**Repair on OpenShift.** A network mapping or application configuration
problem may be faster to correct in place while retaining the current
data. Compare that work with the measured return procedure before
committing to another move.

**Switch back through application replication.** If the old environment
has remained a valid replica, use the application's role-transition
procedure. Oracle Data Guard, for example, supports a
[planned switchover](https://docs.oracle.com/en/database/oracle/oracle-database/19/sbydb/managing-oracle-data-guard-role-transitions.html)
between a primary and standby without data loss. The databases continue
in their new roles. Verify synchronization and readiness before a
switchback, and include application connections in the rehearsal.

This is why the Oracle design keeps the former primary participating as
a standby. That VM is intentionally running in a replication role. The
power-off rule for an independent, stale source copy does not apply to
a correctly managed standby.

**Recover current data into the return environment.** Without a replica,
the application may need a native backup and restore, log recovery, or
an export and import into a compatible guest. Measure that full path,
including validation. Reconcile external messages and transactions that
a database restore cannot reverse.

If current data cannot be recovered within the outage budget, the
business owner has a decision about outage duration and possible data
loss. Record exactly what would be lost before taking that path. A
healthy old VM does not make the decision disappear.

The
[backup and disaster recovery distinction](/posts/oadp-vms-backup-is-not-dr/)
still applies. A restore point has a time and a scope. Identify the
latest recoverable transaction and the destination where the restore has
actually been tested.

## Budget time for the return

Put the latest decision time in the change record. Calculate it from the
service restoration deadline, the measured recovery duration for the
current application state, and a margin for validation.

For example, if service must be available by 02:00, a rehearsed return
takes 45 minutes, and the agreed margin is 15 minutes, the decision is
due at 01:00. Those numbers are a planning example, not an MTV estimate.
If new writes require a two-hour restore, the 45-minute source-restart
measurement no longer applies.

Name the person who can stop the attempt, the application owner who
accepts recovery, and the operators for both platforms. Put observable
failure conditions beside the deadline: a required transaction fails,
data checks disagree, or an essential dependency remains unavailable.

Rehearse two failures in non-production. First, reject the target before
production access opens and prove the source returns. Then commit
identifiable test transactions on the target, invoke the recovery path,
and prove those transactions survive. Include a queue message or an
external test integration if the application uses one.

## Retire the source after recovery is proven

Keep source capacity through an agreed acceptance period that includes
the important business jobs. A successful login says little about the
overnight batch or the next scheduled export.

Before retiring the source, require application acceptance, functioning
monitoring, and a successful backup and representative restore from the
new environment. Record the recovery procedure that will apply after
the old VM is gone.

Preserve the migration evidence before housekeeping. MTV's
[archive operation](https://docs.redhat.com/en/documentation/migration_toolkit_for_virtualization/2.12/html/migrating_your_virtual_machines_to_red_hat_openshift_virtualization/assembly_migrating-from-vmware_mtv)
removes plan logs, history, and metadata and is irreversible. Export what
the operations team needs before archiving the plan.

Retaining an unreplicated source for seven days does not give it seven
days of new transactions. Retention buys time to investigate and keeps
an environment available. A current return path still needs current data.

## The solutions architect takeaway

1. **Record the write boundary.** Application startup, background jobs,
   and external integrations can cross it before user traffic opens.
2. **Keep a controlled validation window.** Choose the target power
   state, prove isolation, and define how test changes are handled.
3. **Write two return procedures.** One for an unchanged production
   state, another for preserving transactions accepted after cutover.
4. **Measure the whole recovery.** Include data movement, dependency
   checks, client routing, and application acceptance in the deadline.
5. **Prove recovery before cleanup.** Preserve the source and migration
   evidence until the new service and its recovery path are accepted.

For the next rehearsal, migrate one non-production application, write a
transaction on the destination, and recover it through the proposed
return path. The transaction is the proof that matters to the person
who owns the service.

## Related posts

- [Migrate Oracle Databases to OpenShift Virtualization](/posts/oracle-database-vsphere-to-openshift-virt/)
- [vSphere to OpenShift Virtualization: Translation Guide](/posts/vsphere-to-openshift-translation-guide/)
- [OADP for OpenShift VMs: Backup Is Not DR](/posts/oadp-vms-backup-is-not-dr/)
- [AI Agents for MTV: vSphere to OpenShift Virtualization](/posts/ai-agents-mtv-vsphere/)

> Want help turning a migration wave into a cutover and recovery plan?
> Reach out to your Red Hat account team—or rehearse one application
> return with a transaction that must survive before scheduling production.
{: .prompt-tip }

## Further reading

- [Cold and warm migration in MTV 2.12](https://docs.redhat.com/en/documentation/migration_toolkit_for_virtualization/2.12/html/planning_your_migration_to_red_hat_openshift_virtualization/assembly_cold-warm-migration_mtv)
- [MTV 2.12 migration plans and target power state](https://docs.redhat.com/en/documentation/migration_toolkit_for_virtualization/2.12/html/planning_your_migration_to_red_hat_openshift_virtualization/assembly_migrating-vms-web-console_mtv)
- [Migrating from VMware vSphere with MTV 2.12](https://docs.redhat.com/en/documentation/migration_toolkit_for_virtualization/2.12/html/migrating_your_virtual_machines_to_red_hat_openshift_virtualization/assembly_migrating-from-vmware_mtv)
- [Understanding MTV migration and guest conversion](https://docs.redhat.com/en/documentation/migration_toolkit_for_virtualization/2.12/html/migrating_your_virtual_machines_to_red_hat_openshift_virtualization/assembly_understanding-mtv-migration_mtv)
- [Oracle Data Guard 19c role transitions](https://docs.oracle.com/en/database/oracle/oracle-database/19/sbydb/managing-oracle-data-guard-role-transitions.html)
- [Migration Toolkit for Virtualization (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/configure-the-cluster/mtv/)

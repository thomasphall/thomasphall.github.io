---
title: "Is OpenShift Virtualization Ready for Your Production VMs?"
description: >-
  Use OpenShift Virtualization readiness scorecards to review performance,
  maintenance, recovery, access, and ownership before production. Download the checklist.
date: 2026-11-17 16:00:00 -0600
categories: [OpenShift, Virtualization]
tags: [openshift, openshift-virtualization, migration, vmware]
permalink: /posts/openshift-virtualization-production-readiness/
social_title: |-
  Ready for
  production VMs?
social_label: OpenShift Virtualization
social_subtitle: Evidence · Owners · Go-live decisions
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization. This scorecard is an acceptance
> framework to adapt to your workloads. Product support requirements come
> from the documentation and compatibility guidance for the versions you run.
{: .prompt-info }

The first virtual machine boots. The application owner can sign in. Storage
looks fast, and the cluster dashboard is green. The project starts looking
for a production date.

Before that date goes on the calendar, ask who has watched the application
through a node drain, restored its data, and received its failure alert.
Those answers often belong to three different teams. Production readiness
is the point where those teams can show the evidence and agree on what
they are accepting.

For Red Hat OpenShift Virtualization, I would use the eight areas below to
run that review. Each area needs a test, an owner, a result, and a place to
record what remains unresolved. **Approve a defined workload on a defined
configuration, under conditions you have tested.**

[Download the production readiness checklist (Excel)](/assets/downloads/openshift-virtualization-production-readiness.xlsx).
It contains 24 checks with fields for status, owner, evidence, open issues,
due or review date, and approver. Start a separate copy for each application
wave or materially different workload class.

If the destination design is still taking shape, follow the
[VMware to OpenShift Migration Guide](/start-here/) first.

## Define the scope before marking a pass

A small Linux application and a large database with dedicated devices need
different acceptance tests. Write down the applications, VM sizes, guest
operating systems, storage classes, networks, and special hardware in scope.
Record the cluster, OpenShift Virtualization, storage driver, backup product,
and relevant Operator versions alongside them.

Agree with the application owner on the required response time, throughput,
batch deadline, permitted maintenance interruption, and recovery objectives.
The recovery time objective (RTO) describes how quickly the service must
return. The recovery point objective (RPO) describes the acceptable data-loss
window. Use service requirements to set those values.

Record the conditions under which the application must meet them: expected
concurrent load, a backup window, planned maintenance, and the failures the
architecture is designed to tolerate. Test disruptive conditions on an
isolated, representative environment with an agreed recovery procedure.

## Use evidence for the status

The checklist starts every check at **Not tested**. Use these statuses
consistently:

- **Not tested:** the test or review is incomplete, or its evidence is missing.
- **Pass:** the agreed criterion was met and the evidence is linked.
- **Fail:** the criterion was missed. Record the issue and the next action.
- **N/A:** the check does not apply to this scope. Record the reason and
  the reviewer who accepted it.
- **Exception:** the accountable owner approved a specific deviation.
  Record the impact, mitigation, approver, and expiry or review date.

Keep exceptions visible. A missed recovery objective remains a missed
objective even when someone accepts the risk temporarily.

Avoid calculating an overall readiness percentage. Twenty-three passes
cannot compensate for an application whose data you cannot recover. Before
testing, identify the requirements that must be met for this wave to proceed.
An untested mandatory check or an unmet requirement without an approved
exception keeps the decision on hold.

## The eight areas to review

| Area | What the evidence must establish |
| ---- | ------------------------------- |
| Supported configuration | The selected versions, guests, drivers, and required features fit a supported design. |
| Application performance | The real application meets its agreed targets at representative load. |
| Capacity and maintenance | The planned maintenance and failure conditions fit the available capacity and interruption budget. |
| Recovery and rollback | The application and its data can return within the agreed objectives. |
| Networking | Required connections work, prohibited connections fail, and addressing behaves as designed. |
| Access and security | Each role can perform its job and is prevented from performing unauthorized actions. |
| Monitoring and response | A service failure reaches an owner who can investigate and act. |
| Operational ownership | The team can maintain the platform and approve the next change using repeatable procedures. |

### Supported configuration

Retain a dated configuration inventory and the support references used to
review it. Include guest operating systems, CPU and device requirements,
storage drivers, backup integrations, and the features each workload needs.
Resolve any dependence on a preview feature or unsupported combination
before approving the design.

Use the
[OpenShift Virtualization documentation](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/virtualization/about)
and its linked compatibility guidance for the target release. A successful
lab boot is useful test evidence; support eligibility still needs its own
review. Check the planned update path as well, including the Operators and
drivers that must remain compatible through the next maintenance cycle.

**Evidence to retain:** the version inventory, support references, required
feature decisions, and the person who reviewed them.

### Application performance

Use a representative dataset and workload, then add the concurrency the
first wave will bring. Measure application correctness, response times,
batch duration, and errors. Keep the source measurement and the destination
configuration so differences can be explained.

Repeat the application test during relevant background work, such as a
backup or image import. Agree separately on any maintenance-period target.
The
[benchmark guide](/posts/benchmark-openshift-vms-before-migration/)
explains how storage measurements support that decision. The application
owner should accept the service result.

**Evidence to retain:** test definitions, per-run results, telemetry from
the same time window, and application-owner acceptance.

### Capacity and maintenance

Rehearse the actual maintenance plan with representative guests running.
Record whether the affected VMs can move, how long the drain takes, what
happens to application response times, and where the guests land afterward.
Include placement rules, quotas, storage access, and special devices in the
review.

Red Hat's
[live migration requirements](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/virtualization/live-migration)
include shared storage, sufficient resources, and compatible CPUs. Having
enough aggregate free memory does not prove that an eligible destination
exists for every VM. Test the intended placement and concurrent drain plan.

For guests that cannot live migrate, document and rehearse the shutdown and
restart procedure against the permitted interruption. Also validate the
failure scenario the design promises to tolerate. A maintenance test and
an unexpected host loss exercise different paths.

**Evidence to retain:** placement and capacity records, drain or restart
timings, application results, and the accepted maintenance procedure. The
[upgrade and VM evacuation guide](/posts/upgrading-openshift-while-vms-stay-running/)
provides the background for that rehearsal.

### Recovery and rollback

Restore a representative VM into an isolated recovery environment. Start the
application, verify its data, check its dependencies, and time the complete
return to service. Include access to backup credentials and encryption keys
in the exercise. If storage or site loss is in scope, establish that the
recovery copy and those dependencies survive that failure.

Review application consistency with the database or application owner.
The
[backup and restore documentation](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/virtualization/backup-and-restore)
distinguishes snapshot conditions such as a missing guest agent; the
restored application still needs its own validation. Record the newest
verified business data in the recovered service and compare it with the
agreed RPO.

For a VMware migration, rehearse the return path after the destination has
accepted a new transaction. Preserve that transaction through the proposed
recovery procedure. The
[rollback guide](/posts/vmware-to-openshift-migration-rollback/)
covers why the state of the old source VM matters less than where the new
writes went. Define who may authorize source retirement and what evidence
they require.

**Evidence to retain:** restore and rollback logs, measured recovery times,
data-validation results, and the source-retirement decision. Keep the
platform recovery procedure in scope alongside VM and application recovery.

### Networking

Test from the clients and dependent services that will actually use the
application. Include DNS, address allocation, routing, firewall rules, load
balancers, and time synchronization where they are dependencies. Repeat
the relevant checks after a guest restart, migration, or restore.

Test an explicitly prohibited connection too. Use the intended tenant
networks and policies, then retain both the allowed and denied results.
The
[VM networking guide](/posts/openshift-virtualization-networking/)
and
[network policy guide](/posts/openshift-network-policies/)
cover the design choices behind those tests.

**Evidence to retain:** an application flow map, addressing records, and
connectivity and isolation results from the relevant endpoints.

### Access and security

Use representative accounts for platform administrators, VM operators,
application owners, and backup operators. Test console access, power
operations, migration, disk attachment, snapshot or restore actions, and
access across namespaces as applicable to each role.

Retain negative tests. If a role should be able to open a console but not
delete the VM, demonstrate both outcomes. Review the guest patching owner,
secrets handling, emergency access, and the ability to retrieve audit
evidence for an administrative action.

The
[hardening priorities](/posts/openshift-virtualization-hardening-priorities/)
are a starting point for the platform baseline. Agree separately on the
security controls required inside the guest operating system.

**Evidence to retain:** a role-to-action matrix, allowed and denied test
results, audit records, and ownership of guest and platform patching.

### Monitoring and response

Exercise a controlled failure and follow the alert through to the person
who responds. Confirm the notification identifies the affected service,
links to a usable procedure, and gives the responder access to the required
logs and metrics.

Include an application-level check. A running VM can contain a failed
service. Combine the
[virtualization monitoring guidance](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/virtualization/monitoring)
with the application's health checks and the
[monitoring questions to carry forward from vRealize Operations](/posts/what-replaces-vrealize-operations/).
Record who handles the incident when it crosses platform, storage, network,
and application boundaries.

**Evidence to retain:** the triggered condition, notification, acknowledgment,
investigation steps, and the time the application was restored.

### Operational ownership

Have someone other than the author follow the maintenance or recovery
runbook. Missing access, an undocumented credential, or a step that depends
on one person's memory belongs in the issue list.

Name the owners for guest images, patching, certificates, backups, capacity,
configuration changes, and vendor escalation. Record how approved settings
are maintained and how an emergency change returns to the managed
configuration. Keep a baseline that can be tested again after significant
changes.

**Evidence to retain:** the exercised runbooks, ownership and escalation
list, change procedure, and the date or trigger for the next readiness review.

## Make the go-live decision explicit

Bring the platform, application, storage, network, security, and operations
owners to the same review. Walk through failures, missing evidence, and
exceptions before reviewing the passed checks.

For example, suppose a restore exercise takes 95 minutes against an agreed
60-minute RTO. Those are illustrative numbers. The recovery requirement
has failed. The choices are to improve the recovery path and retest, obtain
an explicitly approved change to the requirement, approve a time-bounded
exception where policy permits, or hold the wave. Keep the measured result
in the record whichever decision is made.

Record the outcome as **Hold**, **Approved with exceptions**, or **Approved**.
Name the decision owner, the application scope, and the evidence reviewed.
For approval with exceptions, retain the mitigation, approver, and expiry or
review date for every accepted deviation. A support restriction still needs
a supported design or an explicit arrangement with the relevant vendor;
an internal sign-off cannot change a product's support policy.

Reopen affected checks after a material change: a new storage driver, network
design, VM image, backup configuration, cluster release, or workload class.
Keep the earlier evidence so the next review can explain what changed.

## The solutions architect takeaway

1. **Scope the approval.** Name the workload, configuration, load, and failure
   conditions that were tested.
2. **Retain the evidence.** Each result needs an owner and a retrievable test
   record.
3. **Exercise maintenance and recovery.** Include application behavior and
   the data written after cutover.
4. **Keep exceptions visible.** Record the risk, mitigation, approver, and
   review date. Leave unresolved requirements on hold.
5. **Repeat the relevant checks after change.** Production readiness is tied
   to the configuration and workload that were accepted.

> Want help reviewing a first production wave? Bring the completed scorecard,
> application targets, and unresolved checks to your Red Hat account team
> before booking the cutover window.
{: .prompt-tip }

## Related posts

- [Benchmark OpenShift VMs Before the First Migration Wave](/posts/benchmark-openshift-vms-before-migration/)
- [Upgrading OpenShift While VMs Stay Running](/posts/upgrading-openshift-while-vms-stay-running/)
- [OADP for OpenShift VMs: Backup Is Not DR](/posts/oadp-vms-backup-is-not-dr/)
- [Roll Back After Migrating to OpenShift Virtualization](/posts/vmware-to-openshift-migration-rollback/)

## Further reading

- [About OpenShift Virtualization (OpenShift 5.0)](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/virtualization/about)
- [Live migration (OpenShift 5.0)](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/virtualization/live-migration)
- [Backup and restore (OpenShift 5.0)](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/virtualization/backup-and-restore)
- [Monitoring (OpenShift 5.0)](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/virtualization/monitoring)

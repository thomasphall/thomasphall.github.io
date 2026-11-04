---
title: "OpenShift Migration Advisor: Rerun the Assessment"
description: >-
  Use OpenShift migration advisor as a recurring plan. Rerun reports,
  compare remaining blockers, scope by application, and export before MTV
  copies a disk.
date: 2026-11-04 04:15:00 -0600
categories: [OpenShift, Virtualization]
tags: [openshift, openshift-virtualization, vmware, migration, gitops]
permalink: /posts/openshift-migration-advisor-rerun-assessment/
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization. Advisor screens and export
> options move. Confirm the current report, comparison, and data-handling
> behavior in the product before you treat a button name as stable.
{: .prompt-info }

A team planning a VMware exit gets its first assessment, files the PDF,
and walks into the next design review with those numbers. The estate has already
moved. Someone cleared a snapshot, upgraded a guest, or added a
datastore. The slide still shows the August blocker count.

[Red Hat OpenShift migration advisor](https://www.redhat.com/en/blog/whats-new-red-hat-openshift-migration-advisor-clearer-reports-and-smarter-planning)
provides an inventory assessment you can rerun. On 2 November 2026, Red Hat
described the behavior that belongs in that review: refresh a report
from the discovery appliance you already deployed, then compare it
with the report you have. The comparison is how you show that
remediation shrank the blocker list before anyone writes a
[Migration Toolkit for Virtualization](https://docs.redhat.com/en/documentation/migration_toolkit_for_virtualization/2.12)
(MTV) plan.

This is a solutions architect's guide to that loop on
[Red Hat OpenShift](https://www.redhat.com/en/technologies/cloud-computing/openshift)
Container Platform 4.22 and
[OpenShift Virtualization](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/index).
The advisor reads vSphere. MTV copies disks. For namespaces, quotas,
labels, and affinity, see
[vSphere to OpenShift Virtualization: Translation Guide](/posts/vsphere-to-openshift-translation-guide/).
For guests missing from the certified list, see
[32-bit VMs Stay Out of OpenShift Wave 1](/posts/32-bit-vms-not-wave-1/).
If the cluster is still a diagram, start with
[How to Get Started with an OpenShift PoC](/posts/getting-started-openshift-poc/)
and the
[OpenShift Virtualization (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/configure-the-cluster/virtualization/)
installation guide. The advisor runs in the
[Red Hat Hybrid Cloud Console](https://console.redhat.com/)
with a Red Hat account. A paid OpenShift subscription is not required
to produce the assessment.

## The advisor reads. MTV copies.

Keep the three jobs apart. Mixing them is how a PDF becomes a
migration plan that nobody can execute.

| Tool                | Job                                              | Outside this tool                                         |
| ------------------- | ------------------------------------------------ | --------------------------------------------------------- |
| Migration advisor   | Readiness, scope, and a comparison over time     | Disk copy, namespaces, quotas                             |
| MTV                 | `Provider`, maps, `Plan`, `Migration`            | Which applications are allowed into the wave              |
| Git                 | The landing zone you accepted                    | Discovering vCenter                                       |

Two ways in. Upload an RVTools workbook, or deploy the discovery
appliance—an OVA that earlier write-ups call the OMA Discovery
Agent—into vCenter. A
[Red Hat engineer's description of that agent](https://rheb.hatenablog.com/entry/2026/05/26/102144)
calls it a read-only vCenter API client. It sends anonymized inventory
metadata to `console.redhat.com` over HTTPS: guests, hosts,
datastores, port groups, guest-OS support, disk type, VMware Tools,
snapshots, and Changed Block Tracking. The same description says it
does not collect guest filesystem contents, database contents, or
credentials inside the guest. Bring that list to the security
review, and recheck it when a release adds an export. The
[v0.30.0 release notes](https://kubev2v.github.io/openshift-migration-advisor-docs/releases/release-notes-v0-30-0/)
add an option to include running guest processes in a CSV or Excel
file. That option is guest data. Leave it off until the same review
accepts it.

The advisor can report across more than one inventory. Each vCenter
has its own assessment. The OpenShift objects those assessments
turn into are the landing zone in the translation guide.

## Rerun from the appliance you already have

**Run new report** refreshes data from the discovery appliance you
already deployed. Red Hat's wording is that no new setup is required.
Use it after the inventory changes: a guest-prep weekend, a snapshot
cleanup, a cluster you added, or a datastore you built for the landing
zone.

The first PDF cannot show that the list moved. The comparison can.
Red Hat says it looks across historical assessments for inventory
shifts, readiness improvements, and remaining blockers. Bring these
four questions into the room.

| Question                                      | What you cite                                      |
| --------------------------------------------- | -------------------------------------------------- |
| How many VMs were added or removed?            | The inventory shift between the two reports        |
| Which warnings cleared after guest prep?      | The readiness change on those VMs                  |
| What still blocks this wave?                  | Remaining blockers on the latest report            |
| Which applications do those VMs belong to?    | Application detail on the current report           |

A comparison shows that the list moved. It does not time the weekend.
Estimated migration duration was already part of the readiness report,
and it is still an estimate. Use MTV's measured copy time, on a network
you have tested, to build the schedule. Storage copy offload changes
that weekend only when the array supports the path in
[VMware to OpenShift Virtualization: Copy Offload](/posts/mtv-storage-copy-offload-vmware/).

## Scope the report to the wave

The report can label, group, and exclude inventory so the page matches
the wave under discussion. Application information is available for
the whole environment and for each VM. Operating-system support is
grouped by certification tier. v0.30.0 collects VM tags and custom
attributes from vSphere and from RVTools, and it can filter and group
on them.

Use those controls as the bridge to objects you will create. The
advisor does not create them.

| What you did in the report     | What you record for OpenShift                                         |
| ------------------------------ | --------------------------------------------------------------------- |
| An application group           | A namespace, when that group is a permission boundary                 |
| A vSphere tag you grouped on   | A label, when something will select it                                |
| A custom attribute             | An annotation: ticket, CMDB ID, old folder path                        |
| An excluded VM                 | A row that stays out of the MTV `Plan`                                |
| A certification tier           | A check against the certified guest list for the release you will run |

A label is still not a permission. Nested vSphere folders still do not
become nested namespaces. Those rules are in the translation guide. The
advisor is where you notice the tag. Git is where the label and the
`RoleBinding` live.

Certification tiers sort the inventory. They do not waive the
certified guest list. A tier that puts the guest outside that list is
the same filter as the 32-bit post: MTV will copy the disk, and the
destination is still unsupported. Tiers and the
[certified guest article](https://access.redhat.com/articles/4234591)
move on different clocks. The article for the OpenShift Virtualization
version you will run is the decision you put in the wave notes.

Record the scoped set in Git: the namespaces, the labels, and the
excluded names. The CSV you export is the evidence the review saw. It
is not the manifest MTV will follow.

## Disconnected sites upload the next file

**Run new report** is the appliance path. A site that will not leave a
discovery appliance talking to the console still needs a second
reading. It gets there by uploading a newer file, then comparing the
historical reports. Say which path the program is on before you
promise a weekly delta.

| Path                             | How the next report happens                                                                 |
| -------------------------------- | ------------------------------------------------------------------------------------------- |
| Discovery appliance              | **Run new report** on the appliance you already deployed                                    |
| RVTools workbook                 | Upload the newer workbook. Compare that assessment with the one you kept                    |
| Subset-inventory ZIP             | v0.30.0 accepts a manual ZIP upload for a disconnected environment                          |
| Offline Analyzer                 | v0.30.0 reads RVTools with no vSphere connection. The console comparison still needs the console |

An RVTools upload is rejected when the `vInfo` sheet is incomplete. The
[upstream tutorial](https://kubev2v.github.io/openshift-migration-advisor-docs/docs/tutorial/)
requires at least one VM row and non-empty values for VM ID, VM name,
cluster, and VI SDK UUID. If `vHost`, `vDatastore`, `vNetwork`, `vCPU`,
`vMemory`, `vDisk`, or `vNic` is missing, the advisor still builds an
inventory but leaves the corresponding section blank. A blank datastore
section cannot feed a storage offload estimate. Export every sheet.

The Offline Analyzer is the standalone path in the v0.30.0 appliance
notes: one or more RVTools workbooks, options to replace or delete an
earlier upload, and no live vSphere session. It is the tool for a
site that will not send the workbook to the console. Do not describe
it as **Run new report**, and do not describe it as the historical
comparison in the console. Those are the hosted assessments.

Network I/O Control fields are available through the assessment API in
that same release and are not in the user interface yet. Do not hold the wave
for a chart that is not on the page. Size the migration network from
the design.

## Export the view you scoped

The 2 November updates add exports so the review can sit outside the
console. Export the scoped report. An excluded guest that reappears
in the packet will be scheduled by someone who did not read the
filter.

| Format | What you hand over                                                         |
| ------ | -------------------------------------------------------------------------- |
| CSV    | The columns you selected. The working sheet for the wave                   |
| PDF    | The packet for the review                                                  |
| PNG    | One chart or every chart for your slides                                   |
| HTML   | The report in a browser, without a console login for every reader         |

Partner accounts get a separate sizing and total-cost workflow. Red
Hat marks that workflow as available to partners. A customer login that
cannot see a cost button is not a missed step. Cluster complexity,
storage-offload estimates, and rightsizing recommendations are the
planning controls on the assessment itself.

Rightsizing is a recommendation. The instance type you commit in Git
is the decision. An offload estimate is a hint that a datastore might
qualify. Prove it with one VM and a `StorageMap`, as described in the
offload post.
vSAN and fast network copy still depend on a legal VMware Virtual
Disk Development Kit image. For that procurement step, see
[VDDK Off Broadcom's Public Portal: MTV Migrations](/posts/vddk-portal-mtv-openshift/).
The advisor does not ship the SDK.

## Disconnect on purpose

The same November updates cover credentials and disconnection. The
console is supposed to say what happens to assessment data when you
disconnect and what cleanup keeps or removes. Read that notice
before you delete the appliance to close a finding.

If next month's review will cite the comparison, confirm the history
survives the disconnect you are about to approve. Then shut the
appliance down and remove it from vCenter. Revoke the account it used.
A discovery VM is not a permanent management station.

## The solutions architect takeaway

1. **The first report is a baseline.** The comparison is the evidence you
   take into the room.
2. **Run new report uses the appliance you have.** A disconnected site
   uploads the next workbook or ZIP. The Offline Analyzer stays on
   site and is not that button.
3. **Scope to the wave, then export that view.** Application, tags,
   exclusions. The unfiltered estate is how a holdout gets scheduled.
4. **Tiers sort. The certified guest list decides.** A 32-bit operating
   system stays out of wave 1 even when the disk copy would succeed.
5. **Estimates stay estimates.** Rightsizing becomes an instance type
   in Git. An offload estimate becomes a `StorageMap` only after the
   array path is proven. VDDK is still procurement.
6. **Read the disconnect notice first.** Keep the comparison you still
   need to cite. Then remove the appliance and its vCenter account.
7. **MTV starts after the blocker list has moved.** The copy does not
   invent the namespaces, the labels, or the excluded set.

If a console assessment already exists, the next proof is a second
report. Rerun it from the same appliance, or upload a newer workbook.
Exclude the guests the certified list will not carry. Export the CSV
of what remains. That file is the wave. The MTV `Plan` comes after it.

## Related posts

- [vSphere to OpenShift Virtualization: Translation Guide](/posts/vsphere-to-openshift-translation-guide/)
- [32-bit VMs Stay Out of OpenShift Wave 1](/posts/32-bit-vms-not-wave-1/)
- [VDDK Off Broadcom's Public Portal: MTV Migrations](/posts/vddk-portal-mtv-openshift/)
- [VMware to OpenShift Virtualization: Copy Offload](/posts/mtv-storage-copy-offload-vmware/)

> Want help turning a second migration advisor report into a wave list?
> Reach out to your Red Hat account team—or rerun one assessment, exclude
> the unsupported guests, and export the CSV before you create an MTV
> `Plan`.
{: .prompt-tip }

## Further reading

- [What's new in Red Hat OpenShift migration advisor (2 November 2026)](https://www.redhat.com/en/blog/whats-new-red-hat-openshift-migration-advisor-clearer-reports-and-smarter-planning)
- [Generate a migration-readiness report with OpenShift migration advisor](https://www.redhat.com/en/blog/assess-your-vms-migration-migration-advisor-red-hat-openshift)
- [OpenShift migration advisor datasheet](https://www.redhat.com/en/resources/vm-migration-with-openshift-migration-advisor-datasheet)
- [OMA Discovery Agent data collection (Red Hat engineer blog)](https://rheb.hatenablog.com/entry/2026/05/26/102144)
- [OpenShift Migration Advisor docs](https://kubev2v.github.io/openshift-migration-advisor-docs/docs/)
- [Assessment tutorial, including RVTools sheet requirements](https://kubev2v.github.io/openshift-migration-advisor-docs/docs/tutorial/)
- [Release notes v0.30.0](https://kubev2v.github.io/openshift-migration-advisor-docs/releases/release-notes-v0-30-0/)
- [Certified Guest Operating Systems in OpenShift Virtualization](https://access.redhat.com/articles/4234591)
- [Planning a migration from VMware vSphere (MTV 2.12)](https://docs.redhat.com/en/documentation/migration_toolkit_for_virtualization/2.12/html/planning_your_migration_to_red_hat_openshift_virtualization/assembly_planning-migration-vmware_mtv)
- [Migration Toolkit for Virtualization (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/configure-the-cluster/mtv/)

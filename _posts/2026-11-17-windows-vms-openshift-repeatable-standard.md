---
title: "Windows VMs on OpenShift: Build a Repeatable Standard"
description: >-
  Build a Windows VM standard on OpenShift Virtualization with
  versioned images, VirtIO drivers, guest identity, patching, and tested application recovery.
date: 2026-11-17 18:00:00 -0600
categories: [OpenShift, Virtualization]
tags: [openshift, openshift-virtualization, windows, migration]
permalink: /posts/windows-vms-openshift-repeatable-standard/
social_title: |-
  Windows VMs.
  A repeatable standard.
social_label: OpenShift Virtualization
social_subtitle: Images · Identity · Patching · Recovery
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization. Platform references below
> use OpenShift 5.0 documentation; confirm the requirements for your guest
> operating system, applications, and target platform release.
{: .prompt-info }

The first Windows virtual machine boots on OpenShift. Remote Desktop works,
the application starts, and the team saves the disk as its new standard image.

The useful test comes next: create two fresh VMs from that image. Give each
its own identity, enroll both in management, patch and restart them, then
restore one into an isolated recovery environment. That exercise exposes
the settings and credentials that a successful first boot can hide.

For Red Hat OpenShift Virtualization, I would define the Windows standard
as **a versioned image, a VM configuration, a first-boot procedure, and an
operating policy with acceptance evidence**. Together, those let another
administrator build and support the next guest without reconstructing the
original author's console session.

This guide focuses on general-purpose Windows Server member servers.
Domain controllers, certification authorities, clustered applications, and
vendor appliances need role-specific build and recovery procedures. For
using a Windows workstation to administer the platform, see
[Interacting with OpenShift from a Windows Client](/posts/openshift-from-windows-client/).

## Define what the standard contains

Start with the exact Windows edition, version, architecture, and installation
option. Check Red Hat's
[certified guest operating-system matrix](https://access.redhat.com/articles/4234591),
Microsoft's lifecycle for that release, and the application vendor's support
requirements. Record the licensing and activation owner alongside those
decisions.

A standard should identify these five parts:

- **Base image:** Windows source media, build and patch level, driver and
  agent versions, build recipe, and image identifier.
- **VM configuration:** CPU and memory sizing, firmware, device models,
  disk layout, storage class, networks, and placement requirements.
- **First-boot procedure:** naming, addressing, identity enrollment,
  certificates, local administrator management, and management-agent
  registration.
- **Operating policy:** patching rings, maintenance windows, backup
  selection, monitoring, escalation, and retirement.
- **Acceptance evidence:** results from fresh clones, an update and restart
  cycle, maintenance, application checks, and a restore.

Give the image and configuration their own revision identifiers. A name such
as `windows-server-2025-2026-11-r1` is an example of a release label, not a
claim about a validated image. Retain the underlying artifact reference or
checksum and the configuration revision so the label resolves to an exact
build.

Review firmware, Secure Boot, virtual TPM, and any required Windows security
features together against the guest support matrix. If the design uses
BitLocker or other encryption, include recovery-key handling and recovery
of the required VM state in the acceptance plan.

When using a vTPM, set
`spec.template.spec.domain.devices.tpm.persistent` to `true`. Red Hat warns
that BitLocker setup can succeed with a nonpersistent vTPM even though that
vTPM is discarded when the VM shuts down. Include a full VM stop and start
in acceptance, and verify access to encrypted volumes afterward. See the
[vTPM configuration and persistence guidance](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/virtualization/managing-vms).

## Set storage acceptance criteria

Red Hat's
[Windows storage I/O latency guidance](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/virtualization/installing)
classifies latency below **15 ms** as healthy and **15 ms to less than
100 ms** as unhealthy, with a risk of eventual instability. At **100 ms to
less than 1,000 ms**, Windows crashes are highly likely. Red Hat advises
prioritizing the storage root cause when latency exceeds 100 ms multiple
times a day.

Include storage latency in acceptance under representative concurrent load,
backups, and platform maintenance. Retain the measurement interval and
latency spikes alongside application results. Apply the application's own
performance requirements too; a value in the healthy range does not prove
that its response-time target was met.

## Build the image from known inputs

Use a dedicated reference VM and an approved Windows installation source.
Keep production application data and production machine identity out of that
build environment.

Record the choices that are easy to lose in a manual installation: Server
Core or Desktop Experience, language, time zone, disk layout, device models,
required Windows features, and the update source. Complete the intended
patch cycle and required restarts before sealing the image. Retain the
resulting OS build and update inventory.

Keep the base image broadly reusable. Install common prerequisites there;
configure application roles and environment-specific settings through a
separate, versioned procedure. Check each product's image-preparation
instructions before installing an endpoint, backup, or management agent
into the reference VM. Its registration identity may need to be created
after cloning.

In OpenShift, pair the boot image with a reviewed VM definition and sizing
choices. Red Hat's
[VM creation and boot-source documentation](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/virtualization/creating-virtual-machines)
describes the available template, image, and clone workflows. Record which
workflow your team uses and who can promote a new boot source for general
consumption.

## Install drivers and verify the guest agent

Use the Windows VirtIO drivers supplied through official Red Hat sources.
The OpenShift 5.0
[VM management documentation](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/virtualization/managing-vms)
documents downloading the `virtio-win` ISO from **Virtualization → Settings →
Downloads**. That ISO includes drivers and the QEMU guest agent installer.

For a new Windows installation, make the required storage driver available
during setup. After installation, complete the documented guest-tools
installation and restart the guest. Record the package version used and
verify the installed storage and network devices in Device Manager.

Check the guest agent separately: its Windows service must run, and the
platform must report a connected agent. Repeat that check after a restart
and on a fresh clone. A working Remote Desktop session proves network
access; it does not establish guest-agent health.

Retain evidence for the device and agent checks with the image release.
When a later driver package is approved, test it through the same release
process and schedule updates for existing guests.

## Generalize new images, then assign each clone an identity

Microsoft's
[Sysprep guidance](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/sysprep--generalize--a-windows-installation?view=windows-11)
requires generalizing a Windows installation before reusing it to deploy
new machines. Renaming a copied VM is not the complete preparation process.

Follow the
[Windows image generalization and specialization procedure](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/virtualization/creating-virtual-machines)
for your release, including the handling of installation answer files.
Seal and retain the resulting powered-off image. Test first boot on clones
so the published source remains in its intended deployment state.

OpenShift 5.0 does not support cloning a VM with an attached vTPM or creating
a new VM from that VM's snapshot. For this Windows Server image workflow,
keep vTPM and BitLocker out of the reusable reference VM. After cloning,
configure a separate persistent vTPM for each new VM where supported and
required. Enable BitLocker if required by the standard, and retain each
VM's recovery key. See
[Red Hat's vTPM limitations](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/virtualization/managing-vms).

Keep a clear boundary around this step. Microsoft documents Sysprep as an
image-creation tool and lists reconfiguring an already-deployed installation
as unsupported in its
[Sysprep overview](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/sysprep--system-preparation--overview?view=windows-11).
**Do not add Sysprep to the migration runbook for an existing production
server.** Migrating that server preserves its identity through the approved
migration process; building a reusable image creates new servers.

For each new clone, make the first-boot sequence explicit:

1. Assign the computer name and intended network configuration. Verify DNS,
   time synchronization, and access to the required management services.
2. Join the intended domain and organizational unit when required. Confirm
   the expected policy applies and authorized users can sign in.
3. Enroll endpoint protection, monitoring, backup, and configuration-management
   agents according to each product's cloning procedure. Verify a distinct
   record for each guest in the management consoles.
4. Issue machine-specific certificates and establish managed local
   administrator credentials. Test the approved emergency-access procedure.
5. Install or configure the application and run its acceptance checks.

Supply enrollment credentials through the approved secret-delivery process.
Keep reusable passwords, domain-join credentials, and machine private keys
out of the published image and ordinary source control. Review unattended
setup files, build logs, and temporary installation media for retained
secrets before promoting the release.

Test with two clones at the same time. Distinct computer names are only
one result to inspect; verify domain objects, certificates, monitoring
records, and endpoint-management registrations too.

## Give Windows maintenance its own schedule

Updating an OpenShift worker and patching Windows inside a VM are separate
changes. Name the owner of each, and coordinate their maintenance windows.

Maintain two related update processes:

- **Image maintenance:** rebuild or service the reference image, create
  fresh candidates, run acceptance, and promote a new version for future VMs.
- **Fleet maintenance:** update the Windows guests already running, including
  approved driver and agent updates, required restarts, and application checks.

Publishing a new image does not patch the guests previously created from it.
Keep an inventory that relates each VM to its originating image, current
OS build, driver and agent versions, and any approved exception.

Use a small initial patch group before expanding the rollout. Test that
updates install, required restarts finish, guest-agent connectivity returns,
management services check in, and the application resumes its work. Include
scheduled tasks and services that run under service accounts.

Rehearse platform maintenance with those guests too. Where live migration
is part of the design, observe the application during evacuation. Where
the guest requires shutdown, validate that interruption against the agreed
window. Use
[Upgrading OpenShift While VMs Stay Running](/posts/upgrading-openshift-while-vms-stay-running/)
and the
[spare-capacity calculator](/posts/openshift-virtualization-spare-capacity/)
to prepare that review.

## Validate backup through a Windows restore

For online Windows snapshots, the QEMU guest agent and Windows Volume
Shadow Copy Service (VSS) are part of the consistency path. Red Hat warns
that they may not be ready immediately after boot; an early backup can
fail its freeze or thaw operation. See the
[backup and restore documentation](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/virtualization/backup-and-restore).

Microsoft's
[VSS overview](https://learn.microsoft.com/en-us/windows-server/storage/file-server/volume-shadow-copy-service)
describes the coordination among backup software, application writers, and
snapshot providers. Confirm how your backup product protects the actual
application, including its relevant writers and data volumes. Record the
snapshot or backup warnings rather than treating a connected guest agent
as complete proof of application consistency.

Restore a representative guest into an isolated recovery network using a
workflow supported for its vTPM configuration, if applicable. Account
for its retained computer name, addresses, and domain identity before
allowing it to contact production services. Include a controlled procedure
for testing identity-dependent application functions.

Then validate the service: boot, unlock encrypted volumes if applicable,
verify data disks and drive letters, start the application, and check a
known transaction or file. Measure the full return to usable service and
the newest verified data against the recovery objectives. Include the
credentials, keys, and dependencies the recovery operator actually needs.

The
[OADP guide](/posts/oadp-vms-backup-is-not-dr/)
explains the broader backup and disaster-recovery distinction. Keep
application-specific backup and recovery procedures in the Windows
standard wherever the application requires them.

## Release the standard only after fresh-clone acceptance

Use disposable candidates for this review, including at least one VM with
a representative application and dataset. A practical acceptance record
should cover these seven checks:

1. **Repeatable deployment.** Have another operator create the VM. Retain
   the image and configuration revisions, deployment record, and any manual
   steps still required.
2. **Healthy devices and guest agent.** Record installed driver versions,
   device checks, the running agent service, and platform connection status
   after reboot.
3. **Individual identity and management.** Retain distinct enrollment
   records, applied policy, authorized sign-in results, and the tested
   emergency-access procedure for each clone.
4. **Application acceptance.** Record correctness, response time or batch
   results, storage latency under the tested conditions, dependency checks,
   and the application owner's acceptance.
5. **Maintenance acceptance.** Retain patch and restart results, agent
   reconnection, and application behavior during the agreed host-maintenance
   procedure. For vTPM guests, also verify state persistence and access to
   encrypted volumes through a full VM stop and start.
6. **Usable recovery.** Record backup indications, restore steps, data
   validation, measured recovery time, and recovery-point evidence.
7. **Operational ownership.** Name the guest, platform, security, backup,
   and application owners, plus the next review date.

Attach these records to the
[production readiness scorecard](/posts/openshift-virtualization-production-readiness/).
Record failed checks and exceptions with an owner and review date. Keep the
previous approved image available for new deployments until the replacement
has passed acceptance; handling an existing VM's failed update still needs
its own tested recovery procedure.

For Windows VMs arriving from VMware, apply the same operational acceptance
criteria after migration. Verify target drivers, network configuration,
identity, management enrollment, patching, and restore behavior. Record
differences from the new-build standard as remediation work, with an owner,
rather than trying to turn a migrated production machine into a reference
image during cutover.

## The solutions architect takeaway

1. **Version the whole standard.** Keep the image, VM configuration,
   first-boot procedure, and acceptance record together.
2. **Prove the second guest.** Two fresh clones expose identity and
   enrollment problems that a single successful build can miss.
3. **Verify drivers and the agent after restart.** Include the result in
   both image acceptance and ongoing patching.
4. **Maintain images and deployed guests.** Assign owners and a release
   process for both.
5. **Accept recovery at the application.** Retain usable-data evidence
   and measured recovery objectives before production handoff.

## Related posts

- [Is OpenShift Virtualization Ready for Your Production VMs?](/posts/openshift-virtualization-production-readiness/)
- [vSphere to OpenShift Virtualization: Translation Guide](/posts/vsphere-to-openshift-translation-guide/)
- [OADP for OpenShift VMs: Backup Is Not DR](/posts/oadp-vms-backup-is-not-dr/)
- [Interacting with OpenShift from a Windows Client](/posts/openshift-from-windows-client/)

## Further reading

- [Certified Guest Operating Systems in OpenShift Virtualization](https://access.redhat.com/articles/4234591)
- [Installation and Windows storage I/O latency requirements (OpenShift 5.0)](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/virtualization/installing)
- [Creating virtual machines and Windows images (OpenShift 5.0)](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/virtualization/creating-virtual-machines)
- [Managing VMs, VirtIO drivers, and guest agents (OpenShift 5.0)](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/virtualization/managing-vms)
- [Backup and restore (OpenShift 5.0)](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/virtualization/backup-and-restore)
- [Sysprep overview (Microsoft)](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/sysprep--system-preparation--overview?view=windows-11)
- [Volume Shadow Copy Service (Microsoft)](https://learn.microsoft.com/en-us/windows-server/storage/file-server/volume-shadow-copy-service)

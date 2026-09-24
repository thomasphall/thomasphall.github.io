---
title: "32-bit VMs Stay Out of OpenShift Wave 1"
description: >-
  32-bit guest operating systems are a VMware-exit filter, not an MTV
  problem. Disk copy is not guest support. Leave them out of the first
  OpenShift wave.
date: 2026-09-15 11:00:00 -0500
categories: [OpenShift, Virtualization]
tags: [openshift, openshift-virtualization, migration, vmware, windows]
permalink: /posts/32-bit-vms-not-wave-1/
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization. Guest support is version-
> specific. Confirm the certified guest list for the OpenShift Virtualization
> release you will actually run.
{: .prompt-info }

Wave 1 of a VMware exit is a proof. It shows that
[Red Hat OpenShift](https://www.redhat.com/en/technologies/cloud-computing/openshift)
storage, networks, and
[Migration Toolkit for Virtualization](https://docs.redhat.com/en/documentation/migration_toolkit_for_virtualization/2.12)
(MTV) can land a supported guest on
[OpenShift Virtualization](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/index)
and that the application comes back. It is not a museum for every virtual
machine (VM) vSphere ever registered.

A 32-bit *operating system* is the exhibit that should never make that
weekend. MTV will still copy the disk. Copy succeeding is not guest
support, and it is not a reason to put the VM in the same plan as the
64-bit majority. This post is that filter for OpenShift 4.22 and MTV
2.12. It is a solutions-architect map, not a QEMU cookbook. For operator
install, a vSphere provider, and the VMware Virtual Disk Development Kit
(VDDK) in a PoC, use the
[Migration Toolkit for Virtualization (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/configure-the-cluster/mtv/)
guide. Treat Broadcom entitlements as a procurement item—see
[VDDK Off Broadcom's Public Portal: MTV Migrations](/posts/vddk-portal-mtv-openshift/).

## Two meanings of “32-bit” that get mixed in the room

Inventory reports collapse a 32-bit *application* and a 32-bit *guest
OS* into the same red cell. They are not the same migration. Most of
the red cells are 32-bit binaries on current 64-bit Windows or
Red Hat Enterprise Linux (RHEL). A smaller set is a 32-bit guest OS.

| What you actually have                          | Architecture                      | Wave 1?                              |
| ----------------------------------------------- | --------------------------------- | ------------------------------------ |
| 32-bit application on 64-bit Windows            | Windows-on-Windows 64-bit (WOW64) | Yes, if the guest is otherwise ready |
| 32-bit userspace packages on 64-bit RHEL        | Multilib on x86_64                | Yes, if the guest is otherwise ready |
| 32-bit Windows or Linux *operating system*      | i386 / i686 guest                 | No                                   |
| Firmware appliance whose vendor ships i686 only | Vendor image, often unpatchable   | No                                   |

Windows 10 and 11 guests that still run a 32-bit line-of-business binary
are normal 64-bit VMs. RHEL guests that `dnf install` an `i686` library
are the same story. Those VMs belong in the ordinary MTV assessment:
[AI Agents for MTV](/posts/ai-agents-mtv-vsphere/)
is the factory loop; this post is only the architecture gate before that
loop starts.

A Windows 7 32-bit box, a Server 2008 32-bit holdout, an old i686
CentOS appliance, or a vendor image whose installer never grew a 64-bit
build is a different object. Current certified guests for OpenShift
Virtualization are 64-bit operating systems—RHEL 7, 8, 9, and 10, Windows
Server 2016 through 2025, Windows 10, and Windows 11. Confirm the
[Certified Guest Operating Systems in OpenShift Virtualization](https://access.redhat.com/articles/4234591)
article for the hypervisor and version on the design. Windows 11 has no
32-bit SKU. Windows 10 is past end of support as of October 2025 unless
the estate bought Extended Security Updates. None of that is an MTV
setting.

## Find them before you name wave 1

vSphere already knows. The guest ID is the VM's declared OS, not what
VMware Tools last reported.

| Guest ID (examples)      | Meaning             | Filter              |
| ------------------------ | ------------------- | ------------------- |
| `windows7Guest`          | Windows 7 32-bit    | Out of wave 1       |
| `windows7_64Guest`       | Windows 7 64-bit    | Not this filter     |
| `windows9Guest`          | Windows 10 32-bit   | Out of wave 1       |
| `windows9_64Guest`       | Windows 10 64-bit   | Ordinary assessment |
| `ubuntuGuest`            | Ubuntu 32-bit       | Out of wave 1       |
| `rhel6Guest`             | RHEL 6 32-bit       | Out of wave 1       |
| `centosGuest`            | CentOS 32-bit       | Out of wave 1       |
| `otherLinuxGuest`        | Other Linux 32-bit  | Out of wave 1       |
| `ubuntu64Guest`          | Ubuntu 64-bit       | Ordinary assessment |
| `rhel9_64Guest`          | RHEL 9 64-bit       | Ordinary assessment |
| `windows2019srv_64Guest` | Windows Server 2019 | Ordinary assessment |

RVTools, a vCenter export, and the MTV provider inventory all surface
this. Prefer the configured guest ID over a free-text OS name. Tools
can be missing, stale, or wrong; the ID is what the VM was created as.
A `_64Guest` or `64Guest` suffix is the 64-bit signal. If the ID says
64-bit and the bootloader is i686, believe the bootloader and still
keep it out of wave 1. Windows 7 64-bit is still an aging-OS problem
in 2026. That is not this filter. Do not mix the two on the same slide.

Do not spend the first maintenance window discovering this from a hung
`virt-launcher`. Pull the list in discovery, same as shared disks and
vSAN datastores.

## MTV copies disks. Support is a different slide.

[MTV](https://docs.redhat.com/en/documentation/migration_toolkit_for_virtualization/2.12)
orchestrates inventory, mapping, conversion, and cutover. Storage copy
offload changes *where* the bytes move when the SAN allows it—see
[VMware to OpenShift Virtualization: Copy Offload](/posts/mtv-storage-copy-offload-vmware/).
Neither path inspects whether the guest is a certified OS for OpenShift
Virtualization.

A plan can reach `CopyDisks` complete, land persistent volumes, and
still leave you with a VM that does not boot, has no virtio drivers, or
is unsupported the moment it runs. That is the same honesty as
[OADP backup is not DR](/posts/oadp-vms-backup-is-not-dr/):
the product did the job written on its object. The architect still
decides what is allowed to use that job as a production path.

Default OpenShift Virtualization guests are modern 64-bit machines:
q35, virtio, and firmware that a 32-bit OS from the last decade was
never built for. A lab that changes machine type and BIOS to coerce a
boot does not mint a supported destination. It mints a snowflake you
will own for the rest of the cluster's life. This post will not walk
that coercion. Wave 1 is for proving the factory, not for proving QEMU
compatibility.

## Security is the other reason it stays off the platform

An unpatched 32-bit OS on a current OpenShift node is not “lift and
shift.” It is a guest with no vendor patch stream sitting next to
workloads that do.
[Red Hat Advanced Cluster Security for Kubernetes (RHACS)](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_security_for_kubernetes/)
sees the virt-launcher pod, the image, and the Kubernetes surface around
the VM. It does not become Windows 7 patching. That split is already
in
[RHACS for OpenShift Virtualization](/posts/acs-openshift-virtualization/)
and
[guest OS hardening as a separate program](/posts/openshift-security-tools-stack/).
A guest that cannot take that program does not belong on the same
cluster you just hardened.

If the business still needs the application, the answer is a shrinking
holdout on the source hypervisor with a calendar date—not a special
`VirtualMachine` spec. Write the date. Count the VMs. Do not let the
holdout silently become the new estate.

## Decision tree

```text
vSphere / MTV inventory
        │
        v
Is the guest OS 32-bit?
   no ──► 32-bit application on a 64-bit OS?
   │         yes ──► ordinary wave (this is not a 32-bit VM)
   │         no  ──► ordinary 64-bit assessment
   yes
   │
   v
Can the workload run on a current 64-bit OS?
   yes ──► rebuild or reinstall on 64-bit; migrate that guest later
   no ──► vendor 64-bit replacement exists?
            yes ──► replace, then migrate
            no  ──► retire, or holdout island with an exit date
                     (not OpenShift Virtualization wave 1)
```

Four outcomes, none of which are “add it to Saturday's plan”:

1. **Rebuild on 64-bit.** New Windows Server or RHEL guest, same
   application if the vendor still ships it. That new guest is a later
   wave, after wave 1 has proven MTV.
2. **Replace.** Vendor SKU, SaaS, or a container that is actually
   supportable. The old VM is retired on vSphere.
3. **Retire.** Powered off, no owner, license already dead. Do not
   migrate it to keep the count honest.
4. **Holdout island.** Remaining vSphere or another hypervisor for a
   named, shrinking set. Security exception, backup exception, and an
   exit date live on the same slide. OpenShift Virtualization is not
   that island.

Application cutover, QEMU guest agent, and network maps stay with MTV
hooks and
[Ansible Automation Platform](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/)
the way the
[MTV agent post](/posts/ai-agents-mtv-vsphere/)
already described. Those hooks assume a guest that can run current
tools. A 32-bit OS that cannot install them is another reason it is
not wave 1.

## What wave 1 is for

Wave 1 should be boring 64-bit guests: current RHEL or Windows Server,
virtio-capable, independent disks, networks you have already mapped,
storage class you have already proven. The point of the weekend is
cutover rehearsal for the factory—not a representative sample of every
bad decade in the CMDB.

If the program cannot name a short list of 64-bit VMs that are allowed
to move, you do not have a wave 1 problem. You have an
application-modernization problem that MTV will not dissolve. Keep the
landing zone work on the same track as
[How to Get Started with an OpenShift PoC](/posts/getting-started-openshift-poc/)
and the
[OpenShift Virtualization (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/configure-the-cluster/virtualization/)
install. Prove the platform with guests the platform claims.

## The solutions architect takeaway

1. **Split 32-bit app from 32-bit OS** — WOW64 and RHEL multilib are
   64-bit guests. i386/i686 operating systems are the filter.
2. **Use the vSphere guest ID in discovery** — pull it before the first
   `Plan`. Do not learn architecture from a failed boot.
3. **MTV copy is not certification** — offload and VDDK move disks.
   The certified guest list decides whether the destination is allowed.
4. **Do not coerce a lab boot into production** — q35, virtio, and
   current firmware are the platform default. A snowflake machine type
   is not a landing-zone pattern.
5. **Unpatchable guests stay off the cluster** — RHACS and platform
   hardening do not replace a dead vendor patch stream.
6. **Wave 1 proves the factory** — 64-bit, ready, mapped. Rebuild,
   replace, retire, or holdout are the other four doors.

If a non-prod MTV provider already sees vSphere, the next proof is a
spreadsheet column, not a QEMU flag: guest ID, 32-bit OS yes/no, and
one of rebuild / replace / retire / holdout. Then schedule wave 1
without those rows.

## Related posts

- [VMware to OpenShift Virtualization: Copy Offload](/posts/mtv-storage-copy-offload-vmware/)
- [AI Agents for MTV: vSphere to OpenShift Virtualization](/posts/ai-agents-mtv-vsphere/)
- [VDDK Off Broadcom's Public Portal: MTV Migrations](/posts/vddk-portal-mtv-openshift/)
- [RHACS for OpenShift Virtualization Workloads](/posts/acs-openshift-virtualization/)

> Want help filtering a VMware inventory before the first MTV wave?
> Reach out to your Red Hat account team—or pull guest IDs on a non-prod
> provider and split 32-bit OS rows out of wave 1 before you copy a disk.
{: .prompt-tip }

## Further reading

- [Certified Guest Operating Systems in OpenShift Virtualization (Red Hat Customer Portal)](https://access.redhat.com/articles/4234591)
- [OpenShift Virtualization 4.22](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/index)
- [Planning a migration from VMware vSphere (MTV 2.12)](https://docs.redhat.com/en/documentation/migration_toolkit_for_virtualization/2.12/html/planning_your_migration_to_red_hat_openshift_virtualization/assembly_planning-migration-vmware_mtv)
- [Migrating from VMware vSphere (MTV 2.12)](https://docs.redhat.com/en/documentation/migration_toolkit_for_virtualization/2.12/html/migrating_your_virtual_machines_to_red_hat_openshift_virtualization/assembly_migrating-from-vmware_mtv)
- [Migration Toolkit for Virtualization (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/configure-the-cluster/mtv/)
- [OpenShift Virtualization (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/configure-the-cluster/virtualization/)
- [Deploying virtual machines (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/workloads-and-operations/virtual-machine-workloads/)

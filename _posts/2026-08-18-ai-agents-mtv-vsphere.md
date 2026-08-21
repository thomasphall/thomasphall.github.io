---
title: "AI Agents for MTV: vSphere to OpenShift Virtualization"
description: >-
  How AI agents, OpenShift Lightspeed, and Ansible can automate MTV
  migrations from vSphere to OpenShift Virtualization—assessment, waves,
  and troubleshooting.
date: 2026-08-18 09:20:00 -0500
categories: [OpenShift, Virtualization]
tags: [openshift, openshift-virtualization, migration, vmware, ansible, gitops]
og_image: /assets/img/og/ai-agents-mtv-vsphere.png
permalink: /posts/ai-agents-mtv-vsphere/
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization. OpenShift Lightspeed integration
> with MTV and direct Ansible Automation Platform hook triggers are Technology
> Preview on MTV 2.12—verify current status in product documentation before
> treating either as a production control.
{: .prompt-info }

VMware-exit programs rarely stall on whether
[Migration Toolkit for Virtualization](https://docs.redhat.com/en/documentation/migration_toolkit_for_virtualization/2.12)
(MTV) can copy a disk. They stall on the human glue around that copy: which
fifty VMs belong in this weekend’s wave, whether port group `vlan-214` maps to
the right localnet, who stops the database, and why plan `wave-3b` is sitting
on `CopyDisks` at 47%. MTV already owns inventory, mapping, conversion, and
cutover onto
[OpenShift Virtualization](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/index).
AI agents earn their keep when they shrink the glue—not when they pretend to
replace the orchestrator.

This post is a solution-architect pattern for that split on MTV 2.12 and
OpenShift 4.22. It is not a click-by-click agent lab. For operator install, a
vSphere provider, and VDDK in a PoC, use the
[Migration Toolkit for Virtualization (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/post-installation/mtv/)
guide. Treat the VDDK tarball as a procurement item—see
[VDDK Off Broadcom's Public Portal: MTV Migrations](/posts/vddk-portal-mtv-openshift/).

## MTV still owns the move

Keep the control plane honest. From vSphere to OpenShift Virtualization, MTV
is the migration engine. The objects are Kubernetes custom resources:

| Object | Job |
| ------ | --- |
| `Provider` | Talks to vCenter (and to the in-cluster OpenShift destination) |
| `NetworkMap` | Source port group or network → NAD, pod network, or ignored |
| `StorageMap` | Datastore → StorageClass, including offload when the SAN path exists |
| `Plan` | Which VMs, cold vs warm, hooks, transfer network, landing namespace |
| `Migration` | The running instance of that plan |

Agents that skip those objects and “just `virt-v2v` from a laptop” recreate
the snowflake factory you are trying to leave. The useful design is: **agents
propose, GitOps records, Ansible Automation Platform (AAP) applies at scale,
MTV executes.** Humans still approve provider credentials, the first measured
wave, and production cutover.

Disk copy time is still a storage problem. If large SAN-backed disks dominate
the calendar, design
[storage copy offload](/posts/mtv-storage-copy-offload-vmware/)
into the `StorageMap`—on MTV 2.12, warm offload is generally available, which
is a change from the 2.11 Technology Preview note in that earlier post. Agents
can *select* the offload path. They cannot invent array support.

## Where agents actually help

The expensive work in a migration factory is not clicking **Start** on one VM.
It is repeating a judgment loop across hundreds of guests:

1. **Assess** — Which VMs are ready, which need guest prep, which share disks
   or use features that change the plan shape.
2. **Map** — Networks and storage, consistently, without a spreadsheet drift
   between wave 1 and wave 12.
3. **Group** — Application affinity, maintenance windows, and cold vs warm.
4. **Hook** — Quiesce, notify, install QEMU guest agent, fix DNS, re-enroll
   security tooling.
5. **Watch** — Failed or stalled plans, CBT snapshot issues, importer
   placement, naming collisions.
6. **Prove** — Boot, NIC, storage class, and application checks before the
   source is retired.

That loop is text, inventory, and YAML. It is a good agent surface. The copy
itself stays with MTV, VDDK or offload, and the array.

Three agent *kinds* show up in customer conversations. Do not conflate them:

| Kind | What it is | What it is not |
| ---- | ---------- | -------------- |
| **Assist** | OpenShift Lightspeed plus the MTV Model Context Protocol (MCP) server: natural-language questions against live cluster state | An autopilot that starts migrations |
| **Author** | Coding agents or Ansible Lightspeed that draft `Plan`/`NetworkMap`/`StorageMap` YAML, hooks, and GitOps PRs from inventory | A substitute for reviewing the map |
| **Act** | AAP job templates and (Technology Preview) direct MTV→AAP hooks that run the same playbooks every wave | A chat window with cluster-admin |

Lead with Assist and Author in the first design review. Add Act once the
mappings and hook playbooks are boring.

## A reference shape

Conceptually:

```text
vSphere                    Agents & GitOps                        OpenShift 4.22
┌───────────────────┐      ┌─────────────────────────┐            ┌───────────────────────────┐
│ vCenter inventory  │      │ Assist / Author / Act   │            │ MTV ForkliftController   │
│ VM disks / NICs    │─Provider─►│ Human gate: cutover │──GitOps──►│ Provider / Maps / Plan   │
└───────────────────┘      └─────────────────────────┘            └───────────────────────────┘
```

Secrets stay out of the agent’s prompt. The vSphere `Provider` secret belongs
in a vault path delivered by
[External Secrets Operator](/posts/external-secrets-vs-secrets-store-csi/),
not in a chat transcript. Lightspeed uses the signed-in user’s RBAC; it should
not become a second, wider identity.

Network mapping is still the other critical path. An agent that maps every
source to the pod network because “it compiled” will surprise application
owners. Treat
[OpenShift Virtualization networking](/posts/openshift-virtualization-networking/)
as a reviewed input to the `NetworkMap`, not as something the model infers
from vCenter names.

## Assist: Lightspeed on the MTV MCP

On MTV 2.12, the productized assistant is
[Red Hat OpenShift Lightspeed](https://docs.redhat.com/en/documentation/red_hat_openshift_lightspeed/)
talking to MTV over MCP. Enable it by setting `feature_mcp_server: 'true'` on
the `ForkliftController` (string `'true'`, not a boolean—the API is picky).
The operator deploys the MTV MCP server and registers it with Lightspeed.

This integration is **Technology Preview**. Say that in the design review.
It is the right place to evaluate “why did `ProdDB-01` fail” and “list my
providers” without grepping `forklift-controller` logs. It is the wrong place
to park a production SLA.

Useful prompts map to the factory, not to trivia:

- Planning: prerequisites for warm migration from VMware, transfer-network
  requirements, what a failed network map is telling you.
- Live: why a warm migration is stalled, what `import retry limit exceeded`
  means, CBT snapshot issues.
- After: why a guest is up but unreachable, what to verify before retiring
  the source.

Lightspeed reads migration CRs and logs **as the current user**. That is a
feature. It is also a compliance topic: if the chat backend is an external
model provider, cluster metadata and logs may leave the cluster. Decide that
explicitly, the same way you decide where must-gather files go.

A related, separate AI surface is Red Hat’s
[Technical Supportability Review](https://www.redhat.com/en/blog/red-hat-technical-supportability-review-ai-proactive-cluster-assessments)
(TSR). TSR scores a must-gather against recommended practices, including
OpenShift Virtualization and MTV checks. Use it for cluster readiness, not as
the wave scheduler.

## Author: agents that write the factory, not the disks

The Author loop is where most teams get leverage first, because MTV is already
declarative. A coding agent with `oc` (or an MTV CLI) and a GitOps repo can:

1. Read provider inventory (VM names, networks, datastores, power state,
   disk size, shared-disk hints).
2. Diff that inventory against known target NADs and StorageClasses.
3. Open a pull request: `NetworkMap`, `StorageMap`, `Plan` fragments, and a
   wave list grouped by application label—not by “the first 20 names in
   vCenter.”
4. Attach a readiness note: blockers, assumed cold vs warm, whether offload
   applies.

On MTV 2.12 you also have a **deep inspection** Technology Preview that looks
inside the guest filesystem (useful for dual-boot and root-mount choices).
Feed that output to the Author agent as evidence. Do not let the agent guess
root disks when the inspector already answered.

[Ansible Lightspeed](https://www.redhat.com/en/technologies/management/ansible/ansible-lightspeed)
sits on the same Author side for hook content: pre-migration quiesce,
post-migration guest-agent and network validation, ITSM comments. The playbook
still runs in AAP or in an MTV hook runner. The model’s job is to draft
repeatable tasks from your standards, not to SSH into production from a
notebook.

Keep the GitOps repo as the system of record. OpenShift GitOps applying MTV
CRs is how you get the same wave on the next cluster. Chat history is not an
audit trail.

Illustrative landing shape—not a recipe to paste unreviewed:

```yaml
apiVersion: forklift.konveyor.io/v1beta1
kind: Plan
metadata:
  name: wave-3b-payments
  namespace: openshift-mtv
spec:
  provider:
    source:
      name: vsphere-prod
      namespace: openshift-mtv
    destination:
      name: host
      namespace: openshift-mtv
  map:
    network:
      name: prod-localnet
      namespace: openshift-mtv
    storage:
      name: prod-san-offload
      namespace: openshift-mtv
  targetNamespace: virt-payments
  warm: false
  vms:
    - name: pay-app-01
    - name: pay-db-01
```

The agent should be scored on whether `prod-localnet` and `prod-san-offload`
already exist and were reviewed—not on whether it can emit YAML that applies.

## Act: AAP at wave scale

Red Hat’s documented scale path is still
[Ansible Automation Platform plus MTV](https://www.redhat.com/en/resources/automate-migration-and-operation-of-vm-brief).
AAP inventories the estate, opens the change record, applies the GitOps-merged
CRs, waits on `Migration` status, and runs the guest/app steps MTV should not
own.

MTV hooks already run Ansible before and after a VM migrates. On MTV 2.12, **direct
hook triggers into AAP** are Technology Preview: the plan can call AAP instead
of only a hook image plus ConfigMap. Evaluate that when you already run AAP as
the enterprise automation control plane. Until it is GA, keep the GA hook
runner or an AAP workflow that watches plan status as the production path.

Hooks are for guest and application behavior: stop a queue, freeze a database,
install `qemu-guest-agent`, register with identity, validate east-west. They
are not for inventing a second copier. If the hook is copying disks, you have
left MTV.

After cutover, the VM is a Kubernetes `VirtualMachine`. Day-2 fleet control
belongs on
[ACM for OpenShift Virtualization](/posts/acm-openshift-virtualization/),
not on the migration chat. Agents that start, stop, or live-migrate VMs after
landing should use the hub’s RBAC model, not leftover `cluster-admin` from the
factory namespace.

## Guardrails to write into the design

**Propose, then apply.** Author agents open PRs. A human or a gated AAP
template merges. MTV never takes a cutover from an unreviewed chat turn.

**No secrets in context.** vCenter passwords, VDDK pull secrets, and storage
offload credentials stay in External Secrets / AAP credential objects.

**Maps are architecture.** Agents may suggest “`VM Network` → `localnet-214`”
from a naming convention you published. They may not invent a StorageClass or
a NAD.

**Technology Preview stays labeled.** Lightspeed+MTV MCP, AAP-direct hooks,
and deep inspection are TP on 2.12. Use them on the non-prod factory first.

**Cold vs warm is a business input.** An agent can sort candidates. App owners
still own the outage.

**Failure is a first-class output.** A stalled plan should open a ticket with
the Lightspeed diagnosis *and* the raw condition, then stop the wave—not retry
until the maintenance window is gone.

**Landing posture is not optional.** Migrated virt-launcher pods still sit in
the
[RHACS](/posts/acs-openshift-virtualization/)
and
[hardening](/posts/openshift-virtualization-hardening-priorities/)
story. Do not let the factory optimize only for “powered on.”

## A practical rollout

1. Stand up MTV 2.12 on the OpenShift 4.22 landing cluster. Prove one vSphere
   VM by hand: provider, maps, cold plan, boot, NIC, StorageClass.
2. Put those CRs in Git. That is the Author contract.
3. Turn on Lightspeed MCP in non-prod. Practice failure questions against a
   plan you break on purpose.
4. Encode hooks in AAP (quiesce / guest agent / validate). Run them on the
   same VM.
5. Let Author agents draft wave-2 YAML from inventory; review as if it were
   a junior SA’s PR.
6. Only then parallelize. Offload, warm, and production cutover gates stay
   human.

If the first agent-generated plan is the first plan you have ever run, you
will debug the model, the map, and MTV at the same time. That is not a
factory. That is a weekend.

## The SA takeaway

Lead with outcomes:

1. **MTV remains the orchestrator** — agents wrap assessment, mapping drafts,
   hooks, and troubleshooting; they do not replace `Plan` and `Migration`.
2. **Split Assist / Author / Act** — Lightspeed+MCP for questions, coding
   agents and Ansible Lightspeed for GitOps YAML and playbooks, AAP for scale.
3. **GitOps is the audit trail** — chat is not.
4. **Call Technology Preview by name** — Lightspeed MTV integration and
   AAP-direct hooks on 2.12 are for evaluation unless docs say otherwise.
5. **Cutover stays a gate** — the cost of a wrong `NetworkMap` is an
   application outage, not a bad paragraph.

If you are already running an MTV PoC from vSphere, the next proof point is
small: one GitOps-managed plan, one hook playbook, and one Lightspeed session
against a failed copy. When those three agree, you have a factory you can
staff with agents. When they do not, more model context will not fix the map.

For destination-platform context see
[What's New in OpenShift Virtualization 4.22](/posts/openshift-virtualization-4-22-features/).
For the copy path when the SAN can take the load, see
[storage copy offload](/posts/mtv-storage-copy-offload-vmware/).

## Related posts

- [VDDK Off Broadcom's Public Portal: MTV Migrations](/posts/vddk-portal-mtv-openshift/)
- [VMware to OpenShift Virtualization: Copy Offload](/posts/mtv-storage-copy-offload-vmware/)
- [ACM as the Fleet Control Plane for OpenShift VMs](/posts/acm-openshift-virtualization/)
- [What's New in OpenShift Virtualization 4.22](/posts/openshift-virtualization-4-22-features/)

> Want help applying this in your environment? Reach out to your Red Hat
> account team—or evaluate Lightspeed plus one GitOps-managed plan on a
> non-prod cluster first.
{: .prompt-tip }

## Further reading

- [MTV 2.12 planning: Lightspeed integration](https://docs.redhat.com/en/documentation/migration_toolkit_for_virtualization/2.12/html/planning_your_migration_to_red_hat_openshift_virtualization/assembly_lightspeed-integration_mtv)
- [MTV 2.12 release notes](https://docs.redhat.com/en/documentation/migration_toolkit_for_virtualization/2.12/html/release_notes/ref_rn-2-12_release-notes)
- [Planning migration from VMware vSphere](https://docs.redhat.com/en/documentation/migration_toolkit_for_virtualization/2.12/html/planning_your_migration_to_red_hat_openshift_virtualization/assembly_planning-migration-vmware_mtv)
- [Automate migration and ops to OpenShift Virtualization](https://www.redhat.com/en/resources/automate-migration-and-operation-of-vm-brief)
- [MTV migration hooks](https://www.redhat.com/en/blog/migration-hooks-with-migration-toolkit-for-virtualization)
- [Migration Toolkit for Virtualization (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/post-installation/mtv/)
- [OpenShift Virtualization (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/post-installation/virtualization/)

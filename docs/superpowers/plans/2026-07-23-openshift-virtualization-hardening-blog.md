# OpenShift Virtualization Hardening Blog Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish one Chirpy-compatible SA digest of OpenShift Virtualization hardening priorities to `thomasphall/thomasphall.github.io` via feature branch and pull request into `main`.

**Architecture:** Single Markdown file under `_posts/` with Chirpy front matter. GitHub Actions workflow `pages-deploy.yml` builds and deploys on push/merge to `main`. Design and plan docs under `docs/superpowers/` remain repo-only (not site content).

**Tech Stack:** Jekyll, jekyll-theme-chirpy (~> 7.4), GitHub Pages Actions, `gh` CLI

## Global Constraints

- Repo: `thomasphall/thomasphall.github.io`
- Working copy: `/private/tmp/thomasphall-blog-gh`
- Branch: `feature/openshift-virt-hardening-blog` (already created from `main`; design spec committed)
- Filename: `_posts/2026-07-23-openshift-virtualization-hardening-priorities.md`
- Length: ~1,100–1,400 words
- Voice: Red Hat SA; attack-surface themes; outcome-focused
- Source: Dec 2025 OpenShift Virtualization hardening guide (CIS-format, not affiliated; CIS benchmark in progress)
- Include personal-site disclaimer prompt used on other posts
- Do not modify `_config.yml`, theme files, or workflows
- Do not claim the guide is an official CIS benchmark
- Minimal audit commands; no YAML dumps or full remediation scripts
- Publish path: commit post → push branch → `gh pr create` → merge when approved → Pages deploy

## File structure

| Path | Responsibility |
| ---- | -------------- |
| `_posts/2026-07-23-openshift-virtualization-hardening-priorities.md` | Published blog post |
| `docs/superpowers/specs/2026-07-23-openshift-virtualization-hardening-blog-design.md` | Approved design (already committed) |
| `docs/superpowers/plans/2026-07-23-openshift-virtualization-hardening-blog.md` | This plan |

---

### Task 1: Create Chirpy blog post

**Files:**
- Create: `_posts/2026-07-23-openshift-virtualization-hardening-priorities.md`
- Verify: front matter keys `title`, `description`, `date`, `categories`, `tags`, `permalink`
- Do not modify: `_config.yml`, `.github/workflows/pages-deploy.yml`

**Interfaces:**
- Consumes: Approved design in `docs/superpowers/specs/2026-07-23-openshift-virtualization-hardening-blog-design.md`
- Produces: Post that will publish at `/posts/openshift-virtualization-hardening-priorities/` after Pages deploy

- [ ] **Step 1: Confirm branch and working tree**

Run:
```bash
cd /private/tmp/thomasphall-blog-gh
git status -sb
git branch --show-current
```
Expected: on `feature/openshift-virt-hardening-blog`; design spec already committed; post file not yet present.

- [ ] **Step 2: Write the post file with this exact content**

Create `_posts/2026-07-23-openshift-virtualization-hardening-priorities.md`:

```markdown
---
title: "Hardening OpenShift Virtualization: Security Priorities That Matter First"
description: >-
  The highest-impact controls from the OpenShift Virtualization hardening
  guide—RBAC, device pass-through, storage isolation, and network
  segmentation—for platform teams.
date: 2026-07-23 10:00:00 -0500
categories: [OpenShift, Virtualization, Security]
tags: [openshift-virtualization, hardening, security, rbac, networking]
permalink: /posts/openshift-virtualization-hardening-priorities/
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization.
{: .prompt-info }

Hardening [Red Hat OpenShift](https://www.redhat.com/en/technologies/cloud-computing/openshift)
is necessary but not sufficient once
[OpenShift Virtualization](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/index)
is in play. Containers already share a kernel story your platform team knows.
Virtual machines add another blast radius: host devices that cross into guests,
disks that clone across namespaces, consoles that open interactive sessions, and
live migrations that move running state between nodes. The December 2025
*Red Hat OpenShift Virtualization hardening guide* turns that surface into a
prescriptive baseline. This post is a solution-architect digest of the controls
that most reduce risk—not a full audit script.

## Start with the platform, then harden virtualization

The guide is explicit about order of operations. Harden OpenShift and
Red Hat Enterprise Linux CoreOS first—typically with the
[Compliance Operator](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/security_and_compliance/compliance-operator)
and supported profiles—before treating OpenShift Virtualization as a separate
extension. Guest operating systems still need their own hardening programs;
CNV posture does not replace RHEL, Windows, or other OS baselines inside the VM.

One documentation nuance for customer conversations: the guide follows Center
for Internet Security (CIS) formatting conventions, but it is not affiliated
with CIS. Red Hat is working to formalize these recommendations as an
OpenShift Virtualization CIS benchmark. Until then, treat the guide as Red Hat
prescriptive hardening—and pair it with the same evidence habits you use for
platform compliance. That complements the broader
[platform and supply-chain security pattern](/posts/openshift-security-platform-supply-chain/)
of observe, prove, and gate.

## Who can touch the platform

Most virtualization incidents in regulated estates start as privilege problems,
not exotic hypervisor bugs.

**Live migration and migration policy.** Namespace administrators can often
trigger live migrations by default. Migration moves running VM state across
hosts and can contend for CPU, memory, and network with unrelated workloads.
Treat create rights on virtual machine instance migrations and
`MigrationPolicy` objects as cluster-admin–adjacent capabilities. Audit with
`oc adm policy who-can create` on those resources, then remove bindings that
do not belong to the platform operations role.

**Exec and VNC.** `oc exec` into virt-related pods is an interactive path into
the virtualization control plane; it is not required for day-to-day VM
lifecycle. VNC console access is granted through roles that can generate
KubeVirt tokens—often for every workload in a namespace. Prefer stronger
guest access paths (SSH with MFA, enterprise remote access, break-glass
runbooks) and keep VNC/token generation tightly bound.

**Templates that multiply risk.** Cluster-scoped instance types and preferences
are reusable starting points for many VMs. An insecure default in a cluster
instance type propagates faster than a one-off YAML mistake. Likewise, the
Containerized Data Importer (CDI) custom resource is cluster-scoped and holds
sensitive import configuration—update rights should stay with approved
platform administrators only.

## What can leave the host into a VM

Device pass-through is a performance feature and an isolation trade-off.

Keep the HyperConverged `permittedHostDevices` allowlist empty unless a
workload truly needs a specific GPU, PCI, or USB device—and only approve
devices you trust. Default OpenShift Virtualization does not configure
pass-through; every entry you add is an intentional expansion of the attack
surface. The same discipline applies per VM: do not attach host devices or
GPUs because a template “might need them later.”

Feature gates deserve the same least-functionality mindset. Persistent SCSI
reservations enable Windows Shared Cluster Filesystem scenarios but pull in
privileged helper components—leave `persistentReservation` disabled unless
that workload exists. `downwardMetrics` exposes additional host/VM performance
data into the guest; useful for some monitoring designs, useful to an attacker
doing reconnaissance—keep it off by default. On OpenShift Virtualization 4.18
and later, non-root virt-launcher behavior is the enforced secure default; on
older releases, confirm the `nonRoot` feature gate is enabled before you argue
about finer RBAC.

Configure these options through the HyperConverged API (and GitOps), not by
JSON-patching underlying KubeVirt or CDI objects through unsupported
annotations. Unsupported patches are how experimental surfaces become
production debt.

## How disks move and share data

Storage isolation fails quietly when convenience wins.

Cross-namespace DataVolume cloning breaks the mental model that a namespace
owns its disks. Any principal that can clone a source volume into another
namespace effectively reads data it does not own. Keep cloner RoleBindings
rare, explicit, and reviewed—default behavior correctly limits this to cluster
administrators.

Shareable disks are another shared-resource trap. They are only appropriate
when the guest filesystem or application is cluster-aware; incorrect use risks
corruption and widens the blast radius of a compromised VM. Disk
`errorPolicy: ignore` makes I/O failures harder to diagnose and can mask data
loss—prefer `stop` (default) or `report` when a clustered filesystem needs
errors surfaced to the guest.

## How networks isolate tenants

Virtualization networking should look like zero-trust segmentation, not a flat
VLAN full of “temporary” exceptions.

Use dedicated VLANs or secondary networks so VM traffic is segmented at layer 2
where your CNI supports it (OVN-Kubernetes localnet, SR-IOV, or bridge CNI with
VLAN configuration). Enable MAC spoof filtering so a guest cannot easily
impersonate another address on that segment—OVN localnet enables this by
default; SR-IOV and bridge paths need explicit checks.

Then layer MultiNetworkPolicy for microsegmentation inside those networks
(OVN-Kubernetes localnet). Once a policy selects a VM and its
NetworkAttachmentDefinition, traffic that is not allowed is denied. That is the
same story you already tell for pod NetworkPolicy—extended to VM secondary
networks.

## Host posture, briefly

Two host-level items are worth the elevator pitch. Nested virtualization
expands the attack surface; leave it disabled unless you have a concrete
requirement such as WSL2 inside Windows guests. And confirm CPU vulnerability
mitigations on worker nodes—Spectre/Meltdown-class issues are not “solved by
the hypervisor” if the host kernel reports `Vulnerable` with no mitigation.

## The SA takeaway

Lead with a sequence customers can remember:

1. **Least privilege** — migrations, exec, VNC, CDI, and cluster instance types.
2. **Least device surface** — empty pass-through allowlists; closed feature gates.
3. **Least data sharing** — no casual cross-namespace clones or shareable disks.
4. **Network segmentation** — VLANs, MAC spoof filtering, MultiNetworkPolicy.
5. **Host hygiene** — nested virt off unless required; CPU mitigations verified.

Manage the baseline through HyperConverged and GitOps so drift shows up as a
pull request, not a Friday surprise. For release-specific operational context,
see also
[what is new in OpenShift Virtualization 4.22](/posts/openshift-virtualization-4-22-features/).

If you are standing up or migrating a virtualization landing zone, start in
non-production: lock RBAC for migration and console access, confirm no host
devices are permitted, and put the first tenant VMs on a dedicated secondary
network with MAC spoof filtering before you chase every Level 2 check in the
guide.

For the full control list, audit commands, and remediations, use the official
Red Hat OpenShift Virtualization hardening guide as the source of truth—and
keep OpenShift platform hardening and guest OS hardening on their own tracks.

> Want help mapping these controls to your landing zone? Reach out to your
> Red Hat account team—or apply the sequence above on a non-prod OpenShift
> Virtualization cluster first.
{: .prompt-tip }
```

- [ ] **Step 3: Verify front matter, disclaimer, and word count**

Run:
```bash
cd /private/tmp/thomasphall-blog-gh
python3 - <<'PY'
from pathlib import Path
p = Path('_posts/2026-07-23-openshift-virtualization-hardening-priorities.md')
text = p.read_text()
assert text.startswith('---\n')
assert 'title: "Hardening OpenShift Virtualization: Security Priorities That Matter First"' in text
assert 'categories: [OpenShift, Virtualization, Security]' in text
assert 'tags: [openshift-virtualization, hardening, security, rbac, networking]' in text
assert 'permalink: /posts/openshift-virtualization-hardening-priorities/' in text
assert 'Personal site note' in text
assert 'not affiliated' in text.lower() or 'not affiliated with CIS' in text
for needle in [
    'Live migration',
    'VNC',
    'permittedHostDevices',
    'persistentReservation',
    'DataVolume',
    'MAC spoof',
    'MultiNetworkPolicy',
    'Nested virtualization',
]:
    assert needle in text, needle
body = text.split('---', 2)[2]
words = len(body.split())
print(f'words={words}')
assert 1050 <= words <= 1450, words
print('OK')
PY
```
Expected: `words=` in ~1,100–1,400 range and `OK`.

- [ ] **Step 4: Commit the post (and this plan if not yet committed)**

Run:
```bash
cd /private/tmp/thomasphall-blog-gh
git add _posts/2026-07-23-openshift-virtualization-hardening-priorities.md \
  docs/superpowers/plans/2026-07-23-openshift-virtualization-hardening-blog.md
git commit -m "$(cat <<'EOF'
Add OpenShift Virtualization hardening priorities blog post.

EOF
)"
git status -sb
```
Expected: commit succeeds; branch ahead of `origin/main` by design + post commits.

---

### Task 2: Push branch and open pull request

**Files:**
- Remote: `origin` → `thomasphall/thomasphall.github.io`
- No additional local content beyond Task 1 commits

**Interfaces:**
- Consumes: Commits on `feature/openshift-virt-hardening-blog`
- Produces: PR URL; after merge, Pages deploy publishes the post

- [ ] **Step 1: Push the feature branch**

Run:
```bash
cd /private/tmp/thomasphall-blog-gh
git push -u origin HEAD
```
Expected: branch published to `origin/feature/openshift-virt-hardening-blog`.

- [ ] **Step 2: Create the pull request**

Run:
```bash
cd /private/tmp/thomasphall-blog-gh
gh pr create --base main --title "Add OpenShift Virtualization hardening priorities blog post" --body "$(cat <<'EOF'
## Summary
- Adds an SA-oriented digest of the Dec 2025 OpenShift Virtualization hardening guide
- Covers RBAC, device pass-through, storage isolation, networking, and brief host posture
- Includes design/plan docs under `docs/superpowers/` (not site content)

## Test plan
- [ ] Preview Markdown/front matter in the PR diff
- [ ] Confirm disclaimer and CIS-affiliation nuance are present
- [ ] After merge, confirm GitHub Actions `Build and Deploy` succeeds
- [ ] Confirm live URL: https://thomasphall.github.io/posts/openshift-virtualization-hardening-priorities/

EOF
)"
```
Expected: `gh` returns a pull request URL.

- [ ] **Step 3: Report URLs to user**

Provide:
- Pull request URL from Step 2
- Repo file (after merge): `https://github.com/thomasphall/thomasphall.github.io/blob/main/_posts/2026-07-23-openshift-virtualization-hardening-priorities.md`
- Live post (after Pages finishes): `https://thomasphall.github.io/posts/openshift-virtualization-hardening-priorities/`

Do **not** merge the PR unless the user explicitly asks.

---

## Spec coverage check

| Spec requirement | Task |
| ---------------- | ---- |
| Chirpy post path/front matter/permalink | Task 1 |
| Attack-surface outline (hook → RBAC → devices → storage → network → host → takeaway) | Task 1 Step 2 |
| Eight priority control themes | Task 1 Steps 2–3 asserts |
| CIS-format / not affiliated disclaimer | Task 1 Step 2 |
| Personal-site disclaimer | Task 1 Step 2 |
| ~1,100–1,400 words | Task 1 Step 3 |
| Cross-links to related posts when present | Task 1 Step 2 |
| Feature branch + PR (not direct push to main) | Task 2 |
| No theme/workflow changes | Global constraints |
| No YAML dumps / full audit scripts | Task 1 Step 2 content |
| Design/plan docs repo-only | Already under `docs/superpowers/` |

# AI Prompt: RHACS with OpenShift Virtualization

Copy everything below the line into your AI assistant.

---

You are writing a blog post for a personal Jekyll Chirpy site owned by a Red Hat Staff Solution Architect specializing in OpenShift and OpenShift Virtualization.

## Role and voice

- Write as a Red Hat Staff Solution Architect speaking to platform, security, and virtualization teams at enterprise customers.
- Voice: customer-facing, practical, confident, no hype, no marketing fluff.
- Style: solution-architect digest — outcome-focused talking points, not a CLI lab or audit script.
- Prefer clear prose over bullet spam. Use short subsections with descriptive headings.
- Emphasize blast-radius reduction and operational clarity over product feature laundry lists.

## Deliverable

Produce **one ready-to-publish Markdown post** only. Do not include design notes, meta-commentary, or “here is the draft” framing.

### Front matter (required)

```yaml
---
title: "<compelling SA-style title>"
description: >-
  <1–2 sentence description focused on ACS coverage of OpenShift Virtualization workloads>
date: 2026-08-04 10:00:00 -0500
categories: [OpenShift, Virtualization, Security]
tags: [acs, openshift-virtualization, rhacs, security]
permalink: /posts/acs-openshift-virtualization/
---
```

### Disclaimer (required, immediately after front matter)

```markdown
> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization.
{: .prompt-info }
```

### Length and format

- ~1,100–1,400 words
- Markdown only
- Minimal CLI (at most one or two illustrative `oc` examples if truly needed)
- No YAML dumps, no full remediation scripts, no secrets or customer-identifying detail
- Link to official Red Hat documentation where claims need grounding (`docs.redhat.com`)
- Use product names accurately:
  - Red Hat OpenShift
  - Red Hat OpenShift Virtualization
  - Red Hat Advanced Cluster Security for Kubernetes (RHACS)
  - Compliance Operator (when mentioned)

## Thesis (must drive the whole post)

**ACS still applies when VMs land on the platform.** OpenShift Virtualization runs VMs as Kubernetes workloads (`virt-launcher` pods wrapping the VM process). RHACS continues to provide multi-cluster visibility, policy, and risk context for that surface. Guest OS hardening inside the VM remains a separate control layer.

## Required content outline

Follow this structure; you may refine heading wording, but do not drop sections:

1. **Hook**  
   Many teams assume “we moved to VMs on OpenShift, so container security tools no longer apply.” Reframe: virtualization on OpenShift inherits the Kubernetes security plane. VMs add blast radius (devices, disks, consoles, migrations), but they still show up as workloads ACS can observe.

2. **What RHACS sees for OpenShift Virtualization**  
   Explain in SA language (not a deep KubeVirt internals dump):
   - Each VM is backed by a `virt-launcher` pod and related platform objects
   - Container disks / images that feed VMs are part of the image/risk story
   - Misconfigurations that expand host↔guest surface (capabilities, host devices, privileged paths, risky mounts) appear in the same risk view teams already use for containers
   - Multi-cluster consistency matters for hybrid estates (on-prem and managed OpenShift)

3. **Policies that matter when CNV is in play**  
   Focus on which *kinds* of ACS policies help in virtualization conversations:
   - Deployment-time policy that flags risky workload configurations before/as they land
   - Runtime/visibility context for unusual behavior on virt-adjacent pods
   - Practical guidance: virt components may legitimately need capabilities or SCC allowances that look “noisy” next to app pods — use intentional allowlists and scoped exceptions, not cluster-wide policy disablement
   - Keep the discussion outcome-focused; do not invent specific built-in policy names unless you are certain they exist in current RHACS docs

4. **VM vulnerability visibility (Technology Preview — be precise)**  
   Cover RHACS 4.10 Technology Preview support for vulnerability management of VMs on OpenShift Virtualization:
   - Unified visibility goal: containers and VMs in one security conversation
   - **Must label as Technology Preview** — do not describe as GA or fully supported production feature
   - Do not invent scan mechanics, coverage claims, or guest-agent requirements beyond what Red Hat publicly documents; if uncertain, state the capability at the “visibility in the RHACS console alongside containers” level and point readers to the Scanning virtual machines / RHACS 4.10 docs

5. **Clear boundary: platform posture vs guest OS**  
   Explicitly separate:
   - RHACS + OpenShift controls → platform, images, workload policy, and the Kubernetes/virt control plane around the VM
   - Guest OS hardening (RHEL, Windows, etc.) → still required inside the VM
   - Cross-link the hardening digest: `/posts/openshift-virtualization-hardening-priorities/`
   - Cross-link the broader ACS/platform pattern: `/posts/openshift-security-platform-supply-chain/`

6. **Complementary controls (brief)**  
   One short section: RHACS pairs with Compliance Operator (prove platform baseline) and OpenShift Virtualization hardening priorities (RBAC, devices, storage, network segmentation). ACS is not a substitute for those controls.

7. **SA takeaway + soft close**  
   Summarize in a few sentences: observe VM workloads in the same risk plane as containers; enforce policy with intentional virt exceptions; treat TP VM vuln management as emerging unified visibility; keep guest hardening separate. Soft CTA for an architecture conversation — no hard sell.

## Accuracy and safety constraints

- Do **not** invent RHACS features, policy names, architecture components, or OpenShift Virtualization behaviors.
- Do **not** claim RHACS replaces guest antivirus, guest patching, or full VM introspection unless that is explicitly documented (it is not the thesis of this post).
- Do **not** claim CIS certification for OpenShift Virtualization hardening.
- Prefer cautious wording (“can surface,” “helps teams,” “Technology Preview”) over absolute guarantees.
- Prefer linking `docs.redhat.com` over third-party blogs for normative claims.
- Views are personal; keep the disclaimer intact.

## Success criteria

A reader who already uses RHACS for containers should finish the post able to explain:
1. why ACS still matters after OpenShift Virtualization is enabled,
2. what workload surface ACS is looking at for VMs,
3. how to talk about policy noise vs intentional virt allowances,
4. that VM vulnerability management in RHACS 4.10 is Technology Preview, and
5. where guest OS hardening still sits.

Write the post now.

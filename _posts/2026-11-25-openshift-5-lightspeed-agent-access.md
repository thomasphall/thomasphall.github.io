---
title: "What I'd Let an AI Agent Touch on OpenShift 5"
description: >-
  Decide what an AI agent should touch on OpenShift 5, with practical limits
  for MCP access, RBAC, human approval, and auditing Lightspeed 2 remediation.
date: 2026-11-25 00:00:00 -0600
categories: [OpenShift, Automation]
tags: [openshift, automation, security, gitops]
permalink: /posts/openshift-5-lightspeed-agent-access/
social_title: |-
  What should an AI agent
  touch on OpenShift 5?
social_label: OpenShift Operations
social_subtitle: Lightspeed 2 · MCP access · Approval and audit
---

> Personal site note. These views are my own and do not necessarily
> represent Red Hat.
{: .prompt-info }

An `ImagePullBackOff` alert fires at 2 a.m. Before changing anything, the
on-call engineer needs to know whether the image tag is wrong, the registry
is unreachable, or the workload has lost access to it. That's where I'd put
an agent to work. Let it gather the events, check what changed, and bring
back a proposed fix with the evidence attached.

Red Hat OpenShift Lightspeed 2 can do that investigation when a configured
alert fires. It can also apply a proposed fix after approval and check whether
it worked. Red Hat ships autonomous agent runs as a **Technology Preview** and
recommends evaluating them outside production. I'd use a test cluster to learn
where the controls hold and apply the same access policy to any supported agent
integration I connect to production.
[Red Hat's Lightspeed 2 overview](https://www.redhat.com/en/blog/whats-new-red-hat-openshift-lightspeed-2) ·
[Autonomous agent walkthrough](https://developers.redhat.com/articles/2026/11/23/configure-red-hat-openshift-lightspeed-autonomous-agents)

## What approving a fix actually means

Lightspeed records an investigation as an `AgenticRun`. The workflow moves
through analysis, execution, verification, and escalation as needed. Without
an `ApprovalPolicy`, every stage waits for manual approval. Red Hat's
walkthrough lets analysis, verification, and escalation run automatically
while keeping execution manual. Approval covers the **entire execution
stage**, so the reviewer needs to see the proposed commands, the target
resources, and the permissions the agent will receive before clicking Execute.
[Autonomous agent walkthrough](https://developers.redhat.com/articles/2026/11/23/configure-red-hat-openshift-lightspeed-autonomous-agents)

In Red Hat's example, the agent finds a typo in a Deployment's image
reference. That's a reasonable fix to rehearse. I'd want the reviewer to
verify the replacement image, check that the plan targets one Deployment in
one namespace, and know how to roll it back. If GitOps owns the Deployment,
I'd have the agent draft the change for review in Git. A live patch can be
reverted by reconciliation while the bad image reference stays in the source
of truth. After the change, I'd check that the new replica is ready and that
the original alert clears.
[Red Hat's image-pull example](https://developers.redhat.com/articles/2026/11/23/configure-red-hat-openshift-lightspeed-autonomous-agents)

## What I'd give an agent in production

OpenShift 5's Model Context Protocol (MCP) support gives agents a standard
way to call tools that fetch cluster data or perform actions. Red Hat
describes the OpenShift MCP server as read-only by default, with Kubernetes
role-based access control (RBAC) governing access. For production, I'd check
the support status of the specific server and toolset, then start with an
explicit allowlist.
[OpenShift 5 developer overview](https://developers.redhat.com/articles/2026/11/09/red-hat-openshift-5-for-developers)

- **Allow routine reads.** In the namespaces the team owns, let the agent
  inspect pod status, Deployment rollout status, events, and approved
  metrics. Add narrowly scoped application logs after checking what the
  logs contain and where the model processes them. Logs can contain
  customer data and credentials even when the tool itself is read-only.
- **Require approval for bounded writes.** When the integration is supported
  for production, start with a reversible change to one stateless workload
  through the team's existing change process. Give the execution identity
  only the verbs and resources it needs, for the lifetime of the task.
  Kubernetes RBAC can scope a `patch` to a named Deployment. Use an
  admission policy or a narrow tool to restrict which fields can change.
- **Keep privileged operations with existing platform workflows.** Leave
  Secrets, pod shell access, RBAC changes, node drains, persistent storage
  deletion, and changes to shared networking or admission policy outside
  the agent's toolset. A single operation in any of those areas can affect
  other workloads or tenants.

Red Hat grants the demo controller `cluster-admin` so it can create roles
for remediation sandboxes. The controller and each short-lived sandbox have
separate permissions. Review both identities. A narrowly scoped task still
leaves a broadly privileged controller if you carry the demo binding over.
[Red Hat's execution permissions example](https://developers.redhat.com/articles/2026/11/23/configure-red-hat-openshift-lightspeed-autonomous-agents)

## What I'd want in the audit trail

After an incident, I want to answer four questions. What did the agent see?
What did a person approve? What did the cluster API actually receive? Did
the service recover?

Lightspeed exposes run details in the OpenShift console and can link to
Tempo traces. The OpenShift MCP server tags Kubernetes API requests with a
user-agent string so they can be identified in audit logs. I'd correlate the
run with the approver's identity, the plan they reviewed, the API audit
events, and the verification result. The MCP tag helps find the calls. The
approval record tells you who authorized them. Test that you can reconstruct
the sequence before enabling writes.
[Lightspeed audit traces](https://www.redhat.com/en/blog/how-red-hat-openshift-5-simplifies-incident-diagnosis-supervised-ai) ·
[OpenShift MCP audit tagging](https://www.redhat.com/en/blog/model-context-protocol-server-red-hat-openshift-now-available-technology-preview)

## The solutions architect takeaway

The first thing I'd measure is how much sooner the on-call engineer gets a
diagnosis they can verify. Give the agent enough access to assemble that
evidence. Add write access one operation at a time, when the team can explain
exactly what it's approving, how it'll know the fix worked, and how it'll
undo the change.

## Related posts

- [OpenShift 5.0: The Platform Features That Matter](/posts/openshift-5-features-that-matter/)
- [Security Tools Across the OpenShift Stack](/posts/openshift-security-tools-stack/)

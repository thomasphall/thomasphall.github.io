---
title: "Park on 4.22 or Hop to 5.0 Before 4.22 Full Support Ends"
description: >-
  Which OpenShift clusters should park on 4.22, which should hop to 5.0,
  what to clean up before the hop, and the life-cycle dates that force the decision.
date: 2026-11-16 09:00:00 -0600
categories: [OpenShift]
tags: [openshift, openshift-virtualization, gitops]
permalink: /posts/openshift-4-22-vs-5-0-upgrade-decision/
social_title: |-
  Park on 4.22
  or hop to 5.0
social_label: OpenShift lifecycle
social_subtitle: 4.22 clock · 5.0 hop · Cleanup
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization. Dates and support statements
> below are from the OpenShift life-cycle page, the OpenShift 5.0 update
> guide, the OpenShift 5.0 release notes, and
> [RHEA-2026:4893](https://access.redhat.com/errata/RHEA-2026:4893), as
> reviewed on November 16, 2026. The life-cycle page says future dates are
> close approximations, are not definitive, and are subject to change.
{: .prompt-info }

A feature list and a support calendar answer different questions.
[OpenShift 5.0: The Platform Features That Matter](/posts/openshift-5-features-that-matter/)
is the feature list: the in-place hop from 4.x, the unsupported mix of
Red Hat Enterprise Linux CoreOS (RHCOS) 9.x and 10.2, and the move from
runC to crun before the host OS changes. This post is the calendar:
which clusters stay on 4.22, which move to 5.0, what has to be true
first, and which dates set the deadlines.

## Why this decision is due now

The [life-cycle page](https://access.redhat.com/product-life-cycles?product=Red+Hat+OpenShift+Container+Platform),
retrieved November 16, 2026, groups Red Hat OpenShift Container Platform
5.0 and 4.22 under full support, and 4.19, 4.20, and 4.21 under
maintenance support. On these rows, full support begins at general
availability.

| Version | General availability | Full support through | Maintenance support through | Extended Update Support add-on |
| ------- | -------------------- | -------------------- | --------------------------- | ------------------------------ |
| 4.19 | Jun 17, 2025 | Jan 21, 2026 | Dec 17, 2026 | N/A |
| 4.20 | Oct 21, 2025 | May 3, 2026 | Apr 21, 2027 | Term 1 through Oct 21, 2027; Term 2 through Oct 21, 2028 |
| 4.21 | Feb 3, 2026 | Sep 9, 2026 | Aug 3, 2027 | N/A |
| 4.22 | Jun 9, 2026 | Dec 31, 2026 | Dec 31, 2027 | Term 1 Jan 1, 2028–Jun 30, 2028; Term 2 Jul 1, 2028–Jun 30, 2029; Term 3 N/A |
| 5.0 | Nov 3, 2026 | Nov 30, 2027 | Nov 30, 2028 | N/A |

4.22 is the 4.x row still in full support. 5.0's add-on columns are
N/A. 4.19 maintenance support ends December 17, 2026, also with no
add-on columns. That is not a parking release. 4.20 and 4.21 are
already in maintenance support.

[RHEA-2026:4893](https://access.redhat.com/errata/RHEA-2026:4893) was
issued November 3, 2026, the same day the life-cycle page lists as 5.0
general availability. It is a Product Enhancement Advisory. The synopsis
is "OpenShift Container Platform 5.0.0 bug fix update." The topic says
release 5.0.0 is now available, with updates to packages and images that
fix several bugs. Images are published for x86_64, s390x, ppc64le, and
aarch64. The advisory points at RHEA-2026:25269 for the RPMs and tells
5.0 users to upgrade when the images are in the appropriate channel.
Check with `oc` or the web console. Copy digests from the advisory when
you mirror.

Clusters still behind 4.22 follow the update graph. The
[channel chapter](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html-single/updating_clusters/index#understanding-update-channels-releases)
says a minor update has to be contiguous, that Red Hat does not test
noncontiguous updates, and that a cluster is offered channels for its
current minor, the next minor, or the next Extended Update Support (EUS)
version. Run `oc adm upgrade recommend` on that cluster to see the
recommended target versions.

## The hop is an in-place update

The [5.0 update chapter](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/updating_clusters/performing-a-cluster-update)
says an update from a 4.x release to 5.0 is in-place, functionally
identical to a minor update such as 4.16 to 4.17. It does not require a
cluster rebuild or a manual data migration. It says updates to 5.0 are
available on `stable-5.0` and `candidate-5.0`, and that a production
cluster must use a `stable-*`, `eus-*`, or `fast-*` channel.

The same book's channel chapter lists what 5.0 offers: `stable-5.0`,
`fast-5.0`, `candidate-5.0`, and `eus-4.y`. There is no `eus-5.0` in
that list. `eus-4.y` is only for EUS versions, to move between EUS
versions. `fast-5.0` receives a release when Red Hat declares it
generally available, and those releases are supported for production.
`stable-5.0` receives them after a delay: generally a week or two for a
z-stream, and generally 45 to 90 days when a minor first rolls out. The
chapter offers no service-level objective for that delay.
`candidate-5.0` is unsupported early access, for clusters you can
destroy and recreate. New clusters default to a stable channel.

None of those pages names a 4.22 z-stream, and none lists what
`stable-5.0` contains on a given day. The sample `oc adm upgrade recommend`
output in the update chapter shows a cluster on `stable-4.21`. Copy the
command. Leave that sample's versions in the documentation.

The host OS is a separate campaign. The
[release notes](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/release_notes/ocp-5-0-release-notes#ocp-release-notes-rhcos_release-notes)
allow the platform hop with nodes left on their current RHCOS, and a
later move to RHCOS 10.2. A mix of RHCOS 9.x and 10.2 is not supported.
A downgrade from 10.2 to 9.x is not supported. A cluster on runC cannot
change RHCOS version until it uses crun. The 4.22 test plan is
[RHCOS 10 on OpenShift 4.22: What Changes](/posts/rhcos-10-openshift/).

The update still has two phases. The Cluster Version Operator (CVO)
applies the payload first. That phase might take 60 to 120 minutes. The
Machine Config Operator then updates nodes. `maxUnavailable` defaults
to `1`. Leave it there, update one control-plane node at a time, and do
not set `maxUnavailable` to `3` for the control-plane pool. Guests that
have to stay up through a 4.22 drain are covered in
[Upgrading OpenShift While VMs Stay Running](/posts/upgrading-openshift-while-vms-stay-running/).
That post is written against the 4.22 virtualization chapters. Guest
changes in 5.0, including the life-cycle model after this release, are
in
[OpenShift Virtualization 5.0: The Updates That Matter](/posts/openshift-virtualization-5-0-features/).

A Control Plane Only update is a different procedure in the same book:
even-numbered minor to the next even-numbered minor, through the odd
minor, with non-control-plane pools paused, and only after the updates
between those versions are in stable channels. The 4.x to 5.0 chapter
describes the ordinary in-place update. Pause a pool for a canary.
Nodes in a paused pool are skipped.

## Path A and Path B

| Question | Path A: park on 4.22 | Path B: hop to 5.0 |
| -------- | -------------------- | ------------------ |
| Who it fits | Virt-heavy estates still sorting drain and eviction. Change windows that cannot open before 4.22 full support ends. Clusters whose Operator Lifecycle Manager (OLM) Operators have no 5.0-compatible version yet. | Clusters whose Operators have a compatible version, whose graph shows a recommended update, and that want full support past December 31, 2026. |
| Channel | The channel for the minor you are running, so you keep receiving z-streams. | `stable-5.0` or `fast-5.0` once `oc adm upgrade` lists a path. Production uses `stable-*`, `eus-*`, or `fast-*`. |
| Clock | Full support through December 31, 2026, maintenance support through December 31, 2027, then add-on Term 1 and Term 2. Term 3 is N/A. | Full support through November 30, 2027, maintenance support through November 30, 2028. Add-on columns are N/A. |
| Host OS | The stream the cluster already runs. | The hop can leave every node on its current RHCOS. Moving one node to 10.2 means moving all of them, on crun, with no supported downgrade. |

**Path A fits a cluster that can finish 2026 on 4.22 and has a reason
to.** Virt estates still sort guests before nodes reboot. The 4.22
upgrade post covers the drain process: storage, spare memory, eviction
strategy, and the webhook that can block a drain. OpenShift Virtualization
on 5.0 is another Operator. Confirm a compatible version the same way
you confirm every other OLM Operator. If the upgrade window falls after
December 31, 2026, the cluster will enter maintenance support on
January 1, 2027.
The life-cycle table names the phase. It does not, on the table itself,
define which fixes that phase includes. Read the linked support
policy before a change board writes that down. An Operator with no
5.0-compatible version blocks the hop, because the default catalogs
switch minors during the update.

The risk is the clock, and the z-streams you still take. A channel that
matches the current minor applies z-streams and leaves the next minor
alone. `oc adm upgrade` prints the channel names that cluster is
offered. Parking delays the 5.0 deprecation clock. Plan ahead for the
RHCOS and Helm transitions described in the cleanup list below.

**Path B fits a cluster that can finish the in-place update in one
window**, with a recommended version on the graph and the cleanup below
already done. The life-cycle payoff is full support through November 30,
2027, on a row with no Extended Update Support add-on. I would keep the
move to RHCOS 10.2 as its own campaign unless drivers and guests are
already rehearsed.

Path B has to finish. Rollback to the previous version is not supported.
A stable-only policy also absorbs the promotion delay, and that delay
has no service-level objective. `fast-5.0` is the production channel
that receives a release when Red Hat declares it generally available.
Moving from `stable-5.0` to `fast-5.0` leaves the cluster supported.
Read the available-channels list on the 4.22 cluster before you switch.

## Read the graph on the cluster

Declare the channel with `oc adm upgrade channel` or the web console.
The [ClusterVersion API](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html-single/config_apis/index#clusterversion-config-openshift-io-v1)
(`config.openshift.io/v1`) describes `spec.channel` as the identifier
for the update set. `spec.clusterID` is required. Setting
`spec.desiredUpdate` starts an update when the current version differs,
and a value outside the recommended set may cause the update to fail.
The update guide says not to modify the ClusterVersion object directly.
A GitOps repo records the channel and runs the CLI.

```shell
oc adm upgrade
oc adm upgrade recommend
oc adm upgrade channel stable-5.0
oc adm upgrade --to=<version>
```

Replace `<version>` with a version recommended by
`oc adm upgrade recommend` on that cluster.
To move to the latest version, the guide uses
`oc adm upgrade --to-latest=true`. `--force` bypasses release
verification and precondition checks, and the guide says it does not
guarantee success. `--allow-not-recommended` is how an administrator
proceeds after accepting a known risk. Put that acceptance on the change
record.

If recommend shows no path to the minor you want, keep updating to the
latest patch of the current version until the next minor is on the path.
Recommendations change as the update service publishes options. A
channel that does not include the release you are running makes the
console warn and recommend nothing. You can switch back.

When no update service is reachable, the same `oc adm upgrade channel`
command can set an empty channel. If you mirror images yourself, read
the errata before you choose a version, and choose it before you bypass
a console warning. A local OpenShift Update Service is a different
field: `spec.upstream` on `clusterversion/version`, patched with `oc`
or edited in the console. The default the guide names is
`https://api.openshift.com/api/upgrades_info/v1/graph`. That patch
points at an update server. It does not select 5.0.

## Clean these up before the hop

Unmet prerequisites in the update chapter block the hop. Discovering
deprecations during the maintenance window can also disrupt the plan.

1. **Backups.** Take a recent etcd backup and a recent Container Storage
   Interface (CSI) volume snapshot. Restoring a single-node cluster
   from an etcd backup is not officially supported. Take the backup
   anyway. The guide says a healthy control plane might be restorable
   from it. A single-node update requires downtime and does not roll
   back automatically if the node fails to restart.
2. **RHEL 7 workers.** Replace them with RHEL 8 or RHCOS. An in-place
   RHEL 7 to RHEL 8 update of a RHEL worker is not supported. Those
   hosts need a clean install.
3. **OLM Operators.** Move every installed Operator to a version
   compatible with the target before the default catalogs switch minors.
4. **`Upgradeable=False`.** Clear it before a minor update. Cluster
   Settings alerts when a cluster Operator cannot update. A patch
   inside the current minor can still proceed.
5. **`unsupportedConfigOverrides`.** Remove them. The guide says the
   setting is unsupported and can block the update.
6. **Machine config pools.** Leave them running and unpaused unless
   this is a canary. Paused pools are skipped.
7. **Machine health checks.** Pause worker `MachineHealthCheck`
   objects so a briefly unavailable node is not rebooted. Skip this on
   a single node. Resume the checks after the update.

   ```shell
   oc get machinehealthcheck -n openshift-machine-api
   oc -n openshift-machine-api annotate mhc <mhc_name> cluster.x-k8s.io/paused=""
   oc -n openshift-machine-api annotate mhc <mhc_name> cluster.x-k8s.io/paused-
   ```

8. **Pod disruption budgets.** `minAvailable: 1` can block the drain.
   The virt post is the guest-shaped version of that failure. The 5.0
   update chapter states the budget problem and does not restate the
   4.22 drain timers.
9. **crun, before any RHCOS change.** runC is generally available in
   4.21, deprecated in 4.22, and deprecated in 5.0, with removal
   described as a future release. The RHCOS note is the gate: you
   cannot change the RHCOS version on runC, and you must configure
   crun. The platform hop can leave the OS where it is. If this window
   includes RHCOS 10.2, crun comes first.
10. **kmods-via-containers (KVC).** The removed-features section says
    this was deprecated in 4.22 and is removed in 5.0. The deprecation
    topic in the same notes still says removal is a future release.
    Plan from the removed-features section. The notes do not name a
    replacement there. Validate the node configuration on a disposable
    cluster.
11. **Mirroring.** `oc adm release mirror` has been deprecated since
    4.22 and will be removed in a future release. The notes name
    oc-mirror plugin v2 as the alternative. oc-mirror plugin v1 is
    deprecated, and the customer portal no longer carries its docs.
    Move a disconnected pipeline off `oc adm release mirror` before
    the hop, using the fields the v2 procedure shows.
12. **`PolicyGenTemplate`.** As of 5.0, the custom resource and its
    Kustomize plugin are deprecated and will be removed in a future
    release. GitOps Zero Touch Provisioning repos should generate
    `PolicyGenerator` resources. The update chapter does not list this
    as a precondition. A repo that keeps writing the old object is
    still writing it after the hop.
13. **Helm v3 CLI.** Deprecated in 5.0, still usable beside the Helm v4
    CLI, and not available in 5.1 or later. The 5.0 web console uses
    the Helm v4 SDK, and existing charts continue to work. Migrate
    pipelines that call the v3 binary to the Helm v4 CLI before
    upgrading to 5.1.
14. **RHCOS 9.x.** Deprecated in 5.0, with removal planned for 5.3.
    You can hop and leave nodes on 9.x. You cannot run 9.x and 10.2
    together, and you cannot downgrade 10.2 to 9.x.

The deprecation tables also still list `ImageContentSourcePolicy`,
`DeploymentConfig`, iptables, the SQLite catalog format, and the Cluster
Samples Operator. The Node Observability Operator is removed in 5.0.
Use the
[deprecation topic](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/release_notes/ocp-5-0-release-notes#rn-ocp-release-notes-deprecated-features_release-notes)
and the
[removed-features section](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/release_notes/ocp-5-0-release-notes#rn-ocp-release-notes-removed-features_release-notes)
as the full pass.

## Failure modes

> The update guide says a rollback to the previous version is not
> supported when an update fails to finish. The CVO reports the
> blocking components, and the next step it names is Red Hat support.
> `oc adm upgrade --force` skips release verification and precondition
> checks. The guide says that flag does not guarantee success.
{: .prompt-warning }

**A version the cluster did not recommend.** The errata says to upgrade
when 5.0.0 is in the appropriate channel. Use `oc adm upgrade` to check
what your channel offers, then select a version from the output of
`oc adm upgrade recommend`. General availability does not guarantee
that a release is already in your stable channel.

**`stable-5.0` before that cluster has a path.** The console warns when
the channel does not include the current release, and it recommends no
updates until you switch back. Take the latest patch the current
channel does recommend, then read the graph again. December 31, 2026
ends 4.22 full support on the life-cycle page. The update guide does
not attach that date to a z-stream inside `stable-5.0`.

**`candidate-5.0` on a cluster you have to keep.** That channel is for
tests you can destroy. Some releases there are unsupported and may not
offer a path forward.

**The OS move folded into the hop.** Apply the RHCOS compatibility rules
above before adding the OS move to this window. For KVC, plan from the
removed-features section despite the conflicting deprecation wording,
and validate the node configuration on a disposable cluster first.

**A budget, a guest, or a paused worker pool.** `minAvailable: 1` can
block eviction. Sort guests with the 4.22 procedure before the window.
Pausing non-control-plane pools is the Control Plane Only procedure.
For this hop, pause a pool when you are running a canary.

**A single node treated like a compact cluster.** The update requires
downtime. An OS payload reboots the node, and a node that does not
return does not roll back on its own. The virt post's single-node
default is `evictionStrategy: None`, because there is nowhere to move
a guest.

## The solutions architect takeaway

1. **The calendar is the decision.** On the life-cycle page as reviewed
   November 16, 2026, 4.22 full support runs through December 31, 2026,
   then maintenance support through December 31, 2027, then the add-on
   terms on that row. 5.0 reached general availability on November 3,
   2026, full support runs through November 30, 2027, and the add-on
   columns are N/A. Future dates on that page are approximations. 4.19
   maintenance support ends December 17, 2026. That row is not a place
   to park.
2. **Park when the guests, the window, or an Operator cannot absorb 5.0
   yet.** Stay on the channel for 4.22 and keep taking z-streams. Hop
   when `oc adm upgrade recommend` shows a version and the cleanup list
   is done. The hop is in-place, and the release notes allow it with
   nodes left on their current RHCOS.
3. **The graph picks the version.** Production channels are `stable-*`,
   `eus-*`, and `fast-*`. `oc adm upgrade channel stable-5.0` is the
   documented example. Allow for the stable-channel promotion delay
   described above. `candidate-5.0` is for clusters you can throw away.
   Declare the channel with the CLI or the console. Leave the
   ClusterVersion object alone.
4. **Clean up what 5.0 removes or starts a clock on.** crun before any
   RHCOS change. KVC is removed in the removed-features section.
   Replace `oc adm release mirror` and oc-mirror v1 with oc-mirror v2.
   Move `PolicyGenTemplate` to `PolicyGenerator`. Migrate callers to
   the Helm v4 CLI before upgrading to 5.1. RHCOS 9.x is deprecated in
   5.0 and planned for removal in 5.3.
5. **A stalled update has no supported rollback.** Size the window so it
   can finish: etcd backup, CSI snapshots, compatible Operators,
   unpaused pools, paused machine health checks, and disruption budgets
   that allow a drain. Virt estates rehearse the 4.22 guest procedure
   before they book the hop.

> Want help deciding which clusters park on 4.22 and which hop to 5.0?
> Work with your Red Hat account team, and review the output of
> `oc adm upgrade recommend` on each cluster before the window is booked.
{: .prompt-tip }

## Related posts

- [OpenShift 5.0: The Platform Features That Matter](/posts/openshift-5-features-that-matter/)
- [OpenShift Virtualization 5.0: The Updates That Matter](/posts/openshift-virtualization-5-0-features/)
- [Upgrading OpenShift While VMs Stay Running](/posts/upgrading-openshift-while-vms-stay-running/)
- [RHCOS 10 on OpenShift 4.22: What Changes](/posts/rhcos-10-openshift/)

## Further reading

- [Performing a cluster update (OpenShift 5.0)](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/updating_clusters/performing-a-cluster-update)
- [Understanding update channels and releases (OpenShift 5.0)](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html-single/updating_clusters/index#understanding-update-channels-releases)
- [ClusterVersion API (OpenShift 5.0)](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html-single/config_apis/index#clusterversion-config-openshift-io-v1)
- [OpenShift Container Platform 5.0 release notes](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/release_notes/ocp-5-0-release-notes)
- [RHCOS in the 5.0 release notes](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/release_notes/ocp-5-0-release-notes#ocp-release-notes-rhcos_release-notes)
- [Deprecated features (OpenShift 5.0)](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/release_notes/ocp-5-0-release-notes#rn-ocp-release-notes-deprecated-features_release-notes)
- [Removed features (OpenShift 5.0)](https://docs.redhat.com/en/documentation/openshift_container_platform/5.0/html/release_notes/ocp-5-0-release-notes#rn-ocp-release-notes-removed-features_release-notes)
- [OpenShift Container Platform life cycle](https://access.redhat.com/product-life-cycles?product=Red+Hat+OpenShift+Container+Platform)
- [RHEA-2026:4893, OpenShift Container Platform 5.0.0](https://access.redhat.com/errata/RHEA-2026:4893)

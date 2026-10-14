---
title: "Why OpenShift supplementalGroups Fail on ONTAP NFS"
description: >-
  id shows the supplemental GID, but a NetApp ONTAP SVM with extended groups
  ignores it. Grant OpenShift NFS access from the UID's directory group
  membership.
date: 2026-10-14 12:00:00 -0500
categories: [OpenShift]
tags: [openshift, storage]
permalink: /posts/openshift-nfs-supplemental-groups-ontap/
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization. SVM options and name service
> behavior vary by ONTAP release. Confirm
> [Managing security context constraints](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/authentication_and_authorization/managing-pod-security-policies)
> for your OpenShift version and the
> [ONTAP group-ID limit](https://docs.netapp.com/us-en/ontap/nfs-admin/configure-number-group-ids-allowed-nfs-users-task.html)
> for the storage virtual machine (SVM) you will actually mount.
{: .prompt-info }

A workload mounts a NetApp ONTAP NFS export. The pod spec sets `runAsUser` to
a numeric UID and puts the share's group in `supplementalGroups`. `id` inside
the container prints that GID. Access to the mount is denied.

The same UID works when that GID is the primary group (`runAsGroup`). A
different UID that is a real member of the group in the directory also works,
with no `supplementalGroups` at all, and `id` never lists the NAS group.

OpenShift attached the supplemental group. The NFS server ignored it.

## What the tests are telling you

Use two UIDs and one GID that you control. In the examples below, UID `10001`
exists in LDAP and is not a member of GID `20001`. UID `10002` is a member of
GID `20001`. The export is UNIX security style, NFSv4.1, `sec=sys`. The
exported folder is group-owned by `20001` with mode `0770`. Neither UID is in
the image passwd file, so an omitted `runAsGroup` becomes primary GID `0`.

| Pod identity                                      | What `id` shows                                      | NFS result |
| ------------------------------------------------- | ---------------------------------------------------- | ---------- |
| `runAsUser: 10001`, `supplementalGroups: [20001]` | `10001`, primary GID `0`, supplemental `20001`       | Denied     |
| `runAsUser: 10001`, `runAsGroup: 20001`           | primary GID `20001`                                  | Allowed    |
| `runAsUser: 10002`, no group fields               | `10002`, primary GID `0`. Share GID `20001` absent   | Allowed    |

The first row is the one that misleads people. `id` is the container process
credential. It proves the security context constraint (SCC) admitted the GID
and the runtime put it on the process. The NAS does not have to use that list.

The third row decides the design. Access succeeded while `id` did not list
GID `20001`. ONTAP looked up UID `10002` in the directory and applied that
account's groups. On `restricted-v2`, `id` may also list the namespace
`fsGroup`. That extra GID is not the share group.

## What ONTAP does with extended groups

AUTH_SYS (the credential behind `sec=sys`) carries one UID, one primary GID,
and a list of auxiliary GIDs. RFC 5531 caps that auxiliary list at 16. ONTAP
can raise the cap, up to 1024, by enabling AUTH_SYS extended groups on the
SVM.

That option does not mean "trust a longer list from the client." With
`auth-sys-extended-groups` enabled, ONTAP drops the auxiliary GIDs from the
RPC header. It keeps the primary GID, for setgid compatibility, and builds
the rest of the credential by resolving the UID through the SVM name service
switch. When the SVM uses a directory, that switch usually lists local files
first, then LDAP or NIS. A local UNIX user with the same UID shadows LDAP.

The auxiliary list on the pod is not part of the credential ONTAP enforces.
Access is granted when the UID's directory groups include the file's group,
or when the primary GID in the RPC credential matches. Putting GID `20001`
in `supplementalGroups` adds it to `id` and leaves the NAS credential
unchanged.

The primary GID is why the second test passes for a non-member. ONTAP still
honors the primary GID field from the client. That is a useful confirmation.
It is a poor production pattern: every share would need its own primary GID,
and a pod has only one.

Confirm it on the SVM before you redesign the pods:

```text
set -privilege advanced

vserver nfs show -vserver svm1 -fields auth-sys-extended-groups,extended-groups-limit
vserver services name-service ns-switch show -vserver svm1
```

`auth-sys-extended-groups` is an advanced-privilege field. You want it
**enabled**, with `extended-groups-limit` above 16, and the `group` database
including `ldap` or `nis`. An export-policy rule that permits `sys`, on a
qtree with UNIX security style, matches this failure mode. An NTFS security
style, or a mount that negotiates Kerberos instead of `sec=sys`, is a
different problem. If file owners on the mount show up as `nobody` or
`65534`, fix NFSv4 idmapping before you chase groups.

Leave the option enabled. It is what lets users belong to more than 16
groups, and it applies to every NFS client of that SVM. Turning it off would
make the client auxiliary list trusted again, and only up to 16 auxiliary
GIDs.

## Configure the workload

Create one directory account for the workload. Use that account's UID as
`runAsUser`. Add the account to each NAS group that should have access. One
account can be in many groups, so one pod can mount many shares.

Set `runAsGroup` to that account's real primary GID from the directory. If
you set `runAsUser` alone, and the image has no passwd entry for that UID,
the container primary GID becomes `0`. ONTAP keeps that primary GID, so
group permissions on files owned by GID `0` apply. That is broader than the
share you meant to open. The process is still that UID, not UID `0`.

`supplementalGroups` stays unset for this NAS. The group that grants access
will not appear in `id`. That is the expected result on this SVM.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nfs-access-test
  namespace: data-apps
spec:
  securityContext:
    runAsUser: 10002
    runAsGroup: 10002
  containers:
  - name: test
    image: registry.access.redhat.com/ubi9/ubi-minimal
    command: ["/bin/sh", "-c", "sleep infinity"]
    volumeMounts:
    - name: nas
      mountPath: /mnt/data
  volumes:
  - name: nas
    persistentVolumeClaim:
      claimName: app-data
```

`10002` / `10002` here means "the directory account and its primary group."
Use the real values from LDAP. GID `20001` is a secondary group of that
account in the directory. It is not a field in the pod spec.

`runAsUser` has to fall inside the namespace annotation
`openshift.io/sa.scc.uid-range`. On the default `restricted-v2` SCC, that
is the check that rejects a new service-account UID. A pod that is already
`Running` as that UID has passed it.

`restricted-v2` sets `supplementalGroups` to `RunAsAny`, so the cluster
admits any supplemental GID. A running pod is not evidence the NAS will
honor that GID. `fsGroup` on this SCC is `MustRunAs`. OpenShift fills it
with the first value in `openshift.io/sa.scc.supplemental-groups`, or in
the UID range when that annotation is absent, and adds it to the process.
It can show up in `id`. It is not the share group, and extended groups
ignore it the same way. Setting `fsGroup` to the share GID fails admission
unless that GID is exactly the preallocated value. See
[Managing security context constraints](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/authentication_and_authorization/managing-pod-security-policies).

Two storage follow-ups belong in the same change window:

- **Credential cache.** After you add the account to a group, the SVM can
  keep serving the old credential. A positive cache of about a day and a
  negative cache of a couple of hours are common. Read the TTL fields on
  `vserver nfs show` for this SVM, and ask storage to flush the credential
  cache before the retest. Otherwise a correct directory change looks like
  another denial.
- **LDAP group cap.** `extended-groups-limit` of 1024 does not by itself
  mean LDAP will return 1024 groups. RFC 2307bis schemas on the ONTAP LDAP
  client often default to 32. If the service account will sit in more groups
  than that, have storage raise the schema maximum to match the SVM limit.
  NetApp covers the prerequisites in
  [AUTH_SYS extended groups](https://kb.netapp.com/on-prem/ontap/da/NAS/NAS-KBs/How_does_AUTH_SYS_Extended_Groups_change_NFS_authentication).

## Prove the fix

1. On the SVM, record `auth-sys-extended-groups`, `extended-groups-limit`,
   and the `group` name-service order.
2. In the directory, confirm the service account is a member of the share
   group. A GID that merely exists in LDAP is not a membership.
3. Ask storage to flush the SVM credential cache.
4. Run the pod with `runAsUser` and `runAsGroup` only.
5. `id` should show the account and its primary GID. The share group is
   absent unless you also set it as `runAsGroup`. `ls` and a create on the
   mount should succeed.
6. Repeat against a second share whose group the same account has joined.
   Still one primary GID.

If access still fails, compare the data logical interface (LIF) in the pod
(`addr=` in `/proc/mounts`) with any packet capture. A capture of a different
LIF, or of the node's own `GETATTR` traffic, can show `uid=0` and an empty
auxiliary list. That capture does not describe this pod.

## Where supplemental groups still matter

`supplementalGroups` remains the right OpenShift control for local and
block volumes, and for any NFS server that trusts the client auxiliary list.
That is an SVM with extended groups **disabled**: ONTAP then builds the
credential from the RPC header and stops at 16 auxiliary GIDs.

`fsGroup` is not a substitute on this export. The kubelet does not
recursively chown an NFS tree the way it chowns a block volume. On
`restricted-v2` it still adds one GID to the process, and ONTAP extended
groups ignore that GID. The array enforces mode bits from the credential
it built out of the UID's directory groups and the primary GID.

NFS is also the wrong place for etcd, image storage, and other platform
disks. Size and protocol for those paths are covered in
[OpenShift Storage Performance: Disks, IOPS, Architectures](/posts/openshift-storage-performance/).
This post is only the identity problem on an application export that you
have already chosen to serve from ONTAP.

## The solutions architect takeaway

1. **`id` proves the pod, not the NAS.** A supplemental GID in the container
   means the SCC and the runtime did their job.
2. **Extended groups replace the auxiliary list.** ONTAP keeps the primary
   GID and loads groups for that UID from files, then LDAP or NIS.
3. **Put the service account in the directory groups.** One UID, many group
   memberships, one `runAsGroup` set to the account's real primary GID.
4. **Leave extended groups enabled.** Disabling it to make
   `supplementalGroups` work reimposes the cap of 16 auxiliary GIDs on
   every client of the SVM.
5. **Flush the credential cache and check the LDAP group maximum** before
   you call a retest a failure.

## Related posts

- [OpenShift Storage Performance: Disks, IOPS, Architectures](/posts/openshift-storage-performance/)

> Want help pinning down NFS identity on an OpenShift landing zone? Reach
> out to your Red Hat account team, and have storage confirm
> `auth-sys-extended-groups` on the SVM before you design
> `supplementalGroups` into the workload.
{: .prompt-tip }

## Further reading

- [Managing security context constraints (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/authentication_and_authorization/managing-pod-security-policies)
- [Configure the number of group IDs allowed for NFS users (ONTAP)](https://docs.netapp.com/us-en/ontap/nfs-admin/configure-number-group-ids-allowed-nfs-users-task.html)
- [How AUTH_SYS extended groups differ from normal operations (NetApp KB)](https://kb.netapp.com/on-prem/ontap/da/NAS/NAS-KBs/How_does_auth-sys-extended-groups_differ_from_normal_operations)
- [AUTH_SYS extended groups and NFS authentication (NetApp KB)](https://kb.netapp.com/on-prem/ontap/da/NAS/NAS-KBs/How_does_AUTH_SYS_Extended_Groups_change_NFS_authentication)
- [Prerequisites for auth-sys-extended-groups (NetApp KB)](https://kb.netapp.com/on-prem/ontap/da/NAS/NAS-KBs/What_are_the_prerequisites_for_enabling_auth_sys_extended_groups)
- [Storage (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/configure-the-cluster/storage/)

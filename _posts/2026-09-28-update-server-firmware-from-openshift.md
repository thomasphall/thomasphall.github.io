---
title: "How to Update Server Firmware from OpenShift"
description: >-
  Flash BIOS, BMC, and supported NIC firmware on bare-metal OpenShift 4.22
  hosts through Redfish, including the live servicing reboot on provisioned
  hosts.
date: 2026-09-28 09:00:00 -0500
categories: [OpenShift]
tags: [openshift, bare-metal]
permalink: /posts/update-server-firmware-from-openshift/
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization. Firmware images, Redfish
> behavior, and the product procedure move. Confirm the
> [OpenShift 4.22 bare-metal postinstallation chapter](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/installing_on_bare_metal/bare-metal-post-installation-configuration)
> and your vendor's update package for the servers you will actually flash.
{: .prompt-info }

> **A firmware flash reboots the server into the Ironic Python Agent.** Do
> it one host at a time, on a cluster with spare compute capacity. Do not
> interrupt a flash that has started. If it stalls, engage the hardware
> vendor. A cluster with fewer than three compute nodes can go degraded
> for the duration.
{: .prompt-danger }

OpenShift can flash server firmware when the Bare Metal Operator is managing
the host. The operator hands a component name and an image URL to Ironic.
Ironic talks to the baseboard management controller (BMC) over Redfish, boots
the host into the Ironic Python Agent, and applies the image.

That path is for bare-metal hosts with a `BareMetalHost`. Installer-provisioned
infrastructure and other installs that registered hosts with Metal3 qualify.
ROSA, Azure Red Hat OpenShift, OpenShift Dedicated, vSphere, and
OpenShift Virtualization guests do not. Those platforms own the hardware
underneath the node. If the server was installed by hand and never became a
`BareMetalHost`, keep using iDRAC, iLO, XClarity, or Intersight.

## What you are changing

Three custom resources show up on every Metal3 host in
`openshift-machine-api`. Only one of them flashes an image.

| Resource | What it does |
| -------- | ------------ |
| `HostFirmwareComponents` | BIOS, BMC, and some NIC firmware images. You set `spec.updates` to a component and a URL. |
| `HostFirmwareSettings` | BIOS settings (boot order, memory test, virtualization flags). Same reboot machinery, different payload. See [Faster Bare-Metal Boots in OpenShift PoCs](/posts/poc-faster-bare-metal-boot-disable-memory-check/) for the PoC case. |
| `HostUpdatePolicy` | When a change is allowed. `onPreparing` (the default) waits for a provision cycle. `onReboot` allows a live servicing reboot on an already provisioned host. |

`status.components` is an inventory, not a live poll. Ironic fills it at
enrollment and refreshes it after provisioning or a flash. A quiet host will
keep showing the version it had when it was last inspected.

## Before you flash

Check all of these on the target host. Skip the flash if any line fails.

1. **Redfish BMC.** `spec.bmc.address` on the `BareMetalHost` is a Redfish
   URL (`redfish-virtualmedia`, `idrac-redfish`, `ilo5`, or the equivalent).
   An IPMI-only BMC can power the chassis. It cannot take this update.
2. **The image URL is fetchable by Ironic**, not just by your laptop. Put
   the vendor file on an HTTP server the Ironic pods can GET without a
   browser login. A support-site HTML page, a portal that wants credentials,
   or a URL that only resolves on the corporate laptop will fail in
   `servicing`.
3. **The URL is the update trigger.** Ironic applies an update when the URL
   for that component changes. Editing a version string in `status` does
   nothing. Hosting the same bytes at a new URL is what requests a new flash.
4. **One worker first.** Confirm `oc get nodes` shows the node Ready and
   the rest of the compute pool can take its pods. Leave control-plane
   nodes until a worker flash has succeeded on this hardware generation.
5. **Spare capacity.** The product procedure warns that fewer than three
   compute nodes can leave the cluster degraded while the host is offline.

The Bare Metal Operator creates `HostFirmwareComponents` and owns it. Patch
`spec.updates`. Replacing the whole object from Git drops the owner reference
and fights the controller.

Read the inventory before you choose an image:

```shell
oc get hostfirmwarecomponents <host> -n openshift-machine-api -o yaml
```

You want `status.components` for `bios` and `bmc`, plus any `nic:` entries,
and `status.conditions` type `Valid` in `True`.

## Two ways to apply it

| | Live servicing | During provisioning |
| --- | --- | --- |
| When | The host is already `provisioned` and you want the same node back | The host is not provisioned yet, or you are already deleting that worker `Machine` |
| Policy | `HostUpdatePolicy` `firmwareUpdates: onReboot` | Default `onPreparing` |
| What the host does | Stays provisioned. Reboots into the agent, flashes, boots RHCOS again | Drops to `preparing` as part of a provision cycle, then comes back as a new `Machine` |
| Use it for | Day-2 BIOS or BMC on a worker you intend to keep | A worker you are reprovisioning anyway |

The 4.22 chapter has an "edit the resource of a provisioned host" procedure
whose steps delete the `Machine` and scale the `MachineSet`. That is the
provisioning path, and it is aimed at worker machine sets. Use live
servicing when the node should keep its identity.

The same chapter's edit example sets `name:` under `spec.updates`. The
custom resource requires `component` and `url`. `name` is not a field. The
live-update patch later in that chapter uses `component`. Use `component`.

Valid `component` values:

| Value | Firmware |
| ----- | -------- |
| `bios` | System firmware |
| `bmc` | BMC firmware |
| `nic:<adapter-id>` | A NIC Redfish marks updateable. `nic:AD007` is the shape. The id comes from the host, not from a guess. |

NIC flashes through this API are documented for the Intel Ethernet 800 Series
(`ice`) and NVIDIA ConnectX-6 and ConnectX-7 (`mlx5`), validated on Dell
hardware. Redfish can list a NIC and still set `Updateable` to `false`. If
several adapters share a firmware image, Redfish may apply that image to
every adapter that can take it. Read the inventory before you assume a
single-port flash.

## Live servicing

Create a `HostUpdatePolicy` whose name matches the `BareMetalHost`.
`firmwareUpdates: onReboot` is the switch for images.
`firmwareSettings: onPreparing` leaves BIOS *settings* on the provision path
so this change does not also rewrite BIOS knobs.

```yaml
apiVersion: metal3.io/v1alpha1
kind: HostUpdatePolicy
metadata:
  name: worker-0
  namespace: openshift-machine-api
spec:
  firmwareSettings: onPreparing
  firmwareUpdates: onReboot
```

```shell
oc apply -f hostupdatepolicy.yaml
```

Point `spec.updates` at the image. One component is enough; repeat the object
in the array for a second image. This example flashes BIOS only.

```shell
oc patch hostfirmwarecomponents worker-0 \
  -n openshift-machine-api --type merge -p \
  '{"spec":{"updates":[{"component":"bios","url":"http://192.0.2.10/firmware/bios.bin"}]}}'
```

Confirm the resource accepted it. `status.conditions` type `Valid` should be
`True`, and `ChangeDetected` should be `True`. If `Valid` is `False`, the URL
or component name was rejected and the host will not flash.

Drain the cluster node. The node name is usually the fully qualified name
(`worker-0.example.com`). The `BareMetalHost` name is the short name
(`worker-0`). DaemonSet pods will not leave, so ignore them or the drain
waits forever:

```shell
oc drain worker-0.example.com \
  --ignore-daemonsets --delete-emptydir-data --force --grace-period=60
```

Power the host off and leave it offline for about five minutes. That gives
controllers time to treat the node as gone before Ironic takes it:

```shell
oc patch baremetalhost worker-0 -n openshift-machine-api --type merge \
  -p '{"spec":{"online":false}}'
```

Power it back on:

```shell
oc patch baremetalhost worker-0 -n openshift-machine-api --type merge \
  -p '{"spec":{"online":true}}'
```

Watch `status.operationalStatus`. It moves to `servicing` while Ironic boots
the agent and flashes, then back to `OK`. `error` means the operator will
retry; read the message on the `BareMetalHost` before you power-cycle it
again.

```shell
oc get baremetalhost worker-0 -n openshift-machine-api \
  -o jsonpath='{.status.operationalStatus}{"\n"}'
```

When the status is `OK` and `oc get nodes` shows the node `Ready`, return it
to the scheduler:

```shell
oc uncordon worker-0.example.com
```

The product procedure lists uncordon immediately after power-on. Wait for
`Ready`. Uncordoning during `servicing` schedules pods onto a host that is
about to reboot into the agent.

## During provisioning

Use this when the worker is already being replaced, or when
`firmwareUpdates` is still `onPreparing` and you want the flash to happen
before the host is handed back to the cluster.

1. Patch `HostFirmwareComponents` with the same `component` and `url` shape
   as above.
2. On the worker `Machine` (the `CONSUMER` column of
   `oc get baremetalhost <host> -n openshift-machine-api`), annotate
   `machine.openshift.io/delete-machine=true`.
3. Scale that worker `MachineSet` down by one. Wait until the host is
   `available`.
4. Scale the `MachineSet` back to the original replica count.

Do not point that scale-down at a control-plane machine set. Control-plane
firmware belongs on the live path, one node at a time, with etcd healthy and
the other masters Ready.

## Check the result

```shell
oc get hostfirmwarecomponents worker-0 -n openshift-machine-api \
  -o jsonpath='{range .status.components[*]}{.component}{" "}{.currentVersion}{" flashed="}{.lastVersionFlashed}{"\n"}{end}'
```

`currentVersion` should match the image you intended.
`lastVersionFlashed` stays empty until Ironic has actually written an image.
`updatedAt` is the timestamp of that write.

Then confirm the node is `Ready`, pods rescheduled, and the BMC still
answers. A successful OpenShift status with a BMC you can no longer reach is
a failed change.

## Wrap-up

Bare-metal OpenShift flashes firmware through `HostFirmwareComponents`,
Ironic, and Redfish. Set `component` and a URL Ironic can fetch, enable
`firmwareUpdates: onReboot` when the host is already provisioned, and let
servicing finish. BIOS settings are the other resource. Cloud and virtual
nodes stay on the platform that owns the hardware. Vendor appliance stacks
still own firmware when that was the reason you bought them; see
[OpenShift Hardware Vendor Reference Architectures](/posts/openshift-hardware-vendor-reference-architectures/).

For the rest of a bare-metal OpenShift PoC, start at
[How to Get Started with an OpenShift PoC](/posts/getting-started-openshift-poc/)
or the
[OpenShift PoC overview](https://openshift-ssa.github.io/openshift-poc/home/).

## Related posts

- [Faster Bare-Metal Boots in OpenShift PoCs](/posts/poc-faster-bare-metal-boot-disable-memory-check/)
- [OpenShift Hardware Vendor Reference Architectures](/posts/openshift-hardware-vendor-reference-architectures/)
- [How to Get Started with an OpenShift PoC](/posts/getting-started-openshift-poc/)
- [OpenShift Edge Architectures: Form Factor, Then Fleet](/posts/openshift-edge-architectures/)

## Further reading

- [Postinstallation configuration (OpenShift 4.22 bare metal)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/installing_on_bare_metal/bare-metal-post-installation-configuration)
- [Installing on bare metal (OpenShift 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/installing_on_bare_metal/index)
- [Metal3 firmware updates](https://book.metal3.io/bmo/firmware_updates.html)
- [Metal3 live updates (servicing)](https://book.metal3.io/bmo/live_updates_servicing.html)
- [OpenShift PoC overview](https://openshift-ssa.github.io/openshift-poc/home/)

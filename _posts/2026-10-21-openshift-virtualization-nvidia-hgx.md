---
title: "OpenShift Virtualization 4.22 on NVIDIA HGX"
description: >-
  OpenShift Virtualization 4.22 is an NVIDIA-Certified Hypervisor for Hopper
  HGX. What 8-GPU passthrough proves, and when that GPU stays on a VM versus
  a pod.
date: 2026-10-21 15:30:00 -0500
categories: [OpenShift, Virtualization]
tags: [openshift, openshift-virtualization, bare-metal]
permalink: /posts/openshift-virtualization-nvidia-hgx/
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization. Certification scope moves.
> Confirm the
> [NVIDIA-Certified Hypervisors list](https://docs.nvidia.com/certification-programs/certified-hypervisors/latest/hypervisors-list.html)
> and the
> [Red Hat announcement](https://www.redhat.com/en/blog/red-hat-openshift-virtualization-achieves-nvidia-certified-hypervisor-status)
> for the stack you will actually run.
{: .prompt-info }

On 21 October 2026, Red Hat OpenShift Virtualization 4.22 joined the
NVIDIA-Certified Hypervisors list. The row is specific:
[Red Hat OpenShift](https://www.redhat.com/en/technologies/cloud-computing/openshift)
Container Platform 4.22 with OpenShift Virtualization 4.22, on the x86 track,
for NVSwitch-based 8-GPU NVIDIA Hopper SXM systems. Red Hat's announcement
names that board class as NVIDIA HGX.

OpenShift Virtualization is on that list as a Kubernetes-native hypervisor:
the virtual machine is a KubeVirt workload on KVM, scheduled like any other
pod, and the GPUs are assigned by passthrough.

GPU virtual machines and containerized AI share that cluster as separate GPU
node pools. The listing is evidence about an 8-GPU passthrough guest,
its topology, and representative inference. It is the operations piece that
sits beside
[What's New in Red Hat OpenShift AI 3.5](/posts/openshift-ai-3-5-features/)
and
[Confidential AI on OpenShift: TEEs, GPUs, and Trustee](/posts/confidential-ai-openshift-trustee-nras/).

## What the listing actually covers

NVIDIA-Certified Hypervisors is a performance certification for a named
stack: hypervisor, host OS, device-assignment model, management layer, guest
shape, and NVIDIA software baseline.

The x86 track has two required phases. The single-node phase is full GPU and
NIC passthrough. The multi-node phase repeats that guest, one per node, and
checks the path between them.

| Phase      | Guest the suite runs                                      | What it demonstrates                                      |
| ---------- | --------------------------------------------------------- | --------------------------------------------------------- |
| Single-node | One 8-GPU VM on one Hopper SXM node                      | The guest sees the node and holds single-node GPU performance |
| Multi-node  | Two 8-GPU VMs, one per node, on two identical nodes      | Cross-node GPU communication and the RDMA data path still work |

The current certification scope for that track is GPU passthrough. The guest
uses the NVIDIA data center driver. NVIDIA's program notes say this model
does not require an NVIDIA AI Enterprise license. NVIDIA vGPU—fractional,
1:1, or several virtual GPUs per physical GPU—is called out as possible later
coverage. It is outside the listing that published today, and it does require
an NVIDIA AI Enterprise license. OpenShift and other platform subscriptions
are a separate contract.

The Arm track is a different table: a 4-GPU, 2-CPU passthrough VM on one
Grace Blackwell compute tray. OpenShift is on the Hopper SXM table. A GB200
design is a new certification when NVIDIA lists it, which matches how the
program treats a new GPU architecture.

Partners may sell other VM sizes and PCIe GPU servers. Those offerings can be
supported. They are certified only when they appear on the list. A material
change to the hypervisor stack, the guest shape, or the device-assignment
model can require a new review. Treat a future 4.23 or a Blackwell HGX row
as a new line, and read it again before you cite this one.

## What the suite measures

The useful part of the announcement is the test list. "Near bare-metal" in
the Red Hat post and in NVIDIA's program description means those tests, on
that 8-GPU guest, against NVIDIA's virtualized control-stack baseline. Your
model, batch size, and network still need their own measurement.

| Category                    | What the guest must show                                              |
| --------------------------- | --------------------------------------------------------------------- |
| Topology                    | GPU, NIC, PCIe, NVLink, NVSwitch, and NUMA relationships              |
| Collectives                 | GPU-to-GPU bandwidth inside the VM, and across nodes in the multi-node phase |
| CPU, GPU, and memory        | Bandwidth along those paths                                           |
| Compute                     | Throughput for the AI and HPC-style operations in the suite           |
| Inference                   | Throughput, latency, and time to first token on representative serving |
| RDMA                        | GPU-to-NIC locality and GPUDirect RDMA where the phase includes it    |

Topology is the one I would put on a slide. An HGX node is eight SXM GPUs
behind NVSwitch, with NICs placed for GPUDirect. NCCL and multi-GPU
inference care that the guest sees those links, and that a GPU talks to the
NIC that sits next to it. A hypervisor can boot a VM with eight GPUs and
still hide or reshuffle that map. The suite checks the map, then runs the
bandwidth and inference tests that miss their baseline when the map is wrong.

NVIDIA says no single category is end-to-end application performance. Red
Hat's footnote says the same thing in customer language: run your own proof
of concept. I would run the model you will actually serve, on the guest size
you will actually deploy, and keep the certified 8-GPU shape as the reference
point.

## Same cluster, separate GPU nodes

OpenShift Virtualization and the NVIDIA GPU Operator can both be installed
on one cluster. The operator then has to be told which kind of GPU node it
is building. The label is `nvidia.com/gpu.workload.config`. One node gets
one value.

| Label value      | What lands on the node                                      | Who can use the GPU                          |
| ---------------- | ----------------------------------------------------------- | -------------------------------------------- |
| `container`      | Data center driver, container toolkit, device plugin       | Pods requesting `nvidia.com/gpu`             |
| `vm-passthrough` | `vfio-pci` on the GPUs, sandbox device plugin              | Virtual machines, one or more whole GPUs     |
| `vm-vgpu`        | vGPU manager and mediated devices                           | Virtual machines with virtual GPUs           |

An unlabeled node follows the operator default, which is `container` unless
you change `sandboxWorkloads.defaultWorkload`. A node does not mix these.
Passthrough binds the GPU to `vfio-pci` so the guest driver owns it. A
container workload needs the data center driver on the host. Those two
bindings do not share a GPU. NVIDIA's OpenShift Virtualization guidance
also assumes the virtual-machine GPU nodes are bare metal.

That is the sentence behind "one cluster." Build two pools. Label the HGX
nodes that will host the certified-style guests `vm-passthrough`. Label the
nodes that will run
[Red Hat OpenShift AI](https://www.redhat.com/en/technologies/cloud-computing/openshift/openshift-ai)
pods `container`. Schedule with the usual node selectors. The Kubernetes API
is shared. The device is not.

vGPU is a third pool, for density when a physical GPU is larger than the
workload. It is a supported OpenShift Virtualization pattern. It is not the
pattern this certification measured. Keep it off the slide that cites the
Hopper listing.

There is a second supported way to attach a GPU to a virtual machine:
OpenShift Virtualization's own PCI passthrough, with the GPU Operator
operands kept off that node so the two stacks do not fight. Use one
approach per node. The certification does not relieve you of picking one
and writing it down.

## When the GPU stays on a virtual machine

Put the GPU on a virtual machine when the guest is the product.

- The image is an appliance, a Windows build, or an ISV stack that installs
  its own driver and CUDA, and the host must not own that stack.
- A VMware GPU virtual machine is moving in an early migration wave and the
  guest has to stay intact. The migration mechanics are the
  [Migration Toolkit for Virtualization](/posts/mtv-storage-copy-offload-vmware/)
  problem; the GPU decision is whether that guest still needs passthrough
  after it lands.
- The workload is the certified shape: one guest on a Hopper HGX node, all
  eight GPUs, NIC passthrough, NVLink and NUMA visible inside the guest.
  That is the single-node phase. Two such guests on two nodes is the
  multi-node phase.
- You want a guest operating-system boundary around a full GPU, and you can
  spend the whole device on that guest.

Carving that HGX node into 1-, 2-, or 4-GPU virtual machines leaves the
listed configuration. Full passthrough of a subset of GPUs also changes
NVLink behavior on Hopper, because the NVSwitch fabric is a property of the
board. NVIDIA documents a shared-NVSwitch model for smaller guests. Treat
that as a separate design, with its own proof of concept, and cite the 8-GPU
listing only as the reference result.

The guest still needs CPU and memory sized for the GPUs you handed it, and
the NICs that the suite required to be passed through if you care about
GPUDirect. A virt launcher pod with eight GPUs and an emulated NIC is a
different machine than the one NVIDIA ran.

## When the GPU belongs in a pod

Put the GPU on a pod when OpenShift is already the scheduler for the work.

- Model serving, evaluation, and training are container images:
  OpenShift AI 3.5, llm-d, Kueue, Ray, or a pipeline step. The day-2
  controls for that path—flow control, rollouts, queues—are in
  [What's New in Red Hat OpenShift AI 3.5](/posts/openshift-ai-3-5-features/).
  They expect a device plugin, which means a `container` node.
- Several workloads should share one physical GPU through MIG or
  time-slicing. That sharing happens under the host driver. A passthrough
  guest has the whole device until you shut the guest down.
- The platform team wants one driver lifecycle on the node, via the GPU
  Operator, and the application team ships a container that consumes
  `nvidia.com/gpu`.

Confidential computing is a pod path of a different kind. A CPU trusted
execution environment plus an NVIDIA confidential GPU, attested before
weights are released, is the design in
[Confidential AI on OpenShift: TEEs, GPUs, and Trustee](/posts/confidential-ai-openshift-trustee-nras/).
That runtime is sandboxed containers. This hypervisor listing measures
performance of a conventional passthrough guest. Attestation stays on the
Trustee design. The performance claim stays on the listing. If the
requirement is "the host cannot read the weights," use Trustee. If the
requirement is "this 8-GPU guest performs like the bare-metal Hopper node,"
use the certified passthrough shape.

## The solutions architect takeaway

Use the 21 October 2026 listing as a boundary, then pick a pool.

1. **Quote the row.** OpenShift Container Platform 4.22 with OpenShift
   Virtualization 4.22, x86 track, Hopper SXM, 8-GPU passthrough. HGX is
   that board class. Grace Blackwell is a different table.
2. **Quote the guest.** One virtual machine owns the eight GPUs and the
   NICs on a node. Two such virtual machines are the multi-node result.
   Smaller guests and vGPU are outside this result.
3. **Split the nodes.** `vm-passthrough` for those guests, `container` for
   OpenShift AI and other pods. One label per node. Bare metal for the
   virtual-machine GPU pool.
4. **Read the suite as topology plus inference, then measure your model.**
   The evidence is NVLink, NUMA, GPU-to-NIC locality, bandwidth, and
   representative time to first token. Your serving stack still gets a
   proof of concept.
5. **Keep confidential AI on its own track.** Attestation is Trustee and a
   confidential GPU. This certification is performance of a passthrough
   virtual machine.

Pair the decision with
[What's New in OpenShift Virtualization 4.22](/posts/openshift-virtualization-4-22-features/)
for the rest of the release, and with a vendor AI bill of materials only
after the GPU Operator and OpenShift versions on that bill match the row
you intend to cite. Hardware reference architectures go stale the same way
certification rows do; see
[OpenShift Hardware Vendor Reference Architectures](/posts/openshift-hardware-vendor-reference-architectures/).

## Related posts

- [What's New in OpenShift Virtualization 4.22](/posts/openshift-virtualization-4-22-features/)
- [What's New in Red Hat OpenShift AI 3.5](/posts/openshift-ai-3-5-features/)
- [Confidential AI on OpenShift: TEEs, GPUs, and Trustee](/posts/confidential-ai-openshift-trustee-nras/)
- [OpenShift Hardware Vendor Reference Architectures](/posts/openshift-hardware-vendor-reference-architectures/)

> Want help placing GPU virtual machines and OpenShift AI pods on one 4.22
> cluster? Reach out to your Red Hat account team—or confirm the Hopper HGX
> row and prove one 8-GPU passthrough guest on a non-prod bare-metal node
> first.
{: .prompt-tip }

## Further reading

- [Red Hat OpenShift Virtualization achieves NVIDIA-Certified Hypervisor status](https://www.redhat.com/en/blog/red-hat-openshift-virtualization-achieves-nvidia-certified-hypervisor-status)
- [NVIDIA-Certified Hypervisors program](https://docs.nvidia.com/certification-programs/certified-hypervisors/latest/nvidia-certified-hypervisors.html)
- [List of NVIDIA-Certified Hypervisors](https://docs.nvidia.com/certification-programs/certified-hypervisors/latest/hypervisors-list.html)
- [NVIDIA GPU Operator with OpenShift Virtualization](https://docs.nvidia.com/datacenter/cloud-native/openshift/latest/openshift-virtualization.html)
- [NVIDIA GPU architecture (OpenShift Container Platform 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/hardware_accelerators/nvidia-gpu-architecture)
- [OpenShift Virtualization 4.22](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/index)
- [OpenShift Virtualization (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/configure-the-cluster/virtualization/)

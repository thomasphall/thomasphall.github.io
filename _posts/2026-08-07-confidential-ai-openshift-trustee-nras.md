---
title: "Confidential AI on OpenShift: TEEs, GPUs, and Trustee"
description: >-
  CPU TEEs do not protect AI on GPUs. Compare TDX, SEV-SNP, and CCA, close
  the GPU gap with NVIDIA CC, and wire Trustee plus NRAS attestation on
  OpenShift.
date: 2026-08-07 14:00:00 -0500
categories: [OpenShift, Security]
tags: [openshift, security, confidential-computing, trustee]
image: /assets/img/og/confidential-ai.png
permalink: /posts/confidential-ai-openshift-trustee-nras/
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization.
{: .prompt-info }

Architecture reviews for “secure AI on OpenShift” often stop at the wrong
layer. Teams encrypt disks, lock down registries, and put models behind a
private endpoint—then assume the problem is solved. The remaining gap is
**data and weights in use**: plaintext in host memory, visible to a
compromised hypervisor, cluster admin, or opportunistic host process the
moment inference or training touches a GPU.

Confidential computing closes that gap with hardware-backed trusted execution
environments (TEEs). For AI on
[Red Hat OpenShift](https://www.redhat.com/en/technologies/cloud-computing/openshift),
the useful story is not “pick a CPU vendor and you are done.” It is a chain:

1. A **CPU TEE** (Intel TDX, AMD SEV-SNP, or ARM CCA Realms) that isolates a
   confidential VM
2. An **NVIDIA Confidential Computing GPU** that extends that isolation into
   accelerator memory
3. **Composite attestation** so secrets release only after both TEEs prove
   they are genuine and in an expected state
4. An **OpenShift sandboxed containers** path that turns that chain into a
   normal pod (`runtimeClassName: kata-cc-nvidia-gpu`)

This post is a solution-architect map of that journey. It is not a substitute
for the product install guides—those move faster than blog posts—but it is the
mental model I use when the conversation jumps from “we need confidential
computing” to “how do we run this on OpenShift?”

## Why confidential computing shows up for AI

Most platform controls protect data at rest and in transit. AI workloads spend
their interesting life **in use**: prompt and document content in guest RAM,
model weights staged for the accelerator, intermediate tensors on the GPU.
If the host or hypervisor can read that memory, encryption of the PVC and TLS
on the Route do not help.

Confidential computing reduces trust in the infrastructure operator. The
workload still needs a hardened guest OS, signed images, and sane network
policy. What changes is the claim you can make to a model owner or regulator:
*these secrets left the vault only after hardware evidence showed a measured
CPU TEE and a measured GPU TEE.*

That claim is what Red Hat build of Trustee exists to enforce, and what NVIDIA
Remote Attestation Service (NRAS) contributes on the GPU side.

## CPU TEEs: Intel TDX, AMD SEV-SNP, and ARM CCA

For whole-VM confidential computing, the apples-to-apples comparison is
**Intel Trust Domain Extensions (TDX)**, **AMD SEV-SNP** (Secure Encrypted
Virtualization with Secure Nested Paging), and **ARM Confidential Compute
Architecture (CCA)** with **Realms**. All three aim to keep guest memory and
CPU state away from a compromised host or hypervisor. They get there with
different silicon.

| | **Intel TDX** | **AMD SEV-SNP** | **ARM CCA** |
|---|---|---|---|
| Isolation unit | Trust Domain (TD) | Confidential VM | Realm |
| Architectural shape | SEAM privilege world + TDX Module | Extends AMD SVM; on-die Secure Processor | Realm Management Extension (RME) + Realm Management Monitor (RMM) |
| Memory story | Per-TD encryption + integrity metadata | Per-VM keys + Reverse Map Table (RMP) against remapping / aliasing | Per-Realm protection via Granule Protection Table (GPT) + Realm keys |
| Attestation | Intel quote / PCS (and related services) | AMD Secure Processor report / KDS / VCEK | CCA attestation of Realm state (platform-specific roots) |
| Typical SKUs | Xeon with TDX (e.g. Emerald / Granite Rapids class) | EPYC with SNP (Milan / Genoa / Turin class) | Armv9 / Neoverse designs that implement RME |

**Same job, different trust boundary implementation.** TDX creates a distinct
trust-domain execution model above the hypervisor. SEV-SNP hardens the
existing VM model so the hypervisor cannot usefully remap or forge guest
physical memory. CCA introduces a **Realm** world—isolated from both Normal
World and TrustZone’s Secure World—managed by the RMM. None of these remove
the need to trust the CPU vendor’s attestation PKI. None replace guest
hardening.

**Do not confuse CCA with TrustZone.** TrustZone is the older Secure World
model common on phones and edge devices. It is useful, but it is not the
VM-class confidential computing story. CCA Realms are the ARM analogue to TDX
Trust Domains and SEV-SNP confidential VMs.

**Practical fleet rule for OpenShift confidential containers:** pick the TEE
that matches the servers you already buy, and keep worker nodes
**homogeneous**—all TDX, all SEV-SNP, or all CCA—for a given confidential GPU
pool. Mixing TEE types in one worker set fights the operators and the mental
model.

**Maturity note for architecture reviews:** TDX and SEV-SNP are the production
CPU TEEs behind today’s OpenShift sandboxed containers + NVIDIA confidential
GPU path. CCA silicon is shipping into Armv9 / Neoverse platforms, but
Realm-based confidential containers and the confidential GPU composition on
OpenShift are still catching up versus x86. Treat ARM CCA as the right
mental model for ARM fleets—and confirm current product support before you
promise the same GA path you get on TDX or SNP.

Intel SGX still exists as a process/enclave model. For lift-and-shift AI pods
on OpenShift, the path that matters is VM-class TEEs (TDX / SNP today; CCA
Realms as that ecosystem lands), not rewriting the inference stack into SGX
enclaves.

## The GPU gap: CPU TEEs are not enough

Here is the failure mode that kills half-finished confidential AI designs:

```text
  ┌─────────────────────────────────────────────┐
  │ Confidential VM (TDX / SNP / CCA Realm)     │
  │  guest RAM encrypted / isolated from host   │
  │                                             │
  │   app ──copy──▶ GPU memory  ✗ still host-   │
  │                 (weights, prompts)  visible │
  └─────────────────────────────────────────────┘
```

A CPU TEE protects the guest. The moment weights and prompts land in GPU
memory without a GPU TEE, you re-expanded the trust boundary to include the
accelerator path the host can still observe.

**NVIDIA Confidential Computing** closes that gap on Hopper and Blackwell class
GPUs (H100 / H200 / B200 and related CC-capable SKUs). The GPU runs in
confidential computing mode (or Protected PCIe / PPCIE on multi-GPU HGX
topologies), and the device is passed into the confidential VM—typically via
VFIO—so the guest owns the accelerator inside the TEE boundary.

```text
  ┌──────────────────────────────────────────────┐
  │ Confidential VM (TDX / SNP / CCA Realm)      │
  │                                              │
  │  guest RAM  ◄──isolated──►  NVIDIA GPU (CC)  │
  │  CPU TEE                  GPU TEE            │
  └──────────────────────────────────────────────┘
           ▲                         ▲
           │                         │
      CPU evidence              GPU evidence
           └──────────┬──────────────┘
                      ▼
              composite attestation
           (Trustee + NRAS) before secrets
```

CPU vendor still matters for the **CPU** side of that diagram. For the **GPU**
side, the confidential accelerator story is NVIDIA’s CC stack hosted inside
whichever CPU TEE you run. You are not choosing “Intel GPU crypto versus AMD
GPU crypto versus ARM GPU crypto.” You are choosing which CPU TEE your
bare-metal fleet provides underneath NVIDIA’s confidential GPU path—and today
that OpenShift path is documented primarily for TDX and SEV-SNP.

## Composite attestation: Trustee + NRAS

Isolation without attestation is theater. The model owner needs a remote party
to say: *this guest is on real TEE hardware, running the measured software you
expected, with a genuine confidential GPU,* before decryption keys or private
registry credentials appear inside the pod.

On OpenShift, that remote party is Red Hat build of Trustee (documented as
part of
[OpenShift sandboxed containers](https://docs.redhat.com/en/documentation/openshift_sandboxed_containers/)),
the productized form of the upstream Confidential Containers Trustee project,
wired for NVIDIA GPUs through [NRAS](https://docs.nvidia.com/attestation/).

Trustee is composed of three cooperating pieces:

| Component | Role |
|---|---|
| **KBS** (Key Broker Service) | HTTP front door: auth, challenge, resource release |
| **AS** (Attestation Service) | Verifies evidence, builds an EAR attestation token |
| **RVPS** | Holds known-good **CPU** reference values for policy |

With `nvidia_verifier.type = "Remote"`, GPU evidence is delegated to NRAS.
NRAS checks GPU measurements against NVIDIA reference integrity, so your RVPS
stays focused on CPU/guest reference values (often generated with tools such
as `veritas` from the sandboxed containers tooling images).

### Sequence (mental model)

```text
 Workload pod (guest)
   │
   │  1. KBC → KBS /auth  (session + challenge)
   │  2. Collect CPU TEE evidence (TDX or SNP)     [primary]
   │  3. Collect NVIDIA GPU TEE evidence           [additional]
   │  4. KBC → KBS /attest  (composite evidence)
   │
 Trustee
   │  5. AS: built-in TDX/SNP verifier + RVPS      → cpu0 claims
   │  6. AS: NRAS remote GPU verifier              → gpu0 claims
   │  7. OPA attestation policies → EAR token
   │       submods: cpu0, gpu0  (AR4SI trustworthiness)
   │  8. KBC requests resource with session cookie
   │  9. OPA resource policy: release only if
   │       cpu0 and gpu0 are affirming
   ▼
 Secret / key / registry cred returned into the TEE
```

**Composite** is the important word. A passing CPU quote with a failed or
missing GPU attestation must not unlock the model. Default Restricted-profile
resource policy on Trustee is aimed at that outcome: both submods affirm, or
nothing leaves the broker.

NRAS implies outbound HTTPS from the Trustee deployment to NVIDIA’s cloud
attestation endpoints, plus the appropriate NVIDIA licensing agreement for
remote verification. Local GPU verification modes exist in the upstream stack;
the OpenShift “remote verifier” path is the one that matches most
production-shaped docs today.

## How you do this on OpenShift

The OpenShift shape is
[OpenShift sandboxed containers](https://docs.redhat.com/en/documentation/openshift_sandboxed_containers/)
with confidential containers on bare metal, plus the NVIDIA GPU Operator and
Trustee. Each confidential pod becomes a Kata confidential VM (CVM) with an
optional cold-plugged confidential GPU.

As of the sandboxed containers 1.13 / Trustee 1.2 timeframe, confidential
containers with confidential GPU accelerators on bare metal reached general
availability (GA). Treat exact OpenShift minor versions and operator channels
as something you confirm in the current compatibility matrix—plan on a current
4.21+ class cluster for the confidential GPU path described in Red Hat’s
recent guidance.

### Operator stack

```text
 Workload cluster (TEE bare-metal workers)
┌────────────────────────────────────────────────────────────┐
│  NFD          → labels TEE + GPU features                  │
│  NVIDIA GPU   → CC manager, VFIO, kata sandbox plugin      │
│  Sandboxed    → Kata / QEMU, runtime classes               │
│   Containers                                               │
│                                                            │
│  Pod → runtimeClassName: kata-cc-nvidia-gpu                │
│        └─ CVM (TDX|SNP|CCA) + nvidia.com/pgpu              │
└───────────────────────────┬────────────────────────────────┘
                            │ attest
                            ▼
 Trusted side (separate cluster preferred)
┌────────────────────────────────────────────────────────────┐
│  Red Hat build of Trustee  (KBS + AS + RVPS)               │
│       │                                                    │
│       ├─▶ NRAS (GPU)                                       │
│       └─▶ optional HashiCorp Vault (secret backend)        │
└────────────────────────────────────────────────────────────┘
```

Prefer Trustee on a **trusted** cluster (or at least a tightly controlled
failure domain). The workload cluster can be treated as hostile
infrastructure that only receives secrets after attestation.

### Deploy order that keeps you out of trouble

1. **BIOS / firmware** — UEFI; enable TDX *or* SEV-SNP; Secure Boot as required;
   platform options for confidential GPU / CC mode per OEM and NVIDIA guidance.
2. **Trustee** — install Red Hat build of Trustee; create a `TrusteeConfig`
   with a **Restricted** profile so KBS is HTTPS-facing, policies are strict,
   and the NVIDIA verifier is remote (`NRAS`). For TDX, apply any MachineConfig
   prerequisites the guide requires before installing Trustee.
3. **Reference values** — populate RVPS CPU reference values for your measured
   guest stack / initdata (tooling such as `veritas` with `--tee tdx|snp --gpu`).
4. **Workload operators** — NFD, NVIDIA GPU Operator, OpenShift sandboxed
   containers Operator.
5. **IOMMU** — MachineConfig so workers can passthrough GPUs:

```yaml
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: worker
  name: 100-iommu-kernel-args
spec:
  kernelArguments:
    - amd_iommu=on
    - intel_iommu=on
```

6. **NVIDIA `ClusterPolicy`** — confidential sandbox shape, not a normal
   host-driver GPU node:
   - `ccManager` enabled, default mode `on`
   - host `driver.enabled: false` (driver lives in the guest)
   - `sandboxWorkloads` enabled, mode `kata`, default `vm-passthrough`
   - `vfioManager` enabled
   - `kataSandboxDevicePlugin` enabled (alias `pgpu`)
7. **Label reality check** before you create `KataConfig`. Confidential GPU
   workers need the Kata/GPU/CC labels plus exactly one TEE label family, for
   example:
   - `nvidia.com/cc.mode.state: "on"`
   - `nvidia.com/cc.ready.state: "true"`
   - `intel.feature.node.kubernetes.io/tdx: "true"` **or**
     `amd.feature.node.kubernetes.io/snp: "true"`
8. **`KataConfig`** — install the confidential runtime classes (node reboot is
   expected). With node eligibility checks on, `kata-cc-nvidia-gpu` appears
   when TEE + confidential GPU labels exist.
9. **Initdata** — gzip+base64 TOML that points the guest attestation agent /
   CDH at your Trustee URL and TLS material, and carries a **restrictive**
   Kata agent policy. Attach it as
   `io.katacontainers.config.hypervisor.cc_init_data`. Initdata is measured;
   changing it changes attestation.
10. **Secrets in Trustee (or Vault behind KBS)** — model unwrap keys, registry
    pull secrets, etc., addressed as KBS resources
    (`repo` / `type` / `id`).
11. **Workload** — opt in with the confidential GPU runtime class:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: confidential-llm
  annotations:
    io.katacontainers.config.hypervisor.default_memory: "32768"
    io.katacontainers.config.hypervisor.cc_init_data: "<base64-gzip-initdata>"
spec:
  runtimeClassName: kata-cc-nvidia-gpu
  containers:
    - name: inference
      image: registry.example.com/my-llm:1.0
      resources:
        limits:
          nvidia.com/pgpu: "1"
          memory: 32Gi
```

Inside the guest, after attestation, the Confidential Data Hub path looks like
`http://127.0.0.1:8006/cdh/resource/<repo>/<type>/<id>`. Sealed secrets that
point at `kbs:///` URIs are the Kubernetes-shaped way to mount the same gated
material. Prefer **signed images** and initdata image policy so supply chain
integrity is part of the measured story, not an afterthought—the same
gate habit as
[platform and supply-chain security](/posts/openshift-security-platform-supply-chain/),
applied inside the TEE.

> Current practical constraint to say out loud in design reviews: confidential
> GPU pods often start at **one** cold-plugged confidential GPU per pod.
> Multi-GPU / PPCIE topologies are evolving (including newer DGX / Blackwell
> paths)—confirm what your sandboxed containers version actually supports
> before promising eight-way confidential training in the same pod.
{: .prompt-warning }

## Design choices I recommend

| Decision | Recommendation |
|---|---|
| Trustee placement | Separate trusted cluster; Restricted `TrusteeConfig` |
| Secret storage | HashiCorp Vault as KBS resource backend |
| TEE homogeneity | All TDX, all SNP, or all CCA workers in the confidential GPU pool (x86 TEEs for the GA NVIDIA CC path today) |
| Images | Signed; policy enforced via initdata |
| Starting topology | Single confidential GPU inference / eval first |
| GitOps | Cluster repo for MachineConfig / operators / `KataConfig`; app (or trusted) repo for TrusteeConfig, RVPS values, workloads |

That last row maps cleanly onto the usual OpenShift GitOps split: cluster
configuration gets the platform to “TEE + CC GPU ready,” application
configuration deploys only after attestation wiring exists. A PoC GitOps
install is in
[OpenShift GitOps (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/post-installation/openshift-gitops/);
the IOMMU MachineConfig pattern matches
[Machine Config (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/operations/machine-config/).
Vault behind KBS
is for attestation-gated release into the confidential guest; delivery of
ordinary app Secrets on OpenShift remains a separate choice—see
[External Secrets Operator vs Secrets Store CSI](/posts/external-secrets-vs-secrets-store-csi/).

## What this is not

- **Not invulnerability.** TEEs shrink the TCB; they do not remove bugs in your
  model server, prompt injection, or a bad RBAC story on the API in front of
  inference.
- **Not “skip guest hardening.”** SELinux, patches, least privilege, and
  network policy still matter inside the CVM.
- **Not vendor-PKI free.** CPU attestation and NRAS both depend on vendor
  services and trust roots you must accept operationally.
- **Not a reason to paste every CR from a blog into production.** Use the
  current
  [OpenShift sandboxed containers](https://docs.redhat.com/en/documentation/openshift_sandboxed_containers/)
  and
  [NVIDIA confidential containers](https://docs.nvidia.com/datacenter/cloud-native/confidential-containers/latest/overview.html)
  documentation for the install you actually run.

## Closing

Confidential AI on OpenShift is a **composition** problem:

**CPU TEE (TDX, SEV-SNP, or CCA Realms) + NVIDIA CC GPU + Trustee/NRAS attestation + sandboxed containers runtime class.**

Intel, AMD, and ARM are the CPU chapter—TDX, SEV-SNP, and CCA Realms
respectively, with TDX/SNP leading the current OpenShift confidential GPU
path. NVIDIA is the GPU chapter. Trustee is the gate that refuses to hand over
the model key until both chapters check out. If your design stops after
enabling a CPU TEE, you protected the wrong half of the workload.

## Related posts

- [Supply-Chain Security for Regulated Hybrid Cloud](/posts/openshift-security-platform-supply-chain/)
- [External Secrets vs Secrets Store CSI on OpenShift](/posts/external-secrets-vs-secrets-store-csi/)
- [RHACS for OpenShift Virtualization Workloads](/posts/acs-openshift-virtualization/)

## Further reading

- [OpenShift sandboxed containers documentation](https://docs.redhat.com/en/documentation/openshift_sandboxed_containers/)
- [Protect data offloaded to GPU-accelerated environments with OpenShift sandboxed containers](https://developers.redhat.com/articles/2026/05/22/protect-data-offloaded-gpu-accelerated-environments-openshift-sandboxed) (Red Hat Developer)
- [An overview of confidential containers on OpenShift bare metal](https://developers.redhat.com/articles/2026/06/04/overview-confidential-containers-openshift-bare-metal) (Red Hat Developer)
- [NVIDIA Confidential Containers architecture](https://docs.nvidia.com/datacenter/cloud-native/confidential-containers/latest/overview.html)
- [NVIDIA attestation / NRAS documentation](https://docs.nvidia.com/attestation/)
- [ARM Confidential Compute Architecture](https://www.arm.com/architecture/security-features/arm-confidential-compute-architecture)
- [Upstream Trustee NVIDIA verifier notes](https://github.com/confidential-containers/trustee/blob/main/deps/verifier/src/nvidia/README.md)
- [OpenShift GitOps (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/post-installation/openshift-gitops/)
- [Machine Config (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/operations/machine-config/)
- [External Secrets Operator (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/post-installation/external-secrets-operator/)

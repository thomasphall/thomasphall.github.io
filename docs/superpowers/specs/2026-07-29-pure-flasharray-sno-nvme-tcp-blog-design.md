# Design: Pure FlashArray on SNO with NVMe/TCP + LVMS Blog

**Date:** 2026-07-29  
**Target repo:** `thomasphall/thomasphall.github.io`  
**Theme:** Jekyll Chirpy  
**Status:** Design approved in conversation; awaiting user review of this spec before implementation plan

## Goal

Publish a practical, sequential lab guide (~2,500–3,500 words) so OpenShift admins and platform engineers can attach a Pure Storage FlashArray volume to Single Node OpenShift (SNO) over NVMe/TCP, persist the connection across reboots with a MachineConfig (Ignition + systemd oneshot), and consume the discovered NVMe namespace with OpenShift Data Foundation LVM Storage (LVMS / TopoLVM) via an `LVMCluster` that selects a stable `/dev/disk/by-id/...` path.

## Audience & voice

- Primary: OpenShift admins / platform engineers comfortable with `oc` and RHCOS; may be new to NVMe/TCP and Pure host connectivity
- First-person practitioner tone (“I ran into…”, “here’s what worked”)
- Red Hat / OpenShift focused; assume OpenShift (not generic Kubernetes)
- Concise, scannable, command-heavy
- Chirpy personal-site disclaimer prompt used on other posts
- No marketing fluff; no unsubstantiated Pure or Red Hat partner claims

## Source material

- User architecture brief (SNO → Pure NVMe/TCP → MachineConfig → LVMS)
- Pure Storage Linux / NVMe-TCP quickstart patterns (host NQN, portal IPs, `nvme connect` / `nvme connect-all`, port 4420)
- Purity//FA host + volume + network service configuration (GUI primary; CLI equivalents such as `purehost`, `purevol`, `purenetwork eth`)
- OpenShift 4.22 docs for Machine Config Operator and LVM / local storage (`LVMCluster`, `deviceSelector.paths`, `forceWipeDevicesAndDestroyAllData`)
- Existing site posts for voice and Chirpy front matter:
  - `_posts/2026-07-28-openshift-from-windows-client.md`
  - `_posts/2026-07-27-openshift-virtualization-networking.md`

## Approach

**Single sequential lab guide** (selected over architecture-first expandable deep dives and split Pure/OpenShift halves): one ordered path from Pure array setup through reboot-persistent connect to LVMS PVC smoke test.

## Deliverable

| Item        | Value |
| ----------- | ----- |
| Path        | `_posts/2026-07-29-pure-flasharray-sno-nvme-tcp.md` |
| Title       | Installing Pure Storage FlashArray on Single-Node OpenShift with NVMe over TCP |
| Description | Connect a Pure FlashArray volume to SNO over NVMe/TCP, persist it with MachineConfig, and consume it with LVMS using a stable by-id path. |
| Categories  | `[OpenShift]` |
| Tags        | `[openshift, sno, pure-storage, nvme-tcp, lvms]` |
| Permalink   | `/posts/pure-flasharray-sno-nvme-tcp/` |
| Timezone    | America/Chicago (`-0500`) |
| Docs links  | OpenShift Container Platform 4.22 |
| Delivery    | Feature branch + PR into `main` |

## Content outline

1. **Introduction** — Why NVMe/TCP + Pure on SNO matters for lab/edge/demo durability after reboot; personal disclaimer.
2. **Architecture overview** — Pure FlashArray ↔ NVMe/TCP ↔ RHCOS/SNO ↔ MachineConfig/systemd ↔ LVMS StorageClass. Short diagram (mermaid or ASCII). Explicitly not Portworx / Pure CSI.
3. **Prerequisites** — OpenShift SNO; cluster-admin; network reachability to Pure data IPs on TCP 4420; pull secret / catalog access as needed for LVMS operator.
4. **Pure FlashArray setup (full walkthrough)** — Enable NVMe/TCP service on data Ethernet interfaces; read RHCOS host NQN (`/etc/nvme/hostnqn` or `nvme show-hostnqn`); create host and configure NQN; create volume and connect to host; capture `<PURE_DATA_IP>` list, `<SUBSYSTEM_NQN>`, volume name. GUI steps with CLI equivalents. Sanitized placeholders only.
5. **Manual validation first** — Load `nvme-tcp`; one-time `nvme discover` / `nvme connect` (or `connect-all`); confirm with `nvme list` and `nvme list-subsys`; record stable by-id path. Contrast one-time vs reboot-persistent.
6. **Persist with MachineConfig** — Files and unit:
   - `/etc/modules-load.d/nvme-tcp.conf`
   - `/etc/nvme/nvme-tcp.env` with `NVME_ADDRS` (portal IPs), `NVME_NQN` (**subsystem** NQN, not host NQN), `NVME_PORT` (default 4420)
   - `/usr/local/sbin/nvme-tcp-connect.sh`
   - `nvme-tcp-connect.service` (oneshot; After/Wants `network-online.target`)
   - Ignition `contents.source` data URLs (base64 or percent-encoded); **do not use `inline`** (MCO RenderDegraded risk)
   - Sanitized YAML excerpts; encoding notes so readers can regenerate `source` values
7. **Apply and wait for MCP** — `oc apply`; watch `mcp/master` until UPDATED.
8. **Verify after reboot** — systemd unit status; `nvme list`; by-id symlinks.
9. **Install/configure LVMS** — namespace, OperatorGroup, Subscription; `LVMCluster` with `deviceSelector.paths` pointing at unused Pure NVMe by-id path (not OS disk). Mention `forceWipeDevicesAndDestroyAllData` only as intentional destructive option for leftover signatures.
10. **Validate storage** — Brief PVC + pod smoke test.
11. **Troubleshooting** — RenderDegraded / `inline` vs `source`; connect timing vs `network-online`; wrong device selected; multiple data IPs / multipath awareness for SNO labs.
12. **Cleanup / safety** — Wipe warnings; never point LVMS at the OS disk.
13. **Conclusion + references** — Pure NVMe/TCP docs; OpenShift 4.22 LVMS / local storage docs; NVMe-TCP basics.

## Must get right

- Distinguish one-time manual connect vs reboot-persistent MachineConfig
- Ignition `contents.source` only — never `inline`
- Env vars: `NVME_ADDRS` (comma-separated portal IPs), `NVME_NQN` (subsystem NQN), `NVME_PORT`
- Systemd oneshot After/Wants `network-online.target`; script under `/usr/local/sbin/`
- Explain why by-id paths matter for LVMS (device names can reshuffle; by-id is stable)
- LVMS targets one unused Pure NVMe namespace, not the OS disk
- `forceWipeDevicesAndDestroyAllData` framed as destructive and intentional only
- YAML valid and copy-paste friendly with placeholders clearly marked
- Never include real IPs, NQNs, hostnames, pull secrets, tokens, or customer names

## Placeholders (required)

| Placeholder | Meaning |
| ----------- | ------- |
| `<PURE_DATA_IP>` / comma-separated list | FlashArray NVMe/TCP portal / data interface IPs |
| `<SUBSYSTEM_NQN>` | NVMe subsystem NQN from discover/connect |
| `<HOST_NQN>` | RHCOS host NQN registered on Pure |
| `<sno-node>` | SNO node name |
| `<VOLUME>` | Pure volume name fragment in by-id symlink |
| `/dev/disk/by-id/nvme-Pure_Storage_FlashArray_<VOLUME>` | Stable device path for `LVMCluster` |

## Constraints

- Length ~2,500–3,500 words (command/YAML blocks allowed; keep prose tight)
- Chirpy front matter + personal disclaimer
- Link OpenShift 4.22 docs; verify exact LVMS URL at write time (`persistent-storage-using-local-storage` pattern on recent 4.x docs)
- Pure array steps must stay within well-documented FlashArray host/volume/NVMe-TCP practices; do not invent product features
- Markdown only for the post; no theme/config changes
- Design/plan docs live under `docs/superpowers/` and need not ship on the site

## Out of scope

- Portworx / Pure CSI driver install and `px-pure-secret`
- Full production multipath hardening for multi-node worker fleets
- Fibre Channel or iSCSI paths
- Full OpenShift Data Foundation Ceph stack (this post is LVMS only)
- Real customer lab values or unsanitized screenshots in the committed post

## Author checklist (manual assets)

- Architecture diagram (Pure ↔ NVMe/TCP ↔ SNO ↔ MachineConfig ↔ LVMS)
- Sanitized Pure host NQN / volume connect screenshot (optional)
- `nvme list` / `nvme list-subsys` after manual connect
- MachineConfigPool `master` UPDATED
- `ls -l /dev/disk/by-id/nvme-Pure*` (or equivalent) after reboot
- PVC Bound + pod using the LVMS StorageClass

## Success criteria

- A cluster-admin can reproduce the outcome from the post alone
- Reader clearly sees manual connect vs MachineConfig persistence
- by-id rationale for LVMS is explicit
- Safety notes prevent wiping or selecting the OS disk
- Tone matches existing practitioner posts on this site

## Publish path

1. Create feature branch from `main` (for example `feature/pure-flasharray-sno-nvme-tcp-blog`)
2. Add Chirpy-compatible post under `_posts/`
3. Commit with a clear message
4. Push branch and open PR to `main` with `gh`
5. After merge, confirm GitHub Pages picks up  
   `https://thomasphall.github.io/posts/pure-flasharray-sno-nvme-tcp/`

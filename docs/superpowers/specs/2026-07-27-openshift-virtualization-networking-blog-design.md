# Design: OpenShift Virtualization Networking Blog

**Date:** 2026-07-27  
**Target repo:** `thomasphall/thomasphall.github.io`  
**Theme:** Jekyll Chirpy  
**Status:** Decisions agreed in conversation (audience, depth, version, YAML, layered structure); content outline below for review before implementation plan

## Goal

Publish a solution-architect brief (~1,800–2,200 words) that turns the *OpenShift Virtualization for VMware Admins – 202 Networking (July 2026)* deck into a layered OpenShift 4.22 mental model: how VMs attach to networks, which topology to pick, and field YAML for host bridges plus Cluster User Defined Networks (CUDN) localnets.

## Audience & voice

- Mixed SA audience: OpenShift platform / networking engineers **and** VMware-leaning virtualization teams
- Red Hat Staff Solution Architect / OpenShift specialist tone
- Customer-facing, practical, confident — no hype
- VMware analogies only where they clarify (e.g. port groups ≈ localnet VLANs / CUDN-generated NADs)
- Same Chirpy SA voice as existing posts, including the personal-site disclaimer

## Source material

- Local PPTX: `Copy of OpenShift Virtualization for VMware Admins - 202 Networking - July 2026.pptx`
- OpenShift 4.22 docs for multiple networks, OVN-Kubernetes, NMState, and OpenShift Virtualization networking
- Existing site posts for voice and Chirpy front matter patterns:
  - `_posts/2026-07-22-openshift-virtualization-4-22-features.md`
  - `_posts/2026-07-23-openshift-virtualization-hardening-priorities.md`
  - `_posts/2026-07-27-hosted-vs-virtualized-control-planes.md`

## Approach

**Layered mental model** (selected over decision-first and scenario-first): climb the stack CNI/Multus → pod/masquerade default → User-Defined Networks → host/localnet architectures → CUDN VLAN attach path with YAML → Linux bridge only when required → when-to-choose table.

**Version stance:** OpenShift 4.22 as current. Recommend CUDN/localnet as the modern path; note hand-authored NetworkAttachmentDefinitions as the older/compatibility path briefly.

**YAML density:** Field-guide YAML — dual-bond NNCP patterns and a complete localnet CUDN attach path (closer to the deck than illustrative-only snippets).

## Deliverable

| Item | Value |
| ---- | ----- |
| Path | `_posts/2026-07-27-openshift-virtualization-networking.md` |
| Title | OpenShift Virtualization Networking: From Pod Network to Localnet |
| Description | A layered OpenShift 4.22 mental model for OpenShift Virtualization networking—pod network, User-Defined Networks, host architectures, and CUDN localnets—with field YAML for platform teams. |
| Categories | `[OpenShift, Virtualization, Networking]` |
| Tags | `[openshift-virtualization, networking, udn, localnet, ovn-kubernetes, "4.22"]` |
| Permalink | `/posts/openshift-virtualization-networking/` |
| Timezone | America/Chicago (`-0500`) |
| Delivery | Feature branch + PR into `main` |

## Content outline

1. **Hook** — VMs on OpenShift share the same networking plane as pods, but live migration, persistent IPs, and datacenter VLANs change the design questions. This post is a layered mental model, not a full CNI catalog.
2. **Foundation (short)** — CNI + Multus for secondary networks; OVN-Kubernetes as the default CNI story for OpenShift Virtualization.
3. **Default pod / cluster network** — Primary network, default route, per-node `/23` from `clusterNetwork`; VM masquerades as virt-launcher pod IP; guest often sees `10.0.2.2/24`; pod IP changes on live migration. When this is enough (Services/Routes) vs when it is not.
4. **User-Defined Networks** — Tenant-friendly overlays via `UserDefinedNetwork` / `ClusterUserDefinedNetwork`; topologies and roles (Layer2 primary/secondary, Layer3, localnet secondary); persistent IPAM for VMs; isolation / overlapping subnets value. Primary Layer2 UDN for tenant isolation; localnet for provider VLANs.
5. **Host networking for localnet** — `br-ex`, NMState (`NodeNetworkConfigurationPolicy`), bridge mappings (`physicalNetworkName` → OVS bridge). Three architectures: native single bond/NIC, tagged single bond (typical POC), dual bond with dedicated `br-vmdata`.
6. **Field YAML path (4.22 modern)** — NNCP for bond + `br-vmdata` + OVN bridge mapping; CUDN localnet per VLAN with namespaceSelector; controller-generated NADs (do not hand-author); VM attach via Multus + bridge binding. Brief note: pre-CUDN NAD-per-namespace pattern remains for understanding/compatibility.
7. **Linux bridge — only when required** — Prefer OVS/CUDN path; Linux bridge when VLAN guest tagging (802.1q to guest) or similar needs force it; call out lost UDN/overlay simplicity.
8. **When-to-choose table** — Pod network vs primary UDN vs secondary localnet vs Linux bridge; SA takeaway + soft CTA / docs links.
9. **Out of scope** — Full microsegmentation / MultiNetworkPolicy deep dive (deck teaser only); unsupported multi-NAD same-segment workarounds; partner CNIs beyond a one-line mention.

## Must-cover technical points

1. Masquerade on default pod network and migration IP behavior
2. UDN topologies/roles relevant to VMs (especially Layer2 primary and localnet secondary)
3. CUDN as modern VLAN management; auto-generated NADs
4. Bridge mapping + at least dual-bond NNCP field YAML
5. Complete VM attach example for localnet CUDN
6. Linux bridge as exception path for VGT / similar

## Constraints

- Length ~1,800–2,200 words (YAML blocks count toward readability; keep prose tight)
- Chirpy front matter + personal disclaimer prompt
- Link to official OpenShift 4.22 docs; do not paste unsupported workaround content from deck temp slides
- Do not commit the PPTX or `.tmp-pptx-extract*` into the site repo
- Cross-link related posts where natural (4.22 features, hardening networking notes)

## Success criteria

- A mixed SA reader can explain pod vs UDN vs localnet after one read
- A platform engineer can copy the dual-bond + CUDN path as a starting point
- Version story is clear: 4.22 / CUDN-first, NAD-as-legacy note only
- Tone matches existing OpenShift Virtualization posts on this site

# Blog Proofread + Cross-Links Design

Date: 2026-08-07  
Status: Approved approach (light pass + inline/related links)

## Goal

Proofread all posts under `_posts/` with a light editorial pass, and add bidirectional-friendly cross-references between related posts using both inline links and a short Related posts section.

## Scope

In scope:

- All 13 markdown posts in `_posts/`
- Typos, grammar, awkward phrasing, inconsistent capitalization/hyphenation
- Existing permalink-style internal links (`/posts/.../`)
- New inline “see also” links where the topic already appears
- A `## Related posts` section on each post that has meaningful peers

Out of scope:

- Rewriting voice, structure, or SA takeaways
- Changing technical claims, YAML, or external doc URLs unless clearly wrong
- New posts, tags taxonomy cleanup, or site chrome changes
- Forcing links on weakly related posts (especially Windows client)

## Editorial rules (light pass)

1. Prefer the author’s existing SA tone and cadence.
2. Fix clear errors; do not “improve” correct but informal phrasing.
3. Normalize internal link titles to match the target post’s `title` front matter when adding new links.
4. Keep existing cross-links; add only gaps from the map below.
5. Do not invent Related posts that are only loosely thematic.

## Cross-link format

**Inline:** 1–3 natural links woven into existing paragraphs (or one short “see also” sentence) where the related topic is already discussed.

**Related posts:** Place `## Related posts` before the closing tip / wrap-up / references block, with 2–4 bullets:

```markdown
## Related posts

- [Title of related post](/posts/permalink-slug/)
```

If a post already has a References / Further reading section, Related posts comes immediately before that section (or before the tip callout if that is the true end).

## Related-posts map

| Post permalink | Related to |
| -------------- | ---------- |
| `/posts/openshift-security-platform-supply-chain/` | ACS virt, External Secrets vs SSCSI, Virt hardening, Confidential AI |
| `/posts/openshift-virtualization-4-22-features/` | Networking, Hardening, Hosted vs VCP |
| `/posts/openshift-virtualization-hardening-priorities/` | Security platform, ACS virt, Networking, 4.22 |
| `/posts/hosted-vs-virtualized-control-planes/` | 4.22 features, Edge, PoC memory |
| `/posts/openshift-virtualization-networking/` | 4.22, Hardening, MTV offload |
| `/posts/openshift-from-windows-client/` | None required (standalone); Related section optional/omitted |
| `/posts/pure-flasharray-sno-nvme-tcp/` | Dell Unity iSCSI, Edge |
| `/posts/openshift-virt-dell-unity-iscsi/` | Pure FlashArray, Edge, MTV offload |
| `/posts/mtv-storage-copy-offload-vmware/` | Dell Unity, Networking, 4.22 |
| `/posts/poc-faster-bare-metal-boot-disable-memory-check/` | Edge, Hosted vs VCP |
| `/posts/external-secrets-vs-secrets-store-csi/` | Security platform, Confidential AI |
| `/posts/acs-openshift-virtualization/` | Security platform, Hardening, Confidential AI |
| `/posts/openshift-edge-architectures/` | Pure, Dell, Hosted vs VCP, PoC memory |
| `/posts/confidential-ai-openshift-trustee-nras/` | Security platform, External Secrets, ACS virt |

Exact titles must match each post’s front-matter `title`.

## Success criteria

- Every in-scope post is grammar/typo clean under a light pass
- Related clusters from the map have mutual or near-mutual discoverability (inline and/or Related section)
- Windows client post is proofread; no forced Related section
- No content/YAML/architecture changes beyond editorial clarity

## Non-goals

- Medium/heavy rewrites
- Design-system or layout changes
- Automated link checkers beyond manual verification of permalinks

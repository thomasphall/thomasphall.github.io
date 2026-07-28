# Design: OpenShift from a Windows Client Blog

**Date:** 2026-07-28  
**Target repo:** `thomasphall/thomasphall.github.io`  
**Theme:** Jekyll Chirpy  
**Status:** Approved in conversation; awaiting final review before implementation plan

## Goal

Publish a practical PowerShell-first guide (~1,200–1,600 words) so Windows users—app developers and platform/ops—can install the OpenShift CLI (`oc`), put it on PATH, log into a cluster, and use everyday day-1/day-2 CLI patterns without requiring WSL.

## Audience & voice

- Primary: Windows workstation users who need a shared setup story for developers and platform engineers
- Red Hat Staff Solution Architect / OpenShift specialist tone
- Customer-facing, practical, confident — no hype
- Emphasize durable workstation habits (persistent PATH, token login, kubeconfig/contexts) over exhaustive CLI reference

## Source material

- [CLI tools / OpenShift CLI (oc) — Installing on Windows](https://docs.redhat.com/en/documentation/openshift_container_platform/4.19/html/cli_tools/openshift-cli-oc) (align to latest stable OCP docs at write time)
- Cluster web console: **?** → Command Line Tools (version-matched client)
- Red Hat Customer Portal / mirror.openshift.com Windows client archives where console access is unavailable
- Existing site posts for voice and Chirpy front matter patterns:
  - `_posts/2026-07-22-openshift-virtualization-4-22-features.md`
  - `_posts/2026-07-27-hosted-vs-virtualized-control-planes.md`

## Approach

**Sequential setup guide** (selected over checklist+deep-dives and problem-first FAQ): walk from zero to useful workstation—download → PATH → verify → login → kubeconfig → everyday commands → kubectl coexistence → completion/contexts → Windows gotchas.

## Deliverable

| Item        | Value |
| ----------- | ----- |
| Path        | `_posts/2026-07-28-openshift-from-windows-client.md` |
| Title       | Interacting with OpenShift from a Windows Client |
| Description | Install the OpenShift CLI on Windows, put `oc` on your PATH, log in with PowerShell, and handle kubeconfig, contexts, and common Windows gotchas. |
| Categories  | `[OpenShift]` |
| Tags        | `[oc, windows, powershell, kubeconfig, cli]` |
| Permalink   | `/posts/openshift-from-windows-client/` |
| Timezone    | America/Chicago (`-0500`) |

## Content outline

1. **Hook** — A full OpenShift CLI workflow works from Windows; PowerShell is enough. Goal: workstation ready in one sitting.
2. **Get `oc`** — Prefer cluster console **?** → Command Line Tools (version-matched). Alternate: Customer Portal or mirror for the Windows client. Unzip to a stable folder such as `C:\Tools\OpenShift\`.
3. **PATH** — Persist User or Machine PATH via System Properties or PowerShell (`[Environment]::SetEnvironmentVariable`). New terminals pick it up; verify with `Get-Command oc` and `oc version`.
4. **Login** — `oc login` with the API URL; token from the console as the practical Windows default; note `--insecure-skip-tls-verify` only for lab. Document kubeconfig at `%USERPROFILE%\.kube\config`.
5. **Everyday commands** — Short set: `whoami`, `projects`/`project`, `get pods`, `logs`, `apply -f`, `rsh`/`exec`, `explain`.
6. **`kubectl` coexistence** — `oc` speaks Kubernetes; when to keep both; shared kubeconfig; avoid PATH version skew between clients.
7. **Contexts & completion** — `oc config get-contexts` / `use-context`; PowerShell tab completion via `oc completion powershell` (profile snippet).
8. **Windows gotchas** — Corporate proxy (`HTTPS_PROXY`), custom CA / TLS failures, antivirus locking `oc.exe`, YAML line endings, avoiding unnecessary elevated shells.
9. **Close** — Link official CLI docs; soft CTA; personal-site disclaimer.

## Must get right

- Prefer version-matched client from the cluster console when possible
- PATH guidance that survives new PowerShell sessions (persistent environment variable, not only session `$env:Path`)
- Token login as the practical Windows default; password/`oc login` still mentioned
- Accurate kubeconfig location and context switching
- Gotchas framed as checks, not scare tactics
- PowerShell examples throughout; WSL is out of scope as a required path

## Constraints

- Length ~1,200–1,600 words
- Accurate to current OpenShift Container Platform CLI documentation; do not invent flags or GA claims
- Include personal-site disclaimer prompt used on other posts
- No secrets, credentials, or customer-identifying detail
- Markdown only; no theme/config changes
- PowerShell-first; no WSL deep dive, CRC install guide, IDE plugins, or Ansible-from-Windows
- Design/plan docs live under `docs/superpowers/` and need not ship on the site

## Publish path

1. Create feature branch from `main` (for example `feature/openshift-windows-client-blog`)
2. Add Chirpy-compatible post under `_posts/`
3. Commit with a clear message
4. Push branch and open PR to `main` with `gh`
5. After merge, confirm GitHub Pages / Actions pick up the post at  
   `https://thomasphall.github.io/posts/openshift-from-windows-client/`

## Out of scope

- WSL2 / Linux toolchain as the primary path
- CodeReady Containers / local cluster install walkthrough
- VS Code / OpenShift Toolkit deep dive
- `odo` or full Developer Console tutorials
- Exhaustive `oc` command reference
- Corporate SSO / OIDC identity-provider deep dive beyond “use token from console”

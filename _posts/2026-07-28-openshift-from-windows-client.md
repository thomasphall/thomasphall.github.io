---
title: "Interacting with OpenShift from a Windows Client"
description: >-
  Install the OpenShift CLI on Windows, put oc on your PATH, log in with
  PowerShell, and handle kubeconfig, contexts, and common Windows gotchas.
date: 2026-07-28 08:00:00 -0500
categories: [OpenShift]
tags: [oc, windows, powershell, kubeconfig, cli]
permalink: /posts/openshift-from-windows-client/
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization.
{: .prompt-info }

You do not need WSL to run a useful OpenShift workflow from a Windows laptop.
PowerShell, the [OpenShift CLI (`oc`)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/cli_tools/openshift-cli-oc),
and a kubeconfig are enough for developers and platform engineers who share the
same workstation habits. The console remains excellent for discovery; the CLI is
what you want for repeatable apply, logs, and scripting. This post is a
sequential setup guide: get the binary, put it on PATH, log in, use the everyday
commands, then tidy up contexts, completion, and the Windows-specific traps that
usually burn the first hour.

## Get a version-matched `oc`

Prefer the client that matches the cluster you will use. In the OpenShift web
console, open **?** → **Command Line Tools**, download **oc for Windows**
(x86_64), and save the ZIP. That path is documented under
[installing the OpenShift CLI on Windows using the web console](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/cli_tools/openshift-cli-oc#cli-installing-cli-windows_cli-developer-commands)
and keeps you aligned with the cluster's API surface.

If you do not have console access yet, use the
[Red Hat Customer Portal downloads](https://console.redhat.com/openshift/downloads)
(or the public mirror for non-subscription labs) and pick the **Windows Client**
for your OpenShift version. Unzip somewhere durable and boring—for example
`C:\Tools\OpenShift\`—so upgrades are a file replace, not a scavenger hunt
through Downloads.

```powershell
New-Item -ItemType Directory -Force -Path C:\Tools\OpenShift | Out-Null
Expand-Archive -Path $env:USERPROFILE\Downloads\openshift-client-windows.zip `
  -DestinationPath C:\Tools\OpenShift -Force
Get-ChildItem C:\Tools\OpenShift\oc.exe
```

Adjust the ZIP name to whatever the console or portal gave you. You want
`oc.exe` visible in that folder before you touch PATH.

## Put `oc` on PATH (and make it stick)

A session-only `$env:Path += ...` dies when you close the window. Persist the
directory on your **User** PATH (or Machine PATH if you manage shared
workstations):

```powershell
$ocDir = 'C:\Tools\OpenShift'
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($userPath -notlike "*$ocDir*") {
  [Environment]::SetEnvironmentVariable(
    'Path',
    ($userPath.TrimEnd(';') + ';' + $ocDir),
    'User'
  )
}
# Refresh this session without logging out
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
  [Environment]::GetEnvironmentVariable('Path', 'User')

Get-Command oc
oc version
```

`Get-Command oc` should resolve to your `C:\Tools\OpenShift\oc.exe`. `oc version`
prints client details; after you log in it can also show server version. Open a
**new** PowerShell window once to confirm the permanent PATH took effect without
the refresh trick.

You can do the same through **Settings → System → About → Advanced system
settings → Environment Variables** if you prefer the GUI. The goal is the same:
new terminals find `oc` without ceremony.

## Log in from PowerShell

Grab the API URL from the console (**Copy login command** under your username,
or the cluster's documented `https://api.<cluster>:6443`). On Windows, the
token path is usually the least painful—especially with SSO identity providers
that do not love interactive password prompts in a terminal.

```powershell
# Prefer the command the console builds for you (includes server + token)
oc login --token=<token> --server=https://api.example.com:6443

# Or interactive username/password when your IdP allows it
oc login https://api.example.com:6443 -u <username>
```

Use `--insecure-skip-tls-verify` only in throwaway labs. For real environments,
fix trust: corporate root CAs belong in the Windows certificate store or in a
kubeconfig CA bundle—not as a permanent CLI flag. Newer clients also support
browser-assisted login with `oc login <cluster_url> --web` when that fits your
environment; token copy-from-console remains the most reliable default on locked
down corporate laptops.

A successful login writes credentials into your kubeconfig, typically:

`%USERPROFILE%\.kube\config`

Confirm identity and project:

```powershell
oc whoami
oc whoami --show-server
oc project
```

## Everyday commands worth memorizing

Once you are authenticated, the day-1 loop is small:

```powershell
oc whoami
oc projects
oc project <project-name>
oc get pods
oc logs <pod-name>
oc apply -f .\manifest.yaml
oc rsh <pod-name>          # or: oc exec -it <pod-name> -- /bin/sh
oc explain deployment.spec
```

`oc explain` is underrated on a new cluster: it is offline API documentation for
the resources you are about to apply. Keep manifests in UTF-8 and prefer LF line
endings when you share YAML with Linux pipelines; Windows CRLF usually works
with `oc apply`, but mixed tooling is where subtle diffs appear.

## `kubectl` coexistence

`oc` understands Kubernetes objects and OpenShift types (Routes, Projects,
Builds, and friends). Many teams also keep `kubectl` for scripts, IDE plugins,
or muscle memory. That is fine if both clients point at the **same** kubeconfig
and you avoid stacking mismatched major versions on PATH.

```powershell
Get-Command oc, kubectl | Format-Table Name, Source
oc config view --minify
```

If `kubectl` and `oc` disagree about the current context, check
`KUBECONFIG` and which binary Windows resolves first. One kubeconfig, explicit
contexts, and predictable PATH order beat parallel “mystery” configs in
Documents, OneDrive, and a random Downloads folder.

## Contexts and PowerShell completion

Multiple clusters belong in one kubeconfig as contexts—not as a pile of renamed
files you swap by hand:

```powershell
oc config get-contexts
oc config use-context <context-name>
oc config current-context
```

Tab completion saves real time. Load it for the current session:

```powershell
oc completion powershell | Out-String | Invoke-Expression
```

To persist it, append a guarded snippet to your PowerShell profile
(`$PROFILE`):

```powershell
if (-not (Test-Path $PROFILE)) {
  New-Item -ItemType File -Path $PROFILE -Force | Out-Null
}
Add-Content $PROFILE @'

if (Get-Command oc -ErrorAction SilentlyContinue) {
  oc completion powershell | Out-String | Invoke-Expression
}
'@
```

Reload the profile or open a new shell. Official examples live under
`oc completion` in the
[CLI tools documentation](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/cli_tools/openshift-cli-oc).

## Windows gotchas worth checking first

- **Corporate proxy.** If HTTPS breaks only on the corporate network, set
  `HTTPS_PROXY` / `HTTP_PROXY` (and `NO_PROXY` for cluster API and service CIDRs
  you must reach directly). Persist them the same way you persisted PATH.
- **TLS and custom CAs.** “x509: certificate signed by unknown authority” is
  usually a missing enterprise root, not a bad `oc` binary. Install the CA for
  the Current User or Local Machine store, or embed the correct
  `certificate-authority-data` in the kubeconfig cluster entry.
- **Antivirus / Controlled Folder Access.** Some endpoint agents quarantine or
  lock newly dropped `oc.exe` files. If `Get-Command` works but execution fails
  oddly, check quarantine logs before reinstalling.
- **Elevated shells.** You do not need “Run as administrator” for normal `oc`
  usage. Elevating changes the profile and sometimes the effective PATH—then
  “it works in one window and not the other.”
- **Roaming profiles and OneDrive.** If `%USERPROFILE%\.kube` is flaky on
  managed desktops, keep kubeconfig under a synced Documents path and set a
  persistent `KUBECONFIG` to that file. Treat the file as a secret: never commit
  it.

## Wrap-up

A solid Windows OpenShift workstation is boring on purpose: a version-matched
`oc.exe` on a persistent PATH, token login from the console, one kubeconfig with
named contexts, and PowerShell completion so you stop fat-fingering resource
names. Spend the setup minutes once; reclaim them every time you switch
clusters. From there, the same CLI discipline you use on Linux applies—
projects, apply, logs, explain—without pretending Windows is a second-class
client.

For the full command reference and install variants, start with the OpenShift
4.22
[CLI tools](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/cli_tools/openshift-cli-oc)
guide and keep the client you downloaded from *your* cluster’s Command Line
Tools page.

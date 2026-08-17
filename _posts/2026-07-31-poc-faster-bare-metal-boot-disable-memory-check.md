---
title: "Faster Bare-Metal Boots in OpenShift PoCs"
description: >-
  Cut POST wait time on Dell, HPE, Cisco, and Lenovo servers during
  OpenShift bare-metal PoC redeploys, then turn memory checks back on
  before handback.
date: 2026-07-31 12:50:00 -0500
categories: [OpenShift, Bare Metal]
tags: [openshift, bare-metal, ansible]
permalink: /posts/poc-faster-bare-metal-boot-disable-memory-check/
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization.
{: .prompt-info }

> **PoC only.** Disabling firmware memory tests hides failing DIMMs. Use this
> for short-lived labs, demos, and partner Proof of Concepts—not production
> clusters, regulated environments, or hardware you have not validated.
{: .prompt-danger }

OpenShift bare-metal PoCs punish you twice: once while the installer waits on
POST, and again every time you wipe a node and retry. On dense memory servers,
software memory tests during UEFI/POST can add minutes per reboot. Across a
multi-node rack and a week of agent-install / Metal3 / MachineConfig loops,
that tax becomes the loudest part of the engagement.

This post is a field runbook for **temporary** OpenShift PoCs: what “memory
checking” usually means, when it is acceptable to turn it off, vendor steps to
disable and re-enable it on Dell, HPE, Cisco, and Lenovo, and a handback
checklist before you return the gear or promote anything toward production.

## Why PoC boot time hurts more than production

In production you reboot rarely and you want every hardware safety net. In a
PoC you reboot constantly:

- [Assisted Installer](https://openshift-ssa.github.io/openshift-poc/installation/assisted-installer/) / [Agent-based Installer](https://openshift-ssa.github.io/openshift-poc/installation/agent-based/) discovery boots
- Ironic / Metal3 inspection and provisioning cycles
- “Break the [MachineConfig](https://openshift-ssa.github.io/openshift-poc/operations/machine-config/) → reboot → watch the node come back” debugging
- Day-2 operator installs that bounce workers
- Full cluster wipe and rebuild between customer scenarios

Saving even five to fifteen minutes per cold boot compounds quickly. A
six-node PoC that reboots twice a day for five days is sixty POST cycles. Cut
ten minutes each and you reclaim ten hours—more than a full workday—of
waiting.

## What “memory checking” means during POST

Vendors name it differently, but the idea is the same: during power-on or
warm reset, firmware spends time validating DIMMs before handing control to
the boot device (PXE, ISO, disk, or virtual media).

Common categories:

| Category                         | What it does                                         | PoC impact                          |
| -------------------------------- | ---------------------------------------------------- | ----------------------------------- |
| Software memory test             | BIOS/UEFI walks or patterns system RAM               | Often the big win to disable        |
| Extended / enhanced memory test  | Deeper DIMM validation; maps out bad ranks           | Can add large, memory-size-scaled wait |
| Chipset MBIST / hardware BIST    | Built-in self-test from the memory controller        | May still run even if software test is off |
| Memory fast training / quick POST| Shorter training path on subsequent boots            | Complementary; verify per generation |

Dell documents that **System Memory Testing** is a *software* BIOS test and is
distinct from chipset MBIST, which can still run every boot. Expect “faster,”
not “instant.”

## Tradeoffs for PoCs

| Keep checks enabled                         | Disable for the PoC window                          |
| ------------------------------------------- | --------------------------------------------------- |
| Unknown or freshly racked loaner hardware   | Known-good lab gear with recent successful burn-in  |
| Customer wants prod-like validation         | Iteration speed is the engagement bottleneck        |
| You already saw ECC / IML / SEL memory events | No memory faults in BMC/OS logs so far            |
| Hardware will become the production cluster | Pure throwaway demo nodes                           |

If correctable or uncorrectable memory errors appear after you disable tests,
**re-enable immediately** and stop treating the node as healthy PoC inventory.

## When to disable in a PoC

Disable (or confirm already disabled) when all of these are true:

1. The cluster is explicitly a PoC, lab, or demo.
2. Nodes will be wiped or returned at the end of the engagement.
3. You accept the risk of a latent DIMM fault showing up as random crashes
   instead of a clean POST failure.
4. You have a teardown step on the calendar to restore vendor defaults.

Keep checks on (or run one full test first) when:

- The servers are production candidates the customer will keep
- DIMMs were just reseated, upgraded, or moved between systems
- The customer’s success criteria include hardware validation
- You are in a regulated or air-gapped demo where unexplained instability
  is worse than a slow boot

## Vendor runbooks

Menu labels and Redfish attribute names drift by generation. Treat the names
below as the common ones; confirm on *your* firmware before you script a rack.

### Dell PowerEdge (iDRAC / System BIOS)

**Setting:** System Memory Testing  
**Attribute (common):** `BIOS.MemSettings.MemTest`  
**Values:** `Enabled` / `Disabled`  
**Generations:** Widely present on 14G/15G/16G-class PowerEdge with iDRAC9;
verify with `racadm get BIOS.MemSettings.MemTest`.

#### Console

1. Reboot and enter System Setup (`F2`), or open **iDRAC → Configuration → BIOS Settings**.
2. Open **Memory Settings**.
3. Set **System Memory Testing** to **Disabled**.
4. Save and reboot.

#### RACADM (disable for PoC)

```bash
racadm -r <idrac-host> -u <user> -p <password> \
  set BIOS.MemSettings.MemTest Disabled

racadm -r <idrac-host> -u <user> -p <password> \
  jobqueue create BIOS.Setup.1-1 -r pwrcycle -s TIME_NOW
```

#### RACADM (re-enable before handback)

```bash
racadm -r <idrac-host> -u <user> -p <password> \
  set BIOS.MemSettings.MemTest Enabled

racadm -r <idrac-host> -u <user> -p <password> \
  jobqueue create BIOS.Setup.1-1 -r pwrcycle -s TIME_NOW
```

> Dell’s software memory test is separate from chipset MBIST. Disabling
> `MemTest` shortens POST; it does not remove every hardware self-test.
{: .prompt-tip }

### HPE ProLiant (iLO / UEFI System Utilities)

**Setting:** Extended Memory Test  
**Redfish attribute (common):** `ExtendedMemTest`  
**Values:** `Enabled` / `Disabled`  
**Generations:** Documented on Gen10/Gen10 Plus ProLiant with iLO 5 and
Gen11 ProLiant with iLO 6; confirm with a GET of `/redfish/v1/systems/1/bios`.

HPE’s own description: when enabled, the system validates memory during
initialization, can map out failed DIMMs to the IML, and **can significantly
increase boot time**. For PoCs, ensure it is **Disabled** (many images already
default that way—verify; do not assume).

Related options worth checking on your generation (names vary):

- **Memory Fast Training** — shorter training on warm boots
- Boot-time optimization / POST options in System Utilities

#### Console

1. Enter **UEFI System Utilities** during POST (often `F9`), or use the iLO
   remote console.
2. Open **System Configuration → BIOS/Platform Configuration** (path varies).
3. Find **Extended Memory Test** and set it to **Disabled**.
4. Save and reboot.

#### Redfish (disable for PoC)

```bash
curl -k -u "<user>:<password>" -X PATCH \
  "https://<ilo-host>/redfish/v1/systems/1/bios/settings/" \
  -H "Content-Type: application/json" \
  -d '{"Attributes":{"ExtendedMemTest":"Disabled"}}'
```

Then reset the server so pending BIOS settings apply (iLO virtual power /
Redfish `Reset` action).

#### Redfish (re-enable before handback)

```bash
curl -k -u "<user>:<password>" -X PATCH \
  "https://<ilo-host>/redfish/v1/systems/1/bios/settings/" \
  -H "Content-Type: application/json" \
  -d '{"Attributes":{"ExtendedMemTest":"Enabled"}}'
```

Reset again after the PATCH.

### Cisco UCS (CIMC / UCS Manager / Intersight)

**Setting:** Enhanced Memory Test (older docs: Advanced Memory Test)  
**CIMC token (common):** `AdvancedMemTest`  
**Values:** `Disabled` / `Enabled` / `Auto` (platform default is often `Auto`)  
**Scope note:** Cisco documents that enhanced testing applies to certain DIMM
vendors/populations; always confirm on the exact C-Series or B-Series model.

Cisco’s guidance in UCS Manager docs: enhanced memory tests during boot
**increase boot time based on memory size**. For PoCs, set the policy to
**Disabled** unless you intentionally want validation on first rack-up.

#### UCS Manager / Intersight BIOS policy

1. Create or edit a **BIOS policy** used only by the PoC service profile /
   server profile.
2. Under memory-related tokens, set **Enhanced Memory Test** to **Disabled**.
3. Associate the policy and reboot the server(s) so the CIMC buffer applies.

Keep a second policy (or the customer’s baseline) with the original value for
handback.

#### CIMC CLI sketch (standalone C-Series)

Exact subcommand paths vary by IMC release. Pattern:

```text
scope bios
scope advanced
set AdvancedMemTest Disabled
commit
```

Reboot the server after commit. To restore:

```text
set AdvancedMemTest Auto
commit
```

(or `Enabled` if that was the pre-PoC value—capture it before you change
anything).

### Lenovo ThinkSystem (XClarity / UEFI) — common in partner labs

**Setting:** Memory Test  
**OneCLI examples (Intel-class, common):**  
`Memory.MemoryTest` and `IMM.UEFIMemoryTest`  
**Values:** Enable/Disable variants; defaults are often **Enabled**

#### Console

1. Enter UEFI Setup (`F1` on many ThinkSystem models).
2. Open **System Settings → Memory** (label varies slightly by CPU family).
3. Set **Memory Test** to **Disabled**.
4. Save and reboot.

#### OneCLI (disable for PoC)

```bash
OneCli config set Memory.MemoryTest Disable \
  --bmc <user>:<password>@<xcc-host>

OneCli config set IMM.UEFIMemoryTest Disabled --override \
  --bmc <user>:<password>@<xcc-host>
```

Restart the system for the change to take effect. On XCC firmware older than
`d8e130f-2.60`, use `IMM.UEFIMemoryTestOptions` instead of `IMM.UEFIMemoryTest`
(some AMD EPYC platforms, such as SR645/SR665, use this path too); check
Lenovo’s OneCLI memory-test topic for your exact firmware stream.

#### OneCLI (re-enable before handback)

```bash
OneCli config set Memory.MemoryTest Enable \
  --bmc <user>:<password>@<xcc-host>

OneCli config set IMM.UEFIMemoryTest Repair --override \
  --bmc <user>:<password>@<xcc-host>
```

(Use the restore values that match what you captured at engagement start;
Lenovo’s “enable advanced test” flow is more nuanced than a single boolean.)

### Supermicro and other lab vendors

Supermicro and whitebox boards often expose **Memory Testing**, **Quick Boot**,
or vendor-specific POST options under **Advanced → Chipset / Memory**. There
is less uniformity than Dell/HPE/Cisco. For PoCs:

1. Photograph or export the BIOS page before changes.
2. Prefer **Quick Boot / skip memory test** style options when present.
3. Do not script a rack until you have confirmed the Redfish/IPMI attribute
   on one golden node.

## Automating a multi-node PoC rack

For more than a couple of nodes, do this once from a jump host with Ansible
and Redfish rather than walking consoles. Keep credentials out of git; use
environment variables or a local vault file that never leaves the laptop.

Example pattern with `community.general.redfish_command` / raw URI calls
(attribute names differ by vendor—parameterize them):

```yaml
# poc-bios-memory-test.yaml
---
- name: Set BIOS memory test for OpenShift PoC nodes
  hosts: bmc
  gather_facts: false
  vars:
    # dell_memtest | hpe_extended | cisco_enhanced — choose per inventory group
    redfish_base: "https://{{ inventory_hostname }}"
  tasks:
    - name: Stage HPE ExtendedMemTest Disabled
      when: vendor == "hpe"
      uri:
        url: "{{ redfish_base }}/redfish/v1/systems/1/bios/settings/"
        method: PATCH
        user: "{{ bmc_user }}"
        password: "{{ bmc_password }}"
        force_basic_auth: true
        validate_certs: false
        headers:
          Content-Type: application/json
        body_format: json
        body:
          Attributes:
            ExtendedMemTest: Disabled
        status_code: [200, 204]

    - name: Create Dell BIOS job for MemTest Disabled
      when: vendor == "dell"
      # Prefer dellemc.openmanage or racadm; sketch shown for clarity
      ansible.builtin.command:
        argv:
          - racadm
          - -r
          - "{{ inventory_hostname }}"
          - -u
          - "{{ bmc_user }}"
          - -p
          - "{{ bmc_password }}"
          - set
          - BIOS.MemSettings.MemTest
          - Disabled
```

Run Ansible from a project-local venv:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install ansible
ansible-galaxy collection install community.general dellemc.openmanage
ansible-playbook -i inventory.yaml poc-bios-memory-test.yaml
```

After staging BIOS settings, reboot the nodes once *before* you start the
OpenShift install so the first discovery boot already benefits.

## Validation during the PoC

After the change, confirm three things:

1. **Setting stuck:** re-read the attribute (`racadm get`, Redfish GET, UCS
   policy view). Pending vs current values are a common footgun.
2. **POST is actually shorter:** time chassis power-on to PXE/agent start on
   one node before and after.
3. **No new memory faults:** watch iDRAC LifeCycle / HPE IML / UCS SEL, and
   on booted nodes check `dmesg` / EDAC / MCE messages.

If a node starts crashing, dumping MCE, or logging uncorrectable ECC:

1. Remove it from the PoC schedulable set.
2. Re-enable the vendor memory test.
3. Run the vendor diagnostics or replace DIMMs before trusting it again.

## PoC teardown and handback

Put this on the engagement checklist next to “delete cluster” and “revoke
pull secrets”:

1. Restore **System Memory Testing** / **Extended Memory Test** / **Enhanced
   Memory Test** / **Memory Test** to the pre-PoC value (capture it on day
   one).
2. Reboot once and confirm the restored value is active, not merely pending.
3. Optionally run one vendor full memory diagnostic on loaner gear before
   shipping it back.
4. If the customer is keeping the hardware as a production seed, leave checks
   **enabled** and do not hand over a “PoC-tuned” BIOS as the baseline.

## Recommended PoC policy

| Situation                                      | Policy                                              |
| ---------------------------------------------- | --------------------------------------------------- |
| Red Hat / partner lab kit, known-good history  | Disable software/extended tests for the PoC window  |
| Customer loaners, unknown DIMM health          | One full test on day one, then disable if clean     |
| Prod-candidate hardware                        | Leave enabled; accept the boot tax                  |
| Any memory error during the engagement         | Re-enable immediately; quarantine the node          |
| Engagement end                                 | Restore prior BIOS values before handback           |

## Wrap-up

Firmware memory tests are the right default for servers that matter. They are
the wrong default for a throwaway OpenShift PoC where you will reboot the
same six nodes until the demo story works. Disable the vendor software or
extended memory test on Dell, HPE, Cisco, and Lenovo to reclaim POST time;
keep a restore path; and never confuse “PoC fast” with “production ready.”

This pairs well with
[edge form-factor](/posts/openshift-edge-architectures/) and
[hosted vs virtualized control plane](/posts/hosted-vs-virtualized-control-planes/)
labs that lean on Agent-based Installer, Metal3, and Redfish-heavy reboot
loops—use the PoC BIOS tweak for the engagement window, then restore before
you call the gear production-ready. For the rest of a bare-metal OpenShift PoC
(prerequisites through install), start at the
[OpenShift PoC overview](https://openshift-ssa.github.io/openshift-poc/home/).

## Related posts

- [OpenShift Edge Architectures: Form Factor, Then Fleet](/posts/openshift-edge-architectures/)
- [Hosted vs Virtualized Control Planes on OpenShift 4.22](/posts/hosted-vs-virtualized-control-planes/)

### References

Confirm against your exact generation before publishing changes to a shared
lab image:

- Dell iDRAC / RACADM — `BIOS.MemSettings.MemTest` (System Memory Testing)
- Dell PowerEdge BIOS setup guides — System Memory Testing vs MBIST notes
- HPE iLO Redfish BIOS attribute — `ExtendedMemTest` (Extended Memory Test)
- HPE UEFI System Utilities — Boot Time Optimizations / Extended Memory Test
- Cisco UCS Manager / Intersight — Enhanced Memory Test / `AdvancedMemTest`
- Lenovo OneCLI — `Memory.MemoryTest` / `IMM.UEFIMemoryTest`
- OpenShift bare metal / Agent-based Installer docs for your cluster version
- [OpenShift PoC overview](https://openshift-ssa.github.io/openshift-poc/home/)
- [Assisted Installer (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/installation/assisted-installer/)
- [Agent-Based Installer (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/installation/agent-based/)
- [Machine Config (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/operations/machine-config/)

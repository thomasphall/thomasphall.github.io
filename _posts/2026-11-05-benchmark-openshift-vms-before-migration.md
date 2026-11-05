---
title: "Benchmark OpenShift VMs Before the First Migration Wave"
description: >-
  Build a repeatable FIO acceptance test for OpenShift Virtualization.
  Compare VMware baselines, latency, throughput, and concurrent VM load before migration.
date: 2026-11-05 00:00:00 -0600
categories: [OpenShift, Virtualization]
tags: [openshift, openshift-virtualization, storage, migration, vmware]
permalink: /posts/benchmark-openshift-vms-before-migration/
social_title: |-
  Benchmark VMs
  before you migrate
social_label: OpenShift Virtualization
social_subtitle: FIO · Latency · Concurrent VM load
---

> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization.
{: .prompt-info }

A virtual machine boots on the destination cluster. A quick disk test
produces a large number. The migration team puts a green check beside
storage performance.

The useful question comes later: can the application meet its response
time and batch deadlines while the other migrated VMs are busy?

Before the first production wave, agree on the workload, the conditions,
and the evidence that will count as a pass. Then measure the source and
destination against that agreement. **A migration benchmark should give
the application owner a reason to accept the destination.**

Elvir Kuric's
[Red Hat Developer walkthrough](https://developers.redhat.com/articles/2026/11/03/how-run-io-workloads-openshift-virtualization-vms),
updated on November 3, 2026, provides a containerized harness for running
the Flexible I/O Tester (`fio`) across Linux VMs on Red Hat OpenShift
Virtualization. It coordinates execution and collects results across
guests. That is a useful foundation for a repeatable test campaign.

The decisions around those runs matter just as much as the command.
Start with one representative guest, establish a comparison with VMware
vSphere, and then add the concurrency the migration wave will bring.

## Define acceptance before running FIO

Ask the application owner what becomes unacceptable when storage is slow.
An interactive application might have a transaction response-time limit.
A reporting service might need its overnight job finished before 06:00.
A file service might have a sustained transfer requirement. Record the
business condition first, then choose storage tests that help investigate it.

Write down these items before collecting results:

- **The workload:** block sizes, read/write mix, access pattern, working
  set, and expected busy periods. Use application telemetry where it is
  available.
- **The required service:** transaction latency, batch duration, or
  transfer rate, with an owner who can accept the result.
- **The test conditions:** VM size, number of active guests, background
  work, and any maintenance condition included in the approval.
- **The failure conditions:** I/O errors, missed application deadlines,
  or storage latency beyond an agreed limit at the required load.

For example, a team might require an order transaction to remain below
500 milliseconds at the 95th percentile during a representative busy
hour. That is an illustrative application target, not an OpenShift
requirement. An 8 KiB FIO operation cannot stand in for that transaction.
The storage test helps determine whether the destination has enough
capacity and where a slowdown starts.

Keep the source measurement too. If the existing platform already misses
the business target, merely matching its performance will not close the
acceptance question.

## Make the source and destination comparable

Use disposable Linux test VMs with dedicated test disks on both platforms.
Match the guest operating system, FIO version, vCPU count, memory,
filesystem, test-file size, and workload parameters. Preserve the
configuration and record the differences you cannot remove.

There are two useful comparisons. Holding the storage backend constant
can help investigate differences in the virtualization path. Testing the
actual source datastore against the planned destination storage answers
the migration question. If both the hypervisor and storage change,
describe the result as a comparison of the two complete environments.

On OpenShift, record the `StorageClass`, persistent volume claim (PVC)
access mode and volume mode, storage driver version, VM disk configuration,
and worker placement. On vSphere, retain the datastore and storage policy,
virtual controller, and host placement. Include the backend's protection,
compression, deduplication, and provisioning settings in the run notes.

A PVC with `volumeMode: Block` can still hold a disk that the guest formats
with XFS. Record both layers. The guest filesystem is part of the path the
application will use.

The
[storage architecture guide](/posts/openshift-storage-performance/)
covers the underlying design choices. This measurement is specifically
about a VM's workload disk. Keep control-plane storage validation as a
separate check.

## Start with a small set of workload profiles

Choose profiles that expose different constraints:

- **Small random I/O at low queue depth:** explore latency when there
  are few outstanding requests.
- **A representative mixed workload:** use the application's observed
  block size and read/write ratio, then increase concurrency in steps.
- **Large sequential reads and writes:** investigate throughput for
  workloads such as scans and file transfers.
- **A separate synchronous-write test:** investigate workloads whose
  progress depends on durable commits, using the application's actual
  flush behavior as the reference.

Keep the profile names and settings fixed across environments. Changing
block size, queue depth, and VM count at once makes a regression difficult
to explain.

For each profile, decide whether the goal is latency at a required load
or the maximum load the configuration can sustain. Run those as distinct
experiments. A saturation run is useful for finding a limit; the
application still needs acceptable latency at its expected demand.

## Run one guest test you can explain

This example uses one job, an 8 KiB random workload, and a 70 percent read
mix. These are starting values for a lab, not a database workload model
or a recommended setting for every VM.

Use a disposable Linux VM with FIO installed and its dedicated test
filesystem already mounted at `/mnt/fio`. The example writes a 16 GiB
file named `fio-acceptance.bin`; reserve additional filesystem free space.
Confirm that this mount is the intended test disk and that the file can
be overwritten. Run from a fresh working directory for each measurement
so earlier results remain intact.

First, populate the file. Run the following in Bash inside the guest:

```bash
set -euo pipefail

mountpoint -q /mnt/fio || {
  printf '%s\n' 'Mount the disposable test filesystem at /mnt/fio first.' >&2
  exit 1
}
findmnt --mountpoint /mnt/fio
df -h /mnt/fio
mkdir -p fio-results
fio --version > fio-results/fio-version.txt

fio --name=prepare \
  --filename=/mnt/fio/fio-acceptance.bin \
  --size=16G --rw=write --bs=1M \
  --ioengine=libaio --direct=1 --iodepth=16 --numjobs=1 \
  --refill_buffers=1 --end_fsync=1 \
  --output-format=json --output=fio-results/prepare.json
```

Writing the entire file establishes a populated working set before the
read test. It does not establish steady-state behavior for every storage
system. Choose a working set and test duration that exercise the cache
and sustained-load conditions relevant to the application; 16 GiB and a
few minutes may be much too small.

Save this as `vm-storage.fio` in the same working directory:

```ini
[global]
filename=/mnt/fio/fio-acceptance.bin
size=16G
allow_file_create=0
ioengine=libaio
direct=1
iodepth=8
numjobs=1
time_based=1
runtime=300
ramp_time=30
refill_buffers=1
group_reporting=1
lat_percentiles=1
clat_percentiles=1
percentile_list=95:99:99.9

[mixed-8k]
rw=randrw
rwmixread=70
bs=8k
```

Check the job syntax, then run it:

```bash
fio --parse-only vm-storage.fio
fio --output-format=json+ \
  --output=fio-results/mixed-8k.json vm-storage.fio
```

The [FIO manual](https://fio.readthedocs.io/en/latest/fio_doc.html)
defines these options. The 30-second ramp precedes 300 seconds of
measurement. `direct=1` bypasses the Linux guest's page cache; it does not
remove storage-system caches or impose synchronous commit semantics.
`lat_percentiles=1` includes submission and completion time. Inspect
the achieved queue-depth distribution as well as the requested depth.

This job runs as fast as its concurrency permits. For acceptance at a
specific offered load, create a separate rate-limited profile and keep
that rate fixed across platforms. Preserve the saturation profile so
you can also see how much room remains before latency rises.

Repeat each case at least three times as an initial check for variability.
Retain every run. If the measurements drift or differ substantially,
investigate the conditions and extend the experiment before choosing a
representative result.

## Coordinate the tests across VMs

Once the single-guest profile makes sense, use the
[fio-container harness](https://github.com/ekuric/ioscale/blob/main/io-generic/fio-container/fio_README-container.md)
to coordinate a larger campaign. It supports pre-created guests and
automatic provisioning. Its plain SSH mode also supports Linux guests
on vSphere, which gives the source and destination a common orchestration
approach.

Pin the harness revision or container digest and record the resolved
FIO job parameters. Translate the acceptance profile deliberately;
running a harness with different defaults creates a different test.
Keep the guest FIO version fixed too.

The harness's filesystem mode formats the selected data devices, and
raw mode writes directly to them. Use an isolated test namespace and
disposable guests. Inspect the host and device mapping with the documented
`--dry-run --verbose` invocation before executing a campaign. Its
`USE_TESTDIR` mode targets the guest OS disk, so that mode answers a
different question when the application's data lives on another disk.

Keep the per-VM result files, the effective configuration, and the run
log together. A combined summary is useful, but retain enough detail to
find the one guest that missed the target.

## Add the load the migration wave will bring

Increase the number of simultaneously active test VMs in controlled
steps. For example, start with one, then four, then eight if those counts
fit the planned estate. Record where the guests land; eight VMs on one
worker exercise a different condition from eight spread across several
workers.

At each step, compare every VM's latency and achieved throughput with
the baseline. Watch guest CPU and memory pressure, worker load, network
utilization, and backend storage telemetry over the same timestamps.
The
[VM observability post](/posts/what-replaces-vrealize-operations/)
describes the distinction between platform visibility and what still
needs measurement inside the guest.

Then introduce expected background work one condition at a time: a
backup, an image import, or another application's batch window. If
maintenance performance is part of acceptance, test a supported live
migration in the lab while the representative workload runs. Use the
[VM upgrade and evacuation checks](/posts/upgrading-openshift-while-vms-stay-running/)
to establish eligibility and spare capacity first.

An idle-cluster result applies to an idle cluster. Keep normal-load,
background-load, and maintenance results separate so the application
owner can see which operating conditions were accepted.

## Read latency and throughput together

For each VM and profile, retain achieved I/O operations per second
(IOPS), throughput, read and write latency percentiles, error status,
and the measurement window. Check units before comparing exports.

IOPS only becomes comparable when the operation size and workload are
specified. At 8 KiB per operation, 12,000 IOPS represents about
93.75 MiB/s of payload. That arithmetic says nothing about whether the
application's slowest requests are acceptable.

Keep read and write latency separate. A mixed workload can have healthy
reads while writes miss the agreed limit. Check the slowest guest too;
a cluster total can increase while one application gets worse.

Do not average p99 values across VMs or runs and label the result a
fleet p99. Compare individual distributions, or combine compatible
histograms with the appropriate sample counts. Preserve the underlying
results so the calculation can be reviewed.

Choose the result that meets the required demand within the latency
budget. If a higher queue depth raises IOPS while pushing latency past
that budget, the extra IOPS do not satisfy acceptance. Record the first
load level that fails and investigate its bottleneck before adding the
next migration wave.

## Finish with the application

Run a representative application test on the destination after the
storage profiles pass. Include the transaction mix, dataset, concurrency,
and background jobs that established the acceptance condition. Exercise
the database's real commit path where durability affects response time.

Record application errors and correctness alongside performance. A fast
test that returns incomplete results has failed. Include a long enough
window to observe the business job that matters, whether that is an
interactive peak or an overnight batch.

Put the evidence in the migration change record: source and destination
configurations, test definitions, per-VM results, relevant telemetry,
application results, exceptions, and the owner's decision. The
[rollback plan](/posts/vmware-to-openshift-migration-rollback/)
should name the acceptance failures that trigger a return and the latest
time that decision can be made.

Keep the accepted test configuration for later storage, driver, image,
and cluster changes. Repeating it turns the migration baseline into a
way to detect regressions.

## The solutions architect takeaway

1. **Agree on acceptance first.** Tie the test to application demand and
   an observable failure condition.
2. **Preserve the comparison.** Match guest workloads and document the
   infrastructure differences.
3. **Measure the busy environment.** Add concurrent guests and expected
   background activity before accepting a wave.
4. **Keep latency beside throughput.** Retain per-VM results and the
   conditions under which they were measured.
5. **Get application sign-off.** Use the real transaction or batch job
   to make the migration decision.

## Related posts

- [OpenShift Storage Performance: Disks, IOPS, Architectures](/posts/openshift-storage-performance/)
- [What Replaces vRealize Operations for VMs](/posts/what-replaces-vrealize-operations/)
- [Upgrading OpenShift While VMs Stay Running](/posts/upgrading-openshift-while-vms-stay-running/)
- [Roll Back After Migrating to OpenShift Virtualization](/posts/vmware-to-openshift-migration-rollback/)

> Want help defining a performance acceptance test for your first migration
> wave? Bring the application targets and source measurements to your Red
> Hat account team before committing to the destination design.
{: .prompt-tip }

## Further reading

- [How to run I/O workloads on OpenShift Virtualization VMs](https://developers.redhat.com/articles/2026/11/03/how-run-io-workloads-openshift-virtualization-vms)
- [FIO container harness configuration and usage](https://github.com/ekuric/ioscale/blob/main/io-generic/fio-container/fio_README-container.md)
- [FIO manual](https://fio.readthedocs.io/en/latest/fio_doc.html)
- [Storage (OpenShift PoC)](https://openshift-ssa.github.io/openshift-poc/configure-the-cluster/storage/)

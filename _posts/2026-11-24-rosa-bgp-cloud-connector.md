---
title: "Reach ROSA VMs at Their Real IPs with BGP Cloud Connector"
description: >-
  How BGP Cloud Connector makes VM addresses on a primary CUDN reachable from
  an AWS VPC on ROSA 4.22, and how to test routing during maintenance.
date: 2026-11-24 07:00:00 -0600
categories: [OpenShift, Virtualization]
tags: [openshift, openshift-virtualization, rosa, networking, gitops]
permalink: /posts/rosa-bgp-cloud-connector/
social_title: |-
  ROSA VMs at
  their real IPs
social_label: OpenShift Virtualization
social_subtitle: BGP Cloud Connector · VPC Route Server · No NAT
---


> Personal site note: views expressed here are my own and do not necessarily
> represent Red Hat or any other organization. This covers BGP Cloud Connector
> on Red Hat OpenShift Service on AWS (ROSA) 4.22. Field names and defaults are
> new, so confirm them against the docs for the operator version you install.
{: .prompt-info }

The first VMware wave lands on ROSA and the VMs boot fine. Then the firewall
team asks which source IP the database VM will use. With the default pod network and ordinary outbound NAT,
the firewall sees the hosting worker's IP. After a live migration, it can see
a different worker's IP. That can break per-VM firewall rules, leave DNS pointing
clients at an unreachable guest address, and disrupt clustered applications
that advertise their own addresses.

On premises, I'd fix that with a localnet on a real VLAN, the pattern in my
[pod-to-localnet networking guide](/posts/openshift-virtualization-networking/).
AWS doesn't give you a Layer 2 segment to bridge onto. VPCs route at Layer 3.
[BGP Cloud Connector](https://www.redhat.com/en/blog/direct-vm-networking-aws-introducing-bgp-cloud-connector-red-hat-openshift-service-aws),
announced October 30 for ROSA 4.22 and later, gets you to the same result by
routing instead of bridging. Worker nodes advertise a primary
ClusterUserDefinedNetwork (CUDN) to
[Amazon VPC Route Server](https://docs.aws.amazon.com/vpc/latest/userguide/route-server-how-it-works.html)
over BGP. Route Server programs the VPC route tables, so an EC2 instance
reaches the VM at its own IP without NAT, a NodePort, or a load balancer.

## How the pieces fit

There are two layers, and they have different owners.

**The AWS layer is yours to build.** You create the Route Server, associate it
with the cluster VPC, put two Route Server endpoints in every subnet that
holds BGP-enabled workers, and turn on route propagation for the route tables
that need the CUDN prefix. The operator expects all of that to exist already.
[ROSA BGP routing docs](https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html/advanced_networking/bgp-routing)

**The in-cluster layer belongs to the operator.** You declare two custom
resources (CRs):

- `BGPCloudConfiguration` is a cluster-scoped singleton named `cluster`. It
  holds the local autonomous system number (ASN), the router node selector, and the Route Server IDs. From
  those IDs the operator discovers the endpoints, their elastic network interface (ENI) addresses, the
  Availability Zone (AZ) mapping, and the Route Server's ASN. It then generates
  one `FRRConfiguration` per AZ, creates a Route Server peer for each router-node and
  endpoint pair in that zone, and turns off source/destination checks on those nodes' primary ENIs.
- `BGPRouting` is created once per network. It generates a Layer 2 primary
  CUDN with persistent IPAM and a shared `RouteAdvertisements` object that
  advertises it.

Upstream, the operator tags each Route Server peer with the cluster's
infrastructure name, so several clusters can share one Route Server without
touching each other's peers.
[Upstream cloud integration notes](https://github.com/openshift/bgp-cloud-connector/blob/main/docs/cloud-integration.md)

Here's the part that drives most of the design. A VPC route table holds one
route per prefix. Route Server publishes one next hop at a time, so **one worker
node at a time is the ingress router for all inbound traffic to a given CUDN**.
That node hands packets to whichever worker hosts the VM over the Layer 2 CUDN.
Replies and VM-originated connections leave through the ENI of the worker
hosting the VM. If the active gateway fails and another worker is advertising
the prefix, Route Server can switch the route to that worker.
[Red Hat announcement](https://www.redhat.com/en/blog/direct-vm-networking-aws-introducing-bgp-cloud-connector-red-hat-openshift-service-aws)

Traffic can be asymmetric when the gateway and the VM host are different
workers. The request enters through the gateway's ENI and the reply leaves
through the VM host's ENI.

## The AWS limits that shape the design

These come from the
[Amazon VPC quotas page](https://docs.aws.amazon.com/vpc/latest/userguide/amazon-vpc-limits.html).
Three of these quotas are fixed.

| Quota | Default | Adjustable | What it means here |
| ----- | ------- | ---------- | ------------------ |
| Route servers per VPC | 5 | Yes | Plenty for one cluster. Shared VPCs add up. |
| Endpoints per route server | 10 | Yes | At two per subnet, that's five router subnets before you file a ticket. |
| Endpoints per route server and subnet | 2 | **No** | Two is the redundancy ceiling per subnet. |
| Peering sessions per network interface | 20 | Yes | Every router node in a subnet peers with that subnet's endpoints. |
| Routes per route server peer | 100 | **No** | Far more than one CUDN prefix needs. |
| Routes per route server (FIB) | 100 | **No** | Shared by every CUDN and anything else using this Route Server. |

The peering quota matters more than it first appears. The ROSA docs require
every node that can run a directly routed VM to match `routerNodeSelector`,
because egress leaves through the VM's own node. So in this design, every VM
host is a BGP speaker. AWS lists 20 peering sessions per network interface by default.
The quota entry doesn't specify which interface AWS counts in this topology.
Confirm that with AWS before translating the quota into a maximum pool size.
Upstream also has a `forwardingNodeSelector`
for nodes that should forward without peering. It isn't in the ROSA product
doc, so I wouldn't design around it until it is.
[Upstream CR reference](https://github.com/openshift/bgp-cloud-connector/blob/main/docs/custom-resources.md)

**Liveness detection.** Route Server peers support `bgp-keepalive` (the
default) or `bfd`. AWS describes BFD as more sensitive liveness detection
for faster failover, and doesn't expose hold timers to tune.
[RouteServerBgpOptions](https://docs.aws.amazon.com/AWSEC2/latest/APIReference/API_RouteServerBgpOptions.html)
The operator exposes the same choice as `spec.bgp.livenessDetection`. Its
upstream reference puts detection at about 1 second with BFD (300 ms × 3)
and about 90 seconds with keepalives at the default hold time. If you pick
BFD, open UDP 3784 as well as TCP 179.

**Cost.** AWS's Route Server tutorial lists endpoints at $0.75 per hour, and
the
[Cloud Experts guide](https://cloud.redhat.com/experts/rosa/bgp-cloud-connector/)
notes they bill whether or not traffic flows. With one router subnet in each of three AZs and two
endpoints per subnet, six endpoints cost $4.50 per hour, or $3,285 for a
730-hour month. Worker costs are additional. Rates vary by Region, so check
[VPC pricing](https://aws.amazon.com/vpc/pricing/) for yours.
[Create route server endpoints](https://docs.aws.amazon.com/vpc/latest/userguide/route-server-tutorial-create-endpoints.html)

**Instance types.** The Cloud Experts migration guide notes that only bare-metal
instance types expose `devices.kubevirt.io/kvm` on ROSA, and its lab used a
`c5n.metal` router worker. The BGP pool is also your VM pool, so size it like
one.
[Cloud Experts MTV preserve-IP guide](https://cloud.redhat.com/experts/rosa/vsphere-vm-migration-preserve-ip/)

## The GitOps shape

Keep the AWS prerequisites in Terraform or whatever already owns your VPC.
The upstream architecture assumes Terraform outputs feed the CR spec. The
in-cluster side fits an Argo CD application in four sync waves: operator,
cluster configuration, namespace, then routing. Everything below uses only
fields shown in the ROSA docs or the Cloud Experts guide. The
`argocd.argoproj.io/sync-wave` annotation is standard Argo CD.

**Wave 0: the operator.** The IAM role must exist first, because the operator
can't create its own. With STS, pass the role through `ROLEARN`.

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: bgp-cloud-connector
  annotations:
    argocd.argoproj.io/sync-wave: "0"
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: bgp-cloud-connector-operatorgroup
  namespace: bgp-cloud-connector
  annotations:
    argocd.argoproj.io/sync-wave: "0"
spec:
  targetNamespaces:
    - bgp-cloud-connector
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: bgp-cloud-connector-operator
  namespace: bgp-cloud-connector
  annotations:
    argocd.argoproj.io/sync-wave: "0"
spec:
  channel: stable
  installPlanApproval: Manual   # approve the first install and each upgrade
  name: bgp-cloud-connector
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  config:
    env:
      - name: ROLEARN
        value: arn:aws:iam::<aws_account_id>:role/bgp-cloud-connector-operator
```

With manual approval, approve the initial InstallPlan and wait for the
operator's ClusterServiceVersion to reach `Succeeded`. On a fresh cluster,
sync the wave 0 installation manifests first so the connector CRDs exist
before Argo CD validates the remaining resources.
[OLM subscriptions](https://olm.operatorframework.io/docs/concepts/crds/subscription/)

The Cloud Experts guide explicitly enables FRR on the cluster Network
operator before installation. If you follow that path, verify the pods in
`openshift-frr-k8s` now. In the upstream implementation, reconciling the
wave 1 configuration enables FRR. If you rely on that behavior, apply wave 1
first, then verify the FRR pods and the configuration's `Ready` status.
[Upstream reconciliation sequence](https://github.com/openshift/bgp-cloud-connector/blob/main/docs/reconciliation.md)

**Wave 1: cluster BGP configuration.** The local ASN must differ from the
Route Server's Amazon-side ASN. The operator discovers the Route Server's ASN,
so don't copy it in.

```yaml
apiVersion: networking.openshift.io/v1beta1
kind: BGPCloudConfiguration
metadata:
  name: cluster
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  platform: AWS
  bgp:
    localASN: 65001
    livenessDetection: bfd        # docs examples use bgp-keepalive (the default)
  routerNodeSelector:
    bgp_router: "true"
  aws:
    region: us-east-1
    routeServerIDs:
      - rs-0abc123456789abcd
```

**Wave 2: the workload namespace.** The ROSA docs call this out explicitly:
the `k8s.ovn.org/primary-user-defined-network` label must be there when the
namespace is created. Admission policy blocks adding it afterward. If someone
creates the namespace by hand before Argo CD gets to it, you'll be deleting
and recreating it.

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: vms-direct
  labels:
    k8s.ovn.org/primary-user-defined-network: ""
    cluster-udn: app-direct
  annotations:
    argocd.argoproj.io/sync-wave: "2"
```

**Wave 3: the routed network.** `spec.network.name` must match the
`cluster-udn` label value. The subnet must not overlap any VPC CIDR. Each
Layer 2 CUDN gets one IPv4 and one IPv6 CIDR at most.

```yaml
apiVersion: networking.openshift.io/v1beta1
kind: BGPRouting
metadata:
  name: app-direct
  annotations:
    argocd.argoproj.io/sync-wave: "3"
spec:
  network:
    name: app-direct
    subnets:
      - 10.100.0.0/16
```

That generates a CUDN named `cluster-udn-app-direct`. **Don't put the generated
CUDN or `RouteAdvertisements` in Git.** `BGPRouting` owns both, and the Cloud
Experts guide warns against editing the generated CUDN. Upstream, this is
roughly what the operator writes. Read it to understand what you'll see on the
cluster, not to apply it:

```yaml
# Generated by the operator; do not apply or edit
apiVersion: k8s.ovn.org/v1
kind: ClusterUserDefinedNetwork
metadata:
  name: cluster-udn-app-direct
  labels:
    advertise: "true"
    app.kubernetes.io/managed-by: bgp-cloud-connector
spec:
  namespaceSelector:
    matchLabels:
      cluster-udn: app-direct
  network:
    topology: Layer2
    layer2:
      role: Primary
      ipam:
        lifecycle: Persistent
      subnets:
        - 10.100.0.0/16
```

The shared `RouteAdvertisements` selects every CUDN labeled `advertise: "true"`
and advertises `PodNetwork` from all nodes (`nodeSelector: {}`). That matches
the OpenShift rule that pod-network advertisements must select every node.
[OpenShift 4.22 BGP routing](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/advanced_networking/bgp-routing)
One upstream detail matters for GitOps drift: the operator doesn't watch the
`FRRConfiguration` or `RouteAdvertisements` objects it writes. It corrects
drift at the next resync, so a hand edit can stick around for a while.
[Upstream reconciliation notes](https://github.com/openshift/bgp-cloud-connector/blob/main/docs/reconciliation.md)

**The VM.** Two settings matter: the binding, and keeping the VM on router
nodes.

```yaml
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: app01
  namespace: vms-direct
spec:
  runStrategy: Always
  template:
    metadata:
      annotations:
        network.kubevirt.io/addresses: '{"default":["10.100.0.50"]}'   # optional fixed IP
    spec:
      nodeSelector:
        bgp_router: "true"
      domain:
        devices:
          interfaces:
            - name: default
              binding:
                name: l2bridge
      networks:
        - name: default
          pod: {}
      # disks, volumes, and resources omitted
```

The ROSA procedure shows native `bridge: {}`, the binding used in the Cloud
Experts EC2-to-VM connectivity test. For this example I'd use `l2bridge`, the
default in the OpenShift Virtualization 4.22 console for a primary UDN. The
alternative `passt` binding on a primary UDN is Technology Preview in 4.22.
[OpenShift 4.22 virtualization networking](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/networking)

The upstream connector test reports that `masquerade` installs nftables rules
that drop inbound traffic on the UDN interface. The Cloud Experts team used
`l2bridge` in a separate RHEL 9 migration test, described below.
[Upstream VM binding tests](https://github.com/openshift/bgp-cloud-connector/blob/main/docs/kubevirt-testing.md)

Verify the end-to-end path before you call it done. Both CRs should report
`Ready`, `oc get bgpsessionstate -n openshift-frr-k8s` should show `Established`
for each expected endpoint peer, and the VPC route for the CUDN prefix should
be `active` with origin `Advertisement`:

```bash
aws ec2 describe-route-tables \
  --route-table-ids <client_route_table_id> \
  --query 'RouteTables[].Routes[?DestinationCidrBlock==`10.100.0.0/16`]'
```

## Failure modes I'd rehearse

### Draining a VM host and losing the active gateway

I'd run two rehearsals on a non-production cluster with two healthy router
workers advertising the prefix. Before each test, record the VM's host and
the next-hop ENI in the client's route table. From an EC2 client, keep a ping
running and make repeated HTTP requests to the VM's CUDN address.

1. **Drain the active gateway.** Place a migratable VM on that worker, configure
   it for live migration on eviction, and confirm another eligible worker has
   capacity. Drain the worker and record where the VM lands, whether the BGP
   sessions stay up, and whether the next-hop ENI changes. A normal drain
   leaves DaemonSet pods running, so FRR can keep advertising from the drained
   worker. The VM can move while the ingress gateway stays put.
2. **Test loss of the active peer.** With the test VM on the other worker,
   take the active gateway offline in the test environment. Record when its
   sessions drop, when the route changes to the healthy worker's ENI, and
   when ping and HTTP recover. Upstream's roughly one-second BFD estimate is
   for peer-failure detection. The route update and client recovery have
   their own timing. During an upgrade, also check that the replacement
   worker establishes its expected sessions.

[Kubernetes node drains](https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/) ·
[AWS Route Server failover](https://docs.aws.amazon.com/vpc/latest/userguide/route-server-how-it-works.html) ·
[Maintenance capacity for live migration](/posts/openshift-virtualization-vm-maintenance-capacity/)

Route Server's **persist routes** setting matters when *all* BGP sessions end.
With persistence disabled, Route Server removes the routes. With it enabled,
Route Server retains them during the outage and for a configured 1–5 minutes
after BGP returns. That can preserve forwarding during a control-plane
interruption if the selected worker still forwards packets. A route pointing
to an offline worker cannot deliver traffic.
[Create a route server](https://docs.aws.amazon.com/vpc/latest/userguide/route-server-tutorial-create.html)

### Live migration to the wrong node

Ingress doesn't care where the VM lives, because the gateway node forwards
across the Layer 2 CUDN. Egress does. A VM that migrates to a node outside
`routerNodeSelector` sends traffic from an ENI that still has source and
destination checking turned on. That's why I put `bgp_router: "true"` on the
VM and make the BGP machine pool the VM pool. In the Cloud Experts RHEL 9 test with `l2bridge`,
a live migration kept the IP and MAC and lost 1 of 980 pings, with a longest
gap of about 422 ms. The authors tested this separately from the VMware disk migration.
The full sequence on a VMware-derived VM still needs validation.
[Cloud Experts migration results](https://cloud.redhat.com/experts/rosa/vsphere-vm-migration-preserve-ip/)

### Asymmetric paths, security groups and NACLs

Security groups are stateful, but per ENI. A connection a VM starts goes out
through its host's ENI, and the reply can come back through the gateway node's
ENI, which never saw the outbound packet. That's why the ROSA procedure adds
an ingress rule for TCP and UDP 32768–60999 to the BGP security group. Two
things I'd tighten or test:

- **Scope.** The ROSA example uses `0.0.0.0/0` for BGP and ephemeral rules. The
  Cloud Experts lab scoped them to the VPC CIDR and still recommends narrowing
  further. I'd scope BGP to the endpoint subnets and ephemeral ports to the
  CIDRs your VMs actually talk to.
- **Windows guests.** 32768–60999 is the Linux default ephemeral range. Windows
  defaults to 49152–65535, so ports 61000–65535 fall outside the example rule. If you're following my
  [Windows VM standard](/posts/windows-vms-openshift-repeatable-standard/),
  test outbound connections from a Windows guest that are routed back
  through a different node and check the guest's configured range.
  [Microsoft dynamic port ranges](https://learn.microsoft.com/en-us/troubleshoot/windows-client/networking/tcp-ip-port-exhaustion-troubleshooting)

NACLs are stateless and evaluated in rule order, so allow TCP 179 both ways
between worker and endpoint subnets, plus application and return traffic on
every subnet the request or reply can cross. The worker's security groups apply to traffic for every VM behind that ENI.
Rules can match a remote source IP on ingress or a remote destination IP on
egress. The guests share the worker's security-group attachment. Use in-cluster
policy when a rule needs to select a particular VM.
[AWS security group rules](https://docs.aws.amazon.com/vpc/latest/userguide/security-group-rules.html) ·
[OpenShift network policies](/posts/openshift-network-policies/)

### Overlapping and more-specific routes

The ROSA docs require the CUDN CIDR not to overlap any VPC CIDR. The Cloud
Experts prerequisites go further and add the cluster networks, peered VPCs,
Transit Gateway, VPN, Direct Connect, and on-premises ranges. Their
troubleshooting also says to look for overlapping or more-specific routes when
BGP is up but the route is missing. Overlap is the expensive mistake here,
because you only find out when traffic to one address goes somewhere else.

IP-preserving migrations make this sharper. The Cloud Experts MTV guide gives
the ROSA VM its original VMware address, then warns that this doesn't transfer
ownership of the subnet. Don't advertise the same aggregate from on premises
and AWS and hope routing picks the right VM. Plan more-specific routes, route
preference, or an L2 extension, and plan how the route is withdrawn before any
rollback. That last part belongs in your
[rollback plan](/posts/vmware-to-openshift-migration-rollback/). The same
guide hit a practical snag: MTV's migration pods run in the target namespace,
and its CUDN had no route to vCenter. They migrated into a staging namespace on
the pod network and rebuilt the VM in the CUDN namespace.

### Reaching it from outside the VPC

Route Server only programs route tables in the cluster's VPC. It doesn't
advertise the CUDN over Transit Gateway, Direct Connect, VPN, or VPC peering.
For a client in another VPC connected through Transit Gateway, follow the CUDN
destination prefix through three route tables:

1. The client subnet's VPC route table sends the prefix to the Transit Gateway.
2. The Transit Gateway route table associated with the incoming client VPC
   attachment sends the prefix to the cluster VPC attachment.
3. The cluster-side attachment subnet's VPC route table receives the CUDN
   route through Route Server propagation and sends traffic to the worker ENI.

Check the return route from the VM host's subnet through the Transit Gateway
to the client network, and keep NAT out of both directions.
[AWS Transit Gateway routing](https://docs.aws.amazon.com/vpc/latest/tgw/how-it-works.html)

Red Hat specifically recommends against pointing the
connector at other routers with `platform: Manual`, because that peer list
doesn't update as nodes come and go. Also turn on propagation for every
in-VPC client subnet that needs the VMs. The Cloud Experts guide does this for
its tester subnet, and it's easy to miss.

## Path A vs Path B

**Path A: BGP Cloud Connector.** Clients can reach the VM at its CUDN
address using routed unicast traffic permitted by network policy and firewalls.
An external firewall can match that VM's source IP, and clients can reach the
address the guest publishes in DNS. Persistent IPAM and a compatible binding
let the VM retain its address across restarts and eligible live migrations.
Test application behavior and any licensing requirements during the cutover.
Budget for endpoint-hours, one ingress worker per CUDN prefix,
security group and NACL design that has to account for asymmetric paths, a
100-route FIB you can't raise, and a requirement that every VM host be a
labeled bare-metal router node. It's also new: the documented lab ran
OpenShift 4.22.9, OpenShift Virtualization 4.22.12, and operator 1.0.0.

**Path B: the default pod network plus Services and Routes.** It's mature, it's
the same model as your containers, and it's easy to automate. NodePort works
when clients can reach the nodes. A LoadBalancer Service puts a cloud load
balancer in front of the VM. Routes cover HTTP, HTTPS, and TLS through the
ingress controller. With the default egress configuration, external peers see
a node IP, and the pod IP can change on live migration. Each exposed Service
port needs a port entry. One Service can expose several named ports.
[Kubernetes multi-port Services](https://kubernetes.io/docs/concepts/services-networking/service/#multi-port-services)

| Need | Prefer |
| ---- | ------ |
| Web app or API with DNS-named clients | Path B: Route or LoadBalancer |
| A handful of TCP ports, clients don't care about the VM's IP | Path B: LoadBalancer |
| Source-IP firewall rules or allowlists per VM | Path A |
| AD domain members with dynamic DNS | Path A |
| Keep the VMware IP through migration | Path A, plus a routing cutover plan |
| Clustered app that expects identical addresses inside and outside the cluster | Path A |
| Very high inbound throughput on one network | Path B, or test the single-gateway limit under load first |

You can run both. A namespace on a routed CUDN and a namespace on the pod
network can share a cluster, so put each workload where its dependencies need
it.

## The solutions architect takeaway

1. **Use BGP Cloud Connector when the IP address is part of the application
   contract.** That means firewalls, AD, licensing, or cluster membership. If
   clients just need a name and a port, NodePort, LoadBalancer, or Routes are
   simpler, and I'd stay there.
2. **Make the router pool the VM pool.** Every node that can run a routed VM
   must match `routerNodeSelector`, and the VMs should select it too. Size the pool
   for CPU and memory, and confirm how AWS counts sessions per interface
   for your topology.
3. **Design for one gateway per prefix.** Test the throughput of a single
   gateway node. Measure VM migration during a drain and client recovery
   after peer loss before you promise a maintenance-window SLA.
4. **Treat CIDR ownership as a migration deliverable.** Choose non-overlapping
   ranges, or write down exactly how an overlapping subnet moves from on
   premises to AWS and back.
5. **Keep the operator installation manifests, labeled workload namespace,
   `BGPCloudConfiguration`, and `BGPRouting` in Git.** Apply the labels when
   creating the namespace. Let the operator manage the generated CUDN and
   shared `RouteAdvertisements`.

> Planning a VMware exit onto ROSA where IP addresses can't change? Bring your
> CIDR inventory, firewall dependencies, and change window to your Red Hat
> account team, and rehearse both a drain and gateway loss on a non-production cluster.
{: .prompt-tip }

## Related posts

- [OpenShift Virtualization Networking: Pod to Localnet](/posts/openshift-virtualization-networking/)
- [How Many VMs Can You Actually Maintain on One OpenShift Cluster?](/posts/openshift-virtualization-vm-maintenance-capacity/)
- [Karpenter vs Machine Pools on ROSA HCP](/posts/karpenter-vs-machine-pools-rosa/)
- [Roll Back After Migrating to OpenShift Virtualization](/posts/vmware-to-openshift-migration-rollback/)
- [OpenShift Network Policies: Tenant, Admin, Secondary](/posts/openshift-network-policies/)

## Further reading

- [Direct VM networking in AWS: Introducing BGP cloud connector on ROSA](https://www.redhat.com/en/blog/direct-vm-networking-aws-introducing-bgp-cloud-connector-red-hat-openshift-service-aws) (Red Hat, Oct 30, 2026)
- [BGP routing: Advanced networking (ROSA 4)](https://docs.redhat.com/en/documentation/red_hat_openshift_service_on_aws/4/html/advanced_networking/bgp-routing)
- [Deploying BGP Cloud Connector on ROSA HCP](https://cloud.redhat.com/experts/rosa/bgp-cloud-connector/) (Red Hat Cloud Experts)
- [Migrating vSphere VMs to ROSA HCP with MTV while preserving the VM IP address](https://cloud.redhat.com/experts/rosa/vsphere-vm-migration-preserve-ip/) (Red Hat Cloud Experts)
- [BGP routing (OpenShift Container Platform 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/advanced_networking/bgp-routing)
- [Networking (OpenShift Virtualization 4.22)](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/virtualization/networking)
- [openshift/bgp-cloud-connector](https://github.com/openshift/bgp-cloud-connector) (upstream source and CR reference)
- [How Amazon VPC Route Server works](https://docs.aws.amazon.com/vpc/latest/userguide/route-server-how-it-works.html)
- [Amazon VPC quotas: Route servers](https://docs.aws.amazon.com/vpc/latest/userguide/amazon-vpc-limits.html)
- [RouteServerBgpOptions (EC2 API)](https://docs.aws.amazon.com/AWSEC2/latest/APIReference/API_RouteServerBgpOptions.html)
- [Amazon VPC pricing](https://aws.amazon.com/vpc/pricing/)

# Multi-AZ FTW

Remember we deployed our app on nodes in a specific Availability Zone (AZ)? For a production setup you of course want your EKS cluster to be redundant across AZ and your workloads should not be impacted by any AZ outages. However, this has implications when it comes to storage. In this chapter we will find out more....

## Check AZ information

Our EKS cluster is deployed across 3 Availability Zones of AWS region us-west. We can check that by listing the nodes in our cluster. AWS assigns labels to each node that specify the zone the nodes runs in. We can ask Kubernetes to display that label alongside the other node information:

```console
 kubectl get nodes --label-columns topology.kubernetes.io/zone
```

Your output will be similar to this:

```console
NAME                                         STATUS   ROLES    AGE   VERSION                ZONE
ip-10-11-61-153.us-west-2.compute.internal   Ready    <none>   16h   v1.28.15-eks-113cf36   us-west-2a
ip-10-11-77-146.us-west-2.compute.internal   Ready    <none>   16h   v1.28.15-eks-113cf36   us-west-2b
ip-10-11-85-53.us-west-2.compute.internal    Ready    <none>   16h   v1.28.15-eks-113cf36   us-west-2c
```

Note that we have 3 worker nodes in our cluster. The name of each node includes the internal IP address. The last column gives us the AZ information. Each node runs in a different zone.

We can now match that information with out pods. The `-o wide` parameter provides some additional information, including the node on which the pod runs:

```console
kubectl get pod -o wide
```

```console
NAME            READY   STATUS    RESTARTS   AGE     IP             NODE                                         NOMINATED NODE   READINESS GATES
demoapp-0       1/1     Running   0          9m16s   10.11.54.28    ip-10-11-61-153.us-west-2.compute.internal   <none>           <none>
demoapp-ebs-0   1/1     Running   0          9m16s   10.11.51.24    ip-10-11-61-153.us-west-2.compute.internal   <none>           <none>
```

Note that both pods run on the same node. And by matching that with the previous output, we can see that it is the node running in zone us-west-2a. No surprise, as that is exactly what we hade specified in our pod template. We can check that again by checking our pods for the topology-based node selector:

```console
kubectl get pod demoapp-1 -o yaml | grep -A 3 zone
```

```console
kubectl get pod demoapp-ebs-1 -o yaml | grep -A 3 zone
```

In both cases your output should look like this:

```console
          - key: topology.kubernetes.io/zone
            operator: In
            values:
            - us-west-2a
```

## Move Pods to another AZ with EBS storage

So what happens if we change that topology information and ask Kubernetes to use zone `us-west-2b` instead? Kubernetes will remove the pod running in zone `us-west-2a` and create a new pod in zone `us-west-2b`. The following command might look scary, but it is quite simple. We patch the existing statefulset for EBS storage and change the zone to `us-west-2b`:

```console
kubectl patch statefulset demoapp-ebs -p '{"spec":{"template":{"spec":{"affinity":{"nodeAffinity":{"requiredDuringSchedulingIgnoredDuringExecution":{"nodeSelectorTerms":[{"matchExpressions":[{"key":"topology.kubernetes.io/zone","operator":"In","values":["us-west-2b"]}]}]}}}}}}}'
```

Wait a few seconds for Kubernetes to create the new pod in zone 2b. Then run the following command, to again check the information from the actual pod:

```console
kubectl get pod demoapp-ebs-1 -o yaml | grep -A 3 zone
```

Your output will now indicate that the pod has to run on a node in us-west-2b:

```console
          - key: topology.kubernetes.io/zone
            operator: In
            values:
            - us-west-2b
```

So moving the pod to another AZ was successful - or was it not? We better check the pod itself:

```console
kubectl get pod demoapp-ebs-0
```

```console
NAME            READY   STATUS    RESTARTS   AGE
demoapp-ebs-0   1/1     Pending   0          32s
```

The pod is still in state `Pending`. You can wait a little longer, then repeat the command. But it will continue to stay in the pending state. Why is that? Let's describe the pod, maybe that will give us a useful hint:

```console
kubectl describe pod demoapp-ebs-0
```

```console
[...]
Events:
  Type     Reason            Age    From               Message
  ----     ------            ----   ----               -------
  Warning  FailedScheduling  5m17s  default-scheduler  0/3 nodes are available: 1 node(s) had volume node affinity conflict, 2 node(s) didn't match Pod's node affinity/selector. preemption: 0/3 nodes are available: 3 Preemption is not helpful for scheduling..
```

The events at the very end of the output give us the reason.

`1 node(s) had volume node affinity conflict, 2 node(s) didn't match Pod's node affinity/selector`

So only one node is allowed, based on our topology node affinity. That is expected, as we explicitly asked for zone 2b and only have one node in that zone. But that node cannot be used due to the `volume node affinity conflict`. The reason for this is the usage of EBS disks. These are bound to a single AZ. They are neither redundant across AZ nor are they accessible across AZ. Our pod moved to a different zone but the volume cannot move with it, the pod is stuck in `pending`. Ooops. Let's see how our FSxN volume behaves.

## Move Pods to another AZ with FSxN storage

Again, we patch the statefulset (this time the one with the FSxN volume) and change the zone to `us-west-2b`:

```console
kubectl patch statefulset demoapp -p '{"spec":{"template":{"spec":{"affinity":{"nodeAffinity":{"requiredDuringSchedulingIgnoredDuringExecution":{"nodeSelectorTerms":[{"matchExpressions":[{"key":"topology.kubernetes.io/zone","operator":"In","values":["us-west-2b"]}]}]}}}}}}}'
```

Wait a few seconds, then verify the new pod has picked up this change:

```console
kubectl get pod demoapp-1 -o yaml | grep -A 3 zone
```

It has, good. But can the pod actually start?

```console
kubectl get pod -o wide
```

```console
NAME            READY   STATUS    RESTARTS   AGE     IP             NODE                                         NOMINATED NODE   READINESS GATES
demoapp-0       1/1     Running   0          33s     10.11.79.55    ip-10-11-77-146.us-west-2.compute.internal   <none>           <none>
demoapp-ebs-0   1/1     Pending   0          17m     10.11.51.24    ip-10-11-61-153.us-west-2.compute.internal   <none>           <none>
```

Yes it can. If the `demoapp-0` is not yet in a running state then wait a few seconds and repeat the command. It should come up quickly, while the EBS pod continues to stay in `Pending`. This showcases the cabilities of the FSxN storage service in AWS. It can be set up redundant across AZ, so that data is secure and available even when a complete AZ is lost. Furthermore, it is always accessible from all AZ of a region. It did not even have to "move" to zone 2b, is was already available there. Hence the pod can come up immediately and does not have to wait for the volume. This makes it the optimal choice for EKS workloads that need storage. Whereas the EBC storage service is limited to a single AZ, which might be too restrictive for your needs.

But there are more reasons why you might want to choose FSxN as your storage option (not just for EKS). Find out in the next chapter, [5. Oh Snap](snapshots)

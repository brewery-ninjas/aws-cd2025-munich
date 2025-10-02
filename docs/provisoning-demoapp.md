# 4. Provision app and storage

## Deploy our App

Enough with configuration, we finally want to have a real application that consumes some storage. We will be using a simple demo application, based on the popular nginx webserver. It is deployed as a `StatefulSet`in Kubernetes. This is the preferred option for any workloads that has storage needs, as it makes Kubernetes aware of the fact that this is stateful and needs special care. Please open the file `/labguide/provision/statefulset.yaml` in your Cloud9 editor and review it.

We cover some relevant parts here. If you want to dive deeper into the topic of StatefulSets, the Kubernetes documentation has a [good overview](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/).

```yaml
template:
  metadata:
    labels:
      app: demoapp
  spec:
    containers:
      - name: nginx
        image: registry.k8s.io/nginx
        ports:
          - containerPort: 80
            name: web
        volumeMounts:
          - name: www
            mountPath: /var/www/html
```

The StatefulSet defines a pod template. As we can scale this to multiple replicas, each replica pod will be created based on this template. You can see that the pod specifies a `volumeMount`. This instructs Kubernetes to mount a volume called `www`to the path `/var/www/html`- which is where nginx will serve its files from. So any data we write to this volume will be accessible on the web. We will make use of this later on.

If you move on, you find a block that is very specific to the lab exercise we will perform later:

```yaml
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: topology.kubernetes.io/zone
              operator: In
              values:
                # adjust here for zone switch
                - us-west-2a
```

This specifies a node affinity. It instructs Kubernetes to schedule the pod on a node that is in a specific availability zone `us-west-2a`. This gives us control over where the pod is running and demonstrate the effect this has on the different storage options. We will come back to this later, for now just remember that all pods will be scheduled in the AWS region and availability zone `us-west-2a`.

Next on, we need to specify the storage:

```yaml
volumeClaimTemplates:
  - metadata:
      name: www
    spec:
      accessModes: ["ReadWriteOnce"]
      storageClassName: sc-fsxn-san
      resources:
        requests:
          storage: 1Gi
```

Similar to the pod, this makes use of a template. In a StatefulSet, each replica pod will get its own storage volumes. This is a PersistentVolumeClaim definition for the most part, just written in the form of a template. The name of our volume will be `www`, which is what our pods expects. But as we will have multiple volumes (one for each replica pod) they cannot all have the same name. Therefore Kubernetes will automatically add the name of the statefulset (`demoapp` in our case) and the numerical index of the replica to the volume name and adjust the pod manifest accordingly. We will review the resulting names later on.
Note that the volume will use the iSCSI FSxN storage class we created earlier. The keep the volume size small for this lab.

You will then find almost the same YAML manifest again, only that we now name our app `demoapp-ebs`and make use of the `ebs` storage class. So we deploy the exact same statefulset, just with two different storage classes. This allows us to compare the two storage options (EBS and FSxN) side by side. At the end of the file you will also find a Service and Ingress definition. This makes the nginx webserver available via an AWS Application Load Balancer so we can actually reach it from a browser. For the purpose of this lab, we only do that for the first statefulset.

Let's create the StatefulSet:

```console
kubectl apply -f /home/ec2-user/environment/workshop-files/labguide/provision/statefulset.yml
```

## Check storage provisioning

```console
kubectl get pvc
```

It might take a moment for the volumes to be create. Repeat the above command until you see 2 PVCs that both have a status `Bound`:

```console
NAME                    STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
www-demoapp-0           Bound    pvc-9ecb65f4-9037-43ea-8341-0834212ac2ab   1Gi        RWO            sc-fsxn-san    20m
www-demoapp-ebs-0       Bound    pvc-62352dbb-3ea8-473c-8582-40332cc07823   1Gi        RWO            ebs            20m
```

As you can see from the output, two volumes were created, one for each StatefulSet (as we only have one replica in each). The PVC name is `www`as specified by the volume template, followed by the name of the statefulset (demoapp and demoapp-ebs) and then by a zero (as this is the index of the first replica).

The first PVC is on our FSxN storage. We can check directly in the FSxN service by running the following command:

```console
aws fsx describe-volumes --no-cli-pager --query 'Volumes[*].Name'
```

The output will be similar to this:

```console
    "eks_svm_root",
    "trident_pvc_9ecb65f4_9037_43ea_8341_0834212ac2ab",
```

The `root`volume is part of the FSxN service, not created by Trident. The second volume however is a PVC that was dynamically provisioned by the Trident CSI driver. Note that the volume name matches the Volume column from the `kubectl get pvc` command we used above. This is the name of the underlying Persistent Volume (or PV) object in Kubernetes.

The second volumes was created as an EBS disk. Again, we can check this directly from the EBS Service. The following command filters based on tags that the EBS CSI driver automatically adds to each EBS disk it creates. You therefore do not get all of the other EBS disks that exist in your lab environment:

```console
aws ec2 describe-volumes --no-cli-pager --filters Name=tag:kubernetes.io/cluster/cd2025munich-eks,Values=owned --query 'Volumes[*].{VolumeID:VolumeId, PVCName:Tags[?Key==`kubernetes.io/created-for/pvc/name`].Value | [0]}'
```

Your output will be similar to this, showing you the name of the EBS disk and the tag that contains the PVC Name:

```console
    {
        "VolumeID": "vol-0b1b03bcc1d0a34ab",
        "PVCName": "www-ebs-demoapp-ebs-0"
    }
```

As we now verified both volumes have been created and actually exist in their respective AWS service, as a final step we can check this directly from within the application container.

Let's execute a `mount` command inside the container. Since it will have multiple other mounts, we grep for `www` to only see the one that is mounted in our `/var/www/html` path. We start with the first statefulset, using FSxN storage:

```console
kubectl exec -it demoapp-0 -- mount | grep www
```

Your output will be similar to this:

```console
/dev/mapper/3600a09806c5742304c3f5a30366e6765 on /var/www/html type ext4 (rw,relatime,stripe=16)
```

This is an iSCSI volume, making use of Linux multipathing. You therefore see the devicemapper path. This is where the iSCSI LUN is available on the underlying Kubernetes worker node, and then passed on as a bind mount to the container.

We can run the same command for the pod from our second statefulset, using EBS storage:

```console
kubectl exec -it demoapp-ebs-0 -- mount | grep www
```

From the output, we can see that this is not using multipathing and appears to the worker node as a regular NVMe disk:

```console
/dev/nvme1n1 on /var/www/html type ext4 (rw,relatime)
```

## Check app provisioning

Similar to the storage, let's also make sure our app is correctly deployed. The following command gets the status of our statefulsets (or `sts` for short) and the pods created from that:

```console
kubectl get sts,pod
```

You should see an output similar to the following. It shows the two statefulsets, each having their replica (1/1) ready. And the two pods, following the statefulset naming scheme of the pod template name plus the index (0 for the first replica), all pods should be in state `Running`. In case the pods are not ready yet, please wait a moment and then repeat the command.

```console
NAME                           READY   AGE
statefulset.apps/demoapp       1/1     4m45s
statefulset.apps/demoapp-ebs   1/1     4m45s

NAME                READY   STATUS    RESTARTS   AGE
pod/demoapp-0       1/1     Running   0          4m45s
pod/demoapp-ebs-0   1/1     Running   0          4m45s
```

## Create some data

Our storage volume is used by nginx. It serves all files on that volume. But since we just created the volume it is still empty. Exec into the container and create an `index.html` file with the content of your choice:

```console
kubectl exec demoapp-0 -- bash -c "echo 'FSxN storage rocks' > /var/www/html/index.html"
```

We can check that the file was create correctly:

```console
kubectl exec demoapp-0 -- ls -l /var/www/html/
```

## Access your data

Remember we noticed an Ingress and Service that was part of our app deployment? Once the ingress controller has provisioned an ALB, the file we just created will be available on the web. Use the following command the retrieve the DNS name that was created by AWS for this ALB. Then open it in a browser to see your index.html file.

```console
aws elbv2 describe-load-balancers --query 'LoadBalancers[*].DNSName'
```

Note that it can take several minutes until the ALB is actually available/reachable. So no worries if this still gives you an error (or 404 page). Just try again in a few minutes. In the meantime, you can continue to chapter [5. Multi-AZ FTW](multi-az)

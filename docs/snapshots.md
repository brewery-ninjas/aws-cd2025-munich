### Oh Snap!

![](/images/snap.png)

Kubernetes (and therefore EKS) has native support for snapshots, a point-in-time copy of a storage volume. The most common use case for this is as part of a backup process, where PVCs are snapshotted to get a consistent frozen file system that can then be moved to a backup target. All backup tools for Kubernetes make use of Snapshots as part of their process so strong support for Snapshots is a very useful storage service capability. While almost all storage solutions support snapshots, not all snapshot are equal, as we shall see in this chapter.


## Create EBS Snapshot

Creating a snapshot in Kubernetes is easy. The `VolumeSnapshot`manifest is simple and straigt forward. Open the file `workshop-files/labguide/snapshots/ebs-snapshot.yaml in your Cloud9 editor. 

```console
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot 
metadata: 
  name: ebs-snapshot 
spec: 
  volumeSnapshotClassName: ebs-snapclass
  source: 
    persistentVolumeClaimName: www-demoapp-ebs-0
```

The Snapshot references the SnapshotClass (which we created earlier when configuring our storage integration). And it references a source PVC, the volume which we want to snapshot. 

Let's go ahead and create the snapshot, then move quickly to the next step:

```console
kubectl apply -f /home/ec2-user/environment/workshop-files/labguide/snapshots/ebs-snapshot.yaml
```

We want to observe how fast our snapshot is created. Run the following command:

```console
kubectl get volumesnapshot -w
```

This watches for any changes to our volumesnapshot objects. The initial entry has the column `READYTOUSE` as `false`. Wait until you get an output where this column is `true`. Then cancel the command with CTRL+C. 

```console
NAME           READYTOUSE   SOURCEPVC           SOURCESNAPSHOTCONTENT   RESTORESIZE   SNAPSHOTCLASS   SNAPSHOTCONTENT                                    CREATIONTIME   AGE
ebs-snapshot   false        www-demoapp-ebs-0                           1Gi           ebs-snapclass   snapcontent-00089a98-c196-4144-8fda-5fd9305e4af4   5s             6s
ebs-snapshot   true         www-demoapp-ebs-0                           1Gi           ebs-snapclass   snapcontent-00089a98-c196-4144-8fda-5fd9305e4af4   67s            68s
```

From the output we can see in the `AGE`column how long it took to create the snapshot. The snapshot process is done once the ready-to-use state changes to `true`. With the EBS disk we are using here, this will likely take you 1-2 minutes, but the timing can vary quite a bit. That is a long time, given that the volume is only 1GB in size and empty.


## Create FSxN Snapshot

Now let's repeat that for the FSxN based volume. Open the file `fsxn-snapshot.yaml` in your editor and review it. Very similar to the first snapshot, just that we now use the snapshot class for the Trident driver and reference the FSxN-based PVC.

Apply the manifest, then again move quicky to the next step.

```console
kubectl apply -f /home/ec2-user/environment/workshop-files/labguide/snapshots/fsxn-snapshot.yaml
```

```console
kubectl get volumesnapshot 
NAME               READYTOUSE   SOURCEPVC           SOURCESNAPSHOTCONTENT   RESTORESIZE   SNAPSHOTCLASS   SNAPSHOTCONTENT                                    CREATIONTIME   AGE
ebs-snapshot       true         www-demoapp-ebs-0                           1Gi           ebs-snapclass   snapcontent-be42d3d8-2cf1-43d5-96d1-1f190111c6b1   5m11s          5m12s
fsxn-snapshot      true         www-demoapp-0                               1Gi           csi-snapclass   snapcontent-3661ffcb-45ef-4af9-8603-e08100ea3e32   3s             4s
```

Most likely the FSxN snapshot was already done (READYTOUSE=true) before you managed to run the command. If not, repeat it and it will be done. With FsxN the snapshot creation is instant. And this is independent of the volume size! Even with a volume of several TB it would still take a few seconds at most. Also, the snapshot does not consume any extra storage space (so you don't get charged for it extra) and doesn't have any performance impact. One more good reason to choose the FSxN storage service.


## Create clone

While the instant snapshots are pretty cool, what if you want access to the data inside the snapshot? What if you have a use case if quickly providing copies of data. For automated test runs in your build pipeline, just as one example. That is what we call cloning. Try it out, pretty sure you will like it...

Open the file clone.yaml in your Cloud9 Editor.

This manifest defines two objects, a PVC and a Pod that uses it. The PVC is very similar to the volume template we used in our statefulset. The main difference is the dataSource Section:

```yaml
  dataSource:
    name: fsxn-snapshot
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
```

This instructs Kubernetes to not create an empty PVC (as it would usually do) but instead use the snapshot we created earlier as the base for this new PVC. This is what is called a Clone in the storage world. For Kubernetes it is a standard PVC with an additional dataSource section. 
This cloned PVC is then mounted into our nginx pod.

Let's create it:

```console
kubectl apply -f /home/ec2-user/environment/workshop-files/labguide/snapshots/clone.yaml
```

The check if we are done yet:

```console
kubectl get pod,pvc
```

The new clone PVC is probably already in state `Bound`, so the cloning process is already complete. The pod might take a few more seconds to come up. If necessary repeat the command until the clone PVC is `Bound` and the clone pod is `Running`. This will only take a few seconds.

Same as with the snapshot, a clone in FSxN is instant. And again, this is independent of the volume size. It doesn't have any performance impact, the full performance will immediately be available on the clone volume. And it does not consume any extra capacity. 

Finally, let's verify it actually is a clone of our first volume:

```console
kubectl exec clonepod -- ls /var/www/html
```

We see our index.html file that we created earlier. 

```console
index.html
lost+found
```

Does it contain our data as well?

```console
kubectl exec clonepod -- cat /var/www/html/index.html
```

Yes, it does. And it provides nice final words for our lab as well. Hope you enjoyed it. And remember:

```console
FSxN storage rocks
```

### Oh Snap!

![](/labguide/images/snap.png)

## Create EBS Snapshot

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

```console
kubectl get volumesnapshot -w
NAME           READYTOUSE   SOURCEPVC           SOURCESNAPSHOTCONTENT   RESTORESIZE   SNAPSHOTCLASS   SNAPSHOTCONTENT                                    CREATIONTIME   AGE
ebs-snapshot   false        www-demoapp-ebs-0                           1Gi           ebs-snapclass   snapcontent-00089a98-c196-4144-8fda-5fd9305e4af4   5s             6s
ebs-snapshot   true         www-demoapp-ebs-0                           1Gi           ebs-snapclass   snapcontent-00089a98-c196-4144-8fda-5fd9305e4af4   67s            68s
```

## Create FSxN Snapshot

```console
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: fsxn-snapshot
spec:
  volumeSnapshotClassName: csi-snapclass
  source:
    persistentVolumeClaimName: www-demoapp-0
```

```console
 kubectl get volumesnapshot -w
NAME               READYTOUSE   SOURCEPVC           SOURCESNAPSHOTCONTENT   RESTORESIZE   SNAPSHOTCLASS   SNAPSHOTCONTENT                                    CREATIONTIME   AGE
ebs-snapshot       true         www-demoapp-ebs-0                           1Gi           ebs-snapclass   snapcontent-be42d3d8-2cf1-43d5-96d1-1f190111c6b1   5m11s          5m12s
fsxn-snapshot      true         www-demoapp-0                               1Gi           csi-snapclass   snapcontent-3661ffcb-45ef-4af9-8603-e08100ea3e32   3s             4s
```

--> Instant (less than 4 seconds)

## Create clone

```console
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: clone
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  storageClassName: sc-fsxn-san
  dataSource:
    name: fsxn-snapshot
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
---
kind: Pod
apiVersion: v1
metadata:
  name: clonepod
spec:
  volumes:
    - name: clone
      persistentVolumeClaim:
       claimName: clone
  containers:
    - name: nginx
      image: registry.k8s.io/nginx
      volumeMounts:
        - mountPath: "/var/www/html"
          name: clone
```

```console
kubectl get pod,pvc
```

--> clone creation is almost instant. Stays like that even with TB of data. No perf impact, no extra capacity consumed

```console
 kubectl exec clonepod -- ls /var/www/html
index.html
lost+found
```

```console
kubectl exec clonepod -- cat /var/www/html/index.html
FSxN storage rocks
```

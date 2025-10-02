# 2. Explore your lab setup

## EKS Cluster

The script created a small EKS cluster for you to use. It consists of 3 nodes across 3 different availability zones (AZ).

Check the cluster nodes and their AZ with the following command:

```console
kubectl get nodes --label-columns topology.kubernetes.io/zone
```

The cluster also has the EBS storage-addon already installed and a matching storage class configured. You can discover all existing StorageClasses with a simple command:

```console
kubectl get sc
```

Note that the EKS cluster has a pre-configured `gp2` storage class that still uses the deprecated in-tree driver. We will ignore this class for the rest of the lab. And it has an `ebs` storage class. Let's see more details as we are going to use this class in the lab. A _describe_ will provide them. Let's do this

```console
kubectl describe sc ebs
```

As you can see from the output, this storage class uses the provisioner ("CSI Driver") ebs.csi.aws.com. This integrates EBS disks into Kubernetes. However, the use of EBS disks comes with a few drawbacks due to lack of cross-AZ availability, only basic snapshot support and limitations to the number of disks that can be attached per Kubernetes nodes. We will experience some of these shortcomings during the lab exercises. Therefore let's go ahead and integrate the AWS FSxN storage service as well as that helps to overcome these limitations.

## Trident and FSx for NetApp Ontap

[Amazon FSx for NetApp ONTAP (FSxN)](https://aws.amazon.com/ko/fsx/netapp-ontap) is a storage service that allows you to start and run a fully managed NetApp ONTAP file system in the AWS cloud.
It provides the benefits of a fully managed AWS service - agility, scalability, and simplicity - along with the functionality, performance, and APIs of the familiar NetApp file system.
Amazon FSx for NetApp ONTAP provides high-performance file storage that can be widely accessed by Linux, Windows, and macOS computing instances through industry-standard Network File System (NFS) , Server Message Block (SMB) , and Internet Small Computer Systems Interface (iSCSI) protocols.
With a single click, you can access the widely used ONTAP data management features like snapshots and cloning.
It provides highly elastic and nearly limitless low-cost storage capacity, and supports compression and deduplication to further reduce storage costs.

![](/labguide/images/fsxn-overview.png)

The FSxN storage service is integrated with EKS via a CSI driver called [Trident](https://docs.netapp.com/us-en/trident/). This driver is also available as an EKS Add-On. This is already deployed on the cluster in the Trident namespace:

```console
kubectl get all -n trident
```

As you can see, it consists of multiple pods. The Operator manages the Trident installation. The other pods are the trident-controller, which is the main component that also interacts with the FSxN storage service. And a Daemonset that ensures that one additional pod runs on each node of the cluster to control activities such as storage mounting/unmounting.

While the Trident driver is deployed, it is not yet configured. Trident requires one or more TridentBackendConfig that provide the necessary details for the storage service it should connect to. As FSxN support file (NFS, SMB) and block (iSCSI, NVMe) protocols, you can have multiple TridentBackendConfig pointing to the same FSxN service, one for each protocol you would like to use.

In the next chapter we will create two backend configurations, one for NFS and one for iSCSI. So let's move on to chapter [3. Configure Storage](/labguide/configure-your-storage)

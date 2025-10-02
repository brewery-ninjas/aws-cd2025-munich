#!/usr/bin/bash
source ~/.bash_profile
cd ~/aws-cd2025-munich/workshop-environment

helm repo add netapp-trident https://netapp.github.io/trident-helm-chart
helm repo add netapp-trident-protect https://netapp.github.io/trident-protect-helm-chart
helm install trident netapp-trident/trident-operator --version 100.2506.2 --create-namespace --namespace trident

echo "Waiting for Trident to be installed"
until [ $(kubectl describe torc -n trident trident | grep "  Status:"| awk -F ':     '  '{print $2}') == "Installed" ]
do
        sleep 1
        echo -n "."
done

helm install trident-protect netapp-trident-protect/trident-protect --set clusterName=${CLUSTER_NAME} --version 100.2506.0 --create-namespace --namespace trident-protect
echo "Waiting for Trident-Protect to be installed"
until [ $(kubectl get pods -n trident-protect | grep trident-protect-controller-manager  | awk -F' ' '{print $3}') == "Running" ]
do
        sleep 1
        echo -n "."
done

cd ~/environment/fsxn

cat > 00-secret_fsxn.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: secret-fsxn
  namespace: trident
type: Opaque
stringData:
  username: vsadmin
  password: ${SVM_PASS}
EOF

cd ~/environment/fsxn

cat > 01-backend_fsxn_nas.yaml <<EOF
apiVersion: trident.netapp.io/v1
kind: TridentBackendConfig
metadata:
  name: backend-fsxn-nas
  namespace: trident
spec:
  version: 1
  backendName: eks-svm-nas
  storageDriverName: ontap-nas
  nasType: nfs
  managementLIF: ${SVM_MGMT}
  dataLIF: ${SVM_NFS}
  svm: eks-svm
  nfsMountOptions: vers=4.1,sec=sys,nconnect=6,rsize=262144,wsize=262144
  credentials:
    name: secret-fsxn
EOF

cd ~/environment/fsxn

cat > 02-backend_fsxn_san.yaml <<EOF
apiVersion: trident.netapp.io/v1
kind: TridentBackendConfig
metadata:
  name: backend-fsxn-san
  namespace: trident
spec:
  version: 1
  backendName: eks-svm-san
  storageDriverName: ontap-san
  sanType: iscsi
  managementLIF: ${SVM_MGMT}
  svm: eks-svm
  credentials:
    name: secret-fsxn
EOF

cd ~/environment/fsxn

cat > 03-storage_class_fsxn_nas.yaml <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: sc-fsxn-nas
provisioner: csi.trident.netapp.io
parameters:
  backendType: ontap-nas
  fsType: nfs
allowVolumeExpansion: True
reclaimPolicy: Retain
EOF

cd ~/environment/fsxn

cat > 11-storage_class_fsxn_san.yaml <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: sc-fsxn-san
provisioner: csi.trident.netapp.io
parameters:
  backendType: ontap-san
  fsType: ext4
allowVolumeExpansion: True
reclaimPolicy: Retain
EOF


cat > 12_storage_class_snapshot.yaml <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: csi-snapclass
driver: csi.trident.netapp.io
deletionPolicy: Delete
EOF

#!/bin/bash

###############################################
# variables 
###############################################
GITREPO="https://github.com/brewery-ninjas/aws-cd2025-munich"

###############################################

echo "Preparing environment for FSxN and EKS workshop"
echo "--------------------------------------------------"

echo "  + Installing packages"
echo "    + Installing kubectl"
curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/1.32.7/2025-08-03/bin/linux/amd64/kubectl
chmod +x ./kubectl
mkdir -p $HOME/bin && cp ./kubectl $HOME/bin/kubectl && export PATH=$HOME/bin:$PATH

echo "    + Installing eksctl"
ARCH=amd64
PLATFORM=$(uname -s)_$ARCH
curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz
sudo install -m 0755 /tmp/eksctl $HOME/bin && rm /tmp/eksctl


echo "    + Installing Helm"
curl -sSL https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
helm repo add stable https://charts.helm.sh/stable

echo "  + Configuring CLIs"
kubectl completion bash >>  ~/.bash_completion
helm completion bash >> ~/.bash_completion
eksctl completion bash >> ~/.bash_completion

source /etc/profile.d/bash_completion.sh
source ~/.bash_completion

echo "  + Removing existing AWS credentials"
rm -vf ${HOME}/.aws/credentials


# Set environment variables
cd ~
cat ~/.bash_profile | grep -v ^export > bash_profile
cp bash_profile .bash_profile

echo "  + Generating AWS environment variables"
bucket_name=$(aws s3 ls | awk '{print $3}' | head -1)
region=$(aws s3api get-bucket-location --bucket $bucket_name --query 'LocationConstraint' --output text)
if [ "$region" = "None" ]; then
  region="us-east-1"
  echo "export AWS_REGION=us-east-1" | tee -a ~/.bash_profile
else
  echo "export AWS_REGION=$region" | tee -a ~/.bash_profile
fi

ACCOUNT_ID=$(aws sts get-caller-identity --region $region --output text --query Account)
echo "export ACCOUNT_ID=${ACCOUNT_ID}" | tee -a ~/.bash_profile
echo "export CLUSTER_NAME=cd2025munich-eks" | tee -a ~/.bash_profile
echo "export EKS_VERSION=1.28" | tee -a ~/.bash_profile
echo "export FSxN_SG=$(aws ec2 describe-security-groups --filters Name=tag:Name,Values=FSxONTAPSecurityGroup | jq -r '.SecurityGroups[].GroupId')" | tee -a ~/.bash_profile
echo "export CLUSTER_VPC_ID=$(aws ec2 describe-vpcs --filters Name=tag:Name,Values=eksworkshop | jq -r '.Vpcs[].VpcId')" | tee -a ~/.bash_profile
echo "export PublicSubnet01=$(aws ec2 describe-subnets --filters 'Name=tag:Name,Values=eksworkshop-PublicSubnet01' | jq -r '.Subnets[].SubnetId')" | tee -a ~/.bash_profile
echo "export PublicSubnet02=$(aws ec2 describe-subnets --filters 'Name=tag:Name,Values=eksworkshop-PublicSubnet02' | jq -r '.Subnets[].SubnetId')" | tee -a ~/.bash_profile
echo "export PublicSubnet03=$(aws ec2 describe-subnets --filters 'Name=tag:Name,Values=eksworkshop-PublicSubnet03' | jq -r '.Subnets[].SubnetId')" | tee -a ~/.bash_profile
echo "export PrivateSubnet01=$(aws ec2 describe-subnets --filters 'Name=tag:Name,Values=eksworkshop-PrivateSubnet01' | jq -r '.Subnets[].SubnetId')" | tee -a ~/.bash_profile
echo "export PrivateSubnet02=$(aws ec2 describe-subnets --filters 'Name=tag:Name,Values=eksworkshop-PrivateSubnet02' | jq -r '.Subnets[].SubnetId')" | tee -a ~/.bash_profile
echo "export PrivateSubnet03=$(aws ec2 describe-subnets --filters 'Name=tag:Name,Values=eksworkshop-PrivateSubnet03' | jq -r '.Subnets[].SubnetId')" | tee -a ~/.bash_profile
echo "export FSX_PASS=$(aws secretsmanager get-secret-value --secret-id eksworkshop-FsxAdminPassword | jq -r '.SecretString | fromjson.password')" | tee -a ~/.bash_profile
echo "export SVM_PASS=$(aws secretsmanager get-secret-value --secret-id eksworkshop-SVMAdminPassword | jq -r '.SecretString | fromjson.password')" | tee -a ~/.bash_profile
echo "export FSX_MGMT=$(aws fsx describe-file-systems --query "FileSystems[*].OntapConfiguration.Endpoints.Management.DNSName" --output text)" | tee -a ~/.bash_profile
echo "export SVM_MGMT=$(aws fsx describe-storage-virtual-machines --query "StorageVirtualMachines[*].Endpoints.Management.DNSName" --output text)" | tee -a ~/.bash_profile
echo "export SVM_NFS=$(aws fsx describe-storage-virtual-machines --query "StorageVirtualMachines[*].Endpoints.Nfs.DNSName" --output text)" | tee -a ~/.bash_profile
echo "export SVM_ISCSI=$(aws fsx describe-storage-virtual-machines --query "StorageVirtualMachines[*].Endpoints.Iscsi.DNSName" --output text)" | tee -a ~/.bash_profile

# Verify environment variables


echo "  + Preparing EKS Launch Template"
cat > ~/nodeprep_config.template << EOF
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="==MYBOUNDARY=="

--==MYBOUNDARY==
Content-Type: text/x-shellscript; charset="us-ascii"

#!/bin/bash
yum install -y nfs-utils
yum install -y lsscsi iscsi-initiator-utils sg3_utils device-mapper-multipath
sed -i 's/^(node.session.scan).*/1 = manual/' /etc/iscsi/iscsid.conf
cat > /etc/multipath.conf <<EOT
defaults {
    find_multipaths no
}
blacklist {
    device {
        vendor "NVME"
        product "Amazon Elastic Block Store"
    }
}
EOT
systemctl enable --now iscsid multipathd
systemctl enable --now iscsi


--==MYBOUNDARY==--
EOF

userdata_content=$(cat ~/nodeprep_config.template | base64 -w 0)

echo " + Cloning workshop files repository"
mkdir mkdir -p ~/environment/workshop-files
cd ~/environment/workshop-files
git clone ${GITREPO} .

mkdir -p ~/environment/fsxn
cd ~/environment/fsxn

# Launch Template configuration file
cat > eks-lt-for-iscsi.json << EOF
{
"InstanceType": "t3.medium",
"UserData":"${userdata_content}"
}
EOF

echo "  + Creating EKS Launch Template"
# Create Launch Template using AWS CLI
aws ec2 create-launch-template --launch-template-name eks-lt-for-iscsi --version-description version1 --tag-specifications 'ResourceType=launch-template,Tags=[{Key=Name,Value=eks-lt-for-iscsi}]' --launch-template-data file://eks-lt-for-iscsi.json

# Add Launch Template environment variable
echo "export LT_ID=$(aws ec2 describe-launch-templates --filters 'Name=tag:Name,Values=eks-lt-for-iscsi' | jq -r '.LaunchTemplates[0].LaunchTemplateId')" | tee -a ~/.bash_profile

# cat ~/.bash_profile
source ~/.bash_profile


cd ~/environment/fsxn

cat > eks-fsxn-cluster.yaml <<EOF
# EKS Cluster with FSxN
---
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: ${CLUSTER_NAME}
  region: ${AWS_REGION}
  version: "${EKS_VERSION}"

vpc: 
  id: ${CLUSTER_VPC_ID}
  subnets:
    public:
      PublicSubnet01:
        id: ${PublicSubnet01}
      PublicSubnet02:
        id: ${PublicSubnet02}
      PublicSubnet03:
        id: ${PublicSubnet03}
    private:
      PrivateSubnet01:
        id: ${PrivateSubnet01}
      PrivateSubnet02:
        id: ${PrivateSubnet02}
      PrivateSubnet03:
        id: ${PrivateSubnet03}
    
managedNodeGroups:
  - name: mng-01
    minSize: 3
    desiredCapacity: 3
    maxSize: 5
    subnets:
    - ${PrivateSubnet01}
    - ${PrivateSubnet02}
    - ${PrivateSubnet03}
    privateNetworking: true
    launchTemplate:
      id: ${LT_ID}

iam:
  withOIDC: true
addons:
  - name: vpc-cni
    attachPolicyARNs:
      - arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
  - name: coredns
    version: latest
  - name: kube-proxy
    version: latest
  - name: aws-ebs-csi-driver
    wellKnownPolicies:
      ebsCSIController: true
  - name: snapshot-controller
    version: latest
EOF


cd ~/environment/fsxn
echo "  + Creating EKS Cluster configuration file"
echo "  + EKS Cluster and Node Group creation in progress - this will take approx. 15-20 minutes"
eksctl create cluster -f eks-fsxn-cluster.yaml

sleep 200

echo "export EKS_SG1=$(aws eks describe-cluster --name ${CLUSTER_NAME} --output json | jq -r '.cluster.resourcesVpcConfig.securityGroupIds[0]')" | tee -a ~/.bash_profile
source ~/.bash_profile
aws eks update-cluster-config --name ${CLUSTER_NAME} --resources-vpc-config securityGroupIds=$EKS_SG1,$FSxN_SG
sleep 100
aws eks describe-cluster --name  ${CLUSTER_NAME} --output json | jq -r '.cluster.resourcesVpcConfig.securityGroupIds[]'



curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.13.3/docs/install/iam_policy.json
aws iam create-policy   --policy-name AWSLoadBalancerControllerIAMPolicy   --policy-document file://iam_policy.json

eksctl create iamserviceaccount \
    --cluster=${CLUSTER_NAME} \
    --namespace=kube-system \
    --name=aws-load-balancer-controller \
    --attach-policy-arn=arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy \
    --override-existing-serviceaccounts \
    --region ${AWS_REGION} \
    --approve

helm repo add eks https://aws.github.io/eks-charts
helm repo update eks
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=${CLUSTER_NAME} \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --version 1.13.4

# Add Snapshot-Controller
# eksctl create addon --name snapshot-controller --cluster ${CLUSTER_NAME} --region ${AWS_REGION}

# #######################
# Trident deployment
# #######################

#!/usr/bin/bash
source ~/.bash_profile
cd ~/aws-cd2025-munich/workshop-environment

helm repo add netapp-trident https://netapp.github.io/trident-helm-chart
helm repo add netapp-trident-protect https://netapp.github.io/trident-protect-helm-chart
helm install trident netapp-trident/trident-operator --version 22.10.0 --create-namespace --namespace trident

echo "Waiting for Trident to be installed"
sleep 20
until [ $(kubectl describe torc -n trident trident | grep "  Status:"| awk -F ':     '  '{print $2}') == "Installed" ]
do
        sleep 1
        echo -n "."
done

helm install trident-protect netapp-trident-protect/trident-protect --set clusterName=${CLUSTER_NAME} --version 100.2506.0 --create-namespace --namespace trident-protect
echo "Waiting for Trident-Protect to be installed"
sleep 20
until [ $(kubectl get pods -n trident-protect | grep trident-protect-controller-manager  | awk -F' ' '{print $3}') == "Running" ]
do
        sleep 1
        echo -n "."
done

cd ~/environment/fsxn

cat > ebs-storageclass.yaml <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ebs
provisioner: ebs.csi.aws.com
volumeBindingMode: Immediate
reclaimPolicy: Delete
allowedTopologies:
- matchLabelExpressions:
  - key: topology.kubernetes.io/zone
    values:
    - us-west-2a
EOF

kubectl apply -f /home/ec2-user/environment/fsxn/ebs-storageclass.yaml

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


echo "Your lab is now ready, have fun..."

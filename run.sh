#!/bin/bash
# Description = This bash script > With using eksctl , creates a simple eks cluster with ClusterAutoscaler .
# HowToUse = " % ./run.sh| tee -a output.md "
# Duration = Around 15 minutes
# https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/cloudprovider/aws/README.md

### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
### Variables:
export REGION=ap-southeast-2
export CLUSTER_VER=1.27
export CLUSTER_NAME=ca
export CLUSTER=$CLUSTER_NAME
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
export ACC=$AWS_ACCOUNT_ID
export AWS_DEFAULT_REGION=$REGION
# export role_name=AmazonEKS_EFS_CSI_DriverRole_$CLUSTER_NAME


echo " 
### PARAMETERES IN USER >>> 
CLUSTER_NAME=$CLUSTER_NAME  
REGION=$REGION 
AWS_DEFAULT_REGION=$AWS_DEFAULT_REGION
AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID

"

if [[ $1 == "cleanup" ]] ;
then 


### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
echo " 
### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
 ### 0- Cleanup IRSA file system for CA :
 "
# Do Cleanup

kubectl delete -f cluster-autoscaler-autodiscover.yaml

eksctl delete iamserviceaccount \
--region=$REGION \
--cluster=$CLUSTER \
--namespace=kube-system \
--name=cluster-autoscaler 

kubectl  -n kube-system describe sa cluster-autoscaler

exit 1
fi;


### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
echo "
### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
 ### 1- Create cluster "

eksctl create cluster  -f - <<EOF
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: $CLUSTER
  region: $REGION
  version: "$CLUSTER_VER"

managedNodeGroups:
  - name: mng
    privateNetworking: true
    desiredCapacity: 2
    instanceType: t3.medium
    labels:
      worker: linux
    maxSize: 3
    minSize: 0
    volumeSize: 20
    ssh:
      allow: true
      publicKeyPath: AliSyd

kubernetesNetworkConfig:
  ipFamily: IPv4 # or IPv6

addons:
  - name: vpc-cni
  - name: coredns
  - name: kube-proxy
#  - name: aws-ebs-csi-driver

iam:
  withOIDC: true

iamIdentityMappings:
  - arn: arn:aws:iam::$ACC:user/Ali
    groups:
      - system:masters
    username: admin-Ali
  - arn: arn:aws:iam::$ACC:role/Admin
    groups:
      - system:masters
    username: isengard-Ali
    noDuplicateARNs: true # prevents shadowing of ARNs

cloudWatch:
  clusterLogging:
    enableTypes:
      - "*"

EOF

### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
echo "
### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
 ### 2- kubeconfig  : "
aws eks update-kubeconfig --name $CLUSTER --region $REGION

### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
echo " 
### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
### 3- Check cluster node and infrastructure pods  : "
kubectl get node
kubectl -n kube-system get pod 
kubectl   get crd > crd-0.txt

### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
echo "
### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
 ### 3- create IAM Policy : 
 "


cat <<EoF > k8s-asg-policyfor-ca.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": [
                "autoscaling:DescribeAutoScalingGroups",
                "autoscaling:DescribeAutoScalingInstances",
                "autoscaling:DescribeLaunchConfigurations",
                "autoscaling:DescribeTags",
                "autoscaling:SetDesiredCapacity",
                "autoscaling:TerminateInstanceInAutoScalingGroup",
                "ec2:DescribeLaunchTemplateVersions"
            ],
            "Resource": "*",
            "Effect": "Allow"
        }
    ]
}
EoF

aws iam create-policy   \
  --policy-name k8s-asg-policy-for-ca \
  --policy-document file://k8s-asg-policyfor-ca.json




### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
echo "
### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
 ### 4 - Install CA with YAML manifest  : 
 "

 curl -O https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml
# Replace cluster-name with your cluster name 
# use same version of image as cluster version 



#####  Replace the Cluster name :
### For Linux : 
### sed -i 's/<YOUR CLUSTER NAME>/$CLUSTER/p' cluster-autoscaler-autodiscover.yaml
### For MAC   : 
sed -i -e "s/<YOUR CLUSTER NAME>/$CLUSTER/g" cluster-autoscaler-autodiscover.yaml
sed -i -e "s/v1.26.2/v$CLUSTER_VER.1/g" cluster-autoscaler-autodiscover.yaml

kubectl apply -f cluster-autoscaler-autodiscover.yaml
# Watch the logs

# kubectl -n kube-system logs -f deployment/cluster-autoscaler


### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
echo "
### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
 ### 5- create iamserviceaccount  : 
 "

eksctl create iamserviceaccount \
--region=$REGION \
--cluster=$CLUSTER \
--namespace=kube-system \
--name=cluster-autoscaler \
--attach-policy-arn=arn:aws:iam::$ACC:policy/k8s-asg-policy-for-ca \
--override-existing-serviceaccounts \
--approve

kubectl  -n kube-system describe sa cluster-autoscaler > cluster-autoscaler_sa.yaml 



### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
echo "
### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ### ###
 ### 6 - record  Cluster Autoscaler logs and configs  : 
 "
sleep 10
kubectl -n kube-system logs  -l app=cluster-autoscaler > cluster-autoscaler.log
kubectl -n kube-system describe deployment cluster-autoscaler > cluster-autoscaler_describe-deploy.yaml
kubectl -n kube-system describe sa  cluster-autoscaler > cluster-autoscaler_describe-sa.yaml
kubectl -n kube-system  describe configmap cluster-autoscaler-status > cluster-autoscaler_cm.yaml
kubectl -n kube-system  describe pod -l app=cluster-autoscaler > cluster-autoscaler_pod.yaml


# Description = This bash script > With using eksctl , creates a simple eks cluster with ClusterAutoscaler .
# HowToUse = " % ./run.sh| tee -a output.md "
# Duration = Around 15 minutes
# https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/cloudprovider/aws/README.md


Cluster Autoscaler for AWS provides integration with Auto Scaling groups. It enables users to choose from four different options of deployment:

 - One Auto Scaling group
 - Multiple Auto Scaling groups
 - Auto-Discovery
 - Control-plane Node setup

Auto-Discovery is the preferred method to configure Cluster Autoscaler. Click here for more information.

Cluster Autoscaler will attempt to determine the CPU, memory, and GPU resources provided by an Auto Scaling Group based on the instance type specified in its Launch Configuration or Launch Template.

## Configure the ASG
You configure the size of your Auto Scaling group by setting the minimum, maximum, and desired capacity. When we created the cluster we set these settings to 3.
```s
aws autoscaling \
    describe-auto-scaling-groups \
    --query "AutoScalingGroups[? Tags[? (Key=='eks:cluster-name') && Value=='eksworkshop-eksctl']].[AutoScalingGroupName, MinSize, MaxSize,DesiredCapacity]" \
    --output table

-------------------------------------------------------------
|                 DescribeAutoScalingGroups                 |
+-------------------------------------------+----+----+-----+
|  eks-1eb9b447-f3c1-0456-af77-af0bbd65bc9f |  2 |  4 |  3  |
+-------------------------------------------+----+----+-----+
```

Now, increase the maximum capacity to 4 instances

# we need the ASG name
export ASG_NAME=$(aws autoscaling describe-auto-scaling-groups --query "AutoScalingGroups[? Tags[? (Key=='eks:cluster-name') && Value=='eksworkshop-eksctl']].AutoScalingGroupName" --output text)

# increase max capacity up to 4
aws autoscaling \
    update-auto-scaling-group \
    --auto-scaling-group-name ${ASG_NAME} \
    --min-size 3 \
    --desired-capacity 3 \
    --max-size 4

# Check new values
aws autoscaling \
    describe-auto-scaling-groups \
    --query "AutoScalingGroups[? Tags[? (Key=='eks:cluster-name') && Value=='eksworkshop-eksctl']].[AutoScalingGroupName, MinSize, MaxSize,DesiredCapacity]" \
    --output table
IAM roles for service accounts
Click here if you are not familiar with IAM Roles for Service Accounts (IRSA).

With IAM roles for service accounts on Amazon EKS clusters, you can associate an IAM role with a Kubernetes service account. This service account can then provide AWS permissions to the containers in any pod that uses that service account. With this feature, you no longer need to provide extended permissions to the node IAM role so that pods on that node can call AWS APIs.

Enabling IAM roles for service accounts on your cluster

eksctl utils associate-iam-oidc-provider \
    --cluster eksworkshop-eksctl \
    --approve
Creating an IAM policy for your service account that will allow your CA pod to interact with the autoscaling groups.

mkdir ~/environment/cluster-autoscaler

cat <<EoF > ~/environment/cluster-autoscaler/k8s-asg-policy.json
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
  --policy-name k8s-asg-policy \
  --policy-document file://~/environment/cluster-autoscaler/k8s-asg-policy.json
Finally, create an IAM role for the cluster-autoscaler Service Account in the kube-system namespace.

eksctl create iamserviceaccount \
    --name cluster-autoscaler \
    --namespace kube-system \
    --cluster eksworkshop-eksctl \
    --attach-policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/k8s-asg-policy" \
    --approve \
    --override-existing-serviceaccounts
Make sure your service account with the ARN of the IAM role is annotated

kubectl -n kube-system describe sa cluster-autoscaler
Output


Name:                cluster-autoscaler
Namespace:           kube-system
Labels:              <none>
Annotations:         eks.amazonaws.com/role-arn: arn:aws:iam::197520326489:role/eksctl-eksworkshop-eksctl-addon-iamserviceac-Role1-12LNPCGBD6IPZ
Image pull secrets:  <none>
Mountable secrets:   cluster-autoscaler-token-vfk8n
Tokens:              cluster-autoscaler-token-vfk8n
Events:              <none>
Deploy the Cluster Autoscaler (CA)
Deploy the Cluster Autoscaler to your cluster with the following command.

kubectl apply -f https://www.eksworkshop.com/beginner/080_scaling/deploy_ca.files/cluster-autoscaler-autodiscover.yaml
To prevent CA from removing nodes where its own pod is running, we will add the cluster-autoscaler.kubernetes.io/safe-to-evict annotation to its deployment with the following command

kubectl -n kube-system \
    annotate deployment.apps/cluster-autoscaler \
    cluster-autoscaler.kubernetes.io/safe-to-evict="false"
Finally let’s update the autoscaler image to matching kubernetes version

# we need to retrieve the latest docker image available for our EKS version
export K8S_VERSION=$(kubectl version --short | grep 'Server Version:' | sed 's/[^0-9.]*\([0-9.]*\).*/\1/' | cut -d. -f1,2)
export AUTOSCALER_VERSION="1.21.2"

kubectl -n kube-system \
    set image deployment.apps/cluster-autoscaler \
    cluster-autoscaler=us.gcr.io/k8s-artifacts-prod/autoscaling/cluster-autoscaler:v${AUTOSCALER_VERSION}
Watch the logs

kubectl -n kube-system logs -f deployment/cluster-autoscaler
# Z-clusters_ca
creates a simple eks cluster with ClusterAutoscaler

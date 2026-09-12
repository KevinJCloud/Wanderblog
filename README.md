<img width="1393" height="1033" alt="image" src="https://github.com/user-attachments/assets/dd7b012d-16c1-4ca3-8421-2fcdf4ce1e66" />
<img width="1600" height="873" alt="image" src="https://github.com/user-attachments/assets/ac1579ee-c772-421f-9031-cb6a582a9a3c" />
WanderBlog — DevOps CI/CD on AWS EKS

A production-style DevOps implementation for deploying a containerized WanderBlog application on Amazon EKS using Jenkins, Docker, Kubernetes, AWS Load Balancer Controller, EBS CSI Driver, and Argo CD.

The project demonstrates an end-to-end CI/CD and Kubernetes deployment workflow:

Developer
    │
    │ git push
    ▼
 GitHub
    │
    ▼
 Jenkins
    │
    ├── Build Frontend
    ├── Build Backend
    ├── Docker Images
    ├── Push Images
    ├── Update Kubernetes Manifests
    └── Push Manifest Changes
            │
            ▼
          GitHub
            │
            ▼
          Argo CD
            │
            ▼
        Amazon EKS
       ┌────┴────┐
       │         │
    Frontend   Backend
       │         │
       └────┬────┘
            │
            ▼
     AWS Load Balancer
            │
            ▼
          Users
Tech Stack
Technology	Purpose
GitHub	Source Code Management
Jenkins	CI/CD
Docker	Containerization
Docker Hub	Container Image Registry
Kubernetes	Container Orchestration
Amazon EKS	Managed Kubernetes
AWS Load Balancer Controller	ALB provisioning
Application Load Balancer	External traffic
Amazon EBS	Persistent block storage
EBS CSI Driver	Kubernetes → EBS integration
Argo CD	GitOps Continuous Delivery
AWS IAM	Permissions and authentication
eksctl	EKS cluster management
kubectl	Kubernetes administration


Project Structure

Wanderblog/
│
├── frontend/
│   ├── Dockerfile
│   └── ...
│
├── backend/
│   ├── Dockerfile
│   └── ...
│
├── k8s manifest/
│   ├── frontend.yaml
│   ├── backend.yaml
│   ├── ingress.yaml
│   ├── storageclass.yaml
│   ├── pvc.yaml
│   └── ...
│
├── Jenkinsfile
│
└── README.md

1. Prerequisites

Install the following tools on the Jenkins agent or administration machine:

aws --version
kubectl version --client
eksctl version
docker --version
git --version

Configure AWS credentials:

aws configure

Verify:

aws sts get-caller-identity
2. Create the EKS Cluster

Create an EKS cluster using eksctl:

eksctl create cluster \
  --name wanderblog-cluster \
  --region us-east-1 \
  --nodegroup-name wanderblog-nodes \
  --node-type t3.medium \
  --nodes 2 \
  --nodes-min 1 \
  --nodes-max 3

This creates:

EKS Cluster
    │
    ├── Control Plane
    │
    └── Node Group
          ├── EC2 Node
          └── EC2 Node

Verify:

eksctl get cluster --region us-east-1

Check nodes:

kubectl get nodes

Check cluster:

kubectl cluster-info
3. Configure kubectl

If the cluster was created separately or the terminal is using another Kubernetes context:

aws eks update-kubeconfig \
  --region us-east-1 \
  --name wanderblog-cluster

Verify:

kubectl config current-context

Then:

kubectl get nodes
4. Install AWS Load Balancer Controller

The AWS Load Balancer Controller allows Kubernetes Ingress resources to create and manage AWS Application Load Balancers.

Architecture:

Internet
   │
   ▼
AWS ALB
   │
   ▼
AWS Load Balancer Controller
   │
   ▼
Kubernetes Ingress
   │
   ▼
Kubernetes Service
   │
   ▼
Pods
Create IAM Policy

Download the controller IAM policy:

curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.14.1/docs/install/iam_policy.json

Create the IAM policy:

aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam_policy.json

If the policy already exists, retrieve it:

ACCOUNT_ID=$(aws sts get-caller-identity \
  --query Account \
  --output text)

Check:

aws iam get-policy \
  --policy-arn arn:aws:iam::$ACCOUNT_ID:policy/AWSLoadBalancerControllerIAMPolicy
5. Configure IAM Service Account

Create the service account:

eksctl create iamserviceaccount \
  --cluster=wanderblog-cluster \
  --region=us-east-1 \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --attach-policy-arn=arn:aws:iam::$ACCOUNT_ID:policy/AWSLoadBalancerControllerIAMPolicy \
  --override-existing-serviceaccounts \
  --approve

Verify:

kubectl get serviceaccount \
  aws-load-balancer-controller \
  -n kube-system
6. Install AWS Load Balancer Controller

Add the Helm repository:

helm repo add eks https://aws.github.io/eks-charts

Update:

helm repo update

Install:

helm install aws-load-balancer-controller \
  eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=wanderblog-cluster \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=us-east-1

Verify:

kubectl get pods -n kube-system | grep aws-load-balancer

Expected:

aws-load-balancer-controller-xxxxx   1/1   Running
7. EBS CSI Driver

The Amazon EBS CSI Driver allows Kubernetes to dynamically create and attach Amazon EBS volumes to pods.

Architecture:

Kubernetes PVC
      │
      ▼
StorageClass
      │
      ▼
EBS CSI Driver
      │
      ▼
Amazon EBS
      │
      ▼
EC2 Node
      │
      ▼
Pod
8. Create EBS CSI IAM Role

The EBS CSI driver requires AWS permissions to manage EBS volumes.

Create an IAM role with the required EBS CSI permissions.

Example role:

AmazonEKS_EBS_CSI_DriverRole

The role should be associated with the EBS CSI Kubernetes service account.

9. Install EBS CSI Driver as EKS Add-on

Create the add-on:

aws eks create-addon \
  --cluster-name wanderblog-cluster \
  --addon-name aws-ebs-csi-driver \
  --region us-east-1 \
  --service-account-role-arn arn:aws:iam::$ACCOUNT_ID:role/AmazonEKS_EBS_CSI_DriverRole

Check status:

aws eks describe-addon \
  --cluster-name wanderblog-cluster \
  --addon-name aws-ebs-csi-driver \
  --region us-east-1 \
  --query 'addon.status'

Expected:

ACTIVE

Check pods:

kubectl get pods -n kube-system | grep ebs

Expected components include:

ebs-csi-controller-xxxxx
ebs-csi-node-xxxxx
10. Dynamic EBS Provisioning

Dynamic provisioning means Kubernetes automatically creates an EBS volume when a PVC requests storage.

Instead of manually creating:

EBS Volume
     ↓
PV
     ↓
PVC

Kubernetes can automatically provision:

PVC
 ↓
StorageClass
 ↓
EBS CSI Driver
 ↓
EBS Volume
 ↓
PV
11. Create GP3 StorageClass

Create:

apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
parameters:
  type: gp3
  fsType: ext4

Save as:

storageclass.yaml

Apply:

kubectl apply -f storageclass.yaml

Verify:

kubectl get storageclass

Expected:

NAME   PROVISIONER
gp3    ebs.csi.aws.com
12. Create PVC

Example:

apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: wanderblog-pvc
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: gp3
  resources:
    requests:
      storage: 10Gi

Apply:

kubectl apply -f pvc.yaml

Check:

kubectl get pvc

Initially you may see:

STATUS   Pending

This is expected with:

WaitForFirstConsumer

Once a pod uses the PVC:

kubectl get pvc

should show:

STATUS   Bound

Check the automatically created PV:

kubectl get pv
13. Understanding WaitForFirstConsumer

The StorageClass uses:

volumeBindingMode: WaitForFirstConsumer

This prevents Kubernetes from creating the EBS volume before it knows which node/availability zone the pod will run on.

For example:

Pod
 │
 ▼
Node in us-east-1a
 │
 ▼
EBS volume created in us-east-1a

This avoids attaching an EBS volume from the wrong Availability Zone.

14. Kubernetes Ingress / ALB

Create an Ingress for the application.

Example:

apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: wanderblog-ingress
  namespace: default
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
spec:
  ingressClassName: alb
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: frontend
                port:
                  number: 80

Apply:

kubectl apply -f ingress.yaml

Check:

kubectl get ingress

After AWS provisions the ALB:

ADDRESS
xxxxx.us-east-1.elb.amazonaws.com

You can access the application using that address.

15. ALB Architecture

The final traffic flow becomes:

                Internet
                   │
                   ▼
             AWS ALB
                   │
                   ▼
       AWS Load Balancer Controller
                   │
                   ▼
          Kubernetes Ingress
                   │
                   ▼
            Kubernetes Service
                   │
                   ▼
                Pod

For target-type: ip, the ALB can send traffic directly to pod IPs.

16. Argo CD

Argo CD provides GitOps-based continuous delivery.

The desired Kubernetes configuration is stored in Git.

GitHub
   │
   │ Kubernetes manifests
   ▼
Argo CD
   │
   │ Sync
   ▼
EKS
   │
   ├── Deployment
   ├── Service
   ├── Ingress
   └── PVC

Check Argo CD:

kubectl get pods -n argocd

Check services:

kubectl get svc -n argocd

The Argo CD server can remain:

ClusterIP

when exposed through an ALB Ingress.

17. Jenkins CI Pipeline

The Jenkins pipeline performs:

Git Checkout
      │
      ▼
Build Application
      │
      ▼
Docker Build
      │
      ▼
Docker Login
      │
      ▼
Docker Push
      │
      ▼
Update Kubernetes Manifests
      │
      ▼
Git Commit
      │
      ▼
Git Push

Example Docker images:

kevinjcloud/wanderblog-frontend:v1
kevinjcloud/wanderblog-backend:v1
18. Updating Kubernetes Images

Jenkins updates the Kubernetes manifests using sed.

Example:

sed -i \
"s|image:.*kevinjcloud/frontend.*|image: kevinjcloud/wanderblog-frontend:v1|g" \
"k8s manifest/frontend.yaml"

Backend:

sed -i \
"s|image:.*kevinjcloud/backend.*|image: kevinjcloud/wanderblog-backend:v1|g" \
"k8s manifest/backend.yaml"

Then:

git add "k8s manifest/"
git commit -m "Update Kubernetes images"
git push origin HEAD:main
19. Jenkins GitHub Credentials

For GitHub authentication, create a Jenkins credential:

Kind: Username with password
Username: GitHub username
Password: GitHub Personal Access Token
ID: git-token

The PAT goes into the Password field.

Do not place the PAT directly in the Jenkinsfile.

Example:

withCredentials([
    gitUsernamePassword(
        credentialsId: 'git-token',
        gitToolName: 'Default'
    )
]) {
    sh '''
        git add "k8s manifest/"
        git commit -m "Update Kubernetes images" || true
        git push origin HEAD:main
    '''
}
20. Verify Kubernetes Resources

Check all resources:

kubectl get all

Check pods:

kubectl get pods -o wide

Check services:

kubectl get svc

Check ingress:

kubectl get ingress

Check storage:

kubectl get storageclass
kubectl get pvc
kubectl get pv

Check EBS CSI:

kubectl get pods -n kube-system | grep ebs

Check ALB controller:

kubectl get pods -n kube-system | grep aws-load-balancer
21. Troubleshooting
Check pod logs
kubectl logs <pod-name>

For a specific container:

kubectl logs <pod-name> -c <container-name>
Describe a pod
kubectl describe pod <pod-name>
Describe PVC
kubectl describe pvc <pvc-name>
Describe Ingress
kubectl describe ingress <ingress-name>
Check events
kubectl get events --sort-by=.lastTimestamp
Check EBS CSI logs
kubectl logs -n kube-system \
  deployment/ebs-csi-controller
Check ALB controller logs
kubectl logs -n kube-system \
  deployment/aws-load-balancer-controller
22. Delete Application Resources

Delete Kubernetes manifests:

kubectl delete -f "k8s manifest/"

Or individually:

kubectl delete deployment <deployment-name>
kubectl delete service <service-name>
kubectl delete ingress <ingress-name>
kubectl delete pvc <pvc-name>

If the PVC is deleted and the StorageClass reclaim policy is:

Delete

the dynamically provisioned EBS volume can also be deleted.

Always verify AWS EBS volumes after deleting storage resources, especially while learning.

23. Delete ALB

Normally, if the ALB was created by the AWS Load Balancer Controller, deleting the Kubernetes Ingress causes the controller to clean up the ALB and related AWS resources.

kubectl delete ingress wanderblog-ingress

Check:

kubectl get ingress

Then verify in AWS that the ALB has been removed.

24. Delete EKS Cluster

When finished with the project, delete the cluster:

eksctl delete cluster \
  --name wanderblog-cluster \
  --region us-east-1

Check:

eksctl get cluster --region us-east-1

You should no longer see:

wanderblog-cluster
25. Important AWS Cleanup

Before deleting the cluster, check for resources that may continue generating charges.

Check EC2:

aws ec2 describe-instances \
  --region us-east-1

Check EBS volumes:

aws ec2 describe-volumes \
  --region us-east-1

Check Load Balancers:

aws elbv2 describe-load-balancers \
  --region us-east-1

Check EKS:

aws eks list-clusters \
  --region us-east-1

Also check the AWS Console for:

EC2 instances
EBS volumes
Load Balancers
Elastic IPs
NAT Gateways
EKS clusters
CloudFormation stacks

NAT Gateways and unattached EBS volumes are common sources of unexpected AWS charges.

26. Recreate the Environment

If the entire EKS environment is deleted, the basic setup can be recreated with:

eksctl create cluster \
  --name wanderblog-cluster \
  --region us-east-1 \
  --nodegroup-name wanderblog-nodes \
  --node-type t3.medium \
  --nodes 2 \
  --nodes-min 1 \
  --nodes-max 3

Then configure:

aws eks update-kubeconfig \
  --region us-east-1 \
  --name wanderblog-cluster

Install/configure:

1. AWS Load Balancer Controller
2. EBS CSI Driver
3. StorageClass
4. Kubernetes application
5. Ingress
6. Argo CD
7. GitOps application
27. Complete Architecture
                         GitHub
                           │
                           │
                           ▼
                       Jenkins
                           │
             ┌─────────────┴─────────────┐
             │                           │
             ▼                           ▼
        Docker Build                Update YAML
             │                           │
             ▼                           ▼
        Docker Hub                    GitHub
                                         │
                                         ▼
                                      Argo CD
                                         │
                                         ▼
                              ┌──────────────────┐
                              │    Amazon EKS    │
                              │                  │
                              │  ┌────────────┐  │
                              │  │ Kubernetes │  │
                              │  │ Workloads  │  │
                              │  └─────┬──────┘  │
                              │        │         │
                              │        ▼         │
                              │    Services      │
                              │        │         │
                              │        ▼         │
                              │     Ingress      │
                              └────────┬─────────┘
                                       │
                                       ▼
                                  AWS ALB
                                       │
                                       ▼
                                    Users


Storage:

Pod
 │
 ▼
PVC
 │
 ▼
StorageClass (gp3)
 │
 ▼
EBS CSI Driver
 │
 ▼
Amazon EBS
28. Key DevOps Concepts Demonstrated

This project demonstrates practical experience with:

Linux
Git
GitHub
Jenkins
CI/CD
Docker
Docker Hub
Kubernetes
Amazon EKS
Kubernetes Deployments
Kubernetes Services
Kubernetes Ingress
AWS ALB
AWS Load Balancer Controller
IAM
IRSA
EBS CSI Driver
Dynamic Volume Provisioning
StorageClass
PersistentVolume
PersistentVolumeClaim
Argo CD
GitOps
Infrastructure troubleshooting
Production-style deployment workflows
29. Learning Outcome

The project demonstrates an end-to-end DevOps workflow where application code is converted into container images, pushed to a registry, Kubernetes manifests are updated automatically, and Argo CD deploys the desired state to Amazon EKS.

The infrastructure also demonstrates AWS-native Kubernetes integrations including:

EKS
 │
 ├── ALB
 │    └── AWS Load Balancer Controller
 │
 ├── Persistent Storage
 │    └── EBS CSI Driver
 │         └── Dynamic EBS Provisioning
 │
 └── GitOps
      └── Argo CD


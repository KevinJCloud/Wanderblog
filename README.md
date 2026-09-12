# WanderBlog — DevOps CI/CD on AWS EKS

<img width="1393" height="1033" alt="image" src="https://github.com/user-attachments/assets/dd7b012d-16c1-4ca3-8421-2fcdf4ce1e66" />
<img width="1600" height="873" alt="image" src="https://github.com/user-attachments/assets/ac1579ee-c772-421f-9031-cb6a582a9a3c" />


A production-style DevOps implementation for deploying the containerized **WanderBlog** application on **Amazon EKS** using Jenkins, Docker, Kubernetes, AWS Load Balancer Controller, Amazon EBS, and Argo CD.

## Architecture

The project demonstrates an end-to-end CI/CD and Kubernetes deployment workflow:

```text
Developer
    |
    | git push
    v
 GitHub
    |
    v
 Jenkins
    |
    +-- Build Frontend
    +-- Build Backend
    +-- Build Docker Images
    +-- Push Images to Docker Hub
    +-- Update Kubernetes Manifests
    +-- Push Manifest Changes
    |
    v
 GitHub
    |
    v
 Argo CD
    |
    | GitOps Sync
    v
 Amazon EKS
    |
    +------------+
    |            |
    v            v
Frontend       Backend
    |
    v
Kubernetes Service
    |
    v
AWS Application Load Balancer
    |
    v
Users
Tech Stack
Technology	Purpose
GitHub	Source Code Management
Jenkins	CI/CD Automation
Docker	Application Containerization
Docker Hub	Container Image Registry
Kubernetes	Container Orchestration
Amazon EKS	Managed Kubernetes Cluster
AWS Load Balancer Controller	Creates and manages AWS ALB
Application Load Balancer	External application access
Amazon EBS	Persistent Block Storage
EBS CSI Driver	Kubernetes integration with Amazon EBS
StorageClass	Dynamic volume provisioning
PersistentVolumeClaim	Application storage request
Argo CD	GitOps Continuous Delivery
AWS IAM	AWS permissions and authentication
eksctl	EKS cluster management
kubectl	Kubernetes administration
Project Structure
Wanderblog/
|
+-- frontend/
|   +-- Dockerfile
|   +-- ...
|
+-- backend/
|   +-- Dockerfile
|   +-- ...
|
+-- k8s manifest/
|   +-- frontend.yaml
|   +-- backend.yaml
|   +-- ingress.yaml
|   +-- storageclass.yaml
|   +-- pvc.yaml
|   +-- ...
|
+-- Jenkinsfile
|
+-- README.md
1. Prerequisites

Install the following tools:

aws --version
kubectl version --client
eksctl version
docker --version
git --version
helm version

Configure AWS CLI:

aws configure

Verify AWS access:

aws sts get-caller-identity

The AWS user/role should have sufficient permissions to create and manage EKS and related AWS resources.

2. Create the EKS Cluster

Create the EKS cluster using eksctl:

eksctl create cluster \
  --name wanderblog-cluster \
  --region us-east-1 \
  --nodegroup-name wanderblog-nodes \
  --node-type t3.medium \
  --nodes 2 \
  --nodes-min 1 \
  --nodes-max 3

This creates:

Amazon EKS
    |
    +-- Control Plane
    |
    +-- Node Group
         |
         +-- EC2 Node
         |
         +-- EC2 Node

Check the cluster:

eksctl get cluster --region us-east-1

Check nodes:

kubectl get nodes
3. Configure kubectl

Update the local kubeconfig:

aws eks update-kubeconfig \
  --region us-east-1 \
  --name wanderblog-cluster

Verify the current context:

kubectl config current-context

Check the nodes:

kubectl get nodes
4. AWS Load Balancer Controller

The AWS Load Balancer Controller allows Kubernetes Ingress resources to create and manage AWS Application Load Balancers.

Architecture:

Internet
    |
    v
AWS Application Load Balancer
    |
    v
AWS Load Balancer Controller
    |
    v
Kubernetes Ingress
    |
    v
Kubernetes Service
    |
    v
Application Pods
4.1 Create IAM Policy

Download the AWS Load Balancer Controller IAM policy:

curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.14.1/docs/install/iam_policy.json

Get the AWS account ID:

ACCOUNT_ID=$(aws sts get-caller-identity \
  --query Account \
  --output text)

Create the IAM policy:

aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam_policy.json

If the policy already exists, verify it:

aws iam get-policy \
  --policy-arn arn:aws:iam::$ACCOUNT_ID:policy/AWSLoadBalancerControllerIAMPolicy
4.2 Create IAM Service Account
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
4.3 Install Using Helm

Add the Helm repository:

helm repo add eks https://aws.github.io/eks-charts

Update Helm repositories:

helm repo update

Install the controller:

helm install aws-load-balancer-controller \
  eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=wanderblog-cluster \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=us-east-1

Verify:

kubectl get pods -n kube-system | grep aws-load-balancer

The controller pods should show:

Running
5. Install Amazon EBS CSI Driver

The Amazon EBS CSI Driver allows Kubernetes to dynamically create and attach Amazon EBS volumes.

Architecture:

PersistentVolumeClaim
        |
        v
   StorageClass
        |
        v
   EBS CSI Driver
        |
        v
   Amazon EBS Volume
        |
        v
     EC2 Node
        |
        v
       Pod
5.1 Create EBS CSI IAM Role

Create an IAM role for the EBS CSI Driver.

Example role name:

AmazonEKS_EBS_CSI_DriverRole

The role must have the required Amazon EBS CSI permissions.

5.2 Install the EBS CSI Driver Add-on
aws eks create-addon \
  --cluster-name wanderblog-cluster \
  --addon-name aws-ebs-csi-driver \
  --region us-east-1 \
  --service-account-role-arn arn:aws:iam::$ACCOUNT_ID:role/AmazonEKS_EBS_CSI_DriverRole

Check the add-on:

aws eks describe-addon \
  --cluster-name wanderblog-cluster \
  --addon-name aws-ebs-csi-driver \
  --region us-east-1 \
  --query 'addon.status'

Expected:

ACTIVE

Verify the pods:

kubectl get pods -n kube-system | grep ebs

You should see the EBS CSI controller and node components.

6. Dynamic EBS Provisioning

Dynamic provisioning allows Kubernetes to automatically create an Amazon EBS volume when an application requests storage.

Instead of manually creating:

EBS Volume
     |
     v
PersistentVolume
     |
     v
PersistentVolumeClaim

Kubernetes dynamically provisions:

PersistentVolumeClaim
        |
        v
   StorageClass
        |
        v
   EBS CSI Driver
        |
        v
   Amazon EBS Volume
        |
        v
 PersistentVolume
7. Create GP3 StorageClass

Create a file:

storageclass.yaml

Add:

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

Apply:

kubectl apply -f storageclass.yaml

Verify:

kubectl get storageclass

Example:

NAME   PROVISIONER
gp3    ebs.csi.aws.com
8. Create PersistentVolumeClaim

Create:

pvc.yaml

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

Once a pod consumes the PVC:

kubectl get pvc

The PVC should become:

Bound

Check the dynamically created PV:

kubectl get pv
9. Why WaitForFirstConsumer?

The StorageClass uses:

volumeBindingMode: WaitForFirstConsumer

This allows Kubernetes to determine where the pod will run before creating the EBS volume.

For example:

Pod
 |
 v
EC2 Node
 |
 | Availability Zone: us-east-1a
 v
EBS Volume
 |
 +-- us-east-1a

This is important because EBS volumes are associated with a specific Availability Zone.

10. Kubernetes Ingress and ALB

Create an Ingress:

apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: wanderblog-ingress
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

The AWS Load Balancer Controller should provision an AWS Application Load Balancer.

Check the ALB address:

kubectl get ingress

Example:

ADDRESS
xxxxx.us-east-1.elb.amazonaws.com
11. Argo CD

Argo CD is used for GitOps-based continuous delivery.

The Kubernetes manifests are stored in GitHub and Argo CD continuously compares the desired state in Git with the actual state in the EKS cluster.

GitHub
   |
   | Kubernetes manifests
   v
Argo CD
   |
   | Sync
   v
Amazon EKS
   |
   +-- Deployment
   +-- Service
   +-- Ingress
   +-- PVC

Check Argo CD:

kubectl get pods -n argocd

Check services:

kubectl get svc -n argocd
12. Jenkins CI Pipeline

The Jenkins pipeline automates application build and Docker image delivery.

Pipeline flow:

Git Checkout
     |
     v
Build Frontend
     |
     v
Build Backend
     |
     v
Docker Build
     |
     v
Docker Login
     |
     v
Docker Push
     |
     v
Update Kubernetes Manifests
     |
     v
Git Commit
     |
     v
Git Push

Example Docker images:

kevinjcloud/wanderblog-frontend:v1
kevinjcloud/wanderblog-backend:v1
13. GitHub Authentication in Jenkins

Create a Jenkins credential:

Kind: Username with password
Username: GitHub username
Password: GitHub Personal Access Token
ID: git-token

The GitHub Personal Access Token should be stored in the Password field.

Do not hard-code the token in the Jenkinsfile.

Example:

withCredentials([
    gitUsernamePassword(
        credentialsId: 'git-token',
        gitToolName: 'Default'
    )
]) {
    sh '''
        git config user.name "KevinJCloud"
        git config user.email "jobinjkumar@gmail.com"

        git add "k8s manifest/"

        git commit -m "Update Kubernetes images" || true

        git push origin HEAD:main
    '''
}
14. Updating Kubernetes Images

Jenkins updates the image references in the Kubernetes manifests.

Frontend:

sed -i \
"s|image:.*kevinjcloud/frontend.*|image: kevinjcloud/wanderblog-frontend:v1|g" \
"k8s manifest/frontend.yaml"

Backend:

sed -i \
"s|image:.*kevinjcloud/backend.*|image: kevinjcloud/wanderblog-backend:v1|g" \
"k8s manifest/backend.yaml"

Jenkins then commits the changes:

git add "k8s manifest/"
git commit -m "Update Kubernetes images"
git push origin HEAD:main

Argo CD detects the Git change and synchronizes the updated manifests to EKS.

15. Verify Kubernetes Resources

Check workloads:

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

Check AWS Load Balancer Controller:

kubectl get pods -n kube-system | grep aws-load-balancer
16. Troubleshooting

Check pod logs:

kubectl logs <pod-name>

Describe a pod:

kubectl describe pod <pod-name>

Describe a PVC:

kubectl describe pvc <pvc-name>

Describe an Ingress:

kubectl describe ingress <ingress-name>

Check Kubernetes events:

kubectl get events --sort-by=.lastTimestamp

Check EBS CSI logs:

kubectl logs -n kube-system deployment/ebs-csi-controller

Check AWS Load Balancer Controller logs:

kubectl logs -n kube-system deployment/aws-load-balancer-controller
17. Delete Kubernetes Application Resources

Delete the resources defined in the manifest directory:

kubectl delete -f "k8s manifest/"

Or delete individual resources:

kubectl delete deployment <deployment-name>
kubectl delete service <service-name>
kubectl delete ingress <ingress-name>
kubectl delete pvc <pvc-name>
18. Delete the ALB

If the ALB was created by the AWS Load Balancer Controller, delete the Kubernetes Ingress:

kubectl delete ingress wanderblog-ingress

The controller should remove the associated AWS Load Balancer resources.

Verify:

kubectl get ingress

Also verify the ALB in the AWS Console.

19. Delete the EKS Cluster

When finished with the project, delete the EKS cluster:

eksctl delete cluster \
  --name wanderblog-cluster \
  --region us-east-1

Verify:

eksctl get cluster --region us-east-1
20. AWS Resource Cleanup

After deleting the cluster, verify that no unwanted AWS resources remain.

Check EKS clusters:

aws eks list-clusters \
  --region us-east-1

Check EC2 instances:

aws ec2 describe-instances \
  --region us-east-1

Check EBS volumes:

aws ec2 describe-volumes \
  --region us-east-1

Check Application Load Balancers:

aws elbv2 describe-load-balancers \
  --region us-east-1

Also check the AWS Console for:

EKS clusters
EC2 instances
EBS volumes
Load Balancers
Elastic IPs
NAT Gateways
CloudFormation stacks

Important: NAT Gateways and unattached EBS volumes can continue generating AWS charges even after the Kubernetes cluster is deleted.

21. Recreate the Environment

The EKS environment can be recreated when required.

Create the cluster:

eksctl create cluster \
  --name wanderblog-cluster \
  --region us-east-1 \
  --nodegroup-name wanderblog-nodes \
  --node-type t3.medium \
  --nodes 2 \
  --nodes-min 1 \
  --nodes-max 3

Configure kubectl:

aws eks update-kubeconfig \
  --region us-east-1 \
  --name wanderblog-cluster

Then configure:

AWS Load Balancer Controller
EBS CSI Driver
GP3 StorageClass
Kubernetes workloads
Kubernetes Ingress
Argo CD
Argo CD Application
22. Final Architecture
                         GitHub
                           |
                           |
                           v
                       Jenkins CI
                           |
              +------------+------------+
              |                         |
              v                         v
        Docker Images             Kubernetes
              |                    Manifests
              v                         |
         Docker Hub                    GitHub
                                        |
                                        v
                                    Argo CD
                                        |
                                        | GitOps Sync
                                        v
                               +------------------+
                               |    Amazon EKS    |
                               |                  |
                               |  +------------+  |
                               |  | Frontend   |  |
                               |  | Deployment |  |
                               |  +------------+  |
                               |        |         |
                               |        v         |
                               |    Service       |
                               |                  |
                               |  +------------+  |
                               |  | Backend    |  |
                               |  | Deployment |  |
                               |  +------------+  |
                               |                  |
                               |  +------------+  |
                               |  | Ingress    |  |
                               |  +-----+------+  |
                               +--------|---------+
                                        |
                                        v
                             AWS Application
                              Load Balancer
                                        |
                                        v
                                      Users


Persistent Storage:

Pod
 |
 v
PVC
 |
 v
GP3 StorageClass
 |
 v
EBS CSI Driver
 |
 v
Amazon EBS
23. Key DevOps Concepts Demonstrated

This project demonstrates practical experience with:

Linux
Git and GitHub
Jenkins CI/CD
Docker
Docker Hub
Kubernetes
Amazon EKS
Kubernetes Deployments
Kubernetes Services
Kubernetes Ingress
AWS Application Load Balancer
AWS Load Balancer Controller
AWS IAM
IAM Service Accounts
Amazon EBS
EBS CSI Driver
Dynamic EBS Provisioning
StorageClass
PersistentVolume
PersistentVolumeClaim
Argo CD
GitOps
Infrastructure Automation
CI/CD Automation
Kubernetes Troubleshooting
AWS Resource Management
Conclusion

WanderBlog demonstrates an end-to-end DevOps workflow starting from source-code changes in GitHub and ending with an updated application running on Amazon EKS.

The project combines CI/CD, containerization, Kubernetes orchestration, AWS networking, persistent storage, and GitOps into a single deployment workflow.

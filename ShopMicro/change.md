# Infrastructure Changes - Destroy & Recreate

This document outlines what will change when we destroy the current infrastructure and recreate it for the capstone evidence collection.

## What Will Change After Destroy & Rebuild

### 1. AWS Resources (Completely Destroyed & Recreated)

#### Networking
- **VPC**: New VPC ID will be assigned
- **Subnets**: New subnet IDs (2 public, 2 private across availability zones)
- **Internet Gateway**: New IGW ID
- **NAT Gateway**: New NAT Gateway with new Elastic IP
- **Route Tables**: New route table IDs for public and private subnets
- **Security Groups**: New security group IDs for nodes and internal communication

#### Compute
- **EC2 Instances**:
  - New K8s master node with **different public IP address**
  - New K8s worker node with **different public IP address**
  - New SSH key fingerprints
  - K3s cluster will be reinstalled from scratch

#### Container Registry
- **ECR Repositories**: Recreated (may lose existing images unless they're tagged)
  - `dev-shopmicro-backend`
  - `dev-shopmicro-frontend`
  - `dev-shopmicro-ml-service`

#### IAM & OIDC
- **GitHub Actions IAM Role**: New role ARN (will need to update GitHub secret)
- **OIDC Provider**: Recreated with same configuration

### 2. Kubernetes Cluster (Completely Rebuilt)

#### Cluster State
- **K3s Installation**: Fresh installation
- **Cluster Certificates**: New TLS certificates generated
- **Node Names**: New hostnames based on new private IPs
- **Cluster Token**: New K3s token

#### Kubernetes Resources (Need Redeployment)
- **Namespaces**: `shopmicro`, `argocd`, `monitoring` - need to be recreated
- **ArgoCD**: Need to reinstall
- **Application Deployments**: All pods need to be redeployed
- **ConfigMaps & Secrets**: Need to be reapplied
- **Network Policies**: Need to be reapplied
- **HPA**: Need to be reconfigured
- **Monitoring Stack**: Prometheus & Grafana need reinstallation

### 3. What Will Stay The Same

#### Code & Configuration
- ✅ Application source code (backend, frontend, ml-service)
- ✅ Kubernetes manifests in `k8s/` directory
- ✅ Terraform modules and configuration
- ✅ CI/CD pipeline configuration
- ✅ Observability configurations (Prometheus, Grafana dashboards)
- ✅ Network policies and security configurations

#### AWS Account Resources
- ✅ S3 bucket for Terraform state (if using remote backend)
- ✅ DynamoDB table for state locking
- ✅ GitHub OIDC provider configuration (recreated with same settings)

### 4. Required Updates After Rebuild

#### Immediate Actions
1. **Fetch New Kubeconfig**: Run `make ev-2a-fetch-config` with new master IP
2. **Update GitHub Secret**: Update `GH_ACTIONS_ROLE_ARN` with new role ARN
3. **Trigger CI/CD**: Push to rebuild and push Docker images to new ECR repos
4. **Update DNS/Endpoints**: If using any hardcoded IPs, update them

#### Kubernetes Redeployment
1. Install ArgoCD: `make ev-4-argocd`
2. Apply manifests: `make ev-5-manifests`
3. Deploy observability: `make ev-10-observ`
4. Wait for pods to be running and pull images from ECR

### 5. Impact on Evidence Collection

#### Evidence Screenshots That Need Retaking
- ✅ Screenshot 2: Terraform apply output (new resource IDs)
- ✅ Screenshot 3: Kubernetes nodes (new node names and IPs)
- ✅ Screenshot 4: ArgoCD installation
- ✅ Screenshot 6: Pod status (new pod names with different hashes)
- ✅ Screenshot 10-13: Observability (new Prometheus/Grafana endpoints)

#### Evidence That Remains Valid
- ✅ Screenshot 1: CI/CD pipeline runs (if captured before destroy)
- ✅ Code-based evidence: Network policies, HPA configs, manifests
- ✅ Documentation: README, runbooks, architecture diagrams

### 6. Estimated Rebuild Time

| Phase | Duration |
|-------|----------|
| Terraform Apply | 3-5 minutes |
| K3s Installation | 2-3 minutes |
| Kubeconfig Fetch | < 1 minute |
| ArgoCD Install | 2-3 minutes |
| Application Deployment | 2-3 minutes |
| Image Pull & Pod Startup | 3-5 minutes |
| Observability Setup | 2-3 minutes |
| **Total** | **15-20 minutes** |

### 7. Pre-Destroy Checklist

Before running `make tf-destroy`:
- [ ] Verify all evidence screenshots are captured
- [ ] Verify CI/CD pipeline has run successfully
- [ ] Document current resource IDs for comparison
- [ ] Ensure Terraform state is backed up
- [ ] Note down current public IPs

### 8. Post-Rebuild Verification

After recreation:
- [ ] Verify Terraform outputs match expected configuration
- [ ] Verify K3s cluster is healthy (`kubectl get nodes`)
- [ ] Verify all pods are running (`kubectl get pods -A`)
- [ ] Verify ArgoCD is accessible
- [ ] Verify Prometheus is scraping metrics
- [ ] Verify Grafana dashboards are loading
- [ ] Test application endpoints

## Commands Summary

### Destroy
```bash
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_DEFAULT_REGION="us-east-1"
make tf-destroy
```

### Rebuild & Deploy
```bash
# 1. Apply infrastructure
make ev-2-tf-apply

# 2. Wait 2-3 minutes for K3s installation

# 3. Fetch kubeconfig
make ev-2a-fetch-config
export KUBECONFIG=$(pwd)/aws-kubeconfig.yaml

# 4. Verify nodes
make ev-3-nodes

# 5. Install ArgoCD
make ev-4-argocd

# 6. Apply manifests
make ev-5-manifests

# 7. Deploy observability
make ev-10-observ

# 8. Verify everything
make ev-6-pods
make ev-7-hpa
make ev-8-network
```

---

**Note**: This is a learning environment. In production, you would use:
- Blue/green deployments
- Infrastructure versioning
- Backup and restore procedures
- Rolling updates instead of complete teardown
- Persistent volume backups
- Database migration strategies

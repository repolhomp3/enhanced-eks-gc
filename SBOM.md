# Software Bill of Materials (SBOM)
# Enhanced EKS Cluster - us-gov-west-1

**Version:** 1.0.0  
**Date:** 2024-01-15  
**Format:** SPDX-2.3 Compatible

---

## Infrastructure as Code Components

### Terraform
- **Component:** Terraform CLI
- **Version:** >= 1.0
- **Source:** HashiCorp
- **License:** MPL-2.0
- **Purpose:** Infrastructure provisioning

### Terraform Providers
| Provider | Version | Source | License |
|----------|---------|--------|---------|
| aws | ~> 5.0 | hashicorp/aws | MPL-2.0 |
| kubernetes | ~> 2.23 | hashicorp/kubernetes | MPL-2.0 |
| helm | ~> 2.11 | hashicorp/helm | MPL-2.0 |

---

## AWS Managed Services

### EKS Control Plane
- **Component:** Amazon EKS
- **Version:** 1.34
- **Managed By:** AWS
- **Security Updates:** Automatic (AWS-managed)
- **Compliance:** FedRAMP High, HIPAA, PCI-DSS

### EKS Add-ons (AWS-Managed)
| Add-on | Version | CVE Tracking | Update Frequency |
|--------|---------|--------------|------------------|
| kube-proxy | v1.34.0-eksbuild.1 | AWS Security Bulletins | Automatic |
| vpc-cni | v1.19.0-eksbuild.1 | AWS Security Bulletins | Automatic |
| coredns | v1.11.3-eksbuild.2 | AWS Security Bulletins | Automatic |
| aws-ebs-csi-driver | v1.37.0-eksbuild.1 | AWS Security Bulletins | Automatic |
| aws-efs-csi-driver | v2.1.1-eksbuild.1 | AWS Security Bulletins | Automatic |
| aws-mountpoint-s3-csi-driver | v1.10.0-eksbuild.1 | AWS Security Bulletins | Automatic |
| adot | v0.102.1-eksbuild.1 | AWS Security Bulletins | Automatic |

**CVE Monitoring:** https://aws.amazon.com/security/security-bulletins/

---

## AI/ML Components (Optional)

### Amazon Bedrock
- **Component:** Bedrock Agent Runtime
- **Model:** anthropic.claude-3-5-sonnet-20241022-v2:0
- **Managed By:** AWS
- **Security Updates:** Automatic (AWS-managed)
- **Compliance:** FedRAMP Moderate (in process for High)
- **Purpose:** AI-driven EKS operations

### Lambda Functions
| Function | Runtime | Purpose | Source |
|----------|---------|---------|--------|
| mcp-server | Python 3.12 | MCP protocol handler | lambda/mcp-server/ |
| bedrock-agent-trigger | Python 3.12 | EventBridge handler | lambda/bedrock-agent-trigger/ |

**Python Dependencies:**
- boto3 >= 1.34.0 (AWS SDK)
- kubernetes >= 29.0.0 (K8s client)

**CVE Tracking:** 
- AWS Lambda runtime: AWS Security Bulletins
- Python packages: https://pypi.org/security/

---

## Third-Party Helm Charts

### Istio Service Mesh
- **Chart Version:** 1.24.0
- **Source:** https://istio-release.storage.googleapis.com/charts
- **Container Images:**
  - `istio/pilot:1.24.0`
  - `istio/proxyv2:1.24.0`
- **License:** Apache-2.0
- **CVE Tracking:** https://istio.io/latest/news/security/
- **Update Responsibility:** User-managed

### KEDA
- **Chart Version:** 2.15.1
- **Source:** https://kedacore.github.io/charts
- **Container Images:**
  - `ghcr.io/kedacore/keda:2.15.1`
  - `ghcr.io/kedacore/keda-metrics-apiserver:2.15.1`
- **License:** Apache-2.0
- **CVE Tracking:** https://github.com/kedacore/keda/security/advisories
- **Update Responsibility:** User-managed

### Kiali
- **Chart Version:** 1.89.0
- **Source:** https://kiali.org/helm-charts
- **Container Images:**
  - `quay.io/kiali/kiali:v1.89.0`
- **License:** Apache-2.0
- **CVE Tracking:** https://kiali.io/news/security-bulletins/
- **Update Responsibility:** User-managed

### Prometheus
- **Chart Version:** 25.27.0
- **Source:** https://prometheus-community.github.io/helm-charts
- **Container Images:**
  - `quay.io/prometheus/prometheus:v2.54.0`
  - `quay.io/prometheus/alertmanager:v0.27.0`
  - `quay.io/prometheus/node-exporter:v1.8.2`
- **License:** Apache-2.0
- **CVE Tracking:** https://prometheus.io/docs/operating/security/
- **Update Responsibility:** User-managed

### AWS Load Balancer Controller
- **Chart Version:** 1.8.1
- **Source:** https://aws.github.io/eks-charts
- **Container Images:**
  - `public.ecr.aws/eks/aws-load-balancer-controller:v2.8.1`
- **License:** Apache-2.0
- **CVE Tracking:** https://github.com/kubernetes-sigs/aws-load-balancer-controller/security
- **Update Responsibility:** User-managed

### Metrics Server
- **Chart Version:** 3.12.1
- **Source:** https://kubernetes-sigs.github.io/metrics-server/
- **Container Images:**
  - `registry.k8s.io/metrics-server/metrics-server:v0.7.1`
- **License:** Apache-2.0
- **CVE Tracking:** https://github.com/kubernetes-sigs/metrics-server/security
- **Update Responsibility:** User-managed

---

## Container Image Registry Sources

| Registry | Purpose | Trust Level |
|----------|---------|-------------|
| public.ecr.aws | AWS official images | High (AWS-signed) |
| docker.io/istio | Istio official images | High (Istio-signed) |
| ghcr.io/kedacore | KEDA official images | High (KEDA-signed) |
| quay.io/kiali | Kiali official images | Medium (verify signatures) |
| quay.io/prometheus | Prometheus official images | High (CNCF project) |
| registry.k8s.io | Kubernetes official images | High (K8s-signed) |

---

## Vulnerability Scanning

### Recommended Tools
1. **Trivy** - Container and IaC scanning
2. **Checkov** - Terraform security scanning
3. **Snyk** - Dependency vulnerability scanning
4. **AWS Inspector** - Runtime vulnerability assessment

### Scanning Commands
```bash
# Scan Terraform configuration
trivy config . --severity HIGH,CRITICAL

# Scan Helm chart images
trivy image istio/pilot:1.24.0
trivy image ghcr.io/kedacore/keda:2.15.1
trivy image quay.io/prometheus/prometheus:v2.54.0

# Generate SBOM for container images
syft packages istio/pilot:1.24.0 -o spdx-json > istio-sbom.json
```

---

## Update Policy

### AWS-Managed Components
- **Frequency:** Automatic security patches
- **Notification:** AWS Security Bulletins
- **Action Required:** Review and approve EKS add-on updates

### User-Managed Components (Helm Charts)
- **Frequency:** Monthly review recommended
- **Process:**
  1. Check upstream security advisories
  2. Review changelog for security fixes
  3. Test in non-production environment
  4. Update terraform.tfvars with new versions
  5. Apply with `terraform apply`

### Critical CVE Response
- **Timeline:** Patch within 24-48 hours
- **Process:**
  1. Assess impact and exploitability
  2. Test patch in staging
  3. Emergency change approval
  4. Deploy to production
  5. Verify and document

---

## Compliance & Attestation

### SBOM Generation
```bash
# Generate infrastructure SBOM
terraform-docs json . > infrastructure-sbom.json

# Generate container SBOMs
for image in $(grep "image:" -r . | awk '{print $2}'); do
  syft packages $image -o spdx-json > sbom-$(echo $image | tr '/:' '-').json
done
```

### Attestation
- **Terraform State:** Signed and stored in encrypted S3
- **Container Images:** Verify signatures before deployment
- **Helm Charts:** Verify chart signatures with `helm verify`

---

## Security Contacts

### Upstream Security Teams
- **AWS Security:** https://aws.amazon.com/security/vulnerability-reporting/
- **Istio Security:** security@istio.io
- **KEDA Security:** https://github.com/kedacore/keda/security/policy
- **Prometheus Security:** prometheus-team@googlegroups.com

### Internal Contacts
- **Security Team:** security@example.com
- **Infrastructure Team:** infra@example.com
- **On-Call:** oncall@example.com

---

## Audit Trail

| Date | Component | Version | Action | Reason |
|------|-----------|---------|--------|--------|
| 2024-01-15 | Initial | 1.0.0 | Created | Initial deployment |
| | | | | |

---

## License Summary

| License | Components |
|---------|------------|
| Apache-2.0 | Istio, KEDA, Kiali, Prometheus, AWS LB Controller, Metrics Server |
| MPL-2.0 | Terraform, Terraform Providers |
| AWS Customer Agreement | EKS, EKS Add-ons |

---

**Last Updated:** 2024-01-15  
**Next Review:** 2024-02-15  
**Maintained By:** Infrastructure Team

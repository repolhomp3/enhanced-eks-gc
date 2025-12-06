# Enhanced EKS Cluster - us-gov-west-1

Production-ready EKS cluster with Auto Mode, KEDA, and Istio for mTLS.

![Architecture Diagram](enhanced-eks-gc.png)

## Features

- **EKS Auto Mode**: Automated node provisioning and management
- **Region**: us-gov-west-1 (AWS GovCloud)
- **High Availability**: 3 AZs with public/private subnets
- **Add-ons Installed**:
  - kube-proxy
  - vpc-cni
  - coredns
  - aws-ebs-csi-driver
  - aws-efs-csi-driver
  - aws-mountpoint-s3-csi-driver
  - ADOT (AWS Distro for OpenTelemetry) with X-Ray integration
  - Istio (service mesh with mTLS)
- **KEDA**: Kubernetes Event-driven Autoscaling
- **AWS Load Balancer Controller**: Automatic ALB/NLB provisioning

## Cost Estimate

**us-gov-west-1 GovCloud Pricing:**

| Duration | Estimated Cost | Notes |
|----------|----------------|-------|
| **2 Days** | $53-62 | Testing/POC |
| **1 Month** | $800-1,200 | Light production workload |
| **1 Month** | $1,200-1,800 | Moderate production workload |

**Key Cost Components:**
- EKS Control Plane: $87.60/month (fixed)
- NAT Gateway: $98.55/month (1 gateway for cost savings)
- Auto Mode Compute: $500-800/month (scales with workload)
- Storage, observability, load balancers: ~$100/month

**Cost Optimization:**
- Single NAT Gateway saves ~$200/month vs 3 NAT Gateways
- Auto Mode optimizes instance selection automatically
- Use Savings Plans for 30-40% compute savings

For detailed pricing, use the [AWS Pricing Calculator](https://calculator.aws).

## Prerequisites

- AWS CLI configured for us-gov-west-1
- Terraform >= 1.0
- kubectl

## Deployment

```bash
terraform init
terraform plan
terraform apply
```

## Configure kubectl

```bash
aws eks update-kubeconfig --region us-gov-west-1 --name enhanced-eks-cluster
```

## Verify Installation

```bash
# Check cluster
kubectl get nodes

# Check add-ons
kubectl get pods -n kube-system

# Check KEDA
kubectl get pods -n keda

# Check Istio
kubectl get pods -n istio-system

# Check AWS Load Balancer Controller
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Check Kiali
kubectl get pods -n istio-system -l app=kiali

# Check Prometheus
kubectl get pods -n prometheus
```

## Access Kiali Dashboard

```bash
# Port-forward to access Kiali UI
kubectl port-forward -n istio-system svc/kiali-server 20001:20001

# Open browser to http://localhost:20001
```

## Auto Mode

EKS Auto Mode automatically manages:
- Node provisioning and scaling
- Compute capacity optimization
- System pod placement
- Storage provisioning

## Istio Service Mesh

Istio is installed with automatic mTLS enabled for secure service-to-service communication. Includes:
- Istio base (CRDs)
- Istiod (control plane)
- Istio Ingress Gateway (LoadBalancer)

## KEDA Autoscaling

KEDA enables event-driven autoscaling based on various metrics and event sources.

## Kiali Service Mesh Visualization

Kiali provides real-time visualization of your Istio service mesh:
- Service topology graph
- Traffic flow and metrics
- Health status of services
- Configuration validation
- Distributed tracing integration

Access via port-forward: `kubectl port-forward -n istio-system svc/kiali-server 20001:20001`

## AWS Load Balancer Controller

Automatically provisions ALBs and NLBs for Kubernetes Ingress and Service resources:

```yaml
# ALB Ingress example
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
spec:
  ingressClassName: alb
  rules:
  - host: app.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: my-service
            port:
              number: 80
```

## Distributed Tracing with ADOT and AWS X-Ray

ADOT (AWS Distro for OpenTelemetry) is installed and configured to send traces to AWS X-Ray.

### Setup Tracing in Your Application

**1. Deploy ADOT Collector ConfigMap:**

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: adot-collector-config
  namespace: default
data:
  config.yaml: |
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318
    processors:
      batch:
        timeout: 10s
    exporters:
      awsxray:
        region: us-gov-west-1
    service:
      pipelines:
        traces:
          receivers: [otlp]
          processors: [batch]
          exporters: [awsxray]
```

**2. Add ADOT Collector Sidecar to Your Pods:**

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
spec:
  containers:
  - name: app
    image: my-app:latest
    env:
    - name: OTEL_EXPORTER_OTLP_ENDPOINT
      value: "http://localhost:4317"
  
  - name: adot-collector
    image: public.ecr.aws/aws-observability/aws-otel-collector:latest
    env:
    - name: AWS_REGION
      value: us-gov-west-1
    command:
    - "/awscollector"
    - "--config=/conf/config.yaml"
    volumeMounts:
    - name: adot-config
      mountPath: /conf
  
  volumes:
  - name: adot-config
    configMap:
      name: adot-collector-config
```

**3. Instrument Your Application:**

Python example:
```python
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter

trace.set_tracer_provider(TracerProvider())
otlp_exporter = OTLPSpanExporter(endpoint="http://localhost:4317", insecure=True)
trace.get_tracer_provider().add_span_processor(BatchSpanProcessor(otlp_exporter))

tracer = trace.get_tracer(__name__)

with tracer.start_as_current_span("my-operation"):
    # Your code here
    pass
```

**4. View Traces in AWS X-Ray Console:**

- Navigate to AWS X-Ray in us-gov-west-1
- View Service Map for topology
- View Traces for request details
- Analyze latency and errors

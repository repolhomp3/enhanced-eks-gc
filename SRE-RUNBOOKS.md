# SRE Runbooks - AI-Driven Operations

Automated runbooks for Amazon Bedrock AI agents via Model Context Protocol (MCP).

## MCP Server Integration

**Architecture:**
```
Bedrock Claude ↔ MCP Client ↔ MCP Server ↔ EKS Cluster
                                    ↓
                            AWS APIs (EKS, CloudWatch, GuardDuty)
```

**MCP Server Endpoints:**
- `kubectl://` - Kubernetes operations
- `aws://cloudwatch` - Metrics and logs
- `aws://guardduty` - Security findings
- `aws://xray` - Distributed traces

## Runbook 1: Pod CrashLoopBackOff

**Trigger:** CloudWatch alarm `PodCrashLooping`

**AI Execution:**
```json
{
  "runbook": "pod-crash",
  "steps": [
    {
      "action": "kubectl://get",
      "resource": "pod",
      "namespace": "${namespace}",
      "name": "${pod_name}"
    },
    {
      "action": "kubectl://logs",
      "resource": "pod",
      "namespace": "${namespace}",
      "name": "${pod_name}",
      "tail": 100
    },
    {
      "action": "kubectl://describe",
      "resource": "pod",
      "namespace": "${namespace}",
      "name": "${pod_name}"
    },
    {
      "action": "analyze",
      "model": "anthropic.claude-3-5-sonnet-20241022-v2:0",
      "prompt": "Analyze pod crash: logs=${logs}, events=${events}"
    },
    {
      "action": "remediate",
      "conditions": [
        {"if": "OOMKilled", "then": "increase_memory"},
        {"if": "ImagePullBackOff", "then": "check_ecr_permissions"},
        {"if": "CrashLoopBackOff", "then": "rollback_deployment"}
      ]
    }
  ]
}
```

**Manual Override:**
```bash
# Stop AI remediation
aws bedrock stop-model-invocation --invocation-id ${invocation_id}

# Resume manual control
kubectl rollout undo deployment/${deployment} -n ${namespace}
```

## Runbook 2: High Memory Usage

**Trigger:** Prometheus alert `NodeMemoryPressure > 85%`

**AI Execution:**
```json
{
  "runbook": "high-memory",
  "steps": [
    {
      "action": "kubectl://top",
      "resource": "nodes"
    },
    {
      "action": "kubectl://top",
      "resource": "pods",
      "all_namespaces": true,
      "sort_by": "memory"
    },
    {
      "action": "aws://cloudwatch/get-metric-statistics",
      "namespace": "ContainerInsights",
      "metric": "node_memory_utilization",
      "period": 300,
      "statistics": ["Average", "Maximum"]
    },
    {
      "action": "analyze",
      "model": "anthropic.claude-3-5-sonnet-20241022-v2:0",
      "prompt": "Memory pressure analysis: node_metrics=${node_metrics}, pod_metrics=${pod_metrics}"
    },
    {
      "action": "remediate",
      "conditions": [
        {"if": "memory_leak_detected", "then": "restart_pod"},
        {"if": "capacity_exceeded", "then": "scale_out"},
        {"if": "memory_limit_missing", "then": "add_resource_limits"}
      ]
    }
  ]
}
```

## Runbook 3: GuardDuty Critical Finding

**Trigger:** EventBridge rule `GuardDutyCriticalFinding`

**AI Execution:**
```json
{
  "runbook": "guardduty-critical",
  "steps": [
    {
      "action": "aws://guardduty/get-findings",
      "finding_ids": ["${finding_id}"]
    },
    {
      "action": "analyze",
      "model": "anthropic.claude-3-5-sonnet-20241022-v2:0",
      "prompt": "Security threat analysis: finding=${finding}, severity=${severity}"
    },
    {
      "action": "isolate",
      "conditions": [
        {"if": "crypto_mining", "then": "delete_pod"},
        {"if": "privilege_escalation", "then": "revoke_rbac"},
        {"if": "malware_detected", "then": "quarantine_node"}
      ]
    },
    {
      "action": "notify",
      "channels": ["sns", "pagerduty"],
      "severity": "P0"
    }
  ]
}
```

**Isolation Commands:**
```bash
# Quarantine node (AI-executed)
kubectl cordon ${node_name}
kubectl drain ${node_name} --ignore-daemonsets --delete-emptydir-data

# Delete compromised pod
kubectl delete pod ${pod_name} -n ${namespace} --force --grace-period=0

# Revoke RBAC
kubectl delete rolebinding ${binding_name} -n ${namespace}
```

## Runbook 4: Failed Deployment

**Trigger:** Deployment rollout timeout (10 minutes)

**AI Execution:**
```json
{
  "runbook": "failed-deployment",
  "steps": [
    {
      "action": "kubectl://rollout/status",
      "resource": "deployment",
      "namespace": "${namespace}",
      "name": "${deployment}"
    },
    {
      "action": "kubectl://get",
      "resource": "replicaset",
      "namespace": "${namespace}",
      "selector": "app=${app}"
    },
    {
      "action": "kubectl://describe",
      "resource": "replicaset",
      "namespace": "${namespace}",
      "name": "${new_replicaset}"
    },
    {
      "action": "analyze",
      "model": "anthropic.claude-3-5-sonnet-20241022-v2:0",
      "prompt": "Deployment failure: events=${events}, pod_status=${pod_status}"
    },
    {
      "action": "remediate",
      "conditions": [
        {"if": "image_not_found", "then": "notify_dev_team"},
        {"if": "insufficient_resources", "then": "scale_cluster"},
        {"if": "health_check_failed", "then": "rollback"}
      ]
    }
  ]
}
```

## Runbook 5: Istio Service Mesh Degradation

**Trigger:** Kiali alert `ServiceMeshDegraded`

**AI Execution:**
```json
{
  "runbook": "istio-degraded",
  "steps": [
    {
      "action": "kubectl://get",
      "resource": "pods",
      "namespace": "istio-system"
    },
    {
      "action": "kubectl://logs",
      "resource": "deployment/istiod",
      "namespace": "istio-system",
      "tail": 200
    },
    {
      "action": "aws://xray/get-service-graph",
      "start_time": "${now - 15m}",
      "end_time": "${now}"
    },
    {
      "action": "analyze",
      "model": "anthropic.claude-3-5-sonnet-20241022-v2:0",
      "prompt": "Service mesh analysis: istiod_logs=${logs}, service_graph=${graph}"
    },
    {
      "action": "remediate",
      "conditions": [
        {"if": "istiod_crash", "then": "restart_istiod"},
        {"if": "envoy_config_error", "then": "validate_virtualservices"},
        {"if": "mtls_failure", "then": "rotate_certificates"}
      ]
    }
  ]
}
```

## Runbook 6: KEDA Scaler Failure

**Trigger:** KEDA scaler error event

**AI Execution:**
```json
{
  "runbook": "keda-scaler-failure",
  "steps": [
    {
      "action": "kubectl://get",
      "resource": "scaledobject",
      "namespace": "${namespace}",
      "name": "${scaledobject}"
    },
    {
      "action": "kubectl://describe",
      "resource": "scaledobject",
      "namespace": "${namespace}",
      "name": "${scaledobject}"
    },
    {
      "action": "kubectl://logs",
      "resource": "deployment/keda-operator",
      "namespace": "keda",
      "tail": 100
    },
    {
      "action": "analyze",
      "model": "anthropic.claude-3-5-sonnet-20241022-v2:0",
      "prompt": "KEDA failure: scaler_config=${config}, error=${error}"
    },
    {
      "action": "remediate",
      "conditions": [
        {"if": "auth_failed", "then": "refresh_pod_identity"},
        {"if": "metric_unavailable", "then": "check_prometheus"},
        {"if": "invalid_trigger", "then": "fix_scaledobject"}
      ]
    }
  ]
}
```

## Self-Healing Workflows

**Automatic Remediation (No Human Approval):**
- Pod restarts (< 5 restarts/hour)
- Memory limit adjustments (< 2x current)
- Horizontal scaling (within min/max bounds)
- Certificate rotation (expiring < 7 days)

**Human Approval Required:**
- Node termination
- Deployment rollback
- RBAC changes
- Security group modifications

**Approval Flow:**
```json
{
  "approval": {
    "action": "terminate_node",
    "reason": "GuardDuty malware detection",
    "impact": "2 pods will be rescheduled",
    "timeout": "5m",
    "approvers": ["sre-oncall@example.com"],
    "auto_approve_if": "off_hours AND severity=CRITICAL"
  }
}
```

## MCP Server Configuration

**Deploy MCP Server:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mcp-server
  namespace: kube-system
spec:
  replicas: 2
  template:
    spec:
      serviceAccountName: mcp-server
      containers:
      - name: mcp-server
        image: mcp-server:latest
        env:
        - name: AWS_REGION
          value: us-gov-west-1
        - name: CLUSTER_NAME
          value: enhanced-eks-cluster
        ports:
        - containerPort: 8080
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: mcp-server
  namespace: kube-system
  annotations:
    eks.amazonaws.com/role-arn: arn:aws-us-gov:iam::${account_id}:role/mcp-server-role
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: mcp-server
rules:
- apiGroups: ["*"]
  resources: ["*"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: mcp-server
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: mcp-server
subjects:
- kind: ServiceAccount
  name: mcp-server
  namespace: kube-system
```

**IAM Role for MCP Server:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "eks:DescribeCluster",
        "cloudwatch:GetMetricStatistics",
        "cloudwatch:GetMetricData",
        "logs:GetLogEvents",
        "guardduty:GetFindings",
        "xray:GetServiceGraph",
        "xray:GetTraceSummaries",
        "bedrock:InvokeModel"
      ],
      "Resource": "*"
    }
  ]
}
```

## Bedrock Agent Configuration

**Agent Definition:**
```json
{
  "agentName": "eks-sre-agent",
  "foundationModel": "anthropic.claude-3-5-sonnet-20241022-v2:0",
  "instruction": "You are an SRE agent for EKS cluster operations. Execute runbooks, analyze incidents, and remediate issues. Always explain your actions and request approval for destructive operations.",
  "actionGroups": [
    {
      "actionGroupName": "kubernetes-operations",
      "apiSchema": {
        "s3": {
          "s3BucketName": "eks-mcp-schemas",
          "s3ObjectKey": "kubernetes-api.json"
        }
      }
    },
    {
      "actionGroupName": "aws-operations",
      "apiSchema": {
        "s3": {
          "s3BucketName": "eks-mcp-schemas",
          "s3ObjectKey": "aws-api.json"
        }
      }
    }
  ],
  "knowledgeBases": [
    {
      "knowledgeBaseId": "eks-runbooks-kb",
      "description": "SRE runbooks and troubleshooting guides"
    }
  ]
}
```

## Monitoring AI Operations

**CloudWatch Metrics:**
```bash
# AI runbook executions
aws cloudwatch get-metric-statistics \
  --namespace EKS/AI \
  --metric-name RunbookExecutions \
  --dimensions Name=RunbookName,Value=pod-crash \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum

# AI remediation success rate
aws cloudwatch get-metric-statistics \
  --namespace EKS/AI \
  --metric-name RemediationSuccessRate \
  --start-time $(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 3600 \
  --statistics Average
```

**Audit Logs:**
```bash
# View AI actions
aws logs filter-log-events \
  --log-group-name /aws/bedrock/agent/eks-sre-agent \
  --start-time $(date -u -d '1 hour ago' +%s)000 \
  --filter-pattern '{ $.action = "remediate" }'
```

## Emergency Stop

**Disable AI Operations:**
```bash
# Stop Bedrock agent
aws bedrock-agent update-agent \
  --agent-id ${agent_id} \
  --agent-status DISABLED

# Scale down MCP server
kubectl scale deployment mcp-server -n kube-system --replicas=0

# Resume manual operations
export AI_OPERATIONS_ENABLED=false
```

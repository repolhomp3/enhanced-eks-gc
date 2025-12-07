# AI Playbooks - Agentic Workflows

Bedrock Claude agent workflows for autonomous EKS operations via MCP.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Bedrock Claude Agent                     │
│  (anthropic.claude-3-sonnet-20240229-v1:0)                │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│                      MCP Client                              │
│  - Protocol translation                                      │
│  - Request routing                                           │
│  - Response aggregation                                      │
└─────────────────────┬───────────────────────────────────────┘
                      │
        ┌─────────────┼─────────────┬─────────────┐
        ▼             ▼             ▼             ▼
┌──────────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐
│ MCP Server   │ │CloudWatch│ │GuardDuty │ │  X-Ray   │
│ (kubectl://) │ │   API    │ │   API    │ │   API    │
└──────┬───────┘ └──────────┘ └──────────┘ └──────────┘
       │
       ▼
┌──────────────┐
│ EKS Cluster  │
└──────────────┘
```

## Playbook 1: Autonomous Incident Response

**Trigger:** Any P0/P1 alert

**Decision Tree:**
```
Alert Received
    │
    ├─ Severity = P0 (Critical)
    │   ├─ Type = Security
    │   │   ├─ GuardDuty Finding → Isolate + Notify
    │   │   └─ Security Hub Finding → Assess + Remediate
    │   ├─ Type = Availability
    │   │   ├─ Control Plane Down → Escalate AWS Support
    │   │   └─ All Nodes Down → Check Auto Mode + Scale
    │   └─ Type = Performance
    │       ├─ API Latency > 5s → Analyze + Scale
    │       └─ Pod Crash Rate > 50% → Rollback
    │
    └─ Severity = P1 (High)
        ├─ Type = Deployment
        │   ├─ Rollout Failed → Analyze + Rollback
        │   └─ Image Pull Error → Check ECR + Notify
        ├─ Type = Resource
        │   ├─ Memory Pressure → Scale + Add Limits
        │   └─ Disk Pressure → Expand PVC + Clean Logs
        └─ Type = Network
            ├─ Service Unreachable → Check Istio + DNS
            └─ High Latency → Analyze X-Ray + Optimize
```

**Agent Workflow:**
```json
{
  "playbook": "autonomous-incident-response",
  "agent": "eks-sre-agent",
  "model": "anthropic.claude-3-sonnet-20240229-v1:0",
  "workflow": {
    "1_detect": {
      "action": "receive_alert",
      "sources": ["cloudwatch", "prometheus", "guardduty", "security_hub"]
    },
    "2_classify": {
      "action": "analyze_alert",
      "extract": ["severity", "type", "affected_resources", "blast_radius"],
      "reasoning": "Use Claude to classify incident and determine impact"
    },
    "3_investigate": {
      "action": "gather_context",
      "parallel": [
        {"mcp": "kubectl://get pods -n ${namespace}"},
        {"mcp": "kubectl://logs ${pod} -n ${namespace} --tail=200"},
        {"mcp": "aws://cloudwatch/get-metric-data"},
        {"mcp": "aws://xray/get-traces"}
      ]
    },
    "4_decide": {
      "action": "determine_remediation",
      "reasoning": "Analyze gathered data and select appropriate runbook",
      "output": "remediation_plan"
    },
    "5_approve": {
      "action": "check_approval_required",
      "auto_approve_if": [
        "severity == P0 AND off_hours == true",
        "action IN ['restart_pod', 'scale_deployment']",
        "blast_radius < 10_pods"
      ],
      "require_human_if": [
        "action IN ['delete_node', 'modify_rbac', 'change_security_group']",
        "blast_radius > 50_pods"
      ]
    },
    "6_execute": {
      "action": "run_remediation",
      "with_rollback": true,
      "timeout": "10m"
    },
    "7_verify": {
      "action": "validate_remediation",
      "checks": [
        "alert_cleared",
        "metrics_normalized",
        "no_new_errors"
      ]
    },
    "8_document": {
      "action": "create_incident_report",
      "include": ["timeline", "root_cause", "remediation", "lessons_learned"]
    }
  }
}
```

## Playbook 2: Predictive Scaling

**Trigger:** Scheduled (every 5 minutes)

**Agent Workflow:**
```json
{
  "playbook": "predictive-scaling",
  "agent": "eks-sre-agent",
  "model": "anthropic.claude-3-sonnet-20240229-v1:0",
  "workflow": {
    "1_collect": {
      "action": "gather_metrics",
      "timeframe": "last_7_days",
      "metrics": [
        "cpu_utilization",
        "memory_utilization",
        "request_rate",
        "response_time"
      ]
    },
    "2_analyze": {
      "action": "detect_patterns",
      "reasoning": "Identify daily/weekly patterns, traffic spikes, resource trends",
      "output": "usage_forecast"
    },
    "3_predict": {
      "action": "forecast_demand",
      "horizon": "next_4_hours",
      "confidence": 0.85
    },
    "4_recommend": {
      "action": "generate_scaling_plan",
      "constraints": [
        "min_replicas >= 2",
        "max_replicas <= 100",
        "cost_increase < 20%"
      ]
    },
    "5_execute": {
      "action": "apply_scaling",
      "if": "confidence > 0.85 AND predicted_load_increase > 30%",
      "method": "gradual_scale_up"
    }
  }
}
```

## Playbook 3: Security Posture Optimization

**Trigger:** Daily at 2am UTC

**Agent Workflow:**
```json
{
  "playbook": "security-optimization",
  "agent": "eks-sre-agent",
  "model": "anthropic.claude-3-sonnet-20240229-v1:0",
  "workflow": {
    "1_scan": {
      "action": "security_assessment",
      "sources": [
        {"mcp": "aws://security-hub/get-findings"},
        {"mcp": "aws://guardduty/get-findings"},
        {"mcp": "kubectl://get networkpolicies --all-namespaces"},
        {"mcp": "kubectl://get podsecuritypolicies"}
      ]
    },
    "2_analyze": {
      "action": "identify_risks",
      "categories": [
        "exposed_services",
        "missing_network_policies",
        "overprivileged_pods",
        "unencrypted_secrets",
        "outdated_images"
      ]
    },
    "3_prioritize": {
      "action": "risk_ranking",
      "criteria": ["severity", "exploitability", "blast_radius", "compliance_impact"]
    },
    "4_remediate": {
      "action": "auto_fix",
      "auto_fix_if": [
        "risk == exposed_service AND namespace != production",
        "risk == missing_network_policy AND template_available",
        "risk == outdated_image AND patch_available"
      ]
    },
    "5_report": {
      "action": "generate_security_report",
      "recipients": ["security-team@example.com"],
      "include": ["fixed_issues", "remaining_risks", "recommendations"]
    }
  }
}
```

## Playbook 4: Cost Optimization

**Trigger:** Weekly on Monday 6am UTC

**Agent Workflow:**
```json
{
  "playbook": "cost-optimization",
  "agent": "eks-sre-agent",
  "model": "anthropic.claude-3-sonnet-20240229-v1:0",
  "workflow": {
    "1_analyze": {
      "action": "cost_analysis",
      "timeframe": "last_30_days",
      "breakdown": ["compute", "storage", "network", "observability"]
    },
    "2_identify": {
      "action": "find_waste",
      "patterns": [
        "idle_pods (cpu < 5% for 7 days)",
        "oversized_pods (requested >> used)",
        "unused_pvcs (not mounted for 30 days)",
        "redundant_load_balancers"
      ]
    },
    "3_recommend": {
      "action": "generate_savings_plan",
      "opportunities": [
        {"type": "rightsize_pod", "savings": "$120/month"},
        {"type": "delete_unused_pvc", "savings": "$45/month"},
        {"type": "consolidate_lb", "savings": "$65/month"}
      ]
    },
    "4_execute": {
      "action": "apply_optimizations",
      "auto_apply_if": [
        "savings > $50/month",
        "risk == low",
        "approval_not_required"
      ]
    },
    "5_report": {
      "action": "cost_report",
      "include": ["current_spend", "optimizations_applied", "projected_savings"]
    }
  }
}
```

## Playbook 5: Automated Rollback

**Trigger:** Deployment health check failure

**Agent Workflow:**
```json
{
  "playbook": "automated-rollback",
  "agent": "eks-sre-agent",
  "model": "anthropic.claude-3-sonnet-20240229-v1:0",
  "workflow": {
    "1_detect": {
      "action": "health_check",
      "interval": "30s",
      "checks": [
        "pod_ready_rate > 80%",
        "error_rate < 1%",
        "latency_p99 < 500ms"
      ]
    },
    "2_analyze": {
      "action": "compare_versions",
      "current": "v2.1.0",
      "previous": "v2.0.5",
      "metrics": ["error_rate", "latency", "cpu", "memory"]
    },
    "3_decide": {
      "action": "rollback_decision",
      "rollback_if": [
        "error_rate_increase > 200%",
        "latency_increase > 100%",
        "pod_crash_rate > 20%"
      ]
    },
    "4_execute": {
      "action": "rollback_deployment",
      "method": "kubectl rollout undo",
      "verify": true
    },
    "5_notify": {
      "action": "alert_team",
      "channels": ["slack", "pagerduty"],
      "message": "Auto-rollback executed: ${deployment} v2.1.0 → v2.0.5"
    },
    "6_investigate": {
      "action": "root_cause_analysis",
      "gather": ["logs", "events", "metrics", "traces"],
      "output": "incident_report"
    }
  }
}
```

## MCP Protocol Examples

**Kubernetes Operations:**
```json
{
  "jsonrpc": "2.0",
  "method": "kubectl/get",
  "params": {
    "resource": "pods",
    "namespace": "default",
    "selector": "app=api"
  },
  "id": 1
}
```

**CloudWatch Metrics:**
```json
{
  "jsonrpc": "2.0",
  "method": "cloudwatch/get_metric_data",
  "params": {
    "namespace": "ContainerInsights",
    "metric": "pod_cpu_utilization",
    "dimensions": [
      {"name": "ClusterName", "value": "enhanced-eks-cluster"},
      {"name": "Namespace", "value": "default"}
    ],
    "start_time": "2024-01-01T00:00:00Z",
    "end_time": "2024-01-01T01:00:00Z",
    "period": 300
  },
  "id": 2
}
```

**GuardDuty Findings:**
```json
{
  "jsonrpc": "2.0",
  "method": "guardduty/get_findings",
  "params": {
    "detector_id": "abc123",
    "finding_criteria": {
      "severity": {"gte": 7},
      "resource.type": {"eq": "EKSCluster"}
    }
  },
  "id": 3
}
```

## Agent Prompt Engineering

**System Prompt:**
```
You are an expert SRE agent managing an EKS cluster in AWS GovCloud (us-gov-west-1).

Your responsibilities:
- Monitor cluster health and respond to incidents
- Execute runbooks and remediation workflows
- Optimize costs and resource utilization
- Maintain security posture and compliance
- Perform predictive scaling and capacity planning

Guidelines:
- Always explain your reasoning before taking action
- Request approval for destructive operations (node termination, RBAC changes)
- Prioritize availability over cost optimization
- Follow the principle of least privilege
- Document all actions in CloudWatch Logs
- Escalate to humans when uncertain

Available tools:
- kubectl:// - Kubernetes API operations
- aws://cloudwatch - Metrics and logs
- aws://guardduty - Security findings
- aws://xray - Distributed traces
- aws://security-hub - Compliance findings

Constraints:
- Never delete production data without approval
- Never modify security groups without approval
- Never disable security features (GuardDuty, Security Hub)
- Always verify remediation success
- Always create rollback plan before changes
```

**Few-Shot Examples:**
```
Human: Pod api-service-abc123 is in CrashLoopBackOff

Agent: I'll investigate the pod crash. Let me gather information:

1. Get pod details: kubectl://get pod api-service-abc123 -n default
2. Check logs: kubectl://logs api-service-abc123 -n default --tail=100
3. Describe pod: kubectl://describe pod api-service-abc123 -n default

Analysis: Pod is crashing due to OOMKilled (exit code 137). Memory limit is 256Mi but usage peaked at 280Mi.

Remediation: Increase memory limit to 512Mi in deployment spec.

Approval: Not required (resource adjustment within safe bounds).

Executing: kubectl://patch deployment api-service -n default -p '{"spec":{"template":{"spec":{"containers":[{"name":"api","resources":{"limits":{"memory":"512Mi"}}}]}}}}'

Verification: New pods running successfully. Memory usage stable at 320Mi.
```

## Bedrock Agent Configuration

**Create Agent:**
```bash
aws bedrock-agent create-agent \
  --agent-name eks-sre-agent \
  --foundation-model anthropic.claude-3-sonnet-20240229-v1:0 \
  --instruction "$(cat agent-prompt.txt)" \
  --agent-resource-role-arn arn:aws-us-gov:iam::${account_id}:role/bedrock-agent-role \
  --region us-gov-west-1
```

**Add Action Group:**
```bash
aws bedrock-agent create-agent-action-group \
  --agent-id ${agent_id} \
  --agent-version DRAFT \
  --action-group-name kubernetes-operations \
  --action-group-executor '{"lambda":"arn:aws-us-gov:lambda:us-gov-west-1:${account_id}:function:mcp-server"}' \
  --api-schema '{"s3":{"s3BucketName":"eks-mcp-schemas","s3ObjectKey":"kubernetes-api.json"}}' \
  --region us-gov-west-1
```

**Prepare Agent:**
```bash
aws bedrock-agent prepare-agent \
  --agent-id ${agent_id} \
  --region us-gov-west-1
```

**Create Alias:**
```bash
aws bedrock-agent create-agent-alias \
  --agent-id ${agent_id} \
  --agent-alias-name production \
  --region us-gov-west-1
```

## Invoke Agent

**CLI:**
```bash
aws bedrock-agent-runtime invoke-agent \
  --agent-id ${agent_id} \
  --agent-alias-id ${alias_id} \
  --session-id $(uuidgen) \
  --input-text "Check health of api-service deployment in default namespace" \
  --region us-gov-west-1 \
  output.txt
```

**Python SDK:**
```python
import boto3

bedrock = boto3.client('bedrock-agent-runtime', region_name='us-gov-west-1')

response = bedrock.invoke_agent(
    agentId='agent_id',
    agentAliasId='alias_id',
    sessionId='session_123',
    inputText='Investigate high memory usage in production namespace'
)

for event in response['completion']:
    if 'chunk' in event:
        print(event['chunk']['bytes'].decode())
```

## Monitoring AI Operations

**CloudWatch Metrics:**
```bash
# Agent invocations
aws cloudwatch get-metric-statistics \
  --namespace AWS/Bedrock \
  --metric-name Invocations \
  --dimensions Name=AgentId,Value=${agent_id} \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum

# Agent latency
aws cloudwatch get-metric-statistics \
  --namespace AWS/Bedrock \
  --metric-name InvocationLatency \
  --dimensions Name=AgentId,Value=${agent_id} \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average,Maximum
```

**Audit Logs:**
```bash
# View agent actions
aws logs tail /aws/bedrock/agent/${agent_id} --follow

# Filter by action type
aws logs filter-log-events \
  --log-group-name /aws/bedrock/agent/${agent_id} \
  --filter-pattern '{ $.actionType = "kubectl" }' \
  --start-time $(date -u -d '1 hour ago' +%s)000
```

## Safety Controls

**Rate Limiting:**
```json
{
  "rate_limits": {
    "pod_restarts": "5 per hour",
    "deployments_modified": "10 per hour",
    "nodes_terminated": "2 per hour",
    "rbac_changes": "1 per hour"
  }
}
```

**Approval Gates:**
```json
{
  "require_approval": [
    "delete_node",
    "modify_security_group",
    "change_rbac",
    "delete_pvc",
    "scale_down > 50%"
  ],
  "auto_approve": [
    "restart_pod",
    "scale_up < 2x",
    "add_resource_limits",
    "rotate_secrets"
  ]
}
```

**Emergency Stop:**
```bash
# Disable agent
aws bedrock-agent update-agent \
  --agent-id ${agent_id} \
  --agent-status DISABLED \
  --region us-gov-west-1

# Delete agent alias (stops all invocations)
aws bedrock-agent delete-agent-alias \
  --agent-id ${agent_id} \
  --agent-alias-id ${alias_id} \
  --region us-gov-west-1
```

# Incident Response Plan

Comprehensive incident response procedures for EKS cluster security and operational incidents.

## Incident Classification

| Severity | Description | Response Time | Examples |
|----------|-------------|---------------|----------|
| **P0 - Critical** | Complete service outage, data breach | 15 minutes | Control plane down, ransomware, data exfiltration |
| **P1 - High** | Major functionality impaired | 1 hour | Multiple pod failures, GuardDuty critical finding |
| **P2 - Medium** | Partial functionality impaired | 4 hours | Single service degraded, high memory usage |
| **P3 - Low** | Minor issue, no user impact | 24 hours | Non-critical alerts, performance degradation |

## Incident Response Team

**Roles:**
- **Incident Commander**: Coordinates response, makes decisions
- **Technical Lead**: Executes remediation
- **Communications Lead**: Updates stakeholders
- **Security Lead**: Handles security incidents

**On-Call Rotation:**
- Primary: 24/7 on-call via Incident Manager SMS
- Secondary: Escalation after 5 minutes
- Manager: Escalation for P0 incidents

## Response Procedures

### Phase 1: Detection & Triage (0-15 minutes)

**1. Alert Received**
- SMS via Incident Manager
- Teams/Slack via AWS Chatbot
- Email via SNS

**2. Acknowledge Incident**
```bash
# Via AWS Console or CLI
aws ssm-incidents update-incident-record \
  --arn <incident-arn> \
  --status OPEN \
  --region us-gov-west-1
```

**3. Initial Assessment**
- Severity classification
- Blast radius determination
- User impact assessment

**4. Activate Response Team**
```bash
# Engage additional responders
aws ssm-contacts start-engagement \
  --contact-id <contact-arn> \
  --sender incident-commander \
  --subject "P0: EKS Cluster Incident" \
  --content "Critical incident requires immediate attention" \
  --region us-gov-west-1
```

### Phase 2: Containment (15-60 minutes)

**Security Incidents:**

**GuardDuty Critical Finding:**
```bash
# 1. Isolate compromised node
kubectl cordon <node-name>
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data --force

# 2. Capture forensics
kubectl logs <pod-name> -n <namespace> > /tmp/pod-logs.txt
kubectl describe pod <pod-name> -n <namespace> > /tmp/pod-describe.txt

# 3. Terminate compromised resources
kubectl delete pod <pod-name> -n <namespace> --force --grace-period=0

# 4. Block network access
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
  namespace: <namespace>
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
EOF
```

**Data Breach:**
```bash
# 1. Revoke credentials immediately
aws iam delete-access-key --access-key-id <key-id>

# 2. Rotate all secrets
aws secretsmanager rotate-secret --secret-id <secret-name> --region us-gov-west-1

# 3. Enable MFA delete on S3 buckets
aws s3api put-bucket-versioning \
  --bucket <bucket-name> \
  --versioning-configuration Status=Enabled,MFADelete=Enabled \
  --mfa "arn:aws:iam::<account>:mfa/<device> <code>"

# 4. Notify security team
aws sns publish \
  --topic-arn <security-topic-arn> \
  --subject "URGENT: Data Breach Detected" \
  --message "Immediate action required"
```

**Operational Incidents:**

**Control Plane Outage:**
```bash
# 1. Check AWS Health Dashboard
aws health describe-events --region us-gov-west-1

# 2. Open AWS Support case (Enterprise Support)
aws support create-case \
  --subject "EKS Control Plane Outage" \
  --severity-code "urgent" \
  --category-code "technical" \
  --service-code "eks" \
  --communication-body "Control plane unresponsive for cluster enhanced-eks-cluster"

# 3. Failover to DR cluster (if available)
# See DISASTER-RECOVERY.md
```

**Mass Pod Failures:**
```bash
# 1. Check Auto Mode status
aws eks describe-cluster --name enhanced-eks-cluster --region us-gov-west-1

# 2. Check node status
kubectl get nodes
kubectl describe nodes

# 3. Check for resource exhaustion
kubectl top nodes
kubectl top pods --all-namespaces

# 4. Scale up if needed (Auto Mode handles automatically)
# Manual intervention only if Auto Mode fails
```

### Phase 3: Eradication (1-4 hours)

**Remove Threat:**
```bash
# 1. Patch vulnerabilities
kubectl set image deployment/<deployment> <container>=<new-image>

# 2. Update security groups
aws ec2 revoke-security-group-ingress \
  --group-id <sg-id> \
  --ip-permissions <malicious-ip>

# 3. Apply security patches
kubectl apply -f updated-manifests/
```

**Verify Removal:**
```bash
# 1. Scan for malware
aws guardduty get-findings --detector-id <detector-id> --region us-gov-west-1

# 2. Check for persistence mechanisms
kubectl get cronjobs --all-namespaces
kubectl get daemonsets --all-namespaces

# 3. Review audit logs
aws logs filter-log-events \
  --log-group-name /aws/eks/enhanced-eks-cluster/cluster \
  --start-time $(date -u -d '4 hours ago' +%s)000 \
  --filter-pattern '{ $.responseElements.status = "Failure" }'
```

### Phase 4: Recovery (4-24 hours)

**Restore Services:**
```bash
# 1. Uncordon nodes
kubectl uncordon <node-name>

# 2. Scale deployments back up
kubectl scale deployment/<deployment> --replicas=<original-count>

# 3. Verify health
kubectl get pods --all-namespaces
kubectl get svc --all-namespaces

# 4. Run smoke tests
kubectl run test-pod --image=busybox --restart=Never -- wget -O- http://service-name
```

**Monitor for Recurrence:**
```bash
# 1. Watch CloudWatch metrics
aws cloudwatch get-metric-statistics \
  --namespace ContainerInsights \
  --metric-name cluster_failed_node_count \
  --dimensions Name=ClusterName,Value=enhanced-eks-cluster \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average

# 2. Monitor GuardDuty
aws guardduty list-findings \
  --detector-id <detector-id> \
  --finding-criteria '{"Criterion":{"severity":{"Gte":7}}}' \
  --region us-gov-west-1
```

### Phase 5: Post-Incident (24-72 hours)

**1. Document Timeline**
```bash
# Export incident timeline
aws ssm-incidents list-timeline-events \
  --incident-record-arn <incident-arn> \
  --region us-gov-west-1 > incident-timeline.json
```

**2. Root Cause Analysis**
- What happened?
- Why did it happen?
- How was it detected?
- How was it resolved?
- How can we prevent it?

**3. Update Runbooks**
- Document new procedures
- Update automation
- Train team members

**4. Implement Preventive Measures**
```bash
# Example: Add network policy
kubectl apply -f preventive-network-policy.yaml

# Example: Update RBAC
kubectl apply -f restrictive-rbac.yaml
```

**5. Close Incident**
```bash
aws ssm-incidents update-incident-record \
  --arn <incident-arn> \
  --status RESOLVED \
  --region us-gov-west-1
```

## Forensics & Evidence Collection

**Preserve Evidence:**
```bash
# 1. Snapshot EBS volumes
aws ec2 create-snapshot \
  --volume-id <volume-id> \
  --description "Forensic snapshot for incident <id>" \
  --region us-gov-west-1

# 2. Export logs
aws logs create-export-task \
  --log-group-name /aws/eks/enhanced-eks-cluster/cluster \
  --from $(date -u -d '24 hours ago' +%s)000 \
  --to $(date -u +%s)000 \
  --destination <s3-bucket> \
  --destination-prefix forensics/incident-<id>/

# 3. Capture pod state
kubectl get pods --all-namespaces -o yaml > pods-state.yaml
kubectl get events --all-namespaces > events.txt

# 4. Export CloudTrail logs
aws cloudtrail lookup-events \
  --start-time $(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --region us-gov-west-1 > cloudtrail-events.json
```

## Communication Templates

**Initial Notification (P0/P1):**
```
Subject: [P0] EKS Cluster Incident - <brief description>

Incident ID: INC-12345
Severity: P0 - Critical
Status: Investigating
Impact: <describe user impact>
Started: <timestamp>

We are investigating an incident affecting the EKS cluster.
Updates will be provided every 30 minutes.

Incident Commander: <name>
Next Update: <timestamp>
```

**Status Update:**
```
Subject: [P0] EKS Cluster Incident - Update #2

Incident ID: INC-12345
Status: Containment in progress
Impact: <current impact>

Actions Taken:
- Isolated compromised resources
- Applied temporary mitigation
- Root cause identified

Next Steps:
- Deploy permanent fix
- Verify resolution
- Monitor for 2 hours

Next Update: <timestamp>
```

**Resolution Notice:**
```
Subject: [RESOLVED] EKS Cluster Incident

Incident ID: INC-12345
Status: Resolved
Duration: 2 hours 15 minutes
Impact: <final impact summary>

Root Cause: <brief explanation>

Resolution:
- <action 1>
- <action 2>

Preventive Measures:
- <measure 1>
- <measure 2>

Post-Incident Review: Scheduled for <date>
```

## Escalation Paths

**Technical Escalation:**
1. On-call SRE (0-5 min)
2. Senior SRE (5-15 min)
3. Engineering Manager (15-30 min)
4. AWS Support (Enterprise) - Concurrent

**Security Escalation:**
1. Security Engineer (0-5 min)
2. Security Manager (5-15 min)
3. CISO (15-30 min)
4. Legal/Compliance - For data breaches

**Executive Escalation:**
1. Engineering Director (P0 only, 30 min)
2. CTO (P0 with business impact, 1 hour)
3. CEO (Data breach, 2 hours)

## Compliance & Reporting

**Required Reports:**
- Incident summary within 24 hours
- Root cause analysis within 72 hours
- Preventive measures within 1 week

**Regulatory Notifications:**
- Data breach: 72 hours (GDPR)
- PII exposure: Immediate (state laws)
- FedRAMP incidents: 1 hour (JAB)

## Testing & Drills

**Quarterly Incident Response Drills:**
- Simulated security breach
- Simulated service outage
- Tabletop exercises
- Post-drill retrospective

**Annual Full-Scale Exercise:**
- Multi-team coordination
- Executive involvement
- External auditor observation

## Tools & Resources

- **Incident Manager**: https://console.aws.amazon.com/systems-manager/incidents
- **GuardDuty**: https://console.aws.amazon.com/guardduty
- **CloudTrail**: https://console.aws.amazon.com/cloudtrail
- **VPC Flow Logs**: https://console.aws.amazon.com/vpc/
- **Runbooks**: [SRE-RUNBOOKS.md](SRE-RUNBOOKS.md)
- **AI Agent**: Can assist with investigation and remediation

## Contact Information

- **On-Call**: Via Incident Manager SMS
- **Security Team**: security@example.com
- **AWS Support**: 1-800-xxx-xxxx (Enterprise)
- **Legal**: legal@example.com

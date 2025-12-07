"""Extensible MCP tools for Bedrock agent"""
import boto3
import json
from datetime import datetime, timedelta
from kubernetes import client

class MCPTools:
    def __init__(self, region, cluster_name):
        self.region = region
        self.cluster_name = cluster_name
        self.cloudwatch = boto3.client('cloudwatch', region_name=region)
        self.logs = boto3.client('logs', region_name=region)
        self.kinesis = boto3.client('kinesis', region_name=region)
        self.s3 = boto3.client('s3', region_name=region)
        self.glue = boto3.client('glue', region_name=region)
        self.sns = boto3.client('sns', region_name=region)
        self.v1 = client.CoreV1Api()
        self.apps_v1 = client.AppsV1Api()
        
    # ========== Kubernetes Tools ==========
    
    def get_pod_health(self, namespaces):
        """Get health status of all pods in specified namespaces"""
        results = {}
        for ns in namespaces:
            pods = self.v1.list_namespaced_pod(ns)
            results[ns] = {
                'total': len(pods.items),
                'running': sum(1 for p in pods.items if p.status.phase == 'Running'),
                'pending': sum(1 for p in pods.items if p.status.phase == 'Pending'),
                'failed': sum(1 for p in pods.items if p.status.phase == 'Failed'),
                'pods': [{
                    'name': p.metadata.name,
                    'status': p.status.phase,
                    'ready': sum(1 for c in p.status.container_statuses if c.ready) if p.status.container_statuses else 0,
                    'restarts': sum(c.restart_count for c in p.status.container_statuses) if p.status.container_statuses else 0
                } for p in pods.items]
            }
        return results
    
    def probe_logs_for_errors(self, namespace, pod_name, error_patterns=['ERROR', 'FATAL', 'Exception'], tail=1000):
        """Probe pod logs for error patterns and return matches"""
        logs = self.v1.read_namespaced_pod_log(pod_name, namespace, tail_lines=tail)
        errors = []
        for line in logs.split('\n'):
            if any(pattern in line for pattern in error_patterns):
                errors.append(line)
        return {
            'pod': pod_name,
            'namespace': namespace,
            'error_count': len(errors),
            'errors': errors[:50]  # Limit to 50 errors
        }
    
    def get_deployment_status(self, namespace, deployment_name=None):
        """Get deployment status and replica counts"""
        if deployment_name:
            dep = self.apps_v1.read_namespaced_deployment(deployment_name, namespace)
            deployments = [dep]
        else:
            deps = self.apps_v1.list_namespaced_deployment(namespace)
            deployments = deps.items
        
        return [{
            'name': d.metadata.name,
            'namespace': d.metadata.namespace,
            'replicas': d.spec.replicas,
            'ready_replicas': d.status.ready_replicas or 0,
            'available_replicas': d.status.available_replicas or 0,
            'unavailable_replicas': d.status.unavailable_replicas or 0,
            'conditions': [{'type': c.type, 'status': c.status, 'reason': c.reason} for c in d.status.conditions] if d.status.conditions else []
        } for d in deployments]
    
    def get_node_resources(self):
        """Get node resource utilization"""
        nodes = self.v1.list_node()
        return [{
            'name': n.metadata.name,
            'capacity': {
                'cpu': n.status.capacity.get('cpu'),
                'memory': n.status.capacity.get('memory'),
                'pods': n.status.capacity.get('pods')
            },
            'allocatable': {
                'cpu': n.status.allocatable.get('cpu'),
                'memory': n.status.allocatable.get('memory'),
                'pods': n.status.allocatable.get('pods')
            },
            'conditions': [{'type': c.type, 'status': c.status} for c in n.status.conditions]
        } for n in nodes.items]
    
    # ========== Data Pipeline Tools ==========
    
    def get_kinesis_metrics(self, stream_name, hours=1):
        """Get Kinesis stream metrics (records sent, bytes)"""
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(hours=hours)
        
        metrics = {}
        for metric_name in ['IncomingRecords', 'IncomingBytes', 'PutRecord.Success', 'GetRecords.Success']:
            response = self.cloudwatch.get_metric_statistics(
                Namespace='AWS/Kinesis',
                MetricName=metric_name,
                Dimensions=[{'Name': 'StreamName', 'Value': stream_name}],
                StartTime=start_time,
                EndTime=end_time,
                Period=3600,
                Statistics=['Sum']
            )
            metrics[metric_name] = sum(d['Sum'] for d in response['Datapoints'])
        
        return {
            'stream_name': stream_name,
            'time_range_hours': hours,
            'records_sent': metrics.get('IncomingRecords', 0),
            'bytes_sent': metrics.get('IncomingBytes', 0),
            'put_success': metrics.get('PutRecord.Success', 0),
            'get_success': metrics.get('GetRecords.Success', 0)
        }
    
    def get_s3_object_count(self, bucket, prefix=''):
        """Count objects in S3 bucket/prefix (bronze area)"""
        paginator = self.s3.get_paginator('list_objects_v2')
        count = 0
        total_size = 0
        
        for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
            if 'Contents' in page:
                count += len(page['Contents'])
                total_size += sum(obj['Size'] for obj in page['Contents'])
        
        return {
            'bucket': bucket,
            'prefix': prefix,
            'object_count': count,
            'total_size_bytes': total_size,
            'total_size_gb': round(total_size / (1024**3), 2)
        }
    
    def get_glue_job_status(self, job_name=None):
        """Check Glue job runs and status"""
        if job_name:
            response = self.glue.get_job_runs(JobName=job_name, MaxResults=10)
            runs = response['JobRuns']
        else:
            jobs = self.glue.get_jobs()['Jobs']
            runs = []
            for job in jobs[:5]:  # Limit to 5 jobs
                job_runs = self.glue.get_job_runs(JobName=job['Name'], MaxResults=5)
                runs.extend(job_runs['JobRuns'])
        
        return [{
            'job_name': r['JobName'],
            'run_id': r['Id'],
            'state': r['JobRunState'],
            'started': r['StartedOn'].isoformat() if 'StartedOn' in r else None,
            'completed': r['CompletedOn'].isoformat() if 'CompletedOn' in r else None,
            'execution_time': r.get('ExecutionTime', 0),
            'error_message': r.get('ErrorMessage')
        } for r in runs]
    
    def check_glue_crawler_status(self, crawler_name=None):
        """Check Glue crawler status"""
        if crawler_name:
            crawler = self.glue.get_crawler(Name=crawler_name)
            crawlers = [crawler['Crawler']]
        else:
            response = self.glue.get_crawlers()
            crawlers = response['Crawlers']
        
        return [{
            'name': c['Name'],
            'state': c['State'],
            'last_crawl': c.get('LastCrawl', {}).get('Status'),
            'tables_created': c.get('LastCrawl', {}).get('TablesCreated', 0),
            'tables_updated': c.get('LastCrawl', {}).get('TablesUpdated', 0)
        } for c in crawlers]
    
    # ========== Monitoring & Alerting Tools ==========
    
    def send_sns_alert(self, topic_arn, subject, message, severity='INFO'):
        """Send SNS alert with structured message"""
        structured_message = {
            'timestamp': datetime.utcnow().isoformat(),
            'severity': severity,
            'cluster': self.cluster_name,
            'subject': subject,
            'message': message
        }
        
        self.sns.publish(
            TopicArn=topic_arn,
            Subject=f"[{severity}] {subject}",
            Message=json.dumps(structured_message, indent=2)
        )
        
        return {'status': 'sent', 'topic': topic_arn}
    
    def analyze_cloudwatch_logs(self, log_group, hours=1, error_patterns=['ERROR', 'FATAL', 'Exception']):
        """Analyze CloudWatch logs for errors"""
        end_time = int(datetime.utcnow().timestamp() * 1000)
        start_time = int((datetime.utcnow() - timedelta(hours=hours)).timestamp() * 1000)
        
        query = f"fields @timestamp, @message | filter {' or '.join([f'@message like /{p}/' for p in error_patterns])} | sort @timestamp desc | limit 100"
        
        response = self.logs.start_query(
            logGroupName=log_group,
            startTime=start_time,
            endTime=end_time,
            queryString=query
        )
        
        query_id = response['queryId']
        
        # Wait for query to complete (simplified - should poll)
        import time
        time.sleep(2)
        
        results = self.logs.get_query_results(queryId=query_id)
        
        return {
            'log_group': log_group,
            'error_count': len(results.get('results', [])),
            'errors': results.get('results', [])[:50]
        }
    
    def get_eks_cluster_health(self):
        """Get EKS cluster health metrics"""
        metrics = {}
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(hours=1)
        
        for metric_name in ['cluster_failed_node_count', 'cluster_node_count']:
            response = self.cloudwatch.get_metric_statistics(
                Namespace='ContainerInsights',
                MetricName=metric_name,
                Dimensions=[{'Name': 'ClusterName', 'Value': self.cluster_name}],
                StartTime=start_time,
                EndTime=end_time,
                Period=3600,
                Statistics=['Average']
            )
            if response['Datapoints']:
                metrics[metric_name] = response['Datapoints'][0]['Average']
        
        return {
            'cluster_name': self.cluster_name,
            'node_count': metrics.get('cluster_node_count', 0),
            'failed_nodes': metrics.get('cluster_failed_node_count', 0),
            'healthy': metrics.get('cluster_failed_node_count', 0) == 0
        }
    
    # ========== Tool Registry ==========
    
    def get_available_tools(self):
        """Return list of all available tools"""
        return {
            'kubernetes': [
                'get_pod_health',
                'probe_logs_for_errors',
                'get_deployment_status',
                'get_node_resources'
            ],
            'data_pipeline': [
                'get_kinesis_metrics',
                'get_s3_object_count',
                'get_glue_job_status',
                'check_glue_crawler_status'
            ],
            'monitoring': [
                'send_sns_alert',
                'analyze_cloudwatch_logs',
                'get_eks_cluster_health'
            ]
        }

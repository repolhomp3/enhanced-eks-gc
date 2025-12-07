import json
import os
import boto3
import base64
from kubernetes import client, config
from tools import MCPTools

eks = boto3.client('eks', region_name=os.environ['AWS_REGION'])
cloudwatch = boto3.client('cloudwatch', region_name=os.environ['AWS_REGION'])
guardduty = boto3.client('guardduty', region_name=os.environ['AWS_REGION'])
xray = boto3.client('xray', region_name=os.environ['AWS_REGION'])

cluster_name = os.environ['CLUSTER_NAME']
cluster_info = eks.describe_cluster(name=cluster_name)
cluster_cert = cluster_info['cluster']['certificateAuthority']['data']
cluster_ep = cluster_info['cluster']['endpoint']

configuration = client.Configuration()
configuration.host = cluster_ep
configuration.verify_ssl = True
configuration.ssl_ca_cert = '/tmp/ca.crt'

with open('/tmp/ca.crt', 'w') as f:
    f.write(base64.b64decode(cluster_cert).decode('utf-8'))

token = boto3.client('sts').get_caller_identity()
configuration.api_key = {"authorization": f"Bearer {token}"}

client.Configuration.set_default(configuration)
v1 = client.CoreV1Api()
apps_v1 = client.AppsV1Api()

# Initialize MCP tools
mcp_tools = MCPTools(os.environ['AWS_REGION'], os.environ['CLUSTER_NAME'])

def handler(event, context):
    print(f"Received event: {json.dumps(event)}")
    
    action = event.get('actionGroup', '')
    api_path = event.get('apiPath', '')
    parameters = event.get('parameters', [])
    params = {p['name']: p['value'] for p in parameters}
    
    try:
        if action == 'kubernetes-operations':
            result = handle_kubernetes(api_path, params)
        elif action == 'aws-operations':
            result = handle_aws(api_path, params)
        else:
            result = {'error': f'Unknown action group: {action}'}
        
        return {
            'messageVersion': '1.0',
            'response': {
                'actionGroup': action,
                'apiPath': api_path,
                'httpMethod': 'POST',
                'httpStatusCode': 200,
                'responseBody': {
                    'application/json': {
                        'body': json.dumps(result)
                    }
                }
            }
        }
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'messageVersion': '1.0',
            'response': {
                'actionGroup': action,
                'apiPath': api_path,
                'httpMethod': 'POST',
                'httpStatusCode': 500,
                'responseBody': {
                    'application/json': {
                        'body': json.dumps({'error': str(e)})
                    }
                }
            }
        }

def handle_kubernetes(api_path, params):
    if api_path == '/kubectl/get':
        return kubectl_get(params)
    elif api_path == '/kubectl/logs':
        return kubectl_logs(params)
    elif api_path == '/kubectl/describe':
        return kubectl_describe(params)
    elif api_path == '/kubectl/pod-health':
        return mcp_tools.get_pod_health(params.get('namespaces', ['default']))
    elif api_path == '/kubectl/probe-logs':
        return mcp_tools.probe_logs_for_errors(
            params.get('namespace'),
            params.get('pod_name'),
            params.get('error_patterns', ['ERROR', 'FATAL', 'Exception'])
        )
    elif api_path == '/kubectl/deployment-status':
        return mcp_tools.get_deployment_status(params.get('namespace'), params.get('deployment_name'))
    elif api_path == '/kubectl/node-resources':
        return mcp_tools.get_node_resources()
    else:
        return {'error': f'Unknown kubectl operation: {api_path}'}

def kubectl_get(params):
    resource = params.get('resource')
    namespace = params.get('namespace', 'default')
    name = params.get('name')
    
    if resource == 'pods':
        if name:
            pod = v1.read_namespaced_pod(name, namespace)
            return {'pod': pod.to_dict()}
        else:
            pods = v1.list_namespaced_pod(namespace)
            return {'pods': [p.to_dict() for p in pods.items]}
    elif resource == 'deployments':
        if name:
            deployment = apps_v1.read_namespaced_deployment(name, namespace)
            return {'deployment': deployment.to_dict()}
        else:
            deployments = apps_v1.list_namespaced_deployment(namespace)
            return {'deployments': [d.to_dict() for d in deployments.items]}
    else:
        return {'error': f'Unsupported resource type: {resource}'}

def kubectl_logs(params):
    pod = params.get('pod')
    namespace = params.get('namespace', 'default')
    tail = int(params.get('tail', 100))
    
    logs = v1.read_namespaced_pod_log(name=pod, namespace=namespace, tail_lines=tail)
    return {'logs': logs}

def kubectl_describe(params):
    resource = params.get('resource')
    namespace = params.get('namespace', 'default')
    name = params.get('name')
    
    if resource == 'pod':
        pod = v1.read_namespaced_pod(name, namespace)
        events = v1.list_namespaced_event(namespace, field_selector=f'involvedObject.name={name}')
        return {'pod': pod.to_dict(), 'events': [e.to_dict() for e in events.items]}
    else:
        return {'error': f'Unsupported resource type: {resource}'}

def handle_aws(api_path, params):
    if api_path == '/cloudwatch/get-metric-data':
        return get_cloudwatch_metrics(params)
    elif api_path == '/guardduty/get-findings':
        return get_guardduty_findings(params)
    elif api_path == '/xray/get-service-graph':
        return get_xray_service_graph(params)
    elif api_path == '/kinesis/get-metrics':
        return mcp_tools.get_kinesis_metrics(params.get('stream_name'), params.get('hours', 1))
    elif api_path == '/s3/get-object-count':
        return mcp_tools.get_s3_object_count(params.get('bucket'), params.get('prefix', ''))
    elif api_path == '/glue/job-status':
        return mcp_tools.get_glue_job_status(params.get('job_name'))
    elif api_path == '/glue/crawler-status':
        return mcp_tools.check_glue_crawler_status(params.get('crawler_name'))
    elif api_path == '/sns/send-alert':
        return mcp_tools.send_sns_alert(
            params.get('topic_arn'),
            params.get('subject'),
            params.get('message'),
            params.get('severity', 'INFO')
        )
    elif api_path == '/cloudwatch/analyze-logs':
        return mcp_tools.analyze_cloudwatch_logs(
            params.get('log_group'),
            params.get('hours', 1),
            params.get('error_patterns', ['ERROR', 'FATAL', 'Exception'])
        )
    elif api_path == '/eks/cluster-health':
        return mcp_tools.get_eks_cluster_health()
    elif api_path == '/tools/list':
        return mcp_tools.get_available_tools()
    else:
        return {'error': f'Unknown AWS operation: {api_path}'}

def get_cloudwatch_metrics(params):
    response = cloudwatch.get_metric_statistics(
        Namespace=params.get('namespace'),
        MetricName=params.get('metric'),
        StartTime=params.get('start_time'),
        EndTime=params.get('end_time'),
        Period=int(params.get('period', 300)),
        Statistics=['Average', 'Maximum']
    )
    return {'datapoints': response['Datapoints']}

def get_guardduty_findings(params):
    finding_ids = params.get('finding_ids', [])
    detectors = guardduty.list_detectors()
    if not detectors['DetectorIds']:
        return {'error': 'No GuardDuty detector found'}
    
    detector_id = detectors['DetectorIds'][0]
    
    if finding_ids:
        response = guardduty.get_findings(DetectorId=detector_id, FindingIds=finding_ids)
        return {'findings': response['Findings']}
    else:
        response = guardduty.list_findings(DetectorId=detector_id, MaxResults=10)
        return {'finding_ids': response['FindingIds']}

def get_xray_service_graph(params):
    response = xray.get_service_graph(StartTime=params.get('start_time'), EndTime=params.get('end_time'))
    return {'services': response['Services']}

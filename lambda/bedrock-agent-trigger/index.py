import json
import os
import boto3
import uuid

bedrock_agent = boto3.client('bedrock-agent-runtime', region_name=os.environ.get('AWS_REGION', 'us-gov-west-1'))

def handler(event, context):
    print(f"Received event: {json.dumps(event)}")
    
    agent_id = os.environ['AGENT_ID']
    agent_alias_id = os.environ['AGENT_ALIAS_ID']
    
    detail = event.get('detail', {})
    
    if detail.get('type') == 'GuardDuty Finding':
        severity = detail.get('severity', 0)
        finding_type = detail.get('type', 'Unknown')
        resource = detail.get('resource', {})
        
        input_text = f"GuardDuty critical finding detected: Severity={severity}, Type={finding_type}, Resource={json.dumps(resource)}. Investigate and remediate."
    else:
        input_text = f"Alert received: {json.dumps(detail)}"
    
    session_id = str(uuid.uuid4())
    
    try:
        response = bedrock_agent.invoke_agent(
            agentId=agent_id,
            agentAliasId=agent_alias_id,
            sessionId=session_id,
            inputText=input_text
        )
        
        completion = ""
        for event in response.get('completion', []):
            if 'chunk' in event:
                chunk = event['chunk']
                if 'bytes' in chunk:
                    completion += chunk['bytes'].decode('utf-8')
        
        print(f"Agent response: {completion}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'session_id': session_id,
                'response': completion
            })
        }
    except Exception as e:
        print(f"Error invoking Bedrock agent: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

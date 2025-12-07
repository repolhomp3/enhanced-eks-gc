#!/bin/bash
set -e

echo "Building Lambda deployment packages..."

# Build MCP server
cd mcp-server
pip install -r requirements.txt -t .
zip -r ../mcp-server.zip . -x "*.pyc" -x "__pycache__/*"
cd ..

# Build Bedrock agent trigger
cd bedrock-agent-trigger
pip install -r requirements.txt -t .
zip -r ../bedrock-agent-trigger.zip . -x "*.pyc" -x "__pycache__/*"
cd ..

echo "Lambda packages built successfully:"
echo "  - mcp-server.zip"
echo "  - bedrock-agent-trigger.zip"

# n8n Workflows API Reference

> Complete API documentation for n8n workflow automation

## Overview

n8n is a workflow automation platform that allows you to create complex automations using a visual interface. The API provides programmatic access to workflows, executions, and credentials management.

**Base URL**: `http://your-instance-ip:5678`
**Authentication**: API Key or Basic Auth
**API Version**: v1

## Authentication

### API Key Authentication (Recommended)

```bash
# Set API key in headers
curl -X GET http://your-ip:5678/api/v1/workflows \
  -H "X-N8N-API-KEY: your-api-key"
```

### Basic Authentication

```bash
# Use basic auth
curl -X GET http://your-ip:5678/api/v1/workflows \
  -u "admin:your-password"
```

### Get API Key

1. Access n8n UI at `http://your-ip:5678`
2. Go to Settings → API Keys
3. Create new API key

## Workflows API

### List Workflows

Get all workflows in your n8n instance.

```bash
GET /api/v1/workflows
```

**Example Request:**
```bash
curl -X GET http://your-ip:5678/api/v1/workflows \
  -H "X-N8N-API-KEY: your-api-key"
```

**Example Response:**
```json
{
  "data": [
    {
      "id": "1",
      "name": "My Workflow",
      "active": true,
      "createdAt": "2024-01-01T12:00:00.000Z",
      "updatedAt": "2024-01-01T12:00:00.000Z",
      "nodes": [...],
      "connections": {...}
    }
  ]
}
```

### Get Workflow

Retrieve a specific workflow by ID.

```bash
GET /api/v1/workflows/{id}
```

**Example Request:**
```bash
curl -X GET http://your-ip:5678/api/v1/workflows/1 \
  -H "X-N8N-API-KEY: your-api-key"
```

### Create Workflow

Create a new workflow.

```bash
POST /api/v1/workflows
```

**Example Request:**
```bash
curl -X POST http://your-ip:5678/api/v1/workflows \
  -H "X-N8N-API-KEY: your-api-key" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "My New Workflow",
    "nodes": [
      {
        "name": "Start",
        "type": "n8n-nodes-base.start",
        "position": [240, 300],
        "parameters": {}
      }
    ],
    "connections": {}
  }'
```

### Update Workflow

Update an existing workflow.

```bash
PUT /api/v1/workflows/{id}
```

**Example Request:**
```bash
curl -X PUT http://your-ip:5678/api/v1/workflows/1 \
  -H "X-N8N-API-KEY: your-api-key" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Updated Workflow Name",
    "active": true
  }'
```

### Delete Workflow

Delete a workflow.

```bash
DELETE /api/v1/workflows/{id}
```

**Example Request:**
```bash
curl -X DELETE http://your-ip:5678/api/v1/workflows/1 \
  -H "X-N8N-API-KEY: your-api-key"
```

### Activate/Deactivate Workflow

```bash
# Activate
POST /api/v1/workflows/{id}/activate

# Deactivate  
POST /api/v1/workflows/{id}/deactivate
```

**Example Request:**
```bash
curl -X POST http://your-ip:5678/api/v1/workflows/1/activate \
  -H "X-N8N-API-KEY: your-api-key"
```

## Executions API

### Execute Workflow

Trigger a workflow execution.

```bash
POST /api/v1/workflows/{id}/execute
```

**Example Request:**
```bash
curl -X POST http://your-ip:5678/api/v1/workflows/1/execute \
  -H "X-N8N-API-KEY: your-api-key" \
  -H "Content-Type: application/json" \
  -d '{
    "data": {
      "input_data": "your data here"
    }
  }'
```

**Example Response:**
```json
{
  "data": {
    "executionId": "123",
    "data": {
      "resultData": {
        "runData": {...}
      }
    }
  }
}
```

### List Executions

Get workflow executions.

```bash
GET /api/v1/executions
```

**Query Parameters:**
- `workflowId`: Filter by workflow ID
- `status`: Filter by status (success, error, running)
- `limit`: Number of results (default: 20)

**Example Request:**
```bash
curl -X GET "http://your-ip:5678/api/v1/executions?workflowId=1&limit=10" \
  -H "X-N8N-API-KEY: your-api-key"
```

### Get Execution

Get details of a specific execution.

```bash
GET /api/v1/executions/{id}
```

**Example Request:**
```bash
curl -X GET http://your-ip:5678/api/v1/executions/123 \
  -H "X-N8N-API-KEY: your-api-key"
```

### Delete Execution

Delete an execution.

```bash
DELETE /api/v1/executions/{id}
```

## Credentials API

### List Credentials

Get all credentials.

```bash
GET /api/v1/credentials
```

**Example Request:**
```bash
curl -X GET http://your-ip:5678/api/v1/credentials \
  -H "X-N8N-API-KEY: your-api-key"
```

### Create Credential

Create a new credential.

```bash
POST /api/v1/credentials
```

**Example Request:**
```bash
curl -X POST http://your-ip:5678/api/v1/credentials \
  -H "X-N8N-API-KEY: your-api-key" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "OpenAI Credential",
    "type": "openAiApi",
    "data": {
      "apiKey": "sk-..."
    }
  }'
```

## Webhooks

### Webhook URLs

n8n supports webhook triggers for external integrations.

**Webhook URL Format:**
```
http://your-ip:5678/webhook/{webhook-path}
```

**Test Webhook URL:**
```
http://your-ip:5678/webhook-test/{webhook-path}
```

### Webhook Example

```bash
# Trigger webhook
curl -X POST http://your-ip:5678/webhook/my-webhook \
  -H "Content-Type: application/json" \
  -d '{
    "message": "Hello from external system",
    "timestamp": "2024-01-01T12:00:00Z"
  }'
```

## AI Integration Examples

### Ollama Integration

Create a workflow that uses the local Ollama service:

```json
{
  "name": "Ollama LLM Workflow",
  "nodes": [
    {
      "name": "Webhook",
      "type": "n8n-nodes-base.webhook",
      "parameters": {
        "path": "llm-query"
      }
    },
    {
      "name": "HTTP Request to Ollama",
      "type": "n8n-nodes-base.httpRequest",
      "parameters": {
        "url": "http://localhost:11434/api/generate",
        "method": "POST",
        "body": {
          "model": "deepseek-r1:8b",
          "prompt": "={{ $json.prompt }}",
          "stream": false
        }
      }
    },
    {
      "name": "Response",
      "type": "n8n-nodes-base.respondToWebhook",
      "parameters": {
        "response": "={{ $json.response }}"
      }
    }
  ]
}
```

### Qdrant Vector Search

Workflow for vector similarity search:

```json
{
  "name": "Vector Search Workflow",
  "nodes": [
    {
      "name": "Webhook",
      "type": "n8n-nodes-base.webhook",
      "parameters": {
        "path": "vector-search"
      }
    },
    {
      "name": "Generate Embedding",
      "type": "n8n-nodes-base.httpRequest",
      "parameters": {
        "url": "http://localhost:11434/api/embeddings",
        "method": "POST",
        "body": {
          "model": "nomic-embed-text",
          "prompt": "={{ $json.query }}"
        }
      }
    },
    {
      "name": "Search Qdrant",
      "type": "n8n-nodes-base.httpRequest",
      "parameters": {
        "url": "http://localhost:6333/collections/my_collection/points/search",
        "method": "POST",
        "body": {
          "vector": "={{ $json.embedding }}",
          "limit": 5
        }
      }
    }
  ]
}
```

## SDKs and Libraries

### JavaScript/TypeScript

```javascript
import { Client } from 'n8n-client';

const client = new Client('http://your-ip:5678', 'your-api-key');

// Execute workflow
const execution = await client.workflows.execute(1, {
  data: { input: 'your data' }
});

// Get execution result
const result = await client.executions.get(execution.id);
```

### Python

```python
import requests

class N8NClient:
    def __init__(self, base_url, api_key):
        self.base_url = base_url
        self.headers = {'X-N8N-API-KEY': api_key}
    
    def execute_workflow(self, workflow_id, data):
        response = requests.post(
            f"{self.base_url}/api/v1/workflows/{workflow_id}/execute",
            headers=self.headers,
            json={'data': data}
        )
        return response.json()

# Usage
client = N8NClient('http://your-ip:5678', 'your-api-key')
result = client.execute_workflow(1, {'input': 'test'})
```

## Monitoring and Health

### Health Check

```bash
GET /healthz
```

**Example Request:**
```bash
curl http://your-ip:5678/healthz
```

**Response:**
```json
{
  "status": "ok",
  "timestamp": "2024-01-01T12:00:00.000Z"
}
```

### Metrics

```bash
GET /metrics
```

Returns Prometheus-formatted metrics for monitoring.

## Error Handling

### Common HTTP Status Codes

- `200 OK`: Request successful
- `201 Created`: Resource created
- `400 Bad Request`: Invalid request
- `401 Unauthorized`: Authentication required
- `403 Forbidden`: Access denied
- `404 Not Found`: Resource not found
- `500 Internal Server Error`: Server error

### Error Response Format

```json
{
  "error": {
    "code": "WORKFLOW_NOT_FOUND",
    "message": "Workflow with ID 999 not found",
    "timestamp": "2024-01-01T12:00:00.000Z"
  }
}
```

## Rate Limits

- **API Requests**: 100 requests per minute per API key
- **Webhook Requests**: 1000 requests per minute per webhook
- **Workflow Executions**: 10 concurrent executions

## Best Practices

### Performance

1. **Use pagination** for large result sets
2. **Cache credentials** to avoid repeated API calls
3. **Implement retry logic** for transient failures
4. **Use webhooks** instead of polling for real-time updates

### Security

1. **Use API keys** instead of basic authentication
2. **Rotate API keys** regularly
3. **Validate webhook payloads** to prevent abuse
4. **Use HTTPS** in production (configure reverse proxy)

### Workflow Design

1. **Use error handling nodes** to manage failures
2. **Implement timeouts** for long-running operations
3. **Add logging nodes** for debugging
4. **Test workflows** before activation

## Examples

### Complete RAG Workflow

```json
{
  "name": "RAG Pipeline",
  "nodes": [
    {
      "name": "Document Input",
      "type": "n8n-nodes-base.webhook",
      "parameters": {"path": "process-document"}
    },
    {
      "name": "Extract Text",
      "type": "n8n-nodes-base.httpRequest",
      "parameters": {
        "url": "http://localhost:11235/extract",
        "method": "POST"
      }
    },
    {
      "name": "Generate Embeddings",
      "type": "n8n-nodes-base.httpRequest",
      "parameters": {
        "url": "http://localhost:11434/api/embeddings",
        "method": "POST",
        "body": {
          "model": "nomic-embed-text",
          "prompt": "={{ $json.text }}"
        }
      }
    },
    {
      "name": "Store in Qdrant",
      "type": "n8n-nodes-base.httpRequest",
      "parameters": {
        "url": "http://localhost:6333/collections/documents/points",
        "method": "PUT",
        "body": {
          "points": [{
            "id": "={{ $json.id }}",
            "vector": "={{ $json.embedding }}",
            "payload": {"text": "={{ $json.text }}"}
          }]
        }
      }
    }
  ]
}
```

---

**Next**: [Ollama API Reference](ollama-endpoints.md) | [Back to API Overview](README.md)
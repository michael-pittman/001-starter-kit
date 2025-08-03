# Ollama API Reference

> Complete API documentation for Ollama Large Language Model service

## Overview

Ollama provides a REST API for running large language models locally. It supports text generation, embeddings, and model management.

**Base URL**: `http://your-instance-ip:11434`
**Authentication**: None (local service)
**Available Models**: DeepSeek-R1:8B, Qwen2.5-VL:7B

## Available Models

GeuseMaker comes with pre-installed models:

| Model | Size | Purpose | Use Case |
|-------|------|---------|----------|
| `deepseek-r1:8b` | 8B params | Reasoning & Code | General purpose, coding |
| `qwen2.5-vl:7b` | 7B params | Vision & Language | Image analysis, multimodal |
| `nomic-embed-text` | 137M params | Embeddings | Vector generation |

## Text Generation API

### Generate Text

Generate text completion from a prompt.

```bash
POST /api/generate
```

**Request Body:**
```json
{
  "model": "deepseek-r1:8b",
  "prompt": "Explain quantum computing",
  "stream": false
}
```

**Example Request:**
```bash
curl -X POST http://your-ip:11434/api/generate \
  -H "Content-Type: application/json" \
  -d '{
    "model": "deepseek-r1:8b",
    "prompt": "What is artificial intelligence?",
    "stream": false,
    "options": {
      "temperature": 0.7,
      "top_p": 0.9,
      "max_tokens": 500
    }
  }'
```

**Example Response:**
```json
{
  "model": "deepseek-r1:8b",
  "created_at": "2024-01-01T12:00:00.000Z",
  "response": "Artificial intelligence (AI) refers to computer systems that can perform tasks typically requiring human intelligence...",
  "done": true,
  "context": [1, 2, 3, ...],
  "total_duration": 1234567890,
  "load_duration": 123456789,
  "prompt_eval_count": 25,
  "prompt_eval_duration": 123456789,
  "eval_count": 150,
  "eval_duration": 987654321
}
```

### Streaming Generation

For real-time text generation:

```bash
curl -X POST http://your-ip:11434/api/generate \
  -H "Content-Type: application/json" \
  -d '{
    "model": "deepseek-r1:8b",
    "prompt": "Write a story about AI",
    "stream": true
  }'
```

**Streaming Response:**
```json
{"model":"deepseek-r1:8b","created_at":"2024-01-01T12:00:00.000Z","response":"Once","done":false}
{"model":"deepseek-r1:8b","created_at":"2024-01-01T12:00:00.000Z","response":" upon","done":false}
{"model":"deepseek-r1:8b","created_at":"2024-01-01T12:00:00.000Z","response":" a","done":false}
...
{"model":"deepseek-r1:8b","created_at":"2024-01-01T12:00:00.000Z","response":"","done":true}
```

### Generate Parameters

| Parameter | Type | Description | Default |
|-----------|------|-------------|---------|
| `model` | string | Model name | Required |
| `prompt` | string | Input prompt | Required |
| `stream` | boolean | Stream response | false |
| `system` | string | System message | "" |
| `template` | string | Prompt template | "" |
| `context` | array | Previous context | [] |
| `options` | object | Generation options | {} |

### Generation Options

| Option | Type | Description | Default |
|--------|------|-------------|---------|
| `temperature` | float | Randomness (0-2) | 0.8 |
| `top_p` | float | Nucleus sampling (0-1) | 0.9 |
| `top_k` | int | Top-k sampling | 40 |
| `max_tokens` | int | Maximum tokens | -1 (unlimited) |
| `repeat_penalty` | float | Repetition penalty | 1.1 |
| `seed` | int | Random seed | -1 |
| `stop` | array | Stop sequences | [] |

## Chat API

### Chat Completion

For conversational interactions:

```bash
POST /api/chat
```

**Request Body:**
```json
{
  "model": "deepseek-r1:8b",
  "messages": [
    {
      "role": "system",
      "content": "You are a helpful AI assistant."
    },
    {
      "role": "user", 
      "content": "Hello, how are you?"
    }
  ],
  "stream": false
}
```

**Example Request:**
```bash
curl -X POST http://your-ip:11434/api/chat \
  -H "Content-Type: application/json" \
  -d '{
    "model": "deepseek-r1:8b",
    "messages": [
      {"role": "system", "content": "You are a coding assistant."},
      {"role": "user", "content": "Write a Python function to sort a list"}
    ],
    "stream": false
  }'
```

**Example Response:**
```json
{
  "model": "deepseek-r1:8b",
  "created_at": "2024-01-01T12:00:00.000Z",
  "message": {
    "role": "assistant",
    "content": "Here's a Python function to sort a list:\n\n```python\ndef sort_list(lst):\n    return sorted(lst)\n```"
  },
  "done": true
}
```

## Embeddings API

### Generate Embeddings

Create vector embeddings for text:

```bash
POST /api/embeddings
```

**Request Body:**
```json
{
  "model": "nomic-embed-text",
  "prompt": "The quick brown fox jumps over the lazy dog"
}
```

**Example Request:**
```bash
curl -X POST http://your-ip:11434/api/embeddings \
  -H "Content-Type: application/json" \
  -d '{
    "model": "nomic-embed-text",
    "prompt": "GeuseMaker is an AI infrastructure platform"
  }'
```

**Example Response:**
```json
{
  "embedding": [0.123, -0.456, 0.789, ...],
  "model": "nomic-embed-text",
  "prompt": "GeuseMaker is an AI infrastructure platform"
}
```

## Vision API (Qwen2.5-VL)

### Analyze Images

Use the vision model for image analysis:

```bash
curl -X POST http://your-ip:11434/api/generate \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen2.5-vl:7b",
    "prompt": "Describe this image in detail",
    "images": ["base64-encoded-image-data"],
    "stream": false
  }'
```

**With Image File:**
```bash
# Encode image to base64
IMAGE_BASE64=$(base64 -i image.jpg)

curl -X POST http://your-ip:11434/api/generate \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"qwen2.5-vl:7b\",
    \"prompt\": \"What objects do you see in this image?\",
    \"images\": [\"$IMAGE_BASE64\"],
    \"stream\": false
  }"
```

## Model Management API

### List Models

Get all available models:

```bash
GET /api/tags
```

**Example Request:**
```bash
curl http://your-ip:11434/api/tags
```

**Example Response:**
```json
{
  "models": [
    {
      "name": "deepseek-r1:8b",
      "modified_at": "2024-01-01T12:00:00.000Z",
      "size": 4865061584,
      "digest": "sha256:abc123...",
      "details": {
        "format": "gguf",
        "family": "deepseek-r1",
        "families": ["deepseek-r1"],
        "parameter_size": "8B",
        "quantization_level": "Q4_0"
      }
    }
  ]
}
```

### Pull Model

Download a new model:

```bash
POST /api/pull
```

**Request Body:**
```json
{
  "name": "llama2:7b",
  "stream": true
}
```

**Example Request:**
```bash
curl -X POST http://your-ip:11434/api/pull \
  -H "Content-Type: application/json" \
  -d '{
    "name": "llama2:7b",
    "stream": false
  }'
```

### Delete Model

Remove a model:

```bash
DELETE /api/delete
```

**Request Body:**
```json
{
  "name": "model-name:tag"
}
```

**Example Request:**
```bash
curl -X DELETE http://your-ip:11434/api/delete \
  -H "Content-Type: application/json" \
  -d '{
    "name": "llama2:7b"
  }'
```

### Show Model Info

Get detailed model information:

```bash
POST /api/show
```

**Request Body:**
```json
{
  "name": "deepseek-r1:8b"
}
```

**Example Request:**
```bash
curl -X POST http://your-ip:11434/api/show \
  -H "Content-Type: application/json" \
  -d '{
    "name": "deepseek-r1:8b"
  }'
```

## Health and Status

### Health Check

```bash
GET /api/tags
```

If the service is healthy, it will return the models list.

### GPU Status

Check GPU utilization:

```bash
# SSH into instance
ssh -i ~/.ssh/geusemaker-key.pem ubuntu@your-ip

# Check GPU status
nvidia-smi

# Check Ollama GPU usage
docker exec ollama nvidia-smi
```

## Integration Examples

### Python Client

```python
import requests
import json
import base64

class OllamaClient:
    def __init__(self, base_url="http://localhost:11434"):
        self.base_url = base_url
    
    def generate(self, model, prompt, **kwargs):
        data = {
            "model": model,
            "prompt": prompt,
            **kwargs
        }
        response = requests.post(
            f"{self.base_url}/api/generate",
            json=data
        )
        return response.json()
    
    def chat(self, model, messages, **kwargs):
        data = {
            "model": model,
            "messages": messages,
            **kwargs
        }
        response = requests.post(
            f"{self.base_url}/api/chat",
            json=data
        )
        return response.json()
    
    def embed(self, model, text):
        data = {
            "model": model,
            "prompt": text
        }
        response = requests.post(
            f"{self.base_url}/api/embeddings",
            json=data
        )
        return response.json()["embedding"]
    
    def analyze_image(self, model, prompt, image_path):
        with open(image_path, "rb") as image_file:
            image_base64 = base64.b64encode(image_file.read()).decode()
        
        data = {
            "model": model,
            "prompt": prompt,
            "images": [image_base64]
        }
        response = requests.post(
            f"{self.base_url}/api/generate",
            json=data
        )
        return response.json()

# Usage examples
client = OllamaClient("http://your-ip:11434")

# Text generation
result = client.generate("deepseek-r1:8b", "Explain machine learning")
print(result["response"])

# Chat
messages = [
    {"role": "system", "content": "You are a helpful assistant."},
    {"role": "user", "content": "What is Python?"}
]
chat_result = client.chat("deepseek-r1:8b", messages)
print(chat_result["message"]["content"])

# Embeddings
embedding = client.embed("nomic-embed-text", "Hello world")
print(f"Embedding dimension: {len(embedding)}")

# Vision
vision_result = client.analyze_image(
    "qwen2.5-vl:7b", 
    "Describe this image", 
    "image.jpg"
)
print(vision_result["response"])
```

### JavaScript Client

```javascript
class OllamaClient {
    constructor(baseUrl = 'http://localhost:11434') {
        this.baseUrl = baseUrl;
    }
    
    async generate(model, prompt, options = {}) {
        const response = await fetch(`${this.baseUrl}/api/generate`, {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({
                model,
                prompt,
                stream: false,
                ...options
            })
        });
        return response.json();
    }
    
    async chat(model, messages, options = {}) {
        const response = await fetch(`${this.baseUrl}/api/chat`, {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({
                model,
                messages,
                stream: false,
                ...options
            })
        });
        return response.json();
    }
    
    async embeddings(model, prompt) {
        const response = await fetch(`${this.baseUrl}/api/embeddings`, {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({model, prompt})
        });
        const data = await response.json();
        return data.embedding;
    }
    
    async *generateStream(model, prompt, options = {}) {
        const response = await fetch(`${this.baseUrl}/api/generate`, {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({
                model,
                prompt,
                stream: true,
                ...options
            })
        });
        
        const reader = response.body.getReader();
        const decoder = new TextDecoder();
        
        while (true) {
            const {done, value} = await reader.read();
            if (done) break;
            
            const chunk = decoder.decode(value);
            const lines = chunk.split('\n').filter(line => line.trim());
            
            for (const line of lines) {
                try {
                    const data = JSON.parse(line);
                    yield data;
                } catch (e) {
                    // Skip invalid JSON
                }
            }
        }
    }
}

// Usage examples
const client = new OllamaClient('http://your-ip:11434');

// Text generation
const result = await client.generate('deepseek-r1:8b', 'Explain AI');
console.log(result.response);

// Streaming generation
for await (const chunk of client.generateStream('deepseek-r1:8b', 'Write a poem')) {
    if (!chunk.done) {
        process.stdout.write(chunk.response);
    }
}

// Chat
const chatResult = await client.chat('deepseek-r1:8b', [
    {role: 'user', content: 'Hello!'}
]);
console.log(chatResult.message.content);

// Embeddings
const embedding = await client.embeddings('nomic-embed-text', 'Hello world');
console.log(`Embedding dimension: ${embedding.length}`);
```

## Performance Optimization

### Model Loading

Models are loaded on first request. To preload:

```bash
curl -X POST http://your-ip:11434/api/generate \
  -H "Content-Type: application/json" \
  -d '{
    "model": "deepseek-r1:8b",
    "prompt": "",
    "keep_alive": "5m"
  }'
```

### Concurrent Requests

Ollama handles multiple concurrent requests:
- Maximum 3 concurrent generations (GPU memory dependent)
- Requests are queued if limit exceeded
- Use streaming for better perceived performance

### Memory Management

```bash
# Check GPU memory usage
nvidia-smi

# Unload models to free memory
curl -X POST http://your-ip:11434/api/generate \
  -H "Content-Type: application/json" \
  -d '{
    "model": "deepseek-r1:8b",
    "keep_alive": 0
  }'
```

## Error Handling

### Common Errors

| Error | Description | Solution |
|-------|-------------|----------|
| Model not found | Model not pulled | Pull model first |
| Out of memory | GPU memory exhausted | Reduce concurrent requests |
| Connection refused | Service not running | Check Docker container |
| Timeout | Request too long | Reduce max_tokens or complexity |

### Error Response Format

```json
{
  "error": "model 'nonexistent:latest' not found, try pulling it first"
}
```

## Monitoring

### Metrics Collection

```bash
# Monitor GPU usage
watch -n 1 nvidia-smi

# Monitor container logs
docker logs -f ollama

# Check API response times
curl -w "@curl-format.txt" -o /dev/null -s http://your-ip:11434/api/tags
```

### Health Monitoring Script

```bash
#!/bin/bash
check_ollama_health() {
    local response=$(curl -s http://your-ip:11434/api/tags)
    if echo "$response" | jq -e '.models' > /dev/null 2>&1; then
        echo "✅ Ollama is healthy"
        return 0
    else
        echo "❌ Ollama is unhealthy"
        return 1
    fi
}

check_ollama_health
```

---

**Next**: [Qdrant API Reference](qdrant-collections.md) | [Back to API Overview](README.md)
# Qdrant Vector Database API Reference

> Complete API documentation for Qdrant vector database operations

## Overview

Qdrant is a high-performance vector database designed for similarity search and AI applications. It provides REST API for managing collections, points, and performing vector operations.

**Base URL**: `http://your-instance-ip:6333`
**Authentication**: API Key (optional in development)
**Vector Dimensions**: Configurable (768 for nomic-embed-text)

## Collections API

### List Collections

Get all collections in the database.

```bash
GET /collections
```

**Example Request:**
```bash
curl http://your-ip:6333/collections
```

**Example Response:**
```json
{
  "result": {
    "collections": [
      {
        "name": "documents",
        "status": "green",
        "optimizer_status": "ok",
        "vectors_count": 1000,
        "indexed_vectors_count": 1000,
        "points_count": 1000,
        "segments_count": 1,
        "config": {
          "params": {
            "vectors": {
              "size": 768,
              "distance": "Cosine"
            }
          }
        }
      }
    ]
  },
  "status": "ok",
  "time": 0.001
}
```

### Create Collection

Create a new vector collection.

```bash
PUT /collections/{collection_name}
```

**Request Body:**
```json
{
  "vectors": {
    "size": 768,
    "distance": "Cosine"
  },
  "optimizers_config": {
    "default_segment_number": 2
  },
  "replication_factor": 1
}
```

**Example Request:**
```bash
curl -X PUT http://your-ip:6333/collections/my_documents \
  -H "Content-Type: application/json" \
  -d '{
    "vectors": {
      "size": 768,
      "distance": "Cosine"
    },
    "optimizers_config": {
      "default_segment_number": 2,
      "memmap_threshold": 20000
    },
    "replication_factor": 1
  }'
```

**Distance Metrics:**
- `Cosine`: Cosine similarity (recommended for text embeddings)
- `Dot`: Dot product
- `Euclid`: Euclidean distance
- `Manhattan`: Manhattan distance

### Get Collection Info

Retrieve information about a specific collection.

```bash
GET /collections/{collection_name}
```

**Example Request:**
```bash
curl http://your-ip:6333/collections/my_documents
```

### Update Collection

Update collection configuration.

```bash
PATCH /collections/{collection_name}
```

**Request Body:**
```json
{
  "optimizers_config": {
    "default_segment_number": 4
  }
}
```

### Delete Collection

Delete a collection and all its data.

```bash
DELETE /collections/{collection_name}
```

**Example Request:**
```bash
curl -X DELETE http://your-ip:6333/collections/my_documents
```

## Points API (Vector Operations)

### Insert Points

Add vectors with payload to a collection.

```bash
PUT /collections/{collection_name}/points
```

**Request Body:**
```json
{
  "points": [
    {
      "id": 1,
      "vector": [0.1, 0.2, 0.3, ...],
      "payload": {
        "text": "Example document text",
        "title": "Document Title",
        "category": "technical",
        "timestamp": "2024-01-01T12:00:00Z"
      }
    }
  ]
}
```

**Example Request:**
```bash
curl -X PUT http://your-ip:6333/collections/documents/points \
  -H "Content-Type: application/json" \
  -d '{
    "points": [
      {
        "id": 1,
        "vector": [0.1, 0.2, 0.3, 0.4, 0.5],
        "payload": {
          "text": "GeuseMaker is an AI infrastructure platform",
          "source": "documentation",
          "category": "ai"
        }
      },
      {
        "id": 2,
        "vector": [0.6, 0.7, 0.8, 0.9, 1.0],
        "payload": {
          "text": "Unity deployment system for AWS",
          "source": "readme",
          "category": "deployment"
        }
      }
    ]
  }'
```

### Search Vectors

Perform similarity search using a query vector.

```bash
POST /collections/{collection_name}/points/search
```

**Request Body:**
```json
{
  "vector": [0.1, 0.2, 0.3, ...],
  "limit": 10,
  "with_payload": true,
  "with_vector": false,
  "score_threshold": 0.7
}
```

**Example Request:**
```bash
curl -X POST http://your-ip:6333/collections/documents/points/search \
  -H "Content-Type: application/json" \
  -d '{
    "vector": [0.15, 0.25, 0.35, 0.45, 0.55],
    "limit": 5,
    "with_payload": true,
    "with_vector": false,
    "score_threshold": 0.5
  }'
```

**Example Response:**
```json
{
  "result": [
    {
      "id": 1,
      "version": 1,
      "score": 0.95,
      "payload": {
        "text": "GeuseMaker is an AI infrastructure platform",
        "source": "documentation",
        "category": "ai"
      }
    },
    {
      "id": 2,
      "version": 1,
      "score": 0.87,
      "payload": {
        "text": "Unity deployment system for AWS",
        "source": "readme",
        "category": "deployment"
      }
    }
  ],
  "status": "ok",
  "time": 0.005
}
```

### Search with Filters

Search vectors with payload filtering.

```bash
POST /collections/{collection_name}/points/search
```

**Request Body with Filters:**
```json
{
  "vector": [0.1, 0.2, 0.3, ...],
  "limit": 10,
  "filter": {
    "must": [
      {
        "key": "category",
        "match": {
          "value": "ai"
        }
      }
    ]
  },
  "with_payload": true
}
```

**Filter Examples:**

```json
{
  "filter": {
    "must": [
      {"key": "category", "match": {"value": "ai"}},
      {"key": "score", "range": {"gte": 0.8}}
    ],
    "must_not": [
      {"key": "status", "match": {"value": "draft"}}
    ]
  }
}
```

### Get Points

Retrieve specific points by ID.

```bash
POST /collections/{collection_name}/points
```

**Request Body:**
```json
{
  "ids": [1, 2, 3],
  "with_payload": true,
  "with_vector": true
}
```

**Example Request:**
```bash
curl -X POST http://your-ip:6333/collections/documents/points \
  -H "Content-Type: application/json" \
  -d '{
    "ids": [1, 2],
    "with_payload": true,
    "with_vector": false
  }'
```

### Update Points

Update existing points.

```bash
PUT /collections/{collection_name}/points
```

**Request Body:**
```json
{
  "points": [
    {
      "id": 1,
      "vector": [0.1, 0.2, 0.3, ...],
      "payload": {
        "text": "Updated text content",
        "last_modified": "2024-01-02T12:00:00Z"
      }
    }
  ]
}
```

### Delete Points

Delete points by ID or filter.

```bash
POST /collections/{collection_name}/points/delete
```

**Delete by IDs:**
```json
{
  "points": [1, 2, 3]
}
```

**Delete by Filter:**
```json
{
  "filter": {
    "must": [
      {
        "key": "category",
        "match": {
          "value": "outdated"
        }
      }
    ]
  }
}
```

**Example Request:**
```bash
curl -X POST http://your-ip:6333/collections/documents/points/delete \
  -H "Content-Type: application/json" \
  -d '{
    "points": [1, 2]
  }'
```

## Batch Operations

### Batch Upsert

Efficiently insert or update many points.

```bash
PUT /collections/{collection_name}/points/batch
```

**Example Request:**
```bash
curl -X PUT http://your-ip:6333/collections/documents/points/batch \
  -H "Content-Type: application/json" \
  -d '{
    "batch": {
      "ids": [1, 2, 3],
      "vectors": [
        [0.1, 0.2, 0.3],
        [0.4, 0.5, 0.6],
        [0.7, 0.8, 0.9]
      ],
      "payloads": [
        {"text": "First document"},
        {"text": "Second document"},
        {"text": "Third document"}
      ]
    }
  }'
```

## Health and Cluster

### Health Check

Check service health.

```bash
GET /health
```

**Example Request:**
```bash
curl http://your-ip:6333/health
```

**Example Response:**
```json
{
  "status": "ok",
  "version": "1.7.3"
}
```

### Cluster Info

Get cluster information.

```bash
GET /cluster
```

**Example Request:**
```bash
curl http://your-ip:6333/cluster
```

### Metrics

Get Prometheus metrics.

```bash
GET /metrics
```

**Example Request:**
```bash
curl http://your-ip:6333/metrics
```

## Integration Examples

### Python Client

```python
from qdrant_client import QdrantClient
from qdrant_client.http.models import Distance, VectorParams, PointStruct
import requests

# Initialize client
client = QdrantClient(host="your-ip", port=6333)

# Create collection
client.create_collection(
    collection_name="documents",
    vectors_config=VectorParams(size=768, distance=Distance.COSINE),
)

# Generate embeddings using Ollama
def get_embedding(text):
    response = requests.post(
        "http://your-ip:11434/api/embeddings",
        json={"model": "nomic-embed-text", "prompt": text}
    )
    return response.json()["embedding"]

# Add documents with embeddings
documents = [
    {"id": 1, "text": "GeuseMaker is an AI infrastructure platform"},
    {"id": 2, "text": "Unity deployment system for AWS"},
    {"id": 3, "text": "Ollama provides local LLM inference"}
]

points = []
for doc in documents:
    embedding = get_embedding(doc["text"])
    points.append(PointStruct(
        id=doc["id"],
        vector=embedding,
        payload={"text": doc["text"], "source": "docs"}
    ))

client.upsert(
    collection_name="documents",
    points=points
)

# Search for similar documents
query_text = "AI platform for cloud deployment"
query_embedding = get_embedding(query_text)

search_result = client.search(
    collection_name="documents",
    query_vector=query_embedding,
    limit=3,
    score_threshold=0.5
)

for result in search_result:
    print(f"Score: {result.score:.3f}")
    print(f"Text: {result.payload['text']}")
    print("---")
```

### JavaScript Client

```javascript
import { QdrantClient } from '@qdrant/js-client-rest';

const client = new QdrantClient({ host: 'your-ip', port: 6333 });

// Create collection
await client.createCollection('documents', {
  vectors: {
    size: 768,
    distance: 'Cosine',
  },
});

// Function to get embeddings from Ollama
async function getEmbedding(text) {
  const response = await fetch('http://your-ip:11434/api/embeddings', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model: 'nomic-embed-text',
      prompt: text
    })
  });
  const data = await response.json();
  return data.embedding;
}

// Add documents
const documents = [
  { id: 1, text: 'GeuseMaker is an AI infrastructure platform' },
  { id: 2, text: 'Unity deployment system for AWS' },
  { id: 3, text: 'Ollama provides local LLM inference' }
];

const points = await Promise.all(
  documents.map(async (doc) => ({
    id: doc.id,
    vector: await getEmbedding(doc.text),
    payload: { text: doc.text, source: 'docs' }
  }))
);

await client.upsert('documents', {
  wait: true,
  points: points
});

// Perform search
const queryText = 'AI platform for cloud deployment';
const queryEmbedding = await getEmbedding(queryText);

const searchResult = await client.search('documents', {
  vector: queryEmbedding,
  limit: 3,
  score_threshold: 0.5,
  with_payload: true
});

searchResult.forEach(result => {
  console.log(`Score: ${result.score.toFixed(3)}`);
  console.log(`Text: ${result.payload.text}`);
  console.log('---');
});
```

## RAG Pipeline Example

Complete Retrieval-Augmented Generation pipeline:

```python
import requests
from qdrant_client import QdrantClient
from qdrant_client.http.models import Distance, VectorParams, PointStruct

class RAGPipeline:
    def __init__(self, qdrant_host, ollama_host):
        self.qdrant = QdrantClient(host=qdrant_host, port=6333)
        self.ollama_base = f"http://{ollama_host}:11434"
        
    def create_knowledge_base(self, collection_name, documents):
        """Create a knowledge base from documents"""
        # Create collection
        self.qdrant.create_collection(
            collection_name=collection_name,
            vectors_config=VectorParams(size=768, distance=Distance.COSINE)
        )
        
        # Generate embeddings and store documents
        points = []
        for i, doc in enumerate(documents):
            embedding = self._get_embedding(doc["text"])
            points.append(PointStruct(
                id=i,
                vector=embedding,
                payload=doc
            ))
        
        self.qdrant.upsert(
            collection_name=collection_name,
            points=points
        )
    
    def query(self, collection_name, question, top_k=3):
        """Answer a question using RAG"""
        # Get question embedding
        query_embedding = self._get_embedding(question)
        
        # Search for relevant documents
        search_results = self.qdrant.search(
            collection_name=collection_name,
            query_vector=query_embedding,
            limit=top_k,
            score_threshold=0.5
        )
        
        # Prepare context
        context = "\n".join([
            result.payload["text"] 
            for result in search_results
        ])
        
        # Generate answer using context
        prompt = f"""Context: {context}

Question: {question}

Answer based on the provided context:"""
        
        response = requests.post(
            f"{self.ollama_base}/api/generate",
            json={
                "model": "deepseek-r1:8b",
                "prompt": prompt,
                "stream": False,
                "options": {"temperature": 0.3}
            }
        )
        
        return {
            "answer": response.json()["response"],
            "sources": [r.payload for r in search_results],
            "scores": [r.score for r in search_results]
        }
    
    def _get_embedding(self, text):
        """Get embedding from Ollama"""
        response = requests.post(
            f"{self.ollama_base}/api/embeddings",
            json={"model": "nomic-embed-text", "prompt": text}
        )
        return response.json()["embedding"]

# Usage example
rag = RAGPipeline("your-ip", "your-ip")

# Create knowledge base
documents = [
    {
        "text": "GeuseMaker is an AI infrastructure platform that deploys on AWS",
        "title": "GeuseMaker Overview",
        "category": "platform"
    },
    {
        "text": "Unity is the event-driven deployment system used by GeuseMaker",
        "title": "Unity System",
        "category": "deployment"
    },
    {
        "text": "Ollama provides local LLM inference with models like DeepSeek-R1",
        "title": "Ollama Service",
        "category": "ai"
    }
]

rag.create_knowledge_base("geusemaker_docs", documents)

# Query the knowledge base
result = rag.query("geusemaker_docs", "What is GeuseMaker?")
print("Answer:", result["answer"])
print("Sources:", len(result["sources"]))
```

## Performance Optimization

### Indexing

Qdrant automatically indexes vectors. Monitor indexing status:

```bash
curl http://your-ip:6333/collections/documents
```

### Memory Usage

Configure memory mapping for large collections:

```json
{
  "optimizers_config": {
    "memmap_threshold": 20000
  }
}
```

### Batch Operations

Use batch operations for better performance:

```python
# Batch upsert (more efficient)
client.upsert(collection_name="documents", points=large_point_list)

# Instead of individual upserts
for point in large_point_list:
    client.upsert(collection_name="documents", points=[point])
```

## Monitoring

### Collection Statistics

```bash
curl http://your-ip:6333/collections/documents
```

### Health Monitoring Script

```bash
#!/bin/bash
check_qdrant_health() {
    local response=$(curl -s http://your-ip:6333/health)
    if echo "$response" | jq -e '.status == "ok"' > /dev/null 2>&1; then
        echo "✅ Qdrant is healthy"
        return 0
    else
        echo "❌ Qdrant is unhealthy"
        return 1
    fi
}

check_qdrant_health
```

---

**Next**: [Crawl4AI API Reference](crawl4ai-service.md) | [Back to API Overview](README.md)
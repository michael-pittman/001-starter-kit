# Crawl4AI Service API Reference

> Complete API documentation for Crawl4AI web scraping and content extraction

## Overview

Crawl4AI is a web scraping service that extracts clean, structured content from web pages. It's optimized for AI applications and provides intelligent content extraction with support for JavaScript-heavy sites.

**Base URL**: `http://your-instance-ip:11235`
**Authentication**: None (local service)
**Rate Limits**: 30 requests/minute, 5 concurrent requests

## Core API Endpoints

### Basic Web Crawling

Extract content from a web page.

```bash
POST /crawl
```

**Request Body:**
```json
{
  "url": "https://example.com",
  "extraction_strategy": "LLMExtractionStrategy",
  "chunking_strategy": "RegexChunking",
  "bypass_cache": false,
  "include_raw_html": false
}
```

**Example Request:**
```bash
curl -X POST http://your-ip:11235/crawl \
  -H "Content-Type: application/json" \
  -d '{
    "url": "https://example.com/article",
    "extraction_strategy": "LLMExtractionStrategy",
    "chunking_strategy": "RegexChunking",
    "bypass_cache": false,
    "include_raw_html": false
  }'
```

**Example Response:**
```json
{
  "success": true,
  "data": {
    "url": "https://example.com/article",
    "title": "Example Article Title",
    "markdown": "# Example Article Title\n\nThis is the main content...",
    "cleaned_html": "<h1>Example Article Title</h1><p>This is the main content...</p>",
    "extracted_content": [
      {
        "content": "This is a paragraph of text",
        "type": "text",
        "chunk_index": 0
      }
    ],
    "links": [
      {
        "url": "https://example.com/link",
        "text": "Link text",
        "type": "internal"
      }
    ],
    "images": [
      {
        "url": "https://example.com/image.jpg",
        "alt": "Image description",
        "title": "Image title"
      }
    ],
    "metadata": {
      "title": "Example Article Title",
      "description": "Article description",
      "keywords": ["keyword1", "keyword2"],
      "author": "Author Name",
      "language": "en",
      "word_count": 500,
      "reading_time": "2 min"
    }
  },
  "execution_time": 2.5,
  "timestamp": "2024-01-01T12:00:00Z"
}
```

### Batch Crawling

Crawl multiple URLs simultaneously.

```bash
POST /crawl/batch
```

**Request Body:**
```json
{
  "urls": [
    "https://example.com/page1",
    "https://example.com/page2",
    "https://example.com/page3"
  ],
  "extraction_strategy": "LLMExtractionStrategy",
  "max_concurrent": 3
}
```

**Example Request:**
```bash
curl -X POST http://your-ip:11235/crawl/batch \
  -H "Content-Type: application/json" \
  -d '{
    "urls": [
      "https://news.ycombinator.com",
      "https://github.com/trending",
      "https://stackoverflow.com"
    ],
    "extraction_strategy": "CosineClusteringStrategy",
    "max_concurrent": 2
  }'
```

### Screenshot Capture

Capture screenshots of web pages.

```bash
POST /screenshot
```

**Request Body:**
```json
{
  "url": "https://example.com",
  "full_page": true,
  "format": "png",
  "quality": 80,
  "viewport": {
    "width": 1920,
    "height": 1080
  }
}
```

**Example Request:**
```bash
curl -X POST http://your-ip:11235/screenshot \
  -H "Content-Type: application/json" \
  -d '{
    "url": "https://example.com",
    "full_page": true,
    "format": "png",
    "quality": 90
  }'
```

**Response:**
```json
{
  "success": true,
  "data": {
    "screenshot": "base64-encoded-image-data",
    "format": "png",
    "width": 1920,
    "height": 1080,
    "size": 256000
  }
}
```

## Extraction Strategies

### LLM Extraction Strategy

Uses AI to extract structured content based on prompts.

```json
{
  "extraction_strategy": "LLMExtractionStrategy",
  "extraction_config": {
    "provider": "ollama",
    "model": "deepseek-r1:8b",
    "api_base": "http://localhost:11434",
    "instruction": "Extract the main article content, title, and summary",
    "schema": {
      "title": "string",
      "content": "string",
      "summary": "string",
      "tags": ["string"]
    }
  }
}
```

### Cosine Clustering Strategy

Groups similar content using vector similarity.

```json
{
  "extraction_strategy": "CosineClusteringStrategy",
  "extraction_config": {
    "semantic_filter": "article content",
    "word_count_threshold": 10,
    "max_dist": 0.2,
    "linkage_method": "ward",
    "top_k": 3
  }
}
```

### JSON CSS Extraction

Extract specific elements using CSS selectors.

```json
{
  "extraction_strategy": "JsonCssExtractionStrategy",
  "extraction_config": {
    "schema": {
      "name": "Article",
      "baseSelector": "article",
      "fields": [
        {
          "name": "title",
          "selector": "h1",
          "type": "text"
        },
        {
          "name": "content",
          "selector": ".content",
          "type": "text"
        },
        {
          "name": "author",
          "selector": ".author",
          "type": "text"
        }
      ]
    }
  }
}
```

## Chunking Strategies

### Regex Chunking

Split content using regular expressions.

```json
{
  "chunking_strategy": "RegexChunking",
  "chunking_config": {
    "patterns": [
      "\\n\\n",
      "\\n",
      "\\. "
    ]
  }
}
```

### Fixed Length Chunking

Split content into fixed-size chunks.

```json
{
  "chunking_strategy": "FixedLengthWordChunking",
  "chunking_config": {
    "chunk_size": 1000,
    "overlap": 200
  }
}
```

### Semantic Chunking

Split content based on semantic similarity.

```json
{
  "chunking_strategy": "SemanticChunking",
  "chunking_config": {
    "embedding_provider": "ollama",
    "similarity_threshold": 0.8
  }
}
```

## Content Processing

### PDF Extraction

Extract content from PDF files.

```bash
POST /extract/pdf
```

**Request Body (multipart/form-data):**
```bash
curl -X POST http://your-ip:11235/extract/pdf \
  -F "file=@document.pdf" \
  -F "extraction_strategy=LLMExtractionStrategy"
```

### Image Text Extraction (OCR)

Extract text from images.

```bash
POST /extract/image
```

**Request Body:**
```json
{
  "image_url": "https://example.com/image.jpg",
  "ocr_strategy": "TesseractOCR",
  "language": "eng"
}
```

### Markdown Conversion

Convert HTML content to clean Markdown.

```bash
POST /convert/markdown
```

**Request Body:**
```json
{
  "html": "<h1>Title</h1><p>Content</p>",
  "options": {
    "strip_tags": ["script", "style"],
    "convert_links": true,
    "preserve_images": true
  }
}
```

## Advanced Features

### JavaScript Execution

Execute JavaScript before content extraction.

```json
{
  "url": "https://spa-example.com",
  "js_code": [
    "window.scrollTo(0, document.body.scrollHeight);",
    "await new Promise(resolve => setTimeout(resolve, 2000));"
  ],
  "wait_for": {
    "selector": ".dynamic-content",
    "timeout": 10000
  }
}
```

### Custom Headers and Cookies

Set custom headers and cookies for requests.

```json
{
  "url": "https://example.com",
  "headers": {
    "User-Agent": "CustomBot/1.0",
    "Authorization": "Bearer token123"
  },
  "cookies": {
    "session_id": "abc123",
    "preferences": "dark_mode"
  }
}
```

### Proxy Support

Use proxy servers for crawling.

```json
{
  "url": "https://example.com",
  "proxy": {
    "server": "http://proxy.example.com:8080",
    "username": "user",
    "password": "pass"
  }
}
```

## Health and Monitoring

### Health Check

Check service health and status.

```bash
GET /health
```

**Example Request:**
```bash
curl http://your-ip:11235/health
```

**Example Response:**
```json
{
  "status": "healthy",
  "version": "0.2.77",
  "uptime": 3600,
  "active_crawls": 2,
  "queue_size": 5,
  "memory_usage": "45%",
  "browser_status": "running"
}
```

### Statistics

Get crawling statistics and metrics.

```bash
GET /stats
```

**Example Response:**
```json
{
  "total_crawls": 1000,
  "successful_crawls": 950,
  "failed_crawls": 50,
  "average_response_time": 2.3,
  "cache_hit_rate": 0.75,
  "today": {
    "crawls": 100,
    "data_extracted": "50MB"
  }
}
```

## Integration Examples

### Python Integration

```python
import requests
import json
from typing import List, Dict, Optional

class Crawl4AIClient:
    def __init__(self, base_url: str = "http://localhost:11235"):
        self.base_url = base_url
    
    def crawl(
        self, 
        url: str, 
        extraction_strategy: str = "LLMExtractionStrategy",
        **kwargs
    ) -> Dict:
        """Crawl a single URL"""
        payload = {
            "url": url,
            "extraction_strategy": extraction_strategy,
            **kwargs
        }
        
        response = requests.post(
            f"{self.base_url}/crawl",
            json=payload
        )
        return response.json()
    
    def batch_crawl(
        self, 
        urls: List[str], 
        extraction_strategy: str = "LLMExtractionStrategy",
        max_concurrent: int = 3
    ) -> Dict:
        """Crawl multiple URLs"""
        payload = {
            "urls": urls,
            "extraction_strategy": extraction_strategy,
            "max_concurrent": max_concurrent
        }
        
        response = requests.post(
            f"{self.base_url}/crawl/batch",
            json=payload
        )
        return response.json()
    
    def screenshot(
        self, 
        url: str, 
        full_page: bool = True,
        format: str = "png",
        quality: int = 80
    ) -> Dict:
        """Take a screenshot of a webpage"""
        payload = {
            "url": url,
            "full_page": full_page,
            "format": format,
            "quality": quality
        }
        
        response = requests.post(
            f"{self.base_url}/screenshot",
            json=payload
        )
        return response.json()
    
    def extract_with_llm(
        self, 
        url: str, 
        instruction: str,
        schema: Optional[Dict] = None
    ) -> Dict:
        """Extract content using LLM with custom instruction"""
        extraction_config = {
            "provider": "ollama",
            "model": "deepseek-r1:8b",
            "api_base": "http://localhost:11434",
            "instruction": instruction
        }
        
        if schema:
            extraction_config["schema"] = schema
        
        return self.crawl(
            url=url,
            extraction_strategy="LLMExtractionStrategy",
            extraction_config=extraction_config
        )

# Usage examples
client = Crawl4AIClient("http://your-ip:11235")

# Basic crawling
result = client.crawl("https://example.com/article")
print("Title:", result["data"]["title"])
print("Content length:", len(result["data"]["markdown"]))

# Batch crawling
urls = [
    "https://news.ycombinator.com",
    "https://github.com/trending",
    "https://stackoverflow.com"
]
batch_result = client.batch_crawl(urls, max_concurrent=2)

# LLM extraction with custom schema
schema = {
    "title": "string",
    "summary": "string", 
    "key_points": ["string"],
    "sentiment": "string"
}

llm_result = client.extract_with_llm(
    "https://example.com/news-article",
    "Extract the main information from this news article",
    schema
)

# Take screenshot
screenshot_result = client.screenshot("https://example.com", full_page=True)
```

### JavaScript Integration

```javascript
class Crawl4AIClient {
    constructor(baseUrl = 'http://localhost:11235') {
        this.baseUrl = baseUrl;
    }
    
    async crawl(url, options = {}) {
        const payload = {
            url,
            extraction_strategy: 'LLMExtractionStrategy',
            ...options
        };
        
        const response = await fetch(`${this.baseUrl}/crawl`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload)
        });
        
        return response.json();
    }
    
    async batchCrawl(urls, options = {}) {
        const payload = {
            urls,
            extraction_strategy: 'LLMExtractionStrategy',
            max_concurrent: 3,
            ...options
        };
        
        const response = await fetch(`${this.baseUrl}/crawl/batch`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload)
        });
        
        return response.json();
    }
    
    async screenshot(url, options = {}) {
        const payload = {
            url,
            full_page: true,
            format: 'png',
            quality: 80,
            ...options
        };
        
        const response = await fetch(`${this.baseUrl}/screenshot`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload)
        });
        
        return response.json();
    }
    
    async extractWithLLM(url, instruction, schema = null) {
        const extractionConfig = {
            provider: 'ollama',
            model: 'deepseek-r1:8b',
            api_base: 'http://localhost:11434',
            instruction
        };
        
        if (schema) {
            extractionConfig.schema = schema;
        }
        
        return this.crawl(url, {
            extraction_strategy: 'LLMExtractionStrategy',
            extraction_config: extractionConfig
        });
    }
}

// Usage examples
const client = new Crawl4AIClient('http://your-ip:11235');

// Basic crawling
const result = await client.crawl('https://example.com/article');
console.log('Title:', result.data.title);
console.log('Word count:', result.data.metadata.word_count);

// Extract structured data
const schema = {
    title: 'string',
    summary: 'string',
    tags: ['string'],
    difficulty: 'string'
};

const structuredResult = await client.extractWithLLM(
    'https://example.com/tutorial',
    'Extract key information from this tutorial',
    schema
);

console.log('Structured data:', structuredResult.data.extracted_content);
```

## AI-Powered Content Analysis

### Content Summarization

```python
def summarize_webpage(client, url):
    """Summarize webpage content using AI"""
    result = client.extract_with_llm(
        url=url,
        instruction="Provide a concise summary of the main points",
        schema={
            "summary": "string",
            "key_points": ["string"],
            "word_count_estimate": "number"
        }
    )
    return result["data"]["extracted_content"]

# Usage
summary = summarize_webpage(client, "https://example.com/long-article")
print("Summary:", summary["summary"])
```

### Sentiment Analysis

```python
def analyze_sentiment(client, url):
    """Analyze sentiment of webpage content"""
    result = client.extract_with_llm(
        url=url,
        instruction="Analyze the sentiment and tone of this content",
        schema={
            "sentiment": "string",
            "confidence": "number",
            "emotional_tone": "string",
            "key_phrases": ["string"]
        }
    )
    return result["data"]["extracted_content"]

# Usage
sentiment = analyze_sentiment(client, "https://example.com/review")
print("Sentiment:", sentiment["sentiment"])
```

## Performance Optimization

### Caching

Crawl4AI includes intelligent caching:

```json
{
  "url": "https://example.com",
  "bypass_cache": false,
  "cache_strategy": "BasicCacheStrategy",
  "cache_ttl": 3600
}
```

### Concurrent Crawling

Optimize batch operations:

```python
# Optimal concurrent requests
client.batch_crawl(
    urls=large_url_list,
    max_concurrent=5,  # Balance between speed and resource usage
    extraction_strategy="CosineClusteringStrategy"
)
```

### Memory Management

Monitor and optimize memory usage:

```bash
# Check memory usage
curl http://your-ip:11235/stats
```

## Error Handling

### Common Errors

| Error Code | Description | Solution |
|------------|-------------|----------|
| `URL_INVALID` | Invalid URL format | Check URL syntax |
| `TIMEOUT` | Request timeout | Increase timeout or check connectivity |
| `EXTRACTION_FAILED` | Content extraction failed | Try different extraction strategy |
| `RATE_LIMITED` | Too many requests | Implement request throttling |
| `BROWSER_ERROR` | Browser automation failed | Restart service or check resources |

### Error Response Format

```json
{
  "success": false,
  "error": {
    "code": "EXTRACTION_FAILED",
    "message": "Failed to extract content using LLM strategy",
    "details": {
      "url": "https://example.com",
      "strategy": "LLMExtractionStrategy",
      "reason": "Model unavailable"
    }
  },
  "timestamp": "2024-01-01T12:00:00Z"
}
```

---

**Next**: [Monitoring API Reference](monitoring.md) | [Back to API Overview](README.md)
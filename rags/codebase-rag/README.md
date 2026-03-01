# Codebase RAG

Index and query a codebase using vector embeddings. Walks source files, chunks by function/class boundaries (Python) or fixed line windows, embeds with OpenAI, and stores in ChromaDB.

## Setup

```bash
pip install -r requirements.txt
cp .env.example .env
# Edit .env and add your OPENAI_API_KEY
```

## Usage

**Index a codebase:**
```bash
python index.py /path/to/your/project
python index.py /path/to/project --chunk-size 200 --overlap 30
python index.py /path/to/project --reset  # rebuild from scratch
```

**Query the index:**
```bash
python query.py "How does authentication work?"
python query.py "database models" --top-k 10
python query.py "API routes" --ext .ts
python query.py "error handling" --json
```

## How It Works

- **File discovery**: Walks `.py`, `.js`, `.ts`, `.md` and more; skips `node_modules`, `.git`, `__pycache__`
- **Chunking**: Python files are split on `class`/`def` boundaries. All other files use a sliding window (300 lines, 50 overlap by default)
- **Embedding**: OpenAI `text-embedding-3-small`
- **Storage**: Local ChromaDB with cosine similarity
- **Query**: Returns top-K chunks with file path, line numbers, and distance score

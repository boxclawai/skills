# Docs RAG

Index and query markdown, text, and RST documents using FAISS and LangChain. Splits documents by markdown headers or fixed chunk sizes, embeds with OpenAI, and stores in a local FAISS index.

## Setup

```bash
pip install -r requirements.txt
cp .env.example .env
# Edit .env and add your OPENAI_API_KEY
```

Place your documents in the `documents/` directory (or set `DOCS_DIR`).

## Usage

**Index documents:**
```bash
python index.py
python index.py --docs-dir /path/to/docs
python index.py --chunk-size 500 --no-header-split
```

**Query the index:**
```bash
python query.py "What is the deployment process?"
python query.py "API authentication" --top-k 10
python query.py "setup" --source README.md
python query.py "configuration" --json
```

## How It Works

- **File types**: `.md`, `.txt`, `.rst`
- **Splitting**: Markdown files are split by headers first, then by character limit. Other files use recursive character splitting
- **Embedding**: OpenAI `text-embedding-3-small` via LangChain
- **Storage**: Local FAISS index with L2 distance
- **Query**: Returns top-K passages with source file and section headers

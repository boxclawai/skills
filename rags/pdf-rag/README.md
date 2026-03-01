# PDF RAG

Extract text from PDFs, chunk, embed, and query using ChromaDB. Supports page-level and paragraph-level chunking with page number tracking.

## Setup

```bash
pip install -r requirements.txt
cp .env.example .env
# Edit .env and add your OPENAI_API_KEY
```

Place your PDF files in the `pdfs/` directory (or set `PDF_DIR`).

## Usage

**Index PDFs:**
```bash
python index.py
python index.py --pdf-dir /path/to/pdfs
python index.py --chunk-mode page        # one chunk per page
python index.py --chunk-size 800 --reset  # rebuild index
```

**Query the index:**
```bash
python query.py "What are the key findings?"
python query.py "methodology" --top-k 10
python query.py "budget" --pdf financial_report.pdf
python query.py "conclusions" --json
python query.py --list-pdfs  # show all indexed PDFs
```

## How It Works

- **Extraction**: PyPDF2 reads text page-by-page from each PDF
- **Chunking**: Two modes -- `paragraph` (merges pages, splits by character limit with overlap) or `page` (one chunk per page)
- **Page tracking**: Each chunk records which page(s) it came from
- **Embedding**: OpenAI `text-embedding-3-small`
- **Storage**: Local ChromaDB with cosine similarity
- **Query**: Returns top-K passages with PDF filename and page numbers

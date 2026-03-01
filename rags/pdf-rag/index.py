#!/usr/bin/env python3
"""
Extract text from PDFs, chunk, embed, and store in ChromaDB.

Reads all PDF files from a directory, extracts text page-by-page using
PyPDF2, splits into chunks (by paragraph or by page), embeds with OpenAI,
and stores in a local ChromaDB collection.

Usage:
    python index.py
    python index.py --pdf-dir /path/to/pdfs
    python index.py --chunk-mode page
    python index.py --chunk-size 800 --reset
"""

import argparse
import hashlib
import os
import re
import sys
from pathlib import Path

import chromadb
from chromadb.utils.embedding_functions import OpenAIEmbeddingFunction
from PyPDF2 import PdfReader
from langchain.text_splitter import RecursiveCharacterTextSplitter

from config import (
    OPENAI_API_KEY,
    EMBEDDING_MODEL,
    CHROMA_PERSIST_DIR,
    COLLECTION_NAME,
    PDF_DIR,
    CHUNK_MODE,
    CHUNK_SIZE,
    CHUNK_OVERLAP,
)


# ---------------------------------------------------------------------------
# PDF text extraction
# ---------------------------------------------------------------------------

def extract_pages(pdf_path: str) -> list[dict]:
    """Extract text from each page of a PDF. Returns a list of
    {page_num, text} dicts (1-indexed page numbers)."""
    try:
        reader = PdfReader(pdf_path)
    except Exception as exc:
        print(f"  [skip] Cannot read {pdf_path}: {exc}", file=sys.stderr)
        return []

    pages: list[dict] = []
    for i, page in enumerate(reader.pages):
        text = page.extract_text() or ""
        text = text.strip()
        if text:
            pages.append({"page_num": i + 1, "text": text})
    return pages


# ---------------------------------------------------------------------------
# Chunking
# ---------------------------------------------------------------------------

def chunk_by_page(pages: list[dict], pdf_name: str) -> list[dict]:
    """One chunk per page -- simple and preserves page boundaries."""
    chunks: list[dict] = []
    for p in pages:
        chunks.append({
            "text": p["text"],
            "pdf_name": pdf_name,
            "page_num": p["page_num"],
            "page_end": p["page_num"],
        })
    return chunks


def chunk_by_paragraph(
    pages: list[dict],
    pdf_name: str,
    chunk_size: int,
    chunk_overlap: int,
) -> list[dict]:
    """Merge all page text, split by paragraph boundaries into sized chunks,
    and track which pages each chunk spans."""
    splitter = RecursiveCharacterTextSplitter(
        chunk_size=chunk_size,
        chunk_overlap=chunk_overlap,
        separators=["\n\n", "\n", ". ", " ", ""],
    )

    # Build a mapping: character offset -> page number
    full_text = ""
    offset_to_page: list[tuple[int, int, int]] = []  # (start, end, page_num)
    for p in pages:
        start = len(full_text)
        full_text += p["text"] + "\n\n"
        end = len(full_text)
        offset_to_page.append((start, end, p["page_num"]))

    if not full_text.strip():
        return []

    raw_chunks = splitter.split_text(full_text)
    chunks: list[dict] = []
    search_start = 0

    for chunk_text in raw_chunks:
        # Find the position of this chunk in the full text
        pos = full_text.find(chunk_text, search_start)
        if pos == -1:
            pos = full_text.find(chunk_text)
        chunk_end = pos + len(chunk_text) if pos >= 0 else len(full_text)

        # Determine page range for this chunk
        page_start = float('inf')
        page_end = 0
        for seg_start, seg_end, page_num in offset_to_page:
            if pos < seg_end and chunk_end > seg_start:
                page_start = min(page_start, page_num)
                page_end = max(page_end, page_num)
        if page_start == float('inf'):
            page_start = pages[0]["page_num"] if pages else 1
            page_end = page_start

        if pos >= 0:
            search_start = pos + 1

        chunks.append({
            "text": chunk_text.strip(),
            "pdf_name": pdf_name,
            "page_num": page_start,
            "page_end": page_end,
        })

    return chunks


def chunk_pdf(
    pdf_path: str,
    chunk_mode: str,
    chunk_size: int,
    chunk_overlap: int,
) -> list[dict]:
    """Extract and chunk a single PDF."""
    pdf_name = os.path.basename(pdf_path)
    pages = extract_pages(pdf_path)
    if not pages:
        return []

    if chunk_mode == "page":
        return chunk_by_page(pages, pdf_name)
    else:
        return chunk_by_paragraph(pages, pdf_name, chunk_size, chunk_overlap)


# ---------------------------------------------------------------------------
# Indexing
# ---------------------------------------------------------------------------

def build_index(
    pdf_dir: str,
    chunk_mode: str,
    chunk_size: int,
    chunk_overlap: int,
    reset: bool = False,
) -> None:
    """Walk PDFs, chunk, embed, and store in ChromaDB."""
    if not OPENAI_API_KEY:
        sys.exit("Error: OPENAI_API_KEY is not set. Export it or add to .env")

    pdf_dir = os.path.abspath(pdf_dir)
    if not os.path.isdir(pdf_dir):
        sys.exit(f"Error: PDF directory '{pdf_dir}' does not exist.")

    # Discover PDFs
    pdf_files = sorted(
        str(p) for p in Path(pdf_dir).rglob("*.pdf")
    )
    if not pdf_files:
        sys.exit(f"No PDF files found in '{pdf_dir}'.")

    print(f"Found {len(pdf_files)} PDF(s) in: {pdf_dir}")
    print(f"Chunk mode: {chunk_mode}, size: {chunk_size}, overlap: {chunk_overlap}")

    # ChromaDB
    client = chromadb.PersistentClient(path=CHROMA_PERSIST_DIR)
    embed_fn = OpenAIEmbeddingFunction(
        api_key=OPENAI_API_KEY,
        model_name=EMBEDDING_MODEL,
    )

    if reset:
        try:
            client.delete_collection(COLLECTION_NAME)
            print("Deleted existing collection.")
        except ValueError:
            pass

    collection = client.get_or_create_collection(
        name=COLLECTION_NAME,
        embedding_function=embed_fn,
        metadata={"hnsw:space": "cosine"},
    )

    all_chunks: list[dict] = []
    for pdf_path in pdf_files:
        chunks = chunk_pdf(pdf_path, chunk_mode, chunk_size, chunk_overlap)
        all_chunks.extend(chunks)
        print(f"  {os.path.basename(pdf_path)}: {len(chunks)} chunk(s)")

    if not all_chunks:
        sys.exit("No extractable text found in any PDF.")

    print(f"Total: {len(all_chunks)} chunks. Embedding...")

    # Batch upsert
    batch_size = 500
    for i in range(0, len(all_chunks), batch_size):
        batch = all_chunks[i : i + batch_size]
        ids = [
            hashlib.sha256(
                f"{c['pdf_name']}:p{c['page_num']}-{c['page_end']}:{idx}".encode()
            ).hexdigest()
            for idx, c in enumerate(batch, start=i)
        ]
        documents = [c["text"] for c in batch]
        metadatas = [
            {
                "pdf_name": c["pdf_name"],
                "page_num": c["page_num"],
                "page_end": c["page_end"],
            }
            for c in batch
        ]
        collection.upsert(ids=ids, documents=documents, metadatas=metadatas)
        print(f"  Upserted {min(i + batch_size, len(all_chunks))}/{len(all_chunks)}")

    print("Indexing complete.")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Index PDF documents into ChromaDB for RAG retrieval."
    )
    parser.add_argument(
        "--pdf-dir",
        default=PDF_DIR,
        help=f"Directory containing PDF files (default: {PDF_DIR}).",
    )
    parser.add_argument(
        "--chunk-mode",
        choices=["paragraph", "page"],
        default=CHUNK_MODE,
        help=f"Chunking strategy (default: {CHUNK_MODE}).",
    )
    parser.add_argument(
        "--chunk-size",
        type=int,
        default=CHUNK_SIZE,
        help=f"Max characters per chunk in paragraph mode (default: {CHUNK_SIZE}).",
    )
    parser.add_argument(
        "--chunk-overlap",
        type=int,
        default=CHUNK_OVERLAP,
        help=f"Overlap characters between chunks (default: {CHUNK_OVERLAP}).",
    )
    parser.add_argument(
        "--reset",
        action="store_true",
        help="Delete the existing collection before indexing.",
    )
    args = parser.parse_args()
    build_index(
        args.pdf_dir,
        args.chunk_mode,
        args.chunk_size,
        args.chunk_overlap,
        args.reset,
    )


if __name__ == "__main__":
    main()

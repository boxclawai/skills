#!/usr/bin/env python3
"""
Index a codebase into ChromaDB for RAG retrieval.

Walks the target directory, reads supported source files, chunks them by
function/class boundaries (Python) or by fixed line windows, embeds each
chunk with OpenAI, and stores everything in a local ChromaDB collection.

Usage:
    python index.py /path/to/codebase
    python index.py /path/to/codebase --chunk-size 200 --overlap 30
"""

import argparse
import os
import re
import sys
import hashlib
from pathlib import Path
from typing import Generator

import chromadb
from chromadb.utils.embedding_functions import OpenAIEmbeddingFunction

from config import (
    OPENAI_API_KEY,
    EMBEDDING_MODEL,
    EMBEDDING_DIMENSIONS,
    CHROMA_PERSIST_DIR,
    COLLECTION_NAME,
    SUPPORTED_EXTENSIONS,
    SKIP_DIRS,
    CHUNK_SIZE_LINES,
    CHUNK_OVERLAP_LINES,
)


# ---------------------------------------------------------------------------
# Chunking helpers
# ---------------------------------------------------------------------------

_PY_BOUNDARY = re.compile(r"^(class |def |async def )", re.MULTILINE)


def _chunk_python_by_symbols(source: str, filepath: str) -> list[dict]:
    """Split Python source on class/function boundaries, falling back to
    line-window chunking when no symbols are found."""
    lines = source.splitlines(keepends=True)
    if not _PY_BOUNDARY.search(source):
        return _chunk_by_lines(lines, filepath)

    chunks: list[dict] = []
    boundary_indices = [
        i for i, line in enumerate(lines) if _PY_BOUNDARY.match(line)
    ]
    # Add file end as a sentinel
    boundary_indices.append(len(lines))

    for idx in range(len(boundary_indices) - 1):
        start = boundary_indices[idx]
        end = boundary_indices[idx + 1]
        text = "".join(lines[start:end]).rstrip()
        if text.strip():
            chunks.append({
                "text": text,
                "start_line": start + 1,
                "end_line": end,
                "filepath": filepath,
            })
    return chunks


def _chunk_by_lines(
    lines: list[str],
    filepath: str,
    chunk_size: int = CHUNK_SIZE_LINES,
    overlap: int = CHUNK_OVERLAP_LINES,
) -> list[dict]:
    """Sliding-window chunking over raw lines."""
    chunks: list[dict] = []
    total = len(lines)
    start = 0
    while start < total:
        end = min(start + chunk_size, total)
        text = "".join(lines[start:end]).rstrip()
        if text.strip():
            chunks.append({
                "text": text,
                "start_line": start + 1,
                "end_line": end,
                "filepath": filepath,
            })
        start += chunk_size - overlap
    return chunks


def chunk_file(filepath: str, root: str, chunk_size: int, overlap: int) -> list[dict]:
    """Read a file and return a list of chunk dicts."""
    rel = os.path.relpath(filepath, root)
    try:
        with open(filepath, "r", encoding="utf-8", errors="replace") as fh:
            source = fh.read()
    except OSError as exc:
        print(f"  [skip] Cannot read {rel}: {exc}", file=sys.stderr)
        return []

    if not source.strip():
        return []

    if filepath.endswith(".py"):
        chunks = _chunk_python_by_symbols(source, rel)
    else:
        lines = source.splitlines(keepends=True)
        chunks = _chunk_by_lines(lines, rel, chunk_size, overlap)
    return chunks


# ---------------------------------------------------------------------------
# File discovery
# ---------------------------------------------------------------------------

def walk_codebase(root: str) -> Generator[str, None, None]:
    """Yield absolute paths for supported source files under *root*."""
    for dirpath, dirnames, filenames in os.walk(root):
        # Prune skipped directories in-place so os.walk won't descend
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for fname in filenames:
            if Path(fname).suffix in SUPPORTED_EXTENSIONS:
                yield os.path.join(dirpath, fname)


# ---------------------------------------------------------------------------
# Indexing
# ---------------------------------------------------------------------------

def build_index(root: str, chunk_size: int, overlap: int, reset: bool = False) -> None:
    """Walk, chunk, embed, and store the codebase."""
    if not OPENAI_API_KEY:
        sys.exit("Error: OPENAI_API_KEY is not set. Export it or add to .env")

    root = os.path.abspath(root)
    if not os.path.isdir(root):
        sys.exit(f"Error: '{root}' is not a directory")

    print(f"Indexing codebase at: {root}")
    print(f"Chunk size: {chunk_size} lines, overlap: {overlap} lines")

    # ChromaDB client
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
    file_count = 0
    for fpath in walk_codebase(root):
        chunks = chunk_file(fpath, root, chunk_size, overlap)
        all_chunks.extend(chunks)
        file_count += 1

    if not all_chunks:
        sys.exit("No indexable content found.")

    print(f"Found {file_count} files -> {len(all_chunks)} chunks. Embedding...")

    # Batch upsert (ChromaDB recommends batches <= 5000)
    batch_size = 500
    for i in range(0, len(all_chunks), batch_size):
        batch = all_chunks[i : i + batch_size]
        ids = [
            hashlib.sha256(
                f"{c['filepath']}:{c['start_line']}-{c['end_line']}".encode()
            ).hexdigest()
            for c in batch
        ]
        documents = [c["text"] for c in batch]
        metadatas = [
            {
                "filepath": c["filepath"],
                "start_line": c["start_line"],
                "end_line": c["end_line"],
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
    parser = argparse.ArgumentParser(description="Index a codebase for RAG retrieval.")
    parser.add_argument("codebase_path", help="Root directory of the codebase to index.")
    parser.add_argument(
        "--chunk-size",
        type=int,
        default=CHUNK_SIZE_LINES,
        help=f"Lines per chunk (default: {CHUNK_SIZE_LINES}).",
    )
    parser.add_argument(
        "--overlap",
        type=int,
        default=CHUNK_OVERLAP_LINES,
        help=f"Overlap lines between chunks (default: {CHUNK_OVERLAP_LINES}).",
    )
    parser.add_argument(
        "--reset",
        action="store_true",
        help="Delete the existing collection before indexing.",
    )
    args = parser.parse_args()
    build_index(args.codebase_path, args.chunk_size, args.overlap, args.reset)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
Index markdown, text, and RST documents into a FAISS vector store.

Reads all supported files from a documents directory, splits them using
LangChain's markdown-aware or recursive character splitters, embeds with
OpenAI, and persists the FAISS index locally.

Usage:
    python index.py
    python index.py --docs-dir /path/to/docs
    python index.py --docs-dir ./notes --chunk-size 500 --no-header-split
"""

import argparse
import os
import sys
from pathlib import Path

from langchain_community.vectorstores import FAISS
from langchain_openai import OpenAIEmbeddings
from langchain.text_splitter import (
    MarkdownHeaderTextSplitter,
    RecursiveCharacterTextSplitter,
)
from langchain.docstore.document import Document

from config import (
    OPENAI_API_KEY,
    EMBEDDING_MODEL,
    FAISS_INDEX_DIR,
    DOCS_DIR,
    SUPPORTED_EXTENSIONS,
    CHUNK_SIZE,
    CHUNK_OVERLAP,
    SPLIT_BY_HEADERS,
)


# ---------------------------------------------------------------------------
# Document loading
# ---------------------------------------------------------------------------

def load_documents(docs_dir: str) -> list[Document]:
    """Recursively load supported text files as LangChain Documents."""
    docs_path = Path(docs_dir).resolve()
    if not docs_path.is_dir():
        sys.exit(f"Error: Documents directory '{docs_path}' does not exist.")

    documents: list[Document] = []
    for root, _dirs, files in os.walk(docs_path):
        for fname in sorted(files):
            fpath = Path(root) / fname
            if fpath.suffix.lower() not in SUPPORTED_EXTENSIONS:
                continue
            try:
                text = fpath.read_text(encoding="utf-8", errors="replace")
            except OSError as exc:
                print(f"  [skip] {fpath}: {exc}", file=sys.stderr)
                continue
            if not text.strip():
                continue
            rel = str(fpath.relative_to(docs_path))
            documents.append(
                Document(page_content=text, metadata={"source": rel})
            )
    return documents


# ---------------------------------------------------------------------------
# Splitting
# ---------------------------------------------------------------------------

MARKDOWN_HEADERS = [
    ("#", "h1"),
    ("##", "h2"),
    ("###", "h3"),
    ("####", "h4"),
]


def split_documents(
    documents: list[Document],
    chunk_size: int,
    chunk_overlap: int,
    use_headers: bool,
) -> list[Document]:
    """Split documents into chunks, optionally respecting markdown headers."""
    all_chunks: list[Document] = []

    char_splitter = RecursiveCharacterTextSplitter(
        chunk_size=chunk_size,
        chunk_overlap=chunk_overlap,
        separators=["\n\n", "\n", ". ", " ", ""],
    )

    for doc in documents:
        is_markdown = doc.metadata["source"].endswith(".md")

        if is_markdown and use_headers:
            # First pass: split on markdown headers
            header_splitter = MarkdownHeaderTextSplitter(
                headers_to_split_on=MARKDOWN_HEADERS,
                strip_headers=False,
            )
            header_chunks = header_splitter.split_text(doc.page_content)
            # Second pass: ensure chunks respect size limits
            for hc in header_chunks:
                sub_chunks = char_splitter.split_text(hc.page_content)
                for text in sub_chunks:
                    merged_meta = {**doc.metadata, **hc.metadata}
                    all_chunks.append(
                        Document(page_content=text, metadata=merged_meta)
                    )
        else:
            sub_chunks = char_splitter.split_text(doc.page_content)
            for text in sub_chunks:
                all_chunks.append(
                    Document(page_content=text, metadata=dict(doc.metadata))
                )

    return all_chunks


# ---------------------------------------------------------------------------
# Index building
# ---------------------------------------------------------------------------

def build_index(
    docs_dir: str,
    chunk_size: int,
    chunk_overlap: int,
    use_headers: bool,
    index_dir: str,
) -> None:
    """Load, chunk, embed, and persist a FAISS index."""
    if not OPENAI_API_KEY:
        sys.exit("Error: OPENAI_API_KEY is not set. Export it or add to .env")

    print(f"Loading documents from: {os.path.abspath(docs_dir)}")
    raw_docs = load_documents(docs_dir)
    if not raw_docs:
        sys.exit("No supported documents found.")
    print(f"  Loaded {len(raw_docs)} file(s).")

    print(f"Splitting (chunk_size={chunk_size}, overlap={chunk_overlap}, "
          f"header_split={use_headers})...")
    chunks = split_documents(raw_docs, chunk_size, chunk_overlap, use_headers)
    print(f"  Produced {len(chunks)} chunk(s).")

    print("Embedding and building FAISS index...")
    embeddings = OpenAIEmbeddings(
        model=EMBEDDING_MODEL,
        openai_api_key=OPENAI_API_KEY,
    )
    vectorstore = FAISS.from_documents(chunks, embeddings)

    os.makedirs(index_dir, exist_ok=True)
    vectorstore.save_local(index_dir)
    print(f"Index saved to: {os.path.abspath(index_dir)}")
    print("Indexing complete.")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Index documents into a FAISS vector store."
    )
    parser.add_argument(
        "--docs-dir",
        default=DOCS_DIR,
        help=f"Directory containing documents (default: {DOCS_DIR}).",
    )
    parser.add_argument(
        "--chunk-size",
        type=int,
        default=CHUNK_SIZE,
        help=f"Maximum characters per chunk (default: {CHUNK_SIZE}).",
    )
    parser.add_argument(
        "--chunk-overlap",
        type=int,
        default=CHUNK_OVERLAP,
        help=f"Overlap characters between chunks (default: {CHUNK_OVERLAP}).",
    )
    parser.add_argument(
        "--no-header-split",
        action="store_true",
        help="Disable markdown header-aware splitting.",
    )
    parser.add_argument(
        "--index-dir",
        default=FAISS_INDEX_DIR,
        help=f"Directory to save the FAISS index (default: {FAISS_INDEX_DIR}).",
    )
    args = parser.parse_args()
    build_index(
        args.docs_dir,
        args.chunk_size,
        args.chunk_overlap,
        use_headers=not args.no_header_split,
        index_dir=args.index_dir,
    )


if __name__ == "__main__":
    main()

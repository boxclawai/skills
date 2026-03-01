#!/usr/bin/env python3
"""
Query the FAISS document index.

Returns relevant passages from indexed documents along with source file
information and optional header context.

Usage:
    python query.py "What is the deployment process?"
    python query.py "API authentication" --top-k 10
    python query.py "setup instructions" --json
"""

import argparse
import json as json_mod
import os
import sys
import textwrap

from langchain_community.vectorstores import FAISS
from langchain_openai import OpenAIEmbeddings

from config import (
    OPENAI_API_KEY,
    EMBEDDING_MODEL,
    FAISS_INDEX_DIR,
    TOP_K,
)


def load_vectorstore(index_dir: str) -> FAISS:
    """Load a persisted FAISS vectorstore."""
    if not os.path.isdir(index_dir):
        sys.exit(
            f"Error: Index directory '{index_dir}' not found. "
            "Run index.py first to build the index."
        )
    embeddings = OpenAIEmbeddings(
        model=EMBEDDING_MODEL,
        openai_api_key=OPENAI_API_KEY,
    )
    try:
        return FAISS.load_local(
            index_dir,
            embeddings,
            allow_dangerous_deserialization=True,
        )
    except Exception as exc:
        sys.exit(f"Error loading index: {exc}")


def query_index(
    question: str,
    top_k: int = TOP_K,
    index_dir: str = FAISS_INDEX_DIR,
    source_filter: str | None = None,
) -> list[dict]:
    """Query the FAISS index and return matching passages."""
    if not OPENAI_API_KEY:
        sys.exit("Error: OPENAI_API_KEY is not set. Export it or add to .env")

    vectorstore = load_vectorstore(index_dir)

    # FAISS similarity_search_with_score returns (Document, score) tuples
    # where lower score = closer match (L2 distance)
    results = vectorstore.similarity_search_with_score(question, k=top_k)

    hits: list[dict] = []
    for doc, score in results:
        meta = doc.metadata
        if source_filter and source_filter not in meta.get("source", ""):
            continue
        hit = {
            "source": meta.get("source", "unknown"),
            "score": round(float(score), 4),
            "text": doc.page_content,
        }
        # Include header context if available
        for key in ("h1", "h2", "h3", "h4"):
            if key in meta:
                hit[key] = meta[key]
        hits.append(hit)

    return hits


def format_results(hits: list[dict]) -> str:
    """Pretty-print query results for the terminal."""
    if not hits:
        return "No results found."

    parts: list[str] = []
    for i, hit in enumerate(hits, 1):
        header_parts = []
        for key in ("h1", "h2", "h3", "h4"):
            if key in hit:
                header_parts.append(f"{key}={hit[key]}")
        header_ctx = f"  [{', '.join(header_parts)}]" if header_parts else ""

        title = f"[{i}] {hit['source']}{header_ctx}  (score={hit['score']})"
        separator = "-" * min(len(title), 80)

        # Show a preview (first 15 lines)
        preview_lines = hit["text"].splitlines()[:15]
        preview = "\n".join(preview_lines)
        if len(hit["text"].splitlines()) > 15:
            preview += f"\n  ... ({len(hit['text'].splitlines()) - 15} more lines)"

        parts.append(f"{title}\n{separator}\n{preview}\n")
    return "\n".join(parts)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Query the indexed documents.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=textwrap.dedent("""\
            Examples:
              python query.py "How do I deploy the app?"
              python query.py "configuration options" --top-k 10
              python query.py "setup" --source README.md
              python query.py "API reference" --json
        """),
    )
    parser.add_argument("question", help="Natural-language query about the documents.")
    parser.add_argument(
        "--top-k",
        type=int,
        default=TOP_K,
        help=f"Number of results to return (default: {TOP_K}).",
    )
    parser.add_argument(
        "--index-dir",
        default=FAISS_INDEX_DIR,
        help=f"Path to the FAISS index directory (default: {FAISS_INDEX_DIR}).",
    )
    parser.add_argument(
        "--source",
        default=None,
        help="Filter results to a specific source filename.",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output results as JSON.",
    )
    args = parser.parse_args()

    hits = query_index(args.question, args.top_k, args.index_dir, args.source)

    if args.json:
        for h in hits:
            h["text_preview"] = "\n".join(h["text"].splitlines()[:10])
            del h["text"]
        print(json_mod.dumps(hits, indent=2))
    else:
        print(f"\nQuery: {args.question}")
        print(f"Results: {len(hits)}\n")
        print(format_results(hits))


if __name__ == "__main__":
    main()

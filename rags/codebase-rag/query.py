#!/usr/bin/env python3
"""
Query an indexed codebase stored in ChromaDB.

Returns the top-K most relevant code chunks with file paths and line
numbers. Optionally filters by file extension.

Usage:
    python query.py "How does the authentication middleware work?"
    python query.py "database connection" --top-k 10
    python query.py "error handling" --ext .py
"""

import argparse
import sys
import textwrap

import chromadb
from chromadb.utils.embedding_functions import OpenAIEmbeddingFunction

from config import (
    OPENAI_API_KEY,
    EMBEDDING_MODEL,
    CHROMA_PERSIST_DIR,
    COLLECTION_NAME,
    TOP_K,
)


def query_index(
    question: str,
    top_k: int = TOP_K,
    extension_filter: str | None = None,
) -> list[dict]:
    """Query ChromaDB and return matching chunks with metadata."""
    if not OPENAI_API_KEY:
        sys.exit("Error: OPENAI_API_KEY is not set. Export it or add to .env")

    client = chromadb.PersistentClient(path=CHROMA_PERSIST_DIR)
    embed_fn = OpenAIEmbeddingFunction(
        api_key=OPENAI_API_KEY,
        model_name=EMBEDDING_MODEL,
    )

    try:
        collection = client.get_collection(
            name=COLLECTION_NAME,
            embedding_function=embed_fn,
        )
    except ValueError:
        sys.exit(
            f"Error: Collection '{COLLECTION_NAME}' not found. "
            "Run index.py first to build the index."
        )

    where_filter = None
    if extension_filter:
        # ChromaDB metadata filter: filepath ends with extension
        where_filter = {"filepath": {"$contains": extension_filter}}

    results = collection.query(
        query_texts=[question],
        n_results=top_k,
        where=where_filter,
        include=["documents", "metadatas", "distances"],
    )

    hits: list[dict] = []
    if results and results["documents"]:
        for doc, meta, dist in zip(
            results["documents"][0],
            results["metadatas"][0],
            results["distances"][0],
        ):
            hits.append({
                "filepath": meta["filepath"],
                "start_line": meta["start_line"],
                "end_line": meta["end_line"],
                "distance": round(dist, 4),
                "text": doc,
            })
    return hits


def format_results(hits: list[dict]) -> str:
    """Pretty-print query results for the terminal."""
    if not hits:
        return "No results found."

    parts: list[str] = []
    for i, hit in enumerate(hits, 1):
        header = (
            f"[{i}] {hit['filepath']}  "
            f"(lines {hit['start_line']}-{hit['end_line']})  "
            f"distance={hit['distance']}"
        )
        separator = "-" * min(len(header), 80)
        # Show a preview (first 20 lines) to keep output readable
        preview_lines = hit["text"].splitlines()[:20]
        preview = "\n".join(preview_lines)
        if len(hit["text"].splitlines()) > 20:
            preview += f"\n  ... ({len(hit['text'].splitlines()) - 20} more lines)"
        parts.append(f"{header}\n{separator}\n{preview}\n")
    return "\n".join(parts)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Query the indexed codebase.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=textwrap.dedent("""\
            Examples:
              python query.py "How is the user model defined?"
              python query.py "error handling" --top-k 10
              python query.py "API routes" --ext .ts
        """),
    )
    parser.add_argument("question", help="Natural-language query about the codebase.")
    parser.add_argument(
        "--top-k",
        type=int,
        default=TOP_K,
        help=f"Number of results to return (default: {TOP_K}).",
    )
    parser.add_argument(
        "--ext",
        dest="extension",
        default=None,
        help="Filter results by file extension (e.g. .py, .ts).",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output results as JSON instead of formatted text.",
    )
    args = parser.parse_args()

    hits = query_index(args.question, args.top_k, args.extension)

    if args.json:
        import json
        # Strip full text for JSON output to keep it concise
        for h in hits:
            h["text_preview"] = "\n".join(h["text"].splitlines()[:10])
            del h["text"]
        print(json.dumps(hits, indent=2))
    else:
        print(f"\nQuery: {args.question}")
        print(f"Results: {len(hits)}\n")
        print(format_results(hits))


if __name__ == "__main__":
    main()

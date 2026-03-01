#!/usr/bin/env python3
"""
Query the PDF index stored in ChromaDB.

Returns relevant passages with the source PDF name and page number(s).

Usage:
    python query.py "What are the key findings?"
    python query.py "methodology section" --top-k 10
    python query.py "budget" --pdf report.pdf
    python query.py "conclusions" --json
"""

import argparse
import json as json_mod
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
    pdf_filter: str | None = None,
) -> list[dict]:
    """Query ChromaDB and return matching passages with PDF metadata."""
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
    if pdf_filter:
        where_filter = {"pdf_name": {"$eq": pdf_filter}}

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
            page_info = f"p.{meta['page_num']}"
            if meta.get("page_end") and meta["page_end"] != meta["page_num"]:
                page_info = f"pp.{meta['page_num']}-{meta['page_end']}"

            hits.append({
                "pdf_name": meta["pdf_name"],
                "page_num": meta["page_num"],
                "page_end": meta.get("page_end", meta["page_num"]),
                "page_info": page_info,
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
        title = (
            f"[{i}] {hit['pdf_name']}  "
            f"({hit['page_info']})  "
            f"distance={hit['distance']}"
        )
        separator = "-" * min(len(title), 80)

        # Show a preview (first 15 lines)
        preview_lines = hit["text"].splitlines()[:15]
        preview = "\n".join(preview_lines)
        total_lines = len(hit["text"].splitlines())
        if total_lines > 15:
            preview += f"\n  ... ({total_lines - 15} more lines)"

        parts.append(f"{title}\n{separator}\n{preview}\n")
    return "\n".join(parts)


def list_pdfs() -> None:
    """List all indexed PDFs and their chunk counts."""
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
        sys.exit("No index found. Run index.py first.")

    # Retrieve all metadata to enumerate PDFs
    all_data = collection.get(include=["metadatas"])
    pdf_counts: dict[str, int] = {}
    for meta in all_data["metadatas"]:
        name = meta.get("pdf_name", "unknown")
        pdf_counts[name] = pdf_counts.get(name, 0) + 1

    if not pdf_counts:
        print("No PDFs indexed.")
        return

    print(f"Indexed PDFs ({len(pdf_counts)} total):\n")
    for name, count in sorted(pdf_counts.items()):
        print(f"  {name}: {count} chunk(s)")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Query the indexed PDF collection.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=textwrap.dedent("""\
            Examples:
              python query.py "What are the key findings?"
              python query.py "methodology" --top-k 10
              python query.py "budget" --pdf financial_report.pdf
              python query.py --list-pdfs
        """),
    )
    parser.add_argument(
        "question",
        nargs="?",
        default=None,
        help="Natural-language query about the PDFs.",
    )
    parser.add_argument(
        "--top-k",
        type=int,
        default=TOP_K,
        help=f"Number of results to return (default: {TOP_K}).",
    )
    parser.add_argument(
        "--pdf",
        dest="pdf_filter",
        default=None,
        help="Filter results to a specific PDF filename.",
    )
    parser.add_argument(
        "--list-pdfs",
        action="store_true",
        help="List all indexed PDFs and exit.",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output results as JSON.",
    )
    args = parser.parse_args()

    if args.list_pdfs:
        list_pdfs()
        return

    if not args.question:
        parser.error("A question is required unless --list-pdfs is used.")

    hits = query_index(args.question, args.top_k, args.pdf_filter)

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

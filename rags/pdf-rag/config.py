"""
Shared configuration for the PDF RAG pipeline.
"""

import os
from dotenv import load_dotenv

load_dotenv()

# --- OpenAI ---
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "")
EMBEDDING_MODEL = os.getenv("EMBEDDING_MODEL", "text-embedding-3-small")

# --- ChromaDB ---
CHROMA_PERSIST_DIR = os.getenv("CHROMA_PERSIST_DIR", "./chroma_store")
COLLECTION_NAME = os.getenv("COLLECTION_NAME", "pdf_docs")

# --- PDFs ---
PDF_DIR = os.getenv("PDF_DIR", "./pdfs")

# --- Chunking ---
CHUNK_MODE = os.getenv("CHUNK_MODE", "paragraph")  # "paragraph" or "page"
CHUNK_SIZE = int(os.getenv("CHUNK_SIZE", "1000"))
CHUNK_OVERLAP = int(os.getenv("CHUNK_OVERLAP", "200"))

# --- Query ---
TOP_K = int(os.getenv("TOP_K", "5"))

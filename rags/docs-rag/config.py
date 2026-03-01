"""
Shared configuration for the docs RAG pipeline.
"""

import os
from dotenv import load_dotenv

load_dotenv()

# --- OpenAI ---
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "")
EMBEDDING_MODEL = os.getenv("EMBEDDING_MODEL", "text-embedding-3-small")

# --- FAISS ---
FAISS_INDEX_DIR = os.getenv("FAISS_INDEX_DIR", "./faiss_store")

# --- Documents ---
DOCS_DIR = os.getenv("DOCS_DIR", "./documents")
SUPPORTED_EXTENSIONS = {".md", ".txt", ".rst"}

# --- Chunking ---
CHUNK_SIZE = int(os.getenv("CHUNK_SIZE", "1000"))
CHUNK_OVERLAP = int(os.getenv("CHUNK_OVERLAP", "200"))
SPLIT_BY_HEADERS = os.getenv("SPLIT_BY_HEADERS", "true").lower() == "true"

# --- Query ---
TOP_K = int(os.getenv("TOP_K", "5"))

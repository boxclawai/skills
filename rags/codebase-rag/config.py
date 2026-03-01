"""
Shared configuration for the codebase RAG pipeline.
"""

import os
from dotenv import load_dotenv

load_dotenv()

# --- OpenAI ---
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "")
EMBEDDING_MODEL = os.getenv("EMBEDDING_MODEL", "text-embedding-3-small")
EMBEDDING_DIMENSIONS = int(os.getenv("EMBEDDING_DIMENSIONS", "1536"))

# --- ChromaDB ---
CHROMA_PERSIST_DIR = os.getenv("CHROMA_PERSIST_DIR", "./chroma_store")
COLLECTION_NAME = os.getenv("COLLECTION_NAME", "codebase")

# --- Indexing ---
SUPPORTED_EXTENSIONS = {".py", ".js", ".ts", ".md", ".jsx", ".tsx", ".go", ".rs", ".java"}
SKIP_DIRS = {"node_modules", ".git", "__pycache__", ".venv", "venv", "dist", "build", ".tox", ".mypy_cache"}

CHUNK_SIZE_LINES = int(os.getenv("CHUNK_SIZE_LINES", "300"))
CHUNK_OVERLAP_LINES = int(os.getenv("CHUNK_OVERLAP_LINES", "50"))

# --- Query ---
TOP_K = int(os.getenv("TOP_K", "5"))

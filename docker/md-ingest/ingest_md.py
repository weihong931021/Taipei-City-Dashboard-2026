"""
Ingest Markdown files into a Qdrant collection for RAG.

Strategy:
- Walk md_files/ for *.md
- Split each file by headings (# / ## / ###) -> sections
- For each section, sliding-window chunk (CHUNK_CHARS chars, OVERLAP overlap)
- Embed with intfloat/multilingual-e5-base (same model BE uses, 768d)
- Upsert to Qdrant collection (default: documents)

Each point payload:
{
  source_file: "taipei_eco_restaurants_details.md",
  heading_path: "餐廳一覽 > 環保餐廳",
  chunk_idx: 3,
  text: "...",
  char_start: 1500
}
"""

import argparse
import hashlib
import os
import re
import sys
from pathlib import Path

from qdrant_client import QdrantClient
from qdrant_client.http import models as qm
from sentence_transformers import SentenceTransformer

MODEL_ID = "intfloat/multilingual-e5-base"
VECTOR_SIZE = 768
CHUNK_CHARS = 500
OVERLAP = 100


def split_by_headings(md: str):
    """Yield (heading_path, section_text, section_start) tuples."""
    lines = md.splitlines(keepends=True)
    heading_stack = []  # list of (level, title)
    buf = []
    buf_start = 0
    cursor = 0

    def current_path():
        return " > ".join(t for _, t in heading_stack) or "(root)"

    def flush():
        if buf:
            text = "".join(buf).strip()
            if text:
                return current_path(), text, buf_start
        return None

    for line in lines:
        m = re.match(r"^(#{1,6})\s+(.+?)\s*$", line)
        if m:
            out = flush()
            if out:
                yield out
            level = len(m.group(1))
            title = m.group(2).strip()
            heading_stack = [h for h in heading_stack if h[0] < level]
            heading_stack.append((level, title))
            buf = []
            buf_start = cursor + len(line)
        else:
            if not buf:
                buf_start = cursor
            buf.append(line)
        cursor += len(line)

    out = flush()
    if out:
        yield out


def sliding_chunks(text: str, size: int = CHUNK_CHARS, overlap: int = OVERLAP):
    """Yield (chunk_text, start_offset) sliding windows."""
    if len(text) <= size:
        yield text, 0
        return
    step = size - overlap
    i = 0
    while i < len(text):
        chunk = text[i : i + size]
        if len(chunk.strip()) < 50:
            i += step
            continue
        yield chunk, i
        if i + size >= len(text):
            break
        i += step


def make_point_id(source_file: str, char_start: int) -> int:
    """Deterministic 64-bit-ish id from (file, offset). Qdrant accepts unsigned int64."""
    h = hashlib.blake2b(f"{source_file}:{char_start}".encode("utf-8"), digest_size=8)
    return int.from_bytes(h.digest(), "big", signed=False) >> 1  # keep within int64 range


def collect_chunks(md_dir: Path):
    files = sorted(p for p in md_dir.glob("*.md") if p.stat().st_size > 0)
    print(f"Found {len(files)} non-empty markdown files in {md_dir}")
    for f in files:
        text = f.read_text(encoding="utf-8")
        section_count = 0
        chunk_count = 0
        for heading_path, section_text, section_start in split_by_headings(text):
            section_count += 1
            for chunk_text, off in sliding_chunks(section_text):
                chunk_count += 1
                yield {
                    "source_file": f.name,
                    "heading_path": heading_path,
                    "char_start": section_start + off,
                    "text": chunk_text,
                }
        print(f"  {f.name}: {section_count} sections, {chunk_count} chunks")


def embed_e5(model: SentenceTransformer, texts: list[str]) -> list[list[float]]:
    # e5 expects "passage: " prefix for documents (and "query: " for queries)
    prefixed = [f"passage: {t}" for t in texts]
    return model.encode(
        prefixed,
        batch_size=16,
        show_progress_bar=True,
        normalize_embeddings=True,  # L2 normalize, so cosine == dot
    ).tolist()


def upsert_to_qdrant(client: QdrantClient, collection: str, points_data: list[dict], vectors: list[list[float]]):
    points = []
    for d, v in zip(points_data, vectors):
        pid = make_point_id(d["source_file"], d["char_start"])
        points.append(
            qm.PointStruct(
                id=pid,
                vector=v,
                payload=d,
            )
        )

    BATCH = 64
    for i in range(0, len(points), BATCH):
        batch = points[i : i + BATCH]
        client.upsert(collection_name=collection, points=batch, wait=True)
        print(f"  upserted {i + len(batch)}/{len(points)}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--md-dir", default=os.getenv("MD_DIR", "/data/md_files"))
    ap.add_argument("--qdrant-url", default=os.getenv("QDRANT_URL", "http://localhost:6333"))
    ap.add_argument("--qdrant-api-key", default=os.getenv("QDRANT_API_KEY", ""))
    ap.add_argument("--collection", default=os.getenv("QDRANT_DOC_COLLECTION", "documents"))
    ap.add_argument("--recreate", action="store_true", help="drop and recreate the collection")
    args = ap.parse_args()

    md_dir = Path(args.md_dir)
    if not md_dir.is_dir():
        print(f"ERROR: md dir not found: {md_dir}", file=sys.stderr)
        sys.exit(1)

    print(f"Loading embedding model: {MODEL_ID}")
    model = SentenceTransformer(MODEL_ID)

    print(f"Connecting to Qdrant: {args.qdrant_url}")
    client = QdrantClient(url=args.qdrant_url, api_key=args.qdrant_api_key or None)

    collections = [c.name for c in client.get_collections().collections]
    if args.recreate and args.collection in collections:
        print(f"Dropping existing collection '{args.collection}'")
        client.delete_collection(args.collection)
        collections.remove(args.collection)

    if args.collection not in collections:
        print(f"Creating collection '{args.collection}' (size={VECTOR_SIZE}, Cosine)")
        client.create_collection(
            collection_name=args.collection,
            vectors_config=qm.VectorParams(size=VECTOR_SIZE, distance=qm.Distance.COSINE),
        )

    print("Collecting chunks...")
    chunks = list(collect_chunks(md_dir))
    print(f"Total chunks: {len(chunks)}")

    if not chunks:
        print("Nothing to ingest.")
        return

    print("Embedding...")
    vectors = embed_e5(model, [c["text"] for c in chunks])

    print(f"Upserting to '{args.collection}'...")
    upsert_to_qdrant(client, args.collection, chunks, vectors)

    info = client.get_collection(args.collection)
    print(f"Done. Collection '{args.collection}' now has {info.points_count} points.")


if __name__ == "__main__":
    main()

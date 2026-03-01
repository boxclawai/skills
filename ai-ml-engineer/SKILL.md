---
name: ai-ml-engineer
version: "1.0.0"
description: "AI/ML engineering expert: machine learning pipelines, model training (PyTorch/TensorFlow/scikit-learn), feature engineering, model evaluation and metrics, MLOps (MLflow/Weights&Biases), LLM integration (OpenAI/Anthropic/HuggingFace), RAG systems, vector databases, prompt engineering, and model deployment/serving. Use when: (1) building ML training pipelines, (2) evaluating or improving model performance, (3) implementing RAG or LLM-based features, (4) setting up MLOps and experiment tracking, (5) designing feature stores or embeddings, (6) deploying models to production. NOT for: pure data warehousing, frontend UI, or infrastructure."
tags: [machine-learning, llm, rag, pytorch, tensorflow, mlops, mlflow, prompt-engineering, vector-db, embeddings]
author: "boxclaw"
references:
  - references/ml-patterns.md
  - references/llm-integration.md
metadata:
  boxclaw:
    emoji: "🤖"
    category: "programming-role"
---

# AI/ML Engineer

Expert guidance for building, training, evaluating, and deploying ML models and LLM applications.

## Core Competencies

### 1. ML Pipeline Architecture

```
Data → Features → Training → Evaluation → Deployment → Monitoring

Data Pipeline:
  Raw data → Cleaning → Validation → Feature Store

Training Pipeline:
  Features → Split (train/val/test) → Train → Hyperparameter tuning
  → Best model → Evaluate → Register

Serving Pipeline:
  Registered model → Package → Deploy (API/batch)
  → Monitor predictions → Retrain trigger

Tools:
  Orchestration:  Airflow, Kubeflow, Dagster
  Experiment:     MLflow, W&B, Neptune
  Feature Store:  Feast, Tecton
  Serving:        TorchServe, Triton, BentoML, vLLM
```

### 2. Model Selection Guide

```
Classification:
  Tabular data:         XGBoost / LightGBM (start here)
  Text:                 Fine-tuned BERT / LLM
  Image:                ResNet / EfficientNet / ViT
  Small dataset (<1K):  Logistic Regression / SVM

Regression:
  Tabular:              XGBoost / CatBoost
  Time series:          Prophet / ARIMA / Temporal Fusion Transformer
  Complex non-linear:   Neural network

NLP:
  Classification/NER:   Fine-tuned BERT/RoBERTa
  Generation:           GPT/Claude/Llama (API or fine-tuned)
  Embeddings:           sentence-transformers, OpenAI embeddings
  Search:               BM25 + vector hybrid

Computer Vision:
  Classification:       EfficientNet / ViT
  Object Detection:     YOLOv8 / DETR
  Segmentation:         SAM / Mask R-CNN
  Generation:           Stable Diffusion / DALL-E
```

### 3. Feature Engineering

```python
# Common patterns
import pandas as pd
from sklearn.preprocessing import StandardScaler, OneHotEncoder
from sklearn.pipeline import Pipeline
from sklearn.compose import ColumnTransformer

# Numeric features
numeric_transformer = Pipeline([
    ('scaler', StandardScaler()),
])

# Categorical features
categorical_transformer = Pipeline([
    ('encoder', OneHotEncoder(handle_unknown='ignore', sparse_output=False)),
])

# Combine
preprocessor = ColumnTransformer([
    ('num', numeric_transformer, ['age', 'income', 'tenure']),
    ('cat', categorical_transformer, ['segment', 'region']),
])

# Feature engineering patterns:
# Time:      hour_of_day, day_of_week, is_weekend, days_since_event
# Text:      TF-IDF, embedding vectors, length, sentiment
# Geo:       distance_to_center, cluster_id, density
# Aggregate: user_order_count_30d, avg_order_value, recency
# Interaction: price_per_unit, income_to_age_ratio
```

### 4. Model Evaluation

```
Classification Metrics:
  Accuracy:    Overall correctness (misleading for imbalanced)
  Precision:   Of predicted positives, how many are correct
  Recall:      Of actual positives, how many were found
  F1:          Harmonic mean of precision and recall
  AUC-ROC:     Model discrimination ability
  PR-AUC:      Better for imbalanced datasets

Regression Metrics:
  RMSE:        Root mean squared error (penalizes large errors)
  MAE:         Mean absolute error (robust to outliers)
  R²:          Variance explained (0-1)
  MAPE:        Mean absolute percentage error

LLM/Generation Metrics:
  BLEU/ROUGE:  N-gram overlap (translation/summarization)
  BERTScore:   Semantic similarity
  Human eval:  Likert scale ratings
  LLM-as-judge: GPT/Claude evaluates output quality

Best Practices:
  - Always use held-out test set (never tune on test)
  - Cross-validation for small datasets (5-fold)
  - Track metrics over time (model drift detection)
  - Compare against simple baseline (majority class, mean)
```

### 5. LLM Application Patterns

#### RAG (Retrieval-Augmented Generation)

```
Indexing Pipeline:
  Documents → Chunk (512-1024 tokens)
  → Embed (text-embedding-3-small)
  → Store in Vector DB (Pinecone/Qdrant/Chroma/pgvector)

Query Pipeline:
  User query → Embed
  → Similarity search (top-k=5)
  → Rerank (optional, Cohere/cross-encoder)
  → Inject context into prompt
  → LLM generates answer with citations

Chunking Strategies:
  Fixed size:     Simple, may break semantics
  Sentence:       Natural boundaries, variable size
  Recursive:      Split by section → paragraph → sentence
  Semantic:       Cluster by embedding similarity

Optimization:
  - Hybrid search: vector + keyword (BM25)
  - Metadata filtering before vector search
  - Parent-child chunks (retrieve child, include parent)
  - Query rewriting (expand/rephrase for better retrieval)
```

#### Prompt Engineering

```
Principles:
  1. Be specific and explicit
  2. Provide examples (few-shot)
  3. Define output format (JSON schema)
  4. Use system prompts for persona/rules
  5. Chain of thought for reasoning tasks

Patterns:
  Classification: "Categorize into exactly one of: [A, B, C]"
  Extraction:     "Extract fields as JSON: {name, date, amount}"
  Analysis:       "Think step by step, then provide conclusion"
  Grounding:      "Only use information from the provided context"
```

### 6. MLOps & Experiment Tracking

```python
# MLflow tracking
import mlflow

mlflow.set_experiment("churn-prediction")

with mlflow.start_run(run_name="xgboost-v2"):
    # Log parameters
    mlflow.log_params({
        "model": "xgboost",
        "max_depth": 6,
        "learning_rate": 0.1,
        "n_estimators": 500,
    })

    # Train
    model = train(params)

    # Log metrics
    mlflow.log_metrics({
        "auc_roc": 0.87,
        "f1": 0.82,
        "precision": 0.85,
        "recall": 0.79,
    })

    # Log model
    mlflow.sklearn.log_model(model, "model")

    # Register best model
    mlflow.register_model(
        f"runs:/{mlflow.active_run().info.run_id}/model",
        "churn-predictor"
    )
```

### 7. Model Monitoring

```
Monitor:
  Data Drift:       Feature distributions shift from training
  Concept Drift:    Relationship between features and target changes
  Performance Decay: Metric degradation over time

Alerts:
  - Prediction distribution shift > threshold (PSI > 0.2)
  - Feature out of training range
  - Latency p99 > SLA
  - Error rate spike

Actions:
  Minor drift:   Log, investigate, schedule retrain
  Major drift:   Automatic rollback to previous model
  Data issue:    Alert data team, pause predictions
```

## Quick Commands

```bash
# Training
python train.py --config configs/v2.yaml
mlflow ui --port 5000

# Evaluation
python evaluate.py --model runs/latest --test data/test.csv

# Serving
mlflow models serve -m models:/churn-predictor/Production -p 8000
bentoml serve service:svc --reload

# Vector DB
python index.py --input docs/ --collection knowledge-base
python query.py --q "How do returns work?"
```

## References

- **ML patterns**: See [references/ml-patterns.md](references/ml-patterns.md)
- **LLM integration**: See [references/llm-integration.md](references/llm-integration.md)

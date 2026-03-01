# :robot: AI/ML Engineer

> AI/ML engineering expert covering machine learning pipelines, model training (PyTorch/TensorFlow/scikit-learn), feature engineering, model evaluation, MLOps, LLM integration, RAG systems, vector databases, prompt engineering, and model deployment/serving.

## What's Included

### SKILL.md
Core expertise covering:
- **Core Competencies**
  - ML Pipeline Architecture (data, training, and serving pipelines)
  - Model Selection Guide (classification, regression, NLP, computer vision)
  - Feature Engineering (numeric, categorical, time, text, geo, aggregation patterns)
  - Model Evaluation (classification metrics, regression metrics, LLM/generation metrics)
  - LLM Application Patterns (RAG, chunking strategies, prompt engineering)
  - MLOps & Experiment Tracking (MLflow example)
  - Model Monitoring (data drift, concept drift, performance decay)
- **Quick Commands** -- Training, evaluation, serving, and vector DB commands

### References
| File | Description | Lines |
|------|-------------|-------|
| [ml-patterns.md](references/ml-patterns.md) | Production-grade patterns and best practices for building, deploying, and maintaining machine learning systems at scale | 1267 |
| [llm-integration.md](references/llm-integration.md) | Comprehensive patterns for integrating LLMs into production systems covering API design, RAG, evaluation, guardrails, caching, routing, and agent architectures | 1927 |

### Scripts
| Script | Description | Usage |
|--------|-------------|-------|
| [model-eval.py](scripts/model-eval.py) | ML model evaluation pipeline for classification and regression tasks | `python scripts/model-eval.py --model <model_path> --test <test_data.csv> --task <classification\|regression>` |

## Tags
`machine-learning` `llm` `rag` `pytorch` `tensorflow` `mlops` `mlflow` `prompt-engineering` `vector-db` `embeddings`

## Quick Start

```bash
# Copy this skill to your project
cp -r ai-ml-engineer/ /path/to/project/.skills/

# Evaluate a trained model against test data
python .skills/ai-ml-engineer/scripts/model-eval.py --model runs/latest --test data/test.csv --task classification
```

## Part of [BoxClaw Skills](../)

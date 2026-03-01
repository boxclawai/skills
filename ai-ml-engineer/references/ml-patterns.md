# ML Engineering Patterns

Production-grade patterns and best practices for building, deploying, and maintaining machine learning systems at scale.

---

## Table of Contents

1. [Feature Store Design](#feature-store-design)
2. [Training Pipeline Architecture](#training-pipeline-architecture)
3. [Experiment Tracking Best Practices](#experiment-tracking-best-practices)
4. [Model Versioning](#model-versioning)
5. [A/B Testing for ML Models](#ab-testing-for-ml-models)
6. [Feature Importance and Model Explainability](#feature-importance-and-model-explainability)
7. [Handling Class Imbalance](#handling-class-imbalance)
8. [Cross-Validation Strategies](#cross-validation-strategies)
9. [Hyperparameter Optimization](#hyperparameter-optimization)
10. [Model Compression](#model-compression)

---

## Feature Store Design

A feature store provides a centralized, reusable repository for ML features with consistent computation between training and serving.

### Architecture

```
                    +-----------------------+
                    |   Feature Registry    |
                    |  (metadata, schemas,  |
                    |   lineage, owners)    |
                    +-----------+-----------+
                                |
              +-----------------+-----------------+
              |                                   |
   +----------v-----------+          +-----------v----------+
   |   Offline Store      |          |   Online Store       |
   |  (batch features)    |          |  (real-time features)|
   |                      |          |                      |
   |  - Data warehouse    |          |  - Redis / DynamoDB  |
   |  - Parquet / Delta   |          |  - Low-latency reads |
   |  - Historical data   |          |  - Point-in-time     |
   |  - Training queries  |          |  - Serving queries   |
   +----------+-----------+          +-----------+----------+
              |                                   |
   +----------v-----------+          +-----------v----------+
   | Batch Transformation |          | Stream Transformation|
   |                      |          |                      |
   | - Spark / Beam       |          | - Flink / Kafka      |
   | - Scheduled jobs     |          | - Real-time compute  |
   | - Backfill support   |          | - Windowed agg.      |
   +----------------------+          +----------------------+
```

### Key Design Principles

**1. Training-Serving Consistency (Avoid Skew)**

The single most critical requirement. Features must be computed identically in training and serving.

```python
# Feature definition (shared between training and serving)
class UserFeatures:
    """Feature group for user behavioral signals."""

    entity = "user_id"
    description = "User engagement features computed from event stream"

    @feature(dtype=Float64, description="Average session duration over 30 days")
    def avg_session_duration_30d(self, events: DataFrame) -> Series:
        return (
            events
            .filter(col("event_type") == "session_end")
            .filter(col("timestamp") > current_timestamp() - interval("30 days"))
            .groupby("user_id")
            .agg(avg("duration_seconds"))
        )

    @feature(dtype=Int64, description="Total purchases in last 7 days")
    def purchase_count_7d(self, events: DataFrame) -> Series:
        return (
            events
            .filter(col("event_type") == "purchase")
            .filter(col("timestamp") > current_timestamp() - interval("7 days"))
            .groupby("user_id")
            .agg(count("*"))
        )
```

**2. Point-in-Time Correctness**

Prevent data leakage by ensuring features are computed using only data available at prediction time.

```python
# Point-in-time join for training data
def get_training_features(
    entity_df: pd.DataFrame,  # columns: [user_id, event_timestamp, label]
    feature_refs: list[str],
) -> pd.DataFrame:
    """
    For each (user_id, event_timestamp) row, retrieve feature values
    as they existed AT that timestamp -- never using future data.
    """
    return feature_store.get_historical_features(
        entity_df=entity_df,
        features=feature_refs,
        # This ensures each row gets features computed with data
        # available BEFORE event_timestamp (no leakage)
    ).to_df()
```

**3. Feature Schema and Validation**

```python
# Schema definition with validation rules
feature_schema = {
    "avg_session_duration_30d": {
        "dtype": "float64",
        "nullable": False,
        "min_value": 0.0,
        "max_value": 86400.0,  # max 24 hours in seconds
        "description": "Average session duration over 30 days",
        "owner": "ml-team",
        "tags": ["engagement", "user-behavior"],
    },
    "purchase_count_7d": {
        "dtype": "int64",
        "nullable": False,
        "min_value": 0,
        "max_value": 10000,
        "description": "Total purchases in last 7 days",
        "owner": "ml-team",
        "tags": ["revenue", "user-behavior"],
    },
}
```

### Feature Store Selection Guide

| Feature Store | Strengths | Best For |
|--------------|-----------|----------|
| **Feast** | Open source, flexible, cloud-agnostic | Teams wanting control, multi-cloud |
| **Tecton** | Managed, real-time, enterprise features | Real-time ML at scale |
| **Databricks Feature Store** | Tight Spark/Delta integration | Databricks-native teams |
| **SageMaker Feature Store** | AWS-native, managed | AWS-centric organizations |
| **Vertex AI Feature Store** | GCP-native, managed | GCP-centric organizations |
| **Hopsworks** | Open source, real-time, Python-native | Teams wanting open source with real-time |

---

## Training Pipeline Architecture

### End-to-End Pipeline

```
Data Source --> Data Validation --> Preprocessing --> Feature Engineering
                    |                    |                    |
                    v                    v                    v
              Schema checks      Transformations       Feature store
              Distribution       Encoding               materialization
              drift alerts       Normalization
                    |                    |                    |
                    +--------------------+--------------------+
                                         |
                                    Training
                                         |
                              +----------+----------+
                              |                     |
                         Evaluation            Evaluation
                         (holdout)             (cross-val)
                              |                     |
                              +----------+----------+
                                         |
                                  Model Registry
                                  (versioned artifact)
                                         |
                              +----------+----------+
                              |                     |
                         Staging               Shadow mode
                         validation            (production traffic,
                              |                 no user impact)
                              +----------+----------+
                                         |
                                    Production
                                    deployment
```

### Stage 1: Data Validation

Validate data quality before any processing. Catch issues early.

```python
import great_expectations as gx

def validate_training_data(df: pd.DataFrame) -> ValidationResult:
    """Validate training data meets quality requirements."""

    context = gx.get_context()
    suite = context.add_expectation_suite("training_data_validation")

    # Schema validation
    suite.add_expectation(
        gx.expectations.ExpectTableColumnsToMatchOrderedList(
            column_list=["user_id", "feature_1", "feature_2", "label", "timestamp"]
        )
    )

    # Completeness checks
    suite.add_expectation(
        gx.expectations.ExpectColumnValuesToNotBeNull(column="label")
    )

    # Distribution checks (detect drift)
    suite.add_expectation(
        gx.expectations.ExpectColumnMeanToBeBetween(
            column="feature_1", min_value=0.3, max_value=0.7
        )
    )

    # Freshness check
    suite.add_expectation(
        gx.expectations.ExpectColumnMaxToBeBetween(
            column="timestamp",
            min_value=(datetime.now() - timedelta(hours=24)).isoformat(),
            max_value=datetime.now().isoformat(),
        )
    )

    # Volume check
    suite.add_expectation(
        gx.expectations.ExpectTableRowCountToBeBetween(
            min_value=10000, max_value=10000000
        )
    )

    result = context.run_validation(suite, df)

    if not result.success:
        alert_data_quality_team(result)
        raise DataQualityError(f"Validation failed: {result.statistics}")

    return result
```

### Stage 2: Preprocessing Pipeline

Build reproducible, serializable preprocessing pipelines.

```python
from sklearn.pipeline import Pipeline
from sklearn.compose import ColumnTransformer
from sklearn.preprocessing import StandardScaler, OneHotEncoder
from sklearn.impute import SimpleImputer

def build_preprocessing_pipeline(config: dict) -> Pipeline:
    """Build a reproducible preprocessing pipeline from config."""

    numeric_features = config["numeric_features"]
    categorical_features = config["categorical_features"]

    numeric_transformer = Pipeline(steps=[
        ("imputer", SimpleImputer(strategy="median")),
        ("scaler", StandardScaler()),
    ])

    categorical_transformer = Pipeline(steps=[
        ("imputer", SimpleImputer(strategy="constant", fill_value="missing")),
        ("encoder", OneHotEncoder(handle_unknown="ignore", sparse_output=False)),
    ])

    preprocessor = ColumnTransformer(
        transformers=[
            ("num", numeric_transformer, numeric_features),
            ("cat", categorical_transformer, categorical_features),
        ],
        remainder="drop",  # Drop columns not explicitly handled
    )

    return Pipeline(steps=[
        ("preprocessor", preprocessor),
    ])
```

### Stage 3: Training with Experiment Tracking

```python
import mlflow

def train_model(
    X_train: pd.DataFrame,
    y_train: pd.Series,
    X_val: pd.DataFrame,
    y_val: pd.Series,
    config: dict,
) -> tuple[Pipeline, dict]:
    """Train model with full experiment tracking."""

    with mlflow.start_run(run_name=config["run_name"]) as run:
        # Log parameters
        mlflow.log_params(config["hyperparameters"])
        mlflow.log_param("training_rows", len(X_train))
        mlflow.log_param("feature_count", X_train.shape[1])

        # Build and fit pipeline
        pipeline = build_preprocessing_pipeline(config)
        pipeline.steps.append(("model", config["model_class"](**config["hyperparameters"])))
        pipeline.fit(X_train, y_train)

        # Evaluate
        y_pred = pipeline.predict(X_val)
        y_prob = pipeline.predict_proba(X_val)[:, 1] if hasattr(pipeline, "predict_proba") else None

        metrics = compute_metrics(y_val, y_pred, y_prob)
        mlflow.log_metrics(metrics)

        # Log artifacts
        mlflow.sklearn.log_model(pipeline, "model", registered_model_name=config["model_name"])
        log_confusion_matrix(y_val, y_pred)
        log_feature_importance(pipeline, X_train.columns)

        # Log dataset fingerprint for reproducibility
        mlflow.log_param("data_hash", hashlib.sha256(
            pd.util.hash_pandas_object(X_train).values.tobytes()
        ).hexdigest()[:16])

        return pipeline, metrics
```

### Stage 4: Evaluation Gates

```python
def evaluation_gate(
    model: Pipeline,
    X_test: pd.DataFrame,
    y_test: pd.Series,
    thresholds: dict,
) -> bool:
    """
    Gate that determines if a model is ready for promotion.
    Returns True if ALL thresholds are met.
    """
    y_pred = model.predict(X_test)
    y_prob = model.predict_proba(X_test)[:, 1]

    checks = {
        "accuracy": accuracy_score(y_test, y_pred) >= thresholds["min_accuracy"],
        "precision": precision_score(y_test, y_pred) >= thresholds["min_precision"],
        "recall": recall_score(y_test, y_pred) >= thresholds["min_recall"],
        "auc_roc": roc_auc_score(y_test, y_prob) >= thresholds["min_auc_roc"],
        "calibration": brier_score_loss(y_test, y_prob) <= thresholds["max_brier"],
        "latency_p99": measure_inference_latency(model, X_test) <= thresholds["max_latency_ms"],
        "no_regression": not regression_detected(model, thresholds["baseline_metrics"]),
    }

    for check_name, passed in checks.items():
        logger.info(f"Evaluation gate '{check_name}': {'PASS' if passed else 'FAIL'}")

    return all(checks.values())
```

---

## Experiment Tracking Best Practices

### What to Track

| Category | Items | Why |
|----------|-------|-----|
| **Parameters** | Hyperparameters, feature lists, data splits, random seeds | Reproducibility |
| **Metrics** | Loss, accuracy, precision, recall, F1, AUC, custom metrics | Model comparison |
| **Artifacts** | Model binary, preprocessing pipeline, config files | Deployment |
| **Data** | Dataset version/hash, row count, feature statistics | Lineage |
| **Environment** | Python version, library versions, hardware specs | Reproducibility |
| **Code** | Git commit SHA, branch, diff (if dirty) | Reproducibility |

### Experiment Naming Convention

```
{project}/{model_type}/{experiment_description}

Examples:
  fraud-detection/xgboost/baseline-v1
  fraud-detection/xgboost/tuned-learning-rate
  fraud-detection/neural-net/transformer-encoder
  churn-prediction/lightgbm/feature-ablation-study
```

### Comparison and Analysis

```python
def compare_experiments(experiment_ids: list[str]) -> pd.DataFrame:
    """Compare multiple experiment runs side by side."""

    runs = mlflow.search_runs(
        experiment_ids=experiment_ids,
        filter_string="metrics.auc_roc > 0.7",
        order_by=["metrics.auc_roc DESC"],
        max_results=50,
    )

    comparison_cols = [
        "run_id",
        "params.model_type",
        "params.learning_rate",
        "params.max_depth",
        "metrics.auc_roc",
        "metrics.precision",
        "metrics.recall",
        "metrics.f1",
        "metrics.training_time_seconds",
        "metrics.inference_latency_p99_ms",
    ]

    return runs[comparison_cols].round(4)
```

---

## Model Versioning

### Versioning Schema

```
model_name:version_tag

Examples:
  fraud-detector:v1.0.0          # Production model
  fraud-detector:v1.1.0-rc.1     # Release candidate
  fraud-detector:v2.0.0-beta     # Breaking change (new features)
```

### Version Semantics for ML

| Component | When to Increment | Example |
|-----------|-------------------|---------|
| **Major (X.0.0)** | Breaking changes: new features required, API schema change, different model architecture | v1.0.0 -> v2.0.0: switched from XGBoost to neural net |
| **Minor (0.X.0)** | Backward-compatible improvement: retrained with more data, hyperparameter tuning, added features (with defaults) | v1.0.0 -> v1.1.0: retrained with November data |
| **Patch (0.0.X)** | Bug fix: fixed preprocessing bug, corrected feature calculation | v1.1.0 -> v1.1.1: fixed null handling in feature X |

### Model Registry Workflow

```
               Experimentation
                     |
                     v
            +--------+--------+
            | Model Registry  |
            |                 |
            | Stage: None     |  <-- newly registered
            |    |            |
            |    v            |
            | Stage: Staging  |  <-- passes eval gates
            |    |            |
            |    v            |
            | Stage: Prod     |  <-- passes shadow mode + A/B test
            |    |            |
            |    v            |
            | Stage: Archived |  <-- replaced by newer version
            +--------+--------+
```

### Model Card Template

```yaml
model_card:
  name: "fraud-detector"
  version: "v1.2.0"
  description: "Real-time transaction fraud detection model"
  owner: "ml-fraud-team"
  created: "2025-11-15"

  intended_use:
    primary: "Score transactions for fraud probability in real-time"
    out_of_scope: "Not designed for account-level fraud detection"

  training_data:
    source: "transactions table, 2024-01 to 2025-10"
    rows: 45_000_000
    positive_rate: 0.023  # 2.3% fraud rate
    known_biases: "Underrepresents international transactions (<5% of training data)"

  performance:
    holdout_auc: 0.967
    holdout_precision_at_95_recall: 0.42
    latency_p99_ms: 12
    model_size_mb: 45

  fairness:
    evaluated_slices:
      - slice: "transaction_country=US"
        auc: 0.971
      - slice: "transaction_country=non-US"
        auc: 0.943
      - slice: "amount<100"
        auc: 0.958
      - slice: "amount>=100"
        auc: 0.974

  limitations:
    - "Performance degrades for transaction amounts > $50,000 (rare in training data)"
    - "New merchant categories not seen in training may have higher false positive rate"

  ethical_considerations:
    - "Model should not be sole decision-maker; human review required for blocks"
    - "Regular fairness audits across demographic segments required"
```

---

## A/B Testing for ML Models

### Experiment Design

```python
class MLABTest:
    """A/B test configuration for ML model comparison."""

    def __init__(
        self,
        experiment_name: str,
        control_model: str,       # model_name:version
        treatment_model: str,     # model_name:version
        traffic_split: float,     # fraction to treatment (0.0 to 1.0)
        primary_metric: str,
        guardrail_metrics: list[str],
        min_sample_size: int,
        max_duration_days: int,
    ):
        self.experiment_name = experiment_name
        self.control_model = control_model
        self.treatment_model = treatment_model
        self.traffic_split = traffic_split
        self.primary_metric = primary_metric
        self.guardrail_metrics = guardrail_metrics
        self.min_sample_size = min_sample_size
        self.max_duration_days = max_duration_days

    def assign_variant(self, entity_id: str) -> str:
        """Deterministic assignment based on hash for consistency."""
        hash_value = int(hashlib.sha256(
            f"{self.experiment_name}:{entity_id}".encode()
        ).hexdigest(), 16)

        return "treatment" if (hash_value % 10000) / 10000 < self.traffic_split else "control"
```

### Statistical Analysis

```python
from scipy import stats

def analyze_ab_test(
    control_outcomes: np.ndarray,
    treatment_outcomes: np.ndarray,
    alpha: float = 0.05,
) -> dict:
    """Analyze A/B test results with proper statistical rigor."""

    # Basic statistics
    control_mean = np.mean(control_outcomes)
    treatment_mean = np.mean(treatment_outcomes)
    relative_lift = (treatment_mean - control_mean) / control_mean

    # Two-sided t-test
    t_stat, p_value = stats.ttest_ind(control_outcomes, treatment_outcomes)

    # Confidence interval for the difference
    diff = treatment_mean - control_mean
    se_diff = np.sqrt(
        np.var(control_outcomes) / len(control_outcomes) +
        np.var(treatment_outcomes) / len(treatment_outcomes)
    )
    ci_lower = diff - stats.norm.ppf(1 - alpha / 2) * se_diff
    ci_upper = diff + stats.norm.ppf(1 - alpha / 2) * se_diff

    # Effect size (Cohen's d)
    pooled_std = np.sqrt(
        (np.var(control_outcomes) + np.var(treatment_outcomes)) / 2
    )
    cohens_d = diff / pooled_std if pooled_std > 0 else 0

    return {
        "control_mean": control_mean,
        "treatment_mean": treatment_mean,
        "relative_lift": relative_lift,
        "p_value": p_value,
        "significant": p_value < alpha,
        "confidence_interval": (ci_lower, ci_upper),
        "cohens_d": cohens_d,
        "control_n": len(control_outcomes),
        "treatment_n": len(treatment_outcomes),
    }
```

### Guardrail Metrics

Always monitor guardrail metrics that must NOT degrade, even if the primary metric improves:

| Primary Metric | Guardrail Metrics |
|---------------|-------------------|
| Click-through rate | Page load time, crash rate, revenue per user |
| Fraud detection rate | False positive rate, customer friction score |
| Recommendation relevance | Diversity, coverage, latency |
| Conversion rate | Cart abandonment, return rate, support tickets |

### Ramp-Up Strategy

```
Day 1-3:   1% traffic   --> Validate no crashes, latency OK
Day 4-7:   5% traffic   --> Monitor guardrail metrics
Day 8-14:  25% traffic  --> Accumulate statistical power
Day 15-21: 50% traffic  --> Final analysis with full power
Day 22:    Decision     --> Ship (100%) or rollback (0%)
```

---

## Feature Importance and Model Explainability

### SHAP (SHapley Additive exPlanations)

SHAP values provide a unified measure of feature importance grounded in game theory. Each feature's SHAP value represents its contribution to the prediction relative to the average prediction.

```python
import shap

def explain_model_shap(
    model: Pipeline,
    X_explain: pd.DataFrame,
    max_samples: int = 1000,
) -> shap.Explanation:
    """Generate SHAP explanations for model predictions."""

    # Use appropriate explainer based on model type
    if hasattr(model.named_steps["model"], "feature_importances_"):
        # Tree-based models (XGBoost, LightGBM, Random Forest)
        explainer = shap.TreeExplainer(model.named_steps["model"])
    else:
        # Model-agnostic (works with any model, but slower)
        background = shap.sample(X_explain, min(100, len(X_explain)))
        explainer = shap.KernelExplainer(model.predict, background)

    shap_values = explainer(X_explain[:max_samples])

    # Global feature importance (mean absolute SHAP value)
    global_importance = pd.DataFrame({
        "feature": X_explain.columns,
        "mean_abs_shap": np.abs(shap_values.values).mean(axis=0),
    }).sort_values("mean_abs_shap", ascending=False)

    return shap_values, global_importance


def explain_single_prediction(
    model: Pipeline,
    instance: pd.DataFrame,
    explainer: shap.Explainer,
) -> dict:
    """Explain a single prediction for debugging or customer-facing explanations."""

    shap_values = explainer(instance)

    prediction = model.predict_proba(instance)[0, 1]

    # Top contributing features
    feature_contributions = pd.DataFrame({
        "feature": instance.columns,
        "value": instance.values[0],
        "shap_value": shap_values.values[0],
    }).sort_values("shap_value", key=abs, ascending=False)

    return {
        "prediction": prediction,
        "base_value": shap_values.base_values[0],
        "top_positive_factors": feature_contributions[feature_contributions["shap_value"] > 0].head(5).to_dict("records"),
        "top_negative_factors": feature_contributions[feature_contributions["shap_value"] < 0].head(5).to_dict("records"),
    }
```

### LIME (Local Interpretable Model-agnostic Explanations)

LIME explains individual predictions by fitting a simple interpretable model locally around the prediction point.

```python
import lime
import lime.lime_tabular

def explain_with_lime(
    model: Pipeline,
    X_train: pd.DataFrame,
    instance: np.ndarray,
    num_features: int = 10,
) -> lime.explanation.Explanation:
    """Generate LIME explanation for a single instance."""

    explainer = lime.lime_tabular.LimeTabularExplainer(
        training_data=X_train.values,
        feature_names=X_train.columns.tolist(),
        class_names=["negative", "positive"],
        mode="classification",
        discretize_continuous=True,
    )

    explanation = explainer.explain_instance(
        data_row=instance,
        predict_fn=model.predict_proba,
        num_features=num_features,
        num_samples=5000,
    )

    return explanation
```

### When to Use What

| Method | Best For | Limitations |
|--------|----------|-------------|
| **SHAP (TreeExplainer)** | Tree models, fast exact computation | Only works with tree-based models |
| **SHAP (KernelExplainer)** | Any model, theoretically grounded | Slow for large datasets, approximate |
| **LIME** | Quick local explanations, any model | Unstable (different runs may give different results) |
| **Permutation Importance** | Model-agnostic global importance | Slow, doesn't show directionality |
| **Built-in Feature Importance** | Quick overview for tree models | Biased toward high-cardinality features |

---

## Handling Class Imbalance

### Strategy Selection Guide

| Imbalance Ratio | Data Size | Recommended Approaches |
|----------------|-----------|----------------------|
| Mild (5:1 - 10:1) | Any | Class weights, threshold tuning |
| Moderate (10:1 - 100:1) | Large (>100K) | Class weights, focal loss |
| Moderate (10:1 - 100:1) | Small (<100K) | SMOTE + class weights |
| Severe (>100:1) | Large | Focal loss, cost-sensitive learning, ensemble methods |
| Severe (>100:1) | Small | SMOTE variants + ensemble, anomaly detection framing |

### SMOTE and Variants

```python
from imblearn.over_sampling import SMOTE, ADASYN, BorderlineSMOTE
from imblearn.combine import SMOTETomek, SMOTEENN
from imblearn.pipeline import Pipeline as ImbPipeline

def build_resampling_pipeline(
    strategy: str,
    sampling_ratio: float = 0.5,
) -> ImbPipeline:
    """Build pipeline with resampling. sampling_ratio is the target minority/majority ratio."""

    resamplers = {
        "smote": SMOTE(sampling_strategy=sampling_ratio, random_state=42, k_neighbors=5),
        "borderline_smote": BorderlineSMOTE(sampling_strategy=sampling_ratio, random_state=42, kind="borderline-1"),
        "adasyn": ADASYN(sampling_strategy=sampling_ratio, random_state=42),
        "smote_tomek": SMOTETomek(sampling_strategy=sampling_ratio, random_state=42),
        "smote_enn": SMOTEENN(sampling_strategy=sampling_ratio, random_state=42),
    }

    return ImbPipeline(steps=[
        ("resampler", resamplers[strategy]),
        ("scaler", StandardScaler()),
        ("model", XGBClassifier()),
    ])
```

**Important:** Only apply SMOTE to training data, never to validation or test data.

### Class Weights

```python
from sklearn.utils.class_weight import compute_class_weight

def train_with_class_weights(X_train, y_train, X_val, y_val):
    """Train with automatic class weight computation."""

    # Compute balanced weights
    classes = np.unique(y_train)
    weights = compute_class_weight("balanced", classes=classes, y=y_train)
    class_weight_dict = dict(zip(classes, weights))
    # e.g., {0: 0.52, 1: 47.3} for a 1:90 imbalance

    # For sklearn models
    model = LogisticRegression(class_weight="balanced")

    # For XGBoost
    model = XGBClassifier(
        scale_pos_weight=len(y_train[y_train == 0]) / len(y_train[y_train == 1])
    )

    # For LightGBM
    model = LGBMClassifier(
        is_unbalance=True,  # or set class_weight="balanced"
    )

    model.fit(X_train, y_train)
    return model
```

### Focal Loss

Focal loss down-weights well-classified examples, focusing training on hard negatives. Originally from object detection (Lin et al., 2017), highly effective for imbalanced classification.

```python
import torch
import torch.nn.functional as F

class FocalLoss(torch.nn.Module):
    """
    Focal Loss: FL(p_t) = -alpha_t * (1 - p_t)^gamma * log(p_t)

    Args:
        alpha: Weighting factor for the rare class (0 to 1).
        gamma: Focusing parameter. gamma=0 is standard cross-entropy.
               gamma=2 is a common default that works well in practice.
    """

    def __init__(self, alpha: float = 0.25, gamma: float = 2.0):
        super().__init__()
        self.alpha = alpha
        self.gamma = gamma

    def forward(self, inputs: torch.Tensor, targets: torch.Tensor) -> torch.Tensor:
        bce_loss = F.binary_cross_entropy_with_logits(inputs, targets, reduction="none")
        probs = torch.sigmoid(inputs)
        p_t = probs * targets + (1 - probs) * (1 - targets)
        alpha_t = self.alpha * targets + (1 - self.alpha) * (1 - targets)
        focal_weight = alpha_t * (1 - p_t) ** self.gamma
        loss = focal_weight * bce_loss
        return loss.mean()
```

### Evaluation for Imbalanced Data

Never use accuracy for imbalanced datasets. Use these metrics instead:

| Metric | When to Use | Formula |
|--------|------------|---------|
| **Precision-Recall AUC** | Primary metric for imbalanced classification | Area under PR curve |
| **F1 Score** | When you need a single threshold-dependent metric | 2 * P * R / (P + R) |
| **Cohen's Kappa** | When comparing to random chance performance | Agreement corrected for chance |
| **Matthews Correlation Coefficient** | Balanced metric for binary classification | Correlation between predicted and actual |
| **Precision @ K** | Ranking problems (top-K predictions) | Precision in top K results |

---

## Cross-Validation Strategies

### Strategy Selection

| Data Characteristic | Recommended Strategy |
|--------------------|---------------------|
| Standard tabular data | Stratified K-Fold (k=5 or k=10) |
| Time series data | Time-series split (expanding or sliding window) |
| Grouped data (e.g., multiple samples per patient) | Group K-Fold |
| Small dataset (<1000 rows) | Repeated Stratified K-Fold (5x5 or 10x3) |
| Very large dataset (>1M rows) | Single holdout or 3-fold |
| Multi-label classification | Iterative Stratified K-Fold |

### Implementation

```python
from sklearn.model_selection import (
    StratifiedKFold,
    TimeSeriesSplit,
    GroupKFold,
    RepeatedStratifiedKFold,
)

# Standard: Stratified K-Fold (preserves class distribution)
cv = StratifiedKFold(n_splits=5, shuffle=True, random_state=42)

# Time series: Never use future data to predict the past
cv = TimeSeriesSplit(n_splits=5, gap=0)
# Fold 1: train=[0,1], test=[2]
# Fold 2: train=[0,1,2], test=[3]
# Fold 3: train=[0,1,2,3], test=[4]

# Grouped: Ensure all samples from same group are in same fold
cv = GroupKFold(n_splits=5)
# Use: cv.split(X, y, groups=patient_ids)

# Small data: Repeat for more stable estimates
cv = RepeatedStratifiedKFold(n_splits=5, n_repeats=3, random_state=42)
```

### Nested Cross-Validation

Use nested CV when performing hyperparameter tuning to get an unbiased estimate of generalization performance.

```python
from sklearn.model_selection import cross_val_score, GridSearchCV

def nested_cross_validation(
    X: pd.DataFrame,
    y: pd.Series,
    model: BaseEstimator,
    param_grid: dict,
    outer_cv: int = 5,
    inner_cv: int = 3,
) -> dict:
    """
    Nested CV: outer loop estimates generalization,
    inner loop tunes hyperparameters.
    """
    outer = StratifiedKFold(n_splits=outer_cv, shuffle=True, random_state=42)
    inner = StratifiedKFold(n_splits=inner_cv, shuffle=True, random_state=42)

    # Inner loop: hyperparameter tuning
    grid_search = GridSearchCV(
        estimator=model,
        param_grid=param_grid,
        cv=inner,
        scoring="roc_auc",
        n_jobs=-1,
    )

    # Outer loop: unbiased performance estimation
    scores = cross_val_score(
        grid_search, X, y, cv=outer, scoring="roc_auc", n_jobs=-1
    )

    return {
        "mean_score": scores.mean(),
        "std_score": scores.std(),
        "fold_scores": scores.tolist(),
    }
```

---

## Hyperparameter Optimization

### Optuna

Optuna uses Bayesian optimization (Tree-structured Parzen Estimator) to efficiently search the hyperparameter space.

```python
import optuna
from optuna.integration import XGBoostPruningCallback

def optimize_xgboost(
    X_train: pd.DataFrame,
    y_train: pd.Series,
    X_val: pd.DataFrame,
    y_val: pd.Series,
    n_trials: int = 100,
) -> dict:
    """Optimize XGBoost hyperparameters with Optuna."""

    def objective(trial: optuna.Trial) -> float:
        params = {
            "n_estimators": trial.suggest_int("n_estimators", 100, 1000),
            "max_depth": trial.suggest_int("max_depth", 3, 12),
            "learning_rate": trial.suggest_float("learning_rate", 1e-3, 0.3, log=True),
            "subsample": trial.suggest_float("subsample", 0.5, 1.0),
            "colsample_bytree": trial.suggest_float("colsample_bytree", 0.5, 1.0),
            "min_child_weight": trial.suggest_int("min_child_weight", 1, 10),
            "reg_alpha": trial.suggest_float("reg_alpha", 1e-8, 10.0, log=True),
            "reg_lambda": trial.suggest_float("reg_lambda", 1e-8, 10.0, log=True),
            "gamma": trial.suggest_float("gamma", 1e-8, 1.0, log=True),
        }

        model = XGBClassifier(
            **params,
            eval_metric="logloss",
            early_stopping_rounds=50,
            random_state=42,
        )

        model.fit(
            X_train, y_train,
            eval_set=[(X_val, y_val)],
            verbose=False,
            callbacks=[XGBoostPruningCallback(trial, "validation_0-logloss")],
        )

        y_prob = model.predict_proba(X_val)[:, 1]
        return roc_auc_score(y_val, y_prob)

    study = optuna.create_study(
        direction="maximize",
        study_name="xgboost-optimization",
        pruner=optuna.pruners.MedianPruner(n_warmup_steps=10),
        sampler=optuna.samplers.TPESampler(seed=42),
    )

    study.optimize(objective, n_trials=n_trials, timeout=3600)

    return {
        "best_params": study.best_params,
        "best_value": study.best_value,
        "n_trials": len(study.trials),
        "n_pruned": len([t for t in study.trials if t.state == optuna.trial.TrialState.PRUNED]),
    }
```

### Ray Tune

Ray Tune provides distributed hyperparameter tuning with advanced scheduling algorithms.

```python
from ray import tune
from ray.tune.schedulers import ASHAScheduler
from ray.tune.search.optuna import OptunaSearch

def distributed_hpo(
    train_fn: callable,
    search_space: dict,
    num_samples: int = 100,
    max_concurrent: int = 4,
    gpus_per_trial: float = 0.5,
) -> dict:
    """Distributed hyperparameter optimization with Ray Tune."""

    scheduler = ASHAScheduler(
        metric="val_auc",
        mode="max",
        max_t=100,          # max epochs
        grace_period=10,    # min epochs before pruning
        reduction_factor=3, # keep top 1/3 at each rung
    )

    search_alg = OptunaSearch(metric="val_auc", mode="max")

    analysis = tune.run(
        train_fn,
        config=search_space,
        num_samples=num_samples,
        scheduler=scheduler,
        search_alg=search_alg,
        resources_per_trial={"cpu": 2, "gpu": gpus_per_trial},
        max_concurrent_trials=max_concurrent,
        local_dir="/tmp/ray_results",
        name="hpo_experiment",
        verbose=1,
    )

    return {
        "best_config": analysis.best_config,
        "best_result": analysis.best_result,
        "results_df": analysis.results_df,
    }

# Search space definition
search_space = {
    "lr": tune.loguniform(1e-5, 1e-1),
    "batch_size": tune.choice([32, 64, 128, 256]),
    "hidden_dim": tune.choice([128, 256, 512]),
    "dropout": tune.uniform(0.1, 0.5),
    "num_layers": tune.randint(1, 5),
    "weight_decay": tune.loguniform(1e-6, 1e-2),
}
```

### Optimization Strategy Selection

| Method | When to Use | Trials Needed | Parallelizable |
|--------|------------|---------------|----------------|
| **Grid Search** | Small search space (<50 combos) | All combos | Yes |
| **Random Search** | Baseline, quick exploration | 50-100 | Yes |
| **Bayesian (Optuna TPE)** | Default choice, moderate search spaces | 50-200 | Limited |
| **ASHA (Ray Tune)** | Deep learning, expensive evaluations | 50-200 | Yes |
| **Population Based Training** | RL, large-scale neural net training | 20-50 populations | Yes |
| **Hyperband** | Large search spaces with early stopping | 50-200 | Yes |

---

## Model Compression

### Quantization

Reduce model precision from FP32 to INT8 or lower, reducing model size and inference latency.

```python
import torch

def quantize_model_dynamic(model: torch.nn.Module) -> torch.nn.Module:
    """Dynamic quantization: weights quantized ahead of time, activations quantized at runtime."""
    quantized_model = torch.quantization.quantize_dynamic(
        model,
        qconfig_spec={torch.nn.Linear, torch.nn.LSTM},
        dtype=torch.qint8,
    )
    return quantized_model

def quantize_model_static(
    model: torch.nn.Module,
    calibration_dataloader: DataLoader,
) -> torch.nn.Module:
    """Static quantization: both weights and activations quantized ahead of time using calibration data."""
    model.eval()

    # Set quantization config
    model.qconfig = torch.quantization.get_default_qconfig("x86")
    torch.quantization.prepare(model, inplace=True)

    # Calibrate with representative data
    with torch.no_grad():
        for batch in calibration_dataloader:
            model(batch)

    # Convert to quantized model
    torch.quantization.convert(model, inplace=True)
    return model

# ONNX Runtime quantization (framework-agnostic)
from onnxruntime.quantization import quantize_dynamic, QuantType

def quantize_onnx_model(input_path: str, output_path: str):
    """Quantize an ONNX model for deployment."""
    quantize_dynamic(
        model_input=input_path,
        model_output=output_path,
        weight_type=QuantType.QInt8,
    )
```

### Pruning

Remove low-magnitude weights to create sparse models.

```python
import torch.nn.utils.prune as prune

def prune_model(
    model: torch.nn.Module,
    amount: float = 0.3,    # Prune 30% of weights
    method: str = "l1",     # l1 (magnitude) or random
) -> torch.nn.Module:
    """Apply structured or unstructured pruning to reduce model size."""

    for name, module in model.named_modules():
        if isinstance(module, torch.nn.Linear):
            if method == "l1":
                prune.l1_unstructured(module, name="weight", amount=amount)
            elif method == "random":
                prune.random_unstructured(module, name="weight", amount=amount)

    # Calculate sparsity
    total_params = 0
    zero_params = 0
    for name, module in model.named_modules():
        if isinstance(module, torch.nn.Linear):
            total_params += module.weight.nelement()
            zero_params += (module.weight == 0).sum().item()

    sparsity = zero_params / total_params
    print(f"Model sparsity: {sparsity:.2%}")

    return model

def iterative_pruning(
    model: torch.nn.Module,
    train_fn: callable,
    target_sparsity: float = 0.9,
    num_iterations: int = 10,
) -> torch.nn.Module:
    """
    Iterative magnitude pruning: prune a little, retrain, repeat.
    Achieves better accuracy than one-shot pruning at the same sparsity.
    """
    sparsity_per_step = 1 - (1 - target_sparsity) ** (1 / num_iterations)

    for i in range(num_iterations):
        # Prune
        model = prune_model(model, amount=sparsity_per_step)

        # Retrain (fine-tune) to recover accuracy
        model = train_fn(model, epochs=5)

        # Make pruning permanent
        for name, module in model.named_modules():
            if isinstance(module, torch.nn.Linear):
                prune.remove(module, "weight")

        print(f"Iteration {i+1}/{num_iterations} complete")

    return model
```

### Knowledge Distillation

Train a smaller "student" model to mimic a larger "teacher" model.

```python
import torch
import torch.nn.functional as F

class DistillationLoss(torch.nn.Module):
    """
    Combined loss for knowledge distillation:
    L = alpha * L_hard + (1 - alpha) * L_soft

    L_hard: standard cross-entropy with true labels
    L_soft: KL divergence between teacher and student soft predictions
    """

    def __init__(self, temperature: float = 4.0, alpha: float = 0.7):
        super().__init__()
        self.temperature = temperature
        self.alpha = alpha

    def forward(
        self,
        student_logits: torch.Tensor,
        teacher_logits: torch.Tensor,
        labels: torch.Tensor,
    ) -> torch.Tensor:
        # Hard loss (student vs true labels)
        hard_loss = F.cross_entropy(student_logits, labels)

        # Soft loss (student vs teacher)
        soft_student = F.log_softmax(student_logits / self.temperature, dim=-1)
        soft_teacher = F.softmax(teacher_logits / self.temperature, dim=-1)
        soft_loss = F.kl_div(soft_student, soft_teacher, reduction="batchmean")
        soft_loss = soft_loss * (self.temperature ** 2)

        return self.alpha * soft_loss + (1 - self.alpha) * hard_loss


def distill(
    teacher: torch.nn.Module,
    student: torch.nn.Module,
    train_loader: DataLoader,
    optimizer: torch.optim.Optimizer,
    epochs: int = 20,
    temperature: float = 4.0,
    alpha: float = 0.7,
) -> torch.nn.Module:
    """Train student model using knowledge distillation."""

    criterion = DistillationLoss(temperature=temperature, alpha=alpha)
    teacher.eval()

    for epoch in range(epochs):
        student.train()
        total_loss = 0

        for batch_x, batch_y in train_loader:
            with torch.no_grad():
                teacher_logits = teacher(batch_x)

            student_logits = student(batch_x)
            loss = criterion(student_logits, teacher_logits, batch_y)

            optimizer.zero_grad()
            loss.backward()
            optimizer.step()
            total_loss += loss.item()

        print(f"Epoch {epoch+1}/{epochs}, Loss: {total_loss / len(train_loader):.4f}")

    return student
```

### Compression Comparison

| Method | Size Reduction | Speed Improvement | Accuracy Impact | Complexity |
|--------|---------------|-------------------|-----------------|------------|
| **Dynamic Quantization** | 2-4x | 1.5-3x | Minimal (<1%) | Low |
| **Static Quantization** | 2-4x | 2-4x | Small (1-2%) | Medium |
| **Pruning (30%)** | 1.3x | 1-1.5x | Minimal | Low |
| **Pruning (90%)** | 3-5x | 2-5x (with sparse support) | Moderate (2-5%) | High |
| **Knowledge Distillation** | Varies (student design) | Varies | Small-Moderate | High |
| **Quantization + Pruning** | 5-10x | 3-8x | Moderate (2-5%) | High |
| **Distillation + Quantization** | 10-20x | 5-15x | Moderate (3-7%) | Very High |

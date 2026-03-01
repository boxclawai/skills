#!/usr/bin/env python3
"""
model-eval.py - ML Model Evaluation Pipeline
Usage: python model-eval.py --model <model_path> --test <test_data.csv> --task <classification|regression>

Features:
  - Classification: accuracy, precision, recall, F1, AUC-ROC, confusion matrix
  - Regression: RMSE, MAE, R², MAPE
  - Feature importance (if supported)
  - Generates HTML report
"""

import argparse
import json
import sys
from pathlib import Path
from datetime import datetime

def evaluate_classification(y_true, y_pred, y_prob=None, labels=None):
    """Evaluate classification model."""
    from sklearn.metrics import (
        accuracy_score, precision_score, recall_score, f1_score,
        classification_report, confusion_matrix, roc_auc_score,
        average_precision_score
    )

    metrics = {
        "accuracy": accuracy_score(y_true, y_pred),
        "precision_macro": precision_score(y_true, y_pred, average="macro", zero_division=0),
        "recall_macro": recall_score(y_true, y_pred, average="macro", zero_division=0),
        "f1_macro": f1_score(y_true, y_pred, average="macro", zero_division=0),
        "precision_weighted": precision_score(y_true, y_pred, average="weighted", zero_division=0),
        "recall_weighted": recall_score(y_true, y_pred, average="weighted", zero_division=0),
        "f1_weighted": f1_score(y_true, y_pred, average="weighted", zero_division=0),
    }

    if y_prob is not None:
        try:
            if y_prob.ndim == 1 or y_prob.shape[1] == 2:
                prob = y_prob if y_prob.ndim == 1 else y_prob[:, 1]
                metrics["auc_roc"] = roc_auc_score(y_true, prob)
                metrics["avg_precision"] = average_precision_score(y_true, prob)
            else:
                metrics["auc_roc_ovr"] = roc_auc_score(y_true, y_prob, multi_class="ovr")
        except Exception as e:
            metrics["auc_note"] = f"Could not compute AUC: {e}"

    cm = confusion_matrix(y_true, y_pred, labels=labels)
    report = classification_report(y_true, y_pred, labels=labels, output_dict=True, zero_division=0)

    return metrics, cm, report


def evaluate_regression(y_true, y_pred):
    """Evaluate regression model."""
    import numpy as np
    from sklearn.metrics import (
        mean_squared_error, mean_absolute_error, r2_score,
        mean_absolute_percentage_error, explained_variance_score
    )

    metrics = {
        "rmse": float(np.sqrt(mean_squared_error(y_true, y_pred))),
        "mae": float(mean_absolute_error(y_true, y_pred)),
        "r2": float(r2_score(y_true, y_pred)),
        "mape": float(mean_absolute_percentage_error(y_true, y_pred)),
        "explained_variance": float(explained_variance_score(y_true, y_pred)),
    }

    # Residual statistics
    residuals = y_true - y_pred
    metrics["residual_mean"] = float(np.mean(residuals))
    metrics["residual_std"] = float(np.std(residuals))
    metrics["max_error"] = float(np.max(np.abs(residuals)))

    return metrics, residuals


def generate_report(metrics, task, model_path, test_path, output_dir):
    """Generate evaluation report."""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    report = {
        "timestamp": timestamp,
        "model": str(model_path),
        "test_data": str(test_path),
        "task": task,
        "metrics": {},
    }

    # Format metrics
    for key, value in metrics.items():
        if isinstance(value, float):
            report["metrics"][key] = round(value, 4)
        else:
            report["metrics"][key] = value

    # Save JSON report
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    json_path = output_dir / "eval-report.json"
    with open(json_path, "w") as f:
        json.dump(report, f, indent=2, default=str)

    # Print summary
    print("\n" + "=" * 50)
    print(f"  Model Evaluation Report")
    print("=" * 50)
    print(f"  Task:      {task}")
    print(f"  Model:     {model_path}")
    print(f"  Test Data: {test_path}")
    print(f"  Timestamp: {timestamp}")
    print("-" * 50)
    print("  Metrics:")

    for key, value in report["metrics"].items():
        if isinstance(value, (int, float)):
            if "accuracy" in key or "precision" in key or "recall" in key or "f1" in key or "r2" in key or "auc" in key:
                print(f"    {key:25s} {value:.4f} ({value*100:.1f}%)")
            else:
                print(f"    {key:25s} {value:.4f}")
        else:
            print(f"    {key:25s} {value}")

    print("=" * 50)
    print(f"\n  Report saved: {json_path}")

    return report


def main():
    parser = argparse.ArgumentParser(description="ML Model Evaluation Pipeline")
    parser.add_argument("--model", required=True, help="Path to model file (joblib/pickle/onnx)")
    parser.add_argument("--test", required=True, help="Path to test data (CSV)")
    parser.add_argument("--task", choices=["classification", "regression"], required=True)
    parser.add_argument("--target", default="target", help="Target column name (default: target)")
    parser.add_argument("--output", default="eval-reports", help="Output directory")
    args = parser.parse_args()

    try:
        import pandas as pd
        import numpy as np
        import joblib
    except ImportError as e:
        print(f"Missing dependency: {e}")
        print("Install: pip install pandas numpy scikit-learn joblib")
        sys.exit(1)

    # Load data
    print(f"Loading test data: {args.test}")
    df = pd.read_csv(args.test)
    print(f"  Rows: {len(df)}, Columns: {len(df.columns)}")

    if args.target not in df.columns:
        print(f"Error: Target column '{args.target}' not found. Available: {list(df.columns)}")
        sys.exit(1)

    X_test = df.drop(columns=[args.target])
    y_test = df[args.target].values

    # Load model
    print(f"Loading model: {args.model}")
    model = joblib.load(args.model)

    # Predict
    print("Running predictions...")
    y_pred = model.predict(X_test)

    # Evaluate
    if args.task == "classification":
        y_prob = None
        if hasattr(model, "predict_proba"):
            y_prob = model.predict_proba(X_test)
        metrics, cm, class_report = evaluate_classification(y_test, y_pred, y_prob)

        # Add per-class metrics
        for cls, cls_metrics in class_report.items():
            if isinstance(cls_metrics, dict):
                for metric, value in cls_metrics.items():
                    metrics[f"class_{cls}_{metric}"] = value

    elif args.task == "regression":
        metrics, residuals = evaluate_regression(y_test, y_pred)

    # Feature importance
    if hasattr(model, "feature_importances_"):
        importances = model.feature_importances_
        feature_names = X_test.columns.tolist()
        top_features = sorted(zip(feature_names, importances), key=lambda x: -x[1])[:10]
        metrics["top_features"] = {name: round(float(imp), 4) for name, imp in top_features}
        print("\nTop 10 Features:")
        for name, imp in top_features:
            bar = "█" * int(imp * 50)
            print(f"  {name:30s} {imp:.4f} {bar}")

    # Generate report
    generate_report(metrics, args.task, args.model, args.test, args.output)


if __name__ == "__main__":
    main()

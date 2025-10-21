"""INLA Baseline Model chapkit service.

A Bayesian hierarchical model implemented with the INLA library using R.
Uses cyclic random effects for time periods and IID effects for spatial units.
"""

from pathlib import Path

from chapkit import BaseConfig
from chapkit.api import AssessedStatus, MLServiceBuilder, MLServiceInfo
from chapkit.modules.artifact import ArtifactHierarchy
from chapkit.modules.ml import ShellModelRunner

# Get absolute path to R scripts directory
SCRIPTS_DIR = Path(__file__).parent


class INLAConfig(BaseConfig):
    """Configuration for INLA baseline model."""

    n_lag: int = 3
    """Number of lags to include in the model."""

    precision: float = 0.01
    """Prior on the precision of fixed effects. Works as regularization."""


# Create shell-based runner with R command templates
# Note: Chapkit will substitute these variables with actual file paths:
#   {config_file} - YAML config file
#   {data_file} - Training data CSV
#   {model_file} - Model file (RDS format from R)
#   {historic_file} - Historic data CSV
#   {future_file} - Future data CSV
#   {output_file} - Predictions CSV

# Training command: train.R expects (train_fn, model_fn, config_fn)
train_command = f"Rscript {SCRIPTS_DIR}/train.R {{data_file}} {{model_file}} {{config_file}}"

# Prediction command: predict.R expects (model_fn, hist_fn, future_fn, preds_fn, config_fn)
predict_command = (
    f"Rscript {SCRIPTS_DIR}/predict.R "
    f"{{model_file}} {{historic_file}} {{future_file}} {{output_file}} {{config_file}}"
)

# Create shell model runner
# Note: R will save models as RDS, but we tell chapkit "pickle" format
# as the generic binary format identifier
runner = ShellModelRunner(
    train_command=train_command,
    predict_command=predict_command,
    model_format="pickle",
)

# Create ML service info with metadata from MLproject
info = MLServiceInfo(
    display_name="INLA Baseline Model (chapkit)",
    version="1.0.0",
    summary="A Bayesian hierarchical model implemented with the INLA library",
    description=(
        "(Uses chapkit) Uses a cyclic random effect for months/weeks shared across all districts "
        "alongside an IID effect for each district. Supports both weekly and monthly data. "
        "Intended as a baseline model for comparison in benchmarking."
    ),
    author="CHAP team",
    author_note="Red status - baseline model for comparison purposes only",
    author_assessed_status=AssessedStatus.red,
    contact_email="knut.rand@dhis2.org",
    organization="HISP Centre, University of Oslo",
)

# Create artifact hierarchy for ML artifacts
HIERARCHY = ArtifactHierarchy(
    name="inla_baseline_pipeline",
    level_labels={
        0: "trained_model",  # INLA model with spatial/temporal effects
        1: "predictions",    # Disease case predictions with samples
    },
)

# Build the FastAPI application
app = (
    MLServiceBuilder(
        info=info,
        config_schema=INLAConfig,
        hierarchy=HIERARCHY,
        runner=runner,
    )
    .with_monitoring()
    .build()
)


if __name__ == "__main__":
    from chapkit.api import run_app

    run_app("inla_baseline_service:app")
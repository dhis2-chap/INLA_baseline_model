# INLA Baseline Model - Chapkit Integration

This document describes how to run the INLA baseline model as a chapkit ML service.

## Quick Start

```bash
# Navigate to the project directory
cd /home/ivargry/dev/INLA_baseline_model

# Start the service
fastapi dev inla_baseline_service.py

# Service available at: http://127.0.0.1:8000
```

## Features

- **Model**: INLA Bayesian hierarchical model with cyclic temporal effects
- **Target**: `disease_cases`
- **Required covariates**: `population`
- **Optional covariates**: Configurable via MLproject adapters
- **Runner**: ShellModelRunner (executes R scripts)
- **Temporal modes**: Supports both weekly and monthly data
- **Assessment**: Red (baseline for comparison)

## Architecture

```
┌──────────────┐
│ FastAPI App  │
│ (chapkit)    │
└──────┬───────┘
       │
       ▼
┌──────────────────┐
│ ShellModelRunner │
└──────┬───────────┘
       │
       ├─ Train ──▶ train.R
       │            (reads CSV/YAML, writes model)
       │
       └─ Predict ▶ predict.R
                    (reads model/CSV/YAML, writes predictions CSV)
```

## Configuration Schema

```json
{
  "type": "object",
  "properties": {
    "n_lag": {
      "type": "integer",
      "default": 3,
      "description": "Number of lags to include in the model"
    },
    "precision": {
      "type": "number",
      "default": 0.01,
      "description": "Prior on the precision of fixed effects. Works as regularization"
    }
  }
}
```

## Complete Workflow Example

### 1. Check Service Health

```bash
curl http://127.0.0.1:8000/health
```

### 2. View Service Metadata

```bash
curl http://127.0.0.1:8000/api/v1/info
```

**Response:**
```json
{
  "display_name": "INLA Baseline Model",
  "version": "1.0.0",
  "summary": "A Bayesian hierarchical model implemented with the INLA library",
  "author": "CHAP team",
  "author_assessed_status": "red",
  "contact_email": "knut.rand@dhis2.org",
  "organization": "HISP Centre, University of Oslo"
}
```

### 3. Create Configuration

```bash
curl -X POST http://127.0.0.1:8000/api/v1/configs \
  -H "Content-Type: application/json" \
  -d '{
    "name": "inla_baseline_monthly",
    "data": {
      "n_lag": 3,
      "precision": 0.01
    }
  }'
```

**Response:**
```json
{
  "id": "01JAABC123XYZ456...",
  "name": "inla_baseline_monthly",
  "data": {
    "n_lag": 3,
    "precision": 0.01
  },
  "created_at": "2025-10-21T09:30:00Z"
}
```

### 4. Train Model

The training data should be in the format expected by the INLA model, with columns matching the adapters defined in MLproject:
- `disease_cases` (target)
- `population` (required)
- `time_period`, `location`
- Optional: `rainfall`, `mean_temperature`, etc.

```bash
# Note: You'll need to prepare your training data in the appropriate format
# For monthly data, it should include: time_period, location, disease_cases, population, month, year
curl -X POST http://127.0.0.1:8000/api/v1/ml/\$train \
  -H "Content-Type: application/json" \
  -d @training_request.json
```

Where `training_request.json` contains your training data in the columnar format chapkit expects.

### 5. Make Predictions

```bash
curl -X POST http://127.0.0.1:8000/api/v1/ml/\$predict \
  -H "Content-Type: application/json" \
  -d '{
    "model_artifact_id": "01JAABC789GHI345...",
    "historic": { ... },
    "future": { ... }
  }'
```

The predict endpoint will:
1. Load the trained INLA model
2. Combine historic and future data (as per predict.R logic)
3. Generate 1000 prediction samples using INLA posterior sampling
4. Return predictions as CSV with columns: `time_period`, `location`, `sample_0`, ..., `sample_999`

## Data Format Requirements

### Training Data
Must include the columns expected by train.R and the INLA formula:
- `Cases` or `disease_cases`: Number of disease cases
- `E` or `population`: Population (used as offset)
- `month` or `week`: Time period indicator
- `ID_year`: Year
- `ID_spat` or `location`: Spatial unit identifier

### Future Data
Same as training data but `Cases`/`disease_cases` can be NA (will be predicted)

### Predictions Output
- `time_period`: Time period identifier
- `location`: Spatial unit identifier
- `sample_0` through `sample_999`: 1000 posterior predictive samples

## Model Details

The INLA model uses the formula:
```r
Cases ~ 1 + f(ID_spat, model='iid', replicate=ID_year) +
        f(ID_time_cyclic, model='rw1', cyclic=TRUE, scale.model=TRUE)
```

- **IID spatial effect**: Random effect for each location, replicated across years
- **Cyclic temporal effect**: Random walk model for seasonal patterns
- **Family**: Negative binomial
- **Offset**: log(population)

## Weekly vs Monthly Data

The model automatically detects whether to use weekly or monthly mode based on the presence of a `week` column:
- **Weekly**: Uses 52 periods, `nlag=12` (defined in config or defaults to 12)
- **Monthly**: Uses 12 periods, `nlag=3` (defined in config or defaults to 3)

## Dependencies

The R scripts require:
- R (>= 4.0)
- INLA library
- yaml, jsonlite, dplyr, dlnm libraries
- sf, spdep (for spatial effects)

Install with:
```r
install.packages(c("yaml", "jsonlite", "dplyr", "dlnm", "sf", "spdep"))
install.packages("INLA", repos=c(getOption("repos"),
                 INLA="https://inla.r-inla-download.org/R/stable"), dep=TRUE)
```

## Testing with Example Data

The repository includes example data in `example_data_monthly/`:
```bash
# Example using provided test data
# You'll need to convert the CSV files to the JSON format chapkit expects
```

## Troubleshooting

### "Training script failed with exit code 1"
- Check R dependencies are installed
- Check stderr in job result for R error messages
- Verify data has required columns

### "Model file not created"
- Check train.R has write permissions
- Verify train.R successfully saves model file
- Check R script logs

### YAML parsing errors
- Ensure chapkit is writing YAML format (not JSON)
- Check config file structure matches expected format

## Command Templates

The service uses these command templates (defined in `inla_baseline_service.py`):

**Train:**
```bash
Rscript train.R {data_file} {model_file} {config_file}
```

**Predict:**
```bash
Rscript predict.R {model_file} {historic_file} {future_file} {output_file} {config_file}
```

Chapkit substitutes the variables with actual temp file paths during execution.
# INLA baseline model
A simple INLA model without any covariates. It uses a cyclic random effect for months/weeks shared across all districts alogside an IID effect for each district. The formula is written as

```R
formula <- Cases ~ 1 + f(ID_spat, model='iid', replicate=ID_year) +
              f(ID_time_cyclic, model='rw1', cyclic=TRUE, scale.model=TRUE)
```
This model is not meant to be used in production, instead as a baseline to compare other models too, for instance in benchmarking. More complex models with additional covariates should at least outperform this baseline model.

## The difference between weekly and monthly
```R
if( "week" %in% colnames(df)){ # for a weekly model
    df <- mutate(df, ID_time_cyclic = week)
    df <- offset_years_and_weeks(df)
    nlag <- 12
  } else{ # for a monthly model
    df <- mutate(df, ID_time_cyclic = month)
    df <- offset_years_and_months(df)
    nlag <- 3
  }
```
The above code shows the difference needed between weekly and monthly data. We assume weekly input data will have a `week` column and we then define variables for the different cases. For instance weeks have `nlag = 12` while months have `nlag = 3`, which correpsonds to roughly the same amount of time. We also construct the `ID_time_cyclic` column from either weeks or months so the formula later is consistent in both cases.

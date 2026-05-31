# Roadmap Board

## Data Quality
- [ ] Expand provider policy coverage and periodically verify policy-source links
- [ ] Add model-level overrides where provider-wide policy is too coarse
- [ ] Add richer change summaries (absolute + percentage deltas, free↔paid transitions)
- [ ] Add schema versioning policy and migration notes for `docs/data/*.json`

## Ranking Quality
- [ ] Tune weighted task scoring with benchmark feedback
- [ ] Add explicit modality-confidence weighting for mixed-modality models
- [ ] Add score explainability output for each category top pick
- [ ] Add regression tests for ranking drift

## UX
- [ ] Add table-level column chooser and compact mode
- [ ] Add provider dashboard drill-down page
- [ ] Add richer trust tooltips and policy legend in all pages
- [ ] Add compare-page integration with change-movers and policy filters

## Ops Reliability
- [ ] Add retry/backoff observability metrics in workflow logs
- [ ] Add stricter history consistency checks in CI
- [ ] Add fallback mode that preserves previous snapshot on fetch failures
- [ ] Add release cadence/status page for generated data quality checks

---
title: Deployment Fitting Guide
bundle-version: "1.0"
created: 2026-10-14
tags: [deployment, evaluation, scoring, model-selection, fitting, gpu, inference]
---

# Deployment Fitting Guide

A framework for evaluating AI model deployments using four measurable
traits — Quality, Speed, Context, and Size — scored against class-specific
baselines and aggregated into a single deployment score.

The framework evaluates **deployments** (model + engine + hardware + configuration
as a unit), not individual models. A speculative decoding setup with target +
draft model on 4 GPUs is one deployment, scored as one unit.

## Concepts

| Document | Topic |
|----------|-------|
| [four-traits.md](./four-traits.md) | The 4 deployment traits: definitions, correlations, what was considered and rejected |
| [suv-model.md](./suv-model.md) | The 4×4 SUV positioning analogy for understanding trait relationships |
| [class-baselines.md](./class-baselines.md) | Class-specific baselines: Gen AI (Opus) vs Decision (Jev), selection criteria |
| [weighted-scoring.md](./weighted-scoring.md) | Scoring formula, weight rationale, interpretation bands, worked examples |

## Log

| Date | Change |
|------|--------|
| 2026-10-14 | Initial bundle creation from deployment evaluation session |

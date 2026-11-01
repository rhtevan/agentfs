# README Audit Dimensions

Lookup tables for scope-specific audit dimensions. The agent loads
this file on demand during Step 3 interpretation.

## USER Scope Dimensions

| # | Dimension | Check |
|---|-----------|-------|
| D1 | Skill Count | Does README count match actual skill count? |
| D2 | Skill Categories | Does category table match actual skills? |
| D3 | Knowledge Bundles | Does bundle count or list match? |
| D4 | Directory Structure | Does tree diagram match actual layout? |
| D5 | Guardrail Summary | Do guardrail names and count match? |
| D6 | Version References | Do version numbers match? |
| D7 | Feature Descriptions | Do features reflect actual skills? |
| D8 | Setup Instructions | Do paths and commands still work? |
| D9 | Coverage Gaps | Does major content exist without mention? |

## PROJECT Scope Dimensions

| # | Dimension | Check |
|---|-----------|-------|
| P1 | Project Skill Count | Does count match actual? |
| P2 | Agent Profiles | Do profiles match actual? |
| P3 | Agent Identity | Does identity match SOUL.md? |
| P4 | Directory Structure | Does tree match actual layout? |
| P5 | AGENTS.md References | Are references accurate? |
| P6 | Feature Descriptions | Do features reflect actual content? |
| P7 | Setup / Onboarding | Do instructions still work? |
| P8 | Coverage Gaps | Does content exist without mention? |

## Interpretation Rules

- Absence of a claim is not drift. Drift occurs only when the
  README makes a claim that contradicts reality. Mark absent
  claims as N/A.
- Coverage Gaps (D9/P8) are informational. Mark as ℹ️, not ⚠️.

---
type: Trouble Ticket
title: "INC00847291 — SFP Failure at AGG-NYC-E-01"
description: "Original ServiceNow trouble ticket with work notes from 4 engineers over 2.5 hours. Source from which RCA labels were mined."
tags: [trouble-ticket, servicenow, itsm, nlp-extraction, label-source]
timestamp: 2026-06-25T16:35:47
---

# Trouble Ticket — INC00847291

The **raw source material** from which [RCA labels](./rca-labels.md) were extracted.

## Source File

- [06_trouble_ticket.json](./samples/06_trouble_ticket.json)

## Ticket Summary

| Field | Value |
|-------|-------|
| ID | INC00847291 |
| Priority | P1 — Critical |
| Created | 2025-03-14 02:17:33 UTC |
| Resolved | 2025-03-14 04:52:30 UTC |
| MTTR | 155 minutes |
| Resolution | Hardware Failure / Optics/SFP |

## NLP Extraction Challenges

This ticket illustrates why automated label extraction from tickets is difficult:

1. Initial title says "RAN" but root cause was in Transport domain
2. Root cause element not mentioned until 35 min after ticket creation
3. Specific interface buried in free text, not a structured field
4. Requires domain knowledge to interpret optical power readings
5. Resolution code is too generic without sub_code

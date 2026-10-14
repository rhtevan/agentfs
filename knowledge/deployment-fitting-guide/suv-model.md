---
title: The 4×4 SUV Model
parent: deployment-fitting-guide
created: 2026-10-14
tags: [deployment, evaluation, analogy, visualization]
---

# The 4×4 SUV Model

A positioning analogy for the four deployment traits. Each trait maps
to a wheel on a 4×4 SUV, with position reflecting its role in the
deployment experience.

## Layout

```
          Direction of travel (toward the user/output)
                           ▲
                           │

                         FRONT
         ┌───────────────────────────────────┐
         │                                   │
         │    ┌───┐                 ┌───┐    │
         │    │   │                 │   │    │
         │ ┌──┴───┴──┐           ┌──┴───┴──┐ │
    L    │ │ QUALITY │           │  SPEED  │ │    R
    E    │ │ (steer) │           │  (feel) │ │    I
    F    │ └──┬───┬──┘           └──┬───┬──┘ │    G
    T    │    │   │                 │   │    │    H
         │    └───┘                 └───┘    │    T
         │                                   │
         │    ┌───┐                 ┌───┐    │
         │    │   │                 │   │    │
         │ ┌──┴───┴──┐           ┌──┴───┴──┐ │
         │ │ CONTEXT │           │  SIZE   │ │
         │ │  (fuel) │           │ (cargo) │ │
         │ └──┬───┬──┘           └──┬───┬──┘ │
         │    │   │                 │   │    │
         │    └───┘                 └───┘    │
         │                                   │
         │                REAR               │
         └───────────────────────────────────┘
```

## Position Rationale

### Front Axle — What the user experiences directly

| Position | Trait | Role |
|----------|-------|------|
| **Front-Left (driver side)** | **Quality** | The steering wheel. Every deployment decision starts here. Determines direction — if output can't be trusted, nothing else matters. |
| **Front-Right (passenger side)** | **Speed** | Rides alongside quality in every interaction. Users feel latency immediately. Front because it's user-facing; right because it doesn't steer decisions, it accompanies them. |

### Rear Axle — What supports the journey

| Position | Trait | Role |
|----------|-------|------|
| **Rear-Left** | **Context** | The fuel tank. How much information you can carry into each request. Fill it before the trip, monitor during, and when it runs out (or degrades), the vehicle stalls. Users feel the *absence* of context, not context itself. |
| **Rear-Right** | **Size** | The cargo. Physical constraint — VRAM, GPUs, cost. Settled before deployment, not during. Constrains everything else but users never touch it. |

## Drive Dynamics

### Front-wheel drive (Quality + Speed)
Prioritizes user experience. Typical of cloud API deployments where
you don't control size or context. Works on paved roads (standard tasks).

### Rear-wheel drive (Context + Size)
Infrastructure-first deployment. Hardware and context capacity without
user-facing optimization. Raw power, no finesse.

### 4×4 (all four engaged)
Balanced deployment where all traits are considered and tuned.
Example: speculative decoding (Speed), FP8 quantization (Size),
configured context (Context), reasoning-capable model (Quality).
Gets you off-road into workloads that generic deployments can't handle.

### Transfer Case — Architecture Decisions
The linkage between front and rear axles. Speculative decoding,
quantization strategy, TP configuration, and multi-tier architecture
(e.g., SDM + Drools + LLM) are the transfer case. They couple
user experience (front) with infrastructure constraints (rear).

```
Quality ◄──front axle──► Speed
   │                        │
   │   transfer case        │
   │   (architecture)       │
   │                        │
Context ◄──rear axle───► Size
```

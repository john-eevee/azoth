---
layout: home

hero:
  name: "Azoth"
  text: "Distributed reactive workflow engine."
  tagline: Dataflow execution mapped through constrained Starlark DSL. Deterministic, resumable, and fault-tolerant.
  actions:
    - theme: brand
      text: Get Started
      link: /guide/architecture
    - theme: alt
      text: View on GitHub
      link: https://github.com/organization/azoth

features:
  - title: Dataflow execution
    details: Tasks become runnable when their inputs arrive on channels, rather than through a static batch scheduler.
  - title: Constrained DSL
    details: Deterministic, reproducible plans executed via a Starlark-based DSL.
  - title: Strong Resumability
    details: Content-addressable task fingerprinting makes restarts seamless.
---
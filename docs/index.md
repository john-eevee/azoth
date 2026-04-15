---
layout: home

hero:
  name: "Azoth"
  text: "Reactive workflow engine based on files."
  tagline: We don't stream data; we stream information that allows the execution to be close to the data, instead of streaming data to the execution.
  actions:
    - theme: brand
      text: Get Started
      link: /guide/architecture
    - theme: alt
      text: View on GitHub
      link: https://github.com/john-eeve/azoth

features:
  - title: Bring Compute to Data
    details: We don't stream data. We stream information that allows the execution to be closed to the data, instead of streaming data to the execution.
  - title: Dataflow execution
    details: Tasks become runnable when their inputs arrive on channels, rather than through a static batch scheduler.
  - title: Constrained DSL
    details: Deterministic, reproducible plans executed via a Starlark-based DSL.
  - title: Strong Resumability
    details: Content-addressable task fingerprinting makes restarts seamless.
---

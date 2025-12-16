# Mermaid fixture (`mdview`)

This file is dedicated to testing Mermaid code block behavior (deterministic and does not require network access).

SCROLLTARGET_MERMAID

```mermaid
flowchart TD
  A[Start] --> B{Choice}
  B -->|Yes| C[OK]
  B -->|No| D[Retry]
```

```mermaid
flowchart LR
  A[Start] --> B{Choice}
  B -->|Yes| C[Success]
  B -->|No| D[Retry]
  D --> A
```

```mermaid
stateDiagram-v2
  [*] --> Idle
  Idle --> InProgress: Start
  InProgress --> Idle: Done
```

Multiple diagram attachments should appear below (placeholder first; if network is available they may load the images).


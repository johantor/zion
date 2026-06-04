---
description: Run pre-PR ship gate and return a go/no-go summary
---

Run backend tests (`oracle`), frontend e2e tests (`dozer`), build and lint checks, then `/review`, and return a single go/no-go with blocking items.

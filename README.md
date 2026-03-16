# cc-wh-controller
CC:Tweaked program to monitor create mod warehouses and sync with the global coordinator

Its job is to:

1. publish heartbeats
2. answer targeted snapshot requests
3. receive and execute assignment batches
4. report assignment execution and train departures

## Filesystem layout

Development layout:

- `bootstrap.lua`: stable `wget run` installer entrypoint
- `startup.lua`: development launcher that runs `/src/main.lua`
- `src/main.lua`: runnable warehouse entrypoint
- `src/app/`: controller orchestration, snapshot building, and execution flow
- `src/model/`: validated warehouse config
- `src/infra/`: persistence, network, and peripheral-boundary code
- `src/ui/`: terminal UI
- `src/util/`: small shared helpers
- `src/deps/`: vendored runtime dependencies such as logging
- `install/`: installer, manifest, and config template for this program
- `tst/`: warehouse tests and test-only dependencies

Installed layout:

- `/startup.lua`: generated launcher that selects the active installed version and runs `/programs/wh-controller/<version>/src/main.lua`
- `/programs/wh-controller/<version>/src/main.lua`: runnable installed warehouse entrypoint
- `/etc/wh-controller/config.lua`: machine-local warehouse config when installed
- `/var/wh-controller/`: persisted batch/execution state and warehouse log output when installed

Runtime convention:

- `startup.lua` is only a launcher
- `src/main.lua` is the executable entrypoint
- all other files under `src/` are modules loaded with `require`

## Installation

Use `bootstrap.lua` as the operator-facing installer entrypoint. Make sure to use the "raw" file url, not the github explorer ui.

- `wget run <bootstrap-url>` installs the baked-in tagged release
- `wget run <bootstrap-url> -b <barnch>` installs using a branch tip for testing
- `wget run <bootstrap-url> -c <commit>` installs using an exact commit for testing
- pass `--force` to the installer only when you intentionally want to replace an existing installed version directory

The bootstrap only resolves the source and downloads that source's real installer.
Installed versions still live under `/programs/wh-controller/<version>/`, and mutable branch names are never used as installed version directory names.

## Network flow

```text
computer/0 coordinator                        computer/2 warehouse
----------------------                        --------------------

heartbeat <---------------------------------- heartbeat broadcast

get_snapshot --------------------------------> reconcile local batch state
                                             -> rebuild local snapshot
snapshot <----------------------------------- targeted snapshot reply

(on release only)
assignment_batch ----------------------------> persist batch
                                             -> execute batch
assignment_ack <----------------------------- acknowledge receipt
assignment_execution <----------------------- report queued work

train_departure_notice <--------------------- report post-execution departures
```

`get_snapshot` is the ongoing reconciliation path.

If the coordinator includes no active batch, or a different active batch id,
the warehouse clears stale persisted local assignment state before replying.

## Current behavior

- batches execute automatically when an `assignment_batch` arrives
- the UI may show `(persisted)` on restored batch or execution state after boot
- the next `get_snapshot` can clear that restored state if the coordinator says no active batch exists
- train departures are reported back to the coordinator only for the configured export station
- when installed through the versioned launcher flow, config loads from `/etc/wh-controller/config.lua`
- persisted assignment state and logs are written under `/var/wh-controller/`
- startup fails loudly if `/etc/wh-controller/config.lua` is missing

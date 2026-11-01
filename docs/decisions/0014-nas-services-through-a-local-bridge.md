# Reuse NAS learning services through a local bridge

## Status
Accepted
Class: architecture

## Context and Problem Statement

The user operates NAS services for Canvas material downloads, lecture processing, deadline calendars and homework generation. Studio already has overlapping local features. A unified course interface needs a clear owner for background execution and source files. The contract is [NAS learning services](../specs/0017-nas-learning-services.md).

## Decision Drivers

- Preserve independent NAS schedules and existing report protections.
- Keep canonical course files usable through Syncthing and outside Studio.
- Distinguish generation, validation and school submission status.
- Keep credentials and remote execution authority out of browser and model tools.
- Make stale data and failed jobs visible without triggering another run.

## Considered Options

- Read existing synchronized course files and bridge sanitized NAS state through the local daemon.
- Reimplement the NAS workers inside Studio and migrate scheduling and credentials.
- Embed service pages as iframes without a shared course/data model.

## Decision Outcome

The integration uses synchronized files for material access and a local SSH bridge for service/job observations and approved fixed actions. NAS remains the execution owner; Studio owns navigation and explicit course mapping. This adds an adapter dependency on the deployed worker schema and SSH availability, but avoids competing schedulers and duplicate generation.

## Pros and Cons of the Options

The local bridge reuses working infrastructure and supports cached offline views, but must version its schema and distinguish NAS freshness from Syncthing freshness. Reimplementation offers a single stack but requires migration of existing credentials, jobs and protections and risks duplicate work. Iframes are inexpensive but cannot reliably unify deadlines, deliverables, lecture references and status semantics.

## Links

- [NAS integration contract](../specs/0017-nas-learning-services.md)
- [Existing Canvas integration](../specs/0011-canvas-and-schools.md)
- [Library and daemon boundaries](../architecture.md)

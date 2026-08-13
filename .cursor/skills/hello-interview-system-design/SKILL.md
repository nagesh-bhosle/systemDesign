---
name: hello-interview-system-design
description: Implements Hello Interview system-design breakdowns as runnable Spring Boot + Docker demos in this repo. Use when adding a new interview problem (GoPuff, Dropbox, Yelp, or similar), mapping bad/good/great alternatives to application.yml flags, or teaching from Hello Interview notes.
---

# Hello Interview system-design demos

## When to use

The user wants a **working implementation** of a Hello Interview (or similar) system-design problem in this repository, not slides only.

Do not paste Hello Interview articles verbatim into the repo. Capture **requirements, tradeoffs, and our mapping**.

## Repo conventions

Mirror existing demos:

- Folder: `<problem>-demo/` (e.g. `gopuff-demo`, `yelp-demo`)
- Java 21, Spring Boot 3.3.x, Maven wrapper, Docker Compose
- Design notes: `<Problem>.md` next to the code (original summary, not scraped prose)
- README: APIs, flags, how to start/stop
- Ports: do not collide (Dropbox 8080, Yelp 8081, GoPuff 8082)
- Git: `feature/<topic>` from `main` per root `AGENTS.md`

## Implementation pattern

1. **FR / NFR / out of scope** — write them once in `<Problem>.md` and the README.
2. **Entities then APIs** — nouns first, then the smallest REST surface that satisfies FR.
3. **Default = “great” path** from the breakdown.
4. **Every named alternative** is a real strategy class behind an interface, selected with `@ConditionalOnProperty` and `application.yml` (same idea as Yelp `search.backend`).
5. **Docker** for datastores the design actually needs (Postgres, Redis, Azurite, etc.).
6. **Seed data + a UI or curl examples** so the demo is one command (`./start.sh`).
7. **A test that proves the hard invariant** (e.g. no double-booking, one review per user).

## Quality bar

- Controllers depend on interfaces, not a specific “great” class.
- Config flags are documented with why the default is preferred.
- Failure modes called out in the article (deadlock, crash between two stores, stale cache) are either handled or documented next to the flag.
- `./mvnw clean compile` (and tests) must pass before commit.

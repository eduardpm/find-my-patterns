# Specification Quality Checklist: Re-platform the Backend onto NestJS

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-07-28
**Feature**: [spec.md](../spec.md)

## Content Quality

- [x] No implementation details (languages, frameworks, APIs)
- [x] Focused on user value and business needs
- [x] Written for non-technical stakeholders
- [x] All mandatory sections completed

## Requirement Completeness

- [x] No [NEEDS CLARIFICATION] markers remain
- [x] Requirements are testable and unambiguous
- [x] Success criteria are measurable
- [x] Success criteria are technology-agnostic (no implementation details)
- [x] All acceptance scenarios are defined
- [x] Edge cases are identified
- [x] Scope is clearly bounded
- [x] Dependencies and assumptions identified

## Feature Readiness

- [x] All functional requirements have clear acceptance criteria
- [x] User scenarios cover primary flows
- [x] Feature meets measurable outcomes defined in Success Criteria
- [x] No implementation details leak into specification

## Notes

- Items marked incomplete require spec updates before `/speckit-clarify` or `/speckit-plan`

### Validation iteration 1 (2026-07-28)

**A note on "no implementation details".** This item passes, but it deserves an explanation because
the feature's *title* names a framework. The user's request is by nature a technology choice, so the
framework appears in the title and the Input line only. Every requirement and success criterion below
is written in terms of observable behaviour — data survives, clients keep working, rules stay
enforced, responses stay identical — and none names a language, framework, library, or endpoint. A
reader who had never heard of either technology could still verify every FR and SC.

The corollary is that this spec is unusually testable *because* it is a re-platform: "identical to
what it does today" is the strictest possible acceptance criterion, and the current system is
available to compare against.

**Outstanding — 1 [NEEDS CLARIFICATION] marker:**

- **FR-020** — whether the existing on-disk storage is kept exactly as it is, or whether swapping the
  storage engine is in scope too. This is the single largest fork in the feature: keeping it makes
  the change a code rewrite against untouched data; changing it turns the change into a data
  migration, where SC-001's "100% of entries survive" carries real risk. Left to the user rather than
  defaulted, because a request for this particular framework often carries an assumption about the
  data layer that comes with it.

**Deliberate design choices in this spec, recorded so they are not mistaken for omissions:**

- No new capability appears anywhere. That is correct for a re-platform; a spec that quietly added
  features here would make it impossible to tell a migration bug from new behaviour.
- The maintainer appears as an actor in User Story 4. For a solo project where the maintainer is also
  the only user, that is the honest framing — but it is ranked P4 so it cannot justify risk to
  Stories 1–3.
- A "Cost and constitutional tension" section was added beyond the template. Principle II pushes
  against this work, and the spec is the durable record of that decision.

### Validation iteration 2 (2026-07-28) — all items pass

**Q1 → A**: the existing on-disk storage is kept exactly as it is; the new backend is written to read
what is already there.

This is the low-risk answer and it changes the character of the feature: it is now a code rewrite
against untouched data rather than a data migration, so SC-001 ("100% of entries survive") is
satisfied by construction rather than by getting a conversion right. Revert becomes trivial for the
same reason — run the old backend again against the same file.

**Follow-on changes this forced:**

- **FR-020** rewritten as a positive constraint: no engine change, no transformation, no export/import,
  backup stays a file copy.
- **FR-021** added — adopt the stored structure as it stands, including the revision marker added in
  feature 003, with no conversion step for the user.
- **FR-022** added — starting the new backend must not modify the diary at all. This is the sharp
  edge of the decision: data-layer tooling commonly "helps" by adjusting stored structure on startup,
  and that is the most plausible way this feature could quietly damage the diary.
- **SC-011** added — a before-and-after comparison of the stored file shows no difference after
  merely running and reading.
- Two edge cases added covering a subtle structure mismatch and unwanted auto-adjustment on startup.

Final counts: 22 functional requirements, 11 success criteria, 5 user stories, 0 open markers.

### Blocking dependency

**None.** Unlike feature 003, no constitution amendment is needed: v1.1.0 constrains the system's
shape, not its implementation language. Verified by searching the constitution for any language or
framework constraint — there is none.

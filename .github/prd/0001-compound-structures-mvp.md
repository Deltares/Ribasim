# PRD 0001: Compound Structures for Ribasim-python (MVP)

## Problem Statement
Ribasim-python model builders currently need to assemble real-world facilities manually from atomic Nodes and Links. For common systems such as reservoirs, this requires low-level choreography across Basin, release connectors, and optional control Nodes. The current approach is flexible but creates repetitive setup work, raises the chance of modeling mistakes, and makes model intent harder to read and review.

## Solution
Introduce a generic Compound Structure capability in Ribasim-python that lets users define one logical object, validate it, and materialize it into existing atomic Nodes and Links. The MVP delivers Reservoir as the first built-in Compound Structure type.

The solution preserves Ribasim-core simulation semantics by generating only existing atomic types and using existing model validation pathways. Compound Structure membership and provenance are tracked through existing `meta_` columns so grouped Nodes remain discoverable without schema-breaking changes.

## User Stories
1. As a Ribasim-python model builder, I want to define a reservoir as one logical object, so that I do not manually assemble multiple atomic Nodes every time.
2. As a domain expert, I want clear Compound Structure terminology, so that model intent is understandable without deep implementation knowledge.
3. As a model builder, I want pre-materialization validation, so that invalid structure definitions fail early.
4. As a model builder, I want integration validation to reuse existing model validation timing, so that Compound Structures behave consistently with regular node additions.
5. As a model builder, I want Reservoir to require identity, geometry anchor, Basin computability inputs, and at least one release connector, so that generated structures are operationally complete.
6. As a model builder, I want optional control definitions for Reservoir, so that passive and controlled reservoirs are both supported.
7. As a model maintainer, I want generated Nodes tagged with a shared Compound Structure ID, so that I can find all Nodes belonging to one logical structure.
8. As a model maintainer, I want generated Nodes tagged with a Compound Structure type, so that I can filter structures by category.
9. As a model maintainer, I want optional recipe provenance metadata, so that I can inspect how a structure was created.
10. As a model maintainer, I want detached status metadata after manual edits, so that I can distinguish recipe-faithful and diverged groups.
11. As a model builder, I want automatic node ID allocation in MVP, so that I can rely on existing model behavior.
12. As a model builder, I want Compound Structures to be immutable after add_to_model in MVP, so that lifecycle behavior is predictable.
13. As a model builder, I want to remove and recreate a Compound Structure when changing its recipe, so that update behavior is explicit.
14. As a framework maintainer, I want a reusable protocol shared across structure types, so that new built-in structures can be added consistently.
15. As a framework maintainer, I want contracts defined through a type-agnostic schema, so that required and optional elements are clear and extensible.
16. As a framework maintainer, I want validation built from composable rules, so that rules can be reused across different Compound Structures.
17. As a framework maintainer, I want ordered rule-set execution in MVP, so that behavior is simple now and extensible later.
18. As a framework maintainer, I want a built-in contract registry for MVP, so that supported structures are controlled and stable.
19. As a user of generated models, I want no changes to Ribasim-core node semantics, so that existing simulation expectations remain valid.
20. As a documentation reader, I want a reservoir walkthrough from logical input to emitted Nodes/Links, so that adoption is straightforward.
21. As a documentation reader, I want validation failure modes explained by stage, so that I can fix issues faster.
22. As a documentation reader, I want MVP boundaries and deferred items documented, so that I know which capabilities are intentionally excluded.
23. As a QGIS and reporting user, I want detached provenance to be visible in metadata, so that downstream tooling can surface structure state.
24. As a project maintainer, I want the framework to support adding a second structure type with minimal architectural change, so that the MVP proves scalability.

## Implementation Decisions
- Compound Structure is defined as a user-facing recipe that materializes to atomic Nodes and Links, with Ribasim-core operating only on emitted atomic structures.
- MVP introduces a generic Compound Structure protocol with clear lifecycle stages: input definition, structure-level validation, materialization, and integration validation.
- The user-facing API pattern is factory-style structure objects that expose a shared add_to_model lifecycle.
- Contracts use a reusable, type-agnostic schema that expresses required elements, optional elements, defaults, and validation rules.
- Validation follows a two-stage model.
Stage 1 validates the Compound Structure definition and internal computability before materialization.
Stage 2 validates emitted Nodes and model integration through the same existing pathway used for regular node additions.
- Validation rules are composed from reusable rule units and executed as ordered rule sets in MVP.
- Compound Structure metadata uses existing meta columns instead of schema changes.
Required metadata: `meta_compound_structure_id`, `meta_compound_structure_type`.
Optional metadata: `meta_compound_structure_recipe`, `meta_compound_structure_status`.
- Manual edits to generated Nodes are allowed; edited groups are marked detached and then treated as regular Nodes unless rebuilt from recipe.
- Node ID assignment uses existing automatic allocation behavior in MVP.
- Compound Structures are immutable after add_to_model in MVP; in-place synchronization is deferred.
- The built-in contract registry is limited to Ribasim-provided contracts in MVP.
- Reservoir is the first built-in Compound Structure and requires structure identity, geometry anchor, Basin computability inputs, and at least one release connector; control configuration is optional.
- Reservoir materialization emits only existing atomic node types and Links, with no required changes to Ribasim-core simulation logic.

## Testing Decisions
- Good tests assert external behavior and stable contracts, not internal implementation details.
This means testing emitted Node/Link outcomes, validation behavior, metadata semantics, and integration results, while avoiding brittle assertions about internal helper structure.
- Modules to test:
1. Compound Structure protocol lifecycle behavior.
2. Contract schema and required/optional/default handling.
3. Composable rule validation behavior and ordering semantics.
4. Reservoir contract validation for valid and invalid definitions.
5. Reservoir materialization outcomes (emitted atomic types and connectivity).
6. Two-stage validation behavior, including consistency with existing model validation timing.
7. Metadata tagging behavior, including grouping identity and type tags.
8. Provenance detachment behavior after manual edits to generated Nodes.
9. Immutability behavior after add_to_model.
- Prior art for tests:
1. Existing model and node validation tests that verify integration behavior.
2. Existing Ribasim-python tests around Node creation and model assembly.
3. Existing documentation-driven examples that exercise user-facing model building flows.

## Out of Scope
- New atomic node types in Ribasim-core.
- Replacing existing node-level APIs.
- User-defined third-party contract plug-ins in MVP.
- Explicit internal node ID assignment in MVP.
- Managed in-place editing and synchronization for materialized structures.
- Dependency-aware rule-graph execution (beyond ordered rule sets).
- Additional built-in Compound Structure types beyond Reservoir in MVP.

## Further Notes
- Success criteria for MVP:
1. A reservoir can be created through one logical API flow without manual node choreography.
2. Emitted models remain valid under existing validation and simulation pathways.
3. Generated Nodes are discoverable as one grouped structure via metadata.
4. The framework can support a second structure type with minimal architectural change.
- Key risks and mitigations:
1. Risk: Contract rules become brittle.
Mitigation: Keep rules composable and contracts declarative.
2. Risk: Users are confused by post-edit divergence from recipe.
Mitigation: Mark detached status explicitly and document semantics clearly.
3. Risk: Scope creep into non-MVP capabilities.
Mitigation: Keep strict MVP boundaries and track deferred features separately.
- Follow-up clarifications:
1. Minimal control-field set for reservoir variants.
2. Preferred geometry anchor representation across common workflows.
3. How detached status should be surfaced in QGIS and reporting.

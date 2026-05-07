# Ribasim Domain Context

## Glossary

### Compound Structure
A recipe that creates multiple related **Nodes** representing a single logical water system element (e.g., a reservoir, irrigation district). The Compound Structure produces a collection of atomic Nodes (Basin, Outlet, PidControl, etc.) that work together to model the behavior of the real-world facility. Ribasim-core simulates the individual Nodes without needing to understand the Compound Structure; the grouping exists primarily to simplify model construction in Ribasim-python.

Compound Structure membership is tracked using `meta_` columns in the Node table (these are preserved but ignored by the core). Typical metadata includes `meta_compound_structure_id` (groups related nodes) and `meta_compound_structure_type` (e.g., "reservoir").

**Not to be confused with:** Node (an atomic simulation primitive in Ribasim).

### Node
An atomic simulation unit in Ribasim (Basin, Outlet, Pump, TabulatedRatingCurve, etc.). Nodes are connected by Links to form the simulation network. Each Node has a specific type and behavior defined by the core solver.

**Related:** Compound Structure (a recipe that produces multiple Nodes).

### Link
A connection between two Nodes that defines how water flows through the network. Links are directional and instantaneous (no storage).

### Compound Structure Protocol
A generic Ribasim-python interface for creating logical water system objects that expand to multiple atomic Nodes. The preferred API pattern is factory classes (for example, Reservoir) that validate their own parameters and then add themselves to a Model through an add_to_model operation.

The protocol should be reusable across use cases (reservoirs first, then other structures such as land areas with multiple demands) so each structure type follows the same lifecycle: define inputs, validate computability, materialize Nodes and Links, and annotate created nodes with meta_ grouping columns.

Validation follows two stages. Stage 1 checks the Compound Structure itself before materialization (required fields, parameter coherence, internal computability). Stage 2 validates integration with the existing model and individual nodes using the same existing model validation pathway used for regular node additions.

For node identifiers, MVP behavior uses the model's existing automatic node ID allocation. Explicit internal node IDs are out of scope for MVP and treated as a future extension.

Compound Structures are immutable after add_to_model in MVP. If users want changes, they remove and recreate the structure. In-place editing and synchronization of generated nodes are deferred to a future managed-structures feature.

Compound Structure contracts are defined through a reusable, type-agnostic contract schema with required and optional elements. Each structure type (for example reservoir, irrigation district) declares its contract using the same mechanism so rules are easy to extend and refine as new example cases are collected.

For MVP, the Compound Structure contract registry is limited to built-in Ribasim contracts only.

Reservoir MVP contract: requires identity, geometry anchor, Basin computability inputs, and at least one release connector specification; control is optional.

Contract validation uses a composable rule-set pattern. Rules are defined as reusable units and assembled per Compound Structure contract. MVP keeps execution simple (ordered rule sets) while preserving extensibility for future dependency-aware rule graphs.

MVP provenance behavior allows manual edits to generated nodes. When edits affect nodes belonging to a Compound Structure group, the group status should be marked as detached (for example via a meta_compound_structure_status marker). Detached groups are no longer treated as managed recipe-faithful structures and should be handled as regular nodes unless rebuilt.

# Coupling Ribasim & Wflow: Enabling Land Processes and Irrigation

Talking points for the DSD 2026 Ribasim day, 17 November 2026, Delft.
Presenters: Hendrik Kok (H) and Bart de Koning (B). About 10 minutes, followed by Q&A.

Status: draft to structure the story. The slides follow later in the Deltares template.
Items marked **OPEN** still need a decision or data.

## Context of the day

- Our talk is late in the 11:20-13:00 block, after Ribasim-NL and the Meuse conversion talk.
  Only the closing comes after us.
- The audience knows Ribasim from the morning overview. The overview already places Ribasim
  next to Wflow in the Deltares hydrology suite.
- Peter Gijsbers motivates the coupling ("why"). Irrigation demand depends on soil moisture,
  crop and earlier irrigation, so precomputed crop demands can be wrong. He chose Wflow over
  AquaCrop. He covers the roadmap, the TRL (coupling at TRL 3) and HydroMT-Ribasim, and refers
  to our talk for the details. We show "how", so none of those topics come back in our talk.

## Take-home messages

1. **Each model does its part.** Wflow computes overland and subsurface flow and irrigation demand per grid cell.
   Ribasim routes, manages and allocates that water.
2. **Water is conserved.** Everything Wflow hands over arrives in Ribasim.

Framing throughout: this is a proof of concept (one catchment, the Piave), not yet a product.
We only show results that are easy to read and show the coupling working.

## Slide order and timing

| # | Slide | Figure | Who | Time |
|---|---|---|---|---|
| 0 | Bio slides (shown by the host, before the talk) | template | host | – |
| 1 | Title | template | H | 0:15 |
| 2 | Two strengths, one coupled model | `01_combined_strengths` | H | 1:00 |
| 3 | Wflow stand-alone | `02a_concept_wflow` | H | 0:40 |
| 4 | Wflow + Ribasim | `02b_concept_coupled` | H | 0:50 |
| 5 | From grid to network: the Piave | `03_piave_grid_to_network` | H | 1:00 |
| 6 | The river coupling works | `08_outlet_discharge`, `06_river_exchange` | H | 1:00 |
| 7 | Wflow + Ribasim + irrigation | `02c_concept_irrigation` | B | 0:40 |
| 8 | Irrigated cells become UserDemands | `04_irrigation_cells_to_userdemand` | B | 1:00 |
| 9 | One coupled day | `05_coupled_timestep_cycle` | B | 1:10 |
| 10 | The irrigation loop works | `07_irrigation_loop` | B | 1:00 |
| 11 | Take-home messages | text | B | 0:40 |
| 12 | Anything else you'd like to ask? | template | B | Q&A |

Total about 9:15, which leaves some slack for the handover and for slides that run long.
Backup slides (only if asked): water balance details (`b1`), irrigation results per UserDemand
(`b4`), modular Wflow (`b2`), original PR figures (`b3a`, `b3b`). The roadmap (`b5`) is not in
the deck.

## Talking points per slide

### 1. Title (H, 0:15)

- Introduce the talk in one sentence: "We'll show how Wflow and Ribasim run together, first for
  rivers, then for irrigation."
- Say who presents which part: Hendrik the coupling, Bart the irrigation.

### 2. Two strengths, one coupled model (H, 1:00)

- Bridge from Peter: "This morning Peter showed *why* we want this coupling. We'll show *how*
  it works."
- Wflow (left): a distributed hydrological model. The small grid is a piece of the real Piave
  model, with the river cells in blue. Zoom in on one cell: that is the Wflow SBM concept many
  of you know, and every cell runs it.
  - Rain and snow, interception, infiltration and evaporation, and the unsaturated and
    saturated soil stores.
  - Water leaves the cell as overland flow and subsurface flow towards the river.
- Ribasim (right), briefly, since everyone knows it by now: the managed water system, with
  control rules, target levels and allocation by priority.
- Key sentence: "Wflow knows the landscape, Ribasim knows the water system. Together you get
  overland and subsurface flow and irrigation demand from every cell, managed and allocated
  through the network."

### 3. Wflow stand-alone (H, 0:40)

- This is how a Wflow model runs today. Rain falls on the grid, each cell produces overland and
  subsurface flow, and Wflow routes it through its own river cells (kinematic wave).
- Point at the field with crops: Wflow knows the soil and vegetation there, which matters later
  for irrigation.
- What is missing for water managers: Wflow has reservoirs and a simple allocation, but no
  managed network with structures, control rules and priorities between users. That is what
  Ribasim adds.

### 4. Wflow + Ribasim (H, 0:50)

- Same landscape, but the river is now a Ribasim network: Basins connected by
  ManningResistance nodes.
- Wflow keeps everything on the land. Ribasim takes over the river routing.
- Two kinds of inflow:
  - Overland and subsurface flow into a river cell goes into the Basin it lies in.
  - Headwater inflow from areas outside the Ribasim network enters through a FlowBoundary.
- Each model keeps its own state. Each day they only exchange fluxes.

### 5. From grid to network: the Piave (H, 1:00)

- The real case: the Piave catchment in northern Italy. The Wflow model has about 6,600 land
  cells of about 1 km, 661 of them river cells.
- The Ribasim model has 20 Basins and 11 FlowBoundaries, each with an area polygon.
- The coupler links every Wflow river cell to exactly one Ribasim node: 413 cells to Basins,
  248 to FlowBoundaries. Nobody draws that mapping by hand.
- Both models come from HydroMT; no further detail here, Peter covered model building.

### 6. The river coupling works (H, 1:00)

- Left: monthly mean outflow at the Piave outlet over five years (2010–2014), from
  rleander73's validation runs. The coupled model (Ribasim outflow) against stand-alone Wflow
  with the same forcing.
  - The months line up: wet and dry periods arrive at the same time.
  - Over five years the mean outflow is 179 vs 178 m³/s, a difference of 0.6 %.
- Right: daily overland and subsurface flow exchanged in July 2010. What Wflow exports, Ribasim
  receives, up to floating-point precision. **This is take-home message 2.**
- Peaks: the plot shows monthly means, where the volume message is clear. Daily peaks are lower
  in the coupled model; leave that for Q&A (question 8).
- Handover line: "So the river coupling works. Bart will now show what happens when the land
  also needs water back from the river: irrigation."

### 7. Wflow + Ribasim + irrigation (B, 0:40)

- Same picture once more, with one addition: an irrigated field.
- Wflow computes the field's irrigation demand from its soil moisture. That is exactly the
  "why" from Peter's talk.
- Ribasim adds a UserDemand that takes water from the Basin and delivers it back to the field's
  cells.
- The water now flows in both directions between the models: overland and subsurface flow to Ribasim, irrigation back
  to Wflow.

### 8. Irrigated cells become UserDemands (B, 1:00)

- In the Piave, 33 Wflow cells are irrigated, all in the south.
- The coupler groups them per Ribasim Basin and Wflow allocation area. Each group becomes one
  UserDemand that takes water from that Basin.
- Here that gives two UserDemands, #53 and #54.
- The grey cells lie in headwater (FlowBoundary) areas, which have no Basin to take water from.
  They are not coupled yet; mention this only if asked.

### 9. One coupled day (B, 1:10)

- Walk through the loop once, clockwise:
  1. Wflow: the soil dries out, which gives an irrigation demand.
  2. Ribasim allocation shares the available water by priority.
  3. Ribasim physics routes the water and abstracts what is really there.
  4. Wflow puts the realized irrigation on the soil.
  5. Wflow passes the overland and subsurface flow of its river cells to the Basins, and the next day starts.
- The models take turns and only exchange data; each keeps its own state.
- Key sentence: "Wflow says how much water the crops need, Ribasim says how much they get."

### 10. The irrigation loop works (B, 1:00)

- Demand, allocated and realized for UserDemand #53 only. No volume totals or percentages.
- Point at the three lines: the demand comes from Wflow, Ribasim allocates it, and the realized
  supply goes back to Wflow every day.
- The loop closes and the water balance closes.
- Don't discuss the shortage or the model start-up.

### 11. Take-home messages (B, 0:40)

- Each model does its part: Wflow computes overland and subsurface flow and irrigation demand per grid cell; Ribasim
  routes, manages and allocates the water.
- Water is conserved: everything Wflow hands over arrives in Ribasim.
- Close with the proof-of-concept framing: "This runs on a real catchment today, as a proof of
  concept. Thank you."

### 12. Anything else you'd like to ask? (B)

- Both answer questions; Hendrik takes the Wflow and coupling questions, Bart the irrigation and
  allocation questions.

## Likely questions

Answers marked (check) are my understanding and need confirmation by you or Hendrik.

1. **What time step does the coupling use?** One day. Wflow and Ribasim exchange fluxes once per
   day; within the day each model uses its own solver.
2. **Isn't there a delay because the models take turns?** Yes, one day. Wflow hands over the
   overland and subsurface flow of day t at the end of that day, and Ribasim routes it on day t+1.
3. **Why not use Wflow's own water demand and allocation?** Wflow shares the available water
   proportionally: within an allocation area every user gets the same fraction of its demand,
   taken from local river cells first, then the allocation area, then groundwater. There are no
   priorities. Ribasim adds priorities and the managed network with structures and control rules.
4. **What about irrigated cells in headwater areas?** They are not coupled yet. FlowBoundary areas
   have no Basin to take water from.
5. **Does it work for paddy irrigation?** The Piave run only uses non-paddy irrigation (paddy is
   switched off in the Wflow configuration). Paddy has not been tried in the coupling yet.
6. **Is there return flow from irrigation?** Not in this set-up: the return factor of both
   UserDemands is 0, so all abstracted water goes to the Wflow cells. From there, Wflow decides
   what happens to it (crop use, evaporation, overland flow, recharge).
7. **How fast is it?** (check: run time of the Piave run vs stand-alone Wflow)
8. **Why are the coupled peaks lower?** At the outlet the highest daily flow is about 640 m³/s in
   the coupled model and about 1,780 m³/s in stand-alone Wflow, with the same volume. The most
   likely cause, according to rleander73's analysis, is storage in the Ribasim Basins.
   - A chain of Basins works like a series of reservoirs that each flatten the flood wave.
   - The Basin profiles from HydroMT-Ribasim probably use the whole subbasin area rather than
     the river surface, so a large inflow barely raises the level and the outflow.
   - Wflow's kinematic wave moves the peak along with much less flattening.
   - Improving the Basin profiles is ongoing work. Without observed flows we can't say yet
     which model's peaks are closer to reality.
9. **Can I use this in my project?** It is a proof of concept in the Ribasim repository
   (`wflow-coupled/`). River coupling is merged (#3324); irrigation is in review (#3333). It is not
   yet a product.
10. **Does the coupler work with any Wflow model?** Today the coupling script follows Wflow's update
    sequence itself; making Wflow modular should remove that need (backup slide `b2`).

## OPEN

- Bio slides: Hendrik to check his bio.
- Hendrik: check his slides' talking points and the split.
- Q&A answer still marked (check): run time (7).
- rleander73: confirm the explanation of the lower peaks (8).

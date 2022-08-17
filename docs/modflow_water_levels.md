# Assigning MODFLOW water levels

Principally, MODFLOW deals with water levels; Bach deals with water volumes.
The translation from a water volume to a water level should be a relatively
straightforward one: 

```math
\Delta d = \frac{\Delta V}{A}
```

However, the primary complication is that where Bach has **one** volume,
MODFLOW has many levels to adjust. The sum of all these adjustments times
their respective areas should result in the LSW volume change:

```math
\sum_{i=0}^{i=n} \Delta d_i A_i = \Delta V_{LSW}
```

and

```math
h = b + d
```

It should be obvious that there are many ways to distribute this volume change
across the adjustment of every boundary condition of every cell. The main
question is when a volume grows or decreases, how should this volume change be
distributed across the LSW?

The best method to find an answer to this question is to run a hydraulic model,
extract water heights, and compute the total volume. This can then be used as a
lookup table for every cell. These runs can also be used for parametrizing the
volume-discharge lookup tables. In coupling to Bach, we need only find the
appropriate volume and assign the associated water level. For efficiency, this
lookup table can be discretized in a limited number of steps, and in coupling
the level will be interpolated.

!!! note

    Great care is required when parametrizing these volume-level relationships.
    As Bach does not know the properties of the surface water, it can perform
    very limited validation of the volume-level lookup tables. As the total
    volume of the LSW is distributed accross *all* boundary conditions, it
    should be checked that the change of the water column for every boundary
    condition matches the total volume change of the LSW.

In principle, all (stationary!) hydraulic behavior of the LSW can be described
approximately by these lookup tables.

## Examples

To get a feeling for the simplifications and the errors of the approximation,
let's consider three oversimplified hydraulic models:

1. The LSW has a single water level.
2. The LSW has a single water depth.
3. The LSW has a water depth that linearly decreases with bed elevation.

To investigate these cases, we will assume a rectangular profile (constant
wetted area). This allows to create plots of cumulative wetted area versus
height, so that the area between the water level and the bed elevation equals
LSW volume.

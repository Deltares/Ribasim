# Bach

LHM surface water module prototype, based on
[ModelingToolkit.jl](https://mtk.sciml.ai/stable/). Initial focus is on being able to
reproduce the Mozart regional surface water reservoir results. Each component is defined by
a set of symbolic equations, and can be connected to each other. From this a simplified
system of equations is generated automatically. We use solver with adaptive time stepping
from [DifferentialEquations.jl](https://diffeq.sciml.ai/stable/) to get results. 

![Timeseries of
results](https://user-images.githubusercontent.com/4471859/179259333-070dfe18-8f43-4ac4-bb38-013b252e2e4b.png)

![Daily water
balance](https://user-images.githubusercontent.com/4471859/179259174-0caccd4a-c51b-449e-873c-17d48cfc8870.png)

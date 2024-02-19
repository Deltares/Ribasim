using Ribasim
using DataFrames: DataFrame
using SciMLBase: successful_retcode
using Ribasim: NodeID
using JuMP
import HiGHS

model = Model(HiGHS.Optimizer)
model[:flow] = @variable(model, [1:4], base_name = "flow")
flow = model[:flow]
@objective(model, Min, (flow[1] - 0.01002)^2 + (flow[2] - 0.01)^2)
@constraints(model, begin
    flow[3] == flow[4]
    flow[3] == flow[1] + flow[2]
    flow[3] <= 0.004
    flow[4] <= 0.002
end)
print(model)
optimize!(model)
solution_summary(model)

for row in eachrow(flow)
    println(row)
end

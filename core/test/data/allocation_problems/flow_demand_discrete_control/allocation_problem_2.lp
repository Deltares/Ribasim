minimize
obj: 50 flow_(Pump_#2,_Terminal_#3)_
subject to
c1: 1 flow_demand_error_Pump_#2,1,first_ <= 0
c2: 1 flow_demand_error_Pump_#2,1,second_ <= 0
c3: -1 low_storage_factor_Basin_#1_ <= -1
flow_demand_relative_error_constraint_Pump_#2,1_: 1 flow_demand_allocated_Pump_#2,1_ + 0.01587846116148003 flow_demand_error_Pump_#2,1,first_ >= 0.01587846116148003
flow_demand_fairness_error_constraint_Pump_#2,1_: -1 flow_demand_error_Pump_#2,1,first_ + 1 flow_demand_error_Pump_#2,1,second_ + 1 average_flow_unit_error_1_ >= 0
flow_conservation_pump_Pump_#2_: 1 flow_(Basin_#1,_Pump_#2)_ - 1 flow_(Pump_#2,_Terminal_#3)_ = 0
volume_conservation_Basin_#1_: 1 basin_storage_change_Basin_#1_ - 1 flow_(FlowBoundary_#4,_Basin_#1)_ + 1 flow_(Basin_#1,_Pump_#2)_ = 0
flow_demand_allocated_sum_constraint_Pump_#2_: 1 flow_(Basin_#1,_Pump_#2)_ - 1 flow_demand_allocated_Pump_#2,1_ - 1 flow_demand_extra_Pump_#2_ = 0
average_flow_unit_error_constraint_1_: -1 flow_demand_error_Pump_#2,1,first_ + 1 average_flow_unit_error_1_ = 0
Bounds
basin_storage_change_Basin_#1_ >= -0.7748100955648125
0 <= low_storage_factor_Basin_#1_ <= 1
flow_(FlowBoundary_#4,_Basin_#1)_ = 0.03969615290370008
0 <= flow_(Basin_#1,_Pump_#2)_ <= 0.07939230580740016
0 <= flow_(Pump_#2,_Terminal_#3)_ <= 0.07939230580740016
0 <= flow_demand_allocated_Pump_#2,1_ <= 0.01587846116148003
0 <= flow_demand_extra_Pump_#2_ <= 0.07939230580740016
0 <= flow_demand_error_Pump_#2,1,first_ <= 1
0 <= flow_demand_error_Pump_#2,1,second_ <= 1
0 <= average_flow_unit_error_1_ <= 1
End

minimize
obj: 
subject to
flow_demand_relative_error_constraint_Pump_#2,1_: 1 flow_demand_allocated_Pump_#2,1_ + 2 flow_demand_error_Pump_#2,1,first_ >= 2
flow_demand_fairness_error_constraint_Pump_#2,1_: -1 flow_demand_error_Pump_#2,1,first_ + 1 flow_demand_error_Pump_#2,1,second_ + 1 average_flow_unit_error_1_ >= 0
flow_conservation_pump_Pump_#2_: 1 flow_(Basin_#1,_Pump_#2)_ - 1 flow_(Pump_#2,_Terminal_#3)_ = 0
volume_conservation_Basin_#1_: 1 basin_storage_change_Basin_#1_ + 1 low_storage_factor_Basin_#1_ + 1 flow_(Basin_#1,_Pump_#2)_ = 1
pump_constraint_Pump_#2_: -1 low_storage_factor_Basin_#1_ + 1 flow_(Basin_#1,_Pump_#2)_ = 0
flow_demand_allocated_sum_constraint_Pump_#2_: 1 flow_(Basin_#1,_Pump_#2)_ - 1 flow_demand_allocated_Pump_#2,1_ - 1 flow_demand_extra_Pump_#2_ = 0
average_flow_unit_error_constraint_1_: -1 flow_demand_error_Pump_#2,1,first_ + 1 average_flow_unit_error_1_ = 0
Bounds
-0.2 <= basin_storage_change_Basin_#1_ <= 0.8
0 <= low_storage_factor_Basin_#1_ <= 1
0 <= flow_(Basin_#1,_Pump_#2)_ <= 8640000
0 <= flow_(Pump_#2,_Terminal_#3)_ <= 8640000
-8640000 <= flow_demand_allocated_Pump_#2,1_ <= 2
0 <= flow_demand_extra_Pump_#2_ <= 8640000
0 <= flow_demand_error_Pump_#2,1,first_ <= 1
0 <= flow_demand_error_Pump_#2,1,second_ <= 1
0 <= average_flow_unit_error_1_ <= 1
End

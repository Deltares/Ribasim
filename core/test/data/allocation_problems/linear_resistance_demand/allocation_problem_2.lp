minimize
obj: 
subject to
flow_demand_relative_error_constraint_LinearResistance_#2,1_: 1 flow_demand_allocated_LinearResistance_#2,1_ + 2 flow_demand_error_LinearResistance_#2,1,first_ >= 2
c2: -1 flow_demand_error_LinearResistance_#2,1,first_ + 1 flow_demand_error_LinearResistance_#2,1,second_ + 1 average_flow_unit_error_1_ >= 0
flow_conservation_linear_resistance_LinearResistance_#2_: 1 flow_(Basin_#1,_LinearResistance_#2)_ - 1 flow_(LinearResistance_#2,_Basin_#3)_ = 0
volume_conservation_Basin_#1_: 1 basin_storage_change_Basin_#1_ + 1 low_storage_factor_Basin_#1_ + 1 flow_(Basin_#1,_LinearResistance_#2)_ = 1
volume_conservation_Basin_#3_: 1 basin_storage_change_Basin_#3_ + 1 low_storage_factor_Basin_#3_ - 1 flow_(LinearResistance_#2,_Basin_#3)_ = 1
linear_resistance_constraint_LinearResistance_#2_: -0.01 basin_storage_change_Basin_#1_ + 0.01 basin_storage_change_Basin_#3_ + 1 flow_(Basin_#1,_LinearResistance_#2)_ = 1
flow_demand_allocated_sum_constraint_LinearResistance_#2_: 1 flow_(Basin_#1,_LinearResistance_#2)_ - 1 flow_demand_allocated_LinearResistance_#2,1_ - 1 flow_demand_extra_LinearResistance_#2_ = 0
average_flow_unit_error_constraint_1_: -1 flow_demand_error_LinearResistance_#2,1,first_ + 1 average_flow_unit_error_1_ = 0
Bounds
-2 <= basin_storage_change_Basin_#1_ <= 8
-2 <= basin_storage_change_Basin_#3_ <= 8
0 <= low_storage_factor_Basin_#1_ <= 1
0 <= low_storage_factor_Basin_#3_ <= 1
-345.6 <= flow_(Basin_#1,_LinearResistance_#2)_ <= 345.6
-345.6 <= flow_(LinearResistance_#2,_Basin_#3)_ <= 345.6
-86400000 <= flow_demand_allocated_LinearResistance_#2,1_ <= 2
0 <= flow_demand_extra_LinearResistance_#2_ <= 86400000
0 <= flow_demand_error_LinearResistance_#2,1,first_ <= 1
0 <= flow_demand_error_LinearResistance_#2,1,second_ <= 1
0 <= average_flow_unit_error_1_ <= 1
End

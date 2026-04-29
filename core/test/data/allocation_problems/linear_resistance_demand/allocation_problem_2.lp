minimize
obj: 
subject to
flow_demand_relative_error_constraint_LinearResistance_#2,1_: 1 flow_demand_allocated_LinearResistance_#2,1_ + 2 flow_demand_error_LinearResistance_#2,1,first_ >= 2
flow_demand_fairness_error_constraint_LinearResistance_#2,1_: -1 flow_demand_error_LinearResistance_#2,1,first_ + 1 flow_demand_error_LinearResistance_#2,1,second_ + 1 average_flow_unit_error_1_ >= 0
flow_conservation_linear_resistance_LinearResistance_#2_: 1 flow_(Basin_#1,_LinearResistance_#2)_ - 1 flow_(LinearResistance_#2,_Basin_#3)_ = 0
volume_conservation_Basin_#1_: 1 basin_storage_change_Basin_#1_ + 1 low_storage_factor_Basin_#1_ + 1 flow_(Basin_#1,_LinearResistance_#2)_ = 1
volume_conservation_Basin_#3_: 1 basin_storage_change_Basin_#3_ + 1 low_storage_factor_Basin_#3_ - 1 flow_(LinearResistance_#2,_Basin_#3)_ = 1
linear_resistance_constraint_LinearResistance_#2_: -0.01 basin_storage_change_Basin_#1_ + 0.01 basin_storage_change_Basin_#3_ + 1 flow_(Basin_#1,_LinearResistance_#2)_ = 1
flow_demand_allocated_sum_constraint_LinearResistance_#2_: 1 flow_(Basin_#1,_LinearResistance_#2)_ - 1 flow_demand_allocated_LinearResistance_#2,1_ - 1 flow_demand_extra_LinearResistance_#2_ = 0
average_flow_unit_error_constraint_1_: -1 flow_demand_error_LinearResistance_#2,1,first_ + 1 average_flow_unit_error_1_ = 0
Bounds
-1.8181818181818181 <= basin_storage_change_Basin_#1_ <= 7.2727272727272725
-1.8181818181818181 <= basin_storage_change_Basin_#3_ <= 7.2727272727272725
0 <= low_storage_factor_Basin_#1_ <= 1
0 <= low_storage_factor_Basin_#3_ <= 1
-314.1818181818182 <= flow_(Basin_#1,_LinearResistance_#2)_ <= 314.1818181818182
-314.1818181818182 <= flow_(LinearResistance_#2,_Basin_#3)_ <= 314.1818181818182
-7.854545454545455e7 <= flow_demand_allocated_LinearResistance_#2,1_ <= 2
0 <= flow_demand_extra_LinearResistance_#2_ <= 7.854545454545455e7
0 <= flow_demand_error_LinearResistance_#2,1,first_ <= 1
0 <= flow_demand_error_LinearResistance_#2,1,second_ <= 1
0 <= average_flow_unit_error_1_ <= 1
End

minimize
obj: 
subject to
storage_constraint_in_Basin_#1,1_: 1 level_demand_allocated_Basin_#1,1,lower_ + 1 level_demand_error_Basin_#1,1,lower,first_ >= 2000
storage_constraint_out_Basin_#1,1_: -1 level_demand_allocated_Basin_#1,1,upper_ + 1 level_demand_error_Basin_#1,1,upper,first_ >= -3000
level_demand_fairness_error_constraint_Basin_#1,1,upper_: -0.001 level_demand_error_Basin_#1,1,upper,first_ + 1 level_demand_error_Basin_#1,1,upper,second_ + 1 average_storage_unit_error_1,upper_ >= 0
level_demand_fairness_error_constraint_Basin_#1,1,lower_: -0.001 level_demand_error_Basin_#1,1,lower,first_ + 1 level_demand_error_Basin_#1,1,lower,second_ + 1 average_storage_unit_error_1,lower_ >= 0
flow_conservation_outlet_Outlet_#2_: 1 flow_(Basin_#1,_Outlet_#2)_ - 1 flow_(Outlet_#2,_Terminal_#3)_ = 0
volume_conservation_Basin_#1_: 1 basin_storage_change_Basin_#1_ + 1 low_storage_factor_Basin_#1_ + 1 flow_(Basin_#1,_Outlet_#2)_ = 1
storage_change_allocated_sum_constraint_Basin_#1_: 1 basin_storage_change_Basin_#1_ - 1 level_demand_allocated_Basin_#1,0,lower_ + 1 level_demand_allocated_Basin_#1,0,upper_ - 1 level_demand_allocated_Basin_#1,1,lower_ + 1 level_demand_allocated_Basin_#1,1,upper_ = 0
average_storage_unit_error_constraint_1,upper_: -1 level_demand_error_Basin_#1,1,upper,first_ + 1000 average_storage_unit_error_1,upper_ = 0
average_storage_unit_error_constraint_1,lower_: -1 level_demand_error_Basin_#1,1,lower,first_ + 1000 average_storage_unit_error_1,lower_ = 0
Bounds
-1.6666666666666667 <= basin_storage_change_Basin_#1_ <= 6.666666666666667
0 <= low_storage_factor_Basin_#1_ <= 1
0 <= flow_(Basin_#1,_Outlet_#2)_ <= 0.14400000000000002
0 <= flow_(Outlet_#2,_Terminal_#3)_ <= 0.14400000000000002
0 <= level_demand_allocated_Basin_#1,0,lower_ <= 100
0 <= level_demand_allocated_Basin_#1,0,upper_ <= 100
0 <= level_demand_allocated_Basin_#1,1,lower_ <= 100
0 <= level_demand_allocated_Basin_#1,1,upper_ <= 100
level_demand_error_Basin_#1,1,lower,first_ >= 0
level_demand_error_Basin_#1,1,lower,second_ >= 0
level_demand_error_Basin_#1,1,upper,first_ >= 0
level_demand_error_Basin_#1,1,upper,second_ >= 0
average_storage_unit_error_1,lower_ >= 0
average_storage_unit_error_1,upper_ >= 0
End

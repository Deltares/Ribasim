minimize
obj: 1000 flow_(LevelBoundary_#1,_Outlet_#3)_ + 40 flow_(Outlet_#3,_Basin_#4)_
subject to
c1: 1 level_demand_error_Basin_#4,1,lower,first_ + 1 level_demand_error_Basin_#4,1,upper,first_ <= 1.5735272727272729
c2: 1 level_demand_error_Basin_#4,1,lower,second_ + 1 level_demand_error_Basin_#4,1,upper,second_ <= 0
c3: -1 low_storage_factor_Basin_#4_ <= -1
storage_constraint_lower_Basin_#4,1_: 1 basin_storage_change_Basin_#4_ + 1 level_demand_error_Basin_#4,1,lower,first_ >= 1.6363636363636365
storage_constraint_upper_Basin_#4,1_: -1 basin_storage_change_Basin_#4_ + 1 level_demand_error_Basin_#4,1,upper,first_ >= -1.6363636363636365
level_demand_fairness_error_constraint_Basin_#4,1,lower_: -1 level_demand_error_Basin_#4,1,lower,first_ + 1 level_demand_error_Basin_#4,1,lower,second_ + 1 average_storage_unit_error_1,lower_ >= 0
level_demand_fairness_error_constraint_Basin_#4,1,upper_: -1 level_demand_error_Basin_#4,1,upper,first_ + 1 level_demand_error_Basin_#4,1,upper,second_ + 1 average_storage_unit_error_1,upper_ >= 0
flow_conservation_outlet_Outlet_#3_: 1 flow_(LevelBoundary_#1,_Outlet_#3)_ - 1 flow_(Outlet_#3,_Basin_#4)_ = 0
volume_conservation_Basin_#4_: 1 basin_storage_change_Basin_#4_ - 1 flow_(Outlet_#3,_Basin_#4)_ = 0
average_storage_unit_error_constraint_1,upper_: -1 level_demand_error_Basin_#4,1,upper,first_ + 1 average_storage_unit_error_1,upper_ = 0
average_storage_unit_error_constraint_1,lower_: -1 level_demand_error_Basin_#4,1,lower,first_ + 1 average_storage_unit_error_1,lower_ = 0
Bounds
-0.18181818181818182 <= basin_storage_change_Basin_#4_ <= 3.4545454545454546
0 <= low_storage_factor_Basin_#4_ <= 1
0 <= flow_(LevelBoundary_#1,_Outlet_#3)_ <= 0.06283636363636365
0 <= flow_(Outlet_#3,_Basin_#4)_ <= 0.06283636363636365
boundary_level_LevelBoundary_#1_ = 1
level_demand_error_Basin_#4,1,lower,first_ >= 0
level_demand_error_Basin_#4,1,lower,second_ >= 0
level_demand_error_Basin_#4,1,upper,first_ >= 0
level_demand_error_Basin_#4,1,upper,second_ >= 0
average_storage_unit_error_1,lower_ >= 0
average_storage_unit_error_1,upper_ >= 0
End

minimize
obj: 40 flow_(Outlet_#3,_Terminal_#6)_ + 40 flow_(Outlet_#4,_Basin_#1)_ + 1000 flow_(LevelBoundary_#5,_Outlet_#4)_
subject to
c1: 1 level_demand_error_Basin_#1,1,lower,first_ + 1 level_demand_error_Basin_#1,1,upper,first_ <= 0.027324952380952384
c2: 1 level_demand_error_Basin_#1,1,lower,second_ + 1 level_demand_error_Basin_#1,1,upper,second_ <= 0
c3: -1 low_storage_factor_Basin_#1_ <= -1
storage_constraint_lower_Basin_#1,1_: 1 basin_storage_change_Basin_#1_ + 1 level_demand_error_Basin_#1,1,lower,first_ >= -0.02666666666666667
storage_constraint_upper_Basin_#1,1_: -1 basin_storage_change_Basin_#1_ + 1 level_demand_error_Basin_#1,1,upper,first_ >= 0.02666666666666667
level_demand_fairness_error_constraint_Basin_#1,1,lower_: -1 level_demand_error_Basin_#1,1,lower,first_ + 1 level_demand_error_Basin_#1,1,lower,second_ + 1 average_storage_unit_error_1,lower_ >= 0
level_demand_fairness_error_constraint_Basin_#1,1,upper_: -1 level_demand_error_Basin_#1,1,upper,first_ + 1 level_demand_error_Basin_#1,1,upper,second_ + 1 average_storage_unit_error_1,upper_ >= 0
flow_conservation_outlet_Outlet_#3_: 1 flow_(Basin_#1,_Outlet_#3)_ - 1 flow_(Outlet_#3,_Terminal_#6)_ = 0
flow_conservation_outlet_Outlet_#4_: 1 flow_(LevelBoundary_#5,_Outlet_#4)_ - 1 flow_(Outlet_#4,_Basin_#1)_ = 0
volume_conservation_Basin_#1_: 1 basin_storage_change_Basin_#1_ - 1 flow_(Outlet_#4,_Basin_#1)_ + 1 flow_(Basin_#1,_Outlet_#3)_ = 0.0006582857142857143
average_storage_unit_error_constraint_1,upper_: -1 level_demand_error_Basin_#1,1,upper,first_ + 1 average_storage_unit_error_1,upper_ = 0
average_storage_unit_error_constraint_1,lower_: -1 level_demand_error_Basin_#1,1,lower,first_ + 1 average_storage_unit_error_1,lower_ = 0
outlet_constraint_Outlet_#3_: 1 flow_(Basin_#1,_Outlet_#3)_ = 0
outlet_constraint_Outlet_#4_: 1 flow_(LevelBoundary_#5,_Outlet_#4)_ = 0
Bounds
-0.8571428571428571 <= basin_storage_change_Basin_#1_ <= 1.4285714285714286
0 <= low_storage_factor_Basin_#1_ <= 1
flow_(LevelBoundary_#5,_Outlet_#4)_ = 0
flow_(Outlet_#4,_Basin_#1)_ = 0
0 <= flow_(Basin_#1,_Outlet_#3)_ <= 0.00032914285714285717
0 <= flow_(Outlet_#3,_Terminal_#6)_ <= 0.00032914285714285717
boundary_level_LevelBoundary_#5_ = 1
level_demand_error_Basin_#1,1,lower,first_ >= 0
level_demand_error_Basin_#1,1,lower,second_ >= 0
level_demand_error_Basin_#1,1,upper,first_ >= 0
level_demand_error_Basin_#1,1,upper,second_ >= 0
average_storage_unit_error_1,lower_ >= 0
average_storage_unit_error_1,upper_ >= 0
End

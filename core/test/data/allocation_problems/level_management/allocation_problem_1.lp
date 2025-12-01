minimize
obj: 
subject to
storage_constraint_lower_Basin_#4,1_: 1 basin_storage_change_Basin_#4_ + 1 level_demand_error_Basin_#4,1,lower,first_ >= -250
storage_constraint_upper_Basin_#4,1_: -1 basin_storage_change_Basin_#4_ + 1 level_demand_error_Basin_#4,1,upper,first_ >= -750
level_demand_fairness_error_constraint_Basin_#4,1,lower_: -0.001 level_demand_error_Basin_#4,1,lower,first_ + 1 level_demand_error_Basin_#4,1,lower,second_ + 1 average_storage_unit_error_1,lower_ >= 0
level_demand_fairness_error_constraint_Basin_#4,1,upper_: -0.001 level_demand_error_Basin_#4,1,upper,first_ + 1 level_demand_error_Basin_#4,1,upper,second_ + 1 average_storage_unit_error_1,upper_ >= 0
flow_conservation_pump_Pump_#5_: 1 flow_(Basin_#4,_Pump_#5)_ - 1 flow_(Pump_#5,_Terminal_#20)_ = 0
flow_conservation_outlet_Outlet_#13_: 1 flow_(LevelBoundary_#11,_Outlet_#13)_ - 1 flow_(Outlet_#13,_Basin_#4)_ = 0
volume_conservation_Basin_#4_: 1 basin_storage_change_Basin_#4_ + 1 low_storage_factor_Basin_#4_ - 1 flow_(Outlet_#13,_Basin_#4)_ + 1 flow_(Basin_#4,_Pump_#5)_ = 1
average_storage_unit_error_constraint_1,upper_: -1 level_demand_error_Basin_#4,1,upper,first_ + 1000 average_storage_unit_error_1,upper_ = 0
average_storage_unit_error_constraint_1,lower_: -1 level_demand_error_Basin_#4,1,lower,first_ + 1000 average_storage_unit_error_1,lower_ = 0
Bounds
-0.00030769230508875746 <= basin_storage_change_Basin_#4_ <= 0.0012307692203550298
0 <= low_storage_factor_Basin_#4_ <= 1
0 <= flow_(LevelBoundary_#11,_Outlet_#13)_ <= 0.13292307579834323
0 <= flow_(Outlet_#13,_Basin_#4)_ <= 0.13292307579834323
0 <= flow_(Basin_#4,_Pump_#5)_ <= 0.26584615159668645
0 <= flow_(Pump_#5,_Terminal_#20)_ <= 0.26584615159668645
boundary_level_LevelBoundary_#11_ = 0
level_demand_error_Basin_#4,1,lower,first_ >= 0
level_demand_error_Basin_#4,1,lower,second_ >= 0
level_demand_error_Basin_#4,1,upper,first_ >= 0
level_demand_error_Basin_#4,1,upper,second_ >= 0
average_storage_unit_error_1,lower_ >= 0
average_storage_unit_error_1,upper_ >= 0
End

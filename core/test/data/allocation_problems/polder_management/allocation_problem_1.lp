minimize
obj: 
subject to
flow_demand_relative_error_constraint_Pump_#7,2_: 1 flow_demand_allocated_Pump_#7,2_ + 2 flow_demand_error_Pump_#7,2,first_ >= 2
storage_constraint_lower_Basin_#3,1_: 1 basin_storage_change_Basin_#3_ + 1 level_demand_error_Basin_#3,1,lower,first_ >= -250
storage_constraint_lower_Basin_#4,1_: 1 basin_storage_change_Basin_#4_ + 1 level_demand_error_Basin_#4,1,lower,first_ >= -250
storage_constraint_lower_Basin_#6,1_: 1 basin_storage_change_Basin_#6_ + 1 level_demand_error_Basin_#6,1,lower,first_ >= -250
storage_constraint_upper_Basin_#3,1_: -1 basin_storage_change_Basin_#3_ + 1 level_demand_error_Basin_#3,1,upper,first_ >= -750
storage_constraint_upper_Basin_#4,1_: -1 basin_storage_change_Basin_#4_ + 1 level_demand_error_Basin_#4,1,upper,first_ >= -750
storage_constraint_upper_Basin_#6,1_: -1 basin_storage_change_Basin_#6_ + 1 level_demand_error_Basin_#6,1,upper,first_ >= -750
flow_demand_fairness_error_constraint_Pump_#7,2_: -1 flow_demand_error_Pump_#7,2,first_ + 1 flow_demand_error_Pump_#7,2,second_ + 1 average_flow_unit_error_2_ >= 0
level_demand_fairness_error_constraint_Basin_#3,1,lower_: -0.001 level_demand_error_Basin_#3,1,lower,first_ + 1 level_demand_error_Basin_#3,1,lower,second_ + 1 average_storage_unit_error_1,lower_ >= 0
level_demand_fairness_error_constraint_Basin_#3,1,upper_: -0.001 level_demand_error_Basin_#3,1,upper,first_ + 1 level_demand_error_Basin_#3,1,upper,second_ + 1 average_storage_unit_error_1,upper_ >= 0
level_demand_fairness_error_constraint_Basin_#4,1,lower_: -0.001 level_demand_error_Basin_#4,1,lower,first_ + 1 level_demand_error_Basin_#4,1,lower,second_ + 1 average_storage_unit_error_1,lower_ >= 0
level_demand_fairness_error_constraint_Basin_#4,1,upper_: -0.001 level_demand_error_Basin_#4,1,upper,first_ + 1 level_demand_error_Basin_#4,1,upper,second_ + 1 average_storage_unit_error_1,upper_ >= 0
level_demand_fairness_error_constraint_Basin_#6,1,lower_: -0.001 level_demand_error_Basin_#6,1,lower,first_ + 1 level_demand_error_Basin_#6,1,lower,second_ + 1 average_storage_unit_error_1,lower_ >= 0
level_demand_fairness_error_constraint_Basin_#6,1,upper_: -0.001 level_demand_error_Basin_#6,1,upper,first_ + 1 level_demand_error_Basin_#6,1,upper,second_ + 1 average_storage_unit_error_1,upper_ >= 0
flow_conservation_pump_Pump_#7_: 1 flow_(Basin_#6,_Pump_#7)_ - 1 flow_(Pump_#7,_Basin_#9)_ = 0
flow_conservation_outlet_Outlet_#5_: 1 flow_(Basin_#3,_Outlet_#5)_ - 1 flow_(Outlet_#5,_Basin_#4)_ = 0
flow_conservation_outlet_Outlet_#10_: 1 flow_(Basin_#9,_Outlet_#10)_ - 1 flow_(Outlet_#10,_LevelBoundary_#17)_ = 0
flow_conservation_outlet_Outlet_#12_: 1 flow_(LevelBoundary_#11,_Outlet_#12)_ - 1 flow_(Outlet_#12,_Basin_#3)_ = 0
flow_conservation_outlet_Outlet_#13_: 1 flow_(Basin_#4,_Outlet_#13)_ - 1 flow_(Outlet_#13,_Basin_#6)_ = 0
flow_conservation_manning_resistance_ManningResistance_#2_: -1 flow_(ManningResistance_#2,_Basin_#9)_ + 1 flow_(Basin_#3,_ManningResistance_#2)_ = 0
volume_conservation_Basin_#3_: 1 basin_storage_change_Basin_#3_ + 1 low_storage_factor_Basin_#3_ + 1 flow_(Basin_#3,_Outlet_#5)_ + 1 flow_(Basin_#3,_ManningResistance_#2)_ - 1 flow_(Outlet_#12,_Basin_#3)_ = 1
volume_conservation_Basin_#4_: 1 basin_storage_change_Basin_#4_ + 1 low_storage_factor_Basin_#4_ - 1 flow_(Outlet_#5,_Basin_#4)_ + 1 flow_(Basin_#4,_Outlet_#13)_ = 1
volume_conservation_Basin_#6_: 1 basin_storage_change_Basin_#6_ + 1 low_storage_factor_Basin_#6_ - 1 flow_(Outlet_#13,_Basin_#6)_ + 1 flow_(Basin_#6,_Pump_#7)_ = 1
volume_conservation_Basin_#9_: 1 basin_storage_change_Basin_#9_ + 1 low_storage_factor_Basin_#9_ - 1 flow_(ManningResistance_#2,_Basin_#9)_ - 1 flow_(Pump_#7,_Basin_#9)_ + 1 flow_(Basin_#9,_Outlet_#10)_ = 1
manning_resistance_constraint_ManningResistance_#2_: -0.01 basin_storage_change_Basin_#3_ + 0.01 basin_storage_change_Basin_#9_ + 1 flow_(Basin_#3,_ManningResistance_#2)_ = 1
flow_demand_allocated_sum_constraint_Pump_#7_: 1 flow_(Basin_#6,_Pump_#7)_ - 1 flow_demand_allocated_Pump_#7,2_ - 1 flow_demand_extra_Pump_#7_ = 0
average_flow_unit_error_constraint_2_: -1 flow_demand_error_Pump_#7,2,first_ + 1 average_flow_unit_error_2_ = 0
average_storage_unit_error_constraint_1,upper_: -1 level_demand_error_Basin_#3,1,upper,first_ - 1 level_demand_error_Basin_#4,1,upper,first_ - 1 level_demand_error_Basin_#6,1,upper,first_ + 1000 average_storage_unit_error_1,upper_ = 0
average_storage_unit_error_constraint_1,lower_: -1 level_demand_error_Basin_#3,1,lower,first_ - 1 level_demand_error_Basin_#4,1,lower,first_ - 1 level_demand_error_Basin_#6,1,lower,first_ + 1000 average_storage_unit_error_1,lower_ = 0
Bounds
-0.00013793103395957193 <= basin_storage_change_Basin_#3_ <= 0.0005517241358382877
-0.00013793103395957193 <= basin_storage_change_Basin_#4_ <= 0.0005517241358382877
-0.00013793103395957193 <= basin_storage_change_Basin_#6_ <= 0.0005517241358382877
-0.00013793103395957193 <= basin_storage_change_Basin_#9_ <= 0.0005517241358382877
0 <= low_storage_factor_Basin_#3_ <= 1
0 <= low_storage_factor_Basin_#4_ <= 1
0 <= low_storage_factor_Basin_#6_ <= 1
0 <= low_storage_factor_Basin_#9_ <= 1
-5958.6206670535075 <= flow_(ManningResistance_#2,_Basin_#9)_ <= 5958.6206670535075
0 <= flow_(Basin_#3,_Outlet_#5)_ <= 0.05958620667053508
-5958.6206670535075 <= flow_(Basin_#3,_ManningResistance_#2)_ <= 5958.6206670535075
0 <= flow_(Outlet_#5,_Basin_#4)_ <= 0.05958620667053508
0 <= flow_(Basin_#4,_Outlet_#13)_ <= 0.05958620667053508
0 <= flow_(Outlet_#13,_Basin_#6)_ <= 0.05958620667053508
0 <= flow_(Basin_#6,_Pump_#7)_ <= 0.23834482668214033
0 <= flow_(Pump_#7,_Basin_#9)_ <= 0.23834482668214033
0 <= flow_(Basin_#9,_Outlet_#10)_ <= 0.11917241334107016
0 <= flow_(LevelBoundary_#11,_Outlet_#12)_ <= 0.11917241334107016
0 <= flow_(Outlet_#12,_Basin_#3)_ <= 0.11917241334107016
0 <= flow_(Outlet_#10,_LevelBoundary_#17)_ <= 0.11917241334107016
boundary_level_LevelBoundary_#11_ = 0
boundary_level_LevelBoundary_#17_ = 0
-5958.6206670535075 <= flow_demand_allocated_Pump_#7,2_ <= 2
0 <= flow_demand_extra_Pump_#7_ <= 5958.6206670535075
0 <= flow_demand_error_Pump_#7,2,first_ <= 1
0 <= flow_demand_error_Pump_#7,2,second_ <= 1
level_demand_error_Basin_#3,1,lower,first_ >= 0
level_demand_error_Basin_#3,1,lower,second_ >= 0
level_demand_error_Basin_#3,1,upper,first_ >= 0
level_demand_error_Basin_#3,1,upper,second_ >= 0
level_demand_error_Basin_#4,1,lower,first_ >= 0
level_demand_error_Basin_#4,1,lower,second_ >= 0
level_demand_error_Basin_#4,1,upper,first_ >= 0
level_demand_error_Basin_#4,1,upper,second_ >= 0
level_demand_error_Basin_#6,1,lower,first_ >= 0
level_demand_error_Basin_#6,1,lower,second_ >= 0
level_demand_error_Basin_#6,1,upper,first_ >= 0
level_demand_error_Basin_#6,1,upper,second_ >= 0
0 <= average_flow_unit_error_2_ <= 1
average_storage_unit_error_1,lower_ >= 0
average_storage_unit_error_1,upper_ >= 0
End

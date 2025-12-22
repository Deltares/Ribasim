minimize
obj: 
subject to
user_demand_relative_error_constraint_UserDemand_#1,2_: 1 user_demand_allocated_UserDemand_#1,2_ + 2 user_demand_error_UserDemand_#1,2,first_ >= 2
storage_constraint_lower_Basin_#2,1_: 1 basin_storage_change_Basin_#2_ + 1 level_demand_error_Basin_#2,1,lower,first_ >= -250
storage_constraint_upper_Basin_#2,1_: -1 basin_storage_change_Basin_#2_ + 1 level_demand_error_Basin_#2,1,upper,first_ >= -750
user_demand_fairness_error_constraint_UserDemand_#1,2_: -1 user_demand_error_UserDemand_#1,2,first_ + 1 user_demand_error_UserDemand_#1,2,second_ + 1 average_flow_unit_error_2_ >= 0
level_demand_fairness_error_constraint_Basin_#2,1,lower_: -0.001 level_demand_error_Basin_#2,1,lower,first_ + 1 level_demand_error_Basin_#2,1,lower,second_ + 1 average_storage_unit_error_1,lower_ >= 0
level_demand_fairness_error_constraint_Basin_#2,1,upper_: -0.001 level_demand_error_Basin_#2,1,upper,first_ + 1 level_demand_error_Basin_#2,1,upper,second_ + 1 average_storage_unit_error_1,upper_ >= 0
flow_conservation_pump_Pump_#4_: -1 flow_(Pump_#4,_Basin_#2)_ + 1 flow_(LevelBoundary_#7,_Pump_#4)_ = 0
flow_conservation_pump_Pump_#5_: -1 flow_(Pump_#5,_Basin_#2)_ + 1 flow_(LevelBoundary_#8,_Pump_#5)_ = 0
flow_conservation_pump_Pump_#6_: -1 flow_(Pump_#6,_Basin_#2)_ + 1 flow_(LevelBoundary_#9,_Pump_#6)_ = 0
volume_conservation_Basin_#2_: 1 basin_storage_change_Basin_#2_ + 1 low_storage_factor_Basin_#2_ - 1 flow_(Pump_#4,_Basin_#2)_ - 1 flow_(Pump_#5,_Basin_#2)_ - 1 flow_(Pump_#6,_Basin_#2)_ + 1 flow_(Basin_#2,_UserDemand_#1)_ - 1 flow_(UserDemand_#1,_Basin_#2)_ = 1
user_demand_allocated_sum_constraint_UserDemand_#1_: 1 flow_(Basin_#2,_UserDemand_#1)_ - 1 user_demand_allocated_UserDemand_#1,2_ = 0
user_demand_return_flow_UserDemand_#1_: -0.5 flow_(Basin_#2,_UserDemand_#1)_ + 1 flow_(UserDemand_#1,_Basin_#2)_ = 0
average_flow_unit_error_constraint_2_: -1 user_demand_error_UserDemand_#1,2,first_ + 1 average_flow_unit_error_2_ = 0
average_storage_unit_error_constraint_1,upper_: -1 level_demand_error_Basin_#2,1,upper,first_ + 1000 average_storage_unit_error_1,upper_ = 0
average_storage_unit_error_constraint_1,lower_: -1 level_demand_error_Basin_#2,1,lower,first_ + 1000 average_storage_unit_error_1,lower_ = 0
Bounds
-0.2 <= basin_storage_change_Basin_#2_ <= 0.8
0 <= low_storage_factor_Basin_#2_ <= 1
0 <= flow_(Pump_#4,_Basin_#2)_ <= 17.28
0 <= flow_(LevelBoundary_#7,_Pump_#4)_ <= 17.28
0 <= flow_(Pump_#5,_Basin_#2)_ <= 17.28
0 <= flow_(LevelBoundary_#8,_Pump_#5)_ <= 17.28
0 <= flow_(Pump_#6,_Basin_#2)_ <= 17.28
0 <= flow_(LevelBoundary_#9,_Pump_#6)_ <= 17.28
0 <= flow_(Basin_#2,_UserDemand_#1)_ <= 8640000
0 <= flow_(UserDemand_#1,_Basin_#2)_ <= 8640000
boundary_level_LevelBoundary_#7_ = 0
boundary_level_LevelBoundary_#8_ = 0
boundary_level_LevelBoundary_#9_ = 0
0 <= user_demand_allocated_UserDemand_#1,2_ <= 2
0 <= user_demand_error_UserDemand_#1,2,first_ <= 1
0 <= user_demand_error_UserDemand_#1,2,second_ <= 1
level_demand_error_Basin_#2,1,lower,first_ >= 0
level_demand_error_Basin_#2,1,lower,second_ >= 0
level_demand_error_Basin_#2,1,upper,first_ >= 0
level_demand_error_Basin_#2,1,upper,second_ >= 0
0 <= average_flow_unit_error_2_ <= 1
average_storage_unit_error_1,lower_ >= 0
average_storage_unit_error_1,upper_ >= 0
End

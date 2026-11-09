minimize
obj: 1 flow_change_Pump_#4_ + 1 flow_change_Pump_#5_ + 1 flow_change_Pump_#6_
subject to
c1: -1 low_storage_factor_Basin_#2_ <= -1
c2: 1 level_demand_error_Basin_#2,1,lower,first_ + 1 level_demand_error_Basin_#2,1,upper,first_ <= 0
c3: 1 level_demand_error_Basin_#2,1,lower,second_ + 1 level_demand_error_Basin_#2,1,upper,second_ <= 0
c4: 50 flow_(Pump_#4,_Basin_#2)_ + 3009 flow_(LevelBoundary_#7,_Pump_#4)_ + 50 flow_(Pump_#5,_Basin_#2)_ + 3010 flow_(LevelBoundary_#8,_Pump_#5)_ + 50 flow_(Pump_#6,_Basin_#2)_ + 3011 flow_(LevelBoundary_#9,_Pump_#6)_ + 100000 flow_(Basin_#2,_UserDemand_#1)_ <= 0
user_demand_relative_error_constraint_UserDemand_#1,2_: 1 user_demand_allocated_UserDemand_#1,2_ >= 0
storage_constraint_lower_Basin_#2,1_: 1 basin_storage_change_Basin_#2_ + 1 level_demand_error_Basin_#2,1,lower,first_ >= 0
storage_constraint_upper_Basin_#2,1_: -1 basin_storage_change_Basin_#2_ + 1 level_demand_error_Basin_#2,1,upper,first_ >= 0
user_demand_fairness_error_constraint_UserDemand_#1,2_: -1 user_demand_error_UserDemand_#1,2,first_ + 1 user_demand_error_UserDemand_#1,2,second_ + 1 average_flow_unit_error_2_ >= 0
level_demand_fairness_error_constraint_Basin_#2,1,lower_: -1 level_demand_error_Basin_#2,1,lower,first_ + 1 level_demand_error_Basin_#2,1,lower,second_ + 1 average_storage_unit_error_1,lower_ >= 0
level_demand_fairness_error_constraint_Basin_#2,1,upper_: -1 level_demand_error_Basin_#2,1,upper,first_ + 1 level_demand_error_Basin_#2,1,upper,second_ + 1 average_storage_unit_error_1,upper_ >= 0
flow_change_constraint_Pump_#4,_1_: 1 flow_(LevelBoundary_#7,_Pump_#4)_ + 1 flow_change_Pump_#4_ >= 0
flow_change_constraint_Pump_#5,_1_: 1 flow_(LevelBoundary_#8,_Pump_#5)_ + 1 flow_change_Pump_#5_ >= 0
flow_change_constraint_Pump_#6,_1_: 1 flow_(LevelBoundary_#9,_Pump_#6)_ + 1 flow_change_Pump_#6_ >= 0
flow_change_constraint_Pump_#4,1_: -1 flow_(LevelBoundary_#7,_Pump_#4)_ + 1 flow_change_Pump_#4_ >= 0
flow_change_constraint_Pump_#5,1_: -1 flow_(LevelBoundary_#8,_Pump_#5)_ + 1 flow_change_Pump_#5_ >= 0
flow_change_constraint_Pump_#6,1_: -1 flow_(LevelBoundary_#9,_Pump_#6)_ + 1 flow_change_Pump_#6_ >= 0
flow_conservation_pump_Pump_#4_: -1 flow_(Pump_#4,_Basin_#2)_ + 1 flow_(LevelBoundary_#7,_Pump_#4)_ = 0
flow_conservation_pump_Pump_#5_: -1 flow_(Pump_#5,_Basin_#2)_ + 1 flow_(LevelBoundary_#8,_Pump_#5)_ = 0
flow_conservation_pump_Pump_#6_: -1 flow_(Pump_#6,_Basin_#2)_ + 1 flow_(LevelBoundary_#9,_Pump_#6)_ = 0
volume_conservation_Basin_#2_: 1 basin_storage_change_Basin_#2_ - 1 flow_(Pump_#4,_Basin_#2)_ - 1 flow_(Pump_#5,_Basin_#2)_ - 1 flow_(Pump_#6,_Basin_#2)_ + 1 flow_(Basin_#2,_UserDemand_#1)_ - 1 flow_(UserDemand_#1,_Basin_#2)_ = 0
user_demand_allocated_sum_constraint_UserDemand_#1_: 1 flow_(Basin_#2,_UserDemand_#1)_ - 1 user_demand_allocated_UserDemand_#1,2_ = 0
user_demand_return_flow_UserDemand_#1_: 1 flow_(UserDemand_#1,_Basin_#2)_ = 0
average_flow_unit_error_constraint_2_: 1 average_flow_unit_error_2_ = 0
average_storage_unit_error_constraint_1,upper_: -1 level_demand_error_Basin_#2,1,upper,first_ + 1 average_storage_unit_error_1,upper_ = 0
average_storage_unit_error_constraint_1,lower_: -1 level_demand_error_Basin_#2,1,lower,first_ + 1 average_storage_unit_error_1,lower_ = 0
Bounds
basin_storage_change_Basin_#2_ >= -0.5714285714285714
0 <= low_storage_factor_Basin_#2_ <= 1
0 <= flow_(Pump_#4,_Basin_#2)_ <= 9.257142857142858
0 <= flow_(LevelBoundary_#7,_Pump_#4)_ <= 9.257142857142858
0 <= flow_(Pump_#5,_Basin_#2)_ <= 9.257142857142858
0 <= flow_(LevelBoundary_#8,_Pump_#5)_ <= 9.257142857142858
0 <= flow_(Pump_#6,_Basin_#2)_ <= 9.257142857142858
0 <= flow_(LevelBoundary_#9,_Pump_#6)_ <= 9.257142857142858
flow_(Basin_#2,_UserDemand_#1)_ = 0
flow_(UserDemand_#1,_Basin_#2)_ = 0
user_demand_allocated_UserDemand_#1,2_ = 0
0 <= user_demand_error_UserDemand_#1,2,first_ <= 1
0 <= user_demand_error_UserDemand_#1,2,second_ <= 1
level_demand_error_Basin_#2,1,lower,first_ >= 0
level_demand_error_Basin_#2,1,lower,second_ >= 0
level_demand_error_Basin_#2,1,upper,first_ >= 0
level_demand_error_Basin_#2,1,upper,second_ >= 0
0 <= average_flow_unit_error_2_ <= 1
average_storage_unit_error_1,lower_ >= 0
average_storage_unit_error_1,upper_ >= 0
flow_change_Pump_#4_ >= 0
flow_change_Pump_#5_ >= 0
flow_change_Pump_#6_ >= 0
End

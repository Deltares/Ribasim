minimize
obj: 
subject to
user_demand_relative_error_constraint_UserDemand_#6,1_: 1 user_demand_allocated_UserDemand_#6,1_ + 2 user_demand_error_UserDemand_#6,1,first_ >= 2
user_demand_relative_error_constraint_UserDemand_#7,1_: 1 user_demand_allocated_UserDemand_#7,1_ + 2 user_demand_error_UserDemand_#7,1,first_ >= 2
user_demand_relative_error_constraint_UserDemand_#8,1_: 1 user_demand_allocated_UserDemand_#8,1_ + 2 user_demand_error_UserDemand_#8,1,first_ >= 2
user_demand_relative_error_constraint_UserDemand_#9,1_: 1 user_demand_allocated_UserDemand_#9,1_ + 2 user_demand_error_UserDemand_#9,1,first_ >= 2
user_demand_fairness_error_constraint_UserDemand_#6,1_: -1 user_demand_error_UserDemand_#6,1,first_ + 1 user_demand_error_UserDemand_#6,1,second_ + 1 average_flow_unit_error_1_ >= 0
user_demand_fairness_error_constraint_UserDemand_#7,1_: -1 user_demand_error_UserDemand_#7,1,first_ + 1 user_demand_error_UserDemand_#7,1,second_ + 1 average_flow_unit_error_1_ >= 0
user_demand_fairness_error_constraint_UserDemand_#8,1_: -1 user_demand_error_UserDemand_#8,1,first_ + 1 user_demand_error_UserDemand_#8,1,second_ + 1 average_flow_unit_error_1_ >= 0
user_demand_fairness_error_constraint_UserDemand_#9,1_: -1 user_demand_error_UserDemand_#9,1,first_ + 1 user_demand_error_UserDemand_#9,1,second_ + 1 average_flow_unit_error_1_ >= 0
flow_conservation_pump_Pump_#2_: 1 flow_(LevelBoundary_#1,_Pump_#2)_ - 1 flow_(Pump_#2,_Basin_#3)_ = 0
flow_conservation_linear_resistance_LinearResistance_#4_: 1 flow_(Basin_#3,_LinearResistance_#4)_ - 1 flow_(LinearResistance_#4,_Basin_#5)_ = 0
volume_conservation_Basin_#3_: 1 basin_storage_change_Basin_#3_ + 1 low_storage_factor_Basin_#3_ - 1 flow_(Pump_#2,_Basin_#3)_ + 1 flow_(Basin_#3,_LinearResistance_#4)_ + 1 flow_(Basin_#3,_UserDemand_#6)_ + 1 flow_(Basin_#3,_UserDemand_#7)_ - 1 flow_(UserDemand_#6,_Basin_#3)_ - 1 flow_(UserDemand_#7,_Basin_#3)_ = 1
volume_conservation_Basin_#5_: 1 basin_storage_change_Basin_#5_ + 1 low_storage_factor_Basin_#5_ - 1 flow_(LinearResistance_#4,_Basin_#5)_ + 1 flow_(Basin_#5,_UserDemand_#8)_ + 1 flow_(Basin_#5,_UserDemand_#9)_ - 1 flow_(UserDemand_#8,_Basin_#5)_ - 1 flow_(UserDemand_#9,_Basin_#5)_ = 1
linear_resistance_constraint_LinearResistance_#4_: -0.01 basin_storage_change_Basin_#3_ + 0.01 basin_storage_change_Basin_#5_ + 1 flow_(Basin_#3,_LinearResistance_#4)_ = 1
pump_constraint_Pump_#2_: 1 flow_(LevelBoundary_#1,_Pump_#2)_ = 1
c7: 1 flow_(Basin_#3,_UserDemand_#6)_ - 1 user_demand_allocated_UserDemand_#6,1_ = 0
c8: 1 flow_(Basin_#3,_UserDemand_#7)_ - 1 user_demand_allocated_UserDemand_#7,1_ = 0
c9: 1 flow_(Basin_#5,_UserDemand_#8)_ - 1 user_demand_allocated_UserDemand_#8,1_ = 0
c10: 1 flow_(Basin_#5,_UserDemand_#9)_ - 1 user_demand_allocated_UserDemand_#9,1_ = 0
user_demand_return_flow_UserDemand_#6_: -0.5 flow_(Basin_#3,_UserDemand_#6)_ + 1 flow_(UserDemand_#6,_Basin_#3)_ = 0
user_demand_return_flow_UserDemand_#7_: -0.5 flow_(Basin_#3,_UserDemand_#7)_ + 1 flow_(UserDemand_#7,_Basin_#3)_ = 0
user_demand_return_flow_UserDemand_#8_: -0.5 flow_(Basin_#5,_UserDemand_#8)_ + 1 flow_(UserDemand_#8,_Basin_#5)_ = 0
user_demand_return_flow_UserDemand_#9_: -0.5 flow_(Basin_#5,_UserDemand_#9)_ + 1 flow_(UserDemand_#9,_Basin_#5)_ = 0
average_flow_unit_error_constraint_1_: -1 user_demand_error_UserDemand_#6,1,first_ - 1 user_demand_error_UserDemand_#7,1,first_ - 1 user_demand_error_UserDemand_#8,1,first_ - 1 user_demand_error_UserDemand_#9,1,first_ + 1 average_flow_unit_error_1_ = 0
Bounds
-0.36363636363636365 <= basin_storage_change_Basin_#3_ <= 1.4545454545454546
-0.36363636363636365 <= basin_storage_change_Basin_#5_ <= 1.4545454545454546
0 <= low_storage_factor_Basin_#3_ <= 1
0 <= low_storage_factor_Basin_#5_ <= 1
0 <= flow_(LevelBoundary_#1,_Pump_#2)_ <= 282.76363636363635
0 <= flow_(Pump_#2,_Basin_#3)_ <= 282.76363636363635
-1.5709090909090908e7 <= flow_(Basin_#3,_LinearResistance_#4)_ <= 1.5709090909090908e7
-1.5709090909090908e7 <= flow_(LinearResistance_#4,_Basin_#5)_ <= 1.5709090909090908e7
0 <= flow_(Basin_#3,_UserDemand_#6)_ <= 1.5709090909090908e7
0 <= flow_(Basin_#3,_UserDemand_#7)_ <= 1.5709090909090908e7
0 <= flow_(Basin_#5,_UserDemand_#8)_ <= 1.5709090909090908e7
0 <= flow_(Basin_#5,_UserDemand_#9)_ <= 1.5709090909090908e7
0 <= flow_(UserDemand_#6,_Basin_#3)_ <= 1.5709090909090908e7
0 <= flow_(UserDemand_#7,_Basin_#3)_ <= 1.5709090909090908e7
0 <= flow_(UserDemand_#8,_Basin_#5)_ <= 1.5709090909090908e7
0 <= flow_(UserDemand_#9,_Basin_#5)_ <= 1.5709090909090908e7
boundary_level_LevelBoundary_#1_ = 0
0 <= user_demand_allocated_UserDemand_#6,1_ <= 2
0 <= user_demand_allocated_UserDemand_#7,1_ <= 2
0 <= user_demand_allocated_UserDemand_#8,1_ <= 2
0 <= user_demand_allocated_UserDemand_#9,1_ <= 2
0 <= user_demand_error_UserDemand_#6,1,first_ <= 1
0 <= user_demand_error_UserDemand_#6,1,second_ <= 1
0 <= user_demand_error_UserDemand_#7,1,first_ <= 1
0 <= user_demand_error_UserDemand_#7,1,second_ <= 1
0 <= user_demand_error_UserDemand_#8,1,first_ <= 1
0 <= user_demand_error_UserDemand_#8,1,second_ <= 1
0 <= user_demand_error_UserDemand_#9,1,first_ <= 1
0 <= user_demand_error_UserDemand_#9,1,second_ <= 1
0 <= average_flow_unit_error_1_ <= 1
End

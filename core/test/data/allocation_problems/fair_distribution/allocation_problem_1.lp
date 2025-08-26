minimize
obj: 
subject to
c1_1: 1 __1_3_ - 1 y_1_1_ <= 0
c2_1: 1 __2_3_ - 1 y_2_1_ <= 0
c1: 1 __1_2_ + 1 __1_3_ - 1 y_1_1_ >= 0
c2: 1 __2_2_ + 1 __2_3_ - 1 y_2_1_ >= 0
user_demand_constraint_lower_UserDemand_#6_: 1 flow_(Basin_#3,_UserDemand_#6)_ - 2 target_fraction - 1 user_demand_allocated_UserDemand_#6_ + 2 relative_user_demand_error_UserDemand_#6_ >= 0
user_demand_constraint_lower_UserDemand_#7_: 1 flow_(Basin_#3,_UserDemand_#7)_ - 2 target_fraction - 1 user_demand_allocated_UserDemand_#7_ + 2 relative_user_demand_error_UserDemand_#7_ >= 0
user_demand_constraint_lower_UserDemand_#8_: 1 flow_(Basin_#5,_UserDemand_#8)_ - 2 target_fraction - 1 user_demand_allocated_UserDemand_#8_ + 2 relative_user_demand_error_UserDemand_#8_ >= 0
user_demand_constraint_lower_UserDemand_#9_: 1 flow_(Basin_#5,_UserDemand_#9)_ - 2 target_fraction - 1 user_demand_allocated_UserDemand_#9_ + 2 relative_user_demand_error_UserDemand_#9_ >= 0
linear_basin_profile_Basin_#3_: 0.00275 basin_storage_(Basin_#3,__start)_ - 0.00275 basin_storage_(Basin_#3,__end)_ + 1 basin_level_Basin_#3_ = 1000000
linear_basin_profile_Basin_#5_: 0.00275 basin_storage_(Basin_#5,__start)_ - 0.00275 basin_storage_(Basin_#5,__end)_ + 1 basin_level_Basin_#5_ = 1000000
c3: 1 __1_1_ + 1 __1_2_ + 1 __1_3_ = 1
c4: -1 basin_storage_(Basin_#3,__end)_ + 0.03636363636363636 __1_2_ + 0.36363636363636365 __1_3_ = 0
c5: -1 z_1 + 1 __1_2_ + 1 __1_3_ = 0
c6: 1 low_storage_factor_Basin_#3_ - 1 z_1 = 0
c7: 1 __2_1_ + 1 __2_2_ + 1 __2_3_ = 1
c8: -1 basin_storage_(Basin_#5,__end)_ + 0.03636363636363636 __2_2_ + 3.6363636363636362 __2_3_ = 0
c9: -1 z_2 + 1 __2_2_ + 1 __2_3_ = 0
c10: 1 low_storage_factor_Basin_#5_ - 1 z_2 = 0
flow_conservation_pump_Pump_#2_: 1 flow_(LevelBoundary_#1,_Pump_#2)_ - 1 flow_(Pump_#2,_Basin_#3)_ = 0
flow_conservation_linear_resistance_LinearResistance_#4_: 1 flow_(Basin_#3,_LinearResistance_#4)_ - 1 flow_(LinearResistance_#4,_Basin_#5)_ = 0
volume_conservation_Basin_#3_: -1 basin_storage_(Basin_#3,__start)_ + 1 basin_storage_(Basin_#3,__end)_ - 1 flow_(Pump_#2,_Basin_#3)_ + 1 flow_(Basin_#3,_LinearResistance_#4)_ + 1 flow_(Basin_#3,_UserDemand_#6)_ + 1 flow_(Basin_#3,_UserDemand_#7)_ - 1 flow_(UserDemand_#6,_Basin_#3)_ - 1 flow_(UserDemand_#7,_Basin_#3)_ - 1 basin_forcing_Basin_#3_ = 0
volume_conservation_Basin_#5_: -1 basin_storage_(Basin_#5,__start)_ + 1 basin_storage_(Basin_#5,__end)_ - 1 flow_(LinearResistance_#4,_Basin_#5)_ + 1 flow_(Basin_#5,_UserDemand_#8)_ + 1 flow_(Basin_#5,_UserDemand_#9)_ - 1 flow_(UserDemand_#8,_Basin_#5)_ - 1 flow_(UserDemand_#9,_Basin_#5)_ - 1 basin_forcing_Basin_#5_ = 0
linear_resistance_constraint_LinearResistance_#4_: -1 basin_level_Basin_#3_ + 1 basin_level_Basin_#5_ + 1 flow_(Basin_#3,_LinearResistance_#4)_ = 1
pump_constraint_Pump_#2_: 1 flow_(LevelBoundary_#1,_Pump_#2)_ = 1
user_demand_return_flow_UserDemand_#6_: -0.5 flow_(Basin_#3,_UserDemand_#6)_ + 1 flow_(UserDemand_#6,_Basin_#3)_ = 0
user_demand_return_flow_UserDemand_#7_: -0.5 flow_(Basin_#3,_UserDemand_#7)_ + 1 flow_(UserDemand_#7,_Basin_#3)_ = 0
user_demand_return_flow_UserDemand_#8_: -0.5 flow_(Basin_#5,_UserDemand_#8)_ + 1 flow_(UserDemand_#8,_Basin_#5)_ = 0
user_demand_return_flow_UserDemand_#9_: -0.5 flow_(Basin_#5,_UserDemand_#9)_ + 1 flow_(UserDemand_#9,_Basin_#5)_ = 0
Bounds
0 <= basin_storage_(Basin_#3,__start)_ <= 0.7272727272727273
0 <= basin_storage_(Basin_#5,__start)_ <= 7.2727272727272725
0 <= basin_storage_(Basin_#3,__end)_ <= 0.7272727272727273
0 <= basin_storage_(Basin_#5,__end)_ <= 7.2727272727272725
0 <= basin_level_Basin_#3_ <= 1
0 <= basin_level_Basin_#5_ <= 10
0 <= low_storage_factor_Basin_#3_ <= 1
0 <= low_storage_factor_Basin_#5_ <= 1
0 <= z_1 <= 1
0 <= __1_1_ <= 1
0 <= __1_2_ <= 1
0 <= __1_3_ <= 1
0 <= z_2 <= 1
0 <= __2_1_ <= 1
0 <= __2_2_ <= 1
0 <= __2_3_ <= 1
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
basin_forcing_Basin_#3_ = 0
basin_forcing_Basin_#5_ = 0
boundary_level_LevelBoundary_#1_ = 0
target_fraction = 1
user_demand_allocated_UserDemand_#6_ = 0
user_demand_allocated_UserDemand_#7_ = 0
user_demand_allocated_UserDemand_#8_ = 0
user_demand_allocated_UserDemand_#9_ = 0
relative_user_demand_error_UserDemand_#6_ >= 0
relative_user_demand_error_UserDemand_#7_ >= 0
relative_user_demand_error_UserDemand_#8_ >= 0
relative_user_demand_error_UserDemand_#9_ >= 0
Binary
y_1_1_
y_2_1_
End

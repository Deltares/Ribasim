minimize
obj: 
subject to
c1_2: 1 __1_3_ - 1 y_1_1_ <= 0
c2_2: 1 __1_4_ + 1 __1_5_ + 1 __1_6_ - 1 y_1_2_ <= 0
c3_2: 1 __1_6_ - 1 y_1_3_ <= 0
c4_1: 1 __2_3_ - 1 y_2_1_ <= 0
c1_1: 1 __1_2_ + 1 __1_3_ + 1 __1_4_ - 1 y_1_1_ >= 0
c2_1: 1 __1_3_ + 1 __1_4_ + 1 __1_5_ + 1 __1_6_ - 1 y_1_2_ >= 0
c3_1: 1 __1_5_ + 1 __1_6_ - 1 y_1_3_ >= 0
c4: 1 __2_2_ + 1 __2_3_ - 1 y_2_1_ >= 0
user_demand_constraint_lower_UserDemand_#4_: 1 flow_(Basin_#2,_UserDemand_#4)_ - 2 target_fraction - 1 user_demand_allocated_UserDemand_#4_ + 2 relative_user_demand_error_UserDemand_#4_ >= 0
storage_constraint_in_Basin_#2_: 1 basin_storage_(Basin_#2,__end)_ + 1 absolute_storage_error_Basin_#2_ >= 2000
storage_constraint_out_Basin_#2_: -1 basin_storage_(Basin_#2,__end)_ + 1 absolute_storage_error_Basin_#2_ >= -3000
c1: 1 __1_1_ + 1 __1_2_ + 1 __1_3_ + 1 __1_4_ + 1 __1_5_ + 1 __1_6_ = 1
c2: -1 basin_storage_(Basin_#2,__end)_ + 0.15333333333333332 __1_2_ + 0.5777777777777777 __1_3_ + 1.0933333333333333 __1_4_ + 1.4844444444444445 __1_5_ + 2 __1_6_ = 0
c3: -1 z_1 + 0.69 __1_2_ + 2.6329188129594687 __1_3_ + 5.130644767881848 __1_4_ + 7.146397568813835 __1_5_ + 10 __1_6_ = 0
basin_profile_Basin_#2_: 1 basin_level_Basin_#2_ - 1 z_1 = 0
c5: 1 __2_1_ + 1 __2_2_ + 1 __2_3_ = 1
c6: -1 basin_storage_(Basin_#2,__end)_ + 0.022222222222222223 __2_2_ + 2 __2_3_ = 0
c7: -1 z_2 + 1 __2_2_ + 1 __2_3_ = 0
c8: 1 low_storage_factor_Basin_#2_ - 1 z_2 = 0
volume_conservation_Basin_#2_: -1 basin_storage_(Basin_#2,__start)_ + 1 basin_storage_(Basin_#2,__end)_ - 1 flow_(FlowBoundary_#1,_Basin_#2)_ + 1 flow_(Basin_#2,_UserDemand_#4)_ - 1 flow_(UserDemand_#4,_Basin_#2)_ - 1 basin_forcing_Basin_#2_ = 0
user_demand_return_flow_UserDemand_#4_: -0.5 flow_(Basin_#2,_UserDemand_#4)_ + 1 flow_(UserDemand_#4,_Basin_#2)_ = 0
Bounds
0 <= basin_storage_(Basin_#2,__start)_ <= 2
0 <= basin_storage_(Basin_#2,__end)_ <= 2
0 <= basin_level_Basin_#2_ <= 10
0 <= z_1 <= 10
0 <= __1_1_ <= 1
0 <= __1_2_ <= 1
0 <= __1_3_ <= 1
0 <= __1_4_ <= 1
0 <= __1_5_ <= 1
0 <= __1_6_ <= 1
0 <= low_storage_factor_Basin_#2_ <= 1
0 <= z_2 <= 1
0 <= __2_1_ <= 1
0 <= __2_2_ <= 1
0 <= __2_3_ <= 1
0 <= flow_(FlowBoundary_#1,_Basin_#2)_ <= 9600000
0 <= flow_(Basin_#2,_UserDemand_#4)_ <= 9600000
0 <= flow_(UserDemand_#4,_Basin_#2)_ <= 9600000
basin_forcing_Basin_#2_ = 0
target_fraction = 1
user_demand_allocated_UserDemand_#4_ = 0
relative_user_demand_error_UserDemand_#4_ >= 0
absolute_storage_error_Basin_#2_ >= 0
Binary
y_1_1_
y_1_2_
y_1_3_
y_2_1_
End

minimize
obj: 
subject to
c1_1: 1 __1_3_ - 1 y_1_1_ <= 0
c1: 1 __1_2_ + 1 __1_3_ - 1 y_1_1_ >= 0
user_demand_constraint_lower_UserDemand_#4_: 1 flow_(Basin_#2,_UserDemand_#4)_ - 2 target_fraction - 1 user_demand_allocated_UserDemand_#4_ + 2 relative_user_demand_error_UserDemand_#4_ >= 0
storage_constraint_in_Basin_#2_: 1 basin_storage_(Basin_#2,__end)_ + 1 absolute_storage_error_Basin_#2_ >= 2000
storage_constraint_out_Basin_#2_: -1 basin_storage_(Basin_#2,__end)_ + 1 absolute_storage_error_Basin_#2_ >= -3000
linear_basin_profile_Basin_#2_: 0.0045 basin_storage_(Basin_#2,__start)_ - 0.0045 basin_storage_(Basin_#2,__end)_ + 1 basin_level_Basin_#2_ = 1000000
c2: 1 __1_1_ + 1 __1_2_ + 1 __1_3_ = 1
c3: -1 basin_storage_(Basin_#2,__end)_ + 0.022222222222222223 __1_2_ + 2 __1_3_ = 0
c4: -1 z_1 + 1 __1_2_ + 1 __1_3_ = 0
c5: 1 low_storage_factor_Basin_#2_ - 1 z_1 = 0
volume_conservation_Basin_#2_: -1 basin_storage_(Basin_#2,__start)_ + 1 basin_storage_(Basin_#2,__end)_ - 1 flow_(FlowBoundary_#1,_Basin_#2)_ + 1 flow_(Basin_#2,_UserDemand_#4)_ - 1 flow_(UserDemand_#4,_Basin_#2)_ - 1 basin_forcing_Basin_#2_ = 0
user_demand_return_flow_UserDemand_#4_: -0.5 flow_(Basin_#2,_UserDemand_#4)_ + 1 flow_(UserDemand_#4,_Basin_#2)_ = 0
Bounds
0 <= basin_storage_(Basin_#2,__start)_ <= 4
0 <= basin_storage_(Basin_#2,__end)_ <= 4
0 <= basin_level_Basin_#2_ <= 10
0 <= low_storage_factor_Basin_#2_ <= 1
0 <= z_1 <= 1
0 <= __1_1_ <= 1
0 <= __1_2_ <= 1
0 <= __1_3_ <= 1
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
End

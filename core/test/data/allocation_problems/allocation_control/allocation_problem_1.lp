minimize
obj: 
subject to
c1_1: 1 __1_3_ - 1 y_1_1_ <= 0
c1: 1 __1_2_ + 1 __1_3_ - 1 y_1_1_ >= 0
user_demand_constraint_lower_UserDemand_#4_: 1 flow_(Basin_#3,_UserDemand_#4)_ - 2 target_fraction - 1 user_demand_allocated_UserDemand_#4_ + 2 relative_user_demand_error_UserDemand_#4_ >= 0
linear_basin_profile_Basin_#3_: 0.005 basin_storage_(Basin_#3,__start)_ - 0.005 basin_storage_(Basin_#3,__end)_ + 1 basin_level_Basin_#3_ = 1000000
c2: 1 __1_1_ + 1 __1_2_ + 1 __1_3_ = 1
c3: -1 basin_storage_(Basin_#3,__end)_ + 0.002 __1_2_ + 2 __1_3_ = 0
c4: -1 z_1 + 1 __1_2_ + 1 __1_3_ = 0
c5: 1 low_storage_factor_Basin_#3_ - 1 z_1 = 0
flow_conservation_outlet_Outlet_#2_: 1 flow_(LevelBoundary_#1,_Outlet_#2)_ - 1 flow_(Outlet_#2,_Basin_#3)_ = 0
volume_conservation_Basin_#3_: -1 basin_storage_(Basin_#3,__start)_ + 1 basin_storage_(Basin_#3,__end)_ - 1 flow_(Outlet_#2,_Basin_#3)_ + 1 flow_(Basin_#3,_UserDemand_#4)_ - 1 flow_(UserDemand_#4,_Basin_#3)_ - 1 basin_forcing_Basin_#3_ = 0
user_demand_return_flow_UserDemand_#4_: -0.5 flow_(Basin_#3,_UserDemand_#4)_ + 1 flow_(UserDemand_#4,_Basin_#3)_ = 0
Bounds
0 <= basin_storage_(Basin_#3,__start)_ <= 2
0 <= basin_storage_(Basin_#3,__end)_ <= 2
0 <= basin_level_Basin_#3_ <= 100
0 <= low_storage_factor_Basin_#3_ <= 1
0 <= z_1 <= 1
0 <= __1_1_ <= 1
0 <= __1_2_ <= 1
0 <= __1_3_ <= 1
0 <= flow_(LevelBoundary_#1,_Outlet_#2)_ <= 155.52
0 <= flow_(Outlet_#2,_Basin_#3)_ <= 155.52
0 <= flow_(Basin_#3,_UserDemand_#4)_ <= 8640000
0 <= flow_(UserDemand_#4,_Basin_#3)_ <= 8640000
basin_forcing_Basin_#3_ = 0
boundary_level_LevelBoundary_#1_ = 0
target_fraction = 1
user_demand_allocated_UserDemand_#4_ = 0
relative_user_demand_error_UserDemand_#4_ >= 0
Binary
y_1_1_
End

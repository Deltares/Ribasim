minimize
obj: 
subject to
c1_2: 1 __3_3_ - 1 y_3_1_ <= 0
c2_2: 1 __4_3_ - 1 y_4_1_ <= 0
c1_1: 1 __3_2_ + 1 __3_3_ - 1 y_3_1_ >= 0
c2_1: 1 __4_2_ + 1 __4_3_ - 1 y_4_1_ >= 0
user_demand_constraint_lower_UserDemand_#3_: 1 flow_(Basin_#2,_UserDemand_#3)_ - 2 target_fraction - 1 user_demand_allocated_UserDemand_#3_ + 2 relative_user_demand_error_UserDemand_#3_ >= 0
storage_constraint_in_Basin_#2_: 1 basin_storage_(Basin_#2,__end)_ + 1 absolute_storage_error_Basin_#2_ >= 2000
storage_constraint_in_Basin_#5_: 1 basin_storage_(Basin_#5,__end)_ + 1 absolute_storage_error_Basin_#5_ >= 2000
storage_constraint_out_Basin_#2_: -1 basin_storage_(Basin_#2,__end)_ + 1 absolute_storage_error_Basin_#2_ >= -3000
storage_constraint_out_Basin_#5_: -1 basin_storage_(Basin_#5,__end)_ + 1 absolute_storage_error_Basin_#5_ >= -3000
c1: 1 __1_1_ + 1 __1_2_ = 1
c2: -1 basin_storage_(Basin_#2,__end)_ + 2 __1_2_ = 0
c3: -1 z_1 + 10 __1_2_ = 0
basin_profile_Basin_#2_: 1 basin_level_Basin_#2_ - 1 z_1 = 0
c5: 1 __2_1_ + 1 __2_2_ = 1
c6: -1 basin_storage_(Basin_#5,__end)_ + 2 __2_2_ = 0
c7: -1 z_2 + 10 __2_2_ = 0
basin_profile_Basin_#5_: 1 basin_level_Basin_#5_ - 1 z_2 = 0
c9: 1 __3_1_ + 1 __3_2_ + 1 __3_3_ = 1
c10: -1 basin_storage_(Basin_#2,__end)_ + 0.02 __3_2_ + 2 __3_3_ = 0
c11: -1 z_3 + 1 __3_2_ + 1 __3_3_ = 0
c12: 1 low_storage_factor_Basin_#2_ - 1 z_3 = 0
c13: 1 __4_1_ + 1 __4_2_ + 1 __4_3_ = 1
c14: -1 basin_storage_(Basin_#5,__end)_ + 0.02 __4_2_ + 2 __4_3_ = 0
c15: -1 z_4 + 1 __4_2_ + 1 __4_3_ = 0
c16: 1 low_storage_factor_Basin_#5_ - 1 z_4 = 0
volume_conservation_Basin_#2_: -1 basin_storage_(Basin_#2,__start)_ + 1 basin_storage_(Basin_#2,__end)_ - 1 flow_(FlowBoundary_#1,_Basin_#2)_ + 1 flow_(Basin_#2,_UserDemand_#3)_ - 1 basin_forcing_Basin_#2_ = 0
volume_conservation_Basin_#5_: -1 basin_storage_(Basin_#5,__start)_ + 1 basin_storage_(Basin_#5,__end)_ - 1 flow_(UserDemand_#3,_Basin_#5)_ - 1 basin_forcing_Basin_#5_ = 0
user_demand_return_flow_UserDemand_#3_: -0.5 flow_(Basin_#2,_UserDemand_#3)_ + 1 flow_(UserDemand_#3,_Basin_#5)_ = 0
Bounds
0 <= basin_storage_(Basin_#2,__start)_ <= 2
0 <= basin_storage_(Basin_#5,__start)_ <= 2
0 <= basin_storage_(Basin_#2,__end)_ <= 2
0 <= basin_storage_(Basin_#5,__end)_ <= 2
0 <= basin_level_Basin_#2_ <= 10
0 <= basin_level_Basin_#5_ <= 10
0 <= z_1 <= 10
0 <= __1_1_ <= 1
0 <= __1_2_ <= 1
0 <= z_2 <= 10
0 <= __2_1_ <= 1
0 <= __2_2_ <= 1
0 <= low_storage_factor_Basin_#2_ <= 1
0 <= low_storage_factor_Basin_#5_ <= 1
0 <= z_3 <= 1
0 <= __3_1_ <= 1
0 <= __3_2_ <= 1
0 <= __3_3_ <= 1
0 <= z_4 <= 1
0 <= __4_1_ <= 1
0 <= __4_2_ <= 1
0 <= __4_3_ <= 1
0 <= flow_(FlowBoundary_#1,_Basin_#2)_ <= 8640000
0 <= flow_(Basin_#2,_UserDemand_#3)_ <= 8640000
0 <= flow_(UserDemand_#3,_Basin_#5)_ <= 8640000
basin_forcing_Basin_#2_ = 0
basin_forcing_Basin_#5_ = 0
target_fraction = 1
user_demand_allocated_UserDemand_#3_ = 0
relative_user_demand_error_UserDemand_#3_ >= 0
absolute_storage_error_Basin_#2_ >= 0
absolute_storage_error_Basin_#5_ >= 0
Binary
y_3_1_
y_4_1_
End

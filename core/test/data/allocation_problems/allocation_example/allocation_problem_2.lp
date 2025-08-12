minimize
obj: 
subject to
c1_1: 1 __1_3_ - 1 y_1_1_ <= 0
c2_1: 1 __2_3_ - 1 y_2_1_ <= 0
c1: 1 __1_2_ + 1 __1_3_ - 1 y_1_1_ >= 0
c2: 1 __2_2_ + 1 __2_3_ - 1 y_2_1_ >= 0
user_demand_constraint_lower_UserDemand_#3_: 1 flow_(Basin_#2,_UserDemand_#3)_ - 2 target_fraction - 1 user_demand_allocated_UserDemand_#3_ + 2 relative_user_demand_error_UserDemand_#3_ >= 0
user_demand_constraint_lower_UserDemand_#6_: 1 flow_(Basin_#5,_UserDemand_#6)_ - 2 target_fraction - 1 user_demand_allocated_UserDemand_#6_ + 2 relative_user_demand_error_UserDemand_#6_ >= 0
linear_basin_profile_Basin_#2_: 0.15 basin_storage_(Basin_#2,__start)_ - 0.15 basin_storage_(Basin_#2,__end)_ + 1 basin_level_Basin_#2_ = 1000000
linear_basin_profile_Basin_#5_: 0.15 basin_storage_(Basin_#5,__start)_ - 0.15 basin_storage_(Basin_#5,__end)_ + 1 basin_level_Basin_#5_ = 1000000
c3: 1 __1_1_ + 1 __1_2_ + 1 __1_3_ = 1
c4: -1 basin_storage_(Basin_#2,__end)_ + 0.2 __1_2_ + 2 __1_3_ = 0
c5: -1 z_1 + 1 __1_2_ + 1 __1_3_ = 0
c6: 1 low_storage_factor_Basin_#2_ - 1 z_1 = 0
c7: 1 __2_1_ + 1 __2_2_ + 1 __2_3_ = 1
c8: -1 basin_storage_(Basin_#5,__end)_ + 0.2 __2_2_ + 2 __2_3_ = 0
c9: -1 z_2 + 1 __2_2_ + 1 __2_3_ = 0
c10: 1 low_storage_factor_Basin_#5_ - 1 z_2 = 0
flow_conservation_linear_resistance_LinearResistance_#4_: 1 flow_(Basin_#2,_LinearResistance_#4)_ - 1 flow_(LinearResistance_#4,_Basin_#5)_ = 0
flow_conservation_tabulated_rating_curve_TabulatedRatingCurve_#7_: 1 flow_(Basin_#5,_TabulatedRatingCurve_#7)_ - 1 flow_(TabulatedRatingCurve_#7,_Terminal_#8)_ = 0
volume_conservation_Basin_#2_: -1 basin_storage_(Basin_#2,__start)_ + 1 basin_storage_(Basin_#2,__end)_ - 1 flow_(FlowBoundary_#1,_Basin_#2)_ + 1 flow_(Basin_#2,_UserDemand_#3)_ + 1 flow_(Basin_#2,_LinearResistance_#4)_ - 1 flow_(UserDemand_#3,_Basin_#2)_ - 1 basin_forcing_Basin_#2_ = 0
volume_conservation_Basin_#5_: -1 basin_storage_(Basin_#5,__start)_ + 1 basin_storage_(Basin_#5,__end)_ - 1 flow_(LinearResistance_#4,_Basin_#5)_ + 1 flow_(Basin_#5,_UserDemand_#6)_ + 1 flow_(Basin_#5,_TabulatedRatingCurve_#7)_ - 1 flow_(UserDemand_#6,_Basin_#5)_ - 1 basin_forcing_Basin_#5_ = 0
tabulated_rating_curve_constraint_TabulatedRatingCurve_#7_: -1 basin_level_Basin_#5_ + 1 flow_(Basin_#5,_TabulatedRatingCurve_#7)_ = 1
linear_resistance_constraint_LinearResistance_#4_: -1 basin_level_Basin_#2_ + 1 basin_level_Basin_#5_ + 1 flow_(Basin_#2,_LinearResistance_#4)_ = 1
user_demand_return_flow_UserDemand_#3_: -0.5 flow_(Basin_#2,_UserDemand_#3)_ + 1 flow_(UserDemand_#3,_Basin_#2)_ = 0
user_demand_return_flow_UserDemand_#6_: -0.5 flow_(Basin_#5,_UserDemand_#6)_ + 1 flow_(UserDemand_#6,_Basin_#5)_ = 0
Bounds
0 <= basin_storage_(Basin_#2,__start)_ <= 2
0 <= basin_storage_(Basin_#5,__start)_ <= 2
0 <= basin_storage_(Basin_#2,__end)_ <= 2
0 <= basin_storage_(Basin_#5,__end)_ <= 2
0 <= basin_level_Basin_#2_ <= 1
0 <= basin_level_Basin_#5_ <= 1
0 <= low_storage_factor_Basin_#2_ <= 1
0 <= low_storage_factor_Basin_#5_ <= 1
0 <= z_1 <= 1
0 <= __1_1_ <= 1
0 <= __1_2_ <= 1
0 <= __1_3_ <= 1
0 <= z_2 <= 1
0 <= __2_1_ <= 1
0 <= __2_2_ <= 1
0 <= __2_3_ <= 1
0 <= flow_(FlowBoundary_#1,_Basin_#2)_ <= 288000
0 <= flow_(Basin_#2,_UserDemand_#3)_ <= 288000
-288000 <= flow_(Basin_#2,_LinearResistance_#4)_ <= 288000
-288000 <= flow_(LinearResistance_#4,_Basin_#5)_ <= 288000
0 <= flow_(Basin_#5,_UserDemand_#6)_ <= 288000
0 <= flow_(Basin_#5,_TabulatedRatingCurve_#7)_ <= 288000
0 <= flow_(TabulatedRatingCurve_#7,_Terminal_#8)_ <= 288000
0 <= flow_(UserDemand_#3,_Basin_#2)_ <= 288000
0 <= flow_(UserDemand_#6,_Basin_#5)_ <= 288000
basin_forcing_Basin_#2_ = 0
basin_forcing_Basin_#5_ = 0
target_fraction = 1
user_demand_allocated_UserDemand_#3_ = 0
user_demand_allocated_UserDemand_#6_ = 0
relative_user_demand_error_UserDemand_#3_ >= 0
relative_user_demand_error_UserDemand_#6_ >= 0
Binary
y_1_1_
y_2_1_
End

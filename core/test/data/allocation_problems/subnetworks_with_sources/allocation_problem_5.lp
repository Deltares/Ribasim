minimize
obj: 
subject to
c1_1: 1 __1_3_ - 1 y_1_1_ <= 0
c2_1: 1 __2_3_ - 1 y_2_1_ <= 0
c1: 1 __1_2_ + 1 __1_3_ - 1 y_1_1_ >= 0
c2: 1 __2_2_ + 1 __2_3_ - 1 y_2_1_ >= 0
user_demand_constraint_lower_UserDemand_#32_: 1 flow_(Basin_#31,_UserDemand_#32)_ - 2 target_fraction - 1 user_demand_allocated_UserDemand_#32_ + 2 relative_user_demand_error_UserDemand_#32_ >= 0
linear_basin_profile_Basin_#25_: 0.0005 basin_storage_(Basin_#25,__start)_ - 0.0005 basin_storage_(Basin_#25,__end)_ + 1 basin_level_Basin_#25_ = 1000000
linear_basin_profile_Basin_#31_: 0.0005 basin_storage_(Basin_#31,__start)_ - 0.0005 basin_storage_(Basin_#31,__end)_ + 1 basin_level_Basin_#31_ = 1000000
c3: 1 __1_1_ + 1 __1_2_ + 1 __1_3_ = 1
c4: -1 basin_storage_(Basin_#25,__end)_ + 0.2 __1_2_ + 2 __1_3_ = 0
c5: -1 z_1 + 1 __1_2_ + 1 __1_3_ = 0
c6: 1 low_storage_factor_Basin_#25_ - 1 z_1 = 0
c7: 1 __2_1_ + 1 __2_2_ + 1 __2_3_ = 1
c8: -1 basin_storage_(Basin_#31,__end)_ + 0.2 __2_2_ + 2 __2_3_ = 0
c9: -1 z_2 + 1 __2_2_ + 1 __2_3_ = 0
c10: 1 low_storage_factor_Basin_#31_ - 1 z_2 = 0
flow_conservation_tabulated_rating_curve_TabulatedRatingCurve_#26_: 1 flow_(Basin_#25,_TabulatedRatingCurve_#26)_ - 1 flow_(TabulatedRatingCurve_#26,_Basin_#31)_ = 0
volume_conservation_Basin_#25_: -1 basin_storage_(Basin_#25,__start)_ + 1 basin_storage_(Basin_#25,__end)_ + 1 flow_(Basin_#25,_TabulatedRatingCurve_#26)_ - 1 basin_forcing_Basin_#25_ = 0
volume_conservation_Basin_#31_: -1 basin_storage_(Basin_#31,__start)_ + 1 basin_storage_(Basin_#31,__end)_ - 1 flow_(TabulatedRatingCurve_#26,_Basin_#31)_ + 1 flow_(Basin_#31,_UserDemand_#32)_ - 1 flow_(UserDemand_#32,_Basin_#31)_ - 1 basin_forcing_Basin_#31_ = 0
tabulated_rating_curve_constraint_TabulatedRatingCurve_#26_: -1 basin_level_Basin_#25_ + 1 basin_level_Basin_#31_ + 1 flow_(Basin_#25,_TabulatedRatingCurve_#26)_ = 1
user_demand_return_flow_UserDemand_#32_: -0.5 flow_(Basin_#31,_UserDemand_#32)_ + 1 flow_(UserDemand_#32,_Basin_#31)_ = 0
Bounds
0 <= basin_storage_(Basin_#25,__start)_ <= 2
0 <= basin_storage_(Basin_#31,__start)_ <= 2
0 <= basin_storage_(Basin_#25,__end)_ <= 2
0 <= basin_storage_(Basin_#31,__end)_ <= 2
0 <= basin_level_Basin_#25_ <= 1
0 <= basin_level_Basin_#31_ <= 1
0 <= low_storage_factor_Basin_#25_ <= 1
0 <= low_storage_factor_Basin_#31_ <= 1
0 <= z_1 <= 1
0 <= __1_1_ <= 1
0 <= __1_2_ <= 1
0 <= __1_3_ <= 1
0 <= z_2 <= 1
0 <= __2_1_ <= 1
0 <= __2_2_ <= 1
0 <= __2_3_ <= 1
0 <= flow_(Pump_#24,_Basin_#25)_ <= 172.8
0 <= flow_(Basin_#25,_TabulatedRatingCurve_#26)_ <= 86400000
0 <= flow_(TabulatedRatingCurve_#26,_Basin_#31)_ <= 86400000
0 <= flow_(Basin_#31,_UserDemand_#32)_ <= 86400000
0 <= flow_(UserDemand_#32,_Basin_#31)_ <= 86400000
basin_forcing_Basin_#25_ = 0
basin_forcing_Basin_#31_ = 0
target_fraction = 1
user_demand_allocated_UserDemand_#32_ = 0
relative_user_demand_error_UserDemand_#32_ >= 0
Binary
y_1_1_
y_2_1_
End

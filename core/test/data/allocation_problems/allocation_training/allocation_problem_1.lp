minimize
obj: 
subject to
c1_1: 1 __1_3_ - 1 y_1_1_ <= 0
c2_1: 1 __2_3_ - 1 y_2_1_ <= 0
c1: 1 __1_2_ + 1 __1_3_ - 1 y_1_1_ >= 0
c2: 1 __2_2_ + 1 __2_3_ - 1 y_2_1_ >= 0
user_demand_constraint_lower_UserDemand_#6_: 1 flow_(Basin_#7,_UserDemand_#6)_ - 2 target_fraction - 1 user_demand_allocated_UserDemand_#6_ + 2 relative_user_demand_error_UserDemand_#6_ >= 0
user_demand_constraint_lower_UserDemand_#9_: 1 flow_(Basin_#7,_UserDemand_#9)_ - 2 target_fraction - 1 user_demand_allocated_UserDemand_#9_ + 2 relative_user_demand_error_UserDemand_#9_ >= 0
user_demand_constraint_lower_UserDemand_#10_: 1 flow_(Basin_#7,_UserDemand_#10)_ - 2 target_fraction - 1 user_demand_allocated_UserDemand_#10_ + 2 relative_user_demand_error_UserDemand_#10_ >= 0
storage_constraint_in_Basin_#7_: 1 basin_storage_(Basin_#7,__end)_ + 1 absolute_storage_error_Basin_#7_ >= 2000
storage_constraint_out_Basin_#7_: -1 basin_storage_(Basin_#7,__end)_ + 1 absolute_storage_error_Basin_#7_ >= -3000
linear_basin_profile_Basin_#3_: 50.4665 basin_storage_(Basin_#3,__start)_ - 50.4665 basin_storage_(Basin_#3,__end)_ + 1 basin_level_Basin_#3_ = 1000000
linear_basin_profile_Basin_#7_: 50.4665 basin_storage_(Basin_#7,__start)_ - 50.4665 basin_storage_(Basin_#7,__end)_ + 1 basin_level_Basin_#7_ = 1000000
c3: 1 __1_1_ + 1 __1_2_ + 1 __1_3_ = 1
c4: -1 basin_storage_(Basin_#3,__end)_ + 0.0014129505051205587 __1_2_ + 0.3728413898328594 __1_3_ = 0
c5: -1 z_1 + 1 __1_2_ + 1 __1_3_ = 0
c6: 1 low_storage_factor_Basin_#3_ - 1 z_1 = 0
c7: 1 __2_1_ + 1 __2_2_ + 1 __2_3_ = 1
c8: -1 basin_storage_(Basin_#7,__end)_ + 0.03980433979542299 __2_2_ + 3.6271586101671405 __2_3_ = 0
c9: -1 z_2 + 1 __2_2_ + 1 __2_3_ = 0
c10: 1 low_storage_factor_Basin_#7_ - 1 z_2 = 0
flow_conservation_tabulated_rating_curve_TabulatedRatingCurve_#4_: 1 flow_(Basin_#3,_TabulatedRatingCurve_#4)_ - 1 flow_(TabulatedRatingCurve_#4,_Terminal_#5)_ = 0
flow_conservation_tabulated_rating_curve_TabulatedRatingCurve_#8_: 1 flow_(Basin_#7,_TabulatedRatingCurve_#8)_ - 1 flow_(TabulatedRatingCurve_#8,_Basin_#3)_ = 0
volume_conservation_Basin_#3_: -1 basin_storage_(Basin_#3,__start)_ + 1 basin_storage_(Basin_#3,__end)_ - 1 flow_(FlowBoundary_#2,_Basin_#3)_ - 1 flow_(UserDemand_#6,_Basin_#3)_ - 1 flow_(UserDemand_#9,_Basin_#3)_ - 1 flow_(TabulatedRatingCurve_#8,_Basin_#3)_ + 1 flow_(Basin_#3,_TabulatedRatingCurve_#4)_ - 1 flow_(UserDemand_#10,_Basin_#3)_ - 1 basin_forcing_Basin_#3_ = 0
volume_conservation_Basin_#7_: -1 basin_storage_(Basin_#7,__start)_ + 1 basin_storage_(Basin_#7,__end)_ - 1 flow_(FlowBoundary_#1,_Basin_#7)_ + 1 flow_(Basin_#7,_UserDemand_#6)_ + 1 flow_(Basin_#7,_UserDemand_#9)_ + 1 flow_(Basin_#7,_TabulatedRatingCurve_#8)_ + 1 flow_(Basin_#7,_UserDemand_#10)_ - 1 basin_forcing_Basin_#7_ = 0
tabulated_rating_curve_constraint_TabulatedRatingCurve_#4_: -1 basin_level_Basin_#3_ + 1 flow_(Basin_#3,_TabulatedRatingCurve_#4)_ = 1
tabulated_rating_curve_constraint_TabulatedRatingCurve_#8_: 1 basin_level_Basin_#3_ - 1 basin_level_Basin_#7_ + 1 flow_(Basin_#7,_TabulatedRatingCurve_#8)_ = 1
user_demand_return_flow_UserDemand_#6_: -0.5 flow_(Basin_#7,_UserDemand_#6)_ + 1 flow_(UserDemand_#6,_Basin_#3)_ = 0
user_demand_return_flow_UserDemand_#9_: -0.5 flow_(Basin_#7,_UserDemand_#9)_ + 1 flow_(UserDemand_#9,_Basin_#3)_ = 0
user_demand_return_flow_UserDemand_#10_: -0.5 flow_(Basin_#7,_UserDemand_#10)_ + 1 flow_(UserDemand_#10,_Basin_#3)_ = 0
Bounds
0 <= basin_storage_(Basin_#3,__start)_ <= 0.3728413898328594
0 <= basin_storage_(Basin_#7,__start)_ <= 3.6271586101671405
0 <= basin_storage_(Basin_#3,__end)_ <= 0.3728413898328594
0 <= basin_storage_(Basin_#7,__end)_ <= 3.6271586101671405
0 <= basin_level_Basin_#3_ <= 6
0 <= basin_level_Basin_#7_ <= 7
0 <= low_storage_factor_Basin_#3_ <= 1
0 <= low_storage_factor_Basin_#7_ <= 1
0 <= z_1 <= 1
0 <= __1_1_ <= 1
0 <= __1_2_ <= 1
0 <= __1_3_ <= 1
0 <= z_2 <= 1
0 <= __2_1_ <= 1
0 <= __2_2_ <= 1
0 <= __2_3_ <= 1
0 <= flow_(FlowBoundary_#1,_Basin_#7)_ <= 856.0133950244222
0 <= flow_(FlowBoundary_#2,_Basin_#3)_ <= 856.0133950244222
0 <= flow_(Basin_#7,_UserDemand_#6)_ <= 856.0133950244222
0 <= flow_(UserDemand_#6,_Basin_#3)_ <= 856.0133950244222
0 <= flow_(Basin_#7,_UserDemand_#9)_ <= 856.0133950244222
0 <= flow_(UserDemand_#9,_Basin_#3)_ <= 856.0133950244222
0 <= flow_(Basin_#7,_TabulatedRatingCurve_#8)_ <= 856.0133950244222
0 <= flow_(TabulatedRatingCurve_#8,_Basin_#3)_ <= 856.0133950244222
0 <= flow_(Basin_#3,_TabulatedRatingCurve_#4)_ <= 856.0133950244222
0 <= flow_(Basin_#7,_UserDemand_#10)_ <= 856.0133950244222
0 <= flow_(UserDemand_#10,_Basin_#3)_ <= 856.0133950244222
0 <= flow_(TabulatedRatingCurve_#4,_Terminal_#5)_ <= 856.0133950244222
basin_forcing_Basin_#3_ = 0
basin_forcing_Basin_#7_ = 0
target_fraction = 1
user_demand_allocated_UserDemand_#6_ = 0
user_demand_allocated_UserDemand_#9_ = 0
user_demand_allocated_UserDemand_#10_ = 0
relative_user_demand_error_UserDemand_#6_ >= 0
relative_user_demand_error_UserDemand_#9_ >= 0
relative_user_demand_error_UserDemand_#10_ >= 0
absolute_storage_error_Basin_#7_ >= 0
Binary
y_1_1_
y_2_1_
End

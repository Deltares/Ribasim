minimize
obj: 1000 flow_(LevelBoundary_#1,_TabulatedRatingCurve_#2)_ - 10 flow_(TabulatedRatingCurve_#2,_Basin_#3)_
subject to
c1: 1 user_demand_error_UserDemand_#6,1,first_ <= 0
c2: 1 user_demand_error_UserDemand_#6,1,second_ <= 0
c3: 1 flow_demand_error_TabulatedRatingCurve_#2,2,first_ <= 0
c4: 1 flow_demand_error_TabulatedRatingCurve_#2,2,second_ <= 0
c5: 1 user_demand_error_UserDemand_#4,3,first_ <= 0
c6: 1 user_demand_error_UserDemand_#4,3,second_ <= 0
c7: 1 user_demand_error_UserDemand_#8,4,first_ <= 0
c8: 1 user_demand_error_UserDemand_#8,4,second_ <= 0
c9: -1 low_storage_factor_Basin_#3_ - 1 low_storage_factor_Basin_#7_ <= -2
user_demand_relative_error_constraint_UserDemand_#4,3_: 1 user_demand_allocated_UserDemand_#4,3_ + 0.00288 user_demand_error_UserDemand_#4,3,first_ >= 0.00288
user_demand_relative_error_constraint_UserDemand_#6,1_: 1 user_demand_allocated_UserDemand_#6,1_ + 0.00288 user_demand_error_UserDemand_#6,1,first_ >= 0.00288
user_demand_relative_error_constraint_UserDemand_#8,4_: 1 user_demand_allocated_UserDemand_#8,4_ + 0.00576 user_demand_error_UserDemand_#8,4,first_ >= 0.00576
flow_demand_relative_error_constraint_TabulatedRatingCurve_#2,2_: 1 flow_demand_allocated_TabulatedRatingCurve_#2,2_ + 0.00576 flow_demand_error_TabulatedRatingCurve_#2,2,first_ >= 0.00576
user_demand_fairness_error_constraint_UserDemand_#4,3_: -1 user_demand_error_UserDemand_#4,3,first_ + 1 user_demand_error_UserDemand_#4,3,second_ + 1 average_flow_unit_error_3_ >= 0
user_demand_fairness_error_constraint_UserDemand_#6,1_: -1 user_demand_error_UserDemand_#6,1,first_ + 1 user_demand_error_UserDemand_#6,1,second_ + 1 average_flow_unit_error_1_ >= 0
user_demand_fairness_error_constraint_UserDemand_#8,4_: -1 user_demand_error_UserDemand_#8,4,first_ + 1 user_demand_error_UserDemand_#8,4,second_ + 1 average_flow_unit_error_4_ >= 0
flow_demand_fairness_error_constraint_TabulatedRatingCurve_#2,2_: -1 flow_demand_error_TabulatedRatingCurve_#2,2,first_ + 1 flow_demand_error_TabulatedRatingCurve_#2,2,second_ + 1 average_flow_unit_error_2_ >= 0
flow_conservation_tabulated_rating_curve_TabulatedRatingCurve_#2_: 1 flow_(LevelBoundary_#1,_TabulatedRatingCurve_#2)_ - 1 flow_(TabulatedRatingCurve_#2,_Basin_#3)_ = 0
volume_conservation_Basin_#3_: 1 basin_storage_change_Basin_#3_ - 1 flow_(TabulatedRatingCurve_#2,_Basin_#3)_ + 1 flow_(Basin_#3,_UserDemand_#4)_ + 1 flow_(Basin_#3,_UserDemand_#6)_ = 0
volume_conservation_Basin_#7_: 1 basin_storage_change_Basin_#7_ - 1 flow_(UserDemand_#4,_Basin_#7)_ + 1 flow_(Basin_#7,_UserDemand_#8)_ - 1 flow_(UserDemand_#8,_Basin_#7)_ - 1 flow_(UserDemand_#6,_Basin_#7)_ = 0
user_demand_allocated_sum_constraint_UserDemand_#4_: 1 flow_(Basin_#3,_UserDemand_#4)_ - 1 user_demand_allocated_UserDemand_#4,3_ = 0
user_demand_allocated_sum_constraint_UserDemand_#6_: 1 flow_(Basin_#3,_UserDemand_#6)_ - 1 user_demand_allocated_UserDemand_#6,1_ = 0
user_demand_allocated_sum_constraint_UserDemand_#8_: 1 flow_(Basin_#7,_UserDemand_#8)_ - 1 user_demand_allocated_UserDemand_#8,4_ = 0
user_demand_return_flow_UserDemand_#4_: -1 flow_(Basin_#3,_UserDemand_#4)_ + 1 flow_(UserDemand_#4,_Basin_#7)_ = 0
user_demand_return_flow_UserDemand_#6_: -1 flow_(Basin_#3,_UserDemand_#6)_ + 1 flow_(UserDemand_#6,_Basin_#7)_ = 0
user_demand_return_flow_UserDemand_#8_: -1 flow_(Basin_#7,_UserDemand_#8)_ + 1 flow_(UserDemand_#8,_Basin_#7)_ = 0
flow_demand_allocated_sum_constraint_TabulatedRatingCurve_#2_: 1 flow_(LevelBoundary_#1,_TabulatedRatingCurve_#2)_ - 1 flow_demand_allocated_TabulatedRatingCurve_#2,2_ - 1 flow_demand_extra_TabulatedRatingCurve_#2_ = 0
average_flow_unit_error_constraint_1_: -1 user_demand_error_UserDemand_#6,1,first_ + 1 average_flow_unit_error_1_ = 0
average_flow_unit_error_constraint_2_: -1 flow_demand_error_TabulatedRatingCurve_#2,2,first_ + 1 average_flow_unit_error_2_ = 0
average_flow_unit_error_constraint_3_: -1 user_demand_error_UserDemand_#4,3,first_ + 1 average_flow_unit_error_3_ = 0
average_flow_unit_error_constraint_4_: -1 user_demand_error_UserDemand_#8,4,first_ + 1 average_flow_unit_error_4_ = 0
tabulated_rating_curve_constraint_TabulatedRatingCurve_#2_: 1 flow_(LevelBoundary_#1,_TabulatedRatingCurve_#2)_ = 0.00576
Bounds
-0.3333333333333333 <= basin_storage_change_Basin_#3_ <= 3
-0.3333333333333333 <= basin_storage_change_Basin_#7_ <= 3
0 <= low_storage_factor_Basin_#3_ <= 1
0 <= low_storage_factor_Basin_#7_ <= 1
flow_(LevelBoundary_#1,_TabulatedRatingCurve_#2)_ = 0.00576
flow_(TabulatedRatingCurve_#2,_Basin_#3)_ = 0.00576
0 <= flow_(Basin_#3,_UserDemand_#4)_ <= 0.00288
0 <= flow_(UserDemand_#4,_Basin_#7)_ <= 0.00288
0 <= flow_(Basin_#7,_UserDemand_#8)_ <= 0.00576
0 <= flow_(UserDemand_#8,_Basin_#7)_ <= 0.00576
0 <= flow_(Basin_#3,_UserDemand_#6)_ <= 0.00288
0 <= flow_(UserDemand_#6,_Basin_#7)_ <= 0.00288
boundary_level_LevelBoundary_#1_ = 2
0 <= user_demand_allocated_UserDemand_#4,3_ <= 0.00288
0 <= user_demand_allocated_UserDemand_#6,1_ <= 0.00288
0 <= user_demand_allocated_UserDemand_#8,4_ <= 0.00576
0 <= user_demand_error_UserDemand_#4,3,first_ <= 1
0 <= user_demand_error_UserDemand_#4,3,second_ <= 1
0 <= user_demand_error_UserDemand_#6,1,first_ <= 1
0 <= user_demand_error_UserDemand_#6,1,second_ <= 1
0 <= user_demand_error_UserDemand_#8,4,first_ <= 1
0 <= user_demand_error_UserDemand_#8,4,second_ <= 1
0 <= flow_demand_allocated_TabulatedRatingCurve_#2,2_ <= 0.00576
0 <= flow_demand_extra_TabulatedRatingCurve_#2_ <= 0.00576
0 <= flow_demand_error_TabulatedRatingCurve_#2,2,first_ <= 1
0 <= flow_demand_error_TabulatedRatingCurve_#2,2,second_ <= 1
0 <= average_flow_unit_error_1_ <= 1
0 <= average_flow_unit_error_2_ <= 1
0 <= average_flow_unit_error_3_ <= 1
0 <= average_flow_unit_error_4_ <= 1
End

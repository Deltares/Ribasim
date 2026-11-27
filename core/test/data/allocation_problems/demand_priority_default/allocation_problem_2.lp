minimize
obj: 1000 flow_(LevelBoundary_#1,_TabulatedRatingCurve_#2)_ - 10 flow_(TabulatedRatingCurve_#2,_Basin_#3)_
subject to
c1: -1 low_storage_factor_Basin_#3_ <= -1
c2: 0.3333333333333333 user_demand_error_UserDemand_#4,1,first_ + 0.6666666666666666 flow_demand_error_TabulatedRatingCurve_#2,1,first_ <= 0.3346289803116412
c3: 1 user_demand_error_UserDemand_#4,1,second_ + 1 flow_demand_error_TabulatedRatingCurve_#2,1,second_ <= 0.16731449015582062
c4: 1 level_demand_error_Basin_#3,2,lower,first_ + 1 level_demand_error_Basin_#3,2,upper,first_ <= 0
c5: 1 level_demand_error_Basin_#3,2,lower,second_ + 1 level_demand_error_Basin_#3,2,upper,second_ <= 0
user_demand_relative_error_constraint_UserDemand_#4,1_: 1 user_demand_allocated_UserDemand_#4,1_ + 0.04348550167065053 user_demand_error_UserDemand_#4,1,first_ >= 0.04348550167065053
flow_demand_relative_error_constraint_TabulatedRatingCurve_#2,1_: 1 flow_demand_allocated_TabulatedRatingCurve_#2,1_ + 0.08697100334130106 flow_demand_error_TabulatedRatingCurve_#2,1,first_ >= 0.08697100334130106
storage_constraint_lower_Basin_#3,2_: 1 basin_storage_change_Basin_#3_ + 1 level_demand_error_Basin_#3,2,lower,first_ >= -0.6578548867083167
storage_constraint_upper_Basin_#3,2_: -1 basin_storage_change_Basin_#3_ + 1 level_demand_error_Basin_#3,2,upper,first_ >= -0.6842902265833664
user_demand_fairness_error_constraint_UserDemand_#4,1_: -1 user_demand_error_UserDemand_#4,1,first_ + 1 user_demand_error_UserDemand_#4,1,second_ + 1 average_flow_unit_error_1_ >= 0
flow_demand_fairness_error_constraint_TabulatedRatingCurve_#2,1_: -1 flow_demand_error_TabulatedRatingCurve_#2,1,first_ + 1 flow_demand_error_TabulatedRatingCurve_#2,1,second_ + 1 average_flow_unit_error_1_ >= 0
level_demand_fairness_error_constraint_Basin_#3,2,lower_: -1 level_demand_error_Basin_#3,2,lower,first_ + 1 level_demand_error_Basin_#3,2,lower,second_ + 1 average_storage_unit_error_2,lower_ >= 0
level_demand_fairness_error_constraint_Basin_#3,2,upper_: -1 level_demand_error_Basin_#3,2,upper,first_ + 1 level_demand_error_Basin_#3,2,upper,second_ + 1 average_storage_unit_error_2,upper_ >= 0
flow_conservation_tabulated_rating_curve_TabulatedRatingCurve_#2_: 1 flow_(LevelBoundary_#1,_TabulatedRatingCurve_#2)_ - 1 flow_(TabulatedRatingCurve_#2,_Basin_#3)_ = 0
volume_conservation_Basin_#3_: 1 basin_storage_change_Basin_#3_ - 1 flow_(TabulatedRatingCurve_#2,_Basin_#3)_ + 1 flow_(Basin_#3,_UserDemand_#4)_ = 0
tabulated_rating_curve_constraint_TabulatedRatingCurve_#2_: 4.858879619525992 basin_storage_change_Basin_#3_ + 1 flow_(LevelBoundary_#1,_TabulatedRatingCurve_#2)_ = 0.04249520116520274
user_demand_allocated_sum_constraint_UserDemand_#4_: 1 flow_(Basin_#3,_UserDemand_#4)_ - 1 user_demand_allocated_UserDemand_#4,1_ = 0
user_demand_return_flow_UserDemand_#4_: -1 flow_(Basin_#3,_UserDemand_#4)_ + 1 flow_(UserDemand_#4,_Terminal_#7)_ = 0
flow_demand_allocated_sum_constraint_TabulatedRatingCurve_#2_: 1 flow_(LevelBoundary_#1,_TabulatedRatingCurve_#2)_ - 1 flow_demand_allocated_TabulatedRatingCurve_#2,1_ - 1 flow_demand_extra_TabulatedRatingCurve_#2_ = 0
average_flow_unit_error_constraint_1_: -0.3333333333333333 user_demand_error_UserDemand_#4,1,first_ - 0.6666666666666666 flow_demand_error_TabulatedRatingCurve_#2,1,first_ + 1 average_flow_unit_error_1_ = 0
average_storage_unit_error_constraint_2,upper_: -1 level_demand_error_Basin_#3,2,upper,first_ + 1 average_storage_unit_error_2,upper_ = 0
average_storage_unit_error_constraint_2,lower_: -1 level_demand_error_Basin_#3,2,lower,first_ + 1 average_storage_unit_error_2,lower_ = 0
Bounds
basin_storage_change_Basin_#3_ >= -1.3289274433541582
0 <= low_storage_factor_Basin_#3_ <= 1
flow_(LevelBoundary_#1,_TabulatedRatingCurve_#2)_ free
flow_(TabulatedRatingCurve_#2,_Basin_#3)_ free
0 <= flow_(Basin_#3,_UserDemand_#4)_ <= 0.04348550167065053
0 <= flow_(UserDemand_#4,_Terminal_#7)_ <= 0.04348550167065053
0 <= user_demand_allocated_UserDemand_#4,1_ <= 0.04348550167065053
0 <= user_demand_error_UserDemand_#4,1,first_ <= 1
0 <= user_demand_error_UserDemand_#4,1,second_ <= 1
-infinity <= flow_demand_allocated_TabulatedRatingCurve_#2,1_ <= 0.08697100334130106
flow_demand_extra_TabulatedRatingCurve_#2_ >= 0
0 <= flow_demand_error_TabulatedRatingCurve_#2,1,first_ <= 1
0 <= flow_demand_error_TabulatedRatingCurve_#2,1,second_ <= 1
level_demand_error_Basin_#3,2,lower,first_ >= 0
level_demand_error_Basin_#3,2,lower,second_ >= 0
level_demand_error_Basin_#3,2,upper,first_ >= 0
level_demand_error_Basin_#3,2,upper,second_ >= 0
0 <= average_flow_unit_error_1_ <= 1
average_storage_unit_error_2,lower_ >= 0
average_storage_unit_error_2,upper_ >= 0
End

minimize
obj: 1 flow_change_TabulatedRatingCurve_#3_
subject to
tabulated_rating_curve_capacity_constraint_TabulatedRatingCurve_#3_: 1 flow_(Basin_#2,_TabulatedRatingCurve_#3)_ <= 0
c2: -1 low_storage_factor_Basin_#2_ - 1 low_storage_factor_Basin_#4_ <= -2
c3: 1 level_demand_error_Basin_#4,1,lower,first_ + 1 level_demand_error_Basin_#4,1,upper,first_ <= 0.4646840148698885
c4: 1 level_demand_error_Basin_#4,1,lower,second_ + 1 level_demand_error_Basin_#4,1,upper,second_ <= 0
c5: -10 flow_(TabulatedRatingCurve_#3,_Basin_#4)_ <= 0
storage_constraint_lower_Basin_#4,1_: 1 basin_storage_change_Basin_#4_ + 1 level_demand_error_Basin_#4,1,lower,first_ >= 0.4646840148698885
storage_constraint_upper_Basin_#4,1_: -1 basin_storage_change_Basin_#4_ + 1 level_demand_error_Basin_#4,1,upper,first_ >= -0.5111524163568774
level_demand_fairness_error_constraint_Basin_#4,1,lower_: -1 level_demand_error_Basin_#4,1,lower,first_ + 1 level_demand_error_Basin_#4,1,lower,second_ + 1 average_storage_unit_error_1,lower_ >= 0
level_demand_fairness_error_constraint_Basin_#4,1,upper_: -1 level_demand_error_Basin_#4,1,upper,first_ + 1 level_demand_error_Basin_#4,1,upper,second_ + 1 average_storage_unit_error_1,upper_ >= 0
flow_change_constraint_TabulatedRatingCurve_#3,_1_: 1 flow_(Basin_#2,_TabulatedRatingCurve_#3)_ + 1 flow_change_TabulatedRatingCurve_#3_ >= 0
flow_change_constraint_TabulatedRatingCurve_#3,1_: -1 flow_(Basin_#2,_TabulatedRatingCurve_#3)_ + 1 flow_change_TabulatedRatingCurve_#3_ >= 0
flow_conservation_tabulated_rating_curve_TabulatedRatingCurve_#3_: 1 flow_(Basin_#2,_TabulatedRatingCurve_#3)_ - 1 flow_(TabulatedRatingCurve_#3,_Basin_#4)_ = 0
volume_conservation_Basin_#2_: 1 basin_storage_change_Basin_#2_ - 1 flow_(FlowBoundary_#1,_Basin_#2)_ + 1 flow_(Basin_#2,_TabulatedRatingCurve_#3)_ = 0
volume_conservation_Basin_#4_: 1 basin_storage_change_Basin_#4_ - 1 flow_(TabulatedRatingCurve_#3,_Basin_#4)_ = 0
average_storage_unit_error_constraint_1,upper_: -1 level_demand_error_Basin_#4,1,upper,first_ + 1 average_storage_unit_error_1,upper_ = 0
average_storage_unit_error_constraint_1,lower_: -1 level_demand_error_Basin_#4,1,lower,first_ + 1 average_storage_unit_error_1,lower_ = 0
Bounds
basin_storage_change_Basin_#2_ >= -0.9795539033457249
basin_storage_change_Basin_#4_ >= -0.6970260223048327
0 <= low_storage_factor_Basin_#2_ <= 1
0 <= low_storage_factor_Basin_#4_ <= 1
flow_(FlowBoundary_#1,_Basin_#2)_ = 0.030111524163568774
flow_(Basin_#2,_TabulatedRatingCurve_#3)_ >= 0
flow_(TabulatedRatingCurve_#3,_Basin_#4)_ >= 0
level_demand_error_Basin_#4,1,lower,first_ >= 0
level_demand_error_Basin_#4,1,lower,second_ >= 0
level_demand_error_Basin_#4,1,upper,first_ >= 0
level_demand_error_Basin_#4,1,upper,second_ >= 0
average_storage_unit_error_1,lower_ >= 0
average_storage_unit_error_1,upper_ >= 0
flow_change_TabulatedRatingCurve_#3_ >= 0
End

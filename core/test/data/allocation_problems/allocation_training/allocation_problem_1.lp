minimize
obj: 
subject to
user_demand_relative_error_constraint_UserDemand_#6,4_: 1 user_demand_allocated_UserDemand_#6,4_ + 2 user_demand_error_UserDemand_#6,4,first_ >= 2
user_demand_relative_error_constraint_UserDemand_#9,3_: 1 user_demand_allocated_UserDemand_#9,3_ + 2 user_demand_error_UserDemand_#9,3,first_ >= 2
user_demand_relative_error_constraint_UserDemand_#10,2_: 1 user_demand_allocated_UserDemand_#10,2_ + 2 user_demand_error_UserDemand_#10,2,first_ >= 2
storage_constraint_lower_Basin_#7,1_: 1 basin_storage_change_Basin_#7_ + 1 level_demand_error_Basin_#7,1,lower,first_ >= -250
storage_constraint_upper_Basin_#7,1_: -1 basin_storage_change_Basin_#7_ + 1 level_demand_error_Basin_#7,1,upper,first_ >= -750
user_demand_fairness_error_constraint_UserDemand_#6,4_: -1 user_demand_error_UserDemand_#6,4,first_ + 1 user_demand_error_UserDemand_#6,4,second_ + 1 average_flow_unit_error_4_ >= 0
user_demand_fairness_error_constraint_UserDemand_#9,3_: -1 user_demand_error_UserDemand_#9,3,first_ + 1 user_demand_error_UserDemand_#9,3,second_ + 1 average_flow_unit_error_3_ >= 0
user_demand_fairness_error_constraint_UserDemand_#10,2_: -1 user_demand_error_UserDemand_#10,2,first_ + 1 user_demand_error_UserDemand_#10,2,second_ + 1 average_flow_unit_error_2_ >= 0
level_demand_fairness_error_constraint_Basin_#7,1,lower_: -0.001 level_demand_error_Basin_#7,1,lower,first_ + 1 level_demand_error_Basin_#7,1,lower,second_ + 1 average_storage_unit_error_1,lower_ >= 0
level_demand_fairness_error_constraint_Basin_#7,1,upper_: -0.001 level_demand_error_Basin_#7,1,upper,first_ + 1 level_demand_error_Basin_#7,1,upper,second_ + 1 average_storage_unit_error_1,upper_ >= 0
flow_conservation_tabulated_rating_curve_TabulatedRatingCurve_#4_: 1 flow_(Basin_#3,_TabulatedRatingCurve_#4)_ - 1 flow_(TabulatedRatingCurve_#4,_Terminal_#5)_ = 0
flow_conservation_tabulated_rating_curve_TabulatedRatingCurve_#8_: 1 flow_(Basin_#7,_TabulatedRatingCurve_#8)_ - 1 flow_(TabulatedRatingCurve_#8,_Basin_#3)_ = 0
volume_conservation_Basin_#3_: 1 basin_storage_change_Basin_#3_ + 1 low_storage_factor_Basin_#3_ - 1 flow_(FlowBoundary_#2,_Basin_#3)_ - 1 flow_(UserDemand_#6,_Basin_#3)_ - 1 flow_(UserDemand_#9,_Basin_#3)_ - 1 flow_(TabulatedRatingCurve_#8,_Basin_#3)_ + 1 flow_(Basin_#3,_TabulatedRatingCurve_#4)_ - 1 flow_(UserDemand_#10,_Basin_#3)_ = 1
volume_conservation_Basin_#7_: 1 basin_storage_change_Basin_#7_ + 1 low_storage_factor_Basin_#7_ - 1 flow_(FlowBoundary_#1,_Basin_#7)_ + 1 flow_(Basin_#7,_UserDemand_#6)_ + 1 flow_(Basin_#7,_UserDemand_#9)_ + 1 flow_(Basin_#7,_TabulatedRatingCurve_#8)_ + 1 flow_(Basin_#7,_UserDemand_#10)_ = 1
tabulated_rating_curve_constraint_TabulatedRatingCurve_#4_: -0.01 basin_storage_change_Basin_#3_ + 1 flow_(Basin_#3,_TabulatedRatingCurve_#4)_ = 1
tabulated_rating_curve_constraint_TabulatedRatingCurve_#8_: 0.01 basin_storage_change_Basin_#3_ - 0.01 basin_storage_change_Basin_#7_ + 1 flow_(Basin_#7,_TabulatedRatingCurve_#8)_ = 1
c7: 1 flow_(Basin_#7,_UserDemand_#6)_ - 1 user_demand_allocated_UserDemand_#6,4_ = 0
c8: 1 flow_(Basin_#7,_UserDemand_#9)_ - 1 user_demand_allocated_UserDemand_#9,3_ = 0
c9: 1 flow_(Basin_#7,_UserDemand_#10)_ - 1 user_demand_allocated_UserDemand_#10,2_ = 0
user_demand_return_flow_UserDemand_#6_: -0.5 flow_(Basin_#7,_UserDemand_#6)_ + 1 flow_(UserDemand_#6,_Basin_#3)_ = 0
user_demand_return_flow_UserDemand_#9_: -0.5 flow_(Basin_#7,_UserDemand_#9)_ + 1 flow_(UserDemand_#9,_Basin_#3)_ = 0
user_demand_return_flow_UserDemand_#10_: -0.5 flow_(Basin_#7,_UserDemand_#10)_ + 1 flow_(UserDemand_#10,_Basin_#3)_ = 0
average_flow_unit_error_constraint_2_: -1 user_demand_error_UserDemand_#10,2,first_ + 1 average_flow_unit_error_2_ = 0
average_flow_unit_error_constraint_3_: -1 user_demand_error_UserDemand_#9,3,first_ + 1 average_flow_unit_error_3_ = 0
average_flow_unit_error_constraint_4_: -1 user_demand_error_UserDemand_#6,4,first_ + 1 average_flow_unit_error_4_ = 0
average_storage_unit_error_constraint_1,upper_: -1 level_demand_error_Basin_#7,1,upper,first_ + 1000 average_storage_unit_error_1,upper_ = 0
average_storage_unit_error_constraint_1,lower_: -1 level_demand_error_Basin_#7,1,lower,first_ + 1000 average_storage_unit_error_1,lower_ = 0
Bounds
-1.9815124884824588e-5 <= basin_storage_change_Basin_#3_ <= 7.926049953929835e-5
-1.9815124884824588e-5 <= basin_storage_change_Basin_#7_ <= 7.926049953929835e-5
0 <= low_storage_factor_Basin_#3_ <= 1
0 <= low_storage_factor_Basin_#7_ <= 1
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
0 <= user_demand_allocated_UserDemand_#6,4_ <= 2
0 <= user_demand_allocated_UserDemand_#9,3_ <= 2
0 <= user_demand_allocated_UserDemand_#10,2_ <= 2
0 <= user_demand_error_UserDemand_#6,4,first_ <= 1
0 <= user_demand_error_UserDemand_#6,4,second_ <= 1
0 <= user_demand_error_UserDemand_#9,3,first_ <= 1
0 <= user_demand_error_UserDemand_#9,3,second_ <= 1
0 <= user_demand_error_UserDemand_#10,2,first_ <= 1
0 <= user_demand_error_UserDemand_#10,2,second_ <= 1
level_demand_error_Basin_#7,1,lower,first_ >= 0
level_demand_error_Basin_#7,1,lower,second_ >= 0
level_demand_error_Basin_#7,1,upper,first_ >= 0
level_demand_error_Basin_#7,1,upper,second_ >= 0
0 <= average_flow_unit_error_2_ <= 1
0 <= average_flow_unit_error_3_ <= 1
0 <= average_flow_unit_error_4_ <= 1
average_storage_unit_error_1,lower_ >= 0
average_storage_unit_error_1,upper_ >= 0
End

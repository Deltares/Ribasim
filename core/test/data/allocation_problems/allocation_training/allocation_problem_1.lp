minimize
obj: -10 flow_(TabulatedRatingCurve_#4,_Terminal_#5)_ - 10 flow_(TabulatedRatingCurve_#8,_Basin_#3)_
subject to
c1: -1 low_storage_factor_Basin_#3_ - 1 low_storage_factor_Basin_#7_ <= -2
c2: 1 level_demand_error_Basin_#7,1,lower,first_ + 1 level_demand_error_Basin_#7,1,upper,first_ <= 0
c3: 1 level_demand_error_Basin_#7,1,lower,second_ + 1 level_demand_error_Basin_#7,1,upper,second_ <= 0
c4: 1 user_demand_error_UserDemand_#10,2,first_ <= 0
c5: 1 user_demand_error_UserDemand_#10,2,second_ <= 0
c6: 1 user_demand_error_UserDemand_#9,3,first_ <= 0
c7: 1 user_demand_error_UserDemand_#9,3,second_ <= 0
user_demand_relative_error_constraint_UserDemand_#6,4_: 1 user_demand_allocated_UserDemand_#6,4_ >= 0
user_demand_relative_error_constraint_UserDemand_#9,3_: 1 user_demand_allocated_UserDemand_#9,3_ + 0.001382890544212067 user_demand_error_UserDemand_#9,3,first_ >= 0.001382890544212067
user_demand_relative_error_constraint_UserDemand_#10,2_: 1 user_demand_allocated_UserDemand_#10,2_ + 0.002765781088424134 user_demand_error_UserDemand_#10,2,first_ >= 0.002765781088424134
storage_constraint_lower_Basin_#7,1_: 1 basin_storage_change_Basin_#7_ + 1 level_demand_error_Basin_#7,1,lower,first_ >= -0.7669512111870566
storage_constraint_upper_Basin_#7,1_: -1 basin_storage_change_Basin_#7_ + 1 level_demand_error_Basin_#7,1,upper,first_ >= -0.907242665254867
user_demand_fairness_error_constraint_UserDemand_#6,4_: -1 user_demand_error_UserDemand_#6,4,first_ + 1 user_demand_error_UserDemand_#6,4,second_ + 1 average_flow_unit_error_4_ >= 0
user_demand_fairness_error_constraint_UserDemand_#9,3_: -1 user_demand_error_UserDemand_#9,3,first_ + 1 user_demand_error_UserDemand_#9,3,second_ + 1 average_flow_unit_error_3_ >= 0
user_demand_fairness_error_constraint_UserDemand_#10,2_: -1 user_demand_error_UserDemand_#10,2,first_ + 1 user_demand_error_UserDemand_#10,2,second_ + 1 average_flow_unit_error_2_ >= 0
level_demand_fairness_error_constraint_Basin_#7,1,lower_: -1 level_demand_error_Basin_#7,1,lower,first_ + 1 level_demand_error_Basin_#7,1,lower,second_ + 1 average_storage_unit_error_1,lower_ >= 0
level_demand_fairness_error_constraint_Basin_#7,1,upper_: -1 level_demand_error_Basin_#7,1,upper,first_ + 1 level_demand_error_Basin_#7,1,upper,second_ + 1 average_storage_unit_error_1,upper_ >= 0
flow_conservation_tabulated_rating_curve_TabulatedRatingCurve_#4_: 1 flow_(Basin_#3,_TabulatedRatingCurve_#4)_ - 1 flow_(TabulatedRatingCurve_#4,_Terminal_#5)_ = 0
flow_conservation_tabulated_rating_curve_TabulatedRatingCurve_#8_: 1 flow_(Basin_#7,_TabulatedRatingCurve_#8)_ - 1 flow_(TabulatedRatingCurve_#8,_Basin_#3)_ = 0
volume_conservation_Basin_#3_: 1 basin_storage_change_Basin_#3_ - 1 flow_(FlowBoundary_#2,_Basin_#3)_ - 1 flow_(UserDemand_#6,_Basin_#3)_ - 1 flow_(UserDemand_#9,_Basin_#3)_ - 1 flow_(TabulatedRatingCurve_#8,_Basin_#3)_ + 1 flow_(Basin_#3,_TabulatedRatingCurve_#4)_ - 1 flow_(UserDemand_#10,_Basin_#3)_ = 0
volume_conservation_Basin_#7_: 1 basin_storage_change_Basin_#7_ - 1 flow_(FlowBoundary_#1,_Basin_#7)_ + 1 flow_(Basin_#7,_UserDemand_#6)_ + 1 flow_(Basin_#7,_UserDemand_#9)_ + 1 flow_(Basin_#7,_TabulatedRatingCurve_#8)_ + 1 flow_(Basin_#7,_UserDemand_#10)_ = 0
user_demand_allocated_sum_constraint_UserDemand_#6_: 1 flow_(Basin_#7,_UserDemand_#6)_ - 1 user_demand_allocated_UserDemand_#6,4_ = 0
user_demand_allocated_sum_constraint_UserDemand_#9_: 1 flow_(Basin_#7,_UserDemand_#9)_ - 1 user_demand_allocated_UserDemand_#9,3_ = 0
user_demand_allocated_sum_constraint_UserDemand_#10_: 1 flow_(Basin_#7,_UserDemand_#10)_ - 1 user_demand_allocated_UserDemand_#10,2_ = 0
user_demand_return_flow_UserDemand_#6_: 1 flow_(UserDemand_#6,_Basin_#3)_ = 0
user_demand_return_flow_UserDemand_#9_: -0.4 flow_(Basin_#7,_UserDemand_#9)_ + 1 flow_(UserDemand_#9,_Basin_#3)_ = 0
user_demand_return_flow_UserDemand_#10_: -0.5 flow_(Basin_#7,_UserDemand_#10)_ + 1 flow_(UserDemand_#10,_Basin_#3)_ = 0
average_flow_unit_error_constraint_2_: -1 user_demand_error_UserDemand_#10,2,first_ + 1 average_flow_unit_error_2_ = 0
average_flow_unit_error_constraint_3_: -1 user_demand_error_UserDemand_#9,3,first_ + 1 average_flow_unit_error_3_ = 0
average_flow_unit_error_constraint_4_: 1 average_flow_unit_error_4_ = 0
average_storage_unit_error_constraint_1,upper_: -1 level_demand_error_Basin_#7,1,upper,first_ + 1 average_storage_unit_error_1,upper_ = 0
average_storage_unit_error_constraint_1,lower_: -1 level_demand_error_Basin_#7,1,lower,first_ + 1 average_storage_unit_error_1,lower_ = 0
tabulated_rating_curve_constraint_TabulatedRatingCurve_#4_: -0.46298051358305814 basin_storage_change_Basin_#3_ - 0.07472900879666527 low_storage_factor_Basin_#3_ + 1 flow_(Basin_#3,_TabulatedRatingCurve_#4)_ = 0
tabulated_rating_curve_constraint_TabulatedRatingCurve_#8_: -0.05625758431130497 basin_storage_change_Basin_#7_ - 0.08500518638839413 low_storage_factor_Basin_#7_ + 1 flow_(Basin_#7,_TabulatedRatingCurve_#8)_ = 0
Bounds
basin_storage_change_Basin_#3_ >= -0.15041320931626825
basin_storage_change_Basin_#7_ >= -1.6955853817492164
0 <= low_storage_factor_Basin_#3_ <= 1
0 <= low_storage_factor_Basin_#7_ <= 1
flow_(FlowBoundary_#1,_Basin_#7)_ = 0.03270536137061538
flow_(FlowBoundary_#2,_Basin_#3)_ = 0.0001382890544212067
flow_(Basin_#7,_UserDemand_#6)_ = 0
flow_(UserDemand_#6,_Basin_#3)_ = 0
0 <= flow_(Basin_#7,_UserDemand_#9)_ <= 0.001382890544212067
0 <= flow_(UserDemand_#9,_Basin_#3)_ <= 0.001382890544212067
flow_(Basin_#7,_TabulatedRatingCurve_#8)_ free
flow_(TabulatedRatingCurve_#8,_Basin_#3)_ free
flow_(Basin_#3,_TabulatedRatingCurve_#4)_ free
0 <= flow_(Basin_#7,_UserDemand_#10)_ <= 0.002765781088424134
0 <= flow_(UserDemand_#10,_Basin_#3)_ <= 0.002765781088424134
flow_(TabulatedRatingCurve_#4,_Terminal_#5)_ free
user_demand_allocated_UserDemand_#6,4_ = 0
0 <= user_demand_allocated_UserDemand_#9,3_ <= 0.001382890544212067
0 <= user_demand_allocated_UserDemand_#10,2_ <= 0.002765781088424134
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

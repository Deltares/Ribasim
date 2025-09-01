minimize
obj: 
subject to
user_demand_relative_error_constraint_UserDemand_#3,1_: 1 user_demand_allocated_UserDemand_#3,1_ + 2 user_demand_error_UserDemand_#3,1,first_ >= 2
user_demand_relative_error_constraint_UserDemand_#6,3_: 1 user_demand_allocated_UserDemand_#6,3_ + 2 user_demand_error_UserDemand_#6,3,first_ >= 2
user_demand_fairness_error_constraint_UserDemand_#3,1_: -1 user_demand_error_UserDemand_#3,1,first_ + 1 user_demand_error_UserDemand_#3,1,second_ + 1 average_flow_unit_error_1_ >= 0
user_demand_fairness_error_constraint_UserDemand_#6,3_: -1 user_demand_error_UserDemand_#6,3,first_ + 1 user_demand_error_UserDemand_#6,3,second_ + 1 average_flow_unit_error_3_ >= 0
flow_conservation_linear_resistance_LinearResistance_#4_: 1 flow_(Basin_#2,_LinearResistance_#4)_ - 1 flow_(LinearResistance_#4,_Basin_#5)_ = 0
flow_conservation_tabulated_rating_curve_TabulatedRatingCurve_#7_: 1 flow_(Basin_#5,_TabulatedRatingCurve_#7)_ - 1 flow_(TabulatedRatingCurve_#7,_Terminal_#8)_ = 0
volume_conservation_Basin_#2_: 1 basin_storage_change_Basin_#2_ + 1 low_storage_factor_Basin_#2_ - 1 flow_(FlowBoundary_#1,_Basin_#2)_ + 1 flow_(Basin_#2,_UserDemand_#3)_ + 1 flow_(Basin_#2,_LinearResistance_#4)_ - 1 flow_(UserDemand_#3,_Basin_#2)_ = 1
volume_conservation_Basin_#5_: 1 basin_storage_change_Basin_#5_ + 1 low_storage_factor_Basin_#5_ - 1 flow_(LinearResistance_#4,_Basin_#5)_ + 1 flow_(Basin_#5,_UserDemand_#6)_ + 1 flow_(Basin_#5,_TabulatedRatingCurve_#7)_ - 1 flow_(UserDemand_#6,_Basin_#5)_ = 1
tabulated_rating_curve_constraint_TabulatedRatingCurve_#7_: -0.01 basin_storage_change_Basin_#5_ + 1 flow_(Basin_#5,_TabulatedRatingCurve_#7)_ = 1
linear_resistance_constraint_LinearResistance_#4_: -0.01 basin_storage_change_Basin_#2_ + 0.01 basin_storage_change_Basin_#5_ + 1 flow_(Basin_#2,_LinearResistance_#4)_ = 1
c7: 1 flow_(Basin_#2,_UserDemand_#3)_ - 1 user_demand_allocated_UserDemand_#3,1_ = 0
c8: 1 flow_(Basin_#5,_UserDemand_#6)_ - 1 user_demand_allocated_UserDemand_#6,3_ = 0
user_demand_return_flow_UserDemand_#3_: -0.5 flow_(Basin_#2,_UserDemand_#3)_ + 1 flow_(UserDemand_#3,_Basin_#2)_ = 0
user_demand_return_flow_UserDemand_#6_: -0.5 flow_(Basin_#5,_UserDemand_#6)_ + 1 flow_(UserDemand_#6,_Basin_#5)_ = 0
average_flow_unit_error_constraint_1_: -1 user_demand_error_UserDemand_#3,1,first_ + 1 average_flow_unit_error_1_ = 0
average_flow_unit_error_constraint_3_: -1 user_demand_error_UserDemand_#6,3,first_ + 1 average_flow_unit_error_3_ = 0
Bounds
-0.006666666666666667 <= basin_storage_change_Basin_#2_ <= 0.02666666666666667
-0.006666666666666667 <= basin_storage_change_Basin_#5_ <= 0.02666666666666667
0 <= low_storage_factor_Basin_#2_ <= 1
0 <= low_storage_factor_Basin_#5_ <= 1
0 <= flow_(FlowBoundary_#1,_Basin_#2)_ <= 288000
0 <= flow_(Basin_#2,_UserDemand_#3)_ <= 288000
-288000 <= flow_(Basin_#2,_LinearResistance_#4)_ <= 288000
-288000 <= flow_(LinearResistance_#4,_Basin_#5)_ <= 288000
0 <= flow_(Basin_#5,_UserDemand_#6)_ <= 288000
0 <= flow_(Basin_#5,_TabulatedRatingCurve_#7)_ <= 288000
0 <= flow_(TabulatedRatingCurve_#7,_Terminal_#8)_ <= 288000
0 <= flow_(UserDemand_#3,_Basin_#2)_ <= 288000
0 <= flow_(UserDemand_#6,_Basin_#5)_ <= 288000
0 <= user_demand_allocated_UserDemand_#3,1_ <= 2
0 <= user_demand_allocated_UserDemand_#6,3_ <= 2
0 <= user_demand_error_UserDemand_#3,1,first_ <= 1
0 <= user_demand_error_UserDemand_#3,1,second_ <= 1
0 <= user_demand_error_UserDemand_#6,3,first_ <= 1
0 <= user_demand_error_UserDemand_#6,3,second_ <= 1
0 <= average_flow_unit_error_1_ <= 1
0 <= average_flow_unit_error_3_ <= 1
End

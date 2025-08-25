minimize
obj: 
subject to
user_demand_relative_error_constraint_UserDemand_#32,1_: 1 user_demand_allocated_UserDemand_#32,1_ + 2 user_demand_error_UserDemand_#32,1,first_ >= 2
user_demand_fairness_error_constraint_UserDemand_#32,1_: -1 user_demand_error_UserDemand_#32,1,first_ + 1 user_demand_error_UserDemand_#32,1,second_ + 1 average_flow_unit_error_1_ >= 0
flow_conservation_tabulated_rating_curve_TabulatedRatingCurve_#26_: 1 flow_(Basin_#25,_TabulatedRatingCurve_#26)_ - 1 flow_(TabulatedRatingCurve_#26,_Basin_#31)_ = 0
volume_conservation_Basin_#25_: 1 basin_storage_change_Basin_#25_ + 1 low_storage_factor_Basin_#25_ + 1 flow_(Basin_#25,_TabulatedRatingCurve_#26)_ = 1
volume_conservation_Basin_#31_: 1 basin_storage_change_Basin_#31_ + 1 low_storage_factor_Basin_#31_ - 1 flow_(TabulatedRatingCurve_#26,_Basin_#31)_ + 1 flow_(Basin_#31,_UserDemand_#32)_ - 1 flow_(UserDemand_#32,_Basin_#31)_ = 1
tabulated_rating_curve_constraint_TabulatedRatingCurve_#26_: -0.01 basin_storage_change_Basin_#25_ + 0.01 basin_storage_change_Basin_#31_ + 1 flow_(Basin_#25,_TabulatedRatingCurve_#26)_ = 1
c5: 1 flow_(Basin_#31,_UserDemand_#32)_ - 1 user_demand_allocated_UserDemand_#32,1_ = 0
user_demand_return_flow_UserDemand_#32_: -0.5 flow_(Basin_#31,_UserDemand_#32)_ + 1 flow_(UserDemand_#32,_Basin_#31)_ = 0
average_flow_unit_error_constraint_1_: -1 user_demand_error_UserDemand_#32,1,first_ + 1 average_flow_unit_error_1_ = 0
Bounds
-2 <= basin_storage_change_Basin_#25_ <= 8
-2 <= basin_storage_change_Basin_#31_ <= 8
0 <= low_storage_factor_Basin_#25_ <= 1
0 <= low_storage_factor_Basin_#31_ <= 1
0 <= flow_(Pump_#24,_Basin_#25)_ <= 172.8
0 <= flow_(Basin_#25,_TabulatedRatingCurve_#26)_ <= 86400000
0 <= flow_(TabulatedRatingCurve_#26,_Basin_#31)_ <= 86400000
0 <= flow_(Basin_#31,_UserDemand_#32)_ <= 86400000
0 <= flow_(UserDemand_#32,_Basin_#31)_ <= 86400000
0 <= user_demand_allocated_UserDemand_#32,1_ <= 2
0 <= user_demand_error_UserDemand_#32,1,first_ <= 1
0 <= user_demand_error_UserDemand_#32,1,second_ <= 1
0 <= average_flow_unit_error_1_ <= 1
End

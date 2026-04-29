minimize
obj: 
subject to
user_demand_relative_error_constraint_UserDemand_#3,1_: 1 user_demand_allocated_UserDemand_#3,1_ + 2 user_demand_error_UserDemand_#3,1,first_ >= 2
user_demand_fairness_error_constraint_UserDemand_#3,1_: -1 user_demand_error_UserDemand_#3,1,first_ + 1 user_demand_error_UserDemand_#3,1,second_ + 1 average_flow_unit_error_1_ >= 0
volume_conservation_Basin_#2_: 1 basin_storage_change_Basin_#2_ + 2.3148148148148148e-6 low_storage_factor_Basin_#2_ - 2.3148148148148148e-6 flow_(FlowBoundary_#1,_Basin_#2)_ + 2.3148148148148148e-6 flow_(Basin_#2,_UserDemand_#3)_ - 2.3148148148148148e-6 flow_(UserDemand_#3,_Basin_#2)_ = 2.3148148148148148e-6
user_demand_allocated_sum_constraint_UserDemand_#3_: 1 flow_(Basin_#2,_UserDemand_#3)_ - 1 user_demand_allocated_UserDemand_#3,1_ = 0
user_demand_return_flow_UserDemand_#3_: -0.5 flow_(Basin_#2,_UserDemand_#3)_ + 1 flow_(UserDemand_#3,_Basin_#2)_ = 0
average_flow_unit_error_constraint_1_: -1 user_demand_error_UserDemand_#3,1,first_ + 1 average_flow_unit_error_1_ = 0
Bounds
-0.00784313725490196 <= basin_storage_change_Basin_#2_ <= 0.03137254901960784
0 <= low_storage_factor_Basin_#2_ <= 1
0 <= flow_(FlowBoundary_#1,_Basin_#2)_ <= 1.6941176470588234e6
0 <= flow_(Basin_#2,_UserDemand_#3)_ <= 1.6941176470588234e6
0 <= flow_(UserDemand_#3,_Basin_#2)_ <= 1.6941176470588234e6
0 <= user_demand_allocated_UserDemand_#3,1_ <= 2
0 <= user_demand_error_UserDemand_#3,1,first_ <= 1
0 <= user_demand_error_UserDemand_#3,1,second_ <= 1
0 <= average_flow_unit_error_1_ <= 1
End

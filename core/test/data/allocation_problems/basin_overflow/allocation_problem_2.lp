minimize
obj: -1 low_storage_factor_Basin_#2_
subject to
c1: 1 user_demand_error_UserDemand_#3,1,first_ <= 0
c2: 1 user_demand_error_UserDemand_#3,1,second_ <= 0
user_demand_relative_error_constraint_UserDemand_#3,1_: 1 user_demand_allocated_UserDemand_#3,1_ + 1.7280000000000002 user_demand_error_UserDemand_#3,1,first_ >= 1.7280000000000002
user_demand_fairness_error_constraint_UserDemand_#3,1_: -1 user_demand_error_UserDemand_#3,1,first_ + 1 user_demand_error_UserDemand_#3,1,second_ + 1 average_flow_unit_error_1_ >= 0
volume_conservation_Basin_#2_: 1 basin_storage_change_Basin_#2_ - 1 flow_(FlowBoundary_#1,_Basin_#2)_ + 1 flow_(Basin_#2,_UserDemand_#3)_ - 1 flow_(UserDemand_#3,_Basin_#2)_ = 0
user_demand_allocated_sum_constraint_UserDemand_#3_: 1 flow_(Basin_#2,_UserDemand_#3)_ - 1 user_demand_allocated_UserDemand_#3,1_ = 0
user_demand_return_flow_UserDemand_#3_: 1 flow_(UserDemand_#3,_Basin_#2)_ = 0
average_flow_unit_error_constraint_1_: -1 user_demand_error_UserDemand_#3,1,first_ + 1 average_flow_unit_error_1_ = 0
Bounds
-1 <= basin_storage_change_Basin_#2_ <= 34.56
0 <= low_storage_factor_Basin_#2_ <= 1
flow_(FlowBoundary_#1,_Basin_#2)_ = 17.28
0 <= flow_(Basin_#2,_UserDemand_#3)_ <= 1.7280000000000002
0 <= flow_(UserDemand_#3,_Basin_#2)_ <= 1.7280000000000002
0 <= user_demand_allocated_UserDemand_#3,1_ <= 1.7280000000000002
0 <= user_demand_error_UserDemand_#3,1,first_ <= 1
0 <= user_demand_error_UserDemand_#3,1,second_ <= 1
0 <= average_flow_unit_error_1_ <= 1
End

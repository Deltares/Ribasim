minimize
obj: 1000 flow_(LevelBoundary_#1,_Outlet_#2)_ + 40 flow_(Outlet_#2,_Basin_#3)_
subject to
c1: -1 low_storage_factor_Basin_#3_ <= -1
user_demand_relative_error_constraint_UserDemand_#4,1_: 1 user_demand_allocated_UserDemand_#4,1_ >= 0
user_demand_fairness_error_constraint_UserDemand_#4,1_: -1 user_demand_error_UserDemand_#4,1,first_ + 1 user_demand_error_UserDemand_#4,1,second_ + 1 average_flow_unit_error_1_ >= 0
flow_conservation_outlet_Outlet_#2_: 1 flow_(LevelBoundary_#1,_Outlet_#2)_ - 1 flow_(Outlet_#2,_Basin_#3)_ = 0
volume_conservation_Basin_#3_: 1 basin_storage_change_Basin_#3_ - 1 flow_(Outlet_#2,_Basin_#3)_ + 1 flow_(Basin_#3,_UserDemand_#4)_ - 1 flow_(UserDemand_#4,_Basin_#3)_ = 0
user_demand_allocated_sum_constraint_UserDemand_#4_: 1 flow_(Basin_#3,_UserDemand_#4)_ - 1 user_demand_allocated_UserDemand_#4,1_ = 0
user_demand_return_flow_UserDemand_#4_: 1 flow_(UserDemand_#4,_Basin_#3)_ = 0
average_flow_unit_error_constraint_1_: 1 average_flow_unit_error_1_ = 0
Bounds
-0.0392156862745098 <= basin_storage_change_Basin_#3_ <= 3.8823529411764706
0 <= low_storage_factor_Basin_#3_ <= 1
0 <= flow_(LevelBoundary_#1,_Outlet_#2)_ <= 304.94117647058823
0 <= flow_(Outlet_#2,_Basin_#3)_ <= 304.94117647058823
flow_(Basin_#3,_UserDemand_#4)_ = 0
flow_(UserDemand_#4,_Basin_#3)_ = 0
boundary_level_LevelBoundary_#1_ = 5
user_demand_allocated_UserDemand_#4,1_ = 0
0 <= user_demand_error_UserDemand_#4,1,first_ <= 1
0 <= user_demand_error_UserDemand_#4,1,second_ <= 1
0 <= average_flow_unit_error_1_ <= 1
End

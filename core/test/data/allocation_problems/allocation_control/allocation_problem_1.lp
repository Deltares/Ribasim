minimize
obj: 
subject to
user_demand_relative_error_constraint_UserDemand_#4,1_: 1 user_demand_allocated_UserDemand_#4,1_ + 2 user_demand_error_UserDemand_#4,1,first_ >= 2
user_demand_fairness_error_constraint_UserDemand_#4,1_: -1 user_demand_error_UserDemand_#4,1,first_ + 1 user_demand_error_UserDemand_#4,1,second_ + 1 average_flow_unit_error_1_ >= 0
flow_conservation_outlet_Outlet_#2_: 1 flow_(LevelBoundary_#1,_Outlet_#2)_ - 1 flow_(Outlet_#2,_Basin_#3)_ = 0
volume_conservation_Basin_#3_: 1 basin_storage_change_Basin_#3_ + 1 low_storage_factor_Basin_#3_ - 1 flow_(Outlet_#2,_Basin_#3)_ + 1 flow_(Basin_#3,_UserDemand_#4)_ - 1 flow_(UserDemand_#4,_Basin_#3)_ = 1
c3: 1 flow_(Basin_#3,_UserDemand_#4)_ - 1 user_demand_allocated_UserDemand_#4,1_ = 0
user_demand_return_flow_UserDemand_#4_: -0.5 flow_(Basin_#3,_UserDemand_#4)_ + 1 flow_(UserDemand_#4,_Basin_#3)_ = 0
average_flow_unit_error_constraint_1_: -1 user_demand_error_UserDemand_#4,1,first_ + 1 average_flow_unit_error_1_ = 0
Bounds
-0.2 <= basin_storage_change_Basin_#3_ <= 0.8
0 <= low_storage_factor_Basin_#3_ <= 1
0 <= flow_(LevelBoundary_#1,_Outlet_#2)_ <= 155.52
0 <= flow_(Outlet_#2,_Basin_#3)_ <= 155.52
0 <= flow_(Basin_#3,_UserDemand_#4)_ <= 8640000
0 <= flow_(UserDemand_#4,_Basin_#3)_ <= 8640000
boundary_level_LevelBoundary_#1_ = 0
0 <= user_demand_allocated_UserDemand_#4,1_ <= 2
0 <= user_demand_error_UserDemand_#4,1,first_ <= 1
0 <= user_demand_error_UserDemand_#4,1,second_ <= 1
0 <= average_flow_unit_error_1_ <= 1
End

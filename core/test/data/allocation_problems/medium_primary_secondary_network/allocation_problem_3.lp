minimize
obj: 
subject to
user_demand_relative_error_constraint_UserDemand_#17,3_: 1 user_demand_allocated_UserDemand_#17,3_ + 2 user_demand_error_UserDemand_#17,3,first_ >= 2
storage_constraint_lower_Basin_#15,2_: 1 basin_storage_change_Basin_#15_ + 1 level_demand_error_Basin_#15,2,lower,first_ >= -250
storage_constraint_upper_Basin_#15,2_: -1 basin_storage_change_Basin_#15_ + 1 level_demand_error_Basin_#15,2,upper,first_ >= -750
user_demand_fairness_error_constraint_UserDemand_#17,3_: -1 user_demand_error_UserDemand_#17,3,first_ + 1 user_demand_error_UserDemand_#17,3,second_ + 1 average_flow_unit_error_3_ >= 0
level_demand_fairness_error_constraint_Basin_#15,2,lower_: -0.001 level_demand_error_Basin_#15,2,lower,first_ + 1 level_demand_error_Basin_#15,2,lower,second_ + 1 average_storage_unit_error_2,lower_ >= 0
level_demand_fairness_error_constraint_Basin_#15,2,upper_: -0.001 level_demand_error_Basin_#15,2,upper,first_ + 1 level_demand_error_Basin_#15,2,upper,second_ + 1 average_storage_unit_error_2,upper_ >= 0
volume_conservation_Basin_#15_: 1 basin_storage_change_Basin_#15_ + 1 low_storage_factor_Basin_#15_ - 1 flow_(Outlet_#8,_Basin_#15)_ - 1 flow_(Outlet_#11,_Basin_#15)_ + 1 flow_(Basin_#15,_UserDemand_#17)_ - 1 flow_(UserDemand_#17,_Basin_#15)_ = 1
user_demand_allocated_sum_constraint_UserDemand_#17_: 1 flow_(Basin_#15,_UserDemand_#17)_ - 1 user_demand_allocated_UserDemand_#17,3_ = 0
user_demand_return_flow_UserDemand_#17_: -0.5 flow_(Basin_#15,_UserDemand_#17)_ + 1 flow_(UserDemand_#17,_Basin_#15)_ = 0
average_flow_unit_error_constraint_3_: -1 user_demand_error_UserDemand_#17,3,first_ + 1 average_flow_unit_error_3_ = 0
average_storage_unit_error_constraint_2,upper_: -1 level_demand_error_Basin_#15,2,upper,first_ + 1000 average_storage_unit_error_2,upper_ = 0
average_storage_unit_error_constraint_2,lower_: -1 level_demand_error_Basin_#15,2,lower,first_ + 1000 average_storage_unit_error_2,lower_ = 0
Bounds
-0.02 <= basin_storage_change_Basin_#15_ <= 0.08
0 <= low_storage_factor_Basin_#15_ <= 1
0 <= flow_(Outlet_#8,_Basin_#15)_ <= 1.728
0 <= flow_(Outlet_#11,_Basin_#15)_ <= 1.728
0 <= flow_(Basin_#15,_UserDemand_#17)_ <= 864000
0 <= flow_(UserDemand_#17,_Basin_#15)_ <= 864000
0 <= user_demand_allocated_UserDemand_#17,3_ <= 2
0 <= user_demand_error_UserDemand_#17,3,first_ <= 1
0 <= user_demand_error_UserDemand_#17,3,second_ <= 1
level_demand_error_Basin_#15,2,lower,first_ >= 0
level_demand_error_Basin_#15,2,lower,second_ >= 0
level_demand_error_Basin_#15,2,upper,first_ >= 0
level_demand_error_Basin_#15,2,upper,second_ >= 0
0 <= average_flow_unit_error_3_ <= 1
average_storage_unit_error_2,lower_ >= 0
average_storage_unit_error_2,upper_ >= 0
End

minimize
obj: -1 low_storage_factor_Basin_#13_
subject to
c1: 1 level_demand_error_Basin_#13,2,lower,first_ + 1 level_demand_error_Basin_#13,2,upper,first_ <= 0
c2: 1 level_demand_error_Basin_#13,2,lower,second_ + 1 level_demand_error_Basin_#13,2,upper,second_ <= 0
c3: 1 user_demand_error_UserDemand_#14,3,first_ <= 0
c4: 1 user_demand_error_UserDemand_#14,3,second_ <= 0
user_demand_relative_error_constraint_UserDemand_#14,3_: 1 user_demand_allocated_UserDemand_#14,3_ + 0.05184 user_demand_error_UserDemand_#14,3,first_ >= 0.05184
storage_constraint_lower_Basin_#13,2_: 1 basin_storage_change_Basin_#13_ + 1 level_demand_error_Basin_#13,2,lower,first_ >= 0
storage_constraint_upper_Basin_#13,2_: -1 basin_storage_change_Basin_#13_ + 1 level_demand_error_Basin_#13,2,upper,first_ >= -0.10000000000000014
user_demand_fairness_error_constraint_UserDemand_#14,3_: -1 user_demand_error_UserDemand_#14,3,first_ + 1 user_demand_error_UserDemand_#14,3,second_ + 1 average_flow_unit_error_3_ >= 0
level_demand_fairness_error_constraint_Basin_#13,2,lower_: -1 level_demand_error_Basin_#13,2,lower,first_ + 1 level_demand_error_Basin_#13,2,lower,second_ + 1 average_storage_unit_error_2,lower_ >= 0
level_demand_fairness_error_constraint_Basin_#13,2,upper_: -1 level_demand_error_Basin_#13,2,upper,first_ + 1 level_demand_error_Basin_#13,2,upper,second_ + 1 average_storage_unit_error_2,upper_ >= 0
volume_conservation_Basin_#13_: 1 basin_storage_change_Basin_#13_ - 1 flow_(Outlet_#3,_Basin_#13)_ - 1 flow_(Pump_#6,_Basin_#13)_ + 1 flow_(Basin_#13,_UserDemand_#14)_ - 1 flow_(UserDemand_#14,_Basin_#13)_ = 0
user_demand_allocated_sum_constraint_UserDemand_#14_: 1 flow_(Basin_#13,_UserDemand_#14)_ - 1 user_demand_allocated_UserDemand_#14,3_ = 0
user_demand_return_flow_UserDemand_#14_: 1 flow_(UserDemand_#14,_Basin_#13)_ = 0
average_flow_unit_error_constraint_3_: -1 user_demand_error_UserDemand_#14,3,first_ + 1 average_flow_unit_error_3_ = 0
average_storage_unit_error_constraint_2,upper_: -1 level_demand_error_Basin_#13,2,upper,first_ + 1 average_storage_unit_error_2,upper_ = 0
average_storage_unit_error_constraint_2,lower_: -1 level_demand_error_Basin_#13,2,lower,first_ + 1 average_storage_unit_error_2,lower_ = 0
Bounds
-1 <= basin_storage_change_Basin_#13_ <= 1
0 <= low_storage_factor_Basin_#13_ <= 1
flow_(Outlet_#3,_Basin_#13)_ = 0.001728
flow_(Pump_#6,_Basin_#13)_ = 0.050112
0 <= flow_(Basin_#13,_UserDemand_#14)_ <= 0.05184
0 <= flow_(UserDemand_#14,_Basin_#13)_ <= 0.05184
0 <= user_demand_allocated_UserDemand_#14,3_ <= 0.05184
0 <= user_demand_error_UserDemand_#14,3,first_ <= 1
0 <= user_demand_error_UserDemand_#14,3,second_ <= 1
level_demand_error_Basin_#13,2,lower,first_ >= 0
level_demand_error_Basin_#13,2,lower,second_ >= 0
level_demand_error_Basin_#13,2,upper,first_ >= 0
level_demand_error_Basin_#13,2,upper,second_ >= 0
0 <= average_flow_unit_error_3_ <= 1
average_storage_unit_error_2,lower_ >= 0
average_storage_unit_error_2,upper_ >= 0
End

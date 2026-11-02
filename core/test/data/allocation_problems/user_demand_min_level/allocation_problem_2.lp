minimize
obj: 50 flow_(Pump_#6,_Terminal_#4)_ + 40 flow_(Outlet_#9,_Basin_#10)_
subject to
user_demand_min_level_constraint_(Basin_#1,_UserDemand_#3): -18.225 basin_storage_change_Basin_#1_ + 1 flow_(Basin_#1,_UserDemand_#3)_ - 1 user_demand_min_level_slack_(Basin_#1,_UserDemand_#3) <= 0.01130294581717258
user_demand_min_level_constraint_(Basin_#10,_UserDemand_#11): -18.225 basin_storage_change_Basin_#10_ + 1 flow_(Basin_#10,_UserDemand_#11)_ - 1 user_demand_min_level_slack_(Basin_#10,_UserDemand_#11) <= 0.00694011412027605
c3: -1 low_storage_factor_Basin_#1_ - 1 low_storage_factor_Basin_#5_ - 1 low_storage_factor_Basin_#8_ - 1 low_storage_factor_Basin_#10_ + 0.001 user_demand_min_level_slack_(Basin_#1,_UserDemand_#3) + 0.001 user_demand_min_level_slack_(Basin_#10,_UserDemand_#11) <= -4
c4: 0.33333333333333337 user_demand_error_UserDemand_#3,1,first_ + 0.33333333333333337 user_demand_error_UserDemand_#7,1,first_ + 0.33333333333333337 user_demand_error_UserDemand_#11,1,first_ <= 0.5752294796157211
c5: 1 user_demand_error_UserDemand_#3,1,second_ + 1 user_demand_error_UserDemand_#7,1,second_ + 1 user_demand_error_UserDemand_#11,1,second_ <= 0.5752294796157207
user_demand_relative_error_constraint_UserDemand_#3,1_: 1 user_demand_allocated_UserDemand_#3,1_ + 0.006940114120276049 user_demand_error_UserDemand_#3,1,first_ >= 0.006940114120276049
user_demand_relative_error_constraint_UserDemand_#7,1_: 1 user_demand_allocated_UserDemand_#7,1_ + 0.006940114120276049 user_demand_error_UserDemand_#7,1,first_ >= 0.006940114120276049
user_demand_relative_error_constraint_UserDemand_#11,1_: 1 user_demand_allocated_UserDemand_#11,1_ + 0.006940114120276049 user_demand_error_UserDemand_#11,1,first_ >= 0.006940114120276049
user_demand_fairness_error_constraint_UserDemand_#3,1_: -1 user_demand_error_UserDemand_#3,1,first_ + 1 user_demand_error_UserDemand_#3,1,second_ + 1 average_flow_unit_error_1_ >= 0
user_demand_fairness_error_constraint_UserDemand_#7,1_: -1 user_demand_error_UserDemand_#7,1,first_ + 1 user_demand_error_UserDemand_#7,1,second_ + 1 average_flow_unit_error_1_ >= 0
user_demand_fairness_error_constraint_UserDemand_#11,1_: -1 user_demand_error_UserDemand_#11,1,first_ + 1 user_demand_error_UserDemand_#11,1,second_ + 1 average_flow_unit_error_1_ >= 0
flow_conservation_pump_Pump_#6_: 1 flow_(Basin_#5,_Pump_#6)_ - 1 flow_(Pump_#6,_Terminal_#4)_ = 0
flow_conservation_outlet_Outlet_#9_: 1 flow_(Basin_#8,_Outlet_#9)_ - 1 flow_(Outlet_#9,_Basin_#10)_ = 0
volume_conservation_Basin_#1_: 1 basin_storage_change_Basin_#1_ - 1 flow_(FlowBoundary_#2,_Basin_#1)_ + 1 flow_(Basin_#1,_UserDemand_#3)_ = 0
volume_conservation_Basin_#5_: 1 basin_storage_change_Basin_#5_ + 1 flow_(Basin_#5,_Pump_#6)_ + 1 flow_(Basin_#5,_UserDemand_#7)_ = 0
volume_conservation_Basin_#8_: 1 basin_storage_change_Basin_#8_ + 1 flow_(Basin_#8,_Outlet_#9)_ = 0
volume_conservation_Basin_#10_: 1 basin_storage_change_Basin_#10_ - 1 flow_(Outlet_#9,_Basin_#10)_ + 1 flow_(Basin_#10,_UserDemand_#11)_ = 0
user_demand_allocated_sum_constraint_UserDemand_#3_: 1 flow_(Basin_#1,_UserDemand_#3)_ - 1 user_demand_allocated_UserDemand_#3,1_ = 0
user_demand_allocated_sum_constraint_UserDemand_#7_: 1 flow_(Basin_#5,_UserDemand_#7)_ - 1 user_demand_allocated_UserDemand_#7,1_ = 0
user_demand_allocated_sum_constraint_UserDemand_#11_: 1 flow_(Basin_#10,_UserDemand_#11)_ - 1 user_demand_allocated_UserDemand_#11,1_ = 0
user_demand_return_flow_UserDemand_#3_: 1 flow_(UserDemand_#3,_Terminal_#4)_ = 0
user_demand_return_flow_UserDemand_#7_: 1 flow_(UserDemand_#7,_Terminal_#4)_ = 0
user_demand_return_flow_UserDemand_#11_: 1 flow_(UserDemand_#11,_Terminal_#4)_ = 0
average_flow_unit_error_constraint_1_: -0.33333333333333337 user_demand_error_UserDemand_#3,1,first_ - 0.33333333333333337 user_demand_error_UserDemand_#7,1,first_ - 0.33333333333333337 user_demand_error_UserDemand_#11,1,first_ + 1 average_flow_unit_error_1_ = 0
pump_constraint_Pump_#6_: -0.0006940114120276049 low_storage_factor_Basin_#5_ + 1 flow_(Basin_#5,_Pump_#6)_ = 0
Bounds
basin_storage_change_Basin_#1_ >= -0.011330241725648092
basin_storage_change_Basin_#5_ >= -0.10692780859294154
basin_storage_change_Basin_#8_ >= -4.272073403159506
basin_storage_change_Basin_#10_ >= -0.01109085452691577
0 <= low_storage_factor_Basin_#1_ <= 1
0 <= low_storage_factor_Basin_#5_ <= 1
0 <= low_storage_factor_Basin_#8_ <= 1
0 <= low_storage_factor_Basin_#10_ <= 1
flow_(FlowBoundary_#2,_Basin_#1)_ = 0.0013880228240552097
0 <= flow_(Basin_#1,_UserDemand_#3)_ <= 0.006940114120276049
0 <= flow_(UserDemand_#3,_Terminal_#4)_ <= 0.006940114120276049
flow_(Basin_#5,_Pump_#6)_ free
flow_(Pump_#6,_Terminal_#4)_ free
flow_(Basin_#5,_UserDemand_#7)_ = 0
0 <= flow_(UserDemand_#7,_Terminal_#4)_ <= 0.006940114120276049
0 <= flow_(Basin_#8,_Outlet_#9)_ <= 0.06940114120276049
0 <= flow_(Outlet_#9,_Basin_#10)_ <= 0.06940114120276049
0 <= flow_(Basin_#10,_UserDemand_#11)_ <= 0.006940114120276049
0 <= flow_(UserDemand_#11,_Terminal_#4)_ <= 0.006940114120276049
0 <= user_demand_allocated_UserDemand_#3,1_ <= 0.006940114120276049
0 <= user_demand_allocated_UserDemand_#7,1_ <= 0.006940114120276049
0 <= user_demand_allocated_UserDemand_#11,1_ <= 0.006940114120276049
0 <= user_demand_error_UserDemand_#3,1,first_ <= 1
0 <= user_demand_error_UserDemand_#3,1,second_ <= 1
0 <= user_demand_error_UserDemand_#7,1,first_ <= 1
0 <= user_demand_error_UserDemand_#7,1,second_ <= 1
0 <= user_demand_error_UserDemand_#11,1,first_ <= 1
0 <= user_demand_error_UserDemand_#11,1,second_ <= 1
0 <= average_flow_unit_error_1_ <= 1
user_demand_min_level_slack_(Basin_#1,_UserDemand_#3) >= 0
user_demand_min_level_slack_(Basin_#10,_UserDemand_#11) >= 0
End

minimize
obj: 
subject to
user_demand_relative_error_constraint_UserDemand_#20,2_: 1 user_demand_allocated_UserDemand_#20,2_ + 2 user_demand_error_UserDemand_#20,2,first_ >= 2
user_demand_relative_error_constraint_UserDemand_#21,1_: 1 user_demand_allocated_UserDemand_#21,1_ + 2 user_demand_error_UserDemand_#21,1,first_ >= 2
user_demand_relative_error_constraint_UserDemand_#22,2_: 1 user_demand_allocated_UserDemand_#22,2_ + 2 user_demand_error_UserDemand_#22,2,first_ >= 2
user_demand_fairness_error_constraint_UserDemand_#20,2_: -1 user_demand_error_UserDemand_#20,2,first_ + 1 user_demand_error_UserDemand_#20,2,second_ + 1 average_flow_unit_error_2_ >= 0
user_demand_fairness_error_constraint_UserDemand_#21,1_: -1 user_demand_error_UserDemand_#21,1,first_ + 1 user_demand_error_UserDemand_#21,1,second_ + 1 average_flow_unit_error_1_ >= 0
user_demand_fairness_error_constraint_UserDemand_#22,2_: -1 user_demand_error_UserDemand_#22,2,first_ + 1 user_demand_error_UserDemand_#22,2,second_ + 1 average_flow_unit_error_2_ >= 0
flow_conservation_pump_Pump_#15_: 1 flow_(Basin_#12,_Pump_#15)_ - 1 flow_(Pump_#15,_Basin_#16)_ = 0
flow_conservation_outlet_Outlet_#13_: 1 flow_(Basin_#12,_Outlet_#13)_ - 1 flow_(Outlet_#13,_Terminal_#14)_ = 0
flow_conservation_outlet_Outlet_#17_: 1 flow_(Basin_#16,_Outlet_#17)_ - 1 flow_(Outlet_#17,_Basin_#18)_ = 0
flow_conservation_outlet_Outlet_#23_: 1 flow_(Basin_#16,_Outlet_#23)_ - 1 flow_(Outlet_#23,_Terminal_#19)_ = 0
volume_conservation_Basin_#12_: 1 basin_storage_change_Basin_#12_ + 1 low_storage_factor_Basin_#12_ + 1 flow_(Basin_#12,_Outlet_#13)_ + 1 flow_(Basin_#12,_UserDemand_#20)_ + 1 flow_(Basin_#12,_Pump_#15)_ - 1 flow_(UserDemand_#20,_Basin_#12)_ = 1
volume_conservation_Basin_#16_: 1 basin_storage_change_Basin_#16_ + 1 low_storage_factor_Basin_#16_ - 1 flow_(Pump_#15,_Basin_#16)_ + 1 flow_(Basin_#16,_Outlet_#17)_ + 1 flow_(Basin_#16,_UserDemand_#21)_ + 1 flow_(Basin_#16,_Outlet_#23)_ - 1 flow_(UserDemand_#21,_Basin_#16)_ - 1 flow_(FlowBoundary_#58,_Basin_#16)_ = 1
volume_conservation_Basin_#18_: 1 basin_storage_change_Basin_#18_ + 1 low_storage_factor_Basin_#18_ - 1 flow_(Outlet_#17,_Basin_#18)_ + 1 flow_(Basin_#18,_UserDemand_#22)_ - 1 flow_(UserDemand_#22,_Basin_#18)_ = 1
pump_constraint_Pump_#15_: -1 low_storage_factor_Basin_#12_ + 1 flow_(Basin_#12,_Pump_#15)_ = 0
outlet_constraint_Outlet_#13_: -1 low_storage_factor_Basin_#12_ + 1 flow_(Basin_#12,_Outlet_#13)_ = 0
outlet_constraint_Outlet_#17_: -1 low_storage_factor_Basin_#16_ + 1 flow_(Basin_#16,_Outlet_#17)_ = 0
outlet_constraint_Outlet_#23_: -1 low_storage_factor_Basin_#16_ + 1 flow_(Basin_#16,_Outlet_#23)_ = 0
c12: 1 flow_(Basin_#12,_UserDemand_#20)_ - 1 user_demand_allocated_UserDemand_#20,2_ = 0
c13: 1 flow_(Basin_#16,_UserDemand_#21)_ - 1 user_demand_allocated_UserDemand_#21,1_ = 0
c14: 1 flow_(Basin_#18,_UserDemand_#22)_ - 1 user_demand_allocated_UserDemand_#22,2_ = 0
user_demand_return_flow_UserDemand_#20_: -0.5 flow_(Basin_#12,_UserDemand_#20)_ + 1 flow_(UserDemand_#20,_Basin_#12)_ = 0
user_demand_return_flow_UserDemand_#21_: -0.5 flow_(Basin_#16,_UserDemand_#21)_ + 1 flow_(UserDemand_#21,_Basin_#16)_ = 0
user_demand_return_flow_UserDemand_#22_: -0.5 flow_(Basin_#18,_UserDemand_#22)_ + 1 flow_(UserDemand_#22,_Basin_#18)_ = 0
average_flow_unit_error_constraint_1_: -1 user_demand_error_UserDemand_#21,1,first_ + 1 average_flow_unit_error_1_ = 0
average_flow_unit_error_constraint_2_: -1 user_demand_error_UserDemand_#20,2,first_ - 1 user_demand_error_UserDemand_#22,2,first_ + 1 average_flow_unit_error_2_ = 0
Bounds
-0.02 <= basin_storage_change_Basin_#12_ <= 0.08
-0.02 <= basin_storage_change_Basin_#16_ <= 0.08
-0.02 <= basin_storage_change_Basin_#18_ <= 0.08
0 <= low_storage_factor_Basin_#12_ <= 1
0 <= low_storage_factor_Basin_#16_ <= 1
0 <= low_storage_factor_Basin_#18_ <= 1
0 <= flow_(Pump_#11,_Basin_#12)_ <= 17.28
0 <= flow_(Basin_#12,_Outlet_#13)_ <= 5.184
0 <= flow_(Outlet_#13,_Terminal_#14)_ <= 5.184
0 <= flow_(Basin_#12,_UserDemand_#20)_ <= 864000
0 <= flow_(Basin_#12,_Pump_#15)_ <= 6.912
0 <= flow_(Pump_#15,_Basin_#16)_ <= 6.912
0 <= flow_(Basin_#16,_Outlet_#17)_ <= 5.184
0 <= flow_(Outlet_#17,_Basin_#18)_ <= 5.184
0 <= flow_(Basin_#16,_UserDemand_#21)_ <= 864000
0 <= flow_(Basin_#18,_UserDemand_#22)_ <= 864000
0 <= flow_(Basin_#16,_Outlet_#23)_ <= 5.184
0 <= flow_(Outlet_#23,_Terminal_#19)_ <= 5.184
0 <= flow_(UserDemand_#20,_Basin_#12)_ <= 864000
0 <= flow_(UserDemand_#21,_Basin_#16)_ <= 864000
0 <= flow_(UserDemand_#22,_Basin_#18)_ <= 864000
0 <= flow_(FlowBoundary_#58,_Basin_#16)_ <= 864000
0 <= user_demand_allocated_UserDemand_#20,2_ <= 2
0 <= user_demand_allocated_UserDemand_#21,1_ <= 2
0 <= user_demand_allocated_UserDemand_#22,2_ <= 2
0 <= user_demand_error_UserDemand_#20,2,first_ <= 1
0 <= user_demand_error_UserDemand_#20,2,second_ <= 1
0 <= user_demand_error_UserDemand_#21,1,first_ <= 1
0 <= user_demand_error_UserDemand_#21,1,second_ <= 1
0 <= user_demand_error_UserDemand_#22,2,first_ <= 1
0 <= user_demand_error_UserDemand_#22,2,second_ <= 1
0 <= average_flow_unit_error_1_ <= 1
0 <= average_flow_unit_error_2_ <= 1
End

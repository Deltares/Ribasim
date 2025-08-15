minimize
obj: 
subject to
user_demand_relative_error_constraint_UserDemand_#10,2_: 1 user_demand_allocated_UserDemand_#10,2_ + 2 user_demand_error_UserDemand_#10,2,first_ >= 2
user_demand_relative_error_constraint_UserDemand_#11,1_: 1 user_demand_allocated_UserDemand_#11,1_ + 2 user_demand_error_UserDemand_#11,1,first_ >= 2
user_demand_relative_error_constraint_UserDemand_#12,2_: 1 user_demand_allocated_UserDemand_#12,2_ + 2 user_demand_error_UserDemand_#12,2,first_ >= 2
user_demand_fairness_error_constraint_UserDemand_#10,2_: -1 user_demand_error_UserDemand_#10,2,first_ + 1 user_demand_error_UserDemand_#10,2,second_ + 1 average_flow_unit_error_2_ >= 0
user_demand_fairness_error_constraint_UserDemand_#11,1_: -1 user_demand_error_UserDemand_#11,1,first_ + 1 user_demand_error_UserDemand_#11,1,second_ + 1 average_flow_unit_error_1_ >= 0
user_demand_fairness_error_constraint_UserDemand_#12,2_: -1 user_demand_error_UserDemand_#12,2,first_ + 1 user_demand_error_UserDemand_#12,2,second_ + 1 average_flow_unit_error_2_ >= 0
flow_conservation_pump_Pump_#5_: 1 flow_(Basin_#2,_Pump_#5)_ - 1 flow_(Pump_#5,_Basin_#6)_ = 0
flow_conservation_outlet_Outlet_#3_: 1 flow_(Basin_#2,_Outlet_#3)_ - 1 flow_(Outlet_#3,_Terminal_#4)_ = 0
flow_conservation_outlet_Outlet_#7_: 1 flow_(Basin_#6,_Outlet_#7)_ - 1 flow_(Outlet_#7,_Basin_#8)_ = 0
flow_conservation_outlet_Outlet_#13_: 1 flow_(Basin_#6,_Outlet_#13)_ - 1 flow_(Outlet_#13,_Terminal_#9)_ = 0
volume_conservation_Basin_#2_: 1 basin_storage_change_Basin_#2_ + 1 low_storage_factor_Basin_#2_ - 1 flow_(FlowBoundary_#1,_Basin_#2)_ + 1 flow_(Basin_#2,_Outlet_#3)_ + 1 flow_(Basin_#2,_UserDemand_#10)_ + 1 flow_(Basin_#2,_Pump_#5)_ - 1 flow_(UserDemand_#10,_Basin_#2)_ = 1
volume_conservation_Basin_#6_: 1 basin_storage_change_Basin_#6_ + 1 low_storage_factor_Basin_#6_ - 1 flow_(Pump_#5,_Basin_#6)_ + 1 flow_(Basin_#6,_Outlet_#7)_ + 1 flow_(Basin_#6,_UserDemand_#11)_ + 1 flow_(Basin_#6,_Outlet_#13)_ - 1 flow_(UserDemand_#11,_Basin_#6)_ = 1
volume_conservation_Basin_#8_: 1 basin_storage_change_Basin_#8_ + 1 low_storage_factor_Basin_#8_ - 1 flow_(Outlet_#7,_Basin_#8)_ + 1 flow_(Basin_#8,_UserDemand_#12)_ - 1 flow_(UserDemand_#12,_Basin_#8)_ = 1
pump_constraint_Pump_#5_: -1 low_storage_factor_Basin_#2_ + 1 flow_(Basin_#2,_Pump_#5)_ = 0
outlet_constraint_Outlet_#3_: -1 low_storage_factor_Basin_#2_ + 1 flow_(Basin_#2,_Outlet_#3)_ = 0
outlet_constraint_Outlet_#7_: -1 low_storage_factor_Basin_#6_ + 1 flow_(Basin_#6,_Outlet_#7)_ = 0
outlet_constraint_Outlet_#13_: -1 low_storage_factor_Basin_#6_ + 1 flow_(Basin_#6,_Outlet_#13)_ = 0
c12: 1 flow_(Basin_#2,_UserDemand_#10)_ - 1 user_demand_allocated_UserDemand_#10,2_ = 0
c13: 1 flow_(Basin_#6,_UserDemand_#11)_ - 1 user_demand_allocated_UserDemand_#11,1_ = 0
c14: 1 flow_(Basin_#8,_UserDemand_#12)_ - 1 user_demand_allocated_UserDemand_#12,2_ = 0
user_demand_return_flow_UserDemand_#10_: -0.5 flow_(Basin_#2,_UserDemand_#10)_ + 1 flow_(UserDemand_#10,_Basin_#2)_ = 0
user_demand_return_flow_UserDemand_#11_: -0.5 flow_(Basin_#6,_UserDemand_#11)_ + 1 flow_(UserDemand_#11,_Basin_#6)_ = 0
user_demand_return_flow_UserDemand_#12_: -0.5 flow_(Basin_#8,_UserDemand_#12)_ + 1 flow_(UserDemand_#12,_Basin_#8)_ = 0
average_flow_unit_error_constraint_1_: -1 user_demand_error_UserDemand_#11,1,first_ + 1 average_flow_unit_error_1_ = 0
average_flow_unit_error_constraint_2_: -1 user_demand_error_UserDemand_#10,2,first_ - 1 user_demand_error_UserDemand_#12,2,first_ + 1 average_flow_unit_error_2_ = 0
Bounds
-0.0002 <= basin_storage_change_Basin_#2_ <= 0.0008
-0.0002 <= basin_storage_change_Basin_#6_ <= 0.0008
-0.0002 <= basin_storage_change_Basin_#8_ <= 0.0008
0 <= low_storage_factor_Basin_#2_ <= 1
0 <= low_storage_factor_Basin_#6_ <= 1
0 <= low_storage_factor_Basin_#8_ <= 1
0 <= flow_(FlowBoundary_#1,_Basin_#2)_ <= 8640
0 <= flow_(Basin_#2,_Outlet_#3)_ <= 0.05184
0 <= flow_(Outlet_#3,_Terminal_#4)_ <= 0.05184
0 <= flow_(Basin_#2,_UserDemand_#10)_ <= 8640
0 <= flow_(Basin_#2,_Pump_#5)_ <= 0.06912
0 <= flow_(Pump_#5,_Basin_#6)_ <= 0.06912
0 <= flow_(Basin_#6,_Outlet_#7)_ <= 0.05184
0 <= flow_(Outlet_#7,_Basin_#8)_ <= 0.05184
0 <= flow_(Basin_#6,_UserDemand_#11)_ <= 8640
0 <= flow_(Basin_#8,_UserDemand_#12)_ <= 8640
0 <= flow_(Basin_#6,_Outlet_#13)_ <= 0.05184
0 <= flow_(Outlet_#13,_Terminal_#9)_ <= 0.05184
0 <= flow_(UserDemand_#10,_Basin_#2)_ <= 8640
0 <= flow_(UserDemand_#11,_Basin_#6)_ <= 8640
0 <= flow_(UserDemand_#12,_Basin_#8)_ <= 8640
0 <= user_demand_allocated_UserDemand_#10,2_ <= 2
0 <= user_demand_allocated_UserDemand_#11,1_ <= 2
0 <= user_demand_allocated_UserDemand_#12,2_ <= 2
0 <= user_demand_error_UserDemand_#10,2,first_ <= 1
0 <= user_demand_error_UserDemand_#10,2,second_ <= 1
0 <= user_demand_error_UserDemand_#11,1,first_ <= 1
0 <= user_demand_error_UserDemand_#11,1,second_ <= 1
0 <= user_demand_error_UserDemand_#12,2,first_ <= 1
0 <= user_demand_error_UserDemand_#12,2,second_ <= 1
0 <= average_flow_unit_error_1_ <= 1
0 <= average_flow_unit_error_2_ <= 1
End

minimize
obj: 50 flow_(Pump_#2,_Junction_#4)_
subject to
c1: -1 low_storage_factor_Basin_#1_ - 1 low_storage_factor_Basin_#8_ - 1 low_storage_factor_Basin_#9_ - 1 low_storage_factor_Basin_#11_ <= -4
c2: 1 user_demand_error_UserDemand_#5,1,first_ <= 0
c3: 1 user_demand_error_UserDemand_#5,1,second_ <= 0
user_demand_relative_error_constraint_UserDemand_#5,1_: 1 user_demand_allocated_UserDemand_#5,1_ + 4.867593293425453e-5 user_demand_error_UserDemand_#5,1,first_ >= 4.867593293425453e-5
user_demand_fairness_error_constraint_UserDemand_#5,1_: -1 user_demand_error_UserDemand_#5,1,first_ + 1 user_demand_error_UserDemand_#5,1,second_ + 1 average_flow_unit_error_1_ >= 0
flow_conservation_junction_pump_(Pump_#2,_Junction_#4)_: -1 flow_(Basin_#1,_Pump_#2)_ + 1 flow_(Pump_#2,_Junction_#4)_ = 0
volume_conservation_Basin_#1_: 1 basin_storage_change_Basin_#1_ + 1 flow_(Basin_#1,_Pump_#2)_ = 0
volume_conservation_Basin_#8_: 1 basin_storage_change_Basin_#8_ - 1 flow_(Junction_#4,_Basin_#8)_ = 0
volume_conservation_Basin_#9_: 1 basin_storage_change_Basin_#9_ - 1 flow_(Junction_#4,_Basin_#9)_ = 0
volume_conservation_Basin_#11_: 1 basin_storage_change_Basin_#11_ - 1 flow_(Junction_#10,_Basin_#11)_ = 0
pump_constraint_Pump_#2_: -2.4337966467127266e-5 low_storage_factor_Basin_#1_ + 1 flow_(Basin_#1,_Pump_#2)_ = 0
junction_outflow_(Junction_#4,_Basin_#8)_: -0.7 flow_(Pump_#2,_Junction_#4)_ - 0.7 flow_(FlowBoundary_#3,_Junction_#4)_ + 0.7 flow_(Junction_#4,_UserDemand_#5)_ + 1 flow_(Junction_#4,_Basin_#8)_ = 0
junction_outflow_(Junction_#4,_Basin_#9)_: -0.30000000000000004 flow_(Pump_#2,_Junction_#4)_ - 0.30000000000000004 flow_(FlowBoundary_#3,_Junction_#4)_ + 0.30000000000000004 flow_(Junction_#4,_UserDemand_#5)_ + 1 flow_(Junction_#4,_Basin_#9)_ = 0
junction_outflow_(Junction_#10,_Basin_#11)_: -1 flow_(UserDemand_#5,_Junction_#10)_ + 1 flow_(Junction_#10,_Basin_#11)_ = 0
user_demand_allocated_sum_constraint_UserDemand_#5_: 1 flow_(Junction_#4,_UserDemand_#5)_ - 1 user_demand_allocated_UserDemand_#5,1_ = 0
user_demand_return_flow_junction_(UserDemand_#5,_Junction_#10)_: -0.5 flow_(Junction_#4,_UserDemand_#5)_ + 1 flow_(UserDemand_#5,_Junction_#10)_ = 0
average_flow_unit_error_constraint_1_: -1 user_demand_error_UserDemand_#5,1,first_ + 1 average_flow_unit_error_1_ = 0
Bounds
basin_storage_change_Basin_#1_ >= -0.37554533899303727
basin_storage_change_Basin_#8_ >= -0.03757278737415408
basin_storage_change_Basin_#9_ >= -0.037564674718665036
basin_storage_change_Basin_#11_ >= -0.037599153504493464
0 <= low_storage_factor_Basin_#1_ <= 1
0 <= low_storage_factor_Basin_#8_ <= 1
0 <= low_storage_factor_Basin_#9_ <= 1
0 <= low_storage_factor_Basin_#11_ <= 1
flow_(Basin_#1,_Pump_#2)_ free
flow_(Pump_#2,_Junction_#4)_ >= 0
flow_(FlowBoundary_#3,_Junction_#4)_ = 3.6506949700690904e-5
0 <= flow_(Junction_#4,_UserDemand_#5)_ <= 4.867593293425453e-5
flow_(Junction_#4,_Basin_#8)_ >= 0
flow_(Junction_#4,_Basin_#9)_ >= 0
0 <= flow_(UserDemand_#5,_Junction_#10)_ <= 4.867593293425453e-5
flow_(Junction_#10,_Basin_#11)_ >= 0
0 <= user_demand_allocated_UserDemand_#5,1_ <= 4.867593293425453e-5
0 <= user_demand_error_UserDemand_#5,1,first_ <= 1
0 <= user_demand_error_UserDemand_#5,1,second_ <= 1
0 <= average_flow_unit_error_1_ <= 1
End

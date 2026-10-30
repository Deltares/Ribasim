minimize
obj: 50 flow_(Pump_#3,_Basin_#4)_
subject to
c1: -1 low_storage_factor_Basin_#2_ - 1 low_storage_factor_Basin_#4_ <= -2
c2: 0.5 user_demand_error_UserDemand_#5,1,first_ + 0.5 user_demand_error_UserDemand_#6,1,first_ <= 0
c3: 1 user_demand_error_UserDemand_#5,1,second_ + 1 user_demand_error_UserDemand_#6,1,second_ <= 0
user_demand_relative_error_constraint_UserDemand_#5,1_: 1 user_demand_allocated_UserDemand_#5,1_ + 0.00012932877169999078 user_demand_error_UserDemand_#5,1,first_ >= 0.00012932877169999078
user_demand_relative_error_constraint_UserDemand_#6,1_: 1 user_demand_allocated_UserDemand_#6,1_ + 0.00012932877169999078 user_demand_error_UserDemand_#6,1,first_ >= 0.00012932877169999078
user_demand_fairness_error_constraint_UserDemand_#5,1_: -1 user_demand_error_UserDemand_#5,1,first_ + 1 user_demand_error_UserDemand_#5,1,second_ + 1 average_flow_unit_error_1_ >= 0
user_demand_fairness_error_constraint_UserDemand_#6,1_: -1 user_demand_error_UserDemand_#6,1,first_ + 1 user_demand_error_UserDemand_#6,1,second_ + 1 average_flow_unit_error_1_ >= 0
flow_conservation_pump_Pump_#3_: 1 flow_(Basin_#2,_Pump_#3)_ - 1 flow_(Pump_#3,_Basin_#4)_ = 0
volume_conservation_Basin_#2_: 1 basin_storage_change_Basin_#2_ - 1 flow_(FlowBoundary_#1,_Basin_#2)_ + 1 flow_(Basin_#2,_Pump_#3)_ = 0
volume_conservation_Basin_#4_: 1 basin_storage_change_Basin_#4_ - 1 flow_(Pump_#3,_Basin_#4)_ + 1 flow_(Basin_#4,_UserDemand_#5)_ + 1 flow_(Basin_#4,_UserDemand_#6)_ - 1 flow_(UserDemand_#5,_Basin_#4)_ - 1 flow_(UserDemand_#6,_Basin_#4)_ = 0
user_demand_allocated_sum_constraint_UserDemand_#5_: 1 flow_(Basin_#4,_UserDemand_#5)_ - 1 user_demand_allocated_UserDemand_#5,1_ = 0
user_demand_allocated_sum_constraint_UserDemand_#6_: 1 flow_(Basin_#4,_UserDemand_#6)_ - 1 user_demand_allocated_UserDemand_#6,1_ = 0
user_demand_return_flow_UserDemand_#5_: -0.9 flow_(Basin_#4,_UserDemand_#5)_ + 1 flow_(UserDemand_#5,_Basin_#4)_ = 0
user_demand_return_flow_UserDemand_#6_: -0.9 flow_(Basin_#4,_UserDemand_#6)_ + 1 flow_(UserDemand_#6,_Basin_#4)_ = 0
average_flow_unit_error_constraint_1_: -0.5 user_demand_error_UserDemand_#5,1,first_ - 0.5 user_demand_error_UserDemand_#6,1,first_ + 1 average_flow_unit_error_1_ = 0
pump_constraint_Pump_#3_: -0.0005173150867999631 low_storage_factor_Basin_#2_ + 1 flow_(Basin_#2,_Pump_#3)_ = 0
Bounds
basin_storage_change_Basin_#2_ >= -0.003560532850505919
basin_storage_change_Basin_#4_ >= -0.004810710976939163
0 <= low_storage_factor_Basin_#2_ <= 1
0 <= low_storage_factor_Basin_#4_ <= 1
flow_(FlowBoundary_#1,_Basin_#2)_ = 0.00025865754339998156
0 <= flow_(Basin_#2,_Pump_#3)_ <= 0.0005173150867999631
0 <= flow_(Pump_#3,_Basin_#4)_ <= 0.0005173150867999631
0 <= flow_(Basin_#4,_UserDemand_#5)_ <= 0.00012932877169999078
0 <= flow_(Basin_#4,_UserDemand_#6)_ <= 0.00012932877169999078
0 <= flow_(UserDemand_#5,_Basin_#4)_ <= 0.00012932877169999078
0 <= flow_(UserDemand_#6,_Basin_#4)_ <= 0.00012932877169999078
0 <= user_demand_allocated_UserDemand_#5,1_ <= 0.00012932877169999078
0 <= user_demand_allocated_UserDemand_#6,1_ <= 0.00012932877169999078
0 <= user_demand_error_UserDemand_#5,1,first_ <= 1
0 <= user_demand_error_UserDemand_#5,1,second_ <= 1
0 <= user_demand_error_UserDemand_#6,1,first_ <= 1
0 <= user_demand_error_UserDemand_#6,1,second_ <= 1
0 <= average_flow_unit_error_1_ <= 1
End

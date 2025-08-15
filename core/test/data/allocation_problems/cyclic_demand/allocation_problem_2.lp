minimize
obj: 
subject to
user_demand_relative_error_constraint_UserDemand_#7,1_: 1 user_demand_allocated_UserDemand_#7,1_ + 2 user_demand_error_UserDemand_#7,1,first_ >= 2
user_demand_relative_error_constraint_UserDemand_#7,2_: 1 user_demand_allocated_UserDemand_#7,2_ + 2 user_demand_error_UserDemand_#7,2,first_ >= 2
flow_demand_relative_error_constraint_Pump_#3,2_: 1 flow_demand_allocated_Pump_#3,2_ + 2 flow_demand_error_Pump_#3,2,first_ >= 2
storage_constraint_Basin_#2,3,lower_: 1 level_demand_allocated_Basin_#2,3,lower_ + 1 level_demand_error_Basin_#2,3,lower,first_ >= 2000
storage_constraint_Basin_#2,3,upper_: 1 level_demand_allocated_Basin_#2,3,upper_ + 1 level_demand_error_Basin_#2,3,upper,first_ >= 2000
user_demand_fairness_error_constraint_UserDemand_#7,1_: -1 user_demand_error_UserDemand_#7,1,first_ + 1 user_demand_error_UserDemand_#7,1,second_ + 1 average_flow_unit_error_1_ >= 0
user_demand_fairness_error_constraint_UserDemand_#7,2_: -1 user_demand_error_UserDemand_#7,2,first_ + 1 user_demand_error_UserDemand_#7,2,second_ + 1 average_flow_unit_error_2_ >= 0
c8: -1 flow_demand_error_Pump_#3,2,first_ + 1 flow_demand_error_Pump_#3,2,second_ + 1 average_flow_unit_error_2_ >= 0
level_demand_fairness_error_constraint_Basin_#2,3,lower_: -0.001 level_demand_error_Basin_#2,3,lower,first_ + 1 level_demand_error_Basin_#2,3,lower,second_ + 1 average_storage_unit_error_3,lower_ >= 0
level_demand_fairness_error_constraint_Basin_#2,3,upper_: -0.001 level_demand_error_Basin_#2,3,upper,first_ + 1 level_demand_error_Basin_#2,3,upper,second_ + 1 average_storage_unit_error_3,upper_ >= 0
flow_conservation_pump_Pump_#3_: 1 flow_(Basin_#2,_Pump_#3)_ - 1 flow_(Pump_#3,_Basin_#4)_ = 0
volume_conservation_Basin_#2_: 1 basin_storage_change_Basin_#2_ + 1 low_storage_factor_Basin_#2_ - 1 flow_(FlowBoundary_#1,_Basin_#2)_ + 1 flow_(Basin_#2,_Pump_#3)_ = 1
volume_conservation_Basin_#4_: 1 basin_storage_change_Basin_#4_ + 1 low_storage_factor_Basin_#4_ - 1 flow_(Pump_#3,_Basin_#4)_ + 1 flow_(Basin_#4,_UserDemand_#7)_ - 1 flow_(UserDemand_#7,_Basin_#4)_ = 1
c4: 1 flow_(Basin_#4,_UserDemand_#7)_ - 1 user_demand_allocated_UserDemand_#7,1_ - 1 user_demand_allocated_UserDemand_#7,2_ = 0
user_demand_return_flow_UserDemand_#7_: -0.5 flow_(Basin_#4,_UserDemand_#7)_ + 1 flow_(UserDemand_#7,_Basin_#4)_ = 0
c6: 1 flow_(Basin_#2,_Pump_#3)_ - 36 flow_demand_allocated_Pump_#3,2_ - 1 flow_demand_extra_Pump_#3_ = 0
storage_change_allocated_sum_constraint_Basin_#2_: 1 basin_storage_change_Basin_#2_ - 1 level_demand_allocated_Basin_#2,3,lower_ + 1 level_demand_allocated_Basin_#2,3,upper_ - 1 level_demand_extra_Basin_#2_ = 0
average_flow_unit_error_constraint_1_: -1 user_demand_error_UserDemand_#7,1,first_ + 1 average_flow_unit_error_1_ = 0
average_flow_unit_error_constraint_2_: -1 user_demand_error_UserDemand_#7,2,first_ - 1 flow_demand_error_Pump_#3,2,first_ + 1 average_flow_unit_error_2_ = 0
average_storage_unit_error_constraint_3,upper_: -1 level_demand_error_Basin_#2,3,upper,first_ + 1000 average_storage_unit_error_3,upper_ = 0
average_storage_unit_error_constraint_3,lower_: -1 level_demand_error_Basin_#2,3,lower,first_ + 1000 average_storage_unit_error_3,lower_ = 0
Bounds
-0.02 <= basin_storage_change_Basin_#2_ <= 0.08
-0.02 <= basin_storage_change_Basin_#4_ <= 0.08
0 <= low_storage_factor_Basin_#2_ <= 1
0 <= low_storage_factor_Basin_#4_ <= 1
0 <= flow_(FlowBoundary_#1,_Basin_#2)_ <= 864000
0 <= flow_(Basin_#2,_Pump_#3)_ <= 864000
0 <= flow_(Pump_#3,_Basin_#4)_ <= 864000
0 <= flow_(Basin_#4,_UserDemand_#7)_ <= 864000
0 <= flow_(UserDemand_#7,_Basin_#4)_ <= 864000
0 <= user_demand_allocated_UserDemand_#7,1_ <= 2
0 <= user_demand_allocated_UserDemand_#7,2_ <= 2
0 <= user_demand_error_UserDemand_#7,1,first_ <= 1
0 <= user_demand_error_UserDemand_#7,1,second_ <= 1
0 <= user_demand_error_UserDemand_#7,2,first_ <= 1
0 <= user_demand_error_UserDemand_#7,2,second_ <= 1
-864000 <= flow_demand_allocated_Pump_#3,2_ <= 2
0 <= flow_demand_extra_Pump_#3_ <= 864000
0 <= flow_demand_error_Pump_#3,2,first_ <= 1
0 <= flow_demand_error_Pump_#3,2,second_ <= 1
0 <= level_demand_allocated_Basin_#2,3,lower_ <= 100
0 <= level_demand_allocated_Basin_#2,3,upper_ <= 100
level_demand_extra_Basin_#2_ free
level_demand_error_Basin_#2,3,lower,first_ >= 0
level_demand_error_Basin_#2,3,lower,second_ >= 0
level_demand_error_Basin_#2,3,upper,first_ >= 0
level_demand_error_Basin_#2,3,upper,second_ >= 0
0 <= average_flow_unit_error_1_ <= 1
0 <= average_flow_unit_error_2_ <= 1
average_storage_unit_error_3,lower_ >= 0
average_storage_unit_error_3,upper_ >= 0
End

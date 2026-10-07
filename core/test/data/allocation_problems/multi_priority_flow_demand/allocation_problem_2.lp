minimize
obj: 50 flow_(Pump_#2,_Terminal_#3)_
subject to
c1: 1 level_demand_error_Basin_#1,1,lower,first_ + 1 level_demand_error_Basin_#1,1,upper,first_ <= 0
c2: 1 level_demand_error_Basin_#1,1,lower,second_ + 1 level_demand_error_Basin_#1,1,upper,second_ <= 0
c3: 1 flow_demand_error_Pump_#2,2,first_ <= 0
c4: 1 flow_demand_error_Pump_#2,2,second_ <= 0
c5: 1 user_demand_error_UserDemand_#5,3,first_ <= 3.340369319082548e-5
c6: 1 user_demand_error_UserDemand_#5,3,second_ <= 0
c7: 1 flow_demand_error_Pump_#2,4,first_ <= 1
c8: 1 flow_demand_error_Pump_#2,4,second_ <= 0
c9: -1 low_storage_factor_Basin_#1_ <= -1
user_demand_relative_error_constraint_UserDemand_#5,3_: 1 user_demand_allocated_UserDemand_#5,3_ + 0.0027000001217564675 user_demand_error_UserDemand_#5,3,first_ >= 0.0027000001217564675
flow_demand_relative_error_constraint_Pump_#2,2_: 1 flow_demand_allocated_Pump_#2,2_ + 0.0018000000811709783 flow_demand_error_Pump_#2,2,first_ >= 0.0018000000811709783
flow_demand_relative_error_constraint_Pump_#2,4_: 1 flow_demand_allocated_Pump_#2,4_ + 0.0027000001217564675 flow_demand_error_Pump_#2,4,first_ >= 0.0027000001217564675
storage_constraint_lower_Basin_#1,1_: 1 basin_storage_change_Basin_#1_ + 1 level_demand_error_Basin_#1,1,lower,first_ >= 9.018997568258872e-8
storage_constraint_upper_Basin_#1,1_: -1 basin_storage_change_Basin_#1_ + 1 level_demand_error_Basin_#1,1,upper,first_ >= -inf
user_demand_fairness_error_constraint_UserDemand_#5,3_: -1 user_demand_error_UserDemand_#5,3,first_ + 1 user_demand_error_UserDemand_#5,3,second_ + 1 average_flow_unit_error_3_ >= 0
flow_demand_fairness_error_constraint_Pump_#2,2_: -1 flow_demand_error_Pump_#2,2,first_ + 1 flow_demand_error_Pump_#2,2,second_ + 1 average_flow_unit_error_2_ >= 0
flow_demand_fairness_error_constraint_Pump_#2,4_: -1 flow_demand_error_Pump_#2,4,first_ + 1 flow_demand_error_Pump_#2,4,second_ + 1 average_flow_unit_error_4_ >= 0
level_demand_fairness_error_constraint_Basin_#1,1,lower_: -1 level_demand_error_Basin_#1,1,lower,first_ + 1 level_demand_error_Basin_#1,1,lower,second_ + 1 average_storage_unit_error_1,lower_ >= 0
level_demand_fairness_error_constraint_Basin_#1,1,upper_: -1 level_demand_error_Basin_#1,1,upper,first_ + 1 level_demand_error_Basin_#1,1,upper,second_ + 1 average_storage_unit_error_1,upper_ >= 0
flow_conservation_pump_Pump_#2_: 1 flow_(Basin_#1,_Pump_#2)_ - 1 flow_(Pump_#2,_Terminal_#3)_ = 0
volume_conservation_Basin_#1_: 1 basin_storage_change_Basin_#1_ + 1 flow_(Basin_#1,_Pump_#2)_ - 1 flow_(FlowBoundary_#4,_Basin_#1)_ + 1 flow_(Basin_#1,_UserDemand_#5)_ - 1 flow_(UserDemand_#5,_Basin_#1)_ = 0
user_demand_allocated_sum_constraint_UserDemand_#5_: 1 flow_(Basin_#1,_UserDemand_#5)_ - 1 user_demand_allocated_UserDemand_#5,3_ = 0
user_demand_return_flow_UserDemand_#5_: 1 flow_(UserDemand_#5,_Basin_#1)_ = 0
flow_demand_allocated_sum_constraint_Pump_#2_: 1 flow_(Basin_#1,_Pump_#2)_ - 1 flow_demand_allocated_Pump_#2,2_ - 1 flow_demand_allocated_Pump_#2,4_ - 1 flow_demand_extra_Pump_#2_ = 0
average_flow_unit_error_constraint_2_: -1 flow_demand_error_Pump_#2,2,first_ + 1 average_flow_unit_error_2_ = 0
average_flow_unit_error_constraint_3_: -1 user_demand_error_UserDemand_#5,3,first_ + 1 average_flow_unit_error_3_ = 0
average_flow_unit_error_constraint_4_: -1 flow_demand_error_Pump_#2,4,first_ + 1 average_flow_unit_error_4_ = 0
average_storage_unit_error_constraint_1,upper_: -1 level_demand_error_Basin_#1,1,upper,first_ + 1 average_storage_unit_error_1,upper_ = 0
average_storage_unit_error_constraint_1,lower_: -1 level_demand_error_Basin_#1,1,lower,first_ + 1 average_storage_unit_error_1,lower_ = 0
Bounds
-0.7499999436312652 <= basin_storage_change_Basin_#1_ <= 1.7500001691062044
0 <= low_storage_factor_Basin_#1_ <= 1
0 <= flow_(Basin_#1,_Pump_#2)_ <= 0.9000000405854891
0 <= flow_(Pump_#2,_Terminal_#3)_ <= 0.9000000405854891
flow_(FlowBoundary_#4,_Basin_#1)_ = 0.004500000202927446
0 <= flow_(Basin_#1,_UserDemand_#5)_ <= 0.0027000001217564675
0 <= flow_(UserDemand_#5,_Basin_#1)_ <= 0.0027000001217564675
0 <= user_demand_allocated_UserDemand_#5,3_ <= 0.0027000001217564675
0 <= user_demand_error_UserDemand_#5,3,first_ <= 1
0 <= user_demand_error_UserDemand_#5,3,second_ <= 1
0 <= flow_demand_allocated_Pump_#2,2_ <= 0.0018000000811709783
0 <= flow_demand_allocated_Pump_#2,4_ <= 0.0027000001217564675
0 <= flow_demand_extra_Pump_#2_ <= 0.9000000405854891
0 <= flow_demand_error_Pump_#2,2,first_ <= 1
0 <= flow_demand_error_Pump_#2,2,second_ <= 1
0 <= flow_demand_error_Pump_#2,4,first_ <= 1
0 <= flow_demand_error_Pump_#2,4,second_ <= 1
level_demand_error_Basin_#1,1,lower,first_ >= 0
level_demand_error_Basin_#1,1,lower,second_ >= 0
level_demand_error_Basin_#1,1,upper,first_ >= 0
level_demand_error_Basin_#1,1,upper,second_ >= 0
0 <= average_flow_unit_error_2_ <= 1
0 <= average_flow_unit_error_3_ <= 1
0 <= average_flow_unit_error_4_ <= 1
average_storage_unit_error_1,lower_ >= 0
average_storage_unit_error_1,upper_ >= 0
End

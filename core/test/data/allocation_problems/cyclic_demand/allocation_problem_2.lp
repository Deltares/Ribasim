minimize
obj: 50 flow_(Pump_#3,_Basin_#4)_
subject to
c1: 1 user_demand_error_UserDemand_#7,1,first_ <= 0
c2: 1 user_demand_error_UserDemand_#7,1,second_ <= 0
c3: 0.5 user_demand_error_UserDemand_#7,2,first_ + 0.5 flow_demand_error_Pump_#3,2,first_ <= 0
c4: 1 user_demand_error_UserDemand_#7,2,second_ + 1 flow_demand_error_Pump_#3,2,second_ <= 0
c5: 1 level_demand_error_Basin_#2,3,lower,first_ + 1 level_demand_error_Basin_#2,3,upper,first_ <= 0
c6: 1 level_demand_error_Basin_#2,3,lower,second_ + 1 level_demand_error_Basin_#2,3,upper,second_ <= 0
c7: -1 low_storage_factor_Basin_#2_ - 1 low_storage_factor_Basin_#4_ <= -2
user_demand_relative_error_constraint_UserDemand_#7,1_: 1 user_demand_allocated_UserDemand_#7,1_ + 0.0006776470588235295 user_demand_error_UserDemand_#7,1,first_ >= 0.0006776470588235295
user_demand_relative_error_constraint_UserDemand_#7,2_: 1 user_demand_allocated_UserDemand_#7,2_ + 0.0016941176470588236 user_demand_error_UserDemand_#7,2,first_ >= 0.0016941176470588236
flow_demand_relative_error_constraint_Pump_#3,2_: 1 flow_demand_allocated_Pump_#3,2_ + 0.0016941176470588236 flow_demand_error_Pump_#3,2,first_ >= 0.0016941176470588236
storage_constraint_lower_Basin_#2,3_: 1 basin_storage_change_Basin_#2_ + 1 level_demand_error_Basin_#2,3,lower,first_ >= -0.0196078431372549
storage_constraint_upper_Basin_#2,3_: -1 basin_storage_change_Basin_#2_ + 1 level_demand_error_Basin_#2,3,upper,first_ >= 0.011764705882352941
user_demand_fairness_error_constraint_UserDemand_#7,1_: -1 user_demand_error_UserDemand_#7,1,first_ + 1 user_demand_error_UserDemand_#7,1,second_ + 1 average_flow_unit_error_1_ >= 0
user_demand_fairness_error_constraint_UserDemand_#7,2_: -1 user_demand_error_UserDemand_#7,2,first_ + 1 user_demand_error_UserDemand_#7,2,second_ + 1 average_flow_unit_error_2_ >= 0
flow_demand_fairness_error_constraint_Pump_#3,2_: -1 flow_demand_error_Pump_#3,2,first_ + 1 flow_demand_error_Pump_#3,2,second_ + 1 average_flow_unit_error_2_ >= 0
level_demand_fairness_error_constraint_Basin_#2,3,lower_: -1 level_demand_error_Basin_#2,3,lower,first_ + 1 level_demand_error_Basin_#2,3,lower,second_ + 1 average_storage_unit_error_3,lower_ >= 0
level_demand_fairness_error_constraint_Basin_#2,3,upper_: -1 level_demand_error_Basin_#2,3,upper,first_ + 1 level_demand_error_Basin_#2,3,upper,second_ + 1 average_storage_unit_error_3,upper_ >= 0
flow_conservation_pump_Pump_#3_: 1 flow_(Basin_#2,_Pump_#3)_ - 1 flow_(Pump_#3,_Basin_#4)_ = 0
volume_conservation_Basin_#2_: 1 basin_storage_change_Basin_#2_ - 1 flow_(FlowBoundary_#1,_Basin_#2)_ + 1 flow_(Basin_#2,_Pump_#3)_ = 0
volume_conservation_Basin_#4_: 1 basin_storage_change_Basin_#4_ - 1 flow_(Pump_#3,_Basin_#4)_ + 1 flow_(Basin_#4,_UserDemand_#7)_ - 1 flow_(UserDemand_#7,_Basin_#4)_ = 0
user_demand_allocated_sum_constraint_UserDemand_#7_: 1 flow_(Basin_#4,_UserDemand_#7)_ - 1 user_demand_allocated_UserDemand_#7,1_ - 1 user_demand_allocated_UserDemand_#7,2_ = 0
user_demand_return_flow_UserDemand_#7_: -0.5 flow_(Basin_#4,_UserDemand_#7)_ + 1 flow_(UserDemand_#7,_Basin_#4)_ = 0
flow_demand_allocated_sum_constraint_Pump_#3_: 1 flow_(Basin_#2,_Pump_#3)_ - 1 flow_demand_allocated_Pump_#3,2_ - 1 flow_demand_extra_Pump_#3_ = 0
average_flow_unit_error_constraint_1_: -1 user_demand_error_UserDemand_#7,1,first_ + 1 average_flow_unit_error_1_ = 0
average_flow_unit_error_constraint_2_: -0.5 user_demand_error_UserDemand_#7,2,first_ - 0.5 flow_demand_error_Pump_#3,2,first_ + 1 average_flow_unit_error_2_ = 0
average_storage_unit_error_constraint_3,upper_: -1 level_demand_error_Basin_#2,3,upper,first_ + 1 average_storage_unit_error_3,upper_ = 0
average_storage_unit_error_constraint_3,lower_: -1 level_demand_error_Basin_#2,3,lower,first_ + 1 average_storage_unit_error_3,lower_ = 0
Bounds
-0.0392156862745098 <= basin_storage_change_Basin_#2_ <= 3.8823529411764706
-0.0392156862745098 <= basin_storage_change_Basin_#4_ <= 3.8823529411764706
0 <= low_storage_factor_Basin_#2_ <= 1
0 <= low_storage_factor_Basin_#4_ <= 1
flow_(FlowBoundary_#1,_Basin_#2)_ = 0.003388235294117647
0 <= flow_(Basin_#2,_Pump_#3)_ <= 3.388235294117647
0 <= flow_(Pump_#3,_Basin_#4)_ <= 3.388235294117647
0 <= flow_(Basin_#4,_UserDemand_#7)_ <= 0.002371764705882353
0 <= flow_(UserDemand_#7,_Basin_#4)_ <= 0.002371764705882353
0 <= user_demand_allocated_UserDemand_#7,1_ <= 0.0006776470588235295
0 <= user_demand_allocated_UserDemand_#7,2_ <= 0.0016941176470588236
0 <= user_demand_error_UserDemand_#7,1,first_ <= 1
0 <= user_demand_error_UserDemand_#7,1,second_ <= 1
0 <= user_demand_error_UserDemand_#7,2,first_ <= 1
0 <= user_demand_error_UserDemand_#7,2,second_ <= 1
0 <= flow_demand_allocated_Pump_#3,2_ <= 0.0016941176470588236
0 <= flow_demand_extra_Pump_#3_ <= 3.388235294117647
0 <= flow_demand_error_Pump_#3,2,first_ <= 1
0 <= flow_demand_error_Pump_#3,2,second_ <= 1
level_demand_error_Basin_#2,3,lower,first_ >= 0
level_demand_error_Basin_#2,3,lower,second_ >= 0
level_demand_error_Basin_#2,3,upper,first_ >= 0
level_demand_error_Basin_#2,3,upper,second_ >= 0
0 <= average_flow_unit_error_1_ <= 1
0 <= average_flow_unit_error_2_ <= 1
average_storage_unit_error_3,lower_ >= 0
average_storage_unit_error_3,upper_ >= 0
End

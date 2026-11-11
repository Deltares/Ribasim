minimize
obj: 1 flow_change_Pump_#7_ + 1.01 flow_change_Pump_#8_
subject to
c1: -1 low_storage_factor_Basin_#1_ - 1 low_storage_factor_Basin_#5_ - 1 low_storage_factor_Basin_#6_ <= -3
c2: 1 user_demand_error_UserDemand_#2,1,first_ <= 0
c3: 1 user_demand_error_UserDemand_#2,1,second_ <= 0
c4: 50 flow_(Pump_#7,_Basin_#1)_ + 50 flow_(Pump_#8,_Basin_#1)_ <= 1.361192023302711
user_demand_relative_error_constraint_UserDemand_#2,1_: 1 user_demand_allocated_UserDemand_#2,1_ + 0.027223840466054222 user_demand_error_UserDemand_#2,1,first_ >= 0.027223840466054222
user_demand_fairness_error_constraint_UserDemand_#2,1_: -1 user_demand_error_UserDemand_#2,1,first_ + 1 user_demand_error_UserDemand_#2,1,second_ + 1 average_flow_unit_error_1_ >= 0
flow_change_constraint_Pump_#7,_1_: 1 flow_(Basin_#5,_Pump_#7)_ + 1 flow_change_Pump_#7_ >= 0.003781088953618643
flow_change_constraint_Pump_#8,_1_: 1 flow_(Basin_#6,_Pump_#8)_ + 1 flow_change_Pump_#8_ >= 0
flow_change_constraint_Pump_#7,1_: -1 flow_(Basin_#5,_Pump_#7)_ + 1 flow_change_Pump_#7_ >= -0.003781088953618643
flow_change_constraint_Pump_#8,1_: -1 flow_(Basin_#6,_Pump_#8)_ + 1 flow_change_Pump_#8_ >= 0
flow_conservation_pump_Pump_#7_: 1 flow_(Basin_#5,_Pump_#7)_ - 1 flow_(Pump_#7,_Basin_#1)_ = 0
flow_conservation_pump_Pump_#8_: 1 flow_(Basin_#6,_Pump_#8)_ - 1 flow_(Pump_#8,_Basin_#1)_ = 0
volume_conservation_Basin_#1_: 1 basin_storage_change_Basin_#1_ + 1 flow_(Basin_#1,_UserDemand_#2)_ - 1 flow_(UserDemand_#2,_Basin_#1)_ - 1 flow_(Pump_#7,_Basin_#1)_ - 1 flow_(Pump_#8,_Basin_#1)_ = 0
volume_conservation_Basin_#5_: 1 basin_storage_change_Basin_#5_ - 1 flow_(FlowBoundary_#3,_Basin_#5)_ + 1 flow_(Basin_#5,_Pump_#7)_ = 0
volume_conservation_Basin_#6_: 1 basin_storage_change_Basin_#6_ - 1 flow_(FlowBoundary_#4,_Basin_#6)_ + 1 flow_(Basin_#6,_Pump_#8)_ = 0
user_demand_allocated_sum_constraint_UserDemand_#2_: 1 flow_(Basin_#1,_UserDemand_#2)_ - 1 user_demand_allocated_UserDemand_#2,1_ = 0
user_demand_return_flow_UserDemand_#2_: 1 flow_(UserDemand_#2,_Basin_#1)_ = 0
average_flow_unit_error_constraint_1_: -1 user_demand_error_UserDemand_#2,1,first_ + 1 average_flow_unit_error_1_ = 0
Bounds
basin_storage_change_Basin_#1_ >= 0
basin_storage_change_Basin_#5_ >= -0.057472552095003356
basin_storage_change_Basin_#6_ >= -0.06083352005377548
0 <= low_storage_factor_Basin_#1_ <= 1
0 <= low_storage_factor_Basin_#5_ <= 1
0 <= low_storage_factor_Basin_#6_ <= 1
0 <= flow_(Basin_#1,_UserDemand_#2)_ <= 0.027223840466054222
0 <= flow_(UserDemand_#2,_Basin_#1)_ <= 0.027223840466054222
flow_(FlowBoundary_#3,_Basin_#5)_ = 0.016334304279632533
0 <= flow_(Basin_#5,_Pump_#7)_ <= 0.054447680932108444
0 <= flow_(Pump_#7,_Basin_#1)_ <= 0.054447680932108444
flow_(FlowBoundary_#4,_Basin_#6)_ = 0.016334304279632533
0 <= flow_(Basin_#6,_Pump_#8)_ <= 0.054447680932108444
0 <= flow_(Pump_#8,_Basin_#1)_ <= 0.054447680932108444
0 <= user_demand_allocated_UserDemand_#2,1_ <= 0.027223840466054222
0 <= user_demand_error_UserDemand_#2,1,first_ <= 1
0 <= user_demand_error_UserDemand_#2,1,second_ <= 1
0 <= average_flow_unit_error_1_ <= 1
flow_change_Pump_#7_ >= 0
flow_change_Pump_#8_ >= 0
End

minimize
obj: 
subject to
user_demand_relative_error_constraint_UserDemand_#60,2_: 1 user_demand_allocated_UserDemand_#60,2_ + 2 user_demand_error_UserDemand_#60,2,first_ >= 2
secondary_network_relative_error_constraint_(Pump_#11,_Basin_#12),1_: 1 secondary_network_allocated_(Pump_#11,_Basin_#12),1_ + 2 secondary_network_error_(Pump_#11,_Basin_#12),1,first_ >= 2
secondary_network_relative_error_constraint_(Pump_#11,_Basin_#12),2_: 1 secondary_network_allocated_(Pump_#11,_Basin_#12),2_ + 2 secondary_network_error_(Pump_#11,_Basin_#12),2,first_ >= 2
secondary_network_relative_error_constraint_(Pump_#24,_Basin_#25),1_: 1 secondary_network_allocated_(Pump_#24,_Basin_#25),1_ + 2 secondary_network_error_(Pump_#24,_Basin_#25),1,first_ >= 2
secondary_network_relative_error_constraint_(Pump_#38,_Basin_#35),1_: 1 secondary_network_allocated_(Pump_#38,_Basin_#35),1_ + 2 secondary_network_error_(Pump_#38,_Basin_#35),1,first_ >= 2
secondary_network_relative_error_constraint_(Pump_#38,_Basin_#35),2_: 1 secondary_network_allocated_(Pump_#38,_Basin_#35),2_ + 2 secondary_network_error_(Pump_#38,_Basin_#35),2,first_ >= 2
secondary_network_relative_error_constraint_(Pump_#38,_Basin_#35),3_: 1 secondary_network_allocated_(Pump_#38,_Basin_#35),3_ + 2 secondary_network_error_(Pump_#38,_Basin_#35),3,first_ >= 2
user_demand_fairness_error_constraint_UserDemand_#60,2_: -1 user_demand_error_UserDemand_#60,2,first_ + 1 user_demand_error_UserDemand_#60,2,second_ + 1 average_flow_unit_error_2_ >= 0
secondary_network_demand_fairness_error_constraint_(Pump_#11,_Basin_#12),1_: -1 secondary_network_error_(Pump_#11,_Basin_#12),1,first_ + 1 secondary_network_error_(Pump_#11,_Basin_#12),1,second_ + 1 average_flow_unit_error_1_ >= 0
secondary_network_demand_fairness_error_constraint_(Pump_#11,_Basin_#12),2_: -1 secondary_network_error_(Pump_#11,_Basin_#12),2,first_ + 1 secondary_network_error_(Pump_#11,_Basin_#12),2,second_ + 1 average_flow_unit_error_2_ >= 0
secondary_network_demand_fairness_error_constraint_(Pump_#24,_Basin_#25),1_: -1 secondary_network_error_(Pump_#24,_Basin_#25),1,first_ + 1 secondary_network_error_(Pump_#24,_Basin_#25),1,second_ + 1 average_flow_unit_error_1_ >= 0
secondary_network_demand_fairness_error_constraint_(Pump_#38,_Basin_#35),1_: -1 secondary_network_error_(Pump_#38,_Basin_#35),1,first_ + 1 secondary_network_error_(Pump_#38,_Basin_#35),1,second_ + 1 average_flow_unit_error_1_ >= 0
secondary_network_demand_fairness_error_constraint_(Pump_#38,_Basin_#35),2_: -1 secondary_network_error_(Pump_#38,_Basin_#35),2,first_ + 1 secondary_network_error_(Pump_#38,_Basin_#35),2,second_ + 1 average_flow_unit_error_2_ >= 0
secondary_network_demand_fairness_error_constraint_(Pump_#38,_Basin_#35),3_: -1 secondary_network_error_(Pump_#38,_Basin_#35),3,first_ + 1 secondary_network_error_(Pump_#38,_Basin_#35),3,second_ + 1 average_flow_unit_error_3_ >= 0
flow_conservation_pump_Pump_#11_: -1 flow_(Pump_#11,_Basin_#12)_ + 1 flow_(Basin_#2,_Pump_#11)_ = 0
flow_conservation_pump_Pump_#24_: -1 flow_(Pump_#24,_Basin_#25)_ + 1 flow_(Basin_#6,_Pump_#24)_ = 0
flow_conservation_pump_Pump_#38_: -1 flow_(Pump_#38,_Basin_#35)_ + 1 flow_(Basin_#10,_Pump_#38)_ = 0
flow_conservation_linear_resistance_LinearResistance_#3_: 1 flow_(Basin_#2,_LinearResistance_#3)_ - 1 flow_(LinearResistance_#3,_Basin_#4)_ = 0
flow_conservation_linear_resistance_LinearResistance_#5_: 1 flow_(Basin_#4,_LinearResistance_#5)_ - 1 flow_(LinearResistance_#5,_Basin_#6)_ = 0
flow_conservation_linear_resistance_LinearResistance_#7_: 1 flow_(Basin_#6,_LinearResistance_#7)_ - 1 flow_(LinearResistance_#7,_Basin_#8)_ = 0
flow_conservation_linear_resistance_LinearResistance_#9_: 1 flow_(Basin_#8,_LinearResistance_#9)_ - 1 flow_(LinearResistance_#9,_Basin_#10)_ = 0
volume_conservation_Basin_#2_: 1 basin_storage_change_Basin_#2_ + 1 low_storage_factor_Basin_#2_ - 1 flow_(FlowBoundary_#1,_Basin_#2)_ + 1 flow_(Basin_#2,_LinearResistance_#3)_ + 1 flow_(Basin_#2,_Pump_#11)_ = 1
volume_conservation_Basin_#4_: 1 basin_storage_change_Basin_#4_ + 1 low_storage_factor_Basin_#4_ - 1 flow_(LinearResistance_#3,_Basin_#4)_ + 1 flow_(Basin_#4,_LinearResistance_#5)_ = 1
volume_conservation_Basin_#6_: 1 basin_storage_change_Basin_#6_ + 1 low_storage_factor_Basin_#6_ - 1 flow_(LinearResistance_#5,_Basin_#6)_ + 1 flow_(Basin_#6,_LinearResistance_#7)_ + 1 flow_(Basin_#6,_Pump_#24)_ = 1
volume_conservation_Basin_#8_: 1 basin_storage_change_Basin_#8_ + 1 low_storage_factor_Basin_#8_ - 1 flow_(LinearResistance_#7,_Basin_#8)_ + 1 flow_(Basin_#8,_LinearResistance_#9)_ + 1 flow_(Basin_#8,_UserDemand_#60)_ - 1 flow_(UserDemand_#60,_Basin_#8)_ = 1
volume_conservation_Basin_#10_: 1 basin_storage_change_Basin_#10_ + 1 low_storage_factor_Basin_#10_ - 1 flow_(LinearResistance_#9,_Basin_#10)_ + 1 flow_(Basin_#10,_Pump_#38)_ = 1
linear_resistance_constraint_LinearResistance_#3_: -0.01 basin_storage_change_Basin_#2_ + 0.01 basin_storage_change_Basin_#4_ + 1 flow_(Basin_#2,_LinearResistance_#3)_ = 1
linear_resistance_constraint_LinearResistance_#5_: -0.01 basin_storage_change_Basin_#4_ + 0.01 basin_storage_change_Basin_#6_ + 1 flow_(Basin_#4,_LinearResistance_#5)_ = 1
linear_resistance_constraint_LinearResistance_#7_: -0.01 basin_storage_change_Basin_#6_ + 0.01 basin_storage_change_Basin_#8_ + 1 flow_(Basin_#6,_LinearResistance_#7)_ = 1
linear_resistance_constraint_LinearResistance_#9_: -0.01 basin_storage_change_Basin_#8_ + 0.01 basin_storage_change_Basin_#10_ + 1 flow_(Basin_#8,_LinearResistance_#9)_ = 1
user_demand_allocated_sum_constraint_UserDemand_#60_: 1 flow_(Basin_#8,_UserDemand_#60)_ - 1 user_demand_allocated_UserDemand_#60,2_ = 0
user_demand_return_flow_UserDemand_#60_: -0.5 flow_(Basin_#8,_UserDemand_#60)_ + 1 flow_(UserDemand_#60,_Basin_#8)_ = 0
secondary_network_allocated_sum_constraint_(Pump_#11,_Basin_#12)_: 1 flow_(Pump_#11,_Basin_#12)_ - 1 secondary_network_allocated_(Pump_#11,_Basin_#12),1_ - 1 secondary_network_allocated_(Pump_#11,_Basin_#12),2_ = 0
secondary_network_allocated_sum_constraint_(Pump_#24,_Basin_#25)_: 1 flow_(Pump_#24,_Basin_#25)_ - 1 secondary_network_allocated_(Pump_#24,_Basin_#25),1_ = 0
secondary_network_allocated_sum_constraint_(Pump_#38,_Basin_#35)_: 1 flow_(Pump_#38,_Basin_#35)_ - 1 secondary_network_allocated_(Pump_#38,_Basin_#35),1_ - 1 secondary_network_allocated_(Pump_#38,_Basin_#35),2_ - 1 secondary_network_allocated_(Pump_#38,_Basin_#35),3_ = 0
average_flow_unit_error_constraint_1_: -1 secondary_network_error_(Pump_#11,_Basin_#12),1,first_ - 1 secondary_network_error_(Pump_#24,_Basin_#25),1,first_ - 1 secondary_network_error_(Pump_#38,_Basin_#35),1,first_ + 1 average_flow_unit_error_1_ = 0
average_flow_unit_error_constraint_2_: -1 user_demand_error_UserDemand_#60,2,first_ - 1 secondary_network_error_(Pump_#11,_Basin_#12),2,first_ - 1 secondary_network_error_(Pump_#38,_Basin_#35),2,first_ + 1 average_flow_unit_error_2_ = 0
average_flow_unit_error_constraint_3_: -1 secondary_network_error_(Pump_#38,_Basin_#35),3,first_ + 1 average_flow_unit_error_3_ = 0
Bounds
-2 <= basin_storage_change_Basin_#2_ <= 8
-2 <= basin_storage_change_Basin_#4_ <= 8
-2 <= basin_storage_change_Basin_#6_ <= 8
-2 <= basin_storage_change_Basin_#8_ <= 8
-2 <= basin_storage_change_Basin_#10_ <= 8
0 <= low_storage_factor_Basin_#2_ <= 1
0 <= low_storage_factor_Basin_#4_ <= 1
0 <= low_storage_factor_Basin_#6_ <= 1
0 <= low_storage_factor_Basin_#8_ <= 1
0 <= low_storage_factor_Basin_#10_ <= 1
0 <= flow_(FlowBoundary_#1,_Basin_#2)_ <= 86400000
-86400000 <= flow_(Basin_#2,_LinearResistance_#3)_ <= 86400000
-86400000 <= flow_(LinearResistance_#3,_Basin_#4)_ <= 86400000
-86400000 <= flow_(Basin_#4,_LinearResistance_#5)_ <= 86400000
-86400000 <= flow_(LinearResistance_#5,_Basin_#6)_ <= 86400000
-86400000 <= flow_(Basin_#6,_LinearResistance_#7)_ <= 86400000
-86400000 <= flow_(LinearResistance_#7,_Basin_#8)_ <= 86400000
-86400000 <= flow_(Basin_#8,_LinearResistance_#9)_ <= 86400000
-86400000 <= flow_(LinearResistance_#9,_Basin_#10)_ <= 86400000
0 <= flow_(Pump_#11,_Basin_#12)_ <= 1728
0 <= flow_(Pump_#24,_Basin_#25)_ <= 172.8
0 <= flow_(Pump_#38,_Basin_#35)_ <= 172.8
0 <= flow_(Basin_#2,_Pump_#11)_ <= 1728
0 <= flow_(Basin_#6,_Pump_#24)_ <= 172.8
0 <= flow_(Basin_#10,_Pump_#38)_ <= 172.8
0 <= flow_(Basin_#8,_UserDemand_#60)_ <= 86400000
0 <= flow_(UserDemand_#60,_Basin_#8)_ <= 86400000
0 <= user_demand_allocated_UserDemand_#60,2_ <= 2
0 <= user_demand_error_UserDemand_#60,2,first_ <= 1
0 <= user_demand_error_UserDemand_#60,2,second_ <= 1
0 <= secondary_network_allocated_(Pump_#11,_Basin_#12),1_ <= 2
0 <= secondary_network_allocated_(Pump_#11,_Basin_#12),2_ <= 2
0 <= secondary_network_allocated_(Pump_#24,_Basin_#25),1_ <= 2
0 <= secondary_network_allocated_(Pump_#38,_Basin_#35),1_ <= 2
0 <= secondary_network_allocated_(Pump_#38,_Basin_#35),2_ <= 2
0 <= secondary_network_allocated_(Pump_#38,_Basin_#35),3_ <= 2
0 <= secondary_network_error_(Pump_#11,_Basin_#12),1,first_ <= 1
0 <= secondary_network_error_(Pump_#11,_Basin_#12),1,second_ <= 1
0 <= secondary_network_error_(Pump_#11,_Basin_#12),2,first_ <= 1
0 <= secondary_network_error_(Pump_#11,_Basin_#12),2,second_ <= 1
0 <= secondary_network_error_(Pump_#24,_Basin_#25),1,first_ <= 1
0 <= secondary_network_error_(Pump_#24,_Basin_#25),1,second_ <= 1
0 <= secondary_network_error_(Pump_#38,_Basin_#35),1,first_ <= 1
0 <= secondary_network_error_(Pump_#38,_Basin_#35),1,second_ <= 1
0 <= secondary_network_error_(Pump_#38,_Basin_#35),2,first_ <= 1
0 <= secondary_network_error_(Pump_#38,_Basin_#35),2,second_ <= 1
0 <= secondary_network_error_(Pump_#38,_Basin_#35),3,first_ <= 1
0 <= secondary_network_error_(Pump_#38,_Basin_#35),3,second_ <= 1
0 <= average_flow_unit_error_1_ <= 1
0 <= average_flow_unit_error_2_ <= 1
0 <= average_flow_unit_error_3_ <= 1
End

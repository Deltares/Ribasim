minimize
obj: 
subject to
user_demand_relative_error_constraint_UserDemand_#12,3_: 1 user_demand_allocated_UserDemand_#12,3_ + 2 user_demand_error_UserDemand_#12,3,first_ >= 2
user_demand_relative_error_constraint_UserDemand_#14,3_: 1 user_demand_allocated_UserDemand_#14,3_ + 2 user_demand_error_UserDemand_#14,3,first_ >= 2
user_demand_relative_error_constraint_UserDemand_#17,3_: 1 user_demand_allocated_UserDemand_#17,3_ + 2 user_demand_error_UserDemand_#17,3,first_ >= 2
storage_constraint_lower_Basin_#2,1_: 1 basin_storage_change_Basin_#2_ + 1 level_demand_error_Basin_#2,1,lower,first_ >= -250
storage_constraint_lower_Basin_#5,1_: 1 basin_storage_change_Basin_#5_ + 1 level_demand_error_Basin_#5,1,lower,first_ >= -250
storage_constraint_lower_Basin_#7,1_: 1 basin_storage_change_Basin_#7_ + 1 level_demand_error_Basin_#7,1,lower,first_ >= -250
storage_constraint_lower_Basin_#10,1_: 1 basin_storage_change_Basin_#10_ + 1 level_demand_error_Basin_#10,1,lower,first_ >= -250
storage_constraint_lower_Basin_#13,2_: 1 basin_storage_change_Basin_#13_ + 1 level_demand_error_Basin_#13,2,lower,first_ >= -250
storage_constraint_lower_Basin_#15,2_: 1 basin_storage_change_Basin_#15_ + 1 level_demand_error_Basin_#15,2,lower,first_ >= -250
storage_constraint_upper_Basin_#2,1_: -1 basin_storage_change_Basin_#2_ + 1 level_demand_error_Basin_#2,1,upper,first_ >= -750
storage_constraint_upper_Basin_#5,1_: -1 basin_storage_change_Basin_#5_ + 1 level_demand_error_Basin_#5,1,upper,first_ >= -750
storage_constraint_upper_Basin_#7,1_: -1 basin_storage_change_Basin_#7_ + 1 level_demand_error_Basin_#7,1,upper,first_ >= -750
storage_constraint_upper_Basin_#10,1_: -1 basin_storage_change_Basin_#10_ + 1 level_demand_error_Basin_#10,1,upper,first_ >= -750
storage_constraint_upper_Basin_#13,2_: -1 basin_storage_change_Basin_#13_ + 1 level_demand_error_Basin_#13,2,upper,first_ >= -750
storage_constraint_upper_Basin_#15,2_: -1 basin_storage_change_Basin_#15_ + 1 level_demand_error_Basin_#15,2,upper,first_ >= -750
user_demand_fairness_error_constraint_UserDemand_#12,3_: -1 user_demand_error_UserDemand_#12,3,first_ + 1 user_demand_error_UserDemand_#12,3,second_ + 1 average_flow_unit_error_3_ >= 0
user_demand_fairness_error_constraint_UserDemand_#14,3_: -1 user_demand_error_UserDemand_#14,3,first_ + 1 user_demand_error_UserDemand_#14,3,second_ + 1 average_flow_unit_error_3_ >= 0
user_demand_fairness_error_constraint_UserDemand_#17,3_: -1 user_demand_error_UserDemand_#17,3,first_ + 1 user_demand_error_UserDemand_#17,3,second_ + 1 average_flow_unit_error_3_ >= 0
level_demand_fairness_error_constraint_Basin_#2,1,lower_: -0.001 level_demand_error_Basin_#2,1,lower,first_ + 1 level_demand_error_Basin_#2,1,lower,second_ + 1 average_storage_unit_error_1,lower_ >= 0
level_demand_fairness_error_constraint_Basin_#2,1,upper_: -0.001 level_demand_error_Basin_#2,1,upper,first_ + 1 level_demand_error_Basin_#2,1,upper,second_ + 1 average_storage_unit_error_1,upper_ >= 0
level_demand_fairness_error_constraint_Basin_#5,1,lower_: -0.001 level_demand_error_Basin_#5,1,lower,first_ + 1 level_demand_error_Basin_#5,1,lower,second_ + 1 average_storage_unit_error_1,lower_ >= 0
level_demand_fairness_error_constraint_Basin_#5,1,upper_: -0.001 level_demand_error_Basin_#5,1,upper,first_ + 1 level_demand_error_Basin_#5,1,upper,second_ + 1 average_storage_unit_error_1,upper_ >= 0
level_demand_fairness_error_constraint_Basin_#7,1,lower_: -0.001 level_demand_error_Basin_#7,1,lower,first_ + 1 level_demand_error_Basin_#7,1,lower,second_ + 1 average_storage_unit_error_1,lower_ >= 0
level_demand_fairness_error_constraint_Basin_#7,1,upper_: -0.001 level_demand_error_Basin_#7,1,upper,first_ + 1 level_demand_error_Basin_#7,1,upper,second_ + 1 average_storage_unit_error_1,upper_ >= 0
level_demand_fairness_error_constraint_Basin_#10,1,lower_: -0.001 level_demand_error_Basin_#10,1,lower,first_ + 1 level_demand_error_Basin_#10,1,lower,second_ + 1 average_storage_unit_error_1,lower_ >= 0
level_demand_fairness_error_constraint_Basin_#10,1,upper_: -0.001 level_demand_error_Basin_#10,1,upper,first_ + 1 level_demand_error_Basin_#10,1,upper,second_ + 1 average_storage_unit_error_1,upper_ >= 0
level_demand_fairness_error_constraint_Basin_#13,2,lower_: -0.001 level_demand_error_Basin_#13,2,lower,first_ + 1 level_demand_error_Basin_#13,2,lower,second_ + 1 average_storage_unit_error_2,lower_ >= 0
level_demand_fairness_error_constraint_Basin_#13,2,upper_: -0.001 level_demand_error_Basin_#13,2,upper,first_ + 1 level_demand_error_Basin_#13,2,upper,second_ + 1 average_storage_unit_error_2,upper_ >= 0
level_demand_fairness_error_constraint_Basin_#15,2,lower_: -0.001 level_demand_error_Basin_#15,2,lower,first_ + 1 level_demand_error_Basin_#15,2,lower,second_ + 1 average_storage_unit_error_2,lower_ >= 0
level_demand_fairness_error_constraint_Basin_#15,2,upper_: -0.001 level_demand_error_Basin_#15,2,upper,first_ + 1 level_demand_error_Basin_#15,2,upper,second_ + 1 average_storage_unit_error_2,upper_ >= 0
flow_conservation_pump_Pump_#6_: 1 flow_(Basin_#5,_Pump_#6)_ - 1 flow_(Pump_#6,_Basin_#13)_ = 0
flow_conservation_pump_Pump_#11_: 1 flow_(Basin_#10,_Pump_#11)_ - 1 flow_(Pump_#11,_Basin_#15)_ = 0
flow_conservation_outlet_Outlet_#3_: 1 flow_(Basin_#2,_Outlet_#3)_ - 1 flow_(Outlet_#3,_Basin_#13)_ = 0
flow_conservation_outlet_Outlet_#4_: 1 flow_(Basin_#2,_Outlet_#4)_ - 1 flow_(Outlet_#4,_Basin_#5)_ = 0
flow_conservation_outlet_Outlet_#8_: 1 flow_(Basin_#7,_Outlet_#8)_ - 1 flow_(Outlet_#8,_Basin_#15)_ = 0
flow_conservation_outlet_Outlet_#9_: 1 flow_(Basin_#7,_Outlet_#9)_ - 1 flow_(Outlet_#9,_Basin_#10)_ = 0
flow_conservation_outlet_Outlet_#16_: 1 flow_(Basin_#5,_Outlet_#16)_ - 1 flow_(Outlet_#16,_Basin_#7)_ = 0
flow_conservation_outlet_Outlet_#21_: 1 flow_(Basin_#10,_Outlet_#21)_ - 1 flow_(Outlet_#21,_Terminal_#22)_ = 0
volume_conservation_Basin_#2_: 1 basin_storage_change_Basin_#2_ + 1 low_storage_factor_Basin_#2_ - 1 flow_(FlowBoundary_#1,_Basin_#2)_ + 1 flow_(Basin_#2,_Outlet_#3)_ + 1 flow_(Basin_#2,_Outlet_#4)_ = 1
volume_conservation_Basin_#5_: 1 basin_storage_change_Basin_#5_ + 1 low_storage_factor_Basin_#5_ - 1 flow_(Outlet_#4,_Basin_#5)_ + 1 flow_(Basin_#5,_Pump_#6)_ + 1 flow_(Basin_#5,_Outlet_#16)_ = 1
volume_conservation_Basin_#7_: 1 basin_storage_change_Basin_#7_ + 1 low_storage_factor_Basin_#7_ - 1 flow_(Outlet_#16,_Basin_#7)_ + 1 flow_(Basin_#7,_Outlet_#8)_ + 1 flow_(Basin_#7,_Outlet_#9)_ = 1
volume_conservation_Basin_#10_: 1 basin_storage_change_Basin_#10_ + 1 low_storage_factor_Basin_#10_ - 1 flow_(Outlet_#9,_Basin_#10)_ + 1 flow_(Basin_#10,_Pump_#11)_ + 1 flow_(Basin_#10,_UserDemand_#12)_ - 1 flow_(UserDemand_#12,_Basin_#10)_ + 1 flow_(Basin_#10,_Outlet_#21)_ = 1
volume_conservation_Basin_#13_: 1 basin_storage_change_Basin_#13_ + 1 low_storage_factor_Basin_#13_ - 1 flow_(Outlet_#3,_Basin_#13)_ - 1 flow_(Pump_#6,_Basin_#13)_ + 1 flow_(Basin_#13,_UserDemand_#14)_ - 1 flow_(UserDemand_#14,_Basin_#13)_ = 1
volume_conservation_Basin_#15_: 1 basin_storage_change_Basin_#15_ + 1 low_storage_factor_Basin_#15_ - 1 flow_(Outlet_#8,_Basin_#15)_ - 1 flow_(Pump_#11,_Basin_#15)_ + 1 flow_(Basin_#15,_UserDemand_#17)_ - 1 flow_(UserDemand_#17,_Basin_#15)_ = 1
user_demand_allocated_sum_constraint_UserDemand_#12_: 1 flow_(Basin_#10,_UserDemand_#12)_ - 1 user_demand_allocated_UserDemand_#12,3_ = 0
user_demand_allocated_sum_constraint_UserDemand_#14_: 1 flow_(Basin_#13,_UserDemand_#14)_ - 1 user_demand_allocated_UserDemand_#14,3_ = 0
user_demand_allocated_sum_constraint_UserDemand_#17_: 1 flow_(Basin_#15,_UserDemand_#17)_ - 1 user_demand_allocated_UserDemand_#17,3_ = 0
user_demand_return_flow_UserDemand_#12_: -0.5 flow_(Basin_#10,_UserDemand_#12)_ + 1 flow_(UserDemand_#12,_Basin_#10)_ = 0
user_demand_return_flow_UserDemand_#14_: -0.5 flow_(Basin_#13,_UserDemand_#14)_ + 1 flow_(UserDemand_#14,_Basin_#13)_ = 0
user_demand_return_flow_UserDemand_#17_: -0.5 flow_(Basin_#15,_UserDemand_#17)_ + 1 flow_(UserDemand_#17,_Basin_#15)_ = 0
average_flow_unit_error_constraint_3_: -1 user_demand_error_UserDemand_#12,3,first_ - 1 user_demand_error_UserDemand_#14,3,first_ - 1 user_demand_error_UserDemand_#17,3,first_ + 1 average_flow_unit_error_3_ = 0
average_storage_unit_error_constraint_1,upper_: -1 level_demand_error_Basin_#2,1,upper,first_ - 1 level_demand_error_Basin_#5,1,upper,first_ - 1 level_demand_error_Basin_#7,1,upper,first_ - 1 level_demand_error_Basin_#10,1,upper,first_ + 1000 average_storage_unit_error_1,upper_ = 0
average_storage_unit_error_constraint_2,upper_: -1 level_demand_error_Basin_#13,2,upper,first_ - 1 level_demand_error_Basin_#15,2,upper,first_ + 1000 average_storage_unit_error_2,upper_ = 0
average_storage_unit_error_constraint_1,lower_: -1 level_demand_error_Basin_#2,1,lower,first_ - 1 level_demand_error_Basin_#5,1,lower,first_ - 1 level_demand_error_Basin_#7,1,lower,first_ - 1 level_demand_error_Basin_#10,1,lower,first_ + 1000 average_storage_unit_error_1,lower_ = 0
average_storage_unit_error_constraint_2,lower_: -1 level_demand_error_Basin_#13,2,lower,first_ - 1 level_demand_error_Basin_#15,2,lower,first_ + 1000 average_storage_unit_error_2,lower_ = 0
Bounds
-0.02 <= basin_storage_change_Basin_#2_ <= 0.08
-0.02 <= basin_storage_change_Basin_#5_ <= 0.08
-0.02 <= basin_storage_change_Basin_#7_ <= 0.08
-0.02 <= basin_storage_change_Basin_#10_ <= 0.08
-0.02 <= basin_storage_change_Basin_#13_ <= 0.08
-0.02 <= basin_storage_change_Basin_#15_ <= 0.08
0 <= low_storage_factor_Basin_#2_ <= 1
0 <= low_storage_factor_Basin_#5_ <= 1
0 <= low_storage_factor_Basin_#7_ <= 1
0 <= low_storage_factor_Basin_#10_ <= 1
0 <= low_storage_factor_Basin_#13_ <= 1
0 <= low_storage_factor_Basin_#15_ <= 1
0 <= flow_(FlowBoundary_#1,_Basin_#2)_ <= 864000
0 <= flow_(Basin_#2,_Outlet_#3)_ <= 0.001728
0 <= flow_(Basin_#2,_Outlet_#4)_ <= 1.728
0 <= flow_(Outlet_#4,_Basin_#5)_ <= 1.728
0 <= flow_(Basin_#5,_Pump_#6)_ <= 1.728
0 <= flow_(Basin_#5,_Outlet_#16)_ <= 1.728
0 <= flow_(Outlet_#16,_Basin_#7)_ <= 1.728
0 <= flow_(Basin_#7,_Outlet_#8)_ <= 0.001728
0 <= flow_(Basin_#7,_Outlet_#9)_ <= 1.728
0 <= flow_(Outlet_#9,_Basin_#10)_ <= 1.728
0 <= flow_(Basin_#10,_Pump_#11)_ <= 1.728
0 <= flow_(Basin_#10,_UserDemand_#12)_ <= 864000
0 <= flow_(UserDemand_#12,_Basin_#10)_ <= 864000
0 <= flow_(Basin_#10,_Outlet_#21)_ <= 1.728
0 <= flow_(Outlet_#21,_Terminal_#22)_ <= 1.728
0 <= flow_(Outlet_#3,_Basin_#13)_ <= 0.001728
0 <= flow_(Pump_#6,_Basin_#13)_ <= 1.728
0 <= flow_(Basin_#13,_UserDemand_#14)_ <= 864000
0 <= flow_(UserDemand_#14,_Basin_#13)_ <= 864000
0 <= flow_(Outlet_#8,_Basin_#15)_ <= 0.001728
0 <= flow_(Pump_#11,_Basin_#15)_ <= 1.728
0 <= flow_(Basin_#15,_UserDemand_#17)_ <= 864000
0 <= flow_(UserDemand_#17,_Basin_#15)_ <= 864000
0 <= user_demand_allocated_UserDemand_#12,3_ <= 2
0 <= user_demand_allocated_UserDemand_#14,3_ <= 2
0 <= user_demand_allocated_UserDemand_#17,3_ <= 2
0 <= user_demand_error_UserDemand_#12,3,first_ <= 1
0 <= user_demand_error_UserDemand_#12,3,second_ <= 1
0 <= user_demand_error_UserDemand_#14,3,first_ <= 1
0 <= user_demand_error_UserDemand_#14,3,second_ <= 1
0 <= user_demand_error_UserDemand_#17,3,first_ <= 1
0 <= user_demand_error_UserDemand_#17,3,second_ <= 1
level_demand_error_Basin_#2,1,lower,first_ >= 0
level_demand_error_Basin_#2,1,lower,second_ >= 0
level_demand_error_Basin_#2,1,upper,first_ >= 0
level_demand_error_Basin_#2,1,upper,second_ >= 0
level_demand_error_Basin_#5,1,lower,first_ >= 0
level_demand_error_Basin_#5,1,lower,second_ >= 0
level_demand_error_Basin_#5,1,upper,first_ >= 0
level_demand_error_Basin_#5,1,upper,second_ >= 0
level_demand_error_Basin_#7,1,lower,first_ >= 0
level_demand_error_Basin_#7,1,lower,second_ >= 0
level_demand_error_Basin_#7,1,upper,first_ >= 0
level_demand_error_Basin_#7,1,upper,second_ >= 0
level_demand_error_Basin_#10,1,lower,first_ >= 0
level_demand_error_Basin_#10,1,lower,second_ >= 0
level_demand_error_Basin_#10,1,upper,first_ >= 0
level_demand_error_Basin_#10,1,upper,second_ >= 0
level_demand_error_Basin_#13,2,lower,first_ >= 0
level_demand_error_Basin_#13,2,lower,second_ >= 0
level_demand_error_Basin_#13,2,upper,first_ >= 0
level_demand_error_Basin_#13,2,upper,second_ >= 0
level_demand_error_Basin_#15,2,lower,first_ >= 0
level_demand_error_Basin_#15,2,lower,second_ >= 0
level_demand_error_Basin_#15,2,upper,first_ >= 0
level_demand_error_Basin_#15,2,upper,second_ >= 0
0 <= average_flow_unit_error_3_ <= 1
average_storage_unit_error_1,lower_ >= 0
average_storage_unit_error_2,lower_ >= 0
average_storage_unit_error_1,upper_ >= 0
average_storage_unit_error_2,upper_ >= 0
End

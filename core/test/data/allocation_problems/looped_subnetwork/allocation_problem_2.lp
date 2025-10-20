minimize
obj: 
subject to
user_demand_relative_error_constraint_UserDemand_#1,2_: 1 user_demand_allocated_UserDemand_#1,2_ + 2 user_demand_error_UserDemand_#1,2,first_ >= 2
user_demand_relative_error_constraint_UserDemand_#12,1_: 1 user_demand_allocated_UserDemand_#12,1_ + 2 user_demand_error_UserDemand_#12,1,first_ >= 2
user_demand_relative_error_constraint_UserDemand_#18,3_: 1 user_demand_allocated_UserDemand_#18,3_ + 2 user_demand_error_UserDemand_#18,3,first_ >= 2
user_demand_relative_error_constraint_UserDemand_#20,3_: 1 user_demand_allocated_UserDemand_#20,3_ + 2 user_demand_error_UserDemand_#20,3,first_ >= 2
user_demand_relative_error_constraint_UserDemand_#24,2_: 1 user_demand_allocated_UserDemand_#24,2_ + 2 user_demand_error_UserDemand_#24,2,first_ >= 2
user_demand_fairness_error_constraint_UserDemand_#1,2_: -1 user_demand_error_UserDemand_#1,2,first_ + 1 user_demand_error_UserDemand_#1,2,second_ + 1 average_flow_unit_error_2_ >= 0
user_demand_fairness_error_constraint_UserDemand_#12,1_: -1 user_demand_error_UserDemand_#12,1,first_ + 1 user_demand_error_UserDemand_#12,1,second_ + 1 average_flow_unit_error_1_ >= 0
user_demand_fairness_error_constraint_UserDemand_#18,3_: -1 user_demand_error_UserDemand_#18,3,first_ + 1 user_demand_error_UserDemand_#18,3,second_ + 1 average_flow_unit_error_3_ >= 0
user_demand_fairness_error_constraint_UserDemand_#20,3_: -1 user_demand_error_UserDemand_#20,3,first_ + 1 user_demand_error_UserDemand_#20,3,second_ + 1 average_flow_unit_error_3_ >= 0
user_demand_fairness_error_constraint_UserDemand_#24,2_: -1 user_demand_error_UserDemand_#24,2,first_ + 1 user_demand_error_UserDemand_#24,2,second_ + 1 average_flow_unit_error_2_ >= 0
flow_conservation_pump_Pump_#6_: 1 flow_(Basin_#2,_Pump_#6)_ - 1 flow_(Pump_#6,_Basin_#9)_ = 0
flow_conservation_pump_Pump_#16_: 1 flow_(Basin_#15,_Pump_#16)_ - 1 flow_(Pump_#16,_Basin_#17)_ = 0
flow_conservation_outlet_Outlet_#3_: 1 flow_(Basin_#2,_Outlet_#3)_ - 1 flow_(Outlet_#3,_Terminal_#4)_ = 0
flow_conservation_outlet_Outlet_#8_: 1 flow_(Basin_#9,_Outlet_#8)_ - 1 flow_(Outlet_#8,_Basin_#7)_ = 0
flow_conservation_outlet_Outlet_#10_: 1 flow_(Basin_#9,_Outlet_#10)_ - 1 flow_(Outlet_#10,_Basin_#11)_ = 0
flow_conservation_outlet_Outlet_#22_: 1 flow_(Basin_#21,_Outlet_#22)_ - 1 flow_(Outlet_#22,_Terminal_#23)_ = 0
flow_conservation_tabulated_rating_curve_TabulatedRatingCurve_#13_: 1 flow_(Basin_#9,_TabulatedRatingCurve_#13)_ - 1 flow_(TabulatedRatingCurve_#13,_Basin_#15)_ = 0
flow_conservation_tabulated_rating_curve_TabulatedRatingCurve_#14_: 1 flow_(Basin_#11,_TabulatedRatingCurve_#14)_ - 1 flow_(TabulatedRatingCurve_#14,_Basin_#17)_ = 0
flow_conservation_tabulated_rating_curve_TabulatedRatingCurve_#19_: 1 flow_(Basin_#15,_TabulatedRatingCurve_#19)_ - 1 flow_(TabulatedRatingCurve_#19,_Basin_#21)_ = 0
volume_conservation_Basin_#2_: 1 basin_storage_change_Basin_#2_ + 1 low_storage_factor_Basin_#2_ - 1 flow_(FlowBoundary_#5,_Basin_#2)_ + 1 flow_(Basin_#2,_Outlet_#3)_ + 1 flow_(Basin_#2,_UserDemand_#1)_ + 1 flow_(Basin_#2,_Pump_#6)_ - 1 flow_(UserDemand_#1,_Basin_#2)_ = 1
volume_conservation_Basin_#7_: 1 basin_storage_change_Basin_#7_ + 1 low_storage_factor_Basin_#7_ - 1 flow_(Outlet_#8,_Basin_#7)_ + 1 flow_(Basin_#7,_UserDemand_#12)_ - 1 flow_(UserDemand_#12,_Basin_#7)_ = 1
volume_conservation_Basin_#9_: 1 basin_storage_change_Basin_#9_ + 1 low_storage_factor_Basin_#9_ - 1 flow_(Pump_#6,_Basin_#9)_ + 1 flow_(Basin_#9,_Outlet_#8)_ + 1 flow_(Basin_#9,_TabulatedRatingCurve_#13)_ + 1 flow_(Basin_#9,_Outlet_#10)_ = 1
volume_conservation_Basin_#11_: 1 basin_storage_change_Basin_#11_ + 1 low_storage_factor_Basin_#11_ - 1 flow_(Outlet_#10,_Basin_#11)_ + 1 flow_(Basin_#11,_TabulatedRatingCurve_#14)_ + 1 flow_(Basin_#11,_UserDemand_#24)_ - 1 flow_(UserDemand_#24,_Basin_#11)_ = 1
volume_conservation_Basin_#15_: 1 basin_storage_change_Basin_#15_ + 1 low_storage_factor_Basin_#15_ - 1 flow_(TabulatedRatingCurve_#13,_Basin_#15)_ + 1 flow_(Basin_#15,_Pump_#16)_ + 1 flow_(Basin_#15,_TabulatedRatingCurve_#19)_ + 1 flow_(Basin_#15,_UserDemand_#18)_ = 1
volume_conservation_Basin_#17_: 1 basin_storage_change_Basin_#17_ + 1 low_storage_factor_Basin_#17_ - 1 flow_(Pump_#16,_Basin_#17)_ + 1 flow_(Basin_#17,_UserDemand_#20)_ - 1 flow_(TabulatedRatingCurve_#14,_Basin_#17)_ - 1 flow_(UserDemand_#20,_Basin_#17)_ = 1
volume_conservation_Basin_#21_: 1 basin_storage_change_Basin_#21_ + 1 low_storage_factor_Basin_#21_ - 1 flow_(TabulatedRatingCurve_#19,_Basin_#21)_ - 1 flow_(UserDemand_#18,_Basin_#21)_ + 1 flow_(Basin_#21,_Outlet_#22)_ = 1
tabulated_rating_curve_constraint_TabulatedRatingCurve_#13_: -0.01 basin_storage_change_Basin_#9_ + 0.01 basin_storage_change_Basin_#15_ + 1 flow_(Basin_#9,_TabulatedRatingCurve_#13)_ = 1
tabulated_rating_curve_constraint_TabulatedRatingCurve_#14_: -0.01 basin_storage_change_Basin_#11_ + 0.01 basin_storage_change_Basin_#17_ + 1 flow_(Basin_#11,_TabulatedRatingCurve_#14)_ = 1
tabulated_rating_curve_constraint_TabulatedRatingCurve_#19_: -0.01 basin_storage_change_Basin_#15_ + 0.01 basin_storage_change_Basin_#21_ + 1 flow_(Basin_#15,_TabulatedRatingCurve_#19)_ = 1
pump_constraint_Pump_#6_: -1 low_storage_factor_Basin_#2_ + 1 flow_(Basin_#2,_Pump_#6)_ = 0
pump_constraint_Pump_#16_: -1 low_storage_factor_Basin_#15_ + 1 flow_(Basin_#15,_Pump_#16)_ = 0
outlet_constraint_Outlet_#3_: -1 low_storage_factor_Basin_#2_ + 1 flow_(Basin_#2,_Outlet_#3)_ = 0
outlet_constraint_Outlet_#8_: -1 low_storage_factor_Basin_#9_ + 1 flow_(Basin_#9,_Outlet_#8)_ = 0
outlet_constraint_Outlet_#10_: -1 low_storage_factor_Basin_#9_ + 1 flow_(Basin_#9,_Outlet_#10)_ = 0
outlet_constraint_Outlet_#22_: -1 low_storage_factor_Basin_#21_ + 1 flow_(Basin_#21,_Outlet_#22)_ = 0
user_demand_allocated_sum_constraint_UserDemand_#1_: 1 flow_(Basin_#2,_UserDemand_#1)_ - 1 user_demand_allocated_UserDemand_#1,2_ = 0
user_demand_allocated_sum_constraint_UserDemand_#12_: 1 flow_(Basin_#7,_UserDemand_#12)_ - 1 user_demand_allocated_UserDemand_#12,1_ = 0
user_demand_allocated_sum_constraint_UserDemand_#18_: 1 flow_(Basin_#15,_UserDemand_#18)_ - 1 user_demand_allocated_UserDemand_#18,3_ = 0
user_demand_allocated_sum_constraint_UserDemand_#20_: 1 flow_(Basin_#17,_UserDemand_#20)_ - 1 user_demand_allocated_UserDemand_#20,3_ = 0
user_demand_allocated_sum_constraint_UserDemand_#24_: 1 flow_(Basin_#11,_UserDemand_#24)_ - 1 user_demand_allocated_UserDemand_#24,2_ = 0
user_demand_return_flow_UserDemand_#1_: -0.5 flow_(Basin_#2,_UserDemand_#1)_ + 1 flow_(UserDemand_#1,_Basin_#2)_ = 0
user_demand_return_flow_UserDemand_#12_: -0.5 flow_(Basin_#7,_UserDemand_#12)_ + 1 flow_(UserDemand_#12,_Basin_#7)_ = 0
user_demand_return_flow_UserDemand_#18_: -0.5 flow_(Basin_#15,_UserDemand_#18)_ + 1 flow_(UserDemand_#18,_Basin_#21)_ = 0
user_demand_return_flow_UserDemand_#20_: -0.5 flow_(Basin_#17,_UserDemand_#20)_ + 1 flow_(UserDemand_#20,_Basin_#17)_ = 0
user_demand_return_flow_UserDemand_#24_: -0.5 flow_(Basin_#11,_UserDemand_#24)_ + 1 flow_(UserDemand_#24,_Basin_#11)_ = 0
average_flow_unit_error_constraint_1_: -1 user_demand_error_UserDemand_#12,1,first_ + 1 average_flow_unit_error_1_ = 0
average_flow_unit_error_constraint_2_: -1 user_demand_error_UserDemand_#1,2,first_ - 1 user_demand_error_UserDemand_#24,2,first_ + 1 average_flow_unit_error_2_ = 0
average_flow_unit_error_constraint_3_: -1 user_demand_error_UserDemand_#18,3,first_ - 1 user_demand_error_UserDemand_#20,3,first_ + 1 average_flow_unit_error_3_ = 0
Bounds
-2 <= basin_storage_change_Basin_#2_ <= 8
-2 <= basin_storage_change_Basin_#7_ <= 8
-2 <= basin_storage_change_Basin_#9_ <= 8
-2 <= basin_storage_change_Basin_#11_ <= 8
-2 <= basin_storage_change_Basin_#15_ <= 8
-2 <= basin_storage_change_Basin_#17_ <= 8
-2 <= basin_storage_change_Basin_#21_ <= 8
0 <= low_storage_factor_Basin_#2_ <= 1
0 <= low_storage_factor_Basin_#7_ <= 1
0 <= low_storage_factor_Basin_#9_ <= 1
0 <= low_storage_factor_Basin_#11_ <= 1
0 <= low_storage_factor_Basin_#15_ <= 1
0 <= low_storage_factor_Basin_#17_ <= 1
0 <= low_storage_factor_Basin_#21_ <= 1
0 <= flow_(FlowBoundary_#5,_Basin_#2)_ <= 86400000
0 <= flow_(Basin_#2,_Outlet_#3)_ <= 518.4
0 <= flow_(Outlet_#3,_Terminal_#4)_ <= 518.4
0 <= flow_(Basin_#2,_UserDemand_#1)_ <= 86400000
0 <= flow_(Basin_#2,_Pump_#6)_ <= 0.6912
0 <= flow_(Pump_#6,_Basin_#9)_ <= 0.6912
0 <= flow_(Basin_#9,_Outlet_#8)_ <= 518.4
0 <= flow_(Outlet_#8,_Basin_#7)_ <= 518.4
0 <= flow_(Basin_#7,_UserDemand_#12)_ <= 86400000
0 <= flow_(Basin_#9,_TabulatedRatingCurve_#13)_ <= 86400000
0 <= flow_(TabulatedRatingCurve_#13,_Basin_#15)_ <= 86400000
0 <= flow_(Basin_#15,_Pump_#16)_ <= 0.6912
0 <= flow_(Pump_#16,_Basin_#17)_ <= 0.6912
0 <= flow_(Basin_#17,_UserDemand_#20)_ <= 86400000
0 <= flow_(Basin_#15,_TabulatedRatingCurve_#19)_ <= 86400000
0 <= flow_(TabulatedRatingCurve_#19,_Basin_#21)_ <= 86400000
0 <= flow_(Basin_#15,_UserDemand_#18)_ <= 86400000
0 <= flow_(UserDemand_#18,_Basin_#21)_ <= 86400000
0 <= flow_(Basin_#21,_Outlet_#22)_ <= 518.4
0 <= flow_(Outlet_#22,_Terminal_#23)_ <= 518.4
0 <= flow_(Basin_#9,_Outlet_#10)_ <= 518.4
0 <= flow_(Outlet_#10,_Basin_#11)_ <= 518.4
0 <= flow_(Basin_#11,_TabulatedRatingCurve_#14)_ <= 86400000
0 <= flow_(TabulatedRatingCurve_#14,_Basin_#17)_ <= 86400000
0 <= flow_(UserDemand_#1,_Basin_#2)_ <= 86400000
0 <= flow_(UserDemand_#12,_Basin_#7)_ <= 86400000
0 <= flow_(UserDemand_#20,_Basin_#17)_ <= 86400000
0 <= flow_(Basin_#11,_UserDemand_#24)_ <= 86400000
0 <= flow_(UserDemand_#24,_Basin_#11)_ <= 86400000
0 <= user_demand_allocated_UserDemand_#1,2_ <= 2
0 <= user_demand_allocated_UserDemand_#12,1_ <= 2
0 <= user_demand_allocated_UserDemand_#18,3_ <= 2
0 <= user_demand_allocated_UserDemand_#20,3_ <= 2
0 <= user_demand_allocated_UserDemand_#24,2_ <= 2
0 <= user_demand_error_UserDemand_#1,2,first_ <= 1
0 <= user_demand_error_UserDemand_#1,2,second_ <= 1
0 <= user_demand_error_UserDemand_#12,1,first_ <= 1
0 <= user_demand_error_UserDemand_#12,1,second_ <= 1
0 <= user_demand_error_UserDemand_#18,3,first_ <= 1
0 <= user_demand_error_UserDemand_#18,3,second_ <= 1
0 <= user_demand_error_UserDemand_#20,3,first_ <= 1
0 <= user_demand_error_UserDemand_#20,3,second_ <= 1
0 <= user_demand_error_UserDemand_#24,2,first_ <= 1
0 <= user_demand_error_UserDemand_#24,2,second_ <= 1
0 <= average_flow_unit_error_1_ <= 1
0 <= average_flow_unit_error_2_ <= 1
0 <= average_flow_unit_error_3_ <= 1
End

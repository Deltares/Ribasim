minimize
obj: 
subject to
c1_2: 1 __8_3_ - 1 y_8_1_ <= 0
c2_2: 1 __9_3_ - 1 y_9_1_ <= 0
c3_2: 1 __10_3_ - 1 y_10_1_ <= 0
c4_1: 1 __11_3_ - 1 y_11_1_ <= 0
c5_2: 1 __12_3_ - 1 y_12_1_ <= 0
c6_2: 1 __13_3_ - 1 y_13_1_ <= 0
c7_2: 1 __14_3_ - 1 y_14_1_ <= 0
c8_1: 1 __15_3_ - 1 y_15_1_ <= 0
c9_2: 1 __16_3_ - 1 y_16_1_ <= 0
c10_2: 1 __17_3_ - 1 y_17_1_ <= 0
c1_1: 1 __8_2_ + 1 __8_3_ - 1 y_8_1_ >= 0
c2_1: 1 __9_2_ + 1 __9_3_ - 1 y_9_1_ >= 0
c3_1: 1 __10_2_ + 1 __10_3_ - 1 y_10_1_ >= 0
c4: 1 __11_2_ + 1 __11_3_ - 1 y_11_1_ >= 0
c5_1: 1 __12_2_ + 1 __12_3_ - 1 y_12_1_ >= 0
c6_1: 1 __13_2_ + 1 __13_3_ - 1 y_13_1_ >= 0
c7_1: 1 __14_2_ + 1 __14_3_ - 1 y_14_1_ >= 0
c8: 1 __15_2_ + 1 __15_3_ - 1 y_15_1_ >= 0
c9_1: 1 __16_2_ + 1 __16_3_ - 1 y_16_1_ >= 0
c10_1: 1 __17_2_ + 1 __17_3_ - 1 y_17_1_ >= 0
user_demand_constraint_lower_UserDemand_#1_: 1 flow_(Basin_#2,_UserDemand_#1)_ - 2 target_fraction - 1 user_demand_allocated_UserDemand_#1_ + 2 relative_user_demand_error_lower_UserDemand_#1_ >= 0
user_demand_constraint_lower_UserDemand_#12_: 1 flow_(Basin_#7,_UserDemand_#12)_ - 2 target_fraction - 1 user_demand_allocated_UserDemand_#12_ + 2 relative_user_demand_error_lower_UserDemand_#12_ >= 0
user_demand_constraint_lower_UserDemand_#18_: 1 flow_(Basin_#15,_UserDemand_#18)_ - 2 target_fraction - 1 user_demand_allocated_UserDemand_#18_ + 2 relative_user_demand_error_lower_UserDemand_#18_ >= 0
user_demand_constraint_lower_UserDemand_#20_: 1 flow_(Basin_#17,_UserDemand_#20)_ - 2 target_fraction - 1 user_demand_allocated_UserDemand_#20_ + 2 relative_user_demand_error_lower_UserDemand_#20_ >= 0
user_demand_constraint_lower_UserDemand_#24_: 1 flow_(Basin_#11,_UserDemand_#24)_ - 2 target_fraction - 1 user_demand_allocated_UserDemand_#24_ + 2 relative_user_demand_error_lower_UserDemand_#24_ >= 0
user_demand_constraint_upper_UserDemand_#1_: -1 flow_(Basin_#2,_UserDemand_#1)_ + 2 target_fraction + 1 user_demand_allocated_UserDemand_#1_ + 2 relative_user_demand_error_upper_UserDemand_#1_ >= 0
user_demand_constraint_upper_UserDemand_#12_: -1 flow_(Basin_#7,_UserDemand_#12)_ + 2 target_fraction + 1 user_demand_allocated_UserDemand_#12_ + 2 relative_user_demand_error_upper_UserDemand_#12_ >= 0
user_demand_constraint_upper_UserDemand_#18_: -1 flow_(Basin_#15,_UserDemand_#18)_ + 2 target_fraction + 1 user_demand_allocated_UserDemand_#18_ + 2 relative_user_demand_error_upper_UserDemand_#18_ >= 0
user_demand_constraint_upper_UserDemand_#20_: -1 flow_(Basin_#17,_UserDemand_#20)_ + 2 target_fraction + 1 user_demand_allocated_UserDemand_#20_ + 2 relative_user_demand_error_upper_UserDemand_#20_ >= 0
user_demand_constraint_upper_UserDemand_#24_: -1 flow_(Basin_#11,_UserDemand_#24)_ + 2 target_fraction + 1 user_demand_allocated_UserDemand_#24_ + 2 relative_user_demand_error_upper_UserDemand_#24_ >= 0
c1: 1 __1_1_ + 1 __1_2_ = 1
c2: -1 basin_storage_(Basin_#2,__end)_ + 2 __1_2_ = 0
c3: -1 z_1 + 1 __1_2_ = 0
basin_profile_Basin_#2_: 1 basin_level_Basin_#2_ - 1 z_1 = 0
c5: 1 __2_1_ + 1 __2_2_ = 1
c6: -1 basin_storage_(Basin_#7,__end)_ + 2 __2_2_ = 0
c7: -1 z_2 + 1 __2_2_ = 0
basin_profile_Basin_#7_: 1 basin_level_Basin_#7_ - 1 z_2 = 0
c9: 1 __3_1_ + 1 __3_2_ = 1
c10: -1 basin_storage_(Basin_#9,__end)_ + 2 __3_2_ = 0
c11: -1 z_3 + 1 __3_2_ = 0
basin_profile_Basin_#9_: 1 basin_level_Basin_#9_ - 1 z_3 = 0
c13: 1 __4_1_ + 1 __4_2_ = 1
c14: -1 basin_storage_(Basin_#11,__end)_ + 2 __4_2_ = 0
c15: -1 z_4 + 1 __4_2_ = 0
basin_profile_Basin_#11_: 1 basin_level_Basin_#11_ - 1 z_4 = 0
c17: 1 __5_1_ + 1 __5_2_ = 1
c18: -1 basin_storage_(Basin_#15,__end)_ + 2 __5_2_ = 0
c19: -1 z_5 + 1 __5_2_ = 0
basin_profile_Basin_#15_: 1 basin_level_Basin_#15_ - 1 z_5 = 0
c21: 1 __6_1_ + 1 __6_2_ = 1
c22: -1 basin_storage_(Basin_#17,__end)_ + 2 __6_2_ = 0
c23: -1 z_6 + 1 __6_2_ = 0
basin_profile_Basin_#17_: 1 basin_level_Basin_#17_ - 1 z_6 = 0
c25: 1 __7_1_ + 1 __7_2_ = 1
c26: -1 basin_storage_(Basin_#21,__end)_ + 2 __7_2_ = 0
c27: -1 z_7 + 1 __7_2_ = 0
basin_profile_Basin_#21_: 1 basin_level_Basin_#21_ - 1 z_7 = 0
c29: 1 __8_1_ + 1 __8_2_ + 1 __8_3_ = 1
c30: -1 basin_storage_(Basin_#2,__end)_ + 0.2 __8_2_ + 2 __8_3_ = 0
c31: -1 z_8 + 1 __8_2_ + 1 __8_3_ = 0
c32: 1 low_storage_factor_Basin_#2_ - 1 z_8 = 0
c33: 1 __9_1_ + 1 __9_2_ + 1 __9_3_ = 1
c34: -1 basin_storage_(Basin_#7,__end)_ + 0.2 __9_2_ + 2 __9_3_ = 0
c35: -1 z_9 + 1 __9_2_ + 1 __9_3_ = 0
c36: 1 low_storage_factor_Basin_#7_ - 1 z_9 = 0
c37: 1 __10_1_ + 1 __10_2_ + 1 __10_3_ = 1
c38: -1 basin_storage_(Basin_#9,__end)_ + 0.2 __10_2_ + 2 __10_3_ = 0
c39: -1 z_10 + 1 __10_2_ + 1 __10_3_ = 0
c40: 1 low_storage_factor_Basin_#9_ - 1 z_10 = 0
c41: 1 __11_1_ + 1 __11_2_ + 1 __11_3_ = 1
c42: -1 basin_storage_(Basin_#11,__end)_ + 0.2 __11_2_ + 2 __11_3_ = 0
c43: -1 z_11 + 1 __11_2_ + 1 __11_3_ = 0
c44: 1 low_storage_factor_Basin_#11_ - 1 z_11 = 0
c45: 1 __12_1_ + 1 __12_2_ + 1 __12_3_ = 1
c46: -1 basin_storage_(Basin_#15,__end)_ + 0.2 __12_2_ + 2 __12_3_ = 0
c47: -1 z_12 + 1 __12_2_ + 1 __12_3_ = 0
c48: 1 low_storage_factor_Basin_#15_ - 1 z_12 = 0
c49: 1 __13_1_ + 1 __13_2_ + 1 __13_3_ = 1
c50: -1 basin_storage_(Basin_#17,__end)_ + 0.2 __13_2_ + 2 __13_3_ = 0
c51: -1 z_13 + 1 __13_2_ + 1 __13_3_ = 0
c52: 1 low_storage_factor_Basin_#17_ - 1 z_13 = 0
c53: 1 __14_1_ + 1 __14_2_ + 1 __14_3_ = 1
c54: -1 basin_storage_(Basin_#21,__end)_ + 0.2 __14_2_ + 2 __14_3_ = 0
c55: -1 z_14 + 1 __14_2_ + 1 __14_3_ = 0
c56: 1 low_storage_factor_Basin_#21_ - 1 z_14 = 0
flow_conservation_pump_Pump_#6_: 1 flow_(Basin_#2,_Pump_#6)_ - 1 flow_(Pump_#6,_Basin_#9)_ = 0
flow_conservation_pump_Pump_#16_: 1 flow_(Basin_#15,_Pump_#16)_ - 1 flow_(Pump_#16,_Basin_#17)_ = 0
flow_conservation_outlet_Outlet_#3_: 1 flow_(Basin_#2,_Outlet_#3)_ - 1 flow_(Outlet_#3,_Terminal_#4)_ = 0
flow_conservation_outlet_Outlet_#8_: 1 flow_(Basin_#9,_Outlet_#8)_ - 1 flow_(Outlet_#8,_Basin_#7)_ = 0
flow_conservation_outlet_Outlet_#10_: 1 flow_(Basin_#9,_Outlet_#10)_ - 1 flow_(Outlet_#10,_Basin_#11)_ = 0
flow_conservation_outlet_Outlet_#22_: 1 flow_(Basin_#21,_Outlet_#22)_ - 1 flow_(Outlet_#22,_Terminal_#23)_ = 0
flow_conservation_tabulatedratingcurve_TabulatedRatingCurve_#13_: 1 flow_(Basin_#9,_TabulatedRatingCurve_#13)_ - 1 flow_(TabulatedRatingCurve_#13,_Basin_#15)_ = 0
flow_conservation_tabulatedratingcurve_TabulatedRatingCurve_#14_: 1 flow_(Basin_#11,_TabulatedRatingCurve_#14)_ - 1 flow_(TabulatedRatingCurve_#14,_Basin_#17)_ = 0
flow_conservation_tabulatedratingcurve_TabulatedRatingCurve_#19_: 1 flow_(Basin_#15,_TabulatedRatingCurve_#19)_ - 1 flow_(TabulatedRatingCurve_#19,_Basin_#21)_ = 0
volume_conservation_Basin_#2_: -1 basin_storage_(Basin_#2,__start)_ + 1 basin_storage_(Basin_#2,__end)_ - 1 flow_(FlowBoundary_#5,_Basin_#2)_ + 1 flow_(Basin_#2,_Outlet_#3)_ + 1 flow_(Basin_#2,_UserDemand_#1)_ + 1 flow_(Basin_#2,_Pump_#6)_ - 1 flow_(UserDemand_#1,_Basin_#2)_ - 1 basin_forcing_Basin_#2_ = 0
volume_conservation_Basin_#7_: -1 basin_storage_(Basin_#7,__start)_ + 1 basin_storage_(Basin_#7,__end)_ - 1 flow_(Outlet_#8,_Basin_#7)_ + 1 flow_(Basin_#7,_UserDemand_#12)_ - 1 flow_(UserDemand_#12,_Basin_#7)_ - 1 basin_forcing_Basin_#7_ = 0
volume_conservation_Basin_#9_: -1 basin_storage_(Basin_#9,__start)_ + 1 basin_storage_(Basin_#9,__end)_ - 1 flow_(Pump_#6,_Basin_#9)_ + 1 flow_(Basin_#9,_Outlet_#8)_ + 1 flow_(Basin_#9,_TabulatedRatingCurve_#13)_ + 1 flow_(Basin_#9,_Outlet_#10)_ - 1 basin_forcing_Basin_#9_ = 0
volume_conservation_Basin_#11_: -1 basin_storage_(Basin_#11,__start)_ + 1 basin_storage_(Basin_#11,__end)_ - 1 flow_(Outlet_#10,_Basin_#11)_ + 1 flow_(Basin_#11,_TabulatedRatingCurve_#14)_ + 1 flow_(Basin_#11,_UserDemand_#24)_ - 1 flow_(UserDemand_#24,_Basin_#11)_ - 1 basin_forcing_Basin_#11_ = 0
volume_conservation_Basin_#15_: -1 basin_storage_(Basin_#15,__start)_ + 1 basin_storage_(Basin_#15,__end)_ - 1 flow_(TabulatedRatingCurve_#13,_Basin_#15)_ + 1 flow_(Basin_#15,_Pump_#16)_ + 1 flow_(Basin_#15,_TabulatedRatingCurve_#19)_ + 1 flow_(Basin_#15,_UserDemand_#18)_ - 1 basin_forcing_Basin_#15_ = 0
volume_conservation_Basin_#17_: -1 basin_storage_(Basin_#17,__start)_ + 1 basin_storage_(Basin_#17,__end)_ - 1 flow_(Pump_#16,_Basin_#17)_ + 1 flow_(Basin_#17,_UserDemand_#20)_ - 1 flow_(TabulatedRatingCurve_#14,_Basin_#17)_ - 1 flow_(UserDemand_#20,_Basin_#17)_ - 1 basin_forcing_Basin_#17_ = 0
volume_conservation_Basin_#21_: -1 basin_storage_(Basin_#21,__start)_ + 1 basin_storage_(Basin_#21,__end)_ - 1 flow_(TabulatedRatingCurve_#19,_Basin_#21)_ - 1 flow_(UserDemand_#18,_Basin_#21)_ + 1 flow_(Basin_#21,_Outlet_#22)_ - 1 basin_forcing_Basin_#21_ = 0
c73: 1 __15_1_ + 1 __15_2_ + 1 __15_3_ = 1
c74: -1 basin_level_Basin_#9_ - 1 __15_1_ + 1 __15_3_ = 0
c75: -1 z_15 + 345.6 __15_3_ = 0
rating_curve_TabulatedRatingCurve_#13_: 1 flow_(Basin_#9,_TabulatedRatingCurve_#13)_ - 1 z_15 = 0
c77: 1 __16_1_ + 1 __16_2_ + 1 __16_3_ = 1
c78: -1 basin_level_Basin_#11_ - 1 __16_1_ + 1 __16_3_ = 0
c79: -1 z_16 + 345.6 __16_3_ = 0
rating_curve_TabulatedRatingCurve_#14_: 1 flow_(Basin_#11,_TabulatedRatingCurve_#14)_ - 1 z_16 = 0
c81: 1 __17_1_ + 1 __17_2_ + 1 __17_3_ = 1
c82: -1 basin_level_Basin_#15_ - 1 __17_1_ + 1 __17_3_ = 0
c83: -1 z_17 + 345.6 __17_3_ = 0
rating_curve_TabulatedRatingCurve_#19_: 1 flow_(Basin_#15,_TabulatedRatingCurve_#19)_ - 1 z_17 = 0
pump_constraint_Pump_#6_: -1 low_storage_factor_Basin_#2_ + 1 flow_(Basin_#2,_Pump_#6)_ = 0
pump_constraint_Pump_#16_: -1 low_storage_factor_Basin_#15_ + 1 flow_(Basin_#15,_Pump_#16)_ = 0
outlet_constraint_Outlet_#3_: -1 low_storage_factor_Basin_#2_ + 1 flow_(Basin_#2,_Outlet_#3)_ = 0
outlet_constraint_Outlet_#8_: -1 low_storage_factor_Basin_#9_ + 1 flow_(Basin_#9,_Outlet_#8)_ = 0
outlet_constraint_Outlet_#10_: -1 low_storage_factor_Basin_#9_ + 1 flow_(Basin_#9,_Outlet_#10)_ = 0
outlet_constraint_Outlet_#22_: -1 low_storage_factor_Basin_#21_ + 1 flow_(Basin_#21,_Outlet_#22)_ = 0
user_demand_return_flow_UserDemand_#1_: -0.5 flow_(Basin_#2,_UserDemand_#1)_ + 1 flow_(UserDemand_#1,_Basin_#2)_ = 0
user_demand_return_flow_UserDemand_#12_: -0.5 flow_(Basin_#7,_UserDemand_#12)_ + 1 flow_(UserDemand_#12,_Basin_#7)_ = 0
user_demand_return_flow_UserDemand_#18_: -0.5 flow_(Basin_#15,_UserDemand_#18)_ + 1 flow_(UserDemand_#18,_Basin_#21)_ = 0
user_demand_return_flow_UserDemand_#20_: -0.5 flow_(Basin_#17,_UserDemand_#20)_ + 1 flow_(UserDemand_#20,_Basin_#17)_ = 0
user_demand_return_flow_UserDemand_#24_: -0.5 flow_(Basin_#11,_UserDemand_#24)_ + 1 flow_(UserDemand_#24,_Basin_#11)_ = 0
Bounds
0 <= basin_storage_(Basin_#2,__start)_ <= 2
0 <= basin_storage_(Basin_#7,__start)_ <= 2
0 <= basin_storage_(Basin_#9,__start)_ <= 2
0 <= basin_storage_(Basin_#11,__start)_ <= 2
0 <= basin_storage_(Basin_#15,__start)_ <= 2
0 <= basin_storage_(Basin_#17,__start)_ <= 2
0 <= basin_storage_(Basin_#21,__start)_ <= 2
0 <= basin_storage_(Basin_#2,__end)_ <= 2
0 <= basin_storage_(Basin_#7,__end)_ <= 2
0 <= basin_storage_(Basin_#9,__end)_ <= 2
0 <= basin_storage_(Basin_#11,__end)_ <= 2
0 <= basin_storage_(Basin_#15,__end)_ <= 2
0 <= basin_storage_(Basin_#17,__end)_ <= 2
0 <= basin_storage_(Basin_#21,__end)_ <= 2
0 <= basin_level_Basin_#2_ <= 1
0 <= basin_level_Basin_#7_ <= 1
0 <= basin_level_Basin_#9_ <= 1
0 <= basin_level_Basin_#11_ <= 1
0 <= basin_level_Basin_#15_ <= 1
0 <= basin_level_Basin_#17_ <= 1
0 <= basin_level_Basin_#21_ <= 1
0 <= z_1 <= 1
0 <= __1_1_ <= 1
0 <= __1_2_ <= 1
0 <= z_2 <= 1
0 <= __2_1_ <= 1
0 <= __2_2_ <= 1
0 <= z_3 <= 1
0 <= __3_1_ <= 1
0 <= __3_2_ <= 1
0 <= z_4 <= 1
0 <= __4_1_ <= 1
0 <= __4_2_ <= 1
0 <= z_5 <= 1
0 <= __5_1_ <= 1
0 <= __5_2_ <= 1
0 <= z_6 <= 1
0 <= __6_1_ <= 1
0 <= __6_2_ <= 1
0 <= z_7 <= 1
0 <= __7_1_ <= 1
0 <= __7_2_ <= 1
0 <= low_storage_factor_Basin_#2_ <= 1
0 <= low_storage_factor_Basin_#7_ <= 1
0 <= low_storage_factor_Basin_#9_ <= 1
0 <= low_storage_factor_Basin_#11_ <= 1
0 <= low_storage_factor_Basin_#15_ <= 1
0 <= low_storage_factor_Basin_#17_ <= 1
0 <= low_storage_factor_Basin_#21_ <= 1
0 <= z_8 <= 1
0 <= __8_1_ <= 1
0 <= __8_2_ <= 1
0 <= __8_3_ <= 1
0 <= z_9 <= 1
0 <= __9_1_ <= 1
0 <= __9_2_ <= 1
0 <= __9_3_ <= 1
0 <= z_10 <= 1
0 <= __10_1_ <= 1
0 <= __10_2_ <= 1
0 <= __10_3_ <= 1
0 <= z_11 <= 1
0 <= __11_1_ <= 1
0 <= __11_2_ <= 1
0 <= __11_3_ <= 1
0 <= z_12 <= 1
0 <= __12_1_ <= 1
0 <= __12_2_ <= 1
0 <= __12_3_ <= 1
0 <= z_13 <= 1
0 <= __13_1_ <= 1
0 <= __13_2_ <= 1
0 <= __13_3_ <= 1
0 <= z_14 <= 1
0 <= __14_1_ <= 1
0 <= __14_2_ <= 1
0 <= __14_3_ <= 1
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
basin_forcing_Basin_#7_ = 0
basin_forcing_Basin_#17_ = 0
basin_forcing_Basin_#2_ = 0
basin_forcing_Basin_#11_ = 0
basin_forcing_Basin_#21_ = 0
basin_forcing_Basin_#15_ = 0
basin_forcing_Basin_#9_ = 0
0 <= z_15 <= 345.6
0 <= __15_1_ <= 1
0 <= __15_2_ <= 1
0 <= __15_3_ <= 1
0 <= z_16 <= 345.6
0 <= __16_1_ <= 1
0 <= __16_2_ <= 1
0 <= __16_3_ <= 1
0 <= z_17 <= 345.6
0 <= __17_1_ <= 1
0 <= __17_2_ <= 1
0 <= __17_3_ <= 1
target_fraction = 1
user_demand_allocated_UserDemand_#1_ = 0
user_demand_allocated_UserDemand_#12_ = 0
user_demand_allocated_UserDemand_#18_ = 0
user_demand_allocated_UserDemand_#20_ = 0
user_demand_allocated_UserDemand_#24_ = 0
relative_user_demand_error_lower_UserDemand_#1_ >= 0
relative_user_demand_error_lower_UserDemand_#12_ >= 0
relative_user_demand_error_lower_UserDemand_#18_ >= 0
relative_user_demand_error_lower_UserDemand_#20_ >= 0
relative_user_demand_error_lower_UserDemand_#24_ >= 0
relative_user_demand_error_upper_UserDemand_#1_ >= 0
relative_user_demand_error_upper_UserDemand_#12_ >= 0
relative_user_demand_error_upper_UserDemand_#18_ >= 0
relative_user_demand_error_upper_UserDemand_#20_ >= 0
relative_user_demand_error_upper_UserDemand_#24_ >= 0
target_storage_demand_fraction_in = 1
target_storage_demand_fraction_out = 1
Binary
y_8_1_
y_9_1_
y_10_1_
y_11_1_
y_12_1_
y_13_1_
y_14_1_
y_15_1_
y_16_1_
y_17_1_
End

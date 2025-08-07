minimize
obj: 
subject to
c1_2: 1 __1_3_ - 1 y_1_1_ <= 0
c2_2: 1 __2_3_ - 1 y_2_1_ <= 0
c3_2: 1 __3_3_ - 1 y_3_1_ <= 0
c4_2: 1 __4_3_ - 1 y_4_1_ <= 0
c5_2: 1 __5_3_ - 1 y_5_1_ <= 0
c6_2: 1 __6_3_ - 1 y_6_1_ <= 0
c7_2: 1 __7_3_ - 1 y_7_1_ <= 0
c1_1: 1 __1_2_ + 1 __1_3_ - 1 y_1_1_ >= 0
c2_1: 1 __2_2_ + 1 __2_3_ - 1 y_2_1_ >= 0
c3_1: 1 __3_2_ + 1 __3_3_ - 1 y_3_1_ >= 0
c4_1: 1 __4_2_ + 1 __4_3_ - 1 y_4_1_ >= 0
c5_1: 1 __5_2_ + 1 __5_3_ - 1 y_5_1_ >= 0
c6_1: 1 __6_2_ + 1 __6_3_ - 1 y_6_1_ >= 0
c7_1: 1 __7_2_ + 1 __7_3_ - 1 y_7_1_ >= 0
user_demand_constraint_lower_UserDemand_#1_: 1 flow_(Basin_#2,_UserDemand_#1)_ - 2 target_fraction - 1 user_demand_allocated_UserDemand_#1_ + 2 relative_user_demand_error_UserDemand_#1_ >= 0
user_demand_constraint_lower_UserDemand_#12_: 1 flow_(Basin_#7,_UserDemand_#12)_ - 2 target_fraction - 1 user_demand_allocated_UserDemand_#12_ + 2 relative_user_demand_error_UserDemand_#12_ >= 0
user_demand_constraint_lower_UserDemand_#18_: 1 flow_(Basin_#15,_UserDemand_#18)_ - 2 target_fraction - 1 user_demand_allocated_UserDemand_#18_ + 2 relative_user_demand_error_UserDemand_#18_ >= 0
user_demand_constraint_lower_UserDemand_#20_: 1 flow_(Basin_#17,_UserDemand_#20)_ - 2 target_fraction - 1 user_demand_allocated_UserDemand_#20_ + 2 relative_user_demand_error_UserDemand_#20_ >= 0
user_demand_constraint_lower_UserDemand_#24_: 1 flow_(Basin_#11,_UserDemand_#24)_ - 2 target_fraction - 1 user_demand_allocated_UserDemand_#24_ + 2 relative_user_demand_error_UserDemand_#24_ >= 0
c1: 1 __1_1_ + 1 __1_2_ + 1 __1_3_ = 1
c2: -1 basin_storage_(Basin_#2,__end)_ + 0.2 __1_2_ + 2 __1_3_ = 0
c3: -1 z_1 + 1 __1_2_ + 1 __1_3_ = 0
c4: 1 low_storage_factor_Basin_#2_ - 1 z_1 = 0
c5: 1 __2_1_ + 1 __2_2_ + 1 __2_3_ = 1
c6: -1 basin_storage_(Basin_#7,__end)_ + 0.2 __2_2_ + 2 __2_3_ = 0
c7: -1 z_2 + 1 __2_2_ + 1 __2_3_ = 0
c8: 1 low_storage_factor_Basin_#7_ - 1 z_2 = 0
c9: 1 __3_1_ + 1 __3_2_ + 1 __3_3_ = 1
c10: -1 basin_storage_(Basin_#9,__end)_ + 0.2 __3_2_ + 2 __3_3_ = 0
c11: -1 z_3 + 1 __3_2_ + 1 __3_3_ = 0
c12: 1 low_storage_factor_Basin_#9_ - 1 z_3 = 0
c13: 1 __4_1_ + 1 __4_2_ + 1 __4_3_ = 1
c14: -1 basin_storage_(Basin_#11,__end)_ + 0.2 __4_2_ + 2 __4_3_ = 0
c15: -1 z_4 + 1 __4_2_ + 1 __4_3_ = 0
c16: 1 low_storage_factor_Basin_#11_ - 1 z_4 = 0
c17: 1 __5_1_ + 1 __5_2_ + 1 __5_3_ = 1
c18: -1 basin_storage_(Basin_#15,__end)_ + 0.2 __5_2_ + 2 __5_3_ = 0
c19: -1 z_5 + 1 __5_2_ + 1 __5_3_ = 0
c20: 1 low_storage_factor_Basin_#15_ - 1 z_5 = 0
c21: 1 __6_1_ + 1 __6_2_ + 1 __6_3_ = 1
c22: -1 basin_storage_(Basin_#17,__end)_ + 0.2 __6_2_ + 2 __6_3_ = 0
c23: -1 z_6 + 1 __6_2_ + 1 __6_3_ = 0
c24: 1 low_storage_factor_Basin_#17_ - 1 z_6 = 0
c25: 1 __7_1_ + 1 __7_2_ + 1 __7_3_ = 1
c26: -1 basin_storage_(Basin_#21,__end)_ + 0.2 __7_2_ + 2 __7_3_ = 0
c27: -1 z_7 + 1 __7_2_ + 1 __7_3_ = 0
c28: 1 low_storage_factor_Basin_#21_ - 1 z_7 = 0
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
tabulated_rating_curve_constraint_TabulatedRatingCurve_#13_: -1 basin_storage_(Basin_#9,__end)_ + 1 basin_storage_(Basin_#15,__end)_ + 1 flow_(Basin_#9,_TabulatedRatingCurve_#13)_ = 1
tabulated_rating_curve_constraint_TabulatedRatingCurve_#14_: -1 basin_storage_(Basin_#11,__end)_ + 1 basin_storage_(Basin_#17,__end)_ + 1 flow_(Basin_#11,_TabulatedRatingCurve_#14)_ = 1
tabulated_rating_curve_constraint_TabulatedRatingCurve_#19_: -1 basin_storage_(Basin_#15,__end)_ + 1 basin_storage_(Basin_#21,__end)_ + 1 flow_(Basin_#15,_TabulatedRatingCurve_#19)_ = 1
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
0 <= low_storage_factor_Basin_#2_ <= 1
0 <= low_storage_factor_Basin_#7_ <= 1
0 <= low_storage_factor_Basin_#9_ <= 1
0 <= low_storage_factor_Basin_#11_ <= 1
0 <= low_storage_factor_Basin_#15_ <= 1
0 <= low_storage_factor_Basin_#17_ <= 1
0 <= low_storage_factor_Basin_#21_ <= 1
0 <= z_1 <= 1
0 <= __1_1_ <= 1
0 <= __1_2_ <= 1
0 <= __1_3_ <= 1
0 <= z_2 <= 1
0 <= __2_1_ <= 1
0 <= __2_2_ <= 1
0 <= __2_3_ <= 1
0 <= z_3 <= 1
0 <= __3_1_ <= 1
0 <= __3_2_ <= 1
0 <= __3_3_ <= 1
0 <= z_4 <= 1
0 <= __4_1_ <= 1
0 <= __4_2_ <= 1
0 <= __4_3_ <= 1
0 <= z_5 <= 1
0 <= __5_1_ <= 1
0 <= __5_2_ <= 1
0 <= __5_3_ <= 1
0 <= z_6 <= 1
0 <= __6_1_ <= 1
0 <= __6_2_ <= 1
0 <= __6_3_ <= 1
0 <= z_7 <= 1
0 <= __7_1_ <= 1
0 <= __7_2_ <= 1
0 <= __7_3_ <= 1
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
basin_forcing_Basin_#2_ = 0
basin_forcing_Basin_#7_ = 0
basin_forcing_Basin_#9_ = 0
basin_forcing_Basin_#11_ = 0
basin_forcing_Basin_#15_ = 0
basin_forcing_Basin_#17_ = 0
basin_forcing_Basin_#21_ = 0
target_fraction = 1
user_demand_allocated_UserDemand_#1_ = 0
user_demand_allocated_UserDemand_#12_ = 0
user_demand_allocated_UserDemand_#18_ = 0
user_demand_allocated_UserDemand_#20_ = 0
user_demand_allocated_UserDemand_#24_ = 0
relative_user_demand_error_UserDemand_#1_ >= 0
relative_user_demand_error_UserDemand_#12_ >= 0
relative_user_demand_error_UserDemand_#18_ >= 0
relative_user_demand_error_UserDemand_#20_ >= 0
relative_user_demand_error_UserDemand_#24_ >= 0
Binary
y_1_1_
y_2_1_
y_3_1_
y_4_1_
y_5_1_
y_6_1_
y_7_1_
End

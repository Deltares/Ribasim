minimize
obj: 
subject to
c1_1: 1 __1_3_ - 1 y_1_1_ <= 0
c2_1: 1 __2_3_ - 1 y_2_1_ <= 0
c3_1: 1 __3_3_ - 1 y_3_1_ <= 0
c4_1: 1 __4_3_ - 1 y_4_1_ <= 0
c5_1: 1 __5_3_ - 1 y_5_1_ <= 0
c6_1: 1 __6_3_ - 1 y_6_1_ <= 0
c7_1: 1 __7_3_ - 1 y_7_1_ <= 0
c1: 1 __1_2_ + 1 __1_3_ - 1 y_1_1_ >= 0
c2: 1 __2_2_ + 1 __2_3_ - 1 y_2_1_ >= 0
c3: 1 __3_2_ + 1 __3_3_ - 1 y_3_1_ >= 0
c4: 1 __4_2_ + 1 __4_3_ - 1 y_4_1_ >= 0
c5: 1 __5_2_ + 1 __5_3_ - 1 y_5_1_ >= 0
c6: 1 __6_2_ + 1 __6_3_ - 1 y_6_1_ >= 0
c7: 1 __7_2_ + 1 __7_3_ - 1 y_7_1_ >= 0
user_demand_constraint_lower_UserDemand_#34_: 1 flow_(Basin_#35,_UserDemand_#34)_ - 2 target_fraction - 1 user_demand_allocated_UserDemand_#34_ + 2 relative_user_demand_error_UserDemand_#34_ >= 0
user_demand_constraint_lower_UserDemand_#45_: 1 flow_(Basin_#40,_UserDemand_#45)_ - 2 target_fraction - 1 user_demand_allocated_UserDemand_#45_ + 2 relative_user_demand_error_UserDemand_#45_ >= 0
user_demand_constraint_lower_UserDemand_#51_: 1 flow_(Basin_#48,_UserDemand_#51)_ - 2 target_fraction - 1 user_demand_allocated_UserDemand_#51_ + 2 relative_user_demand_error_UserDemand_#51_ >= 0
user_demand_constraint_lower_UserDemand_#53_: 1 flow_(Basin_#50,_UserDemand_#53)_ - 2 target_fraction - 1 user_demand_allocated_UserDemand_#53_ + 2 relative_user_demand_error_UserDemand_#53_ >= 0
user_demand_constraint_lower_UserDemand_#57_: 1 flow_(Basin_#44,_UserDemand_#57)_ - 2 target_fraction - 1 user_demand_allocated_UserDemand_#57_ + 2 relative_user_demand_error_UserDemand_#57_ >= 0
linear_basin_profile_Basin_#35_: 0.0005 basin_storage_(Basin_#35,__start)_ - 0.0005 basin_storage_(Basin_#35,__end)_ + 1 basin_level_Basin_#35_ = 1000000
linear_basin_profile_Basin_#40_: 0.0005 basin_storage_(Basin_#40,__start)_ - 0.0005 basin_storage_(Basin_#40,__end)_ + 1 basin_level_Basin_#40_ = 1000000
linear_basin_profile_Basin_#42_: 0.0005 basin_storage_(Basin_#42,__start)_ - 0.0005 basin_storage_(Basin_#42,__end)_ + 1 basin_level_Basin_#42_ = 1000000
linear_basin_profile_Basin_#44_: 0.0005 basin_storage_(Basin_#44,__start)_ - 0.0005 basin_storage_(Basin_#44,__end)_ + 1 basin_level_Basin_#44_ = 1000000
linear_basin_profile_Basin_#48_: 0.0005 basin_storage_(Basin_#48,__start)_ - 0.0005 basin_storage_(Basin_#48,__end)_ + 1 basin_level_Basin_#48_ = 1000000
linear_basin_profile_Basin_#50_: 0.0005 basin_storage_(Basin_#50,__start)_ - 0.0005 basin_storage_(Basin_#50,__end)_ + 1 basin_level_Basin_#50_ = 1000000
linear_basin_profile_Basin_#54_: 0.0005 basin_storage_(Basin_#54,__start)_ - 0.0005 basin_storage_(Basin_#54,__end)_ + 1 basin_level_Basin_#54_ = 1000000
c8: 1 __1_1_ + 1 __1_2_ + 1 __1_3_ = 1
c9: -1 basin_storage_(Basin_#35,__end)_ + 0.2 __1_2_ + 2 __1_3_ = 0
c10: -1 z_1 + 1 __1_2_ + 1 __1_3_ = 0
c11: 1 low_storage_factor_Basin_#35_ - 1 z_1 = 0
c12: 1 __2_1_ + 1 __2_2_ + 1 __2_3_ = 1
c13: -1 basin_storage_(Basin_#40,__end)_ + 0.2 __2_2_ + 2 __2_3_ = 0
c14: -1 z_2 + 1 __2_2_ + 1 __2_3_ = 0
c15: 1 low_storage_factor_Basin_#40_ - 1 z_2 = 0
c16: 1 __3_1_ + 1 __3_2_ + 1 __3_3_ = 1
c17: -1 basin_storage_(Basin_#42,__end)_ + 0.2 __3_2_ + 2 __3_3_ = 0
c18: -1 z_3 + 1 __3_2_ + 1 __3_3_ = 0
c19: 1 low_storage_factor_Basin_#42_ - 1 z_3 = 0
c20: 1 __4_1_ + 1 __4_2_ + 1 __4_3_ = 1
c21: -1 basin_storage_(Basin_#44,__end)_ + 0.2 __4_2_ + 2 __4_3_ = 0
c22: -1 z_4 + 1 __4_2_ + 1 __4_3_ = 0
c23: 1 low_storage_factor_Basin_#44_ - 1 z_4 = 0
c24: 1 __5_1_ + 1 __5_2_ + 1 __5_3_ = 1
c25: -1 basin_storage_(Basin_#48,__end)_ + 0.2 __5_2_ + 2 __5_3_ = 0
c26: -1 z_5 + 1 __5_2_ + 1 __5_3_ = 0
c27: 1 low_storage_factor_Basin_#48_ - 1 z_5 = 0
c28: 1 __6_1_ + 1 __6_2_ + 1 __6_3_ = 1
c29: -1 basin_storage_(Basin_#50,__end)_ + 0.2 __6_2_ + 2 __6_3_ = 0
c30: -1 z_6 + 1 __6_2_ + 1 __6_3_ = 0
c31: 1 low_storage_factor_Basin_#50_ - 1 z_6 = 0
c32: 1 __7_1_ + 1 __7_2_ + 1 __7_3_ = 1
c33: -1 basin_storage_(Basin_#54,__end)_ + 0.2 __7_2_ + 2 __7_3_ = 0
c34: -1 z_7 + 1 __7_2_ + 1 __7_3_ = 0
c35: 1 low_storage_factor_Basin_#54_ - 1 z_7 = 0
flow_conservation_pump_Pump_#39_: 1 flow_(Basin_#35,_Pump_#39)_ - 1 flow_(Pump_#39,_Basin_#42)_ = 0
flow_conservation_pump_Pump_#49_: 1 flow_(Basin_#48,_Pump_#49)_ - 1 flow_(Pump_#49,_Basin_#50)_ = 0
flow_conservation_outlet_Outlet_#36_: 1 flow_(Basin_#35,_Outlet_#36)_ - 1 flow_(Outlet_#36,_Terminal_#37)_ = 0
flow_conservation_outlet_Outlet_#41_: 1 flow_(Basin_#42,_Outlet_#41)_ - 1 flow_(Outlet_#41,_Basin_#40)_ = 0
flow_conservation_outlet_Outlet_#43_: 1 flow_(Basin_#42,_Outlet_#43)_ - 1 flow_(Outlet_#43,_Basin_#44)_ = 0
flow_conservation_outlet_Outlet_#55_: 1 flow_(Basin_#54,_Outlet_#55)_ - 1 flow_(Outlet_#55,_Terminal_#56)_ = 0
flow_conservation_tabulated_rating_curve_TabulatedRatingCurve_#46_: 1 flow_(Basin_#42,_TabulatedRatingCurve_#46)_ - 1 flow_(TabulatedRatingCurve_#46,_Basin_#48)_ = 0
flow_conservation_tabulated_rating_curve_TabulatedRatingCurve_#47_: 1 flow_(Basin_#44,_TabulatedRatingCurve_#47)_ - 1 flow_(TabulatedRatingCurve_#47,_Basin_#50)_ = 0
flow_conservation_tabulated_rating_curve_TabulatedRatingCurve_#52_: 1 flow_(Basin_#48,_TabulatedRatingCurve_#52)_ - 1 flow_(TabulatedRatingCurve_#52,_Basin_#54)_ = 0
volume_conservation_Basin_#35_: -1 basin_storage_(Basin_#35,__start)_ + 1 basin_storage_(Basin_#35,__end)_ + 1 flow_(Basin_#35,_Outlet_#36)_ + 1 flow_(Basin_#35,_UserDemand_#34)_ + 1 flow_(Basin_#35,_Pump_#39)_ - 1 flow_(UserDemand_#34,_Basin_#35)_ - 1 basin_forcing_Basin_#35_ = 0
volume_conservation_Basin_#40_: -1 basin_storage_(Basin_#40,__start)_ + 1 basin_storage_(Basin_#40,__end)_ - 1 flow_(Outlet_#41,_Basin_#40)_ + 1 flow_(Basin_#40,_UserDemand_#45)_ - 1 flow_(UserDemand_#45,_Basin_#40)_ - 1 basin_forcing_Basin_#40_ = 0
volume_conservation_Basin_#42_: -1 basin_storage_(Basin_#42,__start)_ + 1 basin_storage_(Basin_#42,__end)_ - 1 flow_(Pump_#39,_Basin_#42)_ + 1 flow_(Basin_#42,_Outlet_#41)_ + 1 flow_(Basin_#42,_TabulatedRatingCurve_#46)_ + 1 flow_(Basin_#42,_Outlet_#43)_ - 1 basin_forcing_Basin_#42_ = 0
volume_conservation_Basin_#44_: -1 basin_storage_(Basin_#44,__start)_ + 1 basin_storage_(Basin_#44,__end)_ - 1 flow_(Outlet_#43,_Basin_#44)_ + 1 flow_(Basin_#44,_TabulatedRatingCurve_#47)_ + 1 flow_(Basin_#44,_UserDemand_#57)_ - 1 flow_(UserDemand_#57,_Basin_#44)_ - 1 basin_forcing_Basin_#44_ = 0
volume_conservation_Basin_#48_: -1 basin_storage_(Basin_#48,__start)_ + 1 basin_storage_(Basin_#48,__end)_ - 1 flow_(TabulatedRatingCurve_#46,_Basin_#48)_ + 1 flow_(Basin_#48,_Pump_#49)_ + 1 flow_(Basin_#48,_TabulatedRatingCurve_#52)_ + 1 flow_(Basin_#48,_UserDemand_#51)_ - 1 basin_forcing_Basin_#48_ = 0
volume_conservation_Basin_#50_: -1 basin_storage_(Basin_#50,__start)_ + 1 basin_storage_(Basin_#50,__end)_ - 1 flow_(Pump_#49,_Basin_#50)_ + 1 flow_(Basin_#50,_UserDemand_#53)_ - 1 flow_(TabulatedRatingCurve_#47,_Basin_#50)_ - 1 flow_(UserDemand_#53,_Basin_#50)_ - 1 basin_forcing_Basin_#50_ = 0
volume_conservation_Basin_#54_: -1 basin_storage_(Basin_#54,__start)_ + 1 basin_storage_(Basin_#54,__end)_ - 1 flow_(TabulatedRatingCurve_#52,_Basin_#54)_ - 1 flow_(UserDemand_#51,_Basin_#54)_ + 1 flow_(Basin_#54,_Outlet_#55)_ - 1 basin_forcing_Basin_#54_ = 0
tabulated_rating_curve_constraint_TabulatedRatingCurve_#46_: -1 basin_level_Basin_#42_ + 1 basin_level_Basin_#48_ + 1 flow_(Basin_#42,_TabulatedRatingCurve_#46)_ = 1
tabulated_rating_curve_constraint_TabulatedRatingCurve_#47_: -1 basin_level_Basin_#44_ + 1 basin_level_Basin_#50_ + 1 flow_(Basin_#44,_TabulatedRatingCurve_#47)_ = 1
tabulated_rating_curve_constraint_TabulatedRatingCurve_#52_: -1 basin_level_Basin_#48_ + 1 basin_level_Basin_#54_ + 1 flow_(Basin_#48,_TabulatedRatingCurve_#52)_ = 1
pump_constraint_Pump_#39_: -1 low_storage_factor_Basin_#35_ + 1 flow_(Basin_#35,_Pump_#39)_ = 0
pump_constraint_Pump_#49_: -1 low_storage_factor_Basin_#48_ + 1 flow_(Basin_#48,_Pump_#49)_ = 0
outlet_constraint_Outlet_#36_: -1 low_storage_factor_Basin_#35_ + 1 flow_(Basin_#35,_Outlet_#36)_ = 0
outlet_constraint_Outlet_#41_: -1 low_storage_factor_Basin_#42_ + 1 flow_(Basin_#42,_Outlet_#41)_ = 0
outlet_constraint_Outlet_#43_: -1 low_storage_factor_Basin_#42_ + 1 flow_(Basin_#42,_Outlet_#43)_ = 0
outlet_constraint_Outlet_#55_: -1 low_storage_factor_Basin_#54_ + 1 flow_(Basin_#54,_Outlet_#55)_ = 0
user_demand_return_flow_UserDemand_#34_: -0.5 flow_(Basin_#35,_UserDemand_#34)_ + 1 flow_(UserDemand_#34,_Basin_#35)_ = 0
user_demand_return_flow_UserDemand_#45_: -0.5 flow_(Basin_#40,_UserDemand_#45)_ + 1 flow_(UserDemand_#45,_Basin_#40)_ = 0
user_demand_return_flow_UserDemand_#51_: -0.5 flow_(Basin_#48,_UserDemand_#51)_ + 1 flow_(UserDemand_#51,_Basin_#54)_ = 0
user_demand_return_flow_UserDemand_#53_: -0.5 flow_(Basin_#50,_UserDemand_#53)_ + 1 flow_(UserDemand_#53,_Basin_#50)_ = 0
user_demand_return_flow_UserDemand_#57_: -0.5 flow_(Basin_#44,_UserDemand_#57)_ + 1 flow_(UserDemand_#57,_Basin_#44)_ = 0
Bounds
0 <= basin_storage_(Basin_#35,__start)_ <= 4
0 <= basin_storage_(Basin_#40,__start)_ <= 4
0 <= basin_storage_(Basin_#42,__start)_ <= 4
0 <= basin_storage_(Basin_#44,__start)_ <= 4
0 <= basin_storage_(Basin_#48,__start)_ <= 4
0 <= basin_storage_(Basin_#50,__start)_ <= 4
0 <= basin_storage_(Basin_#54,__start)_ <= 4
0 <= basin_storage_(Basin_#35,__end)_ <= 4
0 <= basin_storage_(Basin_#40,__end)_ <= 4
0 <= basin_storage_(Basin_#42,__end)_ <= 4
0 <= basin_storage_(Basin_#44,__end)_ <= 4
0 <= basin_storage_(Basin_#48,__end)_ <= 4
0 <= basin_storage_(Basin_#50,__end)_ <= 4
0 <= basin_storage_(Basin_#54,__end)_ <= 4
0 <= basin_level_Basin_#35_ <= 1
0 <= basin_level_Basin_#40_ <= 1
0 <= basin_level_Basin_#42_ <= 1
0 <= basin_level_Basin_#44_ <= 1
0 <= basin_level_Basin_#48_ <= 1
0 <= basin_level_Basin_#50_ <= 1
0 <= basin_level_Basin_#54_ <= 1
0 <= low_storage_factor_Basin_#35_ <= 1
0 <= low_storage_factor_Basin_#40_ <= 1
0 <= low_storage_factor_Basin_#42_ <= 1
0 <= low_storage_factor_Basin_#44_ <= 1
0 <= low_storage_factor_Basin_#48_ <= 1
0 <= low_storage_factor_Basin_#50_ <= 1
0 <= low_storage_factor_Basin_#54_ <= 1
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
0 <= flow_(Pump_#38,_Basin_#35)_ <= 172.8
0 <= flow_(Basin_#35,_Outlet_#36)_ <= 518.4
0 <= flow_(Outlet_#36,_Terminal_#37)_ <= 518.4
0 <= flow_(Basin_#35,_UserDemand_#34)_ <= 86400000
0 <= flow_(Basin_#35,_Pump_#39)_ <= 0.6912
0 <= flow_(Pump_#39,_Basin_#42)_ <= 0.6912
0 <= flow_(Basin_#42,_Outlet_#41)_ <= 518.4
0 <= flow_(Outlet_#41,_Basin_#40)_ <= 518.4
0 <= flow_(Basin_#40,_UserDemand_#45)_ <= 86400000
0 <= flow_(Basin_#42,_TabulatedRatingCurve_#46)_ <= 86400000
0 <= flow_(TabulatedRatingCurve_#46,_Basin_#48)_ <= 86400000
0 <= flow_(Basin_#48,_Pump_#49)_ <= 0.6912
0 <= flow_(Pump_#49,_Basin_#50)_ <= 0.6912
0 <= flow_(Basin_#50,_UserDemand_#53)_ <= 86400000
0 <= flow_(Basin_#48,_TabulatedRatingCurve_#52)_ <= 86400000
0 <= flow_(TabulatedRatingCurve_#52,_Basin_#54)_ <= 86400000
0 <= flow_(Basin_#48,_UserDemand_#51)_ <= 86400000
0 <= flow_(UserDemand_#51,_Basin_#54)_ <= 86400000
0 <= flow_(Basin_#54,_Outlet_#55)_ <= 518.4
0 <= flow_(Outlet_#55,_Terminal_#56)_ <= 518.4
0 <= flow_(Basin_#42,_Outlet_#43)_ <= 518.4
0 <= flow_(Outlet_#43,_Basin_#44)_ <= 518.4
0 <= flow_(Basin_#44,_TabulatedRatingCurve_#47)_ <= 86400000
0 <= flow_(TabulatedRatingCurve_#47,_Basin_#50)_ <= 86400000
0 <= flow_(UserDemand_#34,_Basin_#35)_ <= 86400000
0 <= flow_(UserDemand_#45,_Basin_#40)_ <= 86400000
0 <= flow_(UserDemand_#53,_Basin_#50)_ <= 86400000
0 <= flow_(Basin_#44,_UserDemand_#57)_ <= 86400000
0 <= flow_(UserDemand_#57,_Basin_#44)_ <= 86400000
basin_forcing_Basin_#35_ = 0
basin_forcing_Basin_#40_ = 0
basin_forcing_Basin_#42_ = 0
basin_forcing_Basin_#44_ = 0
basin_forcing_Basin_#48_ = 0
basin_forcing_Basin_#50_ = 0
basin_forcing_Basin_#54_ = 0
target_fraction = 1
user_demand_allocated_UserDemand_#34_ = 0
user_demand_allocated_UserDemand_#45_ = 0
user_demand_allocated_UserDemand_#51_ = 0
user_demand_allocated_UserDemand_#53_ = 0
user_demand_allocated_UserDemand_#57_ = 0
relative_user_demand_error_UserDemand_#34_ >= 0
relative_user_demand_error_UserDemand_#45_ >= 0
relative_user_demand_error_UserDemand_#51_ >= 0
relative_user_demand_error_UserDemand_#53_ >= 0
relative_user_demand_error_UserDemand_#57_ >= 0
Binary
y_1_1_
y_2_1_
y_3_1_
y_4_1_
y_5_1_
y_6_1_
y_7_1_
End

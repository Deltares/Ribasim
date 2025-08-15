minimize
obj: 
subject to
user_demand_relative_error_constraint_UserDemand_#34,2_: 1 user_demand_allocated_UserDemand_#34,2_ + 2 user_demand_error_UserDemand_#34,2,first_ >= 2
user_demand_relative_error_constraint_UserDemand_#45,1_: 1 user_demand_allocated_UserDemand_#45,1_ + 2 user_demand_error_UserDemand_#45,1,first_ >= 2
user_demand_relative_error_constraint_UserDemand_#51,3_: 1 user_demand_allocated_UserDemand_#51,3_ + 2 user_demand_error_UserDemand_#51,3,first_ >= 2
user_demand_relative_error_constraint_UserDemand_#53,3_: 1 user_demand_allocated_UserDemand_#53,3_ + 2 user_demand_error_UserDemand_#53,3,first_ >= 2
user_demand_relative_error_constraint_UserDemand_#57,2_: 1 user_demand_allocated_UserDemand_#57,2_ + 2 user_demand_error_UserDemand_#57,2,first_ >= 2
user_demand_fairness_error_constraint_UserDemand_#34,2_: -1 user_demand_error_UserDemand_#34,2,first_ + 1 user_demand_error_UserDemand_#34,2,second_ + 1 average_flow_unit_error_2_ >= 0
user_demand_fairness_error_constraint_UserDemand_#45,1_: -1 user_demand_error_UserDemand_#45,1,first_ + 1 user_demand_error_UserDemand_#45,1,second_ + 1 average_flow_unit_error_1_ >= 0
user_demand_fairness_error_constraint_UserDemand_#51,3_: -1 user_demand_error_UserDemand_#51,3,first_ + 1 user_demand_error_UserDemand_#51,3,second_ + 1 average_flow_unit_error_3_ >= 0
user_demand_fairness_error_constraint_UserDemand_#53,3_: -1 user_demand_error_UserDemand_#53,3,first_ + 1 user_demand_error_UserDemand_#53,3,second_ + 1 average_flow_unit_error_3_ >= 0
user_demand_fairness_error_constraint_UserDemand_#57,2_: -1 user_demand_error_UserDemand_#57,2,first_ + 1 user_demand_error_UserDemand_#57,2,second_ + 1 average_flow_unit_error_2_ >= 0
flow_conservation_pump_Pump_#39_: 1 flow_(Basin_#35,_Pump_#39)_ - 1 flow_(Pump_#39,_Basin_#42)_ = 0
flow_conservation_pump_Pump_#49_: 1 flow_(Basin_#48,_Pump_#49)_ - 1 flow_(Pump_#49,_Basin_#50)_ = 0
flow_conservation_outlet_Outlet_#36_: 1 flow_(Basin_#35,_Outlet_#36)_ - 1 flow_(Outlet_#36,_Terminal_#37)_ = 0
flow_conservation_outlet_Outlet_#41_: 1 flow_(Basin_#42,_Outlet_#41)_ - 1 flow_(Outlet_#41,_Basin_#40)_ = 0
flow_conservation_outlet_Outlet_#43_: 1 flow_(Basin_#42,_Outlet_#43)_ - 1 flow_(Outlet_#43,_Basin_#44)_ = 0
flow_conservation_outlet_Outlet_#55_: 1 flow_(Basin_#54,_Outlet_#55)_ - 1 flow_(Outlet_#55,_Terminal_#56)_ = 0
flow_conservation_tabulated_rating_curve_TabulatedRatingCurve_#46_: 1 flow_(Basin_#42,_TabulatedRatingCurve_#46)_ - 1 flow_(TabulatedRatingCurve_#46,_Basin_#48)_ = 0
flow_conservation_tabulated_rating_curve_TabulatedRatingCurve_#47_: 1 flow_(Basin_#44,_TabulatedRatingCurve_#47)_ - 1 flow_(TabulatedRatingCurve_#47,_Basin_#50)_ = 0
flow_conservation_tabulated_rating_curve_TabulatedRatingCurve_#52_: 1 flow_(Basin_#48,_TabulatedRatingCurve_#52)_ - 1 flow_(TabulatedRatingCurve_#52,_Basin_#54)_ = 0
volume_conservation_Basin_#35_: 1 basin_storage_change_Basin_#35_ + 1 low_storage_factor_Basin_#35_ + 1 flow_(Basin_#35,_Outlet_#36)_ + 1 flow_(Basin_#35,_UserDemand_#34)_ + 1 flow_(Basin_#35,_Pump_#39)_ - 1 flow_(UserDemand_#34,_Basin_#35)_ = 1
volume_conservation_Basin_#40_: 1 basin_storage_change_Basin_#40_ + 1 low_storage_factor_Basin_#40_ - 1 flow_(Outlet_#41,_Basin_#40)_ + 1 flow_(Basin_#40,_UserDemand_#45)_ - 1 flow_(UserDemand_#45,_Basin_#40)_ = 1
volume_conservation_Basin_#42_: 1 basin_storage_change_Basin_#42_ + 1 low_storage_factor_Basin_#42_ - 1 flow_(Pump_#39,_Basin_#42)_ + 1 flow_(Basin_#42,_Outlet_#41)_ + 1 flow_(Basin_#42,_TabulatedRatingCurve_#46)_ + 1 flow_(Basin_#42,_Outlet_#43)_ = 1
volume_conservation_Basin_#44_: 1 basin_storage_change_Basin_#44_ + 1 low_storage_factor_Basin_#44_ - 1 flow_(Outlet_#43,_Basin_#44)_ + 1 flow_(Basin_#44,_TabulatedRatingCurve_#47)_ + 1 flow_(Basin_#44,_UserDemand_#57)_ - 1 flow_(UserDemand_#57,_Basin_#44)_ = 1
volume_conservation_Basin_#48_: 1 basin_storage_change_Basin_#48_ + 1 low_storage_factor_Basin_#48_ - 1 flow_(TabulatedRatingCurve_#46,_Basin_#48)_ + 1 flow_(Basin_#48,_Pump_#49)_ + 1 flow_(Basin_#48,_TabulatedRatingCurve_#52)_ + 1 flow_(Basin_#48,_UserDemand_#51)_ = 1
volume_conservation_Basin_#50_: 1 basin_storage_change_Basin_#50_ + 1 low_storage_factor_Basin_#50_ - 1 flow_(Pump_#49,_Basin_#50)_ + 1 flow_(Basin_#50,_UserDemand_#53)_ - 1 flow_(TabulatedRatingCurve_#47,_Basin_#50)_ - 1 flow_(UserDemand_#53,_Basin_#50)_ = 1
volume_conservation_Basin_#54_: 1 basin_storage_change_Basin_#54_ + 1 low_storage_factor_Basin_#54_ - 1 flow_(TabulatedRatingCurve_#52,_Basin_#54)_ - 1 flow_(UserDemand_#51,_Basin_#54)_ + 1 flow_(Basin_#54,_Outlet_#55)_ = 1
tabulated_rating_curve_constraint_TabulatedRatingCurve_#46_: -0.01 basin_storage_change_Basin_#42_ + 0.01 basin_storage_change_Basin_#48_ + 1 flow_(Basin_#42,_TabulatedRatingCurve_#46)_ = 1
tabulated_rating_curve_constraint_TabulatedRatingCurve_#47_: -0.01 basin_storage_change_Basin_#44_ + 0.01 basin_storage_change_Basin_#50_ + 1 flow_(Basin_#44,_TabulatedRatingCurve_#47)_ = 1
tabulated_rating_curve_constraint_TabulatedRatingCurve_#52_: -0.01 basin_storage_change_Basin_#48_ + 0.01 basin_storage_change_Basin_#54_ + 1 flow_(Basin_#48,_TabulatedRatingCurve_#52)_ = 1
pump_constraint_Pump_#39_: -1 low_storage_factor_Basin_#35_ + 1 flow_(Basin_#35,_Pump_#39)_ = 0
pump_constraint_Pump_#49_: -1 low_storage_factor_Basin_#48_ + 1 flow_(Basin_#48,_Pump_#49)_ = 0
outlet_constraint_Outlet_#36_: -1 low_storage_factor_Basin_#35_ + 1 flow_(Basin_#35,_Outlet_#36)_ = 0
outlet_constraint_Outlet_#41_: -1 low_storage_factor_Basin_#42_ + 1 flow_(Basin_#42,_Outlet_#41)_ = 0
outlet_constraint_Outlet_#43_: -1 low_storage_factor_Basin_#42_ + 1 flow_(Basin_#42,_Outlet_#43)_ = 0
outlet_constraint_Outlet_#55_: -1 low_storage_factor_Basin_#54_ + 1 flow_(Basin_#54,_Outlet_#55)_ = 0
c26: 1 flow_(Basin_#35,_UserDemand_#34)_ - 1 user_demand_allocated_UserDemand_#34,2_ = 0
c27: 1 flow_(Basin_#40,_UserDemand_#45)_ - 1 user_demand_allocated_UserDemand_#45,1_ = 0
c28: 1 flow_(Basin_#48,_UserDemand_#51)_ - 1 user_demand_allocated_UserDemand_#51,3_ = 0
c29: 1 flow_(Basin_#50,_UserDemand_#53)_ - 1 user_demand_allocated_UserDemand_#53,3_ = 0
c30: 1 flow_(Basin_#44,_UserDemand_#57)_ - 1 user_demand_allocated_UserDemand_#57,2_ = 0
user_demand_return_flow_UserDemand_#34_: -0.5 flow_(Basin_#35,_UserDemand_#34)_ + 1 flow_(UserDemand_#34,_Basin_#35)_ = 0
user_demand_return_flow_UserDemand_#45_: -0.5 flow_(Basin_#40,_UserDemand_#45)_ + 1 flow_(UserDemand_#45,_Basin_#40)_ = 0
user_demand_return_flow_UserDemand_#51_: -0.5 flow_(Basin_#48,_UserDemand_#51)_ + 1 flow_(UserDemand_#51,_Basin_#54)_ = 0
user_demand_return_flow_UserDemand_#53_: -0.5 flow_(Basin_#50,_UserDemand_#53)_ + 1 flow_(UserDemand_#53,_Basin_#50)_ = 0
user_demand_return_flow_UserDemand_#57_: -0.5 flow_(Basin_#44,_UserDemand_#57)_ + 1 flow_(UserDemand_#57,_Basin_#44)_ = 0
average_flow_unit_error_constraint_1_: -1 user_demand_error_UserDemand_#45,1,first_ + 1 average_flow_unit_error_1_ = 0
average_flow_unit_error_constraint_2_: -1 user_demand_error_UserDemand_#34,2,first_ - 1 user_demand_error_UserDemand_#57,2,first_ + 1 average_flow_unit_error_2_ = 0
average_flow_unit_error_constraint_3_: -1 user_demand_error_UserDemand_#51,3,first_ - 1 user_demand_error_UserDemand_#53,3,first_ + 1 average_flow_unit_error_3_ = 0
Bounds
-2 <= basin_storage_change_Basin_#35_ <= 8
-2 <= basin_storage_change_Basin_#40_ <= 8
-2 <= basin_storage_change_Basin_#42_ <= 8
-2 <= basin_storage_change_Basin_#44_ <= 8
-2 <= basin_storage_change_Basin_#48_ <= 8
-2 <= basin_storage_change_Basin_#50_ <= 8
-2 <= basin_storage_change_Basin_#54_ <= 8
0 <= low_storage_factor_Basin_#35_ <= 1
0 <= low_storage_factor_Basin_#40_ <= 1
0 <= low_storage_factor_Basin_#42_ <= 1
0 <= low_storage_factor_Basin_#44_ <= 1
0 <= low_storage_factor_Basin_#48_ <= 1
0 <= low_storage_factor_Basin_#50_ <= 1
0 <= low_storage_factor_Basin_#54_ <= 1
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
0 <= user_demand_allocated_UserDemand_#34,2_ <= 2
0 <= user_demand_allocated_UserDemand_#45,1_ <= 2
0 <= user_demand_allocated_UserDemand_#51,3_ <= 2
0 <= user_demand_allocated_UserDemand_#53,3_ <= 2
0 <= user_demand_allocated_UserDemand_#57,2_ <= 2
0 <= user_demand_error_UserDemand_#34,2,first_ <= 1
0 <= user_demand_error_UserDemand_#34,2,second_ <= 1
0 <= user_demand_error_UserDemand_#45,1,first_ <= 1
0 <= user_demand_error_UserDemand_#45,1,second_ <= 1
0 <= user_demand_error_UserDemand_#51,3,first_ <= 1
0 <= user_demand_error_UserDemand_#51,3,second_ <= 1
0 <= user_demand_error_UserDemand_#53,3,first_ <= 1
0 <= user_demand_error_UserDemand_#53,3,second_ <= 1
0 <= user_demand_error_UserDemand_#57,2,first_ <= 1
0 <= user_demand_error_UserDemand_#57,2,second_ <= 1
0 <= average_flow_unit_error_1_ <= 1
0 <= average_flow_unit_error_2_ <= 1
0 <= average_flow_unit_error_3_ <= 1
End

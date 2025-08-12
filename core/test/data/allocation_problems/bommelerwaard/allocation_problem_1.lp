minimize
obj: 
subject to
user_demand_relative_error_constraint_UserDemand_#52,2_: 1 user_demand_allocated_UserDemand_#52,2_ + 2 user_demand_error_UserDemand_#52,2,first_ >= 2
user_demand_relative_error_constraint_UserDemand_#53,2_: 1 user_demand_allocated_UserDemand_#53,2_ + 2 user_demand_error_UserDemand_#53,2,first_ >= 2
user_demand_relative_error_constraint_UserDemand_#54,2_: 1 user_demand_allocated_UserDemand_#54,2_ + 2 user_demand_error_UserDemand_#54,2,first_ >= 2
user_demand_relative_error_constraint_UserDemand_#55,2_: 1 user_demand_allocated_UserDemand_#55,2_ + 2 user_demand_error_UserDemand_#55,2,first_ >= 2
user_demand_relative_error_constraint_UserDemand_#56,2_: 1 user_demand_allocated_UserDemand_#56,2_ + 2 user_demand_error_UserDemand_#56,2,first_ >= 2
user_demand_relative_error_constraint_UserDemand_#57,3_: 1 user_demand_allocated_UserDemand_#57,3_ + 2 user_demand_error_UserDemand_#57,3,first_ >= 2
user_demand_relative_error_constraint_UserDemand_#58,1_: 1 user_demand_allocated_UserDemand_#58,1_ + 2 user_demand_error_UserDemand_#58,1,first_ >= 2
storage_constraint_in_Basin_#8,5_: 1 level_demand_allocated_Basin_#8,5,lower_ + 1 level_demand_error_Basin_#8,5,lower,first_ >= 2000
storage_constraint_in_Basin_#31,4_: 1 level_demand_allocated_Basin_#31,4,lower_ + 1 level_demand_error_Basin_#31,4,lower,first_ >= 2000
storage_constraint_in_Basin_#32,4_: 1 level_demand_allocated_Basin_#32,4,lower_ + 1 level_demand_error_Basin_#32,4,lower,first_ >= 2000
storage_constraint_out_Basin_#8,5_: -1 level_demand_allocated_Basin_#8,5,upper_ + 1 level_demand_error_Basin_#8,5,upper,first_ >= -3000
storage_constraint_out_Basin_#31,4_: -1 level_demand_allocated_Basin_#31,4,upper_ + 1 level_demand_error_Basin_#31,4,upper,first_ >= -3000
storage_constraint_out_Basin_#32,4_: -1 level_demand_allocated_Basin_#32,4,upper_ + 1 level_demand_error_Basin_#32,4,upper,first_ >= -3000
user_demand_fairness_error_constraint_UserDemand_#52,2_: -1 user_demand_error_UserDemand_#52,2,first_ + 1 user_demand_error_UserDemand_#52,2,second_ + 1 average_flow_unit_error_2_ >= 0
user_demand_fairness_error_constraint_UserDemand_#53,2_: -1 user_demand_error_UserDemand_#53,2,first_ + 1 user_demand_error_UserDemand_#53,2,second_ + 1 average_flow_unit_error_2_ >= 0
user_demand_fairness_error_constraint_UserDemand_#54,2_: -1 user_demand_error_UserDemand_#54,2,first_ + 1 user_demand_error_UserDemand_#54,2,second_ + 1 average_flow_unit_error_2_ >= 0
user_demand_fairness_error_constraint_UserDemand_#55,2_: -1 user_demand_error_UserDemand_#55,2,first_ + 1 user_demand_error_UserDemand_#55,2,second_ + 1 average_flow_unit_error_2_ >= 0
user_demand_fairness_error_constraint_UserDemand_#56,2_: -1 user_demand_error_UserDemand_#56,2,first_ + 1 user_demand_error_UserDemand_#56,2,second_ + 1 average_flow_unit_error_2_ >= 0
user_demand_fairness_error_constraint_UserDemand_#57,3_: -1 user_demand_error_UserDemand_#57,3,first_ + 1 user_demand_error_UserDemand_#57,3,second_ + 1 average_flow_unit_error_3_ >= 0
user_demand_fairness_error_constraint_UserDemand_#58,1_: -1 user_demand_error_UserDemand_#58,1,first_ + 1 user_demand_error_UserDemand_#58,1,second_ + 1 average_flow_unit_error_1_ >= 0
level_demand_fairness_error_constraint_Basin_#8,5,upper_: -0.001 level_demand_error_Basin_#8,5,upper,first_ + 1 level_demand_error_Basin_#8,5,upper,second_ + 1 average_storage_unit_error_5,upper_ >= 0
level_demand_fairness_error_constraint_Basin_#8,5,lower_: -0.001 level_demand_error_Basin_#8,5,lower,first_ + 1 level_demand_error_Basin_#8,5,lower,second_ + 1 average_storage_unit_error_5,lower_ >= 0
level_demand_fairness_error_constraint_Basin_#31,4,upper_: -0.001 level_demand_error_Basin_#31,4,upper,first_ + 1 level_demand_error_Basin_#31,4,upper,second_ + 1 average_storage_unit_error_4,upper_ >= 0
level_demand_fairness_error_constraint_Basin_#31,4,lower_: -0.001 level_demand_error_Basin_#31,4,lower,first_ + 1 level_demand_error_Basin_#31,4,lower,second_ + 1 average_storage_unit_error_4,lower_ >= 0
level_demand_fairness_error_constraint_Basin_#32,4,upper_: -0.001 level_demand_error_Basin_#32,4,upper,first_ + 1 level_demand_error_Basin_#32,4,upper,second_ + 1 average_storage_unit_error_4,upper_ >= 0
level_demand_fairness_error_constraint_Basin_#32,4,lower_: -0.001 level_demand_error_Basin_#32,4,lower,first_ + 1 level_demand_error_Basin_#32,4,lower,second_ + 1 average_storage_unit_error_4,lower_ >= 0
flow_conservation_pump_Pump_#36_: -1 flow_(Pump_#36,_Basin_#31)_ + 1 flow_(Basin_#26,_Pump_#36)_ = 0
flow_conservation_pump_Pump_#37_: 1 flow_(Basin_#31,_Pump_#37)_ - 1 flow_(Pump_#37,_Basin_#26)_ = 0
flow_conservation_pump_Pump_#38_: -1 flow_(Pump_#38,_Basin_#32)_ + 1 flow_(Basin_#26,_Pump_#38)_ = 0
flow_conservation_pump_Pump_#39_: 1 flow_(Basin_#32,_Pump_#39)_ - 1 flow_(Pump_#39,_Basin_#26)_ = 0
flow_conservation_pump_Pump_#40_: 1 flow_(Basin_#10,_Pump_#40)_ - 1 flow_(Pump_#40,_Basin_#34)_ = 0
flow_conservation_pump_Pump_#41_: 1 flow_(Basin_#18,_Pump_#41)_ - 1 flow_(Pump_#41,_Basin_#35)_ = 0
flow_conservation_pump_Pump_#42_: 1 flow_(Basin_#33,_Pump_#42)_ - 1 flow_(Pump_#42,_Basin_#26)_ = 0
flow_conservation_linear_resistance_LinearResistance_#29_: 1 flow_(Basin_#28,_LinearResistance_#29)_ - 1 flow_(LinearResistance_#29,_LevelBoundary_#30)_ = 0
flow_conservation_manning_resistance_ManningResistance_#3_: 1 flow_(Basin_#2,_ManningResistance_#3)_ - 1 flow_(ManningResistance_#3,_Basin_#4)_ = 0
flow_conservation_manning_resistance_ManningResistance_#5_: 1 flow_(Basin_#4,_ManningResistance_#5)_ - 1 flow_(ManningResistance_#5,_Basin_#6)_ = 0
flow_conservation_manning_resistance_ManningResistance_#7_: 1 flow_(Basin_#6,_ManningResistance_#7)_ - 1 flow_(ManningResistance_#7,_Basin_#8)_ = 0
flow_conservation_manning_resistance_ManningResistance_#9_: 1 flow_(Basin_#8,_ManningResistance_#9)_ - 1 flow_(ManningResistance_#9,_Basin_#10)_ = 0
flow_conservation_manning_resistance_ManningResistance_#11_: 1 flow_(Basin_#10,_ManningResistance_#11)_ - 1 flow_(ManningResistance_#11,_Basin_#12)_ = 0
flow_conservation_manning_resistance_ManningResistance_#13_: 1 flow_(Basin_#12,_ManningResistance_#13)_ - 1 flow_(ManningResistance_#13,_Basin_#14)_ = 0
flow_conservation_manning_resistance_ManningResistance_#15_: 1 flow_(Basin_#14,_ManningResistance_#15)_ - 1 flow_(ManningResistance_#15,_Basin_#16)_ = 0
flow_conservation_manning_resistance_ManningResistance_#17_: 1 flow_(Basin_#16,_ManningResistance_#17)_ - 1 flow_(ManningResistance_#17,_Basin_#18)_ = 0
flow_conservation_manning_resistance_ManningResistance_#19_: 1 flow_(Basin_#18,_ManningResistance_#19)_ - 1 flow_(ManningResistance_#19,_Basin_#20)_ = 0
flow_conservation_manning_resistance_ManningResistance_#21_: 1 flow_(Basin_#20,_ManningResistance_#21)_ - 1 flow_(ManningResistance_#21,_Basin_#22)_ = 0
flow_conservation_manning_resistance_ManningResistance_#23_: 1 flow_(Basin_#22,_ManningResistance_#23)_ - 1 flow_(ManningResistance_#23,_Basin_#24)_ = 0
flow_conservation_manning_resistance_ManningResistance_#25_: 1 flow_(Basin_#24,_ManningResistance_#25)_ - 1 flow_(ManningResistance_#25,_Basin_#26)_ = 0
flow_conservation_manning_resistance_ManningResistance_#27_: 1 flow_(Basin_#26,_ManningResistance_#27)_ - 1 flow_(ManningResistance_#27,_Basin_#28)_ = 0
flow_conservation_tabulated_rating_curve_TabulatedRatingCurve_#43_: 1 flow_(Basin_#34,_TabulatedRatingCurve_#43)_ - 1 flow_(TabulatedRatingCurve_#43,_Basin_#33)_ = 0
flow_conservation_tabulated_rating_curve_TabulatedRatingCurve_#44_: 1 flow_(Basin_#35,_TabulatedRatingCurve_#44)_ - 1 flow_(TabulatedRatingCurve_#44,_Basin_#33)_ = 0
volume_conservation_Basin_#2_: 1 basin_storage_change_Basin_#2_ + 1 low_storage_factor_Basin_#2_ - 1 flow_(FlowBoundary_#1,_Basin_#2)_ + 1 flow_(Basin_#2,_ManningResistance_#3)_ = 1
volume_conservation_Basin_#4_: 1 basin_storage_change_Basin_#4_ + 1 low_storage_factor_Basin_#4_ - 1 flow_(ManningResistance_#3,_Basin_#4)_ + 1 flow_(Basin_#4,_ManningResistance_#5)_ = 1
volume_conservation_Basin_#6_: 1 basin_storage_change_Basin_#6_ + 1 low_storage_factor_Basin_#6_ - 1 flow_(ManningResistance_#5,_Basin_#6)_ + 1 flow_(Basin_#6,_ManningResistance_#7)_ = 1
volume_conservation_Basin_#8_: 1 basin_storage_change_Basin_#8_ + 1 low_storage_factor_Basin_#8_ - 1 flow_(ManningResistance_#7,_Basin_#8)_ + 1 flow_(Basin_#8,_ManningResistance_#9)_ + 1 flow_(Basin_#8,_UserDemand_#57)_ - 1 flow_(UserDemand_#57,_Basin_#8)_ = 1
volume_conservation_Basin_#10_: 1 basin_storage_change_Basin_#10_ + 1 low_storage_factor_Basin_#10_ - 1 flow_(ManningResistance_#9,_Basin_#10)_ + 1 flow_(Basin_#10,_ManningResistance_#11)_ + 1 flow_(Basin_#10,_Pump_#40)_ = 1
volume_conservation_Basin_#12_: 1 basin_storage_change_Basin_#12_ + 1 low_storage_factor_Basin_#12_ - 1 flow_(ManningResistance_#11,_Basin_#12)_ + 1 flow_(Basin_#12,_ManningResistance_#13)_ = 1
volume_conservation_Basin_#14_: 1 basin_storage_change_Basin_#14_ + 1 low_storage_factor_Basin_#14_ - 1 flow_(ManningResistance_#13,_Basin_#14)_ + 1 flow_(Basin_#14,_ManningResistance_#15)_ = 1
volume_conservation_Basin_#16_: 1 basin_storage_change_Basin_#16_ + 1 low_storage_factor_Basin_#16_ - 1 flow_(ManningResistance_#15,_Basin_#16)_ + 1 flow_(Basin_#16,_ManningResistance_#17)_ = 1
volume_conservation_Basin_#18_: 1 basin_storage_change_Basin_#18_ + 1 low_storage_factor_Basin_#18_ - 1 flow_(ManningResistance_#17,_Basin_#18)_ + 1 flow_(Basin_#18,_ManningResistance_#19)_ + 1 flow_(Basin_#18,_Pump_#41)_ = 1
volume_conservation_Basin_#20_: 1 basin_storage_change_Basin_#20_ + 1 low_storage_factor_Basin_#20_ - 1 flow_(ManningResistance_#19,_Basin_#20)_ + 1 flow_(Basin_#20,_ManningResistance_#21)_ = 1
volume_conservation_Basin_#22_: 1 basin_storage_change_Basin_#22_ + 1 low_storage_factor_Basin_#22_ - 1 flow_(ManningResistance_#21,_Basin_#22)_ + 1 flow_(Basin_#22,_ManningResistance_#23)_ = 1
volume_conservation_Basin_#24_: 1 basin_storage_change_Basin_#24_ + 1 low_storage_factor_Basin_#24_ - 1 flow_(ManningResistance_#23,_Basin_#24)_ + 1 flow_(Basin_#24,_ManningResistance_#25)_ = 1
volume_conservation_Basin_#26_: 1 basin_storage_change_Basin_#26_ + 1 low_storage_factor_Basin_#26_ - 1 flow_(ManningResistance_#25,_Basin_#26)_ + 1 flow_(Basin_#26,_ManningResistance_#27)_ - 1 flow_(Pump_#39,_Basin_#26)_ + 1 flow_(Basin_#26,_Pump_#38)_ - 1 flow_(Pump_#37,_Basin_#26)_ + 1 flow_(Basin_#26,_Pump_#36)_ - 1 flow_(Pump_#42,_Basin_#26)_ = 1
volume_conservation_Basin_#28_: 1 basin_storage_change_Basin_#28_ + 1 low_storage_factor_Basin_#28_ - 1 flow_(ManningResistance_#27,_Basin_#28)_ + 1 flow_(Basin_#28,_LinearResistance_#29)_ + 1 flow_(Basin_#28,_UserDemand_#58)_ - 1 flow_(UserDemand_#58,_Basin_#28)_ = 1
volume_conservation_Basin_#31_: 1 basin_storage_change_Basin_#31_ + 1 low_storage_factor_Basin_#31_ + 1 flow_(Basin_#31,_Pump_#37)_ - 1 flow_(Pump_#36,_Basin_#31)_ + 1 flow_(Basin_#31,_UserDemand_#52)_ - 1 flow_(UserDemand_#52,_Basin_#31)_ = 1
volume_conservation_Basin_#32_: 1 basin_storage_change_Basin_#32_ + 1 low_storage_factor_Basin_#32_ + 1 flow_(Basin_#32,_Pump_#39)_ - 1 flow_(Pump_#38,_Basin_#32)_ + 1 flow_(Basin_#32,_UserDemand_#53)_ - 1 flow_(UserDemand_#53,_Basin_#32)_ = 1
volume_conservation_Basin_#33_: 1 basin_storage_change_Basin_#33_ + 1 low_storage_factor_Basin_#33_ - 1 flow_(TabulatedRatingCurve_#44,_Basin_#33)_ - 1 flow_(TabulatedRatingCurve_#43,_Basin_#33)_ + 1 flow_(Basin_#33,_Pump_#42)_ + 1 flow_(Basin_#33,_UserDemand_#54)_ - 1 flow_(UserDemand_#54,_Basin_#33)_ = 1
volume_conservation_Basin_#34_: 1 basin_storage_change_Basin_#34_ + 1 low_storage_factor_Basin_#34_ + 1 flow_(Basin_#34,_TabulatedRatingCurve_#43)_ - 1 flow_(Pump_#40,_Basin_#34)_ + 1 flow_(Basin_#34,_UserDemand_#55)_ - 1 flow_(UserDemand_#55,_Basin_#34)_ = 1
volume_conservation_Basin_#35_: 1 basin_storage_change_Basin_#35_ + 1 low_storage_factor_Basin_#35_ - 1 flow_(Pump_#41,_Basin_#35)_ + 1 flow_(Basin_#35,_TabulatedRatingCurve_#44)_ + 1 flow_(Basin_#35,_UserDemand_#56)_ - 1 flow_(UserDemand_#56,_Basin_#35)_ = 1
tabulated_rating_curve_constraint_TabulatedRatingCurve_#43_: 0.01 basin_storage_change_Basin_#33_ - 0.01 basin_storage_change_Basin_#34_ + 1 flow_(Basin_#34,_TabulatedRatingCurve_#43)_ = 1
tabulated_rating_curve_constraint_TabulatedRatingCurve_#44_: 0.01 basin_storage_change_Basin_#33_ - 0.01 basin_storage_change_Basin_#35_ + 1 flow_(Basin_#35,_TabulatedRatingCurve_#44)_ = 1
linear_resistance_constraint_LinearResistance_#29_: -0.01 basin_storage_change_Basin_#28_ + 1 flow_(Basin_#28,_LinearResistance_#29)_ = 1
manning_resistance_constraint_ManningResistance_#3_: -0.01 basin_storage_change_Basin_#2_ + 0.01 basin_storage_change_Basin_#4_ + 1 flow_(Basin_#2,_ManningResistance_#3)_ = 1
manning_resistance_constraint_ManningResistance_#5_: -0.01 basin_storage_change_Basin_#4_ + 0.01 basin_storage_change_Basin_#6_ + 1 flow_(Basin_#4,_ManningResistance_#5)_ = 1
manning_resistance_constraint_ManningResistance_#7_: -0.01 basin_storage_change_Basin_#6_ + 0.01 basin_storage_change_Basin_#8_ + 1 flow_(Basin_#6,_ManningResistance_#7)_ = 1
manning_resistance_constraint_ManningResistance_#9_: -0.01 basin_storage_change_Basin_#8_ + 0.01 basin_storage_change_Basin_#10_ + 1 flow_(Basin_#8,_ManningResistance_#9)_ = 1
manning_resistance_constraint_ManningResistance_#11_: -0.01 basin_storage_change_Basin_#10_ + 0.01 basin_storage_change_Basin_#12_ + 1 flow_(Basin_#10,_ManningResistance_#11)_ = 1
manning_resistance_constraint_ManningResistance_#13_: -0.01 basin_storage_change_Basin_#12_ + 0.01 basin_storage_change_Basin_#14_ + 1 flow_(Basin_#12,_ManningResistance_#13)_ = 1
manning_resistance_constraint_ManningResistance_#15_: -0.01 basin_storage_change_Basin_#14_ + 0.01 basin_storage_change_Basin_#16_ + 1 flow_(Basin_#14,_ManningResistance_#15)_ = 1
manning_resistance_constraint_ManningResistance_#17_: -0.01 basin_storage_change_Basin_#16_ + 0.01 basin_storage_change_Basin_#18_ + 1 flow_(Basin_#16,_ManningResistance_#17)_ = 1
manning_resistance_constraint_ManningResistance_#19_: -0.01 basin_storage_change_Basin_#18_ + 0.01 basin_storage_change_Basin_#20_ + 1 flow_(Basin_#18,_ManningResistance_#19)_ = 1
manning_resistance_constraint_ManningResistance_#21_: -0.01 basin_storage_change_Basin_#20_ + 0.01 basin_storage_change_Basin_#22_ + 1 flow_(Basin_#20,_ManningResistance_#21)_ = 1
manning_resistance_constraint_ManningResistance_#23_: -0.01 basin_storage_change_Basin_#22_ + 0.01 basin_storage_change_Basin_#24_ + 1 flow_(Basin_#22,_ManningResistance_#23)_ = 1
manning_resistance_constraint_ManningResistance_#25_: -0.01 basin_storage_change_Basin_#24_ + 0.01 basin_storage_change_Basin_#26_ + 1 flow_(Basin_#24,_ManningResistance_#25)_ = 1
manning_resistance_constraint_ManningResistance_#27_: -0.01 basin_storage_change_Basin_#26_ + 0.01 basin_storage_change_Basin_#28_ + 1 flow_(Basin_#26,_ManningResistance_#27)_ = 1
pump_constraint_Pump_#36_: -1 low_storage_factor_Basin_#26_ + 1 flow_(Basin_#26,_Pump_#36)_ = 0
pump_constraint_Pump_#37_: -1 low_storage_factor_Basin_#31_ + 1 flow_(Basin_#31,_Pump_#37)_ = 0
pump_constraint_Pump_#38_: -1 low_storage_factor_Basin_#26_ + 1 flow_(Basin_#26,_Pump_#38)_ = 0
pump_constraint_Pump_#39_: -1 low_storage_factor_Basin_#32_ + 1 flow_(Basin_#32,_Pump_#39)_ = 0
pump_constraint_Pump_#40_: -1 low_storage_factor_Basin_#10_ + 1 flow_(Basin_#10,_Pump_#40)_ = 0
pump_constraint_Pump_#41_: -1 low_storage_factor_Basin_#18_ + 1 flow_(Basin_#18,_Pump_#41)_ = 0
pump_constraint_Pump_#42_: -1 low_storage_factor_Basin_#33_ + 1 flow_(Basin_#33,_Pump_#42)_ = 0
c66: 1 flow_(Basin_#31,_UserDemand_#52)_ - 1 user_demand_allocated_UserDemand_#52,2_ = 0
c67: 1 flow_(Basin_#32,_UserDemand_#53)_ - 1 user_demand_allocated_UserDemand_#53,2_ = 0
c68: 1 flow_(Basin_#33,_UserDemand_#54)_ - 1 user_demand_allocated_UserDemand_#54,2_ = 0
c69: 1 flow_(Basin_#34,_UserDemand_#55)_ - 1 user_demand_allocated_UserDemand_#55,2_ = 0
c70: 1 flow_(Basin_#35,_UserDemand_#56)_ - 1 user_demand_allocated_UserDemand_#56,2_ = 0
c71: 1 flow_(Basin_#8,_UserDemand_#57)_ - 1 user_demand_allocated_UserDemand_#57,3_ = 0
c72: 1 flow_(Basin_#28,_UserDemand_#58)_ - 1 user_demand_allocated_UserDemand_#58,1_ = 0
user_demand_return_flow_UserDemand_#52_: -0.5 flow_(Basin_#31,_UserDemand_#52)_ + 1 flow_(UserDemand_#52,_Basin_#31)_ = 0
user_demand_return_flow_UserDemand_#53_: -0.5 flow_(Basin_#32,_UserDemand_#53)_ + 1 flow_(UserDemand_#53,_Basin_#32)_ = 0
user_demand_return_flow_UserDemand_#54_: -0.5 flow_(Basin_#33,_UserDemand_#54)_ + 1 flow_(UserDemand_#54,_Basin_#33)_ = 0
user_demand_return_flow_UserDemand_#55_: -0.5 flow_(Basin_#34,_UserDemand_#55)_ + 1 flow_(UserDemand_#55,_Basin_#34)_ = 0
user_demand_return_flow_UserDemand_#56_: -0.5 flow_(Basin_#35,_UserDemand_#56)_ + 1 flow_(UserDemand_#56,_Basin_#35)_ = 0
user_demand_return_flow_UserDemand_#57_: -0.5 flow_(Basin_#8,_UserDemand_#57)_ + 1 flow_(UserDemand_#57,_Basin_#8)_ = 0
user_demand_return_flow_UserDemand_#58_: -0.5 flow_(Basin_#28,_UserDemand_#58)_ + 1 flow_(UserDemand_#58,_Basin_#28)_ = 0
storage_change_allocated_sum_constraint_Basin_#8_: 1 basin_storage_change_Basin_#8_ - 1 level_demand_allocated_Basin_#8,0,lower_ + 1 level_demand_allocated_Basin_#8,0,upper_ - 1 level_demand_allocated_Basin_#8,5,lower_ + 1 level_demand_allocated_Basin_#8,5,upper_ = 0
storage_change_allocated_sum_constraint_Basin_#31_: 1 basin_storage_change_Basin_#31_ - 1 level_demand_allocated_Basin_#31,0,lower_ + 1 level_demand_allocated_Basin_#31,0,upper_ - 1 level_demand_allocated_Basin_#31,4,lower_ + 1 level_demand_allocated_Basin_#31,4,upper_ = 0
storage_change_allocated_sum_constraint_Basin_#32_: 1 basin_storage_change_Basin_#32_ - 1 level_demand_allocated_Basin_#32,0,lower_ + 1 level_demand_allocated_Basin_#32,0,upper_ - 1 level_demand_allocated_Basin_#32,4,lower_ + 1 level_demand_allocated_Basin_#32,4,upper_ = 0
average_flow_unit_error_constraint_1_: -1 user_demand_error_UserDemand_#58,1,first_ + 1 average_flow_unit_error_1_ = 0
average_flow_unit_error_constraint_2_: -1 user_demand_error_UserDemand_#52,2,first_ - 1 user_demand_error_UserDemand_#53,2,first_ - 1 user_demand_error_UserDemand_#54,2,first_ - 1 user_demand_error_UserDemand_#55,2,first_ - 1 user_demand_error_UserDemand_#56,2,first_ + 1 average_flow_unit_error_2_ = 0
average_flow_unit_error_constraint_3_: -1 user_demand_error_UserDemand_#57,3,first_ + 1 average_flow_unit_error_3_ = 0
average_storage_unit_error_constraint_4,upper_: -1 level_demand_error_Basin_#31,4,upper,first_ - 1 level_demand_error_Basin_#32,4,upper,first_ + 1000 average_storage_unit_error_4,upper_ = 0
average_storage_unit_error_constraint_5,upper_: -1 level_demand_error_Basin_#8,5,upper,first_ + 1000 average_storage_unit_error_5,upper_ = 0
average_storage_unit_error_constraint_4,lower_: -1 level_demand_error_Basin_#31,4,lower,first_ - 1 level_demand_error_Basin_#32,4,lower,first_ + 1000 average_storage_unit_error_4,lower_ = 0
average_storage_unit_error_constraint_5,lower_: -1 level_demand_error_Basin_#8,5,lower,first_ + 1000 average_storage_unit_error_5,lower_ = 0
Bounds
-0.00032607940886722903 <= basin_storage_change_Basin_#2_ <= 0.0013043176354689161
-0.00032607940886722903 <= basin_storage_change_Basin_#4_ <= 0.0013043176354689161
-0.00032607940886722903 <= basin_storage_change_Basin_#6_ <= 0.0013043176354689161
-0.00032607940886722903 <= basin_storage_change_Basin_#8_ <= 0.0013043176354689161
-0.00032607940886722903 <= basin_storage_change_Basin_#10_ <= 0.0013043176354689161
-0.00032607940886722903 <= basin_storage_change_Basin_#12_ <= 0.0013043176354689161
-0.00032607940886722903 <= basin_storage_change_Basin_#14_ <= 0.0013043176354689161
-0.00032607940886722903 <= basin_storage_change_Basin_#16_ <= 0.0013043176354689161
-0.00032607940886722903 <= basin_storage_change_Basin_#18_ <= 0.0013043176354689161
-0.00032607940886722903 <= basin_storage_change_Basin_#20_ <= 0.0013043176354689161
-0.00032607940886722903 <= basin_storage_change_Basin_#22_ <= 0.0013043176354689161
-0.00032607940886722903 <= basin_storage_change_Basin_#24_ <= 0.0013043176354689161
-0.00032607940886722903 <= basin_storage_change_Basin_#26_ <= 0.0013043176354689161
-0.00032607940886722903 <= basin_storage_change_Basin_#28_ <= 0.0013043176354689161
-0.00032607940886722903 <= basin_storage_change_Basin_#31_ <= 0.0013043176354689161
-0.00032607940886722903 <= basin_storage_change_Basin_#32_ <= 0.0013043176354689161
-0.00032607940886722903 <= basin_storage_change_Basin_#33_ <= 0.0013043176354689161
-0.00032607940886722903 <= basin_storage_change_Basin_#34_ <= 0.0013043176354689161
-0.00032607940886722903 <= basin_storage_change_Basin_#35_ <= 0.0013043176354689161
0 <= low_storage_factor_Basin_#2_ <= 1
0 <= low_storage_factor_Basin_#4_ <= 1
0 <= low_storage_factor_Basin_#6_ <= 1
0 <= low_storage_factor_Basin_#8_ <= 1
0 <= low_storage_factor_Basin_#10_ <= 1
0 <= low_storage_factor_Basin_#12_ <= 1
0 <= low_storage_factor_Basin_#14_ <= 1
0 <= low_storage_factor_Basin_#16_ <= 1
0 <= low_storage_factor_Basin_#18_ <= 1
0 <= low_storage_factor_Basin_#20_ <= 1
0 <= low_storage_factor_Basin_#22_ <= 1
0 <= low_storage_factor_Basin_#24_ <= 1
0 <= low_storage_factor_Basin_#26_ <= 1
0 <= low_storage_factor_Basin_#28_ <= 1
0 <= low_storage_factor_Basin_#31_ <= 1
0 <= low_storage_factor_Basin_#32_ <= 1
0 <= low_storage_factor_Basin_#33_ <= 1
0 <= low_storage_factor_Basin_#34_ <= 1
0 <= low_storage_factor_Basin_#35_ <= 1
0 <= flow_(FlowBoundary_#1,_Basin_#2)_ <= 14086.630463064295
-14086.630463064295 <= flow_(Basin_#2,_ManningResistance_#3)_ <= 14086.630463064295
-14086.630463064295 <= flow_(ManningResistance_#3,_Basin_#4)_ <= 14086.630463064295
-14086.630463064295 <= flow_(Basin_#4,_ManningResistance_#5)_ <= 14086.630463064295
-14086.630463064295 <= flow_(ManningResistance_#5,_Basin_#6)_ <= 14086.630463064295
-14086.630463064295 <= flow_(Basin_#6,_ManningResistance_#7)_ <= 14086.630463064295
-14086.630463064295 <= flow_(ManningResistance_#7,_Basin_#8)_ <= 14086.630463064295
-14086.630463064295 <= flow_(Basin_#8,_ManningResistance_#9)_ <= 14086.630463064295
-14086.630463064295 <= flow_(ManningResistance_#9,_Basin_#10)_ <= 14086.630463064295
-14086.630463064295 <= flow_(Basin_#10,_ManningResistance_#11)_ <= 14086.630463064295
-14086.630463064295 <= flow_(ManningResistance_#11,_Basin_#12)_ <= 14086.630463064295
-14086.630463064295 <= flow_(Basin_#12,_ManningResistance_#13)_ <= 14086.630463064295
-14086.630463064295 <= flow_(ManningResistance_#13,_Basin_#14)_ <= 14086.630463064295
-14086.630463064295 <= flow_(Basin_#14,_ManningResistance_#15)_ <= 14086.630463064295
-14086.630463064295 <= flow_(ManningResistance_#15,_Basin_#16)_ <= 14086.630463064295
-14086.630463064295 <= flow_(Basin_#16,_ManningResistance_#17)_ <= 14086.630463064295
-14086.630463064295 <= flow_(ManningResistance_#17,_Basin_#18)_ <= 14086.630463064295
-14086.630463064295 <= flow_(Basin_#18,_ManningResistance_#19)_ <= 14086.630463064295
-14086.630463064295 <= flow_(ManningResistance_#19,_Basin_#20)_ <= 14086.630463064295
-14086.630463064295 <= flow_(Basin_#20,_ManningResistance_#21)_ <= 14086.630463064295
-14086.630463064295 <= flow_(ManningResistance_#21,_Basin_#22)_ <= 14086.630463064295
-14086.630463064295 <= flow_(Basin_#22,_ManningResistance_#23)_ <= 14086.630463064295
-14086.630463064295 <= flow_(ManningResistance_#23,_Basin_#24)_ <= 14086.630463064295
-14086.630463064295 <= flow_(Basin_#24,_ManningResistance_#25)_ <= 14086.630463064295
-14086.630463064295 <= flow_(ManningResistance_#25,_Basin_#26)_ <= 14086.630463064295
-14086.630463064295 <= flow_(Basin_#26,_ManningResistance_#27)_ <= 14086.630463064295
-14086.630463064295 <= flow_(ManningResistance_#27,_Basin_#28)_ <= 14086.630463064295
-14086.630463064295 <= flow_(Basin_#28,_LinearResistance_#29)_ <= 14086.630463064295
-14086.630463064295 <= flow_(LinearResistance_#29,_LevelBoundary_#30)_ <= 14086.630463064295
flow_(Basin_#18,_Pump_#41)_ = 0
flow_(Pump_#41,_Basin_#35)_ = 0
0 <= flow_(Basin_#35,_TabulatedRatingCurve_#44)_ <= 14086.630463064295
0 <= flow_(TabulatedRatingCurve_#44,_Basin_#33)_ <= 14086.630463064295
0 <= flow_(Basin_#34,_TabulatedRatingCurve_#43)_ <= 14086.630463064295
0 <= flow_(TabulatedRatingCurve_#43,_Basin_#33)_ <= 14086.630463064295
flow_(Basin_#33,_Pump_#42)_ = 0
flow_(Basin_#10,_Pump_#40)_ = 0
flow_(Pump_#40,_Basin_#34)_ = 0
flow_(Basin_#32,_Pump_#39)_ = 0
flow_(Pump_#38,_Basin_#32)_ = 0
flow_(Pump_#39,_Basin_#26)_ = 0
flow_(Basin_#26,_Pump_#38)_ = 0
flow_(Basin_#31,_Pump_#37)_ = 0
flow_(Pump_#36,_Basin_#31)_ = 0
flow_(Pump_#37,_Basin_#26)_ = 0
flow_(Basin_#26,_Pump_#36)_ = 0
flow_(Pump_#42,_Basin_#26)_ = 0
0 <= flow_(Basin_#31,_UserDemand_#52)_ <= 14086.630463064295
0 <= flow_(UserDemand_#52,_Basin_#31)_ <= 14086.630463064295
0 <= flow_(Basin_#32,_UserDemand_#53)_ <= 14086.630463064295
0 <= flow_(UserDemand_#53,_Basin_#32)_ <= 14086.630463064295
0 <= flow_(Basin_#33,_UserDemand_#54)_ <= 14086.630463064295
0 <= flow_(UserDemand_#54,_Basin_#33)_ <= 14086.630463064295
0 <= flow_(Basin_#34,_UserDemand_#55)_ <= 14086.630463064295
0 <= flow_(UserDemand_#55,_Basin_#34)_ <= 14086.630463064295
0 <= flow_(Basin_#35,_UserDemand_#56)_ <= 14086.630463064295
0 <= flow_(UserDemand_#56,_Basin_#35)_ <= 14086.630463064295
0 <= flow_(Basin_#8,_UserDemand_#57)_ <= 14086.630463064295
0 <= flow_(UserDemand_#57,_Basin_#8)_ <= 14086.630463064295
0 <= flow_(Basin_#28,_UserDemand_#58)_ <= 14086.630463064295
0 <= flow_(UserDemand_#58,_Basin_#28)_ <= 14086.630463064295
boundary_level_LevelBoundary_#30_ = 0
0 <= user_demand_allocated_UserDemand_#52,2_ <= 2
0 <= user_demand_allocated_UserDemand_#53,2_ <= 2
0 <= user_demand_allocated_UserDemand_#54,2_ <= 2
0 <= user_demand_allocated_UserDemand_#55,2_ <= 2
0 <= user_demand_allocated_UserDemand_#56,2_ <= 2
0 <= user_demand_allocated_UserDemand_#57,3_ <= 2
0 <= user_demand_allocated_UserDemand_#58,1_ <= 2
0 <= user_demand_error_UserDemand_#52,2,first_ <= 1
0 <= user_demand_error_UserDemand_#52,2,second_ <= 1
0 <= user_demand_error_UserDemand_#53,2,first_ <= 1
0 <= user_demand_error_UserDemand_#53,2,second_ <= 1
0 <= user_demand_error_UserDemand_#54,2,first_ <= 1
0 <= user_demand_error_UserDemand_#54,2,second_ <= 1
0 <= user_demand_error_UserDemand_#55,2,first_ <= 1
0 <= user_demand_error_UserDemand_#55,2,second_ <= 1
0 <= user_demand_error_UserDemand_#56,2,first_ <= 1
0 <= user_demand_error_UserDemand_#56,2,second_ <= 1
0 <= user_demand_error_UserDemand_#57,3,first_ <= 1
0 <= user_demand_error_UserDemand_#57,3,second_ <= 1
0 <= user_demand_error_UserDemand_#58,1,first_ <= 1
0 <= user_demand_error_UserDemand_#58,1,second_ <= 1
0 <= level_demand_allocated_Basin_#8,0,lower_ <= 100
0 <= level_demand_allocated_Basin_#8,0,upper_ <= 100
0 <= level_demand_allocated_Basin_#8,5,lower_ <= 100
0 <= level_demand_allocated_Basin_#8,5,upper_ <= 100
0 <= level_demand_allocated_Basin_#31,0,lower_ <= 100
0 <= level_demand_allocated_Basin_#31,0,upper_ <= 100
0 <= level_demand_allocated_Basin_#31,4,lower_ <= 100
0 <= level_demand_allocated_Basin_#31,4,upper_ <= 100
0 <= level_demand_allocated_Basin_#32,0,lower_ <= 100
0 <= level_demand_allocated_Basin_#32,0,upper_ <= 100
0 <= level_demand_allocated_Basin_#32,4,lower_ <= 100
0 <= level_demand_allocated_Basin_#32,4,upper_ <= 100
level_demand_error_Basin_#8,5,lower,first_ >= 0
level_demand_error_Basin_#8,5,lower,second_ >= 0
level_demand_error_Basin_#8,5,upper,first_ >= 0
level_demand_error_Basin_#8,5,upper,second_ >= 0
level_demand_error_Basin_#31,4,lower,first_ >= 0
level_demand_error_Basin_#31,4,lower,second_ >= 0
level_demand_error_Basin_#31,4,upper,first_ >= 0
level_demand_error_Basin_#31,4,upper,second_ >= 0
level_demand_error_Basin_#32,4,lower,first_ >= 0
level_demand_error_Basin_#32,4,lower,second_ >= 0
level_demand_error_Basin_#32,4,upper,first_ >= 0
level_demand_error_Basin_#32,4,upper,second_ >= 0
0 <= average_flow_unit_error_1_ <= 1
0 <= average_flow_unit_error_2_ <= 1
0 <= average_flow_unit_error_3_ <= 1
average_storage_unit_error_4,lower_ >= 0
average_storage_unit_error_5,lower_ >= 0
average_storage_unit_error_4,upper_ >= 0
average_storage_unit_error_5,upper_ >= 0
End

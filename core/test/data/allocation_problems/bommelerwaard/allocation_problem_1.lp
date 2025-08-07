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
c8_2: 1 __8_3_ - 1 y_8_1_ <= 0
c9_2: 1 __9_3_ - 1 y_9_1_ <= 0
c10_2: 1 __10_3_ - 1 y_10_1_ <= 0
c11_2: 1 __11_3_ - 1 y_11_1_ <= 0
c12_2: 1 __12_3_ - 1 y_12_1_ <= 0
c13_2: 1 __13_3_ - 1 y_13_1_ <= 0
c14_2: 1 __14_3_ - 1 y_14_1_ <= 0
c15_2: 1 __15_3_ - 1 y_15_1_ <= 0
c16_2: 1 __16_3_ - 1 y_16_1_ <= 0
c17_2: 1 __17_3_ - 1 y_17_1_ <= 0
c18_2: 1 __18_3_ - 1 y_18_1_ <= 0
c19_2: 1 __19_3_ - 1 y_19_1_ <= 0
c1_1: 1 __1_2_ + 1 __1_3_ - 1 y_1_1_ >= 0
c2_1: 1 __2_2_ + 1 __2_3_ - 1 y_2_1_ >= 0
c3_1: 1 __3_2_ + 1 __3_3_ - 1 y_3_1_ >= 0
c4_1: 1 __4_2_ + 1 __4_3_ - 1 y_4_1_ >= 0
c5_1: 1 __5_2_ + 1 __5_3_ - 1 y_5_1_ >= 0
c6_1: 1 __6_2_ + 1 __6_3_ - 1 y_6_1_ >= 0
c7_1: 1 __7_2_ + 1 __7_3_ - 1 y_7_1_ >= 0
c8_1: 1 __8_2_ + 1 __8_3_ - 1 y_8_1_ >= 0
c9_1: 1 __9_2_ + 1 __9_3_ - 1 y_9_1_ >= 0
c10_1: 1 __10_2_ + 1 __10_3_ - 1 y_10_1_ >= 0
c11_1: 1 __11_2_ + 1 __11_3_ - 1 y_11_1_ >= 0
c12_1: 1 __12_2_ + 1 __12_3_ - 1 y_12_1_ >= 0
c13_1: 1 __13_2_ + 1 __13_3_ - 1 y_13_1_ >= 0
c14_1: 1 __14_2_ + 1 __14_3_ - 1 y_14_1_ >= 0
c15_1: 1 __15_2_ + 1 __15_3_ - 1 y_15_1_ >= 0
c16_1: 1 __16_2_ + 1 __16_3_ - 1 y_16_1_ >= 0
c17_1: 1 __17_2_ + 1 __17_3_ - 1 y_17_1_ >= 0
c18_1: 1 __18_2_ + 1 __18_3_ - 1 y_18_1_ >= 0
c19_1: 1 __19_2_ + 1 __19_3_ - 1 y_19_1_ >= 0
user_demand_constraint_lower_UserDemand_#52_: 1 flow_(Basin_#31,_UserDemand_#52)_ - 2 target_fraction - 1 user_demand_allocated_UserDemand_#52_ + 2 relative_user_demand_error_UserDemand_#52_ >= 0
user_demand_constraint_lower_UserDemand_#53_: 1 flow_(Basin_#32,_UserDemand_#53)_ - 2 target_fraction - 1 user_demand_allocated_UserDemand_#53_ + 2 relative_user_demand_error_UserDemand_#53_ >= 0
user_demand_constraint_lower_UserDemand_#54_: 1 flow_(Basin_#33,_UserDemand_#54)_ - 2 target_fraction - 1 user_demand_allocated_UserDemand_#54_ + 2 relative_user_demand_error_UserDemand_#54_ >= 0
user_demand_constraint_lower_UserDemand_#55_: 1 flow_(Basin_#34,_UserDemand_#55)_ - 2 target_fraction - 1 user_demand_allocated_UserDemand_#55_ + 2 relative_user_demand_error_UserDemand_#55_ >= 0
user_demand_constraint_lower_UserDemand_#56_: 1 flow_(Basin_#35,_UserDemand_#56)_ - 2 target_fraction - 1 user_demand_allocated_UserDemand_#56_ + 2 relative_user_demand_error_UserDemand_#56_ >= 0
user_demand_constraint_lower_UserDemand_#57_: 1 flow_(Basin_#8,_UserDemand_#57)_ - 2 target_fraction - 1 user_demand_allocated_UserDemand_#57_ + 2 relative_user_demand_error_UserDemand_#57_ >= 0
user_demand_constraint_lower_UserDemand_#58_: 1 flow_(Basin_#28,_UserDemand_#58)_ - 2 target_fraction - 1 user_demand_allocated_UserDemand_#58_ + 2 relative_user_demand_error_UserDemand_#58_ >= 0
storage_constraint_in_Basin_#8_: 1 basin_storage_(Basin_#8,__end)_ + 1 absolute_storage_error_Basin_#8_ >= 2000
storage_constraint_in_Basin_#31_: 1 basin_storage_(Basin_#31,__end)_ + 1 absolute_storage_error_Basin_#31_ >= 2000
storage_constraint_in_Basin_#32_: 1 basin_storage_(Basin_#32,__end)_ + 1 absolute_storage_error_Basin_#32_ >= 2000
storage_constraint_out_Basin_#8_: -1 basin_storage_(Basin_#8,__end)_ + 1 absolute_storage_error_Basin_#8_ >= -3000
storage_constraint_out_Basin_#31_: -1 basin_storage_(Basin_#31,__end)_ + 1 absolute_storage_error_Basin_#31_ >= -3000
storage_constraint_out_Basin_#32_: -1 basin_storage_(Basin_#32,__end)_ + 1 absolute_storage_error_Basin_#32_ >= -3000
c1: 1 __1_1_ + 1 __1_2_ + 1 __1_3_ = 1
c2: -1 basin_storage_(Basin_#2,__end)_ + 0.0010262675828253335 __1_2_ + 1.3499144921911483 __1_3_ = 0
c3: -1 z_1 + 1 __1_2_ + 1 __1_3_ = 0
c4: 1 low_storage_factor_Basin_#2_ - 1 z_1 = 0
c5: 1 __2_1_ + 1 __2_2_ + 1 __2_3_ = 1
c6: -1 basin_storage_(Basin_#4,__end)_ + 0.00027599261708688167 __2_2_ + 1.5533289469431826 __2_3_ = 0
c7: -1 z_2 + 1 __2_2_ + 1 __2_3_ = 0
c8: 1 low_storage_factor_Basin_#4_ - 1 z_2 = 0
c9: 1 __3_1_ + 1 __3_2_ + 1 __3_3_ = 1
c10: -1 basin_storage_(Basin_#6,__end)_ + 0.0013355859245537578 __3_2_ + 3.403860740412373 __3_3_ = 0
c11: -1 z_3 + 1 __3_2_ + 1 __3_3_ = 0
c12: 1 low_storage_factor_Basin_#6_ - 1 z_3 = 0
c13: 1 __4_1_ + 1 __4_2_ + 1 __4_3_ = 1
c14: -1 basin_storage_(Basin_#8,__end)_ + 0.0023858586716894417 __4_2_ + 3.8654532239387036 __4_3_ = 0
c15: -1 z_4 + 1 __4_2_ + 1 __4_3_ = 0
c16: 1 low_storage_factor_Basin_#8_ - 1 z_4 = 0
c17: 1 __5_1_ + 1 __5_2_ + 1 __5_3_ = 1
c18: -1 basin_storage_(Basin_#10,__end)_ + 0.0018500107347746055 __5_2_ + 2.149093543192401 __5_3_ = 0
c19: -1 z_5 + 1 __5_2_ + 1 __5_3_ = 0
c20: 1 low_storage_factor_Basin_#10_ - 1 z_5 = 0
c21: 1 __6_1_ + 1 __6_2_ + 1 __6_3_ = 1
c22: -1 basin_storage_(Basin_#12,__end)_ + 0.0017641728662932277 __6_2_ + 2.3982956780502707 __6_3_ = 0
c23: -1 z_6 + 1 __6_2_ + 1 __6_3_ = 0
c24: 1 low_storage_factor_Basin_#12_ - 1 z_6 = 0
c25: 1 __7_1_ + 1 __7_2_ + 1 __7_3_ = 1
c26: -1 basin_storage_(Basin_#14,__end)_ + 0.0046618799367941725 __7_2_ + 4.068943220280416 __7_3_ = 0
c27: -1 z_7 + 1 __7_2_ + 1 __7_3_ = 0
c28: 1 low_storage_factor_Basin_#14_ - 1 z_7 = 0
c29: 1 __8_1_ + 1 __8_2_ + 1 __8_3_ = 1
c30: -1 basin_storage_(Basin_#16,__end)_ + 0.002044225685858895 __8_2_ + 2.3329422678273555 __8_3_ = 0
c31: -1 z_8 + 1 __8_2_ + 1 __8_3_ = 0
c32: 1 low_storage_factor_Basin_#16_ - 1 z_8 = 0
c33: 1 __9_1_ + 1 __9_2_ + 1 __9_3_ = 1
c34: -1 basin_storage_(Basin_#18,__end)_ + 0.002121852173780336 __9_2_ + 2.2363731222292205 __9_3_ = 0
c35: -1 z_9 + 1 __9_2_ + 1 __9_3_ = 0
c36: 1 low_storage_factor_Basin_#18_ - 1 z_9 = 0
c37: 1 __10_1_ + 1 __10_2_ + 1 __10_3_ = 1
c38: -1 basin_storage_(Basin_#20,__end)_ + 0.00025287513532712 __10_2_ + 2.9268339512439208 __10_3_ = 0
c39: -1 z_10 + 1 __10_2_ + 1 __10_3_ = 0
c40: 1 low_storage_factor_Basin_#20_ - 1 z_10 = 0
c41: 1 __11_1_ + 1 __11_2_ + 1 __11_3_ = 1
c42: -1 basin_storage_(Basin_#22,__end)_ + 0.0008047212557287162 __11_2_ + 2.6628017152430097 __11_3_ = 0
c43: -1 z_11 + 1 __11_2_ + 1 __11_3_ = 0
c44: 1 low_storage_factor_Basin_#22_ - 1 z_11 = 0
c45: 1 __12_1_ + 1 __12_2_ + 1 __12_3_ = 1
c46: -1 basin_storage_(Basin_#24,__end)_ + 0.0011134753096902032 __12_2_ + 2.7447674765763037 __12_3_ = 0
c47: -1 z_12 + 1 __12_2_ + 1 __12_3_ = 0
c48: 1 low_storage_factor_Basin_#24_ - 1 z_12 = 0
c49: 1 __13_1_ + 1 __13_2_ + 1 __13_3_ = 1
c50: -1 basin_storage_(Basin_#26,__end)_ + 0.0058289263631338675 __13_2_ + 2.7259906268277154 __13_3_ = 0
c51: -1 z_13 + 1 __13_2_ + 1 __13_3_ = 0
c52: 1 low_storage_factor_Basin_#26_ - 1 z_13 = 0
c53: 1 __14_1_ + 1 __14_2_ + 1 __14_3_ = 1
c54: -1 basin_storage_(Basin_#28,__end)_ + 0.001475296780074815 __14_2_ + 2.2503838145373085 __14_3_ = 0
c55: -1 z_14 + 1 __14_2_ + 1 __14_3_ = 0
c56: 1 low_storage_factor_Basin_#28_ - 1 z_14 = 0
c57: 1 __15_1_ + 1 __15_2_ + 1 __15_3_ = 1
c58: -1 basin_storage_(Basin_#31,__end)_ + 0.012859919726905776 __15_2_ + 0.18371313895579683 __15_3_ = 0
c59: -1 z_15 + 1 __15_2_ + 1 __15_3_ = 0
c60: 1 low_storage_factor_Basin_#31_ - 1 z_15 = 0
c61: 1 __16_1_ + 1 __16_2_ + 1 __16_3_ = 1
c62: -1 basin_storage_(Basin_#32,__end)_ + 0.03147718716860878 __16_2_ + 0.44967410240869704 __16_3_ = 0
c63: -1 z_16 + 1 __16_2_ + 1 __16_3_ = 0
c64: 1 low_storage_factor_Basin_#32_ - 1 z_16 = 0
c65: 1 __17_1_ + 1 __17_2_ + 1 __17_3_ = 1
c66: -1 basin_storage_(Basin_#33,__end)_ + 0.007938192887653971 __17_2_ + 0.11340275553791387 __17_3_ = 0
c67: -1 z_17 + 1 __17_2_ + 1 __17_3_ = 0
c68: 1 low_storage_factor_Basin_#33_ - 1 z_17 = 0
c69: 1 __18_1_ + 1 __18_2_ + 1 __18_3_ = 1
c70: -1 basin_storage_(Basin_#34,__end)_ + 0.030544464736293866 __18_2_ + 0.436349356484451 __18_3_ = 0
c71: -1 z_18 + 1 __18_2_ + 1 __18_3_ = 0
c72: 1 low_storage_factor_Basin_#34_ - 1 z_18 = 0
c73: 1 __19_1_ + 1 __19_2_ + 1 __19_3_ = 1
c74: -1 basin_storage_(Basin_#35,__end)_ + 0.010351447898386747 __19_2_ + 0.14787782711981054 __19_3_ = 0
c75: -1 z_19 + 1 __19_2_ + 1 __19_3_ = 0
c76: 1 low_storage_factor_Basin_#35_ - 1 z_19 = 0
flow_conservation_pump_Pump_#36_: -1 flow_(Pump_#36,_Basin_#31)_ + 1 flow_(Basin_#26,_Pump_#36)_ = 0
flow_conservation_pump_Pump_#37_: 1 flow_(Basin_#31,_Pump_#37)_ - 1 flow_(Pump_#37,_Basin_#26)_ = 0
flow_conservation_pump_Pump_#38_: -1 flow_(Pump_#38,_Basin_#32)_ + 1 flow_(Basin_#26,_Pump_#38)_ = 0
flow_conservation_pump_Pump_#39_: 1 flow_(Basin_#32,_Pump_#39)_ - 1 flow_(Pump_#39,_Basin_#26)_ = 0
flow_conservation_pump_Pump_#40_: 1 flow_(Basin_#10,_Pump_#40)_ - 1 flow_(Pump_#40,_Basin_#34)_ = 0
flow_conservation_pump_Pump_#41_: 1 flow_(Basin_#18,_Pump_#41)_ - 1 flow_(Pump_#41,_Basin_#35)_ = 0
flow_conservation_pump_Pump_#42_: 1 flow_(Basin_#33,_Pump_#42)_ - 1 flow_(Pump_#42,_Basin_#26)_ = 0
flow_conservation_linearresistance_LinearResistance_#29_: 1 flow_(Basin_#28,_LinearResistance_#29)_ - 1 flow_(LinearResistance_#29,_LevelBoundary_#30)_ = 0
flow_conservation_manningresistance_ManningResistance_#3_: 1 flow_(Basin_#2,_ManningResistance_#3)_ - 1 flow_(ManningResistance_#3,_Basin_#4)_ = 0
flow_conservation_manningresistance_ManningResistance_#5_: 1 flow_(Basin_#4,_ManningResistance_#5)_ - 1 flow_(ManningResistance_#5,_Basin_#6)_ = 0
flow_conservation_manningresistance_ManningResistance_#7_: 1 flow_(Basin_#6,_ManningResistance_#7)_ - 1 flow_(ManningResistance_#7,_Basin_#8)_ = 0
flow_conservation_manningresistance_ManningResistance_#9_: 1 flow_(Basin_#8,_ManningResistance_#9)_ - 1 flow_(ManningResistance_#9,_Basin_#10)_ = 0
flow_conservation_manningresistance_ManningResistance_#11_: 1 flow_(Basin_#10,_ManningResistance_#11)_ - 1 flow_(ManningResistance_#11,_Basin_#12)_ = 0
flow_conservation_manningresistance_ManningResistance_#13_: 1 flow_(Basin_#12,_ManningResistance_#13)_ - 1 flow_(ManningResistance_#13,_Basin_#14)_ = 0
flow_conservation_manningresistance_ManningResistance_#15_: 1 flow_(Basin_#14,_ManningResistance_#15)_ - 1 flow_(ManningResistance_#15,_Basin_#16)_ = 0
flow_conservation_manningresistance_ManningResistance_#17_: 1 flow_(Basin_#16,_ManningResistance_#17)_ - 1 flow_(ManningResistance_#17,_Basin_#18)_ = 0
flow_conservation_manningresistance_ManningResistance_#19_: 1 flow_(Basin_#18,_ManningResistance_#19)_ - 1 flow_(ManningResistance_#19,_Basin_#20)_ = 0
flow_conservation_manningresistance_ManningResistance_#21_: 1 flow_(Basin_#20,_ManningResistance_#21)_ - 1 flow_(ManningResistance_#21,_Basin_#22)_ = 0
flow_conservation_manningresistance_ManningResistance_#23_: 1 flow_(Basin_#22,_ManningResistance_#23)_ - 1 flow_(ManningResistance_#23,_Basin_#24)_ = 0
flow_conservation_manningresistance_ManningResistance_#25_: 1 flow_(Basin_#24,_ManningResistance_#25)_ - 1 flow_(ManningResistance_#25,_Basin_#26)_ = 0
flow_conservation_manningresistance_ManningResistance_#27_: 1 flow_(Basin_#26,_ManningResistance_#27)_ - 1 flow_(ManningResistance_#27,_Basin_#28)_ = 0
flow_conservation_tabulatedratingcurve_TabulatedRatingCurve_#43_: 1 flow_(Basin_#34,_TabulatedRatingCurve_#43)_ - 1 flow_(TabulatedRatingCurve_#43,_Basin_#33)_ = 0
flow_conservation_tabulatedratingcurve_TabulatedRatingCurve_#44_: 1 flow_(Basin_#35,_TabulatedRatingCurve_#44)_ - 1 flow_(TabulatedRatingCurve_#44,_Basin_#33)_ = 0
volume_conservation_Basin_#2_: -1 basin_storage_(Basin_#2,__start)_ + 1 basin_storage_(Basin_#2,__end)_ - 1 flow_(FlowBoundary_#1,_Basin_#2)_ + 1 flow_(Basin_#2,_ManningResistance_#3)_ - 1 basin_forcing_Basin_#2_ = 0
volume_conservation_Basin_#4_: -1 basin_storage_(Basin_#4,__start)_ + 1 basin_storage_(Basin_#4,__end)_ - 1 flow_(ManningResistance_#3,_Basin_#4)_ + 1 flow_(Basin_#4,_ManningResistance_#5)_ - 1 basin_forcing_Basin_#4_ = 0
volume_conservation_Basin_#6_: -1 basin_storage_(Basin_#6,__start)_ + 1 basin_storage_(Basin_#6,__end)_ - 1 flow_(ManningResistance_#5,_Basin_#6)_ + 1 flow_(Basin_#6,_ManningResistance_#7)_ - 1 basin_forcing_Basin_#6_ = 0
volume_conservation_Basin_#8_: -1 basin_storage_(Basin_#8,__start)_ + 1 basin_storage_(Basin_#8,__end)_ - 1 flow_(ManningResistance_#7,_Basin_#8)_ + 1 flow_(Basin_#8,_ManningResistance_#9)_ + 1 flow_(Basin_#8,_UserDemand_#57)_ - 1 flow_(UserDemand_#57,_Basin_#8)_ - 1 basin_forcing_Basin_#8_ = 0
volume_conservation_Basin_#10_: -1 basin_storage_(Basin_#10,__start)_ + 1 basin_storage_(Basin_#10,__end)_ - 1 flow_(ManningResistance_#9,_Basin_#10)_ + 1 flow_(Basin_#10,_ManningResistance_#11)_ + 1 flow_(Basin_#10,_Pump_#40)_ - 1 basin_forcing_Basin_#10_ = 0
volume_conservation_Basin_#12_: -1 basin_storage_(Basin_#12,__start)_ + 1 basin_storage_(Basin_#12,__end)_ - 1 flow_(ManningResistance_#11,_Basin_#12)_ + 1 flow_(Basin_#12,_ManningResistance_#13)_ - 1 basin_forcing_Basin_#12_ = 0
volume_conservation_Basin_#14_: -1 basin_storage_(Basin_#14,__start)_ + 1 basin_storage_(Basin_#14,__end)_ - 1 flow_(ManningResistance_#13,_Basin_#14)_ + 1 flow_(Basin_#14,_ManningResistance_#15)_ - 1 basin_forcing_Basin_#14_ = 0
volume_conservation_Basin_#16_: -1 basin_storage_(Basin_#16,__start)_ + 1 basin_storage_(Basin_#16,__end)_ - 1 flow_(ManningResistance_#15,_Basin_#16)_ + 1 flow_(Basin_#16,_ManningResistance_#17)_ - 1 basin_forcing_Basin_#16_ = 0
volume_conservation_Basin_#18_: -1 basin_storage_(Basin_#18,__start)_ + 1 basin_storage_(Basin_#18,__end)_ - 1 flow_(ManningResistance_#17,_Basin_#18)_ + 1 flow_(Basin_#18,_ManningResistance_#19)_ + 1 flow_(Basin_#18,_Pump_#41)_ - 1 basin_forcing_Basin_#18_ = 0
volume_conservation_Basin_#20_: -1 basin_storage_(Basin_#20,__start)_ + 1 basin_storage_(Basin_#20,__end)_ - 1 flow_(ManningResistance_#19,_Basin_#20)_ + 1 flow_(Basin_#20,_ManningResistance_#21)_ - 1 basin_forcing_Basin_#20_ = 0
volume_conservation_Basin_#22_: -1 basin_storage_(Basin_#22,__start)_ + 1 basin_storage_(Basin_#22,__end)_ - 1 flow_(ManningResistance_#21,_Basin_#22)_ + 1 flow_(Basin_#22,_ManningResistance_#23)_ - 1 basin_forcing_Basin_#22_ = 0
volume_conservation_Basin_#24_: -1 basin_storage_(Basin_#24,__start)_ + 1 basin_storage_(Basin_#24,__end)_ - 1 flow_(ManningResistance_#23,_Basin_#24)_ + 1 flow_(Basin_#24,_ManningResistance_#25)_ - 1 basin_forcing_Basin_#24_ = 0
volume_conservation_Basin_#26_: -1 basin_storage_(Basin_#26,__start)_ + 1 basin_storage_(Basin_#26,__end)_ - 1 flow_(ManningResistance_#25,_Basin_#26)_ + 1 flow_(Basin_#26,_ManningResistance_#27)_ - 1 flow_(Pump_#39,_Basin_#26)_ + 1 flow_(Basin_#26,_Pump_#38)_ - 1 flow_(Pump_#37,_Basin_#26)_ + 1 flow_(Basin_#26,_Pump_#36)_ - 1 flow_(Pump_#42,_Basin_#26)_ - 1 basin_forcing_Basin_#26_ = 0
volume_conservation_Basin_#28_: -1 basin_storage_(Basin_#28,__start)_ + 1 basin_storage_(Basin_#28,__end)_ - 1 flow_(ManningResistance_#27,_Basin_#28)_ + 1 flow_(Basin_#28,_LinearResistance_#29)_ + 1 flow_(Basin_#28,_UserDemand_#58)_ - 1 flow_(UserDemand_#58,_Basin_#28)_ - 1 basin_forcing_Basin_#28_ = 0
volume_conservation_Basin_#31_: -1 basin_storage_(Basin_#31,__start)_ + 1 basin_storage_(Basin_#31,__end)_ + 1 flow_(Basin_#31,_Pump_#37)_ - 1 flow_(Pump_#36,_Basin_#31)_ + 1 flow_(Basin_#31,_UserDemand_#52)_ - 1 flow_(UserDemand_#52,_Basin_#31)_ - 1 basin_forcing_Basin_#31_ = 0
volume_conservation_Basin_#32_: -1 basin_storage_(Basin_#32,__start)_ + 1 basin_storage_(Basin_#32,__end)_ + 1 flow_(Basin_#32,_Pump_#39)_ - 1 flow_(Pump_#38,_Basin_#32)_ + 1 flow_(Basin_#32,_UserDemand_#53)_ - 1 flow_(UserDemand_#53,_Basin_#32)_ - 1 basin_forcing_Basin_#32_ = 0
volume_conservation_Basin_#33_: -1 basin_storage_(Basin_#33,__start)_ + 1 basin_storage_(Basin_#33,__end)_ - 1 flow_(TabulatedRatingCurve_#44,_Basin_#33)_ - 1 flow_(TabulatedRatingCurve_#43,_Basin_#33)_ + 1 flow_(Basin_#33,_Pump_#42)_ + 1 flow_(Basin_#33,_UserDemand_#54)_ - 1 flow_(UserDemand_#54,_Basin_#33)_ - 1 basin_forcing_Basin_#33_ = 0
volume_conservation_Basin_#34_: -1 basin_storage_(Basin_#34,__start)_ + 1 basin_storage_(Basin_#34,__end)_ + 1 flow_(Basin_#34,_TabulatedRatingCurve_#43)_ - 1 flow_(Pump_#40,_Basin_#34)_ + 1 flow_(Basin_#34,_UserDemand_#55)_ - 1 flow_(UserDemand_#55,_Basin_#34)_ - 1 basin_forcing_Basin_#34_ = 0
volume_conservation_Basin_#35_: -1 basin_storage_(Basin_#35,__start)_ + 1 basin_storage_(Basin_#35,__end)_ - 1 flow_(Pump_#41,_Basin_#35)_ + 1 flow_(Basin_#35,_TabulatedRatingCurve_#44)_ + 1 flow_(Basin_#35,_UserDemand_#56)_ - 1 flow_(UserDemand_#56,_Basin_#35)_ - 1 basin_forcing_Basin_#35_ = 0
tabulated_rating_curve_constraint_TabulatedRatingCurve_#43_: 1 basin_storage_(Basin_#33,__end)_ - 1 basin_storage_(Basin_#34,__end)_ + 1 flow_(Basin_#34,_TabulatedRatingCurve_#43)_ = 1
tabulated_rating_curve_constraint_TabulatedRatingCurve_#44_: 1 basin_storage_(Basin_#33,__end)_ - 1 basin_storage_(Basin_#35,__end)_ + 1 flow_(Basin_#35,_TabulatedRatingCurve_#44)_ = 1
linear_resistance_constraint_LinearResistance_#29_: -1 basin_storage_(Basin_#28,__end)_ + 1 flow_(Basin_#28,_LinearResistance_#29)_ + 1 boundary_level_LevelBoundary_#30_ = 1
manning_resistance_constraint_ManningResistance_#3_: -1 basin_storage_(Basin_#2,__end)_ + 1 basin_storage_(Basin_#4,__end)_ + 1 flow_(Basin_#2,_ManningResistance_#3)_ = 1
manning_resistance_constraint_ManningResistance_#5_: -1 basin_storage_(Basin_#4,__end)_ + 1 basin_storage_(Basin_#6,__end)_ + 1 flow_(Basin_#4,_ManningResistance_#5)_ = 1
manning_resistance_constraint_ManningResistance_#7_: -1 basin_storage_(Basin_#6,__end)_ + 1 basin_storage_(Basin_#8,__end)_ + 1 flow_(Basin_#6,_ManningResistance_#7)_ = 1
manning_resistance_constraint_ManningResistance_#9_: -1 basin_storage_(Basin_#8,__end)_ + 1 basin_storage_(Basin_#10,__end)_ + 1 flow_(Basin_#8,_ManningResistance_#9)_ = 1
manning_resistance_constraint_ManningResistance_#11_: -1 basin_storage_(Basin_#10,__end)_ + 1 basin_storage_(Basin_#12,__end)_ + 1 flow_(Basin_#10,_ManningResistance_#11)_ = 1
manning_resistance_constraint_ManningResistance_#13_: -1 basin_storage_(Basin_#12,__end)_ + 1 basin_storage_(Basin_#14,__end)_ + 1 flow_(Basin_#12,_ManningResistance_#13)_ = 1
manning_resistance_constraint_ManningResistance_#15_: -1 basin_storage_(Basin_#14,__end)_ + 1 basin_storage_(Basin_#16,__end)_ + 1 flow_(Basin_#14,_ManningResistance_#15)_ = 1
manning_resistance_constraint_ManningResistance_#17_: -1 basin_storage_(Basin_#16,__end)_ + 1 basin_storage_(Basin_#18,__end)_ + 1 flow_(Basin_#16,_ManningResistance_#17)_ = 1
manning_resistance_constraint_ManningResistance_#19_: -1 basin_storage_(Basin_#18,__end)_ + 1 basin_storage_(Basin_#20,__end)_ + 1 flow_(Basin_#18,_ManningResistance_#19)_ = 1
manning_resistance_constraint_ManningResistance_#21_: -1 basin_storage_(Basin_#20,__end)_ + 1 basin_storage_(Basin_#22,__end)_ + 1 flow_(Basin_#20,_ManningResistance_#21)_ = 1
manning_resistance_constraint_ManningResistance_#23_: -1 basin_storage_(Basin_#22,__end)_ + 1 basin_storage_(Basin_#24,__end)_ + 1 flow_(Basin_#22,_ManningResistance_#23)_ = 1
manning_resistance_constraint_ManningResistance_#25_: -1 basin_storage_(Basin_#24,__end)_ + 1 basin_storage_(Basin_#26,__end)_ + 1 flow_(Basin_#24,_ManningResistance_#25)_ = 1
manning_resistance_constraint_ManningResistance_#27_: -1 basin_storage_(Basin_#26,__end)_ + 1 basin_storage_(Basin_#28,__end)_ + 1 flow_(Basin_#26,_ManningResistance_#27)_ = 1
pump_constraint_Pump_#36_: -1 low_storage_factor_Basin_#26_ + 1 flow_(Basin_#26,_Pump_#36)_ = 0
pump_constraint_Pump_#37_: -1 low_storage_factor_Basin_#31_ + 1 flow_(Basin_#31,_Pump_#37)_ = 0
pump_constraint_Pump_#38_: -1 low_storage_factor_Basin_#26_ + 1 flow_(Basin_#26,_Pump_#38)_ = 0
pump_constraint_Pump_#39_: -1 low_storage_factor_Basin_#32_ + 1 flow_(Basin_#32,_Pump_#39)_ = 0
pump_constraint_Pump_#40_: -1 low_storage_factor_Basin_#10_ + 1 flow_(Basin_#10,_Pump_#40)_ = 0
pump_constraint_Pump_#41_: -1 low_storage_factor_Basin_#18_ + 1 flow_(Basin_#18,_Pump_#41)_ = 0
pump_constraint_Pump_#42_: -1 low_storage_factor_Basin_#33_ + 1 flow_(Basin_#33,_Pump_#42)_ = 0
user_demand_return_flow_UserDemand_#52_: -0.5 flow_(Basin_#31,_UserDemand_#52)_ + 1 flow_(UserDemand_#52,_Basin_#31)_ = 0
user_demand_return_flow_UserDemand_#53_: -0.5 flow_(Basin_#32,_UserDemand_#53)_ + 1 flow_(UserDemand_#53,_Basin_#32)_ = 0
user_demand_return_flow_UserDemand_#54_: -0.5 flow_(Basin_#33,_UserDemand_#54)_ + 1 flow_(UserDemand_#54,_Basin_#33)_ = 0
user_demand_return_flow_UserDemand_#55_: -0.5 flow_(Basin_#34,_UserDemand_#55)_ + 1 flow_(UserDemand_#55,_Basin_#34)_ = 0
user_demand_return_flow_UserDemand_#56_: -0.5 flow_(Basin_#35,_UserDemand_#56)_ + 1 flow_(UserDemand_#56,_Basin_#35)_ = 0
user_demand_return_flow_UserDemand_#57_: -0.5 flow_(Basin_#8,_UserDemand_#57)_ + 1 flow_(UserDemand_#57,_Basin_#8)_ = 0
user_demand_return_flow_UserDemand_#58_: -0.5 flow_(Basin_#28,_UserDemand_#58)_ + 1 flow_(UserDemand_#58,_Basin_#28)_ = 0
Bounds
0 <= basin_storage_(Basin_#2,__start)_ <= 1.3499144921911483
0 <= basin_storage_(Basin_#4,__start)_ <= 1.5533289469431826
0 <= basin_storage_(Basin_#6,__start)_ <= 3.403860740412373
0 <= basin_storage_(Basin_#8,__start)_ <= 3.8654532239387036
0 <= basin_storage_(Basin_#10,__start)_ <= 2.149093543192401
0 <= basin_storage_(Basin_#12,__start)_ <= 2.3982956780502707
0 <= basin_storage_(Basin_#14,__start)_ <= 4.068943220280416
0 <= basin_storage_(Basin_#16,__start)_ <= 2.3329422678273555
0 <= basin_storage_(Basin_#18,__start)_ <= 2.2363731222292205
0 <= basin_storage_(Basin_#20,__start)_ <= 2.9268339512439208
0 <= basin_storage_(Basin_#22,__start)_ <= 2.6628017152430097
0 <= basin_storage_(Basin_#24,__start)_ <= 2.7447674765763037
0 <= basin_storage_(Basin_#26,__start)_ <= 2.7259906268277154
0 <= basin_storage_(Basin_#28,__start)_ <= 2.2503838145373085
0 <= basin_storage_(Basin_#31,__start)_ <= 0.18371313895579683
0 <= basin_storage_(Basin_#32,__start)_ <= 0.44967410240869704
0 <= basin_storage_(Basin_#33,__start)_ <= 0.11340275553791387
0 <= basin_storage_(Basin_#34,__start)_ <= 0.436349356484451
0 <= basin_storage_(Basin_#35,__start)_ <= 0.14787782711981054
0 <= basin_storage_(Basin_#2,__end)_ <= 1.3499144921911483
0 <= basin_storage_(Basin_#4,__end)_ <= 1.5533289469431826
0 <= basin_storage_(Basin_#6,__end)_ <= 3.403860740412373
0 <= basin_storage_(Basin_#8,__end)_ <= 3.8654532239387036
0 <= basin_storage_(Basin_#10,__end)_ <= 2.149093543192401
0 <= basin_storage_(Basin_#12,__end)_ <= 2.3982956780502707
0 <= basin_storage_(Basin_#14,__end)_ <= 4.068943220280416
0 <= basin_storage_(Basin_#16,__end)_ <= 2.3329422678273555
0 <= basin_storage_(Basin_#18,__end)_ <= 2.2363731222292205
0 <= basin_storage_(Basin_#20,__end)_ <= 2.9268339512439208
0 <= basin_storage_(Basin_#22,__end)_ <= 2.6628017152430097
0 <= basin_storage_(Basin_#24,__end)_ <= 2.7447674765763037
0 <= basin_storage_(Basin_#26,__end)_ <= 2.7259906268277154
0 <= basin_storage_(Basin_#28,__end)_ <= 2.2503838145373085
0 <= basin_storage_(Basin_#31,__end)_ <= 0.18371313895579683
0 <= basin_storage_(Basin_#32,__end)_ <= 0.44967410240869704
0 <= basin_storage_(Basin_#33,__end)_ <= 0.11340275553791387
0 <= basin_storage_(Basin_#34,__end)_ <= 0.436349356484451
0 <= basin_storage_(Basin_#35,__end)_ <= 0.14787782711981054
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
0 <= z_15 <= 1
0 <= __15_1_ <= 1
0 <= __15_2_ <= 1
0 <= __15_3_ <= 1
0 <= z_16 <= 1
0 <= __16_1_ <= 1
0 <= __16_2_ <= 1
0 <= __16_3_ <= 1
0 <= z_17 <= 1
0 <= __17_1_ <= 1
0 <= __17_2_ <= 1
0 <= __17_3_ <= 1
0 <= z_18 <= 1
0 <= __18_1_ <= 1
0 <= __18_2_ <= 1
0 <= __18_3_ <= 1
0 <= z_19 <= 1
0 <= __19_1_ <= 1
0 <= __19_2_ <= 1
0 <= __19_3_ <= 1
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
basin_forcing_Basin_#2_ = 0
basin_forcing_Basin_#4_ = 0
basin_forcing_Basin_#6_ = 0
basin_forcing_Basin_#8_ = 0
basin_forcing_Basin_#10_ = 0
basin_forcing_Basin_#12_ = 0
basin_forcing_Basin_#14_ = 0
basin_forcing_Basin_#16_ = 0
basin_forcing_Basin_#18_ = 0
basin_forcing_Basin_#20_ = 0
basin_forcing_Basin_#22_ = 0
basin_forcing_Basin_#24_ = 0
basin_forcing_Basin_#26_ = 0
basin_forcing_Basin_#28_ = 0
basin_forcing_Basin_#31_ = 0
basin_forcing_Basin_#32_ = 0
basin_forcing_Basin_#33_ = 0
basin_forcing_Basin_#34_ = 0
basin_forcing_Basin_#35_ = 0
boundary_level_LevelBoundary_#30_ = 0
target_fraction = 1
user_demand_allocated_UserDemand_#52_ = 0
user_demand_allocated_UserDemand_#53_ = 0
user_demand_allocated_UserDemand_#54_ = 0
user_demand_allocated_UserDemand_#55_ = 0
user_demand_allocated_UserDemand_#56_ = 0
user_demand_allocated_UserDemand_#57_ = 0
user_demand_allocated_UserDemand_#58_ = 0
relative_user_demand_error_UserDemand_#52_ >= 0
relative_user_demand_error_UserDemand_#53_ >= 0
relative_user_demand_error_UserDemand_#54_ >= 0
relative_user_demand_error_UserDemand_#55_ >= 0
relative_user_demand_error_UserDemand_#56_ >= 0
relative_user_demand_error_UserDemand_#57_ >= 0
relative_user_demand_error_UserDemand_#58_ >= 0
absolute_storage_error_Basin_#8_ >= 0
absolute_storage_error_Basin_#31_ >= 0
absolute_storage_error_Basin_#32_ >= 0
Binary
y_1_1_
y_2_1_
y_3_1_
y_4_1_
y_5_1_
y_6_1_
y_7_1_
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
y_18_1_
y_19_1_
End

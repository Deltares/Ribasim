minimize
obj: 
subject to
c1_2: 1 __6_3_ - 1 y_6_1_ <= 0
c2_2: 1 __7_3_ - 1 y_7_1_ <= 0
c3_2: 1 __8_3_ - 1 y_8_1_ <= 0
c4_1: 1 __9_3_ - 1 y_9_1_ <= 0
c5_2: 1 __10_3_ - 1 y_10_1_ <= 0
c1_1: 1 __6_2_ + 1 __6_3_ - 1 y_6_1_ >= 0
c2_1: 1 __7_2_ + 1 __7_3_ - 1 y_7_1_ >= 0
c3_1: 1 __8_2_ + 1 __8_3_ - 1 y_8_1_ >= 0
c4: 1 __9_2_ + 1 __9_3_ - 1 y_9_1_ >= 0
c5_1: 1 __10_2_ + 1 __10_3_ - 1 y_10_1_ >= 0
user_demand_constraint_lower_UserDemand_#60_: 1 flow_(Basin_#8,_UserDemand_#60)_ - 2 target_fraction - 1 user_demand_allocated_UserDemand_#60_ + 2 relative_user_demand_error_lower_UserDemand_#60_ >= 0
user_demand_constraint_upper_UserDemand_#60_: -1 flow_(Basin_#8,_UserDemand_#60)_ + 2 target_fraction + 1 user_demand_allocated_UserDemand_#60_ + 2 relative_user_demand_error_upper_UserDemand_#60_ >= 0
subnetwork_constraint_lower_(Pump_#11,_Basin_#12)_: 1 flow_(Pump_#11,_Basin_#12)_ - 2 target_fraction - 1 subnetwork_(Pump_#11,_Basin_#12)_ + 2 relative_subnetwork_error_lower_(Pump_#11,_Basin_#12)_ >= 0
subnetwork_constraint_lower_(Pump_#24,_Basin_#25)_: 1 flow_(Pump_#24,_Basin_#25)_ - 2 target_fraction - 1 subnetwork_(Pump_#24,_Basin_#25)_ + 2 relative_subnetwork_error_lower_(Pump_#24,_Basin_#25)_ >= 0
subnetwork_constraint_lower_(Pump_#38,_Basin_#35)_: 1 flow_(Pump_#38,_Basin_#35)_ - 2 target_fraction - 1 subnetwork_(Pump_#38,_Basin_#35)_ + 2 relative_subnetwork_error_lower_(Pump_#38,_Basin_#35)_ >= 0
subnetwork_constraint_upper_(Pump_#11,_Basin_#12)_: -1 flow_(Pump_#11,_Basin_#12)_ + 2 target_fraction + 1 subnetwork_(Pump_#11,_Basin_#12)_ + 2 relative_subnetwork_error_upper_(Pump_#11,_Basin_#12)_ >= 0
subnetwork_constraint_upper_(Pump_#24,_Basin_#25)_: -1 flow_(Pump_#24,_Basin_#25)_ + 2 target_fraction + 1 subnetwork_(Pump_#24,_Basin_#25)_ + 2 relative_subnetwork_error_upper_(Pump_#24,_Basin_#25)_ >= 0
subnetwork_constraint_upper_(Pump_#38,_Basin_#35)_: -1 flow_(Pump_#38,_Basin_#35)_ + 2 target_fraction + 1 subnetwork_(Pump_#38,_Basin_#35)_ + 2 relative_subnetwork_error_upper_(Pump_#38,_Basin_#35)_ >= 0
c1: 1 __1_1_ + 1 __1_2_ = 1
c2: -1 basin_storage_(Basin_#2,__end)_ + 2 __1_2_ = 0
c3: -1 z_1 + 1 __1_2_ = 0
basin_profile_Basin_#2_: 1 basin_level_Basin_#2_ - 1 z_1 = 0
c5: 1 __2_1_ + 1 __2_2_ = 1
c6: -1 basin_storage_(Basin_#4,__end)_ + 2 __2_2_ = 0
c7: -1 z_2 + 1 __2_2_ = 0
basin_profile_Basin_#4_: 1 basin_level_Basin_#4_ - 1 z_2 = 0
c9: 1 __3_1_ + 1 __3_2_ = 1
c10: -1 basin_storage_(Basin_#6,__end)_ + 2 __3_2_ = 0
c11: -1 z_3 + 1 __3_2_ = 0
basin_profile_Basin_#6_: 1 basin_level_Basin_#6_ - 1 z_3 = 0
c13: 1 __4_1_ + 1 __4_2_ = 1
c14: -1 basin_storage_(Basin_#8,__end)_ + 2 __4_2_ = 0
c15: -1 z_4 + 1 __4_2_ = 0
basin_profile_Basin_#8_: 1 basin_level_Basin_#8_ - 1 z_4 = 0
c17: 1 __5_1_ + 1 __5_2_ = 1
c18: -1 basin_storage_(Basin_#10,__end)_ + 2 __5_2_ = 0
c19: -1 z_5 + 1 __5_2_ = 0
basin_profile_Basin_#10_: 1 basin_level_Basin_#10_ - 1 z_5 = 0
c21: 1 __6_1_ + 1 __6_2_ + 1 __6_3_ = 1
c22: -1 basin_storage_(Basin_#2,__end)_ + 0.2 __6_2_ + 2 __6_3_ = 0
c23: -1 z_6 + 1 __6_2_ + 1 __6_3_ = 0
c24: 1 low_storage_factor_Basin_#2_ - 1 z_6 = 0
c25: 1 __7_1_ + 1 __7_2_ + 1 __7_3_ = 1
c26: -1 basin_storage_(Basin_#4,__end)_ + 0.2 __7_2_ + 2 __7_3_ = 0
c27: -1 z_7 + 1 __7_2_ + 1 __7_3_ = 0
c28: 1 low_storage_factor_Basin_#4_ - 1 z_7 = 0
c29: 1 __8_1_ + 1 __8_2_ + 1 __8_3_ = 1
c30: -1 basin_storage_(Basin_#6,__end)_ + 0.2 __8_2_ + 2 __8_3_ = 0
c31: -1 z_8 + 1 __8_2_ + 1 __8_3_ = 0
c32: 1 low_storage_factor_Basin_#6_ - 1 z_8 = 0
c33: 1 __9_1_ + 1 __9_2_ + 1 __9_3_ = 1
c34: -1 basin_storage_(Basin_#8,__end)_ + 0.2 __9_2_ + 2 __9_3_ = 0
c35: -1 z_9 + 1 __9_2_ + 1 __9_3_ = 0
c36: 1 low_storage_factor_Basin_#8_ - 1 z_9 = 0
c37: 1 __10_1_ + 1 __10_2_ + 1 __10_3_ = 1
c38: -1 basin_storage_(Basin_#10,__end)_ + 0.2 __10_2_ + 2 __10_3_ = 0
c39: -1 z_10 + 1 __10_2_ + 1 __10_3_ = 0
c40: 1 low_storage_factor_Basin_#10_ - 1 z_10 = 0
flow_conservation_pump_Pump_#11_: -1 flow_(Pump_#11,_Basin_#12)_ + 1 flow_(Basin_#2,_Pump_#11)_ = 0
flow_conservation_pump_Pump_#24_: -1 flow_(Pump_#24,_Basin_#25)_ + 1 flow_(Basin_#6,_Pump_#24)_ = 0
flow_conservation_pump_Pump_#38_: -1 flow_(Pump_#38,_Basin_#35)_ + 1 flow_(Basin_#10,_Pump_#38)_ = 0
flow_conservation_linearresistance_LinearResistance_#3_: 1 flow_(Basin_#2,_LinearResistance_#3)_ - 1 flow_(LinearResistance_#3,_Basin_#4)_ = 0
flow_conservation_linearresistance_LinearResistance_#5_: 1 flow_(Basin_#4,_LinearResistance_#5)_ - 1 flow_(LinearResistance_#5,_Basin_#6)_ = 0
flow_conservation_linearresistance_LinearResistance_#7_: 1 flow_(Basin_#6,_LinearResistance_#7)_ - 1 flow_(LinearResistance_#7,_Basin_#8)_ = 0
flow_conservation_linearresistance_LinearResistance_#9_: 1 flow_(Basin_#8,_LinearResistance_#9)_ - 1 flow_(LinearResistance_#9,_Basin_#10)_ = 0
volume_conservation_Basin_#2_: -1 basin_storage_(Basin_#2,__start)_ + 1 basin_storage_(Basin_#2,__end)_ - 1 flow_(FlowBoundary_#1,_Basin_#2)_ + 1 flow_(Basin_#2,_LinearResistance_#3)_ + 1 flow_(Basin_#2,_Pump_#11)_ - 1 basin_forcing_Basin_#2_ = 0
volume_conservation_Basin_#4_: -1 basin_storage_(Basin_#4,__start)_ + 1 basin_storage_(Basin_#4,__end)_ - 1 flow_(LinearResistance_#3,_Basin_#4)_ + 1 flow_(Basin_#4,_LinearResistance_#5)_ - 1 basin_forcing_Basin_#4_ = 0
volume_conservation_Basin_#6_: -1 basin_storage_(Basin_#6,__start)_ + 1 basin_storage_(Basin_#6,__end)_ - 1 flow_(LinearResistance_#5,_Basin_#6)_ + 1 flow_(Basin_#6,_LinearResistance_#7)_ + 1 flow_(Basin_#6,_Pump_#24)_ - 1 basin_forcing_Basin_#6_ = 0
volume_conservation_Basin_#8_: -1 basin_storage_(Basin_#8,__start)_ + 1 basin_storage_(Basin_#8,__end)_ - 1 flow_(LinearResistance_#7,_Basin_#8)_ + 1 flow_(Basin_#8,_LinearResistance_#9)_ + 1 flow_(Basin_#8,_UserDemand_#60)_ - 1 flow_(UserDemand_#60,_Basin_#8)_ - 1 basin_forcing_Basin_#8_ = 0
volume_conservation_Basin_#10_: -1 basin_storage_(Basin_#10,__start)_ + 1 basin_storage_(Basin_#10,__end)_ - 1 flow_(LinearResistance_#9,_Basin_#10)_ + 1 flow_(Basin_#10,_Pump_#38)_ - 1 basin_forcing_Basin_#10_ = 0
linear_resistance_LinearResistance_#3_: -172800 basin_level_Basin_#2_ + 172800 basin_level_Basin_#4_ + 1 flow_(Basin_#2,_LinearResistance_#3)_ = 0
linear_resistance_LinearResistance_#5_: -172800 basin_level_Basin_#4_ + 172800 basin_level_Basin_#6_ + 1 flow_(Basin_#4,_LinearResistance_#5)_ = 0
linear_resistance_LinearResistance_#7_: -172800 basin_level_Basin_#6_ + 172800 basin_level_Basin_#8_ + 1 flow_(Basin_#6,_LinearResistance_#7)_ = 0
linear_resistance_LinearResistance_#9_: -172800 basin_level_Basin_#8_ + 172800 basin_level_Basin_#10_ + 1 flow_(Basin_#8,_LinearResistance_#9)_ = 0
pump_constraint_Pump_#11_: -1 low_storage_factor_Basin_#2_ + 1 flow_(Basin_#2,_Pump_#11)_ = 0
pump_constraint_Pump_#24_: -1 low_storage_factor_Basin_#6_ + 1 flow_(Basin_#6,_Pump_#24)_ = 0
pump_constraint_Pump_#38_: -1 low_storage_factor_Basin_#10_ + 1 flow_(Basin_#10,_Pump_#38)_ = 0
user_demand_return_flow_UserDemand_#60_: -0.5 flow_(Basin_#8,_UserDemand_#60)_ + 1 flow_(UserDemand_#60,_Basin_#8)_ = 0
Bounds
0 <= basin_storage_(Basin_#2,__start)_ <= 2
0 <= basin_storage_(Basin_#4,__start)_ <= 2
0 <= basin_storage_(Basin_#6,__start)_ <= 2
0 <= basin_storage_(Basin_#8,__start)_ <= 2
0 <= basin_storage_(Basin_#10,__start)_ <= 2
0 <= basin_storage_(Basin_#2,__end)_ <= 2
0 <= basin_storage_(Basin_#4,__end)_ <= 2
0 <= basin_storage_(Basin_#6,__end)_ <= 2
0 <= basin_storage_(Basin_#8,__end)_ <= 2
0 <= basin_storage_(Basin_#10,__end)_ <= 2
0 <= basin_level_Basin_#2_ <= 1
0 <= basin_level_Basin_#4_ <= 1
0 <= basin_level_Basin_#6_ <= 1
0 <= basin_level_Basin_#8_ <= 1
0 <= basin_level_Basin_#10_ <= 1
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
0 <= low_storage_factor_Basin_#2_ <= 1
0 <= low_storage_factor_Basin_#4_ <= 1
0 <= low_storage_factor_Basin_#6_ <= 1
0 <= low_storage_factor_Basin_#8_ <= 1
0 <= low_storage_factor_Basin_#10_ <= 1
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
basin_forcing_Basin_#8_ = 0
basin_forcing_Basin_#2_ = 0
basin_forcing_Basin_#6_ = 0
basin_forcing_Basin_#10_ = 0
basin_forcing_Basin_#4_ = 0
target_fraction = 1
user_demand_allocated_UserDemand_#60_ = 0
relative_user_demand_error_lower_UserDemand_#60_ >= 0
relative_user_demand_error_upper_UserDemand_#60_ >= 0
target_storage_demand_fraction_in = 1
target_storage_demand_fraction_out = 1
subnetwork_(Pump_#11,_Basin_#12)_ = 0
subnetwork_(Pump_#24,_Basin_#25)_ = 0
subnetwork_(Pump_#38,_Basin_#35)_ = 0
relative_subnetwork_error_lower_(Pump_#11,_Basin_#12)_ >= 0
relative_subnetwork_error_lower_(Pump_#24,_Basin_#25)_ >= 0
relative_subnetwork_error_lower_(Pump_#38,_Basin_#35)_ >= 0
relative_subnetwork_error_upper_(Pump_#11,_Basin_#12)_ >= 0
relative_subnetwork_error_upper_(Pump_#24,_Basin_#25)_ >= 0
relative_subnetwork_error_upper_(Pump_#38,_Basin_#35)_ >= 0
Binary
y_6_1_
y_7_1_
y_8_1_
y_9_1_
y_10_1_
End

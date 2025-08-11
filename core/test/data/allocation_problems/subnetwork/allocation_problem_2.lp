minimize
obj: 
subject to
c1_2: 1 __4_3_ - 1 y_4_1_ <= 0
c2_2: 1 __5_3_ - 1 y_5_1_ <= 0
c3_2: 1 __6_3_ - 1 y_6_1_ <= 0
c1_1: 1 __4_2_ + 1 __4_3_ - 1 y_4_1_ >= 0
c2_1: 1 __5_2_ + 1 __5_3_ - 1 y_5_1_ >= 0
c3_1: 1 __6_2_ + 1 __6_3_ - 1 y_6_1_ >= 0
user_demand_constraint_lower_UserDemand_#10_: 1 flow_(Basin_#2,_UserDemand_#10)_ - 2 target_fraction - 1 user_demand_allocated_UserDemand_#10_ + 2 relative_user_demand_error_UserDemand_#10_ >= 0
user_demand_constraint_lower_UserDemand_#11_: 1 flow_(Basin_#6,_UserDemand_#11)_ - 2 target_fraction - 1 user_demand_allocated_UserDemand_#11_ + 2 relative_user_demand_error_UserDemand_#11_ >= 0
user_demand_constraint_lower_UserDemand_#12_: 1 flow_(Basin_#8,_UserDemand_#12)_ - 2 target_fraction - 1 user_demand_allocated_UserDemand_#12_ + 2 relative_user_demand_error_UserDemand_#12_ >= 0
c1: 1 __1_1_ + 1 __1_2_ = 1
c2: -1 basin_storage_(Basin_#2,__end)_ + 2 __1_2_ = 0
c3: -1 z_1 + 100 __1_2_ = 0
basin_profile_Basin_#2_: 1 basin_level_Basin_#2_ - 1 z_1 = 0
c5: 1 __2_1_ + 1 __2_2_ = 1
c6: -1 basin_storage_(Basin_#6,__end)_ + 2 __2_2_ = 0
c7: -1 z_2 + 100 __2_2_ = 0
basin_profile_Basin_#6_: 1 basin_level_Basin_#6_ - 1 z_2 = 0
c9: 1 __3_1_ + 1 __3_2_ = 1
c10: -1 basin_storage_(Basin_#8,__end)_ + 2 __3_2_ = 0
c11: -1 z_3 + 100 __3_2_ = 0
basin_profile_Basin_#8_: 1 basin_level_Basin_#8_ - 1 z_3 = 0
c13: 1 __4_1_ + 1 __4_2_ + 1 __4_3_ = 1
c14: -1 basin_storage_(Basin_#2,__end)_ + 0.002 __4_2_ + 2 __4_3_ = 0
c15: -1 z_4 + 1 __4_2_ + 1 __4_3_ = 0
c16: 1 low_storage_factor_Basin_#2_ - 1 z_4 = 0
c17: 1 __5_1_ + 1 __5_2_ + 1 __5_3_ = 1
c18: -1 basin_storage_(Basin_#6,__end)_ + 0.002 __5_2_ + 2 __5_3_ = 0
c19: -1 z_5 + 1 __5_2_ + 1 __5_3_ = 0
c20: 1 low_storage_factor_Basin_#6_ - 1 z_5 = 0
c21: 1 __6_1_ + 1 __6_2_ + 1 __6_3_ = 1
c22: -1 basin_storage_(Basin_#8,__end)_ + 0.002 __6_2_ + 2 __6_3_ = 0
c23: -1 z_6 + 1 __6_2_ + 1 __6_3_ = 0
c24: 1 low_storage_factor_Basin_#8_ - 1 z_6 = 0
flow_conservation_pump_Pump_#5_: 1 flow_(Basin_#2,_Pump_#5)_ - 1 flow_(Pump_#5,_Basin_#6)_ = 0
flow_conservation_outlet_Outlet_#3_: 1 flow_(Basin_#2,_Outlet_#3)_ - 1 flow_(Outlet_#3,_Terminal_#4)_ = 0
flow_conservation_outlet_Outlet_#7_: 1 flow_(Basin_#6,_Outlet_#7)_ - 1 flow_(Outlet_#7,_Basin_#8)_ = 0
flow_conservation_outlet_Outlet_#13_: 1 flow_(Basin_#6,_Outlet_#13)_ - 1 flow_(Outlet_#13,_Terminal_#9)_ = 0
volume_conservation_Basin_#2_: -1 basin_storage_(Basin_#2,__start)_ + 1 basin_storage_(Basin_#2,__end)_ - 1 flow_(FlowBoundary_#1,_Basin_#2)_ + 1 flow_(Basin_#2,_Outlet_#3)_ + 1 flow_(Basin_#2,_UserDemand_#10)_ + 1 flow_(Basin_#2,_Pump_#5)_ - 1 flow_(UserDemand_#10,_Basin_#2)_ - 1 basin_forcing_Basin_#2_ = 0
volume_conservation_Basin_#6_: -1 basin_storage_(Basin_#6,__start)_ + 1 basin_storage_(Basin_#6,__end)_ - 1 flow_(Pump_#5,_Basin_#6)_ + 1 flow_(Basin_#6,_Outlet_#7)_ + 1 flow_(Basin_#6,_UserDemand_#11)_ + 1 flow_(Basin_#6,_Outlet_#13)_ - 1 flow_(UserDemand_#11,_Basin_#6)_ - 1 basin_forcing_Basin_#6_ = 0
volume_conservation_Basin_#8_: -1 basin_storage_(Basin_#8,__start)_ + 1 basin_storage_(Basin_#8,__end)_ - 1 flow_(Outlet_#7,_Basin_#8)_ + 1 flow_(Basin_#8,_UserDemand_#12)_ - 1 flow_(UserDemand_#12,_Basin_#8)_ - 1 basin_forcing_Basin_#8_ = 0
pump_constraint_Pump_#5_: -1 low_storage_factor_Basin_#2_ + 1 flow_(Basin_#2,_Pump_#5)_ = 0
outlet_constraint_Outlet_#3_: -1 low_storage_factor_Basin_#2_ + 1 flow_(Basin_#2,_Outlet_#3)_ = 0
outlet_constraint_Outlet_#7_: -1 low_storage_factor_Basin_#6_ + 1 flow_(Basin_#6,_Outlet_#7)_ = 0
outlet_constraint_Outlet_#13_: -1 low_storage_factor_Basin_#6_ + 1 flow_(Basin_#6,_Outlet_#13)_ = 0
user_demand_return_flow_UserDemand_#10_: -0.5 flow_(Basin_#2,_UserDemand_#10)_ + 1 flow_(UserDemand_#10,_Basin_#2)_ = 0
user_demand_return_flow_UserDemand_#11_: -0.5 flow_(Basin_#6,_UserDemand_#11)_ + 1 flow_(UserDemand_#11,_Basin_#6)_ = 0
user_demand_return_flow_UserDemand_#12_: -0.5 flow_(Basin_#8,_UserDemand_#12)_ + 1 flow_(UserDemand_#12,_Basin_#8)_ = 0
Bounds
0 <= basin_storage_(Basin_#2,__start)_ <= 2
0 <= basin_storage_(Basin_#6,__start)_ <= 2
0 <= basin_storage_(Basin_#8,__start)_ <= 2
0 <= basin_storage_(Basin_#2,__end)_ <= 2
0 <= basin_storage_(Basin_#6,__end)_ <= 2
0 <= basin_storage_(Basin_#8,__end)_ <= 2
0 <= basin_level_Basin_#2_ <= 100
0 <= basin_level_Basin_#6_ <= 100
0 <= basin_level_Basin_#8_ <= 100
0 <= z_1 <= 100
0 <= __1_1_ <= 1
0 <= __1_2_ <= 1
0 <= z_2 <= 100
0 <= __2_1_ <= 1
0 <= __2_2_ <= 1
0 <= z_3 <= 100
0 <= __3_1_ <= 1
0 <= __3_2_ <= 1
0 <= low_storage_factor_Basin_#2_ <= 1
0 <= low_storage_factor_Basin_#6_ <= 1
0 <= low_storage_factor_Basin_#8_ <= 1
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
0 <= flow_(FlowBoundary_#1,_Basin_#2)_ <= 8640
0 <= flow_(Basin_#2,_Outlet_#3)_ <= 0.05184
0 <= flow_(Outlet_#3,_Terminal_#4)_ <= 0.05184
0 <= flow_(Basin_#2,_UserDemand_#10)_ <= 8640
0 <= flow_(Basin_#2,_Pump_#5)_ <= 0.06912
0 <= flow_(Pump_#5,_Basin_#6)_ <= 0.06912
0 <= flow_(Basin_#6,_Outlet_#7)_ <= 0.05184
0 <= flow_(Outlet_#7,_Basin_#8)_ <= 0.05184
0 <= flow_(Basin_#6,_UserDemand_#11)_ <= 8640
0 <= flow_(Basin_#8,_UserDemand_#12)_ <= 8640
0 <= flow_(Basin_#6,_Outlet_#13)_ <= 0.05184
0 <= flow_(Outlet_#13,_Terminal_#9)_ <= 0.05184
0 <= flow_(UserDemand_#10,_Basin_#2)_ <= 8640
0 <= flow_(UserDemand_#11,_Basin_#6)_ <= 8640
0 <= flow_(UserDemand_#12,_Basin_#8)_ <= 8640
basin_forcing_Basin_#2_ = 0
basin_forcing_Basin_#6_ = 0
basin_forcing_Basin_#8_ = 0
target_fraction = 1
user_demand_allocated_UserDemand_#10_ = 0
user_demand_allocated_UserDemand_#11_ = 0
user_demand_allocated_UserDemand_#12_ = 0
relative_user_demand_error_UserDemand_#10_ >= 0
relative_user_demand_error_UserDemand_#11_ >= 0
relative_user_demand_error_UserDemand_#12_ >= 0
Binary
y_4_1_
y_5_1_
y_6_1_
End

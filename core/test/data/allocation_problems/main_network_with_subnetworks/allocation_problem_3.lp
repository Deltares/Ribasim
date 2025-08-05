minimize
obj: 
subject to
c1_2: 1 __4_3_ - 1 y_4_1_ <= 0
c2_2: 1 __5_3_ - 1 y_5_1_ <= 0
c3_2: 1 __6_3_ - 1 y_6_1_ <= 0
c1_1: 1 __4_2_ + 1 __4_3_ - 1 y_4_1_ >= 0
c2_1: 1 __5_2_ + 1 __5_3_ - 1 y_5_1_ >= 0
c3_1: 1 __6_2_ + 1 __6_3_ - 1 y_6_1_ >= 0
user_demand_constraint_lower_UserDemand_#20_: 1 flow_(Basin_#12,_UserDemand_#20)_ - 2 target_fraction - 1 user_demand_allocated_UserDemand_#20_ + 2 relative_user_demand_error_UserDemand_#20_ >= 0
user_demand_constraint_lower_UserDemand_#21_: 1 flow_(Basin_#16,_UserDemand_#21)_ - 2 target_fraction - 1 user_demand_allocated_UserDemand_#21_ + 2 relative_user_demand_error_UserDemand_#21_ >= 0
user_demand_constraint_lower_UserDemand_#22_: 1 flow_(Basin_#18,_UserDemand_#22)_ - 2 target_fraction - 1 user_demand_allocated_UserDemand_#22_ + 2 relative_user_demand_error_UserDemand_#22_ >= 0
c1: 1 __1_1_ + 1 __1_2_ = 1
c2: -1 basin_storage_(Basin_#12,__end)_ + 2 __1_2_ = 0
c3: -1 z_1 + 1 __1_2_ = 0
basin_profile_Basin_#12_: 1 basin_level_Basin_#12_ - 1 z_1 = 0
c5: 1 __2_1_ + 1 __2_2_ = 1
c6: -1 basin_storage_(Basin_#16,__end)_ + 2 __2_2_ = 0
c7: -1 z_2 + 1 __2_2_ = 0
basin_profile_Basin_#16_: 1 basin_level_Basin_#16_ - 1 z_2 = 0
c9: 1 __3_1_ + 1 __3_2_ = 1
c10: -1 basin_storage_(Basin_#18,__end)_ + 2 __3_2_ = 0
c11: -1 z_3 + 1 __3_2_ = 0
basin_profile_Basin_#18_: 1 basin_level_Basin_#18_ - 1 z_3 = 0
c13: 1 __4_1_ + 1 __4_2_ + 1 __4_3_ = 1
c14: -1 basin_storage_(Basin_#12,__end)_ + 0.2 __4_2_ + 2 __4_3_ = 0
c15: -1 z_4 + 1 __4_2_ + 1 __4_3_ = 0
c16: 1 low_storage_factor_Basin_#12_ - 1 z_4 = 0
c17: 1 __5_1_ + 1 __5_2_ + 1 __5_3_ = 1
c18: -1 basin_storage_(Basin_#16,__end)_ + 0.2 __5_2_ + 2 __5_3_ = 0
c19: -1 z_5 + 1 __5_2_ + 1 __5_3_ = 0
c20: 1 low_storage_factor_Basin_#16_ - 1 z_5 = 0
c21: 1 __6_1_ + 1 __6_2_ + 1 __6_3_ = 1
c22: -1 basin_storage_(Basin_#18,__end)_ + 0.2 __6_2_ + 2 __6_3_ = 0
c23: -1 z_6 + 1 __6_2_ + 1 __6_3_ = 0
c24: 1 low_storage_factor_Basin_#18_ - 1 z_6 = 0
flow_conservation_pump_Pump_#15_: 1 flow_(Basin_#12,_Pump_#15)_ - 1 flow_(Pump_#15,_Basin_#16)_ = 0
flow_conservation_outlet_Outlet_#13_: 1 flow_(Basin_#12,_Outlet_#13)_ - 1 flow_(Outlet_#13,_Terminal_#14)_ = 0
flow_conservation_outlet_Outlet_#17_: 1 flow_(Basin_#16,_Outlet_#17)_ - 1 flow_(Outlet_#17,_Basin_#18)_ = 0
flow_conservation_outlet_Outlet_#23_: 1 flow_(Basin_#16,_Outlet_#23)_ - 1 flow_(Outlet_#23,_Terminal_#19)_ = 0
volume_conservation_Basin_#12_: -1 basin_storage_(Basin_#12,__start)_ + 1 basin_storage_(Basin_#12,__end)_ + 1 flow_(Basin_#12,_Outlet_#13)_ + 1 flow_(Basin_#12,_UserDemand_#20)_ + 1 flow_(Basin_#12,_Pump_#15)_ - 1 flow_(UserDemand_#20,_Basin_#12)_ - 1 basin_forcing_Basin_#12_ = 0
volume_conservation_Basin_#16_: -1 basin_storage_(Basin_#16,__start)_ + 1 basin_storage_(Basin_#16,__end)_ - 1 flow_(Pump_#15,_Basin_#16)_ + 1 flow_(Basin_#16,_Outlet_#17)_ + 1 flow_(Basin_#16,_UserDemand_#21)_ + 1 flow_(Basin_#16,_Outlet_#23)_ - 1 flow_(UserDemand_#21,_Basin_#16)_ - 1 basin_forcing_Basin_#16_ = 0
volume_conservation_Basin_#18_: -1 basin_storage_(Basin_#18,__start)_ + 1 basin_storage_(Basin_#18,__end)_ - 1 flow_(Outlet_#17,_Basin_#18)_ + 1 flow_(Basin_#18,_UserDemand_#22)_ - 1 flow_(UserDemand_#22,_Basin_#18)_ - 1 basin_forcing_Basin_#18_ = 0
pump_constraint_Pump_#15_: -1 low_storage_factor_Basin_#12_ + 1 flow_(Basin_#12,_Pump_#15)_ = 0
outlet_constraint_Outlet_#13_: -1 low_storage_factor_Basin_#12_ + 1 flow_(Basin_#12,_Outlet_#13)_ = 0
outlet_constraint_Outlet_#17_: -1 low_storage_factor_Basin_#16_ + 1 flow_(Basin_#16,_Outlet_#17)_ = 0
outlet_constraint_Outlet_#23_: -1 low_storage_factor_Basin_#16_ + 1 flow_(Basin_#16,_Outlet_#23)_ = 0
user_demand_return_flow_UserDemand_#20_: -0.5 flow_(Basin_#12,_UserDemand_#20)_ + 1 flow_(UserDemand_#20,_Basin_#12)_ = 0
user_demand_return_flow_UserDemand_#21_: -0.5 flow_(Basin_#16,_UserDemand_#21)_ + 1 flow_(UserDemand_#21,_Basin_#16)_ = 0
user_demand_return_flow_UserDemand_#22_: -0.5 flow_(Basin_#18,_UserDemand_#22)_ + 1 flow_(UserDemand_#22,_Basin_#18)_ = 0
Bounds
0 <= basin_storage_(Basin_#12,__start)_ <= 2
0 <= basin_storage_(Basin_#16,__start)_ <= 2
0 <= basin_storage_(Basin_#18,__start)_ <= 2
0 <= basin_storage_(Basin_#12,__end)_ <= 2
0 <= basin_storage_(Basin_#16,__end)_ <= 2
0 <= basin_storage_(Basin_#18,__end)_ <= 2
0 <= basin_level_Basin_#12_ <= 1
0 <= basin_level_Basin_#16_ <= 1
0 <= basin_level_Basin_#18_ <= 1
0 <= z_1 <= 1
0 <= __1_1_ <= 1
0 <= __1_2_ <= 1
0 <= z_2 <= 1
0 <= __2_1_ <= 1
0 <= __2_2_ <= 1
0 <= z_3 <= 1
0 <= __3_1_ <= 1
0 <= __3_2_ <= 1
0 <= low_storage_factor_Basin_#12_ <= 1
0 <= low_storage_factor_Basin_#16_ <= 1
0 <= low_storage_factor_Basin_#18_ <= 1
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
0 <= flow_(Pump_#11,_Basin_#12)_ <= 17.28
0 <= flow_(Basin_#12,_Outlet_#13)_ <= 5.184
0 <= flow_(Outlet_#13,_Terminal_#14)_ <= 5.184
0 <= flow_(Basin_#12,_UserDemand_#20)_ <= 864000
0 <= flow_(Basin_#12,_Pump_#15)_ <= 6.912
0 <= flow_(Pump_#15,_Basin_#16)_ <= 6.912
0 <= flow_(Basin_#16,_Outlet_#17)_ <= 5.184
0 <= flow_(Outlet_#17,_Basin_#18)_ <= 5.184
0 <= flow_(Basin_#16,_UserDemand_#21)_ <= 864000
0 <= flow_(Basin_#18,_UserDemand_#22)_ <= 864000
0 <= flow_(Basin_#16,_Outlet_#23)_ <= 5.184
0 <= flow_(Outlet_#23,_Terminal_#19)_ <= 5.184
0 <= flow_(UserDemand_#20,_Basin_#12)_ <= 864000
0 <= flow_(UserDemand_#21,_Basin_#16)_ <= 864000
0 <= flow_(UserDemand_#22,_Basin_#18)_ <= 864000
basin_forcing_Basin_#12_ = 0
basin_forcing_Basin_#16_ = 0
basin_forcing_Basin_#18_ = 0
target_fraction = 1
user_demand_allocated_UserDemand_#20_ = 0
user_demand_allocated_UserDemand_#21_ = 0
user_demand_allocated_UserDemand_#22_ = 0
relative_user_demand_error_UserDemand_#20_ >= 0
relative_user_demand_error_UserDemand_#21_ >= 0
relative_user_demand_error_UserDemand_#22_ >= 0
Binary
y_4_1_
y_5_1_
y_6_1_
End

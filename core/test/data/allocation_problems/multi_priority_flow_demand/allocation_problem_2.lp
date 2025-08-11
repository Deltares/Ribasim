minimize
obj: 
subject to
c1_1: 1 __1_3_ - 1 y_1_1_ <= 0
c1: 1 __1_2_ + 1 __1_3_ - 1 y_1_1_ >= 0
user_demand_constraint_lower_UserDemand_#5_: 1 flow_(Basin_#1,_UserDemand_#5)_ - 2 target_fraction - 1 user_demand_allocated_UserDemand_#5_ + 2 relative_user_demand_error_UserDemand_#5_ >= 0
flow_demand_constraint_FlowDemand_#6_: 1 flow_(Basin_#1,_Pump_#2)_ - 2 target_fraction - 1 flow_demand_allocated_FlowDemand_#6_ + 2 relative_flow_demand_error_FlowDemand_#6_ >= 0
storage_constraint_in_Basin_#1_: 1 basin_storage_(Basin_#1,__end)_ + 1 absolute_storage_error_Basin_#1_ >= 2000
storage_constraint_out_Basin_#1_: -1 basin_storage_(Basin_#1,__end)_ + 1 absolute_storage_error_Basin_#1_ >= -3000
linear_basin_profile_Basin_#1_: 0.005 basin_storage_(Basin_#1,__start)_ - 0.005 basin_storage_(Basin_#1,__end)_ + 1 basin_level_Basin_#1_ = 1000000
c2: 1 __1_1_ + 1 __1_2_ + 1 __1_3_ = 1
c3: -1 basin_storage_(Basin_#1,__end)_ + 0.02 __1_2_ + 2 __1_3_ = 0
c4: -1 z_1 + 1 __1_2_ + 1 __1_3_ = 0
c5: 1 low_storage_factor_Basin_#1_ - 1 z_1 = 0
flow_conservation_pump_Pump_#2_: 1 flow_(Basin_#1,_Pump_#2)_ - 1 flow_(Pump_#2,_Terminal_#3)_ = 0
volume_conservation_Basin_#1_: -1 basin_storage_(Basin_#1,__start)_ + 1 basin_storage_(Basin_#1,__end)_ + 1 flow_(Basin_#1,_Pump_#2)_ - 1 flow_(FlowBoundary_#4,_Basin_#1)_ + 1 flow_(Basin_#1,_UserDemand_#5)_ - 1 flow_(UserDemand_#5,_Basin_#1)_ - 1 basin_forcing_Basin_#1_ = 0
user_demand_return_flow_UserDemand_#5_: -0.5 flow_(Basin_#1,_UserDemand_#5)_ + 1 flow_(UserDemand_#5,_Basin_#1)_ = 0
Bounds
0 <= basin_storage_(Basin_#1,__start)_ <= 2
0 <= basin_storage_(Basin_#1,__end)_ <= 2
0 <= basin_level_Basin_#1_ <= 10
0 <= low_storage_factor_Basin_#1_ <= 1
0 <= z_1 <= 1
0 <= __1_1_ <= 1
0 <= __1_2_ <= 1
0 <= __1_3_ <= 1
0 <= flow_(Basin_#1,_Pump_#2)_ <= 8640000
0 <= flow_(Pump_#2,_Terminal_#3)_ <= 8640000
0 <= flow_(FlowBoundary_#4,_Basin_#1)_ <= 8640000
0 <= flow_(Basin_#1,_UserDemand_#5)_ <= 8640000
0 <= flow_(UserDemand_#5,_Basin_#1)_ <= 8640000
basin_forcing_Basin_#1_ = 0
target_fraction = 1
user_demand_allocated_UserDemand_#5_ = 0
relative_user_demand_error_UserDemand_#5_ >= 0
flow_demand_allocated_FlowDemand_#6_ = -500000
relative_flow_demand_error_FlowDemand_#6_ >= 0
absolute_storage_error_Basin_#1_ >= 0
Binary
y_1_1_
End

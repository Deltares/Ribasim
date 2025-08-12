minimize
obj: 
subject to
c1_1: 1 __1_3_ - 1 y_1_1_ <= 0
c2_1: 1 __2_3_ - 1 y_2_1_ <= 0
c1: 1 __1_2_ + 1 __1_3_ - 1 y_1_1_ >= 0
c2: 1 __2_2_ + 1 __2_3_ - 1 y_2_1_ >= 0
flow_demand_constraint_FlowDemand_#4_: 1 flow_(Basin_#1,_LinearResistance_#2)_ - 2 target_fraction - 1 flow_demand_allocated_FlowDemand_#4_ + 2 relative_flow_demand_error_FlowDemand_#4_ >= 0
linear_basin_profile_Basin_#1_: 0.0005 basin_storage_(Basin_#1,__start)_ - 0.0005 basin_storage_(Basin_#1,__end)_ + 1 basin_level_Basin_#1_ = 1000000
linear_basin_profile_Basin_#3_: 0.0005 basin_storage_(Basin_#3,__start)_ - 0.0005 basin_storage_(Basin_#3,__end)_ + 1 basin_level_Basin_#3_ = 1000000
c3: 1 __1_1_ + 1 __1_2_ + 1 __1_3_ = 1
c4: -1 basin_storage_(Basin_#1,__end)_ + 0.2 __1_2_ + 2 __1_3_ = 0
c5: -1 z_1 + 1 __1_2_ + 1 __1_3_ = 0
c6: 1 low_storage_factor_Basin_#1_ - 1 z_1 = 0
c7: 1 __2_1_ + 1 __2_2_ + 1 __2_3_ = 1
c8: -1 basin_storage_(Basin_#3,__end)_ + 0.2 __2_2_ + 2 __2_3_ = 0
c9: -1 z_2 + 1 __2_2_ + 1 __2_3_ = 0
c10: 1 low_storage_factor_Basin_#3_ - 1 z_2 = 0
flow_conservation_linear_resistance_LinearResistance_#2_: 1 flow_(Basin_#1,_LinearResistance_#2)_ - 1 flow_(LinearResistance_#2,_Basin_#3)_ = 0
volume_conservation_Basin_#1_: -1 basin_storage_(Basin_#1,__start)_ + 1 basin_storage_(Basin_#1,__end)_ + 1 flow_(Basin_#1,_LinearResistance_#2)_ - 1 basin_forcing_Basin_#1_ = 0
volume_conservation_Basin_#3_: -1 basin_storage_(Basin_#3,__start)_ + 1 basin_storage_(Basin_#3,__end)_ - 1 flow_(LinearResistance_#2,_Basin_#3)_ - 1 basin_forcing_Basin_#3_ = 0
linear_resistance_constraint_LinearResistance_#2_: -1 basin_level_Basin_#1_ + 1 basin_level_Basin_#3_ + 1 flow_(Basin_#1,_LinearResistance_#2)_ = 1
Bounds
0 <= basin_storage_(Basin_#1,__start)_ <= 2
0 <= basin_storage_(Basin_#3,__start)_ <= 2
0 <= basin_storage_(Basin_#1,__end)_ <= 2
0 <= basin_storage_(Basin_#3,__end)_ <= 2
0 <= basin_level_Basin_#1_ <= 1
0 <= basin_level_Basin_#3_ <= 1
0 <= low_storage_factor_Basin_#1_ <= 1
0 <= low_storage_factor_Basin_#3_ <= 1
0 <= z_1 <= 1
0 <= __1_1_ <= 1
0 <= __1_2_ <= 1
0 <= __1_3_ <= 1
0 <= z_2 <= 1
0 <= __2_1_ <= 1
0 <= __2_2_ <= 1
0 <= __2_3_ <= 1
-345.6 <= flow_(Basin_#1,_LinearResistance_#2)_ <= 345.6
-345.6 <= flow_(LinearResistance_#2,_Basin_#3)_ <= 345.6
basin_forcing_Basin_#1_ = 0
basin_forcing_Basin_#3_ = 0
target_fraction = 1
flow_demand_allocated_FlowDemand_#4_ = -500000
relative_flow_demand_error_FlowDemand_#4_ >= 0
Binary
y_1_1_
y_2_1_
End

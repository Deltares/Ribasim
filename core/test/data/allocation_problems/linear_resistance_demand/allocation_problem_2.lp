minimize
obj: 
subject to
c1_2: 1 __1_3_ - 1 y_1_1_ <= 0
c2_2: 1 __2_3_ - 1 y_2_1_ <= 0
c1_1: 1 __1_2_ + 1 __1_3_ - 1 y_1_1_ >= 0
c2_1: 1 __2_2_ + 1 __2_3_ - 1 y_2_1_ >= 0
flow_demand_constraint_LinearResistance_#2_: 1 flow_(Basin_#1,_LinearResistance_#2)_ - 2 target_fraction - 1 flow_demand_allocated_LinearResistance_#2_ + 2 relative_flow_demand_error_LinearResistance_#2_ >= 0
flow_demand_goal_LinearResistance_#2_: 1 flow_(Basin_#1,_LinearResistance_#2)_ - 1 flow_demand_allocated_LinearResistance_#2_ >= 0
c1: 1 __1_1_ + 1 __1_2_ + 1 __1_3_ = 1
c2: -1 basin_storage_(Basin_#1,__end)_ + 0.2 __1_2_ + 2 __1_3_ = 0
c3: -1 z_1 + 1 __1_2_ + 1 __1_3_ = 0
c4: 1 low_storage_factor_Basin_#1_ - 1 z_1 = 0
c5: 1 __2_1_ + 1 __2_2_ + 1 __2_3_ = 1
c6: -1 basin_storage_(Basin_#3,__end)_ + 0.2 __2_2_ + 2 __2_3_ = 0
c7: -1 z_2 + 1 __2_2_ + 1 __2_3_ = 0
c8: 1 low_storage_factor_Basin_#3_ - 1 z_2 = 0
flow_conservation_linearresistance_LinearResistance_#2_: 1 flow_(Basin_#1,_LinearResistance_#2)_ - 1 flow_(LinearResistance_#2,_Basin_#3)_ = 0
volume_conservation_Basin_#1_: -1 basin_storage_(Basin_#1,__start)_ + 1 basin_storage_(Basin_#1,__end)_ + 1 flow_(Basin_#1,_LinearResistance_#2)_ - 1 basin_forcing_Basin_#1_ = 0
volume_conservation_Basin_#3_: -1 basin_storage_(Basin_#3,__start)_ + 1 basin_storage_(Basin_#3,__end)_ - 1 flow_(LinearResistance_#2,_Basin_#3)_ - 1 basin_forcing_Basin_#3_ = 0
linear_resistance_constraint_LinearResistance_#2_: -1 basin_storage_(Basin_#1,__end)_ + 1 basin_storage_(Basin_#3,__end)_ + 1 flow_(Basin_#1,_LinearResistance_#2)_ = 1
Bounds
0 <= basin_storage_(Basin_#1,__start)_ <= 2
0 <= basin_storage_(Basin_#3,__start)_ <= 2
0 <= basin_storage_(Basin_#1,__end)_ <= 2
0 <= basin_storage_(Basin_#3,__end)_ <= 2
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
flow_demand_allocated_LinearResistance_#2_ = -500000
relative_flow_demand_error_LinearResistance_#2_ >= 0
Binary
y_1_1_
y_2_1_
End

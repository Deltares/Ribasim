minimize
obj: 
subject to
c1_1: 1 __1_3_ - 1 y_1_1_ <= 0
c1: 1 __1_2_ + 1 __1_3_ - 1 y_1_1_ >= 0
storage_constraint_in_Basin_#1_: 1 basin_storage_(Basin_#1,__end)_ + 1 absolute_storage_error_Basin_#1_ >= 2000
storage_constraint_out_Basin_#1_: -1 basin_storage_(Basin_#1,__end)_ + 1 absolute_storage_error_Basin_#1_ >= -3000
linear_basin_profile_Basin_#1_: 0.0006 basin_storage_(Basin_#1,__start)_ - 0.0006 basin_storage_(Basin_#1,__end)_ + 1 basin_level_Basin_#1_ = 1000000
c2: 1 __1_1_ + 1 __1_2_ + 1 __1_3_ = 1
c3: -1 basin_storage_(Basin_#1,__end)_ + 0.016666666666666666 __1_2_ + 2 __1_3_ = 0
c4: -1 z_1 + 1 __1_2_ + 1 __1_3_ = 0
c5: 1 low_storage_factor_Basin_#1_ - 1 z_1 = 0
flow_conservation_outlet_Outlet_#2_: 1 flow_(Basin_#1,_Outlet_#2)_ - 1 flow_(Outlet_#2,_Terminal_#3)_ = 0
volume_conservation_Basin_#1_: -1 basin_storage_(Basin_#1,__start)_ + 1 basin_storage_(Basin_#1,__end)_ + 1 flow_(Basin_#1,_Outlet_#2)_ - 1 basin_forcing_Basin_#1_ = 0
Bounds
0 <= basin_storage_(Basin_#1,__start)_ <= 4
0 <= basin_storage_(Basin_#1,__end)_ <= 4
0 <= basin_level_Basin_#1_ <= 12
0 <= low_storage_factor_Basin_#1_ <= 1
0 <= z_1 <= 1
0 <= __1_1_ <= 1
0 <= __1_2_ <= 1
0 <= __1_3_ <= 1
0 <= flow_(Basin_#1,_Outlet_#2)_ <= 0.14400000000000002
0 <= flow_(Outlet_#2,_Terminal_#3)_ <= 0.14400000000000002
basin_forcing_Basin_#1_ = 0
target_fraction = 1
absolute_storage_error_Basin_#1_ >= 0
Binary
y_1_1_
End

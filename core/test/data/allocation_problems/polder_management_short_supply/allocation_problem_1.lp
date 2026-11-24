minimize
obj: 1 flow_change_Pump_#7_ + 1.0025 flow_change_Outlet_#5_ + 1.005 flow_change_Outlet_#10_ + 1.0075 flow_change_Outlet_#12_ + 1.01 flow_change_Outlet_#13_
subject to
c1: -1 low_storage_factor_Basin_#3_ - 1 low_storage_factor_Basin_#4_ - 1 low_storage_factor_Basin_#6_ - 1 low_storage_factor_Basin_#9_ <= -4
c2: 1 level_demand_error_Basin_#4,1,lower,first_ + 1 level_demand_error_Basin_#4,1,upper,first_ + 1 level_demand_error_Basin_#6,1,lower,first_ + 1 level_demand_error_Basin_#6,1,upper,first_ <= 0
c3: 1 level_demand_error_Basin_#4,1,lower,second_ + 1 level_demand_error_Basin_#4,1,upper,second_ + 1 level_demand_error_Basin_#6,1,lower,second_ + 1 level_demand_error_Basin_#6,1,upper,second_ <= 0
c4: 1 level_demand_error_Basin_#3,3,lower,first_ + 1 level_demand_error_Basin_#3,3,upper,first_ <= 0
c5: 1 level_demand_error_Basin_#3,3,lower,second_ + 1 level_demand_error_Basin_#3,3,upper,second_ <= 0
c6: 40 flow_(Outlet_#5,_Basin_#4)_ + 40 flow_(Outlet_#13,_Basin_#6)_ + 50 flow_(Pump_#7,_Basin_#9)_ + 1000 flow_(LevelBoundary_#11,_Outlet_#12)_ + 40 flow_(Outlet_#12,_Basin_#3)_ + 40 flow_(Outlet_#10,_LevelBoundary_#17)_ <= 1.5134977800546232
flow_demand_relative_error_constraint_Pump_#7,2_: 1 flow_demand_allocated_Pump_#7,2_ >= 0
storage_constraint_lower_Basin_#3,3_: 1 basin_storage_change_Basin_#3_ + 1 level_demand_error_Basin_#3,3,lower,first_ >= -0.015564051023567557
storage_constraint_lower_Basin_#4,1_: 1 basin_storage_change_Basin_#4_ + 1 level_demand_error_Basin_#4,1,lower,first_ >= 0
storage_constraint_lower_Basin_#6,1_: 1 basin_storage_change_Basin_#6_ + 1 level_demand_error_Basin_#6,1,lower,first_ >= 0
storage_constraint_upper_Basin_#3,3_: -1 basin_storage_change_Basin_#3_ + 1 level_demand_error_Basin_#3,3,upper,first_ >= 0
storage_constraint_upper_Basin_#4,1_: -1 basin_storage_change_Basin_#4_ + 1 level_demand_error_Basin_#4,1,upper,first_ >= 0
storage_constraint_upper_Basin_#6,1_: -1 basin_storage_change_Basin_#6_ + 1 level_demand_error_Basin_#6,1,upper,first_ >= 0
flow_demand_fairness_error_constraint_Pump_#7,2_: -1 flow_demand_error_Pump_#7,2,first_ + 1 flow_demand_error_Pump_#7,2,second_ + 1 average_flow_unit_error_2_ >= 0
level_demand_fairness_error_constraint_Basin_#3,3,lower_: -1 level_demand_error_Basin_#3,3,lower,first_ + 1 level_demand_error_Basin_#3,3,lower,second_ + 1 average_storage_unit_error_3,lower_ >= 0
level_demand_fairness_error_constraint_Basin_#3,3,upper_: -1 level_demand_error_Basin_#3,3,upper,first_ + 1 level_demand_error_Basin_#3,3,upper,second_ + 1 average_storage_unit_error_3,upper_ >= 0
level_demand_fairness_error_constraint_Basin_#4,1,lower_: -0.9954545455 level_demand_error_Basin_#4,1,lower,first_ + 1 level_demand_error_Basin_#4,1,lower,second_ + 1 average_storage_unit_error_1,lower_ >= 0
level_demand_fairness_error_constraint_Basin_#4,1,upper_: -0.9954545455 level_demand_error_Basin_#4,1,upper,first_ + 1 level_demand_error_Basin_#4,1,upper,second_ + 1 average_storage_unit_error_1,upper_ >= 0
level_demand_fairness_error_constraint_Basin_#6,1,lower_: -1.0045871559170103 level_demand_error_Basin_#6,1,lower,first_ + 1 level_demand_error_Basin_#6,1,lower,second_ + 1 average_storage_unit_error_1,lower_ >= 0
level_demand_fairness_error_constraint_Basin_#6,1,upper_: -1.0045871559170103 level_demand_error_Basin_#6,1,upper,first_ + 1 level_demand_error_Basin_#6,1,upper,second_ + 1 average_storage_unit_error_1,upper_ >= 0
flow_change_constraint_Pump_#7,_1_: 1 flow_(Basin_#6,_Pump_#7)_ + 1 flow_change_Pump_#7_ >= 0.010085505063271777
flow_change_constraint_Outlet_#5,_1_: 1 flow_(Basin_#3,_Outlet_#5)_ + 1 flow_change_Outlet_#5_ >= 0
flow_change_constraint_Outlet_#10,_1_: 1 flow_(Basin_#9,_Outlet_#10)_ + 1 flow_change_Outlet_#10_ >= 0.0028732691366891196
flow_change_constraint_Outlet_#12,_1_: 1 flow_(LevelBoundary_#11,_Outlet_#12)_ + 1 flow_change_Outlet_#12_ >= 0
flow_change_constraint_Outlet_#13,_1_: 1 flow_(Basin_#4,_Outlet_#13)_ + 1 flow_change_Outlet_#13_ >= 0.005042752531635888
flow_change_constraint_Pump_#7,1_: -1 flow_(Basin_#6,_Pump_#7)_ + 1 flow_change_Pump_#7_ >= -0.010085505063271777
flow_change_constraint_Outlet_#5,1_: -1 flow_(Basin_#3,_Outlet_#5)_ + 1 flow_change_Outlet_#5_ >= 0
flow_change_constraint_Outlet_#10,1_: -1 flow_(Basin_#9,_Outlet_#10)_ + 1 flow_change_Outlet_#10_ >= -0.0028732691366891196
flow_change_constraint_Outlet_#12,1_: -1 flow_(LevelBoundary_#11,_Outlet_#12)_ + 1 flow_change_Outlet_#12_ >= 0
flow_change_constraint_Outlet_#13,1_: -1 flow_(Basin_#4,_Outlet_#13)_ + 1 flow_change_Outlet_#13_ >= -0.005042752531635888
flow_conservation_pump_Pump_#7_: 1 flow_(Basin_#6,_Pump_#7)_ - 1 flow_(Pump_#7,_Basin_#9)_ = 0
flow_conservation_outlet_Outlet_#5_: 1 flow_(Basin_#3,_Outlet_#5)_ - 1 flow_(Outlet_#5,_Basin_#4)_ = 0
flow_conservation_outlet_Outlet_#10_: 1 flow_(Basin_#9,_Outlet_#10)_ - 1 flow_(Outlet_#10,_LevelBoundary_#17)_ = 0
flow_conservation_outlet_Outlet_#12_: 1 flow_(LevelBoundary_#11,_Outlet_#12)_ - 1 flow_(Outlet_#12,_Basin_#3)_ = 0
flow_conservation_outlet_Outlet_#13_: 1 flow_(Basin_#4,_Outlet_#13)_ - 1 flow_(Outlet_#13,_Basin_#6)_ = 0
flow_conservation_manning_resistance_ManningResistance_#2_: -1 flow_(ManningResistance_#2,_Basin_#9)_ + 1 flow_(Basin_#3,_ManningResistance_#2)_ = 0
volume_conservation_Basin_#3_: 1 basin_storage_change_Basin_#3_ + 1 flow_(Basin_#3,_Outlet_#5)_ + 1 flow_(Basin_#3,_ManningResistance_#2)_ - 1 flow_(Outlet_#12,_Basin_#3)_ = 0.005042752531635888
volume_conservation_Basin_#4_: 1 basin_storage_change_Basin_#4_ - 1 flow_(Outlet_#5,_Basin_#4)_ + 1 flow_(Basin_#4,_Outlet_#13)_ = 0.005042752531635888
volume_conservation_Basin_#6_: 1 basin_storage_change_Basin_#6_ - 1 flow_(Outlet_#13,_Basin_#6)_ + 1 flow_(Basin_#6,_Pump_#7)_ = 0.005042752531635888
volume_conservation_Basin_#9_: 1 basin_storage_change_Basin_#9_ - 1 flow_(ManningResistance_#2,_Basin_#9)_ - 1 flow_(Pump_#7,_Basin_#9)_ + 1 flow_(Basin_#9,_Outlet_#10)_ = 0.005042752531635888
manning_resistance_constraint_ManningResistance_#2_: -513.3232658624439 basin_storage_change_Basin_#3_ + 513.3283113346056 basin_storage_change_Basin_#9_ + 0.003581426999031634 low_storage_factor_Basin_#9_ + 1 flow_(Basin_#3,_ManningResistance_#2)_ = 0
flow_demand_allocated_sum_constraint_Pump_#7_: 1 flow_(Basin_#6,_Pump_#7)_ - 1 flow_demand_allocated_Pump_#7,2_ - 1 flow_demand_extra_Pump_#7_ = 0
average_flow_unit_error_constraint_2_: 1 average_flow_unit_error_2_ = 0
average_storage_unit_error_constraint_1,upper_: -1 level_demand_error_Basin_#4,1,upper,first_ - 1 level_demand_error_Basin_#6,1,upper,first_ + 2 average_storage_unit_error_1,upper_ = 0
average_storage_unit_error_constraint_3,upper_: -1 level_demand_error_Basin_#3,3,upper,first_ + 1 average_storage_unit_error_3,upper_ = 0
average_storage_unit_error_constraint_1,lower_: -1 level_demand_error_Basin_#4,1,lower,first_ - 1 level_demand_error_Basin_#6,1,lower,first_ + 2 average_storage_unit_error_1,lower_ = 0
average_storage_unit_error_constraint_3,lower_: -1 level_demand_error_Basin_#3,3,lower,first_ + 1 average_storage_unit_error_3,lower_ = 0
Bounds
basin_storage_change_Basin_#3_ >= -0.8949329424153626
basin_storage_change_Basin_#4_ >= -0.8560228148564437
basin_storage_change_Basin_#6_ >= -0.8405295095186396
basin_storage_change_Basin_#9_ >= -0.8949399192545066
0 <= low_storage_factor_Basin_#3_ <= 1
0 <= low_storage_factor_Basin_#4_ <= 1
0 <= low_storage_factor_Basin_#6_ <= 1
0 <= low_storage_factor_Basin_#9_ <= 1
flow_(ManningResistance_#2,_Basin_#9)_ free
0 <= flow_(Basin_#3,_Outlet_#5)_ <= 0.025213762658179442
flow_(Basin_#3,_ManningResistance_#2)_ free
0 <= flow_(Outlet_#5,_Basin_#4)_ <= 0.025213762658179442
0 <= flow_(Basin_#4,_Outlet_#13)_ <= 0.025213762658179442
0 <= flow_(Outlet_#13,_Basin_#6)_ <= 0.025213762658179442
0 <= flow_(Basin_#6,_Pump_#7)_ <= 0.10085505063271777
0 <= flow_(Pump_#7,_Basin_#9)_ <= 0.10085505063271777
0 <= flow_(Basin_#9,_Outlet_#10)_ <= 0.050427525316358884
0 <= flow_(LevelBoundary_#11,_Outlet_#12)_ <= 0.010085505063271777
0 <= flow_(Outlet_#12,_Basin_#3)_ <= 0.010085505063271777
0 <= flow_(Outlet_#10,_LevelBoundary_#17)_ <= 0.050427525316358884
flow_demand_allocated_Pump_#7,2_ = 0
0 <= flow_demand_extra_Pump_#7_ <= 0.10085505063271777
0 <= flow_demand_error_Pump_#7,2,first_ <= 1
0 <= flow_demand_error_Pump_#7,2,second_ <= 1
level_demand_error_Basin_#3,3,lower,first_ >= 0
level_demand_error_Basin_#3,3,lower,second_ >= 0
level_demand_error_Basin_#3,3,upper,first_ >= 0
level_demand_error_Basin_#3,3,upper,second_ >= 0
level_demand_error_Basin_#4,1,lower,first_ >= 0
level_demand_error_Basin_#4,1,lower,second_ >= 0
level_demand_error_Basin_#4,1,upper,first_ >= 0
level_demand_error_Basin_#4,1,upper,second_ >= 0
level_demand_error_Basin_#6,1,lower,first_ >= 0
level_demand_error_Basin_#6,1,lower,second_ >= 0
level_demand_error_Basin_#6,1,upper,first_ >= 0
level_demand_error_Basin_#6,1,upper,second_ >= 0
0 <= average_flow_unit_error_2_ <= 1
average_storage_unit_error_1,lower_ >= 0
average_storage_unit_error_3,lower_ >= 0
average_storage_unit_error_1,upper_ >= 0
average_storage_unit_error_3,upper_ >= 0
flow_change_Pump_#7_ >= 0
flow_change_Outlet_#5_ >= 0
flow_change_Outlet_#10_ >= 0
flow_change_Outlet_#12_ >= 0
flow_change_Outlet_#13_ >= 0
End

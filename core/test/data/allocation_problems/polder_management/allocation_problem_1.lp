minimize
obj: 40 flow_(Outlet_#5,_Basin_#4)_ + 50 flow_(Pump_#7,_Basin_#9)_ + 40 flow_(Outlet_#10,_LevelBoundary_#17)_ + 1000 flow_(LevelBoundary_#11,_Outlet_#12)_ + 40 flow_(Outlet_#12,_Basin_#3)_ + 40 flow_(Outlet_#13,_Basin_#6)_
subject to
c1: 1 level_demand_error_Basin_#3,1,lower,first_ + 1 level_demand_error_Basin_#3,1,upper,first_ + 1 level_demand_error_Basin_#4,1,lower,first_ + 1 level_demand_error_Basin_#4,1,upper,first_ + 1 level_demand_error_Basin_#6,1,lower,first_ + 1 level_demand_error_Basin_#6,1,upper,first_ <= 0
c2: 1 level_demand_error_Basin_#3,1,lower,second_ + 1 level_demand_error_Basin_#3,1,upper,second_ + 1 level_demand_error_Basin_#4,1,lower,second_ + 1 level_demand_error_Basin_#4,1,upper,second_ + 1 level_demand_error_Basin_#6,1,lower,second_ + 1 level_demand_error_Basin_#6,1,upper,second_ <= 0
c3: -1 low_storage_factor_Basin_#3_ - 1 low_storage_factor_Basin_#4_ - 1 low_storage_factor_Basin_#6_ - 1 low_storage_factor_Basin_#9_ <= -4
flow_demand_relative_error_constraint_Pump_#7,2_: 1 flow_demand_allocated_Pump_#7,2_ >= 0
storage_constraint_lower_Basin_#3,1_: 1 basin_storage_change_Basin_#3_ + 1 level_demand_error_Basin_#3,1,lower,first_ >= 2.1778476532988364e-11
storage_constraint_lower_Basin_#4,1_: 1 basin_storage_change_Basin_#4_ + 1 level_demand_error_Basin_#4,1,lower,first_ >= -8.714062925825932e-16
storage_constraint_lower_Basin_#6,1_: 1 basin_storage_change_Basin_#6_ + 1 level_demand_error_Basin_#6,1,lower,first_ >= 1.4523438209709888e-16
storage_constraint_upper_Basin_#3,1_: -1 basin_storage_change_Basin_#3_ + 1 level_demand_error_Basin_#3,1,upper,first_ >= -2.1778476532988364e-11
storage_constraint_upper_Basin_#4,1_: -1 basin_storage_change_Basin_#4_ + 1 level_demand_error_Basin_#4,1,upper,first_ >= 8.714062925825932e-16
storage_constraint_upper_Basin_#6,1_: -1 basin_storage_change_Basin_#6_ + 1 level_demand_error_Basin_#6,1,upper,first_ >= -1.4523438209709888e-16
flow_demand_fairness_error_constraint_Pump_#7,2_: -1 flow_demand_error_Pump_#7,2,first_ + 1 flow_demand_error_Pump_#7,2,second_ + 1 average_flow_unit_error_2_ >= 0
level_demand_fairness_error_constraint_Basin_#3,1,lower_: -0.996969697 level_demand_error_Basin_#3,1,lower,first_ + 1 level_demand_error_Basin_#3,1,lower,second_ + 1 average_storage_unit_error_1,lower_ >= 0
level_demand_fairness_error_constraint_Basin_#3,1,upper_: -0.996969697 level_demand_error_Basin_#3,1,upper,first_ + 1 level_demand_error_Basin_#3,1,upper,second_ + 1 average_storage_unit_error_1,upper_ >= 0
level_demand_fairness_error_constraint_Basin_#4,1,lower_: -0.996969697 level_demand_error_Basin_#4,1,lower,first_ + 1 level_demand_error_Basin_#4,1,lower,second_ + 1 average_storage_unit_error_1,lower_ >= 0
level_demand_fairness_error_constraint_Basin_#4,1,upper_: -0.996969697 level_demand_error_Basin_#4,1,upper,first_ + 1 level_demand_error_Basin_#4,1,upper,second_ + 1 average_storage_unit_error_1,upper_ >= 0
level_demand_fairness_error_constraint_Basin_#6,1,lower_: -1.006116207889347 level_demand_error_Basin_#6,1,lower,first_ + 1 level_demand_error_Basin_#6,1,lower,second_ + 1 average_storage_unit_error_1,lower_ >= 0
level_demand_fairness_error_constraint_Basin_#6,1,upper_: -1.006116207889347 level_demand_error_Basin_#6,1,upper,first_ + 1 level_demand_error_Basin_#6,1,upper,second_ + 1 average_storage_unit_error_1,upper_ >= 0
flow_conservation_pump_Pump_#7_: 1 flow_(Basin_#6,_Pump_#7)_ - 1 flow_(Pump_#7,_Basin_#9)_ = 0
flow_conservation_outlet_Outlet_#5_: 1 flow_(Basin_#3,_Outlet_#5)_ - 1 flow_(Outlet_#5,_Basin_#4)_ = 0
flow_conservation_outlet_Outlet_#10_: 1 flow_(Basin_#9,_Outlet_#10)_ - 1 flow_(Outlet_#10,_LevelBoundary_#17)_ = 0
flow_conservation_outlet_Outlet_#12_: 1 flow_(LevelBoundary_#11,_Outlet_#12)_ - 1 flow_(Outlet_#12,_Basin_#3)_ = 0
flow_conservation_outlet_Outlet_#13_: 1 flow_(Basin_#4,_Outlet_#13)_ - 1 flow_(Outlet_#13,_Basin_#6)_ = 0
flow_conservation_manning_resistance_ManningResistance_#2_: -1 flow_(ManningResistance_#2,_Basin_#9)_ + 1 flow_(Basin_#3,_ManningResistance_#2)_ = 0
volume_conservation_Basin_#3_: 1 basin_storage_change_Basin_#3_ + 0.9999999999999999 flow_(Basin_#3,_Outlet_#5)_ + 0.9999999999999999 flow_(Basin_#3,_ManningResistance_#2)_ - 0.9999999999999999 flow_(Outlet_#12,_Basin_#3)_ = 0.004602752193094901
volume_conservation_Basin_#4_: 1 basin_storage_change_Basin_#4_ - 0.9999999999999999 flow_(Outlet_#5,_Basin_#4)_ + 0.9999999999999999 flow_(Basin_#4,_Outlet_#13)_ = 0.004602752193094901
volume_conservation_Basin_#6_: 1 basin_storage_change_Basin_#6_ - 0.9999999999999999 flow_(Outlet_#13,_Basin_#6)_ + 0.9999999999999999 flow_(Basin_#6,_Pump_#7)_ = 0.004602752193094901
volume_conservation_Basin_#9_: 1 basin_storage_change_Basin_#9_ - 0.9999999999999999 flow_(ManningResistance_#2,_Basin_#9)_ - 0.9999999999999999 flow_(Pump_#7,_Basin_#9)_ + 0.9999999999999999 flow_(Basin_#9,_Outlet_#10)_ = 0.004602752193094901
manning_resistance_constraint_ManningResistance_#2_: -462.514376928252 basin_storage_change_Basin_#3_ + 462.5078776197652 basin_storage_change_Basin_#9_ - 0.004602829204778008 low_storage_factor_Basin_#3_ + 1 flow_(Basin_#3,_ManningResistance_#2)_ = 0
flow_demand_allocated_sum_constraint_Pump_#7_: 1 flow_(Basin_#6,_Pump_#7)_ - 1 flow_demand_allocated_Pump_#7,2_ - 1 flow_demand_extra_Pump_#7_ = 0
average_flow_unit_error_constraint_2_: 1 average_flow_unit_error_2_ = 0
average_storage_unit_error_constraint_1,upper_: -1 level_demand_error_Basin_#3,1,upper,first_ - 1 level_demand_error_Basin_#4,1,upper,first_ - 1 level_demand_error_Basin_#6,1,upper,first_ + 3 average_storage_unit_error_1,upper_ = 0
average_storage_unit_error_constraint_1,lower_: -1 level_demand_error_Basin_#3,1,lower,first_ - 1 level_demand_error_Basin_#4,1,lower,first_ - 1 level_demand_error_Basin_#6,1,lower,first_ + 3 average_storage_unit_error_1,lower_ = 0
Bounds
-0.8888821214957299 <= basin_storage_change_Basin_#3_ <= 1.372309227017755
-0.8576932754494189 <= basin_storage_change_Basin_#4_ <= 1.403498073064066
-0.8421697361557279 <= basin_storage_change_Basin_#6_ <= 1.4190216123577573
-0.8888721698721538 <= basin_storage_change_Basin_#9_ <= 1.3723191786413313
0 <= low_storage_factor_Basin_#3_ <= 1
0 <= low_storage_factor_Basin_#4_ <= 1
0 <= low_storage_factor_Basin_#6_ <= 1
0 <= low_storage_factor_Basin_#9_ <= 1
-1045.824588487357 <= flow_(ManningResistance_#2,_Basin_#9)_ <= 1045.827730679058
0 <= flow_(Basin_#3,_Outlet_#5)_ <= 0.023013760965474504
-1045.824588487357 <= flow_(Basin_#3,_ManningResistance_#2)_ <= 1045.827730679058
0 <= flow_(Outlet_#5,_Basin_#4)_ <= 0.023013760965474504
0 <= flow_(Basin_#4,_Outlet_#13)_ <= 0.023013760965474504
0 <= flow_(Outlet_#13,_Basin_#6)_ <= 0.023013760965474504
0 <= flow_(Basin_#6,_Pump_#7)_ <= 0.09205504386189801
0 <= flow_(Pump_#7,_Basin_#9)_ <= 0.09205504386189801
0 <= flow_(Basin_#9,_Outlet_#10)_ <= 0.04602752193094901
0 <= flow_(LevelBoundary_#11,_Outlet_#12)_ <= 0.04602752193094901
0 <= flow_(Outlet_#12,_Basin_#3)_ <= 0.04602752193094901
0 <= flow_(Outlet_#10,_LevelBoundary_#17)_ <= 0.04602752193094901
boundary_level_LevelBoundary_#11_ = 10
boundary_level_LevelBoundary_#17_ = 0.9
flow_demand_allocated_Pump_#7,2_ = 0
0 <= flow_demand_extra_Pump_#7_ <= 0.09205504386189801
0 <= flow_demand_error_Pump_#7,2,first_ <= 1
0 <= flow_demand_error_Pump_#7,2,second_ <= 1
level_demand_error_Basin_#3,1,lower,first_ >= 0
level_demand_error_Basin_#3,1,lower,second_ >= 0
level_demand_error_Basin_#3,1,upper,first_ >= 0
level_demand_error_Basin_#3,1,upper,second_ >= 0
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
average_storage_unit_error_1,upper_ >= 0
End

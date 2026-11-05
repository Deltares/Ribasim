minimize
obj: 40 flow_(Outlet_#2,_Basin_#3)_ + 50 flow_(Pump_#6,_Basin_#7)_
subject to
c1: -1 low_storage_factor_Basin_#1_ - 1 low_storage_factor_Basin_#3_ - 1 low_storage_factor_Basin_#7_ <= -3
c2: 0.5 user_demand_error_UserDemand_#4,1,first_ + 0.5 user_demand_error_UserDemand_#8,1,first_ <= 0
c3: 1 user_demand_error_UserDemand_#4,1,second_ + 1 user_demand_error_UserDemand_#8,1,second_ <= 0
user_demand_relative_error_constraint_UserDemand_#4,1_: 1 user_demand_allocated_UserDemand_#4,1_ + 0.00550833049982999 user_demand_error_UserDemand_#4,1,first_ >= 0.00550833049982999
user_demand_relative_error_constraint_UserDemand_#8,1_: 1 user_demand_allocated_UserDemand_#8,1_ + 0.00550833049982999 user_demand_error_UserDemand_#8,1,first_ >= 0.00550833049982999
user_demand_fairness_error_constraint_UserDemand_#4,1_: -1 user_demand_error_UserDemand_#4,1,first_ + 1 user_demand_error_UserDemand_#4,1,second_ + 1 average_flow_unit_error_1_ >= 0
user_demand_fairness_error_constraint_UserDemand_#8,1_: -1 user_demand_error_UserDemand_#8,1,first_ + 1 user_demand_error_UserDemand_#8,1,second_ + 1 average_flow_unit_error_1_ >= 0
flow_conservation_pump_Pump_#6_: 1 flow_(Basin_#1,_Pump_#6)_ - 1 flow_(Pump_#6,_Basin_#7)_ = 0
flow_conservation_outlet_Outlet_#2_: 1 flow_(Basin_#1,_Outlet_#2)_ - 1 flow_(Outlet_#2,_Basin_#3)_ = 0
volume_conservation_Basin_#1_: 1 basin_storage_change_Basin_#1_ + 1 flow_(Basin_#1,_Outlet_#2)_ + 1 flow_(Basin_#1,_Pump_#6)_ = 0
volume_conservation_Basin_#3_: 1 basin_storage_change_Basin_#3_ - 1 flow_(Outlet_#2,_Basin_#3)_ + 1 flow_(Basin_#3,_UserDemand_#4)_ = 0
volume_conservation_Basin_#7_: 1 basin_storage_change_Basin_#7_ - 1 flow_(Pump_#6,_Basin_#7)_ + 1 flow_(Basin_#7,_UserDemand_#8)_ = 0
user_demand_allocated_sum_constraint_UserDemand_#4_: 1 flow_(Basin_#3,_UserDemand_#4)_ - 1 user_demand_allocated_UserDemand_#4,1_ = 0
user_demand_allocated_sum_constraint_UserDemand_#8_: 1 flow_(Basin_#7,_UserDemand_#8)_ - 1 user_demand_allocated_UserDemand_#8,1_ = 0
user_demand_return_flow_UserDemand_#4_: 1 flow_(UserDemand_#4,_Terminal_#5)_ = 0
user_demand_return_flow_UserDemand_#8_: 1 flow_(UserDemand_#8,_Terminal_#5)_ = 0
average_flow_unit_error_constraint_1_: -0.5 user_demand_error_UserDemand_#4,1,first_ - 0.5 user_demand_error_UserDemand_#8,1,first_ + 1 average_flow_unit_error_1_ = 0
Bounds
basin_storage_change_Basin_#1_ >= -3.398843930635838
basin_storage_change_Basin_#3_ >= 0
basin_storage_change_Basin_#7_ >= 0
0 <= low_storage_factor_Basin_#1_ <= 1
0 <= low_storage_factor_Basin_#3_ <= 1
0 <= low_storage_factor_Basin_#7_ <= 1
0 <= flow_(Basin_#1,_Outlet_#2)_ <= 0.0550833049982999
0 <= flow_(Outlet_#2,_Basin_#3)_ <= 0.0550833049982999
0 <= flow_(Basin_#3,_UserDemand_#4)_ <= 0.00550833049982999
0 <= flow_(UserDemand_#4,_Terminal_#5)_ <= 0.00550833049982999
0 <= flow_(Basin_#1,_Pump_#6)_ <= 0.0550833049982999
0 <= flow_(Pump_#6,_Basin_#7)_ <= 0.0550833049982999
0 <= flow_(Basin_#7,_UserDemand_#8)_ <= 0.00550833049982999
0 <= flow_(UserDemand_#8,_Terminal_#5)_ <= 0.00550833049982999
0 <= user_demand_allocated_UserDemand_#4,1_ <= 0.00550833049982999
0 <= user_demand_allocated_UserDemand_#8,1_ <= 0.00550833049982999
0 <= user_demand_error_UserDemand_#4,1,first_ <= 1
0 <= user_demand_error_UserDemand_#4,1,second_ <= 1
0 <= user_demand_error_UserDemand_#8,1,first_ <= 1
0 <= user_demand_error_UserDemand_#8,1,second_ <= 1
0 <= average_flow_unit_error_1_ <= 1
End

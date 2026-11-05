minimize
obj: 50 flow_(Pump_#5,_Terminal_#6)_ + 50 flow_(Pump_#8,_Terminal_#6)_ + 20 flow_(LinearResistance_#10,_Basin_#1)_
subject to
c1: -1 low_storage_factor_Basin_#1_ - 1 low_storage_factor_Basin_#11_ <= -2
c2: 1 user_demand_error_UserDemand_#9,1,first_ <= 0
c3: 1 user_demand_error_UserDemand_#9,1,second_ <= 0
user_demand_relative_error_constraint_UserDemand_#9,1_: 1 user_demand_allocated_UserDemand_#9,1_ + 2.4452331914745887e-5 user_demand_error_UserDemand_#9,1,first_ >= 2.4452331914745887e-5
user_demand_fairness_error_constraint_UserDemand_#9,1_: -1 user_demand_error_UserDemand_#9,1,first_ + 1 user_demand_error_UserDemand_#9,1,second_ + 1 average_flow_unit_error_1_ >= 0
flow_conservation_pump_Pump_#5_: -1 flow_(Pump_#5,_Terminal_#6)_ + 1 flow_(Basin_#1,_Pump_#5)_ = 0
flow_conservation_pump_Pump_#8_: -1 flow_(Pump_#8,_Terminal_#6)_ + 1 flow_(Basin_#1,_Pump_#8)_ = 0
flow_conservation_linear_resistance_LinearResistance_#10_: 1 flow_(Basin_#11,_LinearResistance_#10)_ - 1 flow_(LinearResistance_#10,_Basin_#1)_ = 0
volume_conservation_Basin_#1_: 1 basin_storage_change_Basin_#1_ - 1 flow_(FlowBoundary_#4,_Basin_#1)_ - 1 flow_(FlowBoundary_#7,_Basin_#1)_ - 1 flow_(LinearResistance_#10,_Basin_#1)_ - 1 flow_(UserDemand_#9,_Basin_#1)_ + 1 flow_(Basin_#1,_Pump_#5)_ + 1 flow_(Basin_#1,_Pump_#8)_ + 1 flow_(Basin_#1,_UserDemand_#9)_ = 0
volume_conservation_Basin_#11_: 1 basin_storage_change_Basin_#11_ + 1 flow_(Basin_#11,_LinearResistance_#10)_ = 0
linear_resistance_constraint_LinearResistance_#10_: 3.2400000000000003e-6 basin_storage_change_Basin_#1_ - 3.24e-5 basin_storage_change_Basin_#11_ + 4.890439975511307e-6 low_storage_factor_Basin_#1_ + 1 flow_(Basin_#11,_LinearResistance_#10)_ = 0
user_demand_allocated_sum_constraint_UserDemand_#9_: 1 flow_(Basin_#1,_UserDemand_#9)_ - 1 user_demand_allocated_UserDemand_#9,1_ = 0
user_demand_return_flow_UserDemand_#9_: 1 flow_(UserDemand_#9,_Basin_#1)_ - 0.5 flow_(Basin_#1,_UserDemand_#9)_ = 0
average_flow_unit_error_constraint_1_: -1 user_demand_error_UserDemand_#9,1,first_ + 1 average_flow_unit_error_1_ = 0
pump_constraint_Pump_#5_: -3.667849787211883e-5 low_storage_factor_Basin_#1_ + 1 flow_(Basin_#1,_Pump_#5)_ = 0
pump_constraint_Pump_#8_: -8.558316170161061e-5 low_storage_factor_Basin_#1_ + 1 flow_(Basin_#1,_Pump_#8)_ = 0
Bounds
basin_storage_change_Basin_#1_ >= -1.8868273627934935
basin_storage_change_Basin_#11_ >= -0.0377432308623337
0 <= low_storage_factor_Basin_#1_ <= 1
0 <= low_storage_factor_Basin_#11_ <= 1
flow_(Pump_#5,_Terminal_#6)_ free
flow_(Pump_#8,_Terminal_#6)_ free
flow_(Basin_#11,_LinearResistance_#10)_ free
flow_(FlowBoundary_#4,_Basin_#1)_ = 0.00012226165957372943
flow_(FlowBoundary_#7,_Basin_#1)_ = 6.113082978686471e-5
flow_(LinearResistance_#10,_Basin_#1)_ free
0 <= flow_(UserDemand_#9,_Basin_#1)_ <= 2.4452331914745887e-5
flow_(Basin_#1,_Pump_#5)_ free
flow_(Basin_#1,_Pump_#8)_ free
0 <= flow_(Basin_#1,_UserDemand_#9)_ <= 2.4452331914745887e-5
0 <= user_demand_allocated_UserDemand_#9,1_ <= 2.4452331914745887e-5
0 <= user_demand_error_UserDemand_#9,1,first_ <= 1
0 <= user_demand_error_UserDemand_#9,1,second_ <= 1
0 <= average_flow_unit_error_1_ <= 1
End

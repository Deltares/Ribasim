minimize
obj: 
subject to
user_demand_relative_error_constraint_UserDemand_#5,1_: 1 user_demand_allocated_UserDemand_#5,1_ + 2 user_demand_error_UserDemand_#5,1,first_ >= 2
user_demand_fairness_error_constraint_UserDemand_#5,1_: -1 user_demand_error_UserDemand_#5,1,first_ + 1 user_demand_error_UserDemand_#5,1,second_ + 1 average_flow_unit_error_1_ >= 0
flow_conservation_pump_Pump_#3_: 1 flow_(Basin_#2,_Pump_#3)_ - 1 flow_(Pump_#3,_Basin_#4)_ = 0
volume_conservation_Basin_#2_: 1 basin_storage_change_Basin_#2_ + 1.1574074074074075e-5 low_storage_factor_Basin_#2_ - 1.1574074074074075e-5 flow_(FlowBoundary_#1,_Basin_#2)_ + 1.1574074074074075e-5 flow_(Basin_#2,_Pump_#3)_ = 1.1574074074074075e-5
volume_conservation_Basin_#4_: 1 basin_storage_change_Basin_#4_ + 1.1574074074074075e-5 low_storage_factor_Basin_#4_ - 1.1574074074074075e-5 flow_(Pump_#3,_Basin_#4)_ + 1.1574074074074075e-5 flow_(Basin_#4,_UserDemand_#5)_ - 1.1574074074074075e-5 flow_(UserDemand_#5,_Basin_#4)_ = 1.1574074074074075e-5
pump_constraint_Pump_#3_: -1 low_storage_factor_Basin_#2_ + 1 flow_(Basin_#2,_Pump_#3)_ = 0
user_demand_allocated_sum_constraint_UserDemand_#5_: 1 flow_(Basin_#4,_UserDemand_#5)_ - 1 user_demand_allocated_UserDemand_#5,1_ = 0
user_demand_return_flow_UserDemand_#5_: -0.5 flow_(Basin_#4,_UserDemand_#5)_ + 1 flow_(UserDemand_#5,_Basin_#4)_ = 0
average_flow_unit_error_constraint_1_: -1 user_demand_error_UserDemand_#5,1,first_ + 1 average_flow_unit_error_1_ = 0
Bounds
-0.06611570247933884 <= basin_storage_change_Basin_#2_ <= 0.2644628099173554
-0.06611570247933884 <= basin_storage_change_Basin_#4_ <= 0.2644628099173554
0 <= low_storage_factor_Basin_#2_ <= 1
0 <= low_storage_factor_Basin_#4_ <= 1
0 <= flow_(FlowBoundary_#1,_Basin_#2)_ <= 2.856198347107438e6
0 <= flow_(Basin_#2,_Pump_#3)_ <= 2.856198347107438
0 <= flow_(Pump_#3,_Basin_#4)_ <= 2.856198347107438
0 <= flow_(Basin_#4,_UserDemand_#5)_ <= 2.856198347107438e6
0 <= flow_(UserDemand_#5,_Basin_#4)_ <= 2.856198347107438e6
0 <= user_demand_allocated_UserDemand_#5,1_ <= 2
0 <= user_demand_error_UserDemand_#5,1,first_ <= 1
0 <= user_demand_error_UserDemand_#5,1,second_ <= 1
0 <= average_flow_unit_error_1_ <= 1
End

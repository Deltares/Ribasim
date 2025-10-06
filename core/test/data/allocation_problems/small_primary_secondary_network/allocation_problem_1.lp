minimize
obj: 
subject to
user_demand_relative_error_constraint_UserDemand_#3,2_: 1 user_demand_allocated_UserDemand_#3,2_ + 2 user_demand_error_UserDemand_#3,2,first_ >= 2
secondary_network_relative_error_constraint_(Outlet_#4,_Basin_#5),1_: 1 secondary_network_allocated_(Outlet_#4,_Basin_#5),1_ + 2 secondary_network_error_(Outlet_#4,_Basin_#5),1,first_ >= 2
secondary_network_relative_error_constraint_(Outlet_#4,_Basin_#5),2_: 1 secondary_network_allocated_(Outlet_#4,_Basin_#5),2_ + 2 secondary_network_error_(Outlet_#4,_Basin_#5),2,first_ >= 2
user_demand_fairness_error_constraint_UserDemand_#3,2_: -1 user_demand_error_UserDemand_#3,2,first_ + 1 user_demand_error_UserDemand_#3,2,second_ + 1 average_flow_unit_error_2_ >= 0
subnetwork_demand_fairness_error_constraint_(Outlet_#4,_Basin_#5),1_: -1 secondary_network_error_(Outlet_#4,_Basin_#5),1,first_ + 1 secondary_network_error_(Outlet_#4,_Basin_#5),1,second_ + 1 average_flow_unit_error_1_ >= 0
subnetwork_demand_fairness_error_constraint_(Outlet_#4,_Basin_#5),2_: -1 secondary_network_error_(Outlet_#4,_Basin_#5),2,first_ + 1 secondary_network_error_(Outlet_#4,_Basin_#5),2,second_ + 1 average_flow_unit_error_2_ >= 0
flow_conservation_outlet_Outlet_#4_: 1 flow_(Basin_#2,_Outlet_#4)_ - 1 flow_(Outlet_#4,_Basin_#5)_ = 0
volume_conservation_Basin_#2_: 1 basin_storage_change_Basin_#2_ + 1 low_storage_factor_Basin_#2_ + 1 flow_(Basin_#2,_UserDemand_#3)_ + 1 flow_(Basin_#2,_Outlet_#4)_ - 1 flow_(UserDemand_#3,_Basin_#2)_ = 1
user_demand_allocated_sum_constraint_UserDemand_#3_: 1 flow_(Basin_#2,_UserDemand_#3)_ - 1 user_demand_allocated_UserDemand_#3,2_ = 0
user_demand_return_flow_UserDemand_#3_: -0.5 flow_(Basin_#2,_UserDemand_#3)_ + 1 flow_(UserDemand_#3,_Basin_#2)_ = 0
secondary_network_allocated_sum_constraint_(Outlet_#4,_Basin_#5)_: 1 flow_(Outlet_#4,_Basin_#5)_ - 1 secondary_network_allocated_(Outlet_#4,_Basin_#5),1_ - 1 secondary_network_allocated_(Outlet_#4,_Basin_#5),2_ = 0
average_flow_unit_error_constraint_1_: -1 secondary_network_error_(Outlet_#4,_Basin_#5),1,first_ + 1 average_flow_unit_error_1_ = 0
average_flow_unit_error_constraint_2_: -1 user_demand_error_UserDemand_#3,2,first_ - 1 secondary_network_error_(Outlet_#4,_Basin_#5),2,first_ + 1 average_flow_unit_error_2_ = 0
Bounds
-0.006666666666666667 <= basin_storage_change_Basin_#2_ <= 0.02666666666666667
0 <= low_storage_factor_Basin_#2_ <= 1
0 <= flow_(Basin_#2,_UserDemand_#3)_ <= 288000
0 <= flow_(Basin_#2,_Outlet_#4)_ <= 1.728
0 <= flow_(Outlet_#4,_Basin_#5)_ <= 1.728
0 <= flow_(UserDemand_#3,_Basin_#2)_ <= 288000
0 <= user_demand_allocated_UserDemand_#3,2_ <= 2
0 <= user_demand_error_UserDemand_#3,2,first_ <= 1
0 <= user_demand_error_UserDemand_#3,2,second_ <= 1
0 <= secondary_network_allocated_(Outlet_#4,_Basin_#5),1_ <= 2
0 <= secondary_network_allocated_(Outlet_#4,_Basin_#5),2_ <= 2
0 <= secondary_network_error_(Outlet_#4,_Basin_#5),1,first_ <= 1
0 <= secondary_network_error_(Outlet_#4,_Basin_#5),1,second_ <= 1
0 <= secondary_network_error_(Outlet_#4,_Basin_#5),2,first_ <= 1
0 <= secondary_network_error_(Outlet_#4,_Basin_#5),2,second_ <= 1
0 <= average_flow_unit_error_1_ <= 1
0 <= average_flow_unit_error_2_ <= 1
End

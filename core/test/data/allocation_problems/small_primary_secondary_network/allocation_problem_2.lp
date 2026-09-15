minimize
obj: 40 flow_(Outlet_#4,_Basin_#5)_
subject to
c1: 1 level_demand_error_Basin_#5,1,lower,first_ + 1 level_demand_error_Basin_#5,1,upper,first_ <= 0
c2: 1 level_demand_error_Basin_#5,1,lower,second_ + 1 level_demand_error_Basin_#5,1,upper,second_ <= 0
c3: 1 user_demand_error_UserDemand_#6,2,first_ <= 0
c4: 1 user_demand_error_UserDemand_#6,2,second_ <= 0
c5: -1 low_storage_factor_Basin_#5_ <= -1
user_demand_relative_error_constraint_UserDemand_#6,2_: 1 user_demand_allocated_UserDemand_#6,2_ + 0.4114285714285715 user_demand_error_UserDemand_#6,2,first_ >= 0.4114285714285715
storage_constraint_lower_Basin_#5,1_: 1 basin_storage_change_Basin_#5_ + 1 level_demand_error_Basin_#5,1,lower,first_ >= -0.5714285714285714
storage_constraint_upper_Basin_#5,1_: -1 basin_storage_change_Basin_#5_ + 1 level_demand_error_Basin_#5,1,upper,first_ >= -0.8571428571428571
user_demand_fairness_error_constraint_UserDemand_#6,2_: -1 user_demand_error_UserDemand_#6,2,first_ + 1 user_demand_error_UserDemand_#6,2,second_ + 1 average_flow_unit_error_2_ >= 0
level_demand_fairness_error_constraint_Basin_#5,1,lower_: -1 level_demand_error_Basin_#5,1,lower,first_ + 1 level_demand_error_Basin_#5,1,lower,second_ + 1 average_storage_unit_error_1,lower_ >= 0
level_demand_fairness_error_constraint_Basin_#5,1,upper_: -1 level_demand_error_Basin_#5,1,upper,first_ + 1 level_demand_error_Basin_#5,1,upper,second_ + 1 average_storage_unit_error_1,upper_ >= 0
volume_conservation_Basin_#5_: 1 basin_storage_change_Basin_#5_ - 1 flow_(Outlet_#4,_Basin_#5)_ + 1 flow_(Basin_#5,_UserDemand_#6)_ - 1 flow_(UserDemand_#6,_Basin_#5)_ = 0
user_demand_allocated_sum_constraint_UserDemand_#6_: 1 flow_(Basin_#5,_UserDemand_#6)_ - 1 user_demand_allocated_UserDemand_#6,2_ = 0
user_demand_return_flow_UserDemand_#6_: 1 flow_(UserDemand_#6,_Basin_#5)_ = 0
average_flow_unit_error_constraint_2_: -1 user_demand_error_UserDemand_#6,2,first_ + 1 average_flow_unit_error_2_ = 0
average_storage_unit_error_constraint_1,upper_: -1 level_demand_error_Basin_#5,1,upper,first_ + 1 average_storage_unit_error_1,upper_ = 0
average_storage_unit_error_constraint_1,lower_: -1 level_demand_error_Basin_#5,1,lower,first_ + 1 average_storage_unit_error_1,lower_ = 0
Bounds
-1.2857142857142858 <= basin_storage_change_Basin_#5_ <= 0.14285714285714285
0 <= low_storage_factor_Basin_#5_ <= 1
flow_(Outlet_#4,_Basin_#5)_ = 0
0 <= flow_(Basin_#5,_UserDemand_#6)_ <= 0.4114285714285715
0 <= flow_(UserDemand_#6,_Basin_#5)_ <= 0.4114285714285715
0 <= user_demand_allocated_UserDemand_#6,2_ <= 0.4114285714285715
0 <= user_demand_error_UserDemand_#6,2,first_ <= 1
0 <= user_demand_error_UserDemand_#6,2,second_ <= 1
level_demand_error_Basin_#5,1,lower,first_ >= 0
level_demand_error_Basin_#5,1,lower,second_ >= 0
level_demand_error_Basin_#5,1,upper,first_ >= 0
level_demand_error_Basin_#5,1,upper,second_ >= 0
0 <= average_flow_unit_error_2_ <= 1
average_storage_unit_error_1,lower_ >= 0
average_storage_unit_error_1,upper_ >= 0
End

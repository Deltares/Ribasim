minimize
obj: 1 user_demand_error_UserDemand_#3,2,second_
subject to
c1: 1 user_demand_error_UserDemand_#6,1,first_ <= 0
c2: 1 user_demand_error_UserDemand_#6,1,second_ <= 0
c3: 1 user_demand_error_UserDemand_#3,2,first_ <= 1
user_demand_relative_error_constraint_UserDemand_#3,2_: 1 user_demand_allocated_UserDemand_#3,2_ + 1 user_demand_error_UserDemand_#3,2,first_ >= 1
user_demand_relative_error_constraint_UserDemand_#6,1_: 1 user_demand_allocated_UserDemand_#6,1_ + 1 user_demand_error_UserDemand_#6,1,first_ >= 1
user_demand_fairness_error_constraint_UserDemand_#3,2_: -1 user_demand_error_UserDemand_#3,2,first_ + 1 user_demand_error_UserDemand_#3,2,second_ + 1 average_flow_unit_error_2_ >= 0
user_demand_fairness_error_constraint_UserDemand_#6,1_: -1 user_demand_error_UserDemand_#6,1,first_ + 1 user_demand_error_UserDemand_#6,1,second_ + 1 average_flow_unit_error_1_ >= 0
junction_outflow_(Junction_#2,_Junction_#5)_: -1 flow_(FlowBoundary_#1,_Junction_#2)_ + 1 flow_(Junction_#2,_UserDemand_#3)_ + 1 flow_(Junction_#2,_Junction_#5)_ = 0
junction_outflow_(Junction_#5,_Terminal_#9)_: -1 flow_(Junction_#2,_Junction_#5)_ + 1 flow_(Junction_#5,_UserDemand_#6)_ + 1 flow_(Junction_#5,_Terminal_#9)_ = 0
user_demand_allocated_sum_constraint_UserDemand_#3_: 1 flow_(Junction_#2,_UserDemand_#3)_ - 1 user_demand_allocated_UserDemand_#3,2_ = 0
user_demand_allocated_sum_constraint_UserDemand_#6_: 1 flow_(Junction_#5,_UserDemand_#6)_ - 1 user_demand_allocated_UserDemand_#6,1_ = 0
user_demand_return_flow_UserDemand_#3_: 1 flow_(UserDemand_#3,_Terminal_#4)_ = 0
user_demand_return_flow_UserDemand_#6_: 1 flow_(UserDemand_#6,_Terminal_#7)_ = 0
average_flow_unit_error_constraint_1_: -1 user_demand_error_UserDemand_#6,1,first_ + 1 average_flow_unit_error_1_ = 0
average_flow_unit_error_constraint_2_: -1 user_demand_error_UserDemand_#3,2,first_ + 1 average_flow_unit_error_2_ = 0
Bounds
flow_(FlowBoundary_#1,_Junction_#2)_ = 1
0 <= flow_(Junction_#2,_UserDemand_#3)_ <= 1
0 <= flow_(UserDemand_#3,_Terminal_#4)_ <= 1
flow_(Junction_#2,_Junction_#5)_ >= 0
0 <= flow_(Junction_#5,_UserDemand_#6)_ <= 1
0 <= flow_(UserDemand_#6,_Terminal_#7)_ <= 1
flow_(Junction_#5,_Terminal_#9)_ >= 0
0 <= user_demand_allocated_UserDemand_#3,2_ <= 1
0 <= user_demand_allocated_UserDemand_#6,1_ <= 1
0 <= user_demand_error_UserDemand_#3,2,first_ <= 1
0 <= user_demand_error_UserDemand_#3,2,second_ <= 1
0 <= user_demand_error_UserDemand_#6,1,first_ <= 1
0 <= user_demand_error_UserDemand_#6,1,second_ <= 1
0 <= average_flow_unit_error_1_ <= 1
0 <= average_flow_unit_error_2_ <= 1
End

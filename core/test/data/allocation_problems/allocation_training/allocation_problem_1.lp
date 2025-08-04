minimize
obj: 
subject to
c1_2: 1 __1_3_ + 1 __1_7_ + 1 __1_11_ - 1 y_1_1_ <= 0
c2_2: 1 __1_4_ + 1 __1_5_ + 1 __1_6_ + 1 __1_12_ + 1 __1_13_ + 1 __1_14_ - 1 y_1_2_ <= 0
c3_2: 1 __1_6_ + 1 __1_7_ + 1 __1_8_ + 1 __1_9_ + 1 __1_10_ + 1 __1_11_ + 1 __1_12_ - 1 y_1_3_ <= 0
c4_1: 1 __1_10_ + 1 __1_11_ + 1 __1_12_ + 1 __1_13_ + 1 __1_14_ - 1 y_1_4_ <= 0
c5_2: 1 __2_3_ + 1 __2_7_ - 1 y_2_1_ <= 0
c6_2: 1 __2_4_ + 1 __2_5_ + 1 __2_6_ - 1 y_2_2_ <= 0
c7_2: 1 __2_6_ + 1 __2_7_ + 1 __2_8_ + 1 __2_9_ - 1 y_2_3_ <= 0
c8_1: 1 __3_3_ - 1 y_3_1_ <= 0
c9_2: 1 __4_3_ - 1 y_4_1_ <= 0
c10_2: 1 __5_3_ + 1 __5_4_ - 1 y_5_1_ <= 0
c11_2: 1 __5_4_ - 1 y_5_2_ <= 0
c12_2: 1 __6_3_ + 1 __6_4_ - 1 y_6_1_ <= 0
c13_2: 1 __6_4_ - 1 y_6_2_ <= 0
c1_1: 1 __1_2_ + 1 __1_3_ + 1 __1_4_ + 1 __1_6_ + 1 __1_7_ + 1 __1_8_ + 1 __1_10_ + 1 __1_11_ + 1 __1_12_ - 1 y_1_1_ >= 0
c2_1: 1 __1_3_ + 1 __1_4_ + 1 __1_5_ + 1 __1_6_ + 1 __1_7_ + 1 __1_11_ + 1 __1_12_ + 1 __1_13_ + 1 __1_14_ - 1 y_1_2_ >= 0
c3_1: 1 __1_5_ + 1 __1_6_ + 1 __1_7_ + 1 __1_8_ + 1 __1_9_ + 1 __1_10_ + 1 __1_11_ + 1 __1_12_ + 1 __1_13_ - 1 y_1_3_ >= 0
c4: 1 __1_9_ + 1 __1_10_ + 1 __1_11_ + 1 __1_12_ + 1 __1_13_ + 1 __1_14_ - 1 y_1_4_ >= 0
c5_1: 1 __2_2_ + 1 __2_3_ + 1 __2_4_ + 1 __2_6_ + 1 __2_7_ + 1 __2_8_ - 1 y_2_1_ >= 0
c6_1: 1 __2_3_ + 1 __2_4_ + 1 __2_5_ + 1 __2_6_ + 1 __2_7_ - 1 y_2_2_ >= 0
c7_1: 1 __2_5_ + 1 __2_6_ + 1 __2_7_ + 1 __2_8_ + 1 __2_9_ - 1 y_2_3_ >= 0
c8: 1 __3_2_ + 1 __3_3_ - 1 y_3_1_ >= 0
c9_1: 1 __4_2_ + 1 __4_3_ - 1 y_4_1_ >= 0
c10_1: 1 __5_2_ + 1 __5_3_ + 1 __5_4_ - 1 y_5_1_ >= 0
c11_1: 1 __5_3_ + 1 __5_4_ - 1 y_5_2_ >= 0
c12_1: 1 __6_2_ + 1 __6_3_ + 1 __6_4_ - 1 y_6_1_ >= 0
c13_1: 1 __6_3_ + 1 __6_4_ - 1 y_6_2_ >= 0
user_demand_constraint_lower_UserDemand_#6_: 1 flow_(Basin_#7,_UserDemand_#6)_ - 2 target_fraction - 1 user_demand_allocated_UserDemand_#6_ + 2 relative_user_demand_error_lower_UserDemand_#6_ >= 0
user_demand_constraint_lower_UserDemand_#9_: 1 flow_(Basin_#7,_UserDemand_#9)_ - 2 target_fraction - 1 user_demand_allocated_UserDemand_#9_ + 2 relative_user_demand_error_lower_UserDemand_#9_ >= 0
user_demand_constraint_lower_UserDemand_#10_: 1 flow_(Basin_#7,_UserDemand_#10)_ - 2 target_fraction - 1 user_demand_allocated_UserDemand_#10_ + 2 relative_user_demand_error_lower_UserDemand_#10_ >= 0
user_demand_constraint_upper_UserDemand_#6_: -1 flow_(Basin_#7,_UserDemand_#6)_ + 2 target_fraction + 1 user_demand_allocated_UserDemand_#6_ + 2 relative_user_demand_error_upper_UserDemand_#6_ >= 0
user_demand_constraint_upper_UserDemand_#9_: -1 flow_(Basin_#7,_UserDemand_#9)_ + 2 target_fraction + 1 user_demand_allocated_UserDemand_#9_ + 2 relative_user_demand_error_upper_UserDemand_#9_ >= 0
user_demand_constraint_upper_UserDemand_#10_: -1 flow_(Basin_#7,_UserDemand_#10)_ + 2 target_fraction + 1 user_demand_allocated_UserDemand_#10_ + 2 relative_user_demand_error_upper_UserDemand_#10_ >= 0
storage_constraint_in_Basin_#7_: -1 basin_storage_(Basin_#7,__start)_ + 1 basin_storage_(Basin_#7,__end)_ - 2 target_storage_demand_fraction_in + 2 relative_storage_error_in_Basin_#7_ >= 0
storage_constraint_out_Basin_#7_: 1 basin_storage_(Basin_#7,__start)_ - 1 basin_storage_(Basin_#7,__end)_ + 2 target_storage_demand_fraction_out + 2 relative_storage_error_out_Basin_#7_ >= 0
c1: 1 __1_1_ + 1 __1_2_ + 1 __1_3_ + 1 __1_4_ + 1 __1_5_ + 1 __1_6_ + 1 __1_7_ + 1 __1_8_ + 1 __1_9_ + 1 __1_10_ + 1 __1_11_ + 1 __1_12_ + 1 __1_13_ + 1 __1_14_ = 1
c2: -1 basin_storage_(Basin_#3,__end)_ + 0.003728413898328594 __1_2_ + 0.007456827796657188 __1_3_ + 0.011185241694985783 __1_4_ + 0.01864206949164297 __1_5_ + 0.029827311186628753 __1_6_ + 0.04101255288161454 __1_7_ + 0.05219779457660032 __1_8_ + 0.07083986406824329 __1_9_ + 0.09693876135654345 __1_10_ + 0.1342229003398294 __1_11_ + 0.1864206949164297 __1_12_ + 0.2609889728830016 __1_13_ + 0.3728413898328594 __1_14_ = 0
c3: -1 z_1 + 0.24370485457809737 __1_2_ + 0.44109778697620317 __1_3_ + 0.6114919005906716 __1_4_ + 0.9023793049731823 __1_5_ + 1.2638546927991616 __1_6_ + 1.5712577578701283 __1_7_ + 1.8433904506376406 __1_8_ + 2.24366011651335 __1_9_ + 2.7289506519030784 __1_10_ + 3.3247600040199807 __1_11_ + 4.037589222208597 __1_12_ + 4.903893745836065 __1_13_ + 6 __1_14_ = 0
basin_profile_Basin_#3_: 1 basin_level_Basin_#3_ - 1 z_1 = 0
c5: 1 __2_1_ + 1 __2_2_ + 1 __2_3_ + 1 __2_4_ + 1 __2_5_ + 1 __2_6_ + 1 __2_7_ + 1 __2_8_ + 1 __2_9_ = 1
c6: -1 basin_storage_(Basin_#7,__end)_ + 0.03627158610167141 __2_2_ + 0.10881475830501422 __2_3_ + 0.32644427491504263 __2_4_ + 0.5803453776267425 __2_5_ + 1.0156044108467994 __2_6_ + 1.8861224772869132 __2_7_ + 2.611554199320341 __2_8_ + 3.6271586101671405 __2_9_ = 0
c7: -1 z_2 + 0.09115994759514195 __2_2_ + 0.27134072428408346 __2_3_ + 0.7958982683606178 __2_4_ + 1.380662130695116 __2_5_ + 2.3251981405925526 __2_6_ + 4.041708780773147 __2_7_ + 5.338060291424692 __2_8_ + 7 __2_9_ = 0
basin_profile_Basin_#7_: 1 basin_level_Basin_#7_ - 1 z_2 = 0
c9: 1 __3_1_ + 1 __3_2_ + 1 __3_3_ = 1
c10: -1 basin_storage_(Basin_#3,__end)_ + 0.0014129505051205587 __3_2_ + 0.3728413898328594 __3_3_ = 0
c11: -1 z_3 + 1 __3_2_ + 1 __3_3_ = 0
c12: 1 low_storage_factor_Basin_#3_ - 1 z_3 = 0
c13: 1 __4_1_ + 1 __4_2_ + 1 __4_3_ = 1
c14: -1 basin_storage_(Basin_#7,__end)_ + 0.03980433979542299 __4_2_ + 3.6271586101671405 __4_3_ = 0
c15: -1 z_4 + 1 __4_2_ + 1 __4_3_ = 0
c16: 1 low_storage_factor_Basin_#7_ - 1 z_4 = 0
flow_conservation_tabulatedratingcurve_TabulatedRatingCurve_#4_: 1 flow_(Basin_#3,_TabulatedRatingCurve_#4)_ - 1 flow_(TabulatedRatingCurve_#4,_Terminal_#5)_ = 0
flow_conservation_tabulatedratingcurve_TabulatedRatingCurve_#8_: 1 flow_(Basin_#7,_TabulatedRatingCurve_#8)_ - 1 flow_(TabulatedRatingCurve_#8,_Basin_#3)_ = 0
volume_conservation_Basin_#3_: -1 basin_storage_(Basin_#3,__start)_ + 1 basin_storage_(Basin_#3,__end)_ - 1 flow_(FlowBoundary_#2,_Basin_#3)_ - 1 flow_(UserDemand_#6,_Basin_#3)_ - 1 flow_(UserDemand_#9,_Basin_#3)_ - 1 flow_(TabulatedRatingCurve_#8,_Basin_#3)_ + 1 flow_(Basin_#3,_TabulatedRatingCurve_#4)_ - 1 flow_(UserDemand_#10,_Basin_#3)_ - 1 basin_forcing_Basin_#3_ = 0
volume_conservation_Basin_#7_: -1 basin_storage_(Basin_#7,__start)_ + 1 basin_storage_(Basin_#7,__end)_ - 1 flow_(FlowBoundary_#1,_Basin_#7)_ + 1 flow_(Basin_#7,_UserDemand_#6)_ + 1 flow_(Basin_#7,_UserDemand_#9)_ + 1 flow_(Basin_#7,_TabulatedRatingCurve_#8)_ + 1 flow_(Basin_#7,_UserDemand_#10)_ - 1 basin_forcing_Basin_#7_ = 0
c21: 1 __5_1_ + 1 __5_2_ + 1 __5_3_ + 1 __5_4_ = 1
c22: -1 basin_level_Basin_#3_ - 1 __5_1_ + 2 __5_3_ + 5 __5_4_ = 0
c23: -1 z_5 + 0.08560133950244221 __5_3_ + 0.34240535800976885 __5_4_ = 0
rating_curve_TabulatedRatingCurve_#4_: 1 flow_(Basin_#3,_TabulatedRatingCurve_#4)_ - 1 z_5 = 0
c25: 1 __6_1_ + 1 __6_2_ + 1 __6_3_ + 1 __6_4_ = 1
c26: -1 basin_level_Basin_#7_ - 1 __6_1_ + 1.5 __6_3_ + 5 __6_4_ = 0
c27: -1 z_6 + 0.077041205552198 __6_3_ + 0.34240535800976885 __6_4_ = 0
rating_curve_TabulatedRatingCurve_#8_: 1 flow_(Basin_#7,_TabulatedRatingCurve_#8)_ - 1 z_6 = 0
user_demand_return_flow_UserDemand_#6_: -0.5 flow_(Basin_#7,_UserDemand_#6)_ + 1 flow_(UserDemand_#6,_Basin_#3)_ = 0
user_demand_return_flow_UserDemand_#9_: -0.5 flow_(Basin_#7,_UserDemand_#9)_ + 1 flow_(UserDemand_#9,_Basin_#3)_ = 0
user_demand_return_flow_UserDemand_#10_: -0.5 flow_(Basin_#7,_UserDemand_#10)_ + 1 flow_(UserDemand_#10,_Basin_#3)_ = 0
Bounds
0 <= basin_storage_(Basin_#3,__start)_ <= 0.3728413898328594
0 <= basin_storage_(Basin_#7,__start)_ <= 3.6271586101671405
0 <= basin_storage_(Basin_#3,__end)_ <= 0.3728413898328594
0 <= basin_storage_(Basin_#7,__end)_ <= 3.6271586101671405
0 <= basin_level_Basin_#3_ <= 6
0 <= basin_level_Basin_#7_ <= 7
0 <= z_1 <= 6
0 <= __1_1_ <= 1
0 <= __1_2_ <= 1
0 <= __1_3_ <= 1
0 <= __1_4_ <= 1
0 <= __1_5_ <= 1
0 <= __1_6_ <= 1
0 <= __1_7_ <= 1
0 <= __1_8_ <= 1
0 <= __1_9_ <= 1
0 <= __1_10_ <= 1
0 <= __1_11_ <= 1
0 <= __1_12_ <= 1
0 <= __1_13_ <= 1
0 <= __1_14_ <= 1
0 <= z_2 <= 7
0 <= __2_1_ <= 1
0 <= __2_2_ <= 1
0 <= __2_3_ <= 1
0 <= __2_4_ <= 1
0 <= __2_5_ <= 1
0 <= __2_6_ <= 1
0 <= __2_7_ <= 1
0 <= __2_8_ <= 1
0 <= __2_9_ <= 1
0 <= low_storage_factor_Basin_#3_ <= 1
0 <= low_storage_factor_Basin_#7_ <= 1
0 <= z_3 <= 1
0 <= __3_1_ <= 1
0 <= __3_2_ <= 1
0 <= __3_3_ <= 1
0 <= z_4 <= 1
0 <= __4_1_ <= 1
0 <= __4_2_ <= 1
0 <= __4_3_ <= 1
0 <= flow_(FlowBoundary_#1,_Basin_#7)_ <= 856.0133950244222
0 <= flow_(FlowBoundary_#2,_Basin_#3)_ <= 856.0133950244222
0 <= flow_(Basin_#7,_UserDemand_#6)_ <= 856.0133950244222
0 <= flow_(UserDemand_#6,_Basin_#3)_ <= 856.0133950244222
0 <= flow_(Basin_#7,_UserDemand_#9)_ <= 856.0133950244222
0 <= flow_(UserDemand_#9,_Basin_#3)_ <= 856.0133950244222
0 <= flow_(Basin_#7,_TabulatedRatingCurve_#8)_ <= 856.0133950244222
0 <= flow_(TabulatedRatingCurve_#8,_Basin_#3)_ <= 856.0133950244222
0 <= flow_(Basin_#3,_TabulatedRatingCurve_#4)_ <= 856.0133950244222
0 <= flow_(Basin_#7,_UserDemand_#10)_ <= 856.0133950244222
0 <= flow_(UserDemand_#10,_Basin_#3)_ <= 856.0133950244222
0 <= flow_(TabulatedRatingCurve_#4,_Terminal_#5)_ <= 856.0133950244222
basin_forcing_Basin_#7_ = 0
basin_forcing_Basin_#3_ = 0
0 <= z_5 <= 0.34240535800976885
0 <= __5_1_ <= 1
0 <= __5_2_ <= 1
0 <= __5_3_ <= 1
0 <= __5_4_ <= 1
0 <= z_6 <= 0.34240535800976885
0 <= __6_1_ <= 1
0 <= __6_2_ <= 1
0 <= __6_3_ <= 1
0 <= __6_4_ <= 1
target_fraction = 1
user_demand_allocated_UserDemand_#6_ = 0
user_demand_allocated_UserDemand_#9_ = 0
user_demand_allocated_UserDemand_#10_ = 0
relative_user_demand_error_lower_UserDemand_#6_ >= 0
relative_user_demand_error_lower_UserDemand_#9_ >= 0
relative_user_demand_error_lower_UserDemand_#10_ >= 0
relative_user_demand_error_upper_UserDemand_#6_ >= 0
relative_user_demand_error_upper_UserDemand_#9_ >= 0
relative_user_demand_error_upper_UserDemand_#10_ >= 0
target_storage_demand_fraction_in = 1
target_storage_demand_fraction_out = 1
relative_storage_error_in_Basin_#7_ >= 0
relative_storage_error_out_Basin_#7_ >= 0
Binary
y_1_1_
y_1_2_
y_1_3_
y_1_4_
y_2_1_
y_2_2_
y_2_3_
y_3_1_
y_4_1_
y_5_1_
y_5_2_
y_6_1_
y_6_2_
End

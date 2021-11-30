libname td_demo teradata server=barbera user=sasdemo 
password='{SAS002}835DA5352D5AE01B196D396B1920462032A1731E' database=demo_data ;

proc sql;
connect using td_demo as td;
execute(drop table demo_data.new_customers) by td;
execute(commit) by td;
disconnect from td;

run;
proc sql;
connect using td_demo as td;
execute(drop table demo_data.dupe_customers) by td;
execute(commit) by td;
disconnect from td;

run;
proc sql;
connect using td_demo as td;
execute(drop table demo_data.dqmatch_name) by td;
execute(commit) by td;
disconnect from td;

run;
proc sql;
connect using td_demo as td;
execute(drop table demo_data.dqmatch_address) by td;
execute(commit) by td;
disconnect from td;

run;
proc sql;
connect using td_demo as td;
execute(drop table demo_data.cust_state_std) by td;
execute(commit) by td;
disconnect from td;

run;
proc sql;
connect using td_demo as td;
execute(drop table demo_data.cust_gend) by td;
execute(commit) by td;
disconnect from td;

run;
proc sql;
connect using td_demo as td;
/*execute(drop table demo_data.txn_pvt) by td;
execute(commit) by td;*/
disconnect from td;

run;
proc sql;
connect using td_demo as td;
execute(delete from demo_data.txn_pvt_mnth) by td;
execute(commit) by td;
disconnect from td;

run;
proc sql;
connect using td_demo as td;
execute(drop view demo_data.master_customer_clustered by td;
execute(commit) by td;
disconnect from td;

run;
proc sql;
connect using td_demo as td;
execute (drop view demo_data.master_customer_list) by td;
execute(commit) by td;
disconnect from td;

run;

proc sql;
connect using td_demo as td;
execute(delete from demo_data.master_customer_clustered) by td;
execute(commit) by td;
disconnect from td;

run;

libname td_demo clear;

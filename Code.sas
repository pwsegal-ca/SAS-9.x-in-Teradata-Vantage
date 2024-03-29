```SAS

/******************

   V 2.2 July 21 2021
         Paul Segal
         change explicit SQL to use connect using syntax
         
*******************/         
Options sastrace=',,,ds' sastraceloc=saslog nostsuffix;
options dbidirectexec;
%let idconn = server=barbera user=sasdemo password='{SAS002}835DA5352D5AE01B196D396B1920462032A1731E' mode=teradata;
%let txn_tbl=txn_12m;

libname td_demo teradata server=barbera user=sasdemo 
password='{SAS002}835DA5352D5AE01B196D396B1920462032A1731E' database=demo_data mode=teradata;


proc print data=td_demo.cust_vw (obs=10);

run;

libname fs '/data/';


proc print data=fs.new_customers(obs=10);
run;

data td_demo.new_customers (fastload=yes tpt=yes dbcommit=0);
set fs.new_customers;
run;

/* check to see that they are actually new customers */

proc sql;
connect using td_demo as td;
select * from connection to td
(
SELECT 1 AS "xidx", '#records     ' AS "xtable", "cust_vw", "new_customers" FROM
	  (SELECT CAST(COUNT(*) AS FLOAT) AS "cust_vw" FROM "demo_data"."cust_vw") T1
	, (SELECT CAST(COUNT(*) AS FLOAT) AS "new_customers" FROM "demo_data"."new_customers") T2
UNION
SELECT 2, '#uniques     ', "cust_vw", "new_customers" FROM
	  (SELECT CAST(COUNT(DISTINCT "cid") AS FLOAT) AS "cust_vw" FROM "demo_data"."cust_vw") T1
	, (SELECT CAST(COUNT(DISTINCT "cid") AS FLOAT) AS "new_customers" FROM "demo_data"."new_customers") T2
UNION
SELECT 3, 'cust_vw      ', NULL, "new_customers" FROM
	 (SELECT CAST(COUNT(DISTINCT c1) AS FLOAT) AS "new_customers" FROM
	  (SELECT DISTINCT "cid" AS c1 FROM "demo_data"."cust_vw") A,
	  (SELECT DISTINCT "cid" AS c2 FROM "demo_data"."new_customers") B
	WHERE c1 = c2) T2
ORDER BY 1;
);
disconnect from td;
run;


/*
we have 75 in common based on cid
lets check to see if they really are duplicate records
*/
proc sql;
connect using td_demo as td;
execute (create table demo_data.dupe_customers as 
(select 'd'||nc.cid as uid,nc.* from demo_data.new_customers as nc 
inner join 
demo_data.cust_vw as c
on nc.cid=c.cid
union all
select 'o'|| c.cid as uid,c.* from demo_data.new_customers as nc 
inner join 
demo_data.cust_vw as c
on nc.cid=c.cid) with data) by td;
disconnect from td;
run;

proc sql;
select * from td_demo.dupe_customers;
run;

/* 
now we could visually inspect the rows between the table
but that is error prone especially when dealing with 
wide records, and/or lots of records
so instead we will use matchcode at 100% 
*/

/* 
we are only interested in this case on name and address matches
*/

/*
check for name matches
*/


proc sql;
connect using td_demo as td;
execute (
call sas_sysfnlib.dq_match
('Name', '100','demo_data.dupe_customers', 'Fullname',
 'uid','demo_data.dqmatch_name', 'ENUSA')) by td;
 
/* 
now check the address
*/
 
execute (
call sas_sysfnlib.dq_match
('Address', '100','demo_data.dupe_customers', 'streetaddress',
 'uid','demo_data.dqmatch_address', 'ENUSA')) by td;

 disconnect from td;
 
 run;
 
/* 
have a look at the raw data
*/

proc sql;
select * from td_demo.dqmatch_name;
run;

proc freq data=td_demo.dqmatch_name;
tables matchcode;
run;

proc freq data=td_demo.dqmatch_address;
tables matchcode;
run;

/* 
now combine the non-dupe new customers with existing customers
*/

proc sql;
create view td_demo.master_customer_list
as (select * from td_demo.cust_vw
union 
select * from td_demo.new_customers
) ;

run;

proc sql;
select count(*) from td_demo.master_customer_list;
run;


proc print data=td_demo.master_customer_list;
where cid between 12368 and 12378;
run;

/* 
we have some states that don't conform to the 2 letter abbreviation
and we don't have any gender info
*/

/* lets see how bad the states are */

proc freq data=td_demo.master_customer_list;
tables state;
run;

/* 
so lets standardise the state codes
*/
proc sql;
connect using td_demo as td;
execute (
          call sas_sysfnlib.dq_standardize(
          'State/Province (Abbreviation)',
          'demo_data.master_customer_list',
          'state',
          'cid',
          'demo_data.cust_state_std',
          'ENUSA')
        ) by td;
        
quit;

/*
did it work?
*/
proc freq data=td_demo.cust_state_std;
tables standardized;
run;

/*
now lets work out the gender information
*/

proc sql;
connect using td_demo as td;
execute (
          call sas_sysfnlib.dq_gender(
          'Name',
          'demo_data.master_customer_list',
          'fullname',
          'cid',
          'demo_data.cust_gend',
          'ENUSA')
        ) by td;
        
quit;

/*

look at the frequency of the results
we have U for undetermined due to possible non-Anglo names
or gender neutral names like Lindsey

*/

proc freq data=td_demo.cust_gend;
tables gender;
run;


/*
now lets look at the transaction informatio
*/

proc sql;
select count(*) from td_demo.&txn_tbl;
run;

/* 3.6B rows in 12m*/

proc print data=td_demo.&txn_tbl;
where txn_date between '12Dec2018'd and '14Dec2018'd and custid between 12368 and 12370;
run;

/*
now lets roll this up to one row per customer per day
Probably won't run this during demo as it takes ~5 minutes
execute.
Don't drop the table, just start from next step

proc sql;
connect to teradata (server=barbera user=sasdemo 
password='{SAS002}835DA5352D5AE01B196D396B1920462032A1731E' mode=teradata);
execute (create table demo_data.txn_pvt as ( 
select * from demo_data.&txn_tbl pivot( sum(txn_count) as txn_c, sum(txn_amt) as txn_a
for channel in (
'X' as X,
'T' as T,
'F' as F,
'B' as B,
'C' as C,
'D' as D,
'A' as A,
'J' as J,
'Z' as Z)

) TMP) with data) by teradata;
disconnect from teradata;
run;



now lets extract the month from the txn date column
*/

proc print data=td_demo.txn_pvt (obs=100);
run;


proc sql;
insert into td_demo.txn_pvt_mnth
select 
custid ,
month(txn_date),
      X_txn_c ,
      X_txn_a ,
      T_txn_c ,
      T_txn_a ,
      F_txn_c ,
      F_txn_a ,
      B_txn_c ,
      B_txn_a ,
      C_txn_c ,
      C_txn_a ,
      D_txn_c ,
      D_txn_a ,
      A_txn_c ,
      A_txn_a ,
      J_txn_c ,
      J_txn_a ,
      Z_txn_c ,
      Z_txn_a 
from td_demo.txn_pvt;
run;
 
 
/*
now let roll up to customer level
and calculate the totals of the counts and amounts
by month
so end up with 1M rows
*/
     
proc ds2 ds2accel=yes ;

  /* thread program defines the parallel logic to run on each Teradata AMP */
  thread work.p_thread / overwrite=yes;
	vararray double TX_c[12];   /* create arrays to hold the pivoted data*/
	vararray double TT_c[12];
    vararray double TF_c[12];
    vararray double TB_c[12];
    vararray double TC_c[12];
    vararray double TD_c[12];
    vararray double TA_c[12];
    vararray double TJ_c[12];
    vararray double TZ_c[12];
	vararray double TX_a[12];   
	vararray double TT_a[12];
    vararray double TF_a[12];
    vararray double TB_a[12];
    vararray double TC_a[12];
    vararray double TD_a[12];
    vararray double TA_a[12];
    vararray double TJ_a[12];
    vararray double TZ_a[12];    
    
	dcl  integer custid;            /* this is the group by variable id */
	
	keep custid  TX_c1-TX_c12 TT_c1-TT_c12 TF_c1-TF_c12 TB_c1-TB_c12 TC_c1-TC_c12 
	             TD_c1-TD_c12 TA_c1-TA_c12 TJ_c1-TJ_c12 TZ_c1-TZ_c12
	             TX_a1-TX_a12 TT_a1-TT_a12 TF_a1-TF_a12 TB_a1-TB_a12 TC_a1-TC_a12 
	             TD_a1-TD_a12 TA_a1-TA_a12 TJ_a1-TJ_a12 TZ_a1-TZ_a12; 
	retain TX_c1-TX_c12 TT_c1-TT_c12 TF_c1-TF_c12 TB_c1-TB_c12 TC_c1-TC_c12 
	             TD_c1-TD_c12 TA_c1-TA_c12 TJ_c1-TJ_c12 TZ_c1-TZ_c12
	             TX_a1-TX_a12 TT_a1-TT_a12 TF_a1-TF_a12 TB_a1-TB_a12 TC_a1-TC_a12 
	             TD_a1-TD_a12 TA_a1-TA_a12 TJ_a1-TJ_a12 TZ_a1-TZ_a12; 

	
	method clear_arrays();      /* zero out the arrays */
      dcl  float i; 
      do i=1 to 12 ; 
     	TX_c[i] = 0;  
     	TT_c[i] = 0;
        TF_c[i] = 0;
        TB_c[i] = 0;
        TC_c[i] = 0; 
  	    TD_c[i] = 0;
  	    TA_c[i] = 0;
  	    TJ_c[i] = 0;
  	    TZ_c[i] = 0;
    	TX_a[i] = 0;  
     	TT_a[i] = 0;
        TF_a[i] = 0;
        TB_a[i] = 0;
        TC_a[i] = 0; 
  	    TD_a[i] = 0;
  	    TA_a[i] = 0;
  	    TJ_a[i] = 0;
  	    TZ_a[i] = 0; 	    
  	  end; 
	end;

	method run(); 
  	  set td_demo.txn_pvt_mnth;    /* read data in from txn_pvt_mnth table in TD */ 
      by custid;              /* the role up level */
  	  if first.custid then    /* for each new id clear out the arrays as these are reused */
        clear_arrays(); 
        TX_c[mnth]=X_txn_c+TX_c[mnth];  /* for each month create the totals */
		TT_c[mnth]=T_txn_c+TT_c[mnth];
		TF_c[mnth]=F_txn_c+TF_c[mnth];
		TB_c[mnth]=B_txn_c+TB_c[mnth];
		TC_c[mnth]=C_txn_c+TC_c[mnth];
		TD_c[mnth]=D_txn_c+TD_c[mnth];
		TA_c[mnth]=A_txn_c+TA_c[mnth];
		TJ_c[mnth]=J_txn_c+TJ_c[mnth];
		TZ_c[mnth]=Z_txn_c+TZ_c[mnth];
        TX_a[mnth]=X_txn_a+TX_a[mnth];  
		TT_a[mnth]=T_txn_a+TT_a[mnth];
		TF_a[mnth]=F_txn_a+TF_a[mnth];
		TB_a[mnth]=B_txn_a+TB_a[mnth];
		TC_a[mnth]=C_txn_a+TC_a[mnth];
		TD_a[mnth]=D_txn_a+TD_a[mnth];
		TA_a[mnth]=A_txn_a+TA_a[mnth];
		TJ_a[mnth]=J_txn_a+TJ_a[mnth];
		TZ_a[mnth]=Z_txn_a+TZ_a[mnth];		
	if last.custid then              /* then write out the results */ 
        output; 	
      
    end;
    
  endthread;
  run;

  /* Execute the DS2 we wrote above */
  data td_demo.txn_pvt_cust;         /* results are going into a teradata table*/
    dcl thread p_thread p; /* instance of the thread */
    method run();          /* call the run method we created above */
      set from p;
      output;
    end;
  enddata;

run;
quit;

proc print data=td_demo.txn_pvt_cust;
where custid between 12368 and 12378;
run;

/*
put it all together
*/
proc sql;
create view td_demo.ads_prelim
as 
(select 
    custid,
    Title_,
    fullname,
    gender,
    StreetAddress,
    City,
    standardized as State,
    ZipCode,
    Country,
    EmailAddress,
    TelephoneNumber,
    Birthday,
    CCType,
    TX_c1,
    TX_c2,
    TX_c3,
    TX_c4,
    TX_c5,
    TX_c6,
    TX_c7,
    TX_c8,
    TX_c9,
    TX_c10,
    TX_c11,
    TX_c12,
    TX_a1,
    TX_a2,
    TX_a3,
    TX_a4,
    TX_a5,
    TX_a6,
    TX_a7,
    TX_a8,
    TX_a9,
    TX_a10,
    TX_a11,
    TX_a12,
    TT_c1,
    TT_c2,
    TT_c3,
    TT_c4,
    TT_c5,
    TT_c6,
    TT_c7,
    TT_c8,
    TT_c9,
    TT_c10,
    TT_c11,
    TT_c12,    
    TT_a1,
    TT_a2,
    TT_a3,
    TT_a4,
    TT_a5,
    TT_a6,
    TT_a7,
    TT_a8,
    TT_a9,
    TT_a10,
    TT_a11,
    TT_a12,
    TF_c1,
    TF_c2,
    TF_c3,
    TF_c4,
    TF_c5,
    TF_c6,
    TF_c7,
    TF_c8,
    TF_c9,
    TF_c10,
    TF_c11,
    TF_c12,
    TF_a1,
    TF_a2,
    TF_a3,
    TF_a4,
    TF_a5,
    TF_a6,
    TF_a7,
    TF_a8,
    TF_a9,
    TF_a10,
    TF_a11,
    TF_a12,
    TB_c1,
    TB_c2,
    TB_c3,
    TB_c4,
    TB_c5,
    TB_c6,
    TB_c7,
    TB_c8,
    TB_c9,
    TB_c10,
    TB_c11,
    TB_c12,
    TB_a1,
    TB_a2,
    TB_a3,
    TB_a4,
    TB_a5,
    TB_a6,
    TB_a7,
    TB_a8,
    TB_a9,
    TB_a10,
    TB_a11,
    TB_a12,
    TC_c1,
    TC_c2,
    TC_c3,
    TC_c4,
    TC_c5,
    TC_c6,
    TC_c7,
    TC_c8,
    TC_c9,
    TC_c10,
    TC_c11,
    TC_c12,
    TC_a1,
    TC_a2,
    TC_a3,
    TC_a4,
    TC_a5,
    TC_a6,
    TC_a7,
    TC_a8,
    TC_a9,
    TC_a10,
    TC_a11,
    TC_a12,
    TD_c1,
    TD_c2,
    TD_c3,
    TD_c4,
    TD_c5,
    TD_c6,
    TD_c7,
    TD_c8,
    TD_c9,
    TD_c10,
    TD_c11,
    TD_c12,
    TD_a1,
    TD_a2,
    TD_a3,
    TD_a4,
    TD_a5,
    TD_a6,
    TD_a7,
    TD_a8,
    TD_a9,
    TD_a10,
    TD_a11,
    TD_a12,
    TA_c1,
    TA_c2,
    TA_c3,
    TA_c4,
    TA_c5,
    TA_c6,
    TA_c7,
    TA_c8,
    TA_c9,
    TA_c10,
    TA_c11,
    TA_c12,    
    TA_a1,
    TA_a2,
    TA_a3,
    TA_a4,
    TA_a5,
    TA_a6,
    TA_a7,
    TA_a8,
    TA_a9,
    TA_a10,
    TA_a11,
    TA_a12,
    TJ_c1,
    TJ_c2,
    TJ_c3,
    TJ_c4,
    TJ_c5,
    TJ_c6,
    TJ_c7,
    TJ_c8,
    TJ_c9,
    TJ_c10,
    TJ_c11,
    TJ_c12,
    TJ_a1,
    TJ_a2,
    TJ_a3,
    TJ_a4,
    TJ_a5,
    TJ_a6,
    TJ_a7,
    TJ_a8,
    TJ_a9,
    TJ_a10,
    TJ_a11,
    TJ_a12,
    TZ_c1,
    TZ_c2,
    TZ_c3,
    TZ_c4,
    TZ_c5,
    TZ_c6,
    TZ_c7,
    TZ_c8,
    TZ_c9,
    TZ_c10,
    TZ_c11,
    TZ_c12,
    TZ_a1,
    TZ_a2,
    TZ_a3,
    TZ_a4,
    TZ_a5,
    TZ_a6,
    TZ_a7,
    TZ_a8,
    TZ_a9,
    TZ_a10,
    TZ_a11,
    TZ_a12
from td_demo.txn_pvt_cust as tpc
inner join td_demo.master_customer_list as mcl
on tpc.custid=mcl.cid
inner join td_demo.cust_gend as cg
on mcl.cid = cg._PK_
inner join td_demo.cust_state_std as cgs
on mcl.cid = cgs._PK_);
run;


proc print data=td_demo.ads_prelim;
where custid between 12368 and 12378;
run;

/* 
define a format
*/

proc format ;
value txn_amt_band
0-1000 = 'low'
1001-20000 = 'medium'
20001-100000 = 'high'
other='extreme';
run;
    
/*needed for format publish macro */
%let indconn=server=barbera user=sasdemo password='{SAS002}835DA5352D5AE01B196D396B1920462032A1731E' database=demo_data;

/* now publish this format to the database */

/*initialise the format publishing system*/
%indtdpf;

/*now send the formats to the DB as VDFs*/
%indtd_publish_formats (fmtcat=work, 
database=demo_data, 
fmttable=sas_formats, 
action=replace, 
mode=protected);

/*use this format in a proc freq
notice in the log we see the SQL
the format has been written as SQL in the where clause
as a case statement
This is faster that having to call a VDF.
If the Access engine is unable to rewrite the SQL to
accomodate the format, it will call the sas_put VDF */

proc freq data=td_demo.ads_prelim;
format TX_a1-TX_a12 txn_amt_band.;
tables TX_a1-TX_a12 * gender;
run;

proc means data=td_demo.ads_prelim;
class state;
var TZ_a1-TZ_a12;
run;

/*
lets see if there is any significant correlation
between the amounts over the last 3 months
*/
proc corr data=td_demo.ads_prelim;
var TX_a9-TX_a12 TT_a9-TT_a12 TF_a9-TF_a12  
    TC_a9-TC_a12 TD_a9-TD_a12 TA_a9-TA_a12 TJ_a9-TJ_a12
    TZ_a9-TZ_a12;
	
run;

/* when using EP, indconn MUST have database defined, even if we overwrite it later*/

%let indconn= server=barbera user=sasdemo password='{SAS002}835DA5352D5AE01B196D396B1920462032A1731E' database=demo_data;

/* publish SA code */
%indtdpm;

%indtd_create_modeltable(
database=demo_data,
modeltable=clustering_models,
action=replace);


%indtd_publish_model (
dir=/data/demo2/sasdemo,
modelname=MasterCustomers,
modeltable=clustering_models,
action=replace,
mechanism=EP);

proc sql noerrorstop;
connect to teradata (&indconn mode=teradata);
execute (
call sas_sysfnlib.sas_score_ep 
                       ( 'MODELTABLE=demo_data.clustering_models',
                         'MODELNAME=MasterCustomers',
                         'INQUERY=demo_data.ads_prelim',
                         'OUTTABLE=demo_data.master_customer_clustered',
                         'OUTKEY=custid',
                         'OPTIONS=VOLATILE=NO;UNIQUE=YES;DIRECT=YES;'
                        )
          ) by teradata;
          disconnect from teradata;
quit;
 
 proc sql;
 select *
 from td_demo.master_customer_clustered
 where custid between 12368 and 12378;
 run;
 
proc freq data=td_demo.master_customer_clustered;
tables _CLUSTER_ID_;
run;

proc means data=td_demo.master_customer_clustered;
class _CLUSTER_ID_;
run;


```
